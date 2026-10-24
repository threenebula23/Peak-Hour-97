# IMPLEMENTATION — контракт реализации (PEAK HOUR, Godot 4.7.2)

> Точный контракт для параллельной разработки. Числа берутся ТОЛЬКО из
> `data/balance.json` и `docs/DECISIONS.md` (D01–D17). Параметры, не заданные
> в промпте, в `balance.json` помечены `null` и списком `_todo` — их нужно
> уточнить до кода, не выдумывать в реализации.
> Язык: GDScript. UI строится кодом; `.tscn` — только корень сцены.
> Комментарии/UI — на русском, идентификаторы — на английском.

## 1. Автолоады

| Автолоад | Файл | Ответственность |
| --- | --- | --- |
| `Game` | `scripts/autoload/game.gd` | состояния/переходы, сброс забега |
| `Data` | `scripts/autoload/data.gd` | чтение `res://data/*.json`, строки |
| `Rng` | `scripts/autoload/rng.gd` | сид забега, детерминизм |
| `Audio` | `scripts/autoload/audio.gd` | SFX/музыка, громкости |

### Game
```gdscript
signals:
  state_changed(next_state: String)
  hour_started(hour: int)
  hour_finished(hour: int, report: Dictionary)
  run_finished(report: Dictionary)
methods:
  func start_new_run(seed: int) -> void
  func next_hour() -> void          # transitions Hour -> Prep/Results
  func pause() -> void / unpause() -> void
  func esc_pressed() -> void        # routes per D10
fields:
  var state: String                 # "menu"|"prep"|"hour"|"modal"|"results"
  var day_number: int               # счётчик 30+ ч для D02 (склад-поражение)
```
Автолоады не знают о конкретных сценах; сцены не хранят глобальное состояние.

### Data
```gdscript
methods:
  func load_balance() -> Dictionary             # data/balance.json (валидация схемы)
  func name(adjective: bool, seed) -> String    # names_ru.json
  func string(key: String) -> String            # strings_ru.json, стиль btn.*/msg.*/ui.*...
fields:
  var balance: Dictionary
  var names: Dictionary
```

### Rng
```gdscript
methods:
  func set_seed(seed: int) -> void
  func pick(ref: Array) -> Variant      # детерминированный выбор
  func nextf() -> float                 # [0..1)
```

### Audio
```gdscript
methods:
  func play_sfx(id_variants: String) -> void
  func music(track: String) -> void
fields/настройки: music_volume: float, sfx_volume: float
```

## 2. Классы

| Класс | Файл (предполагаемый) | Ответственность |
| --- | --- | --- |
| `FileRegistry` | `scripts/systems/file_registry.gd` | создаёт/хранит `FileItem`, выдаёт по id, счётчики буфера, `required`-карты запросов |
| `FileItem` | `scripts/entities/file_item.gd` | данные файла: id, тип, name, ext, folder, флаги D09 |
| `Folder` | `scripts/entities/folder.gd` | список файлов, capacity 8, отображалка |
| `Section` | `scripts/entities/section.gd` | страницы папок, докупаемые позиции |
| `Packet` | `scripts/entities/packet.gd` | входящий пакет + свой таймер (тики слишком идут из директора) |
| `Request` | `scripts/entities/request.gd` | клиентский запрос: `required` (id), флаги `slot_reserved/connected/minigame_active`, таймер |
| `SlotManager` | `scripts/systems/slot_manager.gd` | слоты соединений (start→max по D13), резерв/освобождение |
| `HourDirector` | `scripts/systems/hour_director.gd` | ЕДИНЫЙ тик `tick(delta)` всех таймеров часа, спавны, канонический Clock |
| `AttackDirector` | `scripts/systems/attack_director.gd` | выбор атаки, её эффект, отражение щитом |
| `Shop` | `scripts/systems/shop.gd` | 9 позиций D13, уровни, цены, применение эффектов |
| `SaveManager` | `scripts/systems/save_manager.gd` | save/load между часами, JSON, `commit()` |
| `MiniGame` | `scripts/minigames/minigame_base.gd` | базовая модалка мини-игры, `start(type, difficulty)` |
| `ConnectionGame` | `scripts/systems/connection_game.gd` | полоска соединения по формуле D04 |

### FileRegistry
```gdscript
signals:
  files_changed()
  file_failed(id: String)
methods:
  func spawn_packet(type: String) -> String            # ID нового пакета
  func accept_to_folder(packet_id: String, folder: String) -> bool  # (+0.5 SLA)
  func attach(file_id: String, req_id: String) -> bool # D06: attach единственный
  func detach(file_id: String) -> void                 # cooldown 20 c (D02)
  func destroy(file_id: String) -> bool                # D02:folder-only / malicious всегда
  func try_reserve(req_id: String, file_id: String) -> bool
invariants:
  - буфер = 4 + 2×buffer_upgrades, максимум 8 (D05);
  - файл attached не более, чем в 1 запросе (D06);
  - `failed` файл → все запросы, где он required, отменяются со штрафом (D06);
  - `locked`/malicious файл кликабелен (D08).
```

### HourDirector (единственный тикер)
```gdscript
signals:
  packet_spawned(id: String)
  request_spawned(id: String)
  spawn_frozen(reason: String)       # "modal"|"buffer_full" (D03)
methods:
  func tick(delta: float) -> void    # delta = min(delta, 0.1) (D11)
  func set_paused(paused: bool) -> void
invariants:
  - сущности не тикают сами; все таймеры замыруются здесь;
  - спавн/таймеры пакетов: паез (D03/D05), открытая модалка/панель (D03);
  - таймер активного запроса неудержно идёт даже с открытой модалкой (D03);
  - после часа 8 таблица сложности — час 8, +5 % к скорости спавна каждые 2 ч (D12).
```

