# AI_REPORT — PEAK HOUR 97

Отчёт об использовании ИИ. Требование джем-регламента: перечислить модели,
что именно сгенерировано и что проверено вручную.

## 1. Какие ИИ использовались

| Модель / агент | Роль | Что делал |
| --- | --- | --- |
| DeepSeek V4.1 Flash (через OpenCode, субагент `devops`) | инфраструктура | скелет проекта, `project.godot`, `export_presets.cfg`, .gitignore, документация, проверка headless-запуска и web-экспорта |
| _TODO_ | геймдизайн | _заполнить_ |
| _TODO_ | код геймплея | _заполнить_ |
| _TODO_ | арт/звук | _заполнить_ |

## 2. Что сгенерировано ИИ

- `project.godot` — конфигурация (1280×720, canvas_items/keep/integer, GL Compatibility,
  nearest-фильтр, max_fps=60, автолоады).
- `export_presets.cfg` — пресет Web (HTML5), no threads, adaptive canvas resize.
- `scenes/Main.tscn`, `scenes/Prep.tscn`, `scenes/Hour.tscn`, `scenes/ui/HUD.tscn`,
  `scenes/minigames/MinigameBase.tscn`, `scenes/modals/ModalBase.tscn` — каркас сцен.
- `scripts/main.gd`, `scripts/autoload/*.gd`, `scripts/**` — заглушки без игровой логики.
- `art/fonts/ui_theme.tres` — тема с дефолтным шрифтом.
- `icon.svg` — простая иконка (формы, без текста).
- `data/*.json` — скелеты данных (значения намеренно не заданы).
- `README.md`, `ASSETS.md`, `AI_REPORT.md`, `LICENSE`, `.gitignore`, `docs/`.

_Игровой код, баланс, сценарий, финальный арт — TODO._

## 3. Что проверено вручную

- [ ] Просмотр сцены `Main.tscn` в редакторе.
- [ ] Запуск игры в окне, проверка масштабирования при 1280×720 / 1920×1080 / 2560×1440.
- [ ] Кириллица в UI на выбранном шрифте (в т.ч. `Ё`, `П`, `О`).
- [ ] Web-сборка открывается по HTTP локально.
- [ ] Отсутствие ошибок в консоли браузера при старте.

Проверки, выполненные автоматически (headless-запуск, web-экспорт), см. раздел 4.

## 4. Автоматические проверки (лог)

Окружение: Godot `4.7.2.stable.official.ed1daf0bf`, export templates 4.7.2.stable.

```
$ "$GODOT" --headless --path /home/eq/techlb/peak-hour --quit
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

exit=0            # ни одного SCRIPT ERROR / Parse Error

$ "$GODOT" --headless --path /home/eq/techlb/peak-hour \
    --export-release "Web" build/web/index.html
exit=0

$ ls -lh build/web/index.html build/web/index.pck build/web/index.wasm
-rw-r--r-- 1 eq eq 5,4K index.html
-rw-r--r-- 1 eq eq 123K index.pck
-rw-r--r-- 1 eq eq  38M index.wasm
# всего build/web ≈ 39M
```

Дополнительно: web-сборка проверена на чистом клоне (`git clone` → `--import` →
`--export-release`), ассеты и `.gitignore` воспроизводятся без ручных шагов.

## 5. Замечания и ограничения

- Godot 4.7.2, GL Compatibility: без Forward+/Vulkan — совместимо с web и слабыми GPU.
- Web-сборка без threads: не требует COOP/COEP, но `Thread`/`WorkerThreadPool`
  в игре использовать нельзя (или только после переключения пресета).
- Шрифты: основной — Press Start 2P (полная кириллица, OFL). Pixelify Sans
  не содержит глифов `П`/`О`, поэтому не годится для русского UI (детали в `ASSETS.md`).
- Секретов и токенов в репозитории нет; экспортные credentials игнорируются git.
