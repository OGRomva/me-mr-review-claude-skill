#!/usr/bin/env bash
# Постановка задачи из GanttFlow по ключу (STR-N): описание, статус, исполнители, родитель/связанные, чеклист, комментарии.
# Креды — из rbw (запись по URI), пароль не попадает ни в argv, ни в вывод.
# Использование: gantt-task.sh STR-N
#   GANTT_URL       (по умолчанию http://10.13.35.2:3100)
#   GANTT_RBW_ENTRY запись в rbw: имя/URI/UUID (по умолчанию 10.13.35.2)
set -euo pipefail
URL="${GANTT_URL:-http://10.13.35.2:3100}"
ENTRY="${GANTT_RBW_ENTRY:-10.13.35.2}"
key=$(tr a-z A-Z <<<"${1:?нужен ключ задачи, например STR-1026}")

dir="${XDG_RUNTIME_DIR:-/tmp}/mr-review"; mkdir -p "$dir"; chmod 700 "$dir"
jar="$dir/gantt.cookies"; boot="$dir/gantt-bootstrap.json"
touch "$jar"; chmod 600 "$jar"
CURL=(curl -sS -m 30 -b "$jar" -c "$jar" -H 'Content-Type: application/json')

login() {
  rbw unlocked >/dev/null 2>&1 || rbw unlock >/dev/null || { echo "gantt-task: rbw заблокирован" >&2; exit 2; }
  rbw get --raw "$ENTRY" \
    | jq -c '{login: .data.username, password: .data.password}' \
    | "${CURL[@]}" -o /dev/null -w '%{http_code}' -X POST --data @- "$URL/api/auth/login" \
    | grep -q '^2' || { echo "gantt-task: логин не удался (запись rbw: $ENTRY)" >&2; exit 2; }
}

code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$URL/api/auth/me")
[[ "$code" == 2* ]] || login

# bootstrap ~8 МБ — кешируем на 10 минут
if [ ! -s "$boot" ] || [ -n "$(find "$boot" -mmin +10)" ]; then
  "${CURL[@]}" "$URL/api/data/bootstrap" > "$boot.tmp" && jq -e .tasks "$boot.tmp" >/dev/null \
    && mv "$boot.tmp" "$boot" || { rm -f "$boot.tmp"; echo "gantt-task: bootstrap не получен" >&2; exit 2; }
fi

id=$(jq -r --arg k "$key" '.tasks[] | select(.taskKey == $k) | .id' "$boot" | head -1)
[ -n "$id" ] || { echo "gantt-task: задача $key не найдена" >&2; exit 1; }

comments=$("${CURL[@]}" "$URL/api/data/tasks/$id/comments")
checklist=$("${CURL[@]}" "$URL/api/data/tasks/$id/checklist")

jq --arg id "$id" --argjson c "$comments" --argjson cl "$checklist" '
  (.employees | map({(.id): .name}) | add) as $emp
  | (.tasks | map({(.id): .}) | add) as $t
  | $t[$id] as $x
  | def brief($i): if $i then $t[$i] | {taskKey, name, status: .kanbanColumnName, desc} else null end;
  {
    taskKey: $x.taskKey, name: $x.name, status: $x.kanbanColumnName, priority: $x.priority,
    category: $x.category, team: $x.team, start: $x.start, end: $x.end,
    assignees: [($x.assignees // [$x.assignee])[] | $emp[.] // .],
    desc: $x.desc,
    parent: brief($x.parentTaskId), testTask: brief($x.testTaskId), uiTask: brief($x.uiTaskId),
    subtasks: [.tasks[] | select(.parentTaskId == $id) | {taskKey, name, status: .kanbanColumnName}],
    checklist: [$cl[] | {text, done}],
    comments: [$c[] | {at, author, body}]
  }' "$boot"
