# WORKFLOW — ветки, MR и CI (PEAK HOUR 97)

> Репозиторий: `admin/Game-JAM` на `https://git.194-146-38-78.sslip.io`.
> Участники: `admin` (владелец), `Nikita`, `Artem`, `Micho`.
> Коротко: **разработчики работают только в `dev-<name>` и открывают MR в
> `dev`; `main` — прод, туда пишет и мержит только `admin`.**

## 1. Модель веток

| Ветка | Назначение | Кто пишет / мержит |
| --- | --- | --- |
| `main` | Прод. Стабильные сборки, релиз на itch.io. | Только `admin` |
| `dev` | Интеграция. Сюда вливаются все MR. | MR из `dev-<name>`, мержит `admin` |
| `dev-nikita` | Личная ветка Nikita | Nikita |
| `dev-artem` | Личная ветка Artem | Artem |
| `dev-micho` | Личная ветка Micho | Micho |

> **Почему дефис, а не слэш.** Git не разрешает одновременно существовать
> `refs/heads/dev` и `refs/heads/dev/nikita` (directory/file-конфликт refs);
> на сервере Gitea будет та же ошибка при push. Поэтому личные ветки —
> `dev-nikita`, `dev-artem`, `dev-micho`.

Правила:

- Прямой push в `main` и `dev` запрещён всем, кроме `admin` (branch
  protection).
- Один MR — одна задача/фича. Ветка живёт до мержа, потом удаляется.
- `dev-<name>` — долгоживущие личные ветки: перед новой задачей подтяните `dev`.
- Force-push разрешён только `admin` (и только для `admin`-веток).

## 2. Flow разработчика

```bash
# 1. Клон (один раз)
git clone https://git.194-146-38-78.sslip.io/admin/Game-JAM.git
cd Game-JAM

# 2. Свежий dev и личная ветка
git checkout dev
git pull --ff-only origin dev
git checkout -B dev-nikita origin/dev   # или dev-artem, dev-micho

# 3. Работа: коммиты маленькими порциями
git add -A
git commit -m "feat(hour): ..."

# 4. Push только своей ветки
git push -u origin dev-nikita

# 5. Открыть MR: dev-nikita -> dev (Gitea UI)
```

После открытия MR автоматически:

1. **CI** (`.gitea/workflows/ci.yml`) — импорт проекта, все headless-тесты
   (`scripts/run_all_tests.sh`), smoke-запуск `--quit`.
2. **OpenCode review** (`.gitea/workflows/review.yml`) — бот читает diff MR,
   сверяет с `docs/GDD.md` и `docs/DECISIONS.md` и публикует комментарий
   `## 🤖 OpenCode review` с разделами Blockers / High / Medium / Test gaps /
   Verdict. Бот **не** approves и **не** мержит.

Дальше MR смотрит `admin`. Мерж — только после зелёного CI и разобранных
блокеров ревью.

Чего делать нельзя:

- пушить в `main` или `dev` напрямую;
- мержить собственный MR (это делает `admin`);
- коммитить секреты, `.env`, `export_credentials.cfg`;
- тащить в MR несвязанные правки и сгенерированные файлы.

## 3. Flow администратора

1. Проверить MR: дифф, CI, комментарий OpenCode.
2. Прогнать локально при сомнениях:
   ```bash
   bash scripts/run_all_tests.sh
   ```
3. Смержить `dev-<name>` → `dev` (Merge / Squash — на выбор admin; для
   истории джема допустим squash).
4. Релиз `dev` → `main`: только `admin`, после полного прогона тестов и
   ручного smoke на целевой сборке.
5. Тег/сборка — по `docs/build.md`.

## 4. Branch protection

Настраивается скриптом (идемпотентно):

```bash
GITEA_TOKEN=... REVIEWER_TOKEN=... bash scripts/setup_gitea.sh
```

`REVIEWER_TOKEN` — отдельный бот-токен для секрета Actions; если он не
передан, скрипт не трогает уже созданный секрет (чтобы не перезаписать его
админским токеном).

Для `main` и `dev`:

- `enable_push=true`, `enable_push_whitelist=true`,
  `push_whitelist_usernames=["admin"]`;
- `enable_merge_whitelist=true`, `merge_whitelist_usernames=["admin"]`;
- `enable_force_push=true`, `enable_force_push_allowlist=true`,
  `force_push_allowlist_usernames=["admin"]`;
- `required_approvals=0` — формальные approve не блокируют мерж (решение
  принимает admin по CI + ревью-боту);
- `enable_status_check=false` — статус-чек CI **не** является техническим
  блокером мержа; зелёный CI обязателен по процессу. При желании можно
  включить позже (тогда Gitea будет требовать успешный job `tests`);
- `block_admin_merge_override=false` — admin может смержить в обход, если
  CI сломан по инфраструктурной причине.

## 5. CI и runner

Оба workflow используют `runs-on: host` — self-hosted runner на машине
разработки/сборки с label `host`.

Runner должен уметь:

- запускать Godot:
  `/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64`
  (в CI пробрасывается через `env: GODOT_BIN`);
- иметь `python3`, `curl`, `timeout` (coreutils);
- иметь `opencode` в `PATH` (для review.yml); иначе скрипт возьмёт
  `/home/eq/.opencode/bin/opencode`;
- писать в `/tmp/opencode` (туда сохраняется `review_<PR>.md`).

Секрет **`REVIEWER_TOKEN`** создаётся тем же `scripts/setup_gitea.sh`
(`PUT /actions/secrets/REVIEWER_TOKEN`; имя `GITEA_TOKEN` Gitea запрещает —
префикс зарезервирован). Workflow разворачивает его в env-переменную
`GITEA_TOKEN`, которую читает `scripts/review_mr.sh`. Токен нужен
review-боту для чтения
diff и публикации комментария. Если инстанс ожидает base64 в поле `data`,
скрипт автоматически повторяет запрос с base64.

## 6. Локальные проверки перед push

```bash
# все headless-тесты + parse check
bash scripts/run_all_tests.sh

# проверить синтаксис скриптов
bash -n scripts/run_all_tests.sh
bash -n scripts/review_mr.sh
bash -n scripts/setup_gitea.sh

# посмотреть ревью-бота без публикации (нужен реальный MR)
DRY_RUN=1 GITEA_TOKEN=... GITHUB_EVENT_PATH=/tmp/event.json \
  bash scripts/review_mr.sh
```

## 7. Типовые проблемы

- **CI «ждёт runner»** — runner не запущен или у него нет label `host`.
- **`review.yml` упал** — проверьте secret `REVIEWER_TOKEN` и доступность
  `opencode`; бот оставит в MR комментарий `OpenCode review failed: ...`.
- **Тест упал только в CI** — смотрите `build/test-logs/` (артефакты
  провалов складываются туда при `CI=true`); чаще всего это разный
  `XDG_DATA_HOME` или отсутствующий импорт ассетов.
- **ObjectDB instances leaked** — безвредный шум Godot при выходе, тест
  считается пройденным, если нет `SCRIPT ERROR`/`FAIL`.
- **Нужно срочно поправить прод** — только `admin`, через `dev` или
  hotfix-ветку `dev-<name>` с последующим мержем в `main`.
