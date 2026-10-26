#!/usr/bin/env bash
# Открытые MR во всех доступных проектах, связанные с задачей (STR-N в title/description).
# Использование: mr-related.sh STR-N
set -euo pipefail
HOST="${MR_REVIEW_HOST:-git.stormapi.su}"
key="${1:?нужен ключ задачи, например STR-1026}"
glab api --hostname "$HOST" --paginate "merge_requests?scope=all&state=opened&per_page=100&search=$key" \
  | jq -s --arg k "$key" 'add // [] | map(select(
      [.source_branch, .title, (.description // "")] | join(" ") | ascii_downcase
      | test(($k | ascii_downcase) + "(?![0-9])")))
    | map({ref: .references.full, title, source_branch, target_branch, author: .author.username, web_url})'
