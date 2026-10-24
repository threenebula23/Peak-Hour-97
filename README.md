# PEAK HOUR 97

> Час пик. Одна смена. Ни одного свободного места.

Каркас Godot-проекта для гейм-джема: Godot **4.7.2**, рендер **GL Compatibility**,
целевая платформа — **Web (HTML5, без threads)**.

Сейчас в репозитории только скелет: запускаемая сцена, автолоады-заглушки,
пустые директории под сцены/скрипты/данные, экспорт-пресет и документация.
Игровой логики нет.

## Требования

- Godot 4.7.2 (в этом окружении: `/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64`)
- Export templates 4.7.2 в `~/.local/share/godot/export_templates/4.7.2.stable/`
  (для web-сборки нужен `web_nothreads_release.zip`)

## Запуск

Свежий клон не содержит `res://.godot/` (он в .gitignore), поэтому один раз нужно
импортировать ассеты — иначе шрифт и `ui_theme.tres` ещё не скомпилированы:

```bash
/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path /home/eq/techlb/peak-hour --import
```

Дальше — обычный запуск:

```bash
/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path /home/eq/techlb/peak-hour
```

Редактор:

```bash
/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64 -e --path /home/eq/techlb/peak-hour
```

## Сборка Web

```bash
mkdir -p build/web
/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path /home/eq/techlb/peak-hour \
  --export-release "Web" build/web/index.html
```

Результат: `build/web/index.html` + `.wasm` + `.pck` (+ сопутствующие `.js`, `.png`, `.worker.js`).

Локальный просмотр (нужен HTTP-сервер, `file://` не работает):

```bash
python3 -m http.server 8000 --directory build/web
# http://localhost:8000
```

Пресет собран под **no threads** (`variant/thread_support=false`): игра запускается
без COOP/COEP-заголовков, что удобно для itch.io и простого статического хостинга.

## Управление

Игровая логика ещё не реализована — сейчас работают только системные вещи
(окно/растяжение). Запланированная схема ввода:

| Действие | Клавиша |
| --- | --- |
| Движение по сцене | `WASD` / стрелки |
| Взаимодействие / выбор | ЛКМ, `E` |
| Отмена / назад | `Esc` |
| Пауза | `Esc` |
| Полный экран | `F11` |

Таблица поддерживается в актуальном состоянии по мере появления механик.

## Структура

```
peak-hour/
├─ project.godot          # настройки проекта, автолоады
├─ export_presets.cfg     # пресет Web (no threads)
├─ scenes/                # Main / Prep / Hour + ui, minigames, modals
├─ scripts/
│  ├─ autoload/           # Game, Data, Audio, Rng (заглушки)
│  ├─ core/               # состояние забега, константы
│  ├─ entities/           # посетители, стойки
│  ├─ systems/            # спавн, очки, сохранения
│  ├─ ui/                 # HUD, модалки
│  └─ minigames/          # базовый класс мини-игр
├─ data/                  # balance.json, strings_ru.json, names_ru.json
├─ art/                   # fonts/ (OFL), icons/, ui/
├─ audio/                 # sfx/, music/
├─ shaders/
├─ tests/
├─ docs/
└─ build/                 # в .gitignore
```

## Соглашения

- Разрешение проекта 1280×720, `stretch/mode = canvas_items`, `aspect = keep`,
  `scale_mode = integer`, nearest-фильтрация текстур — пиксель-арт без мыла.
- Все секреты (ключи экспорта, токены деплоя) — только через переменные окружения / CI-переменные,
  никогда не в репозитории (`*.cfg` с credentials в .gitignore).
- Экспорт и артефакты — в `build/`, в git не попадают.
- Коммиты — локальные; push в remote выполняет только человек/CI с правами.

## Лицензии

Код — MIT (см. `LICENSE`), шрифты — SIL OFL 1.1 (см. `ASSETS.md`).
