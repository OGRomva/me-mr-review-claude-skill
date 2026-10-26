# mr-review — скилл Claude Code

Ревью GitLab MR (git.stormapi.su): правильность решения против постановки из GanttFlow,
чистота кода, актуальность swagger, проверка прошлых тредов. Выдаёт нумерованный список
замечаний и публикует отобранные через `glab`. Вызов: `/mr-review`.

## Установка

В Claude Code:

```
/plugin marketplace add OGRomva/me-mr-review-claude-skill
/plugin install mr-review@me-mr-review
```

Обновление: `/plugin marketplace update me-mr-review`.

## Разработка

Правки — в клоне репозитория, скилл лежит в `skills/mr-review/`. После `git push` на всех устройствах:
`/plugin marketplace update me-mr-review`.

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
