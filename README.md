# PEAK HOUR 97

> Час пик. Одна смена. Ни одного свободного места.

Ночной диспетчер узла файлового обмена, 1997 год. Принимайте пакеты,
раскладывайте файлы, собирайте запросы клиентов, держите канал и SLA — в
интерфейсе shareware-программы 90-х.

**Жанр:** менеджмент / тайм-менеджмент, retro UI.
**Платформа:** Godot **4.7.2** → **Web (HTML5, без threads)**, RU-only,
1280×720, мышь.
**Забег:** 9 игровых часов по 5 минут (≈45 минут) + подготовка между часами.

## Статус

Играбельный веб-прототип полного цикла: **меню → подготовка → час → итоги
часа → … → итоги забега**. Девять часов проходят на сидах `1`, `42`, `777`
без потери часов; сохранение работает между часами.

Реализовано:

- 4 типа файлов (текст, звук, фото, видео), буфер приёма, папки и секции.
- TCP-слоты и полоска соединения: три попадания по очереди.
- 4 атаки: мусор, DDoS, фишинг, шифровальщик.
- 9 апгрейдов магазина: слоты, буфер, таймеры, зона, канал, секции, поиск, щит.
- Пауза, настройки, итоги часа и забега, сохранение/продолжение.
- UI 90-х рисуется кодом; Handjet + Press Start 2P; 18 SFX + фоновый `hum`.
- Полный забег: 9 часов × 5 минут, победа или поражение по SLA.

Упрощено:

- Поиск по файлам: апгрейд «Поиск» покупается, но отдельного окна/фильтра
  поиска пока нет.
- Туториал: три подсказки-тоста в первом часе, без пошагового сценария.
- Сохранение в Web идёт через IndexedDB (`user://save.json`) — проверяйте
  продолжение после перезагрузки вкладки.

## Управление

| Действие | Ввод |
| --- | --- |
| Выбор, меню, перетаскивание | ЛКМ |
| Контекстное меню | ПКМ |
| Пакет из «Приёма» → папка; файл → карточка запроса | drag&drop |
| Мини-игра соединения: три попадания по очереди | ЛКМ или `Space` |
| Мини-игра подготовки: отправить | `Enter` или кнопка |
| Пауза | `Esc` |
| Панель соединения: отмена (слот свободен, запрос остаётся) | `Esc` |
| Мини-игра подготовки: `Esc` не закрывает окно (D10) | — |

## Запуск

Нужен Godot 4.7.2. В этом окружении:

```bash
GODOT=/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64

# один раз после клона: импорт шрифтов и темы
"$GODOT" --headless --path . --import

# игра
"$GODOT" --path .

# редактор
"$GODOT" -e --path .
```

## Сборка Web

```bash
mkdir -p build/web
"$GODOT" --headless --path . \
  --export-release "Web" build/web/index.html
```

Результат: `build/web/index.html`, `index.wasm`, `index.pck` и служебные
`.js`/`.png`. Пресет собран с `thread_support=false`, поэтому COOP/COEP не
нужны. Локальный просмотр — только по HTTP:

```bash
python3 -m http.server 8000 --directory build/web
# http://localhost:8000
```

Нужны export templates 4.7.2 (`web_nothreads_release.zip`).

## Тесты

```bash
"$GODOT" --headless --path . --script tests/run_tests.gd
"$GODOT" --headless --path . --script tests/test_fuzz.gd
"$GODOT" --headless --path . --script tests/test_full_playthrough.gd
"$GODOT" --headless --path . --script scripts/ui/ui_smoke.gd
```

Другие наборы: `test_hour`, `test_shop`, `test_slots`, `test_minigame`,
`test_audio`, `test_integration`, `test_attacks`, `test_controller`,
`test_main_prep`, `test_main_hour`, `test_main_interactions`,
`test_main_attacks`, `test_main_pause`.

Суммарно около **5 100 проверок, 0 провалов**, включая полный 9-часовой
прогон на трёх сидах. Подробности — в [AI_REPORT](AI_REPORT.md).

## Структура

```
peak-hour/
├─ project.godot              # 1280×720, GL Compatibility, автолоады
├─ export_presets.cfg         # Web (no threads)
├─ scenes/                    # Main + ui/modals/minigames
├─ scripts/
│  ├─ game_controller.gd      # цикл menu → prep → hour → results
│  ├─ autoload/               # Game, Data, Audio, Rng
│  ├─ core/                   # HourDirector, FileRegistry, SlotManager, Economy
│  ├─ entities/               # файлы, пакеты, запросы, папки, слоты
│  ├─ systems/                # атаки, магазин, сохранения
│  ├─ ui/                     # компоненты и модалки 90-х
│  └─ minigames/              # ConnectionGame, MiniGame
├─ data/                      # balance.json, strings_ru.json, names_ru.json
├─ art/fonts/                 # Handjet, Press Start 2P + OFL
├─ audio/                     # generate_sfx.py, sfx/, music/
├─ tests/                     # headless-наборы
├─ docs/                      # GDD, DECISIONS, screenshots, ITCH_PAGE
└─ build/                     # артефакты экспорта (gitignored)
```

## Требования

- Godot **4.7.2** (GL Compatibility).
- Для Web: export templates 4.7.2, `web_nothreads_release.zip`.
- Python 3 — только для пересборки SFX.
- Никаких секретов и внешних сервисов.

## Документация

- [GDD](docs/GDD.md) — правила и числа.
- [DECISIONS](docs/DECISIONS.md) — решения D01–D17.
- [AI_REPORT](AI_REPORT.md) — модели, приёмы и проверки.
- [ASSETS](ASSETS.md) — шрифты, звук, лицензии и воспроизведение.
- [IMPLEMENTATION](docs/IMPLEMENTATION.md) и [TEST_PLAN](docs/TEST_PLAN.md) —
  контракты и матрица тестов.
- [ITCH_PAGE](docs/ITCH_PAGE.md) — текст страницы itch.io.
- [screenshots](docs/screenshots/) — кадры меню, подготовки, часа и атак.

## Лицензии

Код — **MIT** ([LICENSE](LICENSE)). Шрифты — **SIL OFL 1.1**
(`art/fonts/OFL-*.txt`). UI и иконка — MIT. SFX и `hum.wav` — MIT/CC0,
сгенерированы `audio/generate_sfx.py`. Подробности — в [ASSETS.md](ASSETS.md).
