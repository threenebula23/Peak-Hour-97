# PEAK HOUR 97

> Час пик. Одна смена. Ни одного свободного места.

1997 год. Ночной диспетчер узла файлового обмена: принимайте пакеты,
раскладывайте файлы-полимино по папкам, собирайте контейнеры запросов,
проходите мини-игры и держите SLA. UI — «Kaleidos»: тёплая бумага, тонкие
контуры и бирюзовый акцент.

**Жанр:** менеджмент / тайм-менеджмент, retro UI.
**Платформа:** Godot **4.7.2** → **Web (HTML5, без threads)**, RU-only.
**Окно:** 1920×1080, логический viewport 1280×720, fractional scale.
**Забег:** 9 игровых часов по 5 минут (≈45 минут) + подготовка между часами.

## Статус v2.0

Играбельный веб-прототип полного цикла: **меню → подготовка → час → итоги
часа → … → итоги забега**. Актуальная спецификация — [GDD v2.0](docs/GDD.md),
решения — [DECISIONS](docs/DECISIONS.md) (D29–D44).

Реализовано:

- **9 часов**, старт **50 $**, **SLA 60/60** (кап растёт +35 за уровень
  `lot_sla` до 200), 1 слот (макс. 5), канал 10 (макс. 46), буфер 6 (макс. 12),
  таймер запроса 30 с (макс. 55), таймер пакета 20 с.
- **4 типа файлов-полимино:** текст 1, звук 2, фото 3, видео 4 клетки;
  поворот `R`/ПКМ во время drag; сетка папки 5×4 → 8×6.
- **Стол сортировки 4×6** в подготовке; файлы со стола нельзя прикрепить,
  на старте часа они автоматически возвращаются в папки (если места нет —
  час не начинается).
- **8 лотов магазина**; ровно 3 предложения, рероллы 40/80/120 (макс. 3 за
  подготовку), замок отдельного предложения. Магазин — с H2 и только в
  подготовке. Полное дерево — 13 100 $.
- **7 мини-игр отправки** (`dots`, `sound`, `wires`, `text`, `video`, `photo`,
  `maze`) и **4 мини-игры атак** (`junk`, `ddos`, `phishing`, `ransomware`);
  без таймеров, с экраном `q%`/вердикт и `ПРОДОЛЖИТЬ`.
- **Явная отправка** `ОТПРАВИТЬ` (автостарта нет) и переключатель **TCP/UDP**:
  TCP +15 % к выплате, UDP ×0.8 ко времени. Файлы расходуются при успешной
  отправке и сохраняются при отмене/таймауте.
- **20 атак за забег** (`0,1,1,2,2,3,3,4,4`), 4 вида, 4 ступени; атака — это
  мини-игра, которая ставит час на паузу. Щит «Заземление» гасит атаку
  автоматически (50 % награды, без штрафа).
- **Save VERSION 2**: позиции только в `folder.files`/`table`, метаданные в
  `files`; v1-сейвы мигрируют без потери файлов и без уменьшения сеток;
  офферы/рероллы/замки и стол сохраняются.
- Мета-награды после 3/5/9 часов, маскот **БАЙТ**, UI v2 «Kaleidos»,
  ambient машинного зала, VHS только в главном меню.

Ограничения:

- Туториал — маскот и несколько подсказок, без пошагового сценария.
- Сохранение в Web идёт через IndexedDB (`user://save.json`); проверяйте
  продолжение после перезагрузки вкладки.
- Средний расход магазина в симуляторе — **44,1 %** дерева (ниже старой
  цели 55–65 %); это известное ограничение баланса, а не «полный выкуп».
- Remote push ещё не выполнен; сборка для itch.io готовится локально.

## Управление

| Действие | Ввод |
| --- | --- |
| Выбор, меню, перетаскивание | ЛКМ |
| Контекстное меню | ПКМ |
| Поворот фигуры во время drag | `R` или ПКМ |
| Пакет из «Приёма» → папка | drag&drop |
| Файл из папки → карточка запроса | drag&drop |
| Файл ↔ стол сортировки | drag&drop |
| Отправка запроса | кнопка `ОТПРАВИТЬ` |
| TCP/UDP | переключатель на карточке запроса до отправки |
| Мини-игра: действие | ЛКМ / `Space` / стрелки (по игре) |
| Пропустить мини-игру | `ПРОПУСТИТЬ` + подтверждение |
| Результат мини-игры | `ПРОДОЛЖИТЬ` или `Esc` |
| Магазин: закрыть | `ЗАКРЫТЬ` или `Esc` |
| Пауза | `Esc` |

## Запуск

Нужен Godot **4.7.2**. Команды выполняются из корня репозитория; ниже
`GODOT` — путь к бинарю Godot.

```bash
# один раз после клона: импорт шрифтов и темы
"$GODOT" --headless --path . --import

# игра
"$GODOT" --path .

# редактор
"$GODOT" -e --path .
```

