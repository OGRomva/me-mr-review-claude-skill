# mr-review — скилл Claude Code

Ревью GitLab MR (git.stormapi.su): правильность решения против постановки из GanttFlow,
чистота кода, актуальность swagger, проверка прошлых тредов. Выдаёт нумерованный список
замечаний и публикует отобранные через `glab`. Вызов: `/mr-review`.

## Установка

```bash
git clone git@github.com:OGRomva/me-mr-review-claude-skill.git ~/.claude/skills/mr-review
```

Обновление: `git -C ~/.claude/skills/mr-review pull`.

## Зависимости

- `git`, `curl`, `jq`, `python3`
- `glab`, авторизованный на git.stormapi.su: `glab auth login --hostname git.stormapi.su`
- `rbw` (клиент Bitwarden) с записью для GanttFlow — оттуда `gantt-task.sh` берёт логин/пароль

## Переменные окружения (необязательные)

| Переменная            | По умолчанию                 | Назначение                                   |
| --------------------- | ---------------------------- | -------------------------------------------- |
| `MR_REVIEW_HOST`      | `git.stormapi.su`            | хост GitLab                                  |
| `MR_REVIEW_GROUP`     | `jungerschaft`               | группа по умолчанию для `project!iid`        |
| `MR_REVIEW_WORK_ROOT` | `$HOME/Рабочий стол/work`    | где искать локальные клоны проектов          |
| `MR_REVIEW_CACHE`     | `$HOME/.cache/mr-review`     | кеш клонов, если локального нет              |
| `GANTT_URL`           | `http://10.13.35.2:3100`     | адрес GanttFlow                              |
| `GANTT_RBW_ENTRY`     | `10.13.35.2`                 | запись в rbw (имя/URI/UUID)                  |
