#!/usr/bin/env python3
"""Публикация отобранных находок из findings.json в GitLab.

Использование:
  post-comments.py <findings.json> <ids> [--send]
    ids: "1,3,5-7" | "all" | "all-4,9" (все, кроме перечисленных)
  Без --send только печатает payload'ы (dry-run).

Находка: {id, project, iid, run_dir, head_sha, path?, new_line?, old_line?, body, posted?}
Строка в диффе → inline discussion с position; иначе → обычный note в MR.
Публикуется только body: без подписей и служебных пометок.
"""
import json, os, re, subprocess, sys, tempfile, urllib.parse

HOST = os.environ.get("MR_REVIEW_HOST", "git.stormapi.su")
FORBIDDEN = re.compile(r"claude|anthropic|generated with|co-authored-by|🤖", re.I)


def parse_ids(spec, all_ids):
    def expand(part):
        out = set()
        for tok in filter(None, part.split(",")):
            a, _, b = tok.partition("-")
            out |= set(range(int(a), int(b or a) + 1))
        return out
    spec = spec.replace(" ", "")
    if spec.startswith("all"):
        rest = spec[3:].lstrip("-")
        return sorted(set(all_ids) - expand(rest))
    return sorted(expand(spec))


def glab(path, method="GET", payload=None):
    cmd = ["glab", "api", "--hostname", HOST, "-X", method, path]
    tmp = None
    if payload is not None:
        tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump(payload, tmp, ensure_ascii=False)
        tmp.close()
        cmd += ["--input", tmp.name, "-H", "Content-Type: application/json"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    finally:
        if tmp:
            os.unlink(tmp.name)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or res.stdout.strip())
    return json.loads(res.stdout or "null")


def line_map(repo, start, head, path):
    """new_line → old_line (None для добавленных) и множество удалённых old_line."""
    diff = subprocess.run(["git", "-C", repo, "diff", start, head, "--", path],
                          capture_output=True, text=True).stdout
    new_to_old, removed = {}, set()
    o = n = 0
    for ln in diff.splitlines():
        m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", ln)
        if m:
            o, n = int(m[1]), int(m[2])
            continue
        if not o and not n:
            continue
        if ln.startswith("+") and not ln.startswith("+++"):
            new_to_old[n] = None; n += 1
        elif ln.startswith("-") and not ln.startswith("---"):
            removed.add(o); o += 1
        elif ln.startswith(" "):
            new_to_old[n] = o; o += 1; n += 1
    return new_to_old, removed


def build(f, mr):
    refs = mr["diff_refs"]
    body = f["body"].strip()
    path, new_line, old_line = f.get("path"), f.get("new_line"), f.get("old_line")
    if path and (new_line or old_line):
        meta = json.load(open(os.path.join(f["run_dir"], "meta.json")))
        n2o, removed = line_map(meta["repo"], refs["start_sha"], refs["head_sha"], path)
        pos = {"position_type": "text", "base_sha": refs["base_sha"], "start_sha": refs["start_sha"],
               "head_sha": refs["head_sha"], "old_path": f.get("old_path") or path, "new_path": path}
        if new_line and new_line in n2o:
            pos["new_line"] = new_line
            if n2o[new_line] is not None:
                pos["old_line"] = n2o[new_line]
            return "discussion", {"body": body, "position": pos}
        if old_line and old_line in removed:
            pos["old_line"] = old_line
            return "discussion", {"body": body, "position": pos}
        loc = f"`{path}:{new_line or old_line}`"
        return "note", {"body": f"{loc}\n\n{body}"}
    return "note", {"body": body}


def main():
    args = [a for a in sys.argv[1:] if a != "--send"]
    send = "--send" in sys.argv
    if len(args) != 2:
        sys.exit(__doc__)
    fpath, spec = args
    findings = json.load(open(fpath))
    by_id = {f["id"]: f for f in findings}
    ids = parse_ids(spec, by_id)
    missing = [i for i in ids if i not in by_id]
    if missing:
        sys.exit(f"нет находок с id {missing}")

    mrs = {}
    for i in ids:
        f = by_id[i]
        if f.get("posted"):
            print(f"#{i}: уже опубликовано → {f['posted']}"); continue
        if FORBIDDEN.search(f["body"]):
            print(f"#{i}: ПРОПУЩЕНО — в тексте подпись/упоминание ИИ"); continue
        key = (f["project"], f["iid"])
        proj = urllib.parse.quote(f["project"], safe="")
        if key not in mrs:
            mrs[key] = glab(f"projects/{proj}/merge_requests/{f['iid']}")
        mr = mrs[key]
        if f.get("head_sha") and f["head_sha"] != mr["diff_refs"]["head_sha"]:
            print(f"#{i}: ПРОПУЩЕНО — MR {f['project']}!{f['iid']} обновился после ревью "
                  f"({f['head_sha'][:8]} → {mr['diff_refs']['head_sha'][:8]}), перепроверь строку"); continue
        kind, payload = build(f, mr)
        endpoint = f"projects/{proj}/merge_requests/{f['iid']}/{'discussions' if kind == 'discussion' else 'notes'}"
        if not send:
            print(f"#{i}: [dry-run] POST {endpoint}\n{json.dumps(payload, ensure_ascii=False, indent=2)}\n")
            continue
        try:
            res = glab(endpoint, "POST", payload)
        except RuntimeError as e:
            if kind == "discussion":
                # GitLab не принял позицию — публикуем общей заметкой с указанием места
                payload = {"body": f"`{f['path']}:{f.get('new_line') or f.get('old_line')}`\n\n{payload['body']}"}
                endpoint = f"projects/{proj}/merge_requests/{f['iid']}/notes"
                print(f"#{i}: inline не принят ({e}), публикую заметкой")
                res, kind = glab(endpoint, "POST", payload), "note"
            else:
                print(f"#{i}: ОШИБКА {e}"); continue
        note_id = res["notes"][0]["id"] if kind == "discussion" else res["id"]
        f["posted"] = f"{mr['web_url']}#note_{note_id}"
        print(f"#{i}: {kind} → {f['posted']}")
        json.dump(findings, open(fpath, "w"), ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
