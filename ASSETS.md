# ASSETS

Список сторонних и собственных ассетов проекта. Правило репозитория: только
ассеты с явной лицензией, разрешающей использование в джем-проекте.

## Шрифты

### Press Start 2P — основной UI-шрифт

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/PressStart2P-Regular.ttf` |
| Стиль | Regular (single weight, bitmap-подобный пиксельный) |
| Автор / проект | The Press Start 2P Project Authors (CodeMan38, cody@zone38.net) |
| Источник | https://github.com/google/fonts/tree/main/ofl/pressstart2p |
| Прямая ссылка | https://raw.githubusercontent.com/google/fonts/main/ofl/pressstart2p/PressStart2P-Regular.ttf |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL-PressStart2P.txt` |
| SHA-256 | `034c77f1f05ec89421e4a63f0e3a4ca1ecf852cc6d2bf611f126f275728e017d` |
| Кириллица | полная: А–Я, а–я, Ё/ё, Ъ/ъ, Ь/ь, Ы/ы, Э/э, Ю/ю, Я/я + цифры и `:/-` |
| Использование | `project.godot → gui/theme/custom = res://art/fonts/ui_theme.tres` (default_font), заголовок `scenes/Main.tscn` |

Шрифт выбран основным, потому что покрывает кириллицу целиком (проверено по cmap:
656 кодпоинтов, пропусков в русском алфавите нет). Это критично: интерфейс игры
русскоязычный (`data/strings_ru.json`).

### Pixelify Sans — декоративный (латиница)

| Поле | Значение |
| --- | --- |
| Файл | `art/fonts/PixelifySans[wght].ttf` (variable, ось `wght`) |
| Автор / проект | The Pixelify Sans Project Authors — https://github.com/eifetx/Pixelify-Sans |
| Источник | https://github.com/google/fonts/tree/main/ofl/pixelifysans |
| Прямая ссылка | https://raw.githubusercontent.com/google/fonts/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf |
| Лицензия | SIL Open Font License 1.1 — `art/fonts/OFL.txt` |
| SHA-256 | `9ba86cd010a4de309d263ceff8e8044092c9db7efda869620cb9ff1c4389e8a5` |
| Кириллица | **неполная** — в cmap отсутствуют `П` (U+041F), `О` (U+041E), `І` (U+0406), `Ѝ` (U+040D) |
| Использование | только латинские надписи/логотип. В UI по умолчанию НЕ подключён |

Причина: variable TTF импортируется в Godot корректно, но в исходном шрифте
(и в Google Fonts, и в upstream-репозитории) нет глифов `П` и `О`. Русский текст
набрать нельзя («ПИК ЧАС» → потеря букв), поэтому основным шрифтом взят
Press Start 2P. Pixelify Sans оставлен как альтернатива для латиницы —
подключать точечно через `Label.theme_override_fonts/font`, не глобально.

Оба шрифта распространяются по OFL 1.1: их можно использовать и встраивать в
игру (в т.ч. коммерческую), но нельзя продавать сами шрифты; при распространении
нужно сохранять текст лицензии (`art/fonts/OFL*.txt`) и не использовать
Reserved Font Name для производных шрифтов.

## Графика

| Файл | Автор | Лицензия | Примечание |
| --- | --- | --- | --- |
| `icon.svg` | команда проекта | MIT | нарисован вручную для этого проекта, текст в SVG не используется (ThorVG) |

Директории `art/icons/`, `art/ui/` пока пусты (`.gitkeep`).

## Аудио

`audio/sfx/`, `audio/music/` пока пусты (`.gitkeep`). При добавлении звуков
обязательно фиксировать здесь: файл, автор, лицензия, ссылка на источник.

## Чего в проекте нет

- Сторонних спрайтов, тайлсетов, музыкальных треков и SFX.
- Ассетов из коммерческих игр (в т.ч. Namco) — Press Start 2P лишь стилизован
  под аркадные bitmap-шрифты, это самостоятельный шрифт под OFL.
