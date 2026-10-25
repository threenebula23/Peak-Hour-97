# Архитектура

Короткая карта реализации. Правила и числа — в [GDD](GDD.md), контракты
модулей и тестовые хуки — в [IMPLEMENTATION](IMPLEMENTATION.md); здесь только
структура проекта.

## Сцена и UI

- `scenes/Main.tscn` — единственная сцена игрового потока: корень `Control` +
  `scripts/main.gd`, 1280×720.
- Весь интерфейс строится кодом в `scripts/ui/*.gd`: панели, кнопки, карточки,
  сетка файлов, дерево папок, скроллбары и стиль 90-х.
- Модальные окна — `Control`-скрипты `scripts/ui/*_modal.gd`: `MainMenu`,
  `ShopModal`, `PauseModal`, `SettingsModal`, `HourResultModal`,
  `RunResultModal`, `ConfirmModal`. Отдельной базовой сцены модалок нет.
- Дев-инструменты (`scenes/ui/ModalsPreview.tscn`, `font_preview.tscn`,
  `scenes/minigames/MinigameBase.tscn`) не входят в игровой поток.

## Игровой цикл

- `scripts/game_controller.gd` — фазы `menu → prep → hour → hour_result →
  run_result`, связывает `Game`, `HourDirector`, `Shop` и `SaveManager`.
- `scripts/core/hour_director.gd` — единый тикер часа: пакеты, запросы, слоты,
  спавн и атаки. Сущности не тикают сами.
- Автолоады: `Game` (состояние забега), `Data` (JSON), `Audio` (SFX/фон),
  `Rng` (детерминизм). Автолоады не знают о сценах и UI.

## Данные

- `data/balance.json` — числа и таблицы сложности.
- `data/strings_ru.json` — RU-тексты UI.
- `data/names_ru.json` — имена файлов, папок и клиентов.
- Значения по умолчанию живут в данных и коде модулей, отдельных глобальных
  констант нет.

## Договорённости

- В `.tscn` — только корень; контролы собираются в `_ready()`.
- Модалки и мини-игры — на `PROCESS_MODE_ALWAYS` (D03/D11).
- Web без threads: без `Thread`/`WorkerThreadPool` и блокирующего IO в кадре.
- UI-тексты — русский, идентификаторы — английский, файлы — `snake_case`.
- Мини-игры наследуют `scripts/minigames/minigame_base.gd` и не лезут в UI
  напрямую.

## Подробности

- [GDD](GDD.md) — механики, формулы, решения.
- [IMPLEMENTATION](IMPLEMENTATION.md) — контракты классов, drag&drop, таймеры,
  схемы данных и тестовые хуки.
