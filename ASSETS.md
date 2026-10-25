# ASSETS — PEAK HOUR 97

Сторонние и собственные ассеты проекта. В репозитории только файлы с явной
лицензией, совместимой с джем-проектом и MIT-кодом.

## Шрифты

### Golos Text — основной UI-шрифт (v3)

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/GolosText-VF.ttf` (variable; локальное имя для `GolosText[wght].ttf`) |
| Оси | `wght` 400–900; в теме — `wght 600` |
| Автор / проект | The Golos Text Project Authors — https://github.com/googlefonts/golos-text |
| Источник | https://github.com/google/fonts/tree/main/ofl/golostext |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL-GolosText.txt` |
| SHA-256 | `17bb58fb69aec2dfb047a2ebf52534023e9b688c97a6b7ac795b0a72912c2063` |
| Кириллица | полная (О/П/Ё/№), гуманистический рисунок, хорошо читается в 11–17 px |
| Использование | `default_font` темы `art/fonts/ui_theme.tres`; весь текст UI |

Типографическая шкала v3: **11 / 13 / 17 / 26 px** (`FS_MICRO`, `FS_BODY`,
`FS_HEAD`, `FS_LOGO`). Подписи файлов в сетке — 12/14/16 px в зависимости от
размера клетки.

### Handjet — legacy, в теме не используется

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/Handjet-VF.ttf` (variable; локальное имя для `Handjet[ELGR,ELSH,wght].ttf`) |
| Оси | `wght` 100–900, `ELGR` 1–2, `ELSH` 0–16 |
| Автор / проект | The Handjet Project Authors / Rosetta Type — https://github.com/google/fonts/tree/main/ofl/handjet |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL-Handjet.txt` |
| SHA-256 | `9262749e8bb0b73ebcae0e20428689c3c59576eebeb6c4e1020300d2d41bdf4d` |
| Кириллица | полная (1339 кодпоинтов) |
| Использование | **нигде**: после перехода на Golos Text (D51) файл оставлен как исторический артефакт |

TTF, `.import` и OFL можно удалить без влияния на игру; тема на Handjet не
ссылается. Узкий рисунок Handjet больше не нужен: Golos Text держит плотный
русский текст в карточках 400 px.

### Press Start 2P — только логотип и цифры

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/PressStart2P-Regular.ttf` |
| Автор / проект | The Press Start 2P Project Authors (CodeMan38) |
| Источник | https://github.com/google/fonts/tree/main/ofl/pressstart2p |
| Прямая ссылка | https://raw.githubusercontent.com/google/fonts/main/ofl/pressstart2p/PressStart2P-Regular.ttf |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL-PressStart2P.txt` |
| SHA-256 | `034c77f1f05ec89421e4a63f0e3a4ca1ecf852cc6d2bf611f126f275728e017d` |
| Кириллица | полная (656 кодпоинтов, включая Ё/ё и служебные `:/-`) |
| Использование | **только** логотип, заголовки и числовые акценты (`theme90.gd → logo()`) |

Шрифт слишком широкий для тела текста и карточек, поэтому основным текстом
он не используется (D51).

### Pixelify Sans — в теме не используется

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/PixelifySans[wght].ttf` (variable, `wght` 400–700) |
| Автор / проект | The Pixelify Sans Project Authors — https://github.com/eifetx/Pixelify-Sans |
| Источник | https://github.com/google/fonts/tree/main/ofl/pixelifysans |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL.txt` |
| SHA-256 | `9ba86cd010a4de309d263ceff8e8044092c9db7efda869620cb9ff1c4389e8a5` |
| Кириллица | **неполная**: нет глифов `О` (U+041E) и `П` (U+041F) |
| Использование | нигде; в `ui_theme.tres` и `theme90.gd` не подключён |

Файл оставлен как исторический артефакт. Если он не нужен — удалите TTF,
`.import` и строку из этого раздела; тема от этого не изменится.

### Совместимость лицензий

Golos Text, Handjet, Press Start 2P и Pixelify Sans — **SIL OFL 1.1**.
OFL разрешает встраивать шрифты в игру (включая коммерческую), но требует
сохранять текст лицензии и не продавать шрифт отдельно. Для производных
шрифтов действует Reserved Font Name. Это совместимо с MIT-лицензией кода:
MIT не накладывает ограничений на шрифты, а OFL-тексты лежат рядом с файлами.

## Графика