В Windows удобно задать путь один раз:

```powershell
$env:GODOT_BIN = "D:\Apps\godot\Godot_v4.7.2-stable_win64_console.exe"
& $env:GODOT_BIN --path .
```

## Сборка Web

```bash
mkdir -p build/web
"$GODOT" --headless --path . \
  --export-release "Web" build/web/index.html
```

Результат: `build/web/index.html`, `index.wasm`, `index.pck` и служебные
`.js`/`.png`. Пресет `thread_support=false`: COOP/COEP не нужны. Локальный
просмотр — только по HTTP:

```bash
python -m http.server 8000 --directory build/web
# http://localhost:8000
```

Нужны export templates 4.7.2 (`web_nothreads_release.zip`). Каталог шаблонов
должен называться `4.7.2.stable`.

## Тесты

Полный прогон — **25 тестовых наборов + parse-check (итого 26/26 PASS)**:

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File scripts/run_all_tests.ps1
```

```bash
# Linux / macOS
bash scripts/run_all_tests.sh
```

Windows-раннер сам ищет Godot (сначала `GODOT_BIN`, затем стандартный путь,
затем `godot4`/`godot` из `PATH`); путь можно передать явно:
`-GodotBin <path>`.

Точечно:

```bash
"$GODOT" --headless --path . --script tests/run_tests.gd
"$GODOT" --headless --path . --script tests/test_fuzz.gd
"$GODOT" --headless --path . --script tests/test_full_playthrough.gd
"$GODOT" --headless --path . --script scripts/ui/ui_smoke.gd
```

Баланс (240 сидов, отчёт `tests/SIM_BALANCE_REPORT.md`):

```bash
python tests/sim_balance.py
```

Фактический итог v2: **26/26 PASS** (25 наборов + parse-check), симулятор
завершается с кодом 0 и вердиктом `PASS`. Подробности — в [AI_REPORT](AI_REPORT.md).

## Структура

```
Game-JAM/
├─ project.godot              # 1920×1080 / 1280×720, GL Compatibility
├─ export_presets.cfg         # Web (no threads)
├─ scenes/                    # Main + UI/мини-игры
├─ scripts/
│  ├─ main.gd                 # UI, ввод, модалки, drag&drop
│  ├─ game_controller.gd      # цикл menu → prep → hour → results
│  ├─ run_all_tests.ps1/.sh   # полный headless-прогон
│  ├─ autoload/               # Game, Data, Audio, Rng, Ambient
│  ├─ core/                   # HourDirector, FileRegistry, SlotManager, Economy
│  ├─ entities/               # файлы, папки, секции, пакеты, запросы, слоты
│  ├─ systems/                # Shop, AttackDirector, SaveManager
│  ├─ ui/                     # Theme90, FileGrid, SortingTable, ShopModal, VHS
│  └─ minigames/              # MiniGame, factory, send/, attack/
├─ data/                      # balance.json, strings_ru.json, names_ru.json
├─ art/fonts/                 # Handjet, Press Start 2P + OFL
├─ audio/                     # sfx/, music/, amb/, generate_*py
├─ shaders/                   # vhs.gdshader (только главное меню)
├─ tests/                     # headless-наборы, sim_balance.py
├─ docs/                      # GDD, DECISIONS, UI_REFRESH, скриншоты
└─ build/                     # артефакты экспорта (gitignored)
```

## Требования

- Godot **4.7.2** (GL Compatibility).
- Для Web: export templates 4.7.2, `web_nothreads_release.zip`.
- Python 3 — для баланса и пересборки SFX/ambient.
- Никаких секретов и внешних сервисов.

## Документация

- [GDD](docs/GDD.md) — правила и числа v2.0.
- [DECISIONS](docs/DECISIONS.md) — решения D01–D44 (актуальны D29–D44).
- [AI_REPORT](AI_REPORT.md) — модели, приёмы и проверки.
- [ASSETS](ASSETS.md) — шрифты, звук, лицензии и воспроизведение.
- [UI_REFRESH](docs/UI_REFRESH.md) — UI v2 «Kaleidos».
- [IMPLEMENTATION](docs/IMPLEMENTATION.md) и [TEST_PLAN](docs/TEST_PLAN.md) —
  исторические контракты v1 и матрица тестов.
- [ITCH_PAGE](docs/ITCH_PAGE.md) — текст страницы itch.io.
- [screenshots](docs/screenshots/) — кадры меню, подготовки, часа и атак.

## Лицензии

Код — **MIT** ([LICENSE](LICENSE)). Шрифты — **SIL OFL 1.1**
(`art/fonts/OFL-*.txt`). UI и иконка — MIT. SFX и `hum.wav` — MIT/CC0,
сгенерированы `audio/generate_sfx.py`. Подробности — в [ASSETS.md](ASSETS.md).