### ConnectionGame
```gdscript
signals:
  connected(success: bool)
methods:
  func open(request_id: String, hour: int, successes: int, zone_level: int) -> void
  func width() -> float              # W-Zone по D04
  # W = clamp(0.30 − 0.005*(hour-1) − 0.005*successes + 0.05*zone_upgrade_level, 0.18, 0.36)
  # скорости: 440/340/280 px/с; окно ~130–200 мс
invariants:
  - zone — только эта формула (D04/D05);
  - открытая панель останавливает спавн приёма и таймеры пакетов (D03);
  - Esc — отмена: слот свободен, запрос остаётся (D10).
```

### Шоп-Shop (D13)
```gdscript
methods:
  func can_buy(item_id: String) -> bool
  func buy(item_id: String) -> bool
  func level(item_id: String) -> int
invariants:
  - 9 позиций с ценами/уровнями как в `balance.json → shop`;
  - сканер/автосортировка не реализуются (D13, позиций «резерв» в данных НЕТ).
```

### SaveManager
```gdscript
methods:
  func commit() -> void               # по началу подготовки
  func load() -> Dictionary
fields: слот — между часами, JSON, без секретов и без вычислимых полей.
```

### MiniGame
```gdscript
methods:
  static func select_type(difficulty: float) -> String:
    # coeff: text 1.0, sound 2.0, photo 3.0, video 4.0 (среднее по required, D17)
    # <1.5 text, <2.5 sound, <3.5 photo, иначе video
  func start(type: String, difficulty: float) -> void
invariants:
  - модалка; открытие останавливает спавн приёма и таймеры пакетов (D03),
    сама живёт на `PROCESS_MODE_ALWAYS`;
  - Esc — no-op; закрытие — только кнопкой/таймаутом (D10);
  - заглушка quality = 1.0 (D17).
```

## 3. Схемы сцен

```
Main.tscn  (корень Control + main.gd; только сцена-панель, UI кодом)
  └─ Prep.tscn  (подготовка: магазин, чистка папок)
      └─ Hour.tscn (HUD, несколько дочерних Control; карта прямых детей)
         modals: ModalBase.tscn, minigame_* и connection-панель
```

- `.tscn` файлах — только корень сцены; все контролы строятся `_ready()`-кодом.
- Переходы сцен — только через автолоад `Game` (`state_changed`).
- Модалки и соединяшки — на `PROCESS_MODE_ALWAYS` (D03/D11).

## 4. Drag & drop

**Источник** — карточка пакета (приём) или файла (папка/склад).
**Цель** — папка (приклад в приёме), карточка запроса (приклад в запрос).
Данные, возвращённые `_get_drag_data`:

```gdscript
return {
  "kind": "packet" | "file" | "request",
  "id": self.id,
}
```

- Отмена перетаскивания: ПКМ или `Esc` — обработка в `_cancel_drag()`.
- Подсветка: `_can_drop_data` проверяет допустимость (capacity папки, лока,
  cooldown); `_can_drop_data == true` — цветовая подложка boundbox (зелёный/красный).
- D06: файл, уже есть во втором запросе — рисуем его серым.

## 5. Таймеры и тики

- Единственный Clock = `HourDirector.tick(delta)`; сущности НЕ тикают сами.
- `delta = min(delta, 0.1)`; авто-пауза при
  `NOTIFICATION_APPLICATION_FOCUS_OUT`; `Engine.max_fps = 60` (D11).
- `PROCESS_MODE_ALWAYS` — только на модалках/соединяшке (D03).
- Список таймеров, монтируемых в директоре: `packet_timer` (с D03),
  `request_timer`, спавн-интервалы `recv_interval`, `send_interval`,
  `attack_alert` (3 с).

## 6. Схема data/*.json

Поле ping — только числа и строки, никаких секретов. Схемы — в файл источнике.
Подсказка: `_todo` по ключам — тег «уточнить», НЕ значение.

- `data/balance.json` — вся аритметика игры (схема внутри файла).
- `data/names_ru.json` — пулы для генератора имён/организаций.
- `data/strings_ru.json` — ключи: `btn.*`, `msg.*`, `ui.*`, `shop.*`, `attack.*`.

## 7. Тестовые хуки

- **Ускоренное время:** OS env `PEAKHOUR_TIMESCALE=8.0` (или в консоли Godot
  `--seed TIME_SCALE=8.0`) — HourDirector умножает время на множитель; deliberate
  только для тестов, в release НЕ включать (disable-флаг по D11).
- **Инжект сид:** env `PEAKHOUR_SEED=123` читает рание `Rng.set_seed`.
- **Headless:** запуск `/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64
  --headless --path . --script tests/run_all.gd` (без окно, нативный).
- **Web smoke:** локальный `python3 -m http.server 8000 --directory build/web`.

## 8. Распределение файлов

| Владелец | Зона |
| --- | --- |
| Lane A (core) | `scripts/autoload/*`, `scripts/core/*`, `data/balance.json` |
| Lane B (entities) | `scripts/entities/*` (FileItem, Folder, Section, Packet, Request, Visitor) |
| Lane C (systems) | `scripts/systems/*` (FileRegistry, SlotManager, HourDirector, AttackDirector, Shop, SaveManager, ConnectionGame) |
| Lane D (ui/minigames) | `scripts/ui/*`, `scripts/minigames/*`, сцены, HUD, strings_ru.json |
| Общие (не трогать) | `project.godot`, `scenes/Main.tscn`, `scripts/main.gd`, `export_presets.cfg`, шрифты, git |