| Файл | Автор | Лицензия | Примечание |
| --- | --- | --- | --- |
| `art/icons/*.png` | команда проекта | MIT | 32×32 RGBA, пиксельные иконки файлов/папки/пакета; сгенерированы `art/icons/generate_icons.py` |
| UI, панели, маскот | команда проекта | MIT | рисуются кодом в `scripts/ui/theme90.gd`; внешних UI-текстур нет |
| `icon.svg` | команда проекта | MIT | иконка проекта, формы без текста (ThorVG) |
| `docs/screenshots/*.png` | команда проекта | MIT | кадры игры 1280×720, сняты из работающей сборки |

### Пиксельные иконки файлов

`art/icons/` содержит `file_text.png`, `file_sound.png`, `file_photo.png`,
`file_video.png`, `folder.png` и `packet.png` (все 32×32 RGBA). Иконки
показываются в сетке папки, drag-preview, чипах запроса и карточках пакетов;
в `Theme90.draw_file_icon()` они рисуются с `nearest`, поэтому остаются
резкими в 16/24/32 px.

- Генератор: `art/icons/generate_icons.py` (Python 3 + Pillow), палитра
  Kaleidos, контур 1 px `#2C2A26`, без сглаживания.
- Лицензия: **MIT**, сгенерировано в команде проекта в стиле пиксельного
  тайл-листа; сторонних спрайтов нет.
- Исходный тайл-лист/лист иконок был недоступен, поэтому набор **не вырезан**
  из готового файла, а **перегенерирован** скриптом с нуля. Это позволяет
  воспроизвести все PNG одной командой и не зависит от потерянного исходника.

Пересборка:

```bash
cd peak-hour
python3 art/icons/generate_icons.py
# превью: python3 art/icons/generate_icons.py --preview /tmp/opencode/icons_preview.png
```

`art/ui/` по-прежнему пуст (`.gitkeep`): отдельных UI-спрайтов нет.

## Аудио

Все звуки — оригинальные, синтезированы скриптом проекта
`audio/generate_sfx.py` (только стандартная библиотека Python, без сэмплов).
Автор — команда проекта, лицензия **MIT/CC0**: файлы можно свободно
использовать и распространять, скрипт — по MIT.

| Категория | Файлы |
| --- | --- |
| Интерфейс | `click`, `drag`, `drop`, `drop_error` |
| Приём и передача | `recv`, `request_ready`, `modem`, `connect_fail`, `tick`, `packet_loss` |
| Мини-игры | `minigame_win`, `minigame_fail` |
| Атаки | `attack`, `attack_blocked` |
| Экономика | `money_up`, `money_down` |
| Итоги | `hour_end`, `run_end` |
| Фон | `audio/music/hum.wav` — гул серверной, 3 с, loop-friendly |

Итого **18 SFX** в `audio/sfx/` + **1 фон** в `audio/music/`. Формат:
22050 Гц, 16 бит, моно, пик −6 dBFS; SFX 30–800 мс. Сиды фиксированы, поэтому
повторная генерация даёт те же файлы.

## Как воспроизвести ассеты

### Звук

```bash
cd peak-hour
python3 audio/generate_sfx.py
```

Скрипт создаёт `audio/sfx/*.wav` (18 файлов) и `audio/music/hum.wav`, проверяет
длительности, пики и шов петли. Нужен только Python 3.

### Шрифты

```bash
cd peak-hour/art/fonts
# Golos Text: скачайте GolosText[wght].ttf из google/fonts/ofl/golostext
# и сохраните локально как GolosText-VF.ttf
curl -L -o PressStart2P-Regular.ttf \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/pressstart2p/PressStart2P-Regular.ttf"
sha256sum GolosText-VF.ttf PressStart2P-Regular.ttf
```

Ожидаемые хеши — в таблицах выше. Тексты OFL уже лежат в `art/fonts/`; при
обновлении шрифта обновите и их. Handjet и Pixelify Sans для сборки не
требуются.

### Графика

Иконки пересобираются `python3 art/icons/generate_icons.py` (нужен Pillow).
`icon.svg` — обычный SVG. После клонирования достаточно импортировать проект
в Godot 4.7.2.

## Чего в проекте нет

- Сторонних спрайтов, тайлсетов, музыкальных треков и сэмплов.
- Ассетов из коммерческих игр; Press Start 2P лишь стилизован под аркадные
  bitmap-шрифты и распространяется по OFL.
- Секретов, ключей и токенов в ассетах и данных.
