#!/usr/bin/env bash
# Дамп MR в каталог прогона: mr.json, discussions.json, commits.json, versions.json, diff.patch, meta.json.
# Рабочую копию не трогает: только git fetch и чтение объектов.
# Использование: mr-fetch.sh [<url> | <group/project>!<iid> | <project>!<iid> | !<iid> | <iid>]
#   без аргумента — MR текущей ветки в текущем репозитории.
set -euo pipefail

HOST="${MR_REVIEW_HOST:-git.stormapi.su}"
GROUP="${MR_REVIEW_GROUP:-jungerschaft}"
WORK_ROOT="${MR_REVIEW_WORK_ROOT:-$HOME/Рабочий стол/work}"
CACHE="${MR_REVIEW_CACHE:-$HOME/.cache/mr-review}"

die() { echo "mr-fetch: $*" >&2; exit 1; }
api() { glab api --hostname "$HOST" "$@"; }
enc() { jq -rn --arg s "$1" '$s|@uri'; }

# project path из origin текущего репозитория
current_project() {
  git remote get-url origin 2>/dev/null \
    | sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##'
}

ref="${1:-}"
project="" iid=""
case "$ref" in
  http*://*/-/merge_requests/*)
    project=$(sed -E 's#^https?://[^/]+/(.+)/-/merge_requests/.*#\1#' <<<"$ref")
    iid=$(sed -E 's#.*/-/merge_requests/([0-9]+).*#\1#' <<<"$ref") ;;
  *!*)
    project="${ref%%!*}"; iid="${ref##*!}"
    [ -z "$project" ] && project=$(current_project)
    [[ "$project" == */* ]] || project="$GROUP/$project" ;;
  [0-9]*)
    project=$(current_project); iid="$ref" ;;
  "")
    project=$(current_project)
    [ -n "$project" ] || die "не в git-репозитории и MR не указан"
    branch=$(git branch --show-current)
    iid=$(api "projects/$(enc "$project")/merge_requests?state=opened&source_branch=$(enc "$branch")" | jq -r '.[0].iid // empty')
    [ -n "$iid" ] || die "нет открытого MR для ветки $branch в $project" ;;
  *) die "не понял ссылку на MR: $ref" ;;
esac
[[ "$iid" =~ ^[0-9]+$ ]] || die "некорректный iid: $iid"
[ -n "$project" ] || die "не удалось определить проект"

P=$(enc "$project")
run="$CACHE/$(tr '/' '_' <<<"$project")-$iid"
mkdir -p "$run"

api "projects/$P/merge_requests/$iid" > "$run/mr.json"
api --paginate "projects/$P/merge_requests/$iid/discussions?per_page=100" | jq -s 'add // []' > "$run/discussions.json"
api --paginate "projects/$P/merge_requests/$iid/commits?per_page=100" | jq -s 'add // []' > "$run/commits.json"
api "projects/$P/merge_requests/$iid/versions" > "$run/versions.json"

src=$(jq -r .source_branch "$run/mr.json")
tgt=$(jq -r .target_branch "$run/mr.json")
base=$(jq -r .diff_refs.base_sha "$run/mr.json")
start=$(jq -r .diff_refs.start_sha "$run/mr.json")
head=$(jq -r .diff_refs.head_sha "$run/mr.json")

# локальный клон: ищем по origin, иначе blobless-клон в кеш
repo=""
while IFS= read -r gitdir; do
  d=$(dirname "$gitdir")
  url=$(git -C "$d" remote get-url origin 2>/dev/null || true)
  if [[ "$(sed -E 's#\.git$##' <<<"$url")" == *"/$project" || "$url" == *":$project.git" ]]; then repo="$d"; break; fi
done < <(find "$WORK_ROOT" -maxdepth 4 -name .git 2>/dev/null | sort)
if [ -z "$repo" ]; then
  repo="$CACHE/repos/$project"
  [ -d "$repo/.git" ] || git clone --quiet --filter=blob:none --no-checkout "https://$HOST/$project.git" "$repo"
fi

git -C "$repo" fetch --quiet origin "$tgt" "$src" 2>/dev/null \
  || git -C "$repo" fetch --quiet origin "$tgt" "refs/merge-requests/$iid/head" \
  || die "git fetch не удался в $repo"
git -C "$repo" cat-file -e "$head^{commit}" 2>/dev/null \
  || git -C "$repo" fetch --quiet origin "refs/merge-requests/$iid/head" \
  || die "нет коммита $head в $repo"

git -C "$repo" diff "$start" "$head" > "$run/diff.patch"
git -C "$repo" diff --stat "$start" "$head" > "$run/diff.stat"

task=$(jq -r '"\(.title) \(.source_branch) \(.description // "")"' "$run/mr.json" | grep -oiE 'STR-[0-9]+' | head -1 | tr a-z A-Z || true)

jq -n --arg run "$run" --arg repo "$repo" --arg project "$project" --arg task "$task" \
  --slurpfile mr "$run/mr.json" --slurpfile d "$run/discussions.json" '
  $mr[0] as $m | {
    run_dir: $run, repo: $repo, project: $project, project_id: $m.project_id, iid: $m.iid,
    title: $m.title, author: $m.author.username, web_url: $m.web_url, state: $m.state,
    source_branch: $m.source_branch, target_branch: $m.target_branch,
    diff_refs: $m.diff_refs, task: (if $task == "" then null else $task end),
    threads: ($d[0] | map(select(.individual_note | not)) | length),
    unresolved: ($d[0] | map(select((.individual_note | not) and (.notes[0].resolvable) and (.notes[0].resolved | not))) | length),
    notes: ($d[0] | map(select(.individual_note and (.notes[0].system | not))) | length)
  }' | tee "$run/meta.json"
