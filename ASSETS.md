# ASSETS — PEAK HOUR 97

Сторонние и собственные ассеты проекта. В репозитории только файлы с явной
лицензией, совместимой с джем-проектом и MIT-кодом.

## Шрифты

### Handjet — основной UI-шрифт

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/Handjet-VF.ttf` (variable; локальное имя для `Handjet[ELGR,ELSH,wght].ttf`) |
| Оси | `wght` 100–900, `ELGR` 1–2, `ELSH` 0–16; в теме — `wght 700, ELGR 2, ELSH 2` |
| Автор / проект | The Handjet Project Authors / Rosetta Type — https://github.com/google/fonts/tree/main/ofl/handjet |
| Прямая ссылка | https://raw.githubusercontent.com/google/fonts/main/ofl/handjet/Handjet%5BELGR%2CELSH%2Cwght%5D.ttf |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL-Handjet.txt` |
| SHA-256 | `9262749e8bb0b73ebcae0e20428689c3c59576eebeb6c4e1020300d2d41bdf4d` |
| Кириллица | полная (проверено по cmap: А–Я, а–я, Ё/ё, цифры; 1339 кодпоинтов) |
| Использование | `default_font` темы `art/fonts/ui_theme.tres`; все UI-тексты |

Handjet узкий (средняя ширина ≈0.36 em), поэтому в карточки 132 px влезают
имена файлов. Допустимые кегли: **10 / 12 / 16 / 24**.

### Press Start 2P — логотип и крупные цифры

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/PressStart2P-Regular.ttf` |
| Автор / проект | The Press Start 2P Project Authors (CodeMan38) |
| Источник | https://github.com/google/fonts/tree/main/ofl/pressstart2p |
| Прямая ссылка | https://raw.githubusercontent.com/google/fonts/main/ofl/pressstart2p/PressStart2P-Regular.ttf |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL-PressStart2P.txt` |
| SHA-256 | `034c77f1f05ec89421e4a63f0e3a4ca1ecf852cc6d2bf611f126f275728e017d` |
| Кириллица | полная (656 кодпоинтов, включая Ё/ё и служебные `:/-`) |
| Использование | только логотип, заголовки и числовые строки (`theme90.gd → logo()`) |

Шрифт слишком широкий для карточек (17 символов не влезают в 132 px), поэтому
основным текстом он не используется.

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

Все три шрифта — **SIL OFL 1.1**. OFL разрешает встраивать шрифты в игру
(включая коммерческую), но требует сохранять текст лицензии и не продавать
шрифт отдельно. Для производных шрифтов действует Reserved Font Name
(у Press Start 2P — «Press Start 2P»). Это совместимо с MIT-лицензией кода:
MIT не накладывает ограничений на шрифты, а OFL-тексты лежат рядом с файлами.

## Графика

| Файл | Автор | Лицензия | Примечание |
| --- | --- | --- | --- |
| UI, иконки, фаски | команда проекта | MIT | рисуются кодом в `scripts/ui/theme90.gd`; внешних текстур нет |
| `icon.svg` | команда проекта | MIT | иконка проекта, формы без текста (ThorVG) |
| `docs/screenshots/*.png` | команда проекта | MIT | кадры игры 1280×720, сняты из работающей сборки |

`art/icons/` и `art/ui/` пусты (`.gitkeep`): спрайтов, тайлсетов и сторонней
графики в проекте нет.

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
curl -L -o Handjet-VF.ttf \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/handjet/Handjet%5BELGR%2CELSH%2Cwght%5D.ttf"
curl -L -o PressStart2P-Regular.ttf \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/pressstart2p/PressStart2P-Regular.ttf"
sha256sum Handjet-VF.ttf PressStart2P-Regular.ttf
```

Ожидаемые хеши — в таблицах выше. Тексты OFL уже лежат в `art/fonts/`; при
обновлении шрифта обновите и их. Pixelify Sans скачивается по ссылке из его
раздела, но для сборки не требуется.

### Графика

Генерировать нечего: UI и иконки рисуются кодом, `icon.svg` — обычный SVG.
После клонирования достаточно импортировать проект в Godot 4.7.2.

## Чего в проекте нет

- Сторонних спрайтов, тайлсетов, музыкальных треков и сэмплов.
- Ассетов из коммерческих игр; Press Start 2P лишь стилизован под аркадные
  bitmap-шрифты и распространяется по OFL.
- Секретов, ключей и токенов в ассетах и данных.
