# PEAK HOUR 97

> Час пик. Одна смена. Ни одного свободного места.

Ночной диспетчер узла файлового обмена, 1997 год. Принимайте пакеты,
раскладывайте файлы, собирайте запросы клиентов, держите канал и SLA — в
интерфейсе, вдохновлённом Kaleidos: тёплая бумага, тонкие контуры и
бирюзовый акцент.

**Жанр:** менеджмент / тайм-менеджмент, retro UI.
**Платформа:** Godot **4.7.2** → **Web (HTML5, без threads)**, RU-only.
**Окно:** 1600×900, логический viewport 1280×720, fractional scale.
**Забег:** 9 игровых часов по 5 минут (≈45 минут) + подготовка между часами.

## Статус v1.2

Играбельный веб-прототип полного цикла: **меню → подготовка → час → итоги
часа → … → итоги забега**. Девять часов проходят на сидах `1`, `42`, `777`
без потери часов; SLA после магазина — 200.

Реализовано:

- 4 типа файлов (text/sound/photo/video), буфер приёма, папки и секции.
- **10 апгрейдов** магазина, включая `SLA +24`; магазин открывается с часа 2
  и скрыт во время часа.
- TCP-слоты и полоска соединения: три попадания; промах закрывает панель
  без автоповтора.
- 4 атаки, но **час 1 проходит без атак**; junk/ddos — с часа 2,
  phishing — с 3, ransomware — с 4.
- **SLA 128 / 200** на старте; потеря пакета: text 2 / sound 4 / photo 8 /
  video 16.
- Мета-награды **постепенно по часам**: поиск после 3-го часа, щит после
  5-го, `complete_run` после 9-го; итоги показывают «ОТКРЫТО: …», прогресс
  живёт между забегами. `minigame_advanced` — резерв под будущий контент.
- Поиск по имени в текущей папке после открытия; заголовок «N ИЗ M ОБЪЕКТОВ».
- Автообновление папки/дерева, уникальные имена папок (`Имя`, `Имя 2`),
  удаление пустых папок, attached-галочки, скролл приёма до 8 пакетов.
- «Уничтожить содержимое» папки удаляет файлы с подтверждением и −5 SLA;
  пустая папка удаляется без штрафа.
- «Спокойный фон» — плоская бумага без dither; Esc на итогах забега ведёт
  в главное меню.
- UI v2 «Kaleidos», маскот **БАЙТ** и короткий туториал первого часа.
- Handjet + Press Start 2P, 18 SFX + фоновый `hum`.

Ограничения:

- Туториал — маскот и несколько подсказок, без пошагового сценария.
- Сохранение в Web идёт через IndexedDB (`user://save.json`); проверяйте
  продолжение после перезагрузки вкладки.
- Remote push ещё не выполнен; сборка для itch.io готовится локально.

## Управление

| Действие | Ввод |
| --- | --- |
| Выбор, меню, перетаскивание | ЛКМ |
| Контекстное меню | ПКМ |
| Пакет из «Приёма» → папка; файл → карточка запроса | drag&drop |
| Поиск по имени в текущей папке | после открытия «Поиска» |
| Мини-игра соединения: три попадания | ЛКМ или `Space` |
| Мини-игра подготовки: отправить | `Enter` или кнопка |
| Пауза | `Esc` |
| Панель соединения: отмена (слот свободен, запрос остаётся) | `Esc` |

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
`.js`/`.png`. Пресет `thread_support=false`: COOP/COEP не нужны. Локальный
просмотр — только по HTTP:

```bash
python3 -m http.server 8000 --directory build/web
# http://localhost:8000
```

Нужны export templates 4.7.2 (`web_nothreads_release.zip`).

## Тесты

Полный прогон (20 наборов + parse-check):

```bash
bash scripts/run_all_tests.sh
```

Точечно:

```bash
"$GODOT" --headless --path . --script tests/run_tests.gd
"$GODOT" --headless --path . --script tests/test_fuzz.gd
"$GODOT" --headless --path . --script tests/test_full_playthrough.gd
"$GODOT" --headless --path . --script scripts/ui/ui_smoke.gd
```

Фактический итог: **5 498 проверок, 0 провалов**; `run_all_tests.sh` —
**21/21 PASS** (20 наборов + parse-check). Подробности — в
[AI_REPORT](AI_REPORT.md).

## Структура

```
peak-hour/
├─ project.godot              # 1600×900 / 1280×720, GL Compatibility
├─ export_presets.cfg         # Web (no threads)
├─ scenes/                    # Main + dev-превью
├─ scripts/
│  ├─ game_controller.gd      # цикл menu → prep → hour → results
│  ├─ run_all_tests.sh        # полный headless-прогон
│  ├─ autoload/               # Game, Data, Audio, Rng
│  ├─ core/                   # HourDirector, FileRegistry, SlotManager, Economy
│  ├─ entities/               # файлы, пакеты, запросы, папки, слоты
│  ├─ systems/                # атаки, магазин, сохранения
│  ├─ ui/                     # Theme90 v2, компоненты, модалки, маскот
│  └─ minigames/              # ConnectionGame, MiniGame
├─ data/                      # balance.json, strings_ru.json, names_ru.json
├─ art/fonts/                 # Handjet, Press Start 2P + OFL
├─ audio/                     # generate_sfx.py, sfx/, music/
├─ tests/                     # headless-наборы
├─ docs/                      # GDD, DECISIONS, UI_REFRESH, screenshots
└─ build/                     # артефакты экспорта (gitignored)
```

## Требования

- Godot **4.7.2** (GL Compatibility).
- Для Web: export templates 4.7.2, `web_nothreads_release.zip`.
- Python 3 — только для пересборки SFX.
- Никаких секретов и внешних сервисов.

## Документация

- [GDD](docs/GDD.md) — правила и числа v1.2.
- [DECISIONS](docs/DECISIONS.md) — решения D01–D25.
- [AI_REPORT](AI_REPORT.md) — модели, приёмы и проверки.
- [ASSETS](ASSETS.md) — шрифты, звук, лицензии и воспроизведение.
- [UI_REFRESH](docs/UI_REFRESH.md) — UI v2 «Kaleidos».
- [IMPLEMENTATION](docs/IMPLEMENTATION.md) и [TEST_PLAN](docs/TEST_PLAN.md) —
  контракты и матрица тестов.
- [ITCH_PAGE](docs/ITCH_PAGE.md) — текст страницы itch.io.
- [screenshots](docs/screenshots/) — кадры меню, подготовки, часа и атак.

## Лицензии

Код — **MIT** ([LICENSE](LICENSE)). Шрифты — **SIL OFL 1.1**
(`art/fonts/OFL-*.txt`). UI и иконка — MIT. SFX и `hum.wav` — MIT/CC0,
сгенерированы `audio/generate_sfx.py`. Подробности — в [ASSETS.md](ASSETS.md).
