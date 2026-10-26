# IMPLEMENTATION — контракт реализации (PEAK HOUR, Godot 4.7.2)

> Точный контракт для параллельной разработки. Числа берутся ТОЛЬКО из
> `data/balance.json` и `docs/DECISIONS.md` (D01–D17). Параметры, не заданные
> в промпте, в `balance.json` помечены `null` и списком `_todo` — их нужно
> уточнить до кода, не выдумывать в реализации.
> Язык: GDScript. UI строится кодом; `.tscn` — только корень сцены.
> Комментарии/UI — на русском, идентификаторы — на английском.

## 0. Дельты v3.0 (читать первым)

Этот файл — исторический контракт v1. Актуальная спецификация — `docs/GDD.md`
v3.0 и `docs/DECISIONS.md` D45–D61. Ниже — что в контракте уже неверно:

- **Длительность и темп:** час длится `hours[].duration` — **120 / 150 / 180 /
  210 / 240 / 270 / 300 / 330 / 360 с** (`120 + 30×(h−1)`), забег **36 минут**
  плюс подготовка; `constants.hour_seconds = 300` — только legacy-fallback.
  Спавн файлов идёт в окно **75 %** часа, интервал — `spawn_window / files`
  (скорость `hours[].files`), без carry и общего лимита. Атаки — `clamp(0.25×duration, 20, 60)` …
  `min(0.85×duration, duration−20)`. См. D57/D60, GDD §3/§6/§8.
- **Файлы — каталог, не расходник:** успешная отправка снимает только
  `required_by`/attachment; файл остаётся в папке и доступен новым запросам.
  Общего лимита на забег нет; `hours[].files` (6,6,7,8,9,9,10,10,10) задаёт
  темп. См. D58, GDD §6/§11.
- **Запросы без `request_cap`:** только `hours[].active_requests`, cutoff
  последних **10 с** и `send_interval`; анти-голодание — только для первого
  запроса часа. См. D59, GDD §7/§13.

- **Запросы:** `required` снова хранит **конкретные `file_id`**, но их 1–4, а
  не 1–3; запрос резервирует файлы (`required_by`), UI показывает имена
  сеткой 2×2 и «ПОТЕРЯН». См. GDD §7, D46.
- **Соединение:** `ConnectionGame` **вернулось** в v3. Формула зоны и скорости
  из раздела «ConnectionGame» снова актуальны (D45), но панель вызывается
  только для TCP и замораживает таймер своего запроса; промах −4 SLA / 8 с,
  Esc — 0 SLA / 4 с. TCP-соединение — отдельная сущность `TcpConnection`
  (D53), а не только флаг запроса. До соединения файлы не прикрепляются;
  успех занимает out-слот и **не** открывает мини-игру отправки. После
  успешной отправки слот остаётся idle до `ОТКЛЮЧИТЬ` (D54).
- **Мини-игры:** не 11, а **10** (6 отправки + 4 атаки); игры с проводами нет.
  У отправки **3 ступени**, у атак 4; выбор — `Economy.selection_for_sum()` по
  27 суммам и таблице `rank_games`, без `rank % 7`. См. GDD §8.4, §10.
- **Магазин:** не 9 позиций v1, а **9 лотов** v3 (8 прежних + `lot_udp`),
  дерево **8 825 $** (было 8 085 $); SLA-кап **220**; цены/эффекты — GDD §14,
  D50/D55. Поля «9 позиций D13», «SLA +24», «секция/поиск/зона» устарели.
- **UDP:** соединения нет; шанс успеха — `min(0.40 + 0.10×udp_level, 0.80)`
  (`lot_udp`, 4 уровня), ролл в конце передачи. Провал: −3 SLA, без выплаты,
  файлы остаются, повтор через 4 с, слот освобождается, streak сбрасывается.
  Успех тоже не удаляет файлы — каталог сохраняется (D58). См. D55, GDD §11.2.
- **Экономика/буфер:** SLA-кап +40 до 220 (прежняя схема v2 — история),
  таймер запроса +7 с до 65 (не +5 до 55), буфер 6+уровень (не 4+2×),
  папка 180 $ (не 100), сетки 5×4 → 9×6. Ускорение передачи `×0.90` за
  уровень (прежний множитель v2 — история).
- **Шрифты:** Kechusilka Regular — тело текста (fallback Golos Text),
  DisplayOTF — крупный текст, Press Start 2P — только цифры/счётчики; шкала
  11/13/17/26; иконки — `art/icons/*.png`. Handjet — legacy. См. D56.
- **UI «ЖАРА»:** `TemperatureGauge` в меню-баре вместо часов 03:42,
  `StressOverlay` с alpha-only шейдером без `hint_screen_texture`, пульс
  SLA/CRIT, тряска панелей ≤2 px, `UiMotion`/`reduce_motion`; в headless
  слой скрыт. См. D61, GDD §20.1.
- **Туториал:** 5 событийных шагов с рамками и «ДАЛЕЕ», а не лента подсказок;
  прогресс в `Game.stats["tutorial_done"]`.

Исторические разделы ниже (9 позиций v1, 4+2 буфера, анонимные слоты,
`rank % 7`, панель соединения как «удалённая») оставлены для провенанса и не
являются текущим контрактом.

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

| Класс | Файл | Ответственность |
| --- | --- | --- |
| `FileRegistry` | `scripts/core/file_registry.gd` | создаёт/хранит `FileItem`, выдаёт по id, счётчики буфера, `required`-карты запросов |
| `FileItem` | `scripts/entities/file_item.gd` | данные файла: id, тип, name, ext, folder, флаги D09 |
| `Folder` | `scripts/entities/folder.gd` | список файлов, capacity 8, отображалка |
| `Section` | `scripts/entities/section.gd` | страницы папок, докупаемые позиции |
| `Packet` | `scripts/entities/packet.gd` | входящий пакет + свой таймер (тики слишком идут из директора) |
| `Request` | `scripts/entities/request.gd` | клиентский запрос: `required` (id), `connection_id`, флаги `slot_reserved/connected/minigame_active`, UDP-поля, таймер |
| `TcpConnection` | `scripts/entities/tcp_connection.gd` | установленное TCP-соединение: клиент, IP, `request_id`, `slot_index`; живёт отдельно от запроса |
| `SlotManager` | `scripts/core/slot_manager.gd` | слоты соединений `1 + slot_level` (макс. 5), `kind`/`detail`/`linked_request_id`, резерв/освобождение |
| `HourDirector` | `scripts/core/hour_director.gd` | ЕДИНЫЙ тик `tick(delta)` всех таймеров часа, спавны, `active_connections`, канонический Clock |
| `AttackDirector` | `scripts/systems/attack_director.gd` | выбор атаки, её эффект, отражение щитом |
| `Shop` | `scripts/systems/shop.gd` | 9 лотов v3, уровни, цены, применение эффектов |
| `SaveManager` | `scripts/systems/save_system.gd` | save/load между часами, JSON, `commit()` |
| `MiniGame` | `scripts/minigames/minigame_base.gd` | базовая модалка мини-игры, `start(type, difficulty)` |
| `ConnectionGame` | `scripts/minigames/connection_game.gd` | полоска соединения по формуле D04; `finished(success, request_id)` |

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
  finished(success: bool, request_id: String)
methods:
  func start(hour: int, successes: int, zone_level: int, request_id: String) -> void
  func open(request_id: String, hour: int, successes: int, zone_level: int) -> void  # legacy alias
  func width() -> float              # W-Zone по D04
  static func compute_zone(hour: int, successes: int, zone_level: int) -> float
  # W = clamp(0.30 − 0.005*(hour-1) − 0.005*successes + 0.05*zone_upgrade_level, 0.18, 0.36)
  # скорости: 440/340/280 px/с; 3 попадания; Esc / промах → finished(false, id)
invariants:
  - zone — только эта формула (D04/D05);
  - промах/уход за край: −4 SLA и кулдаун 8 с; Esc: 0 SLA и кулдаун 4 с;
  - открытая панель останавливает спавн приёма и таймеры пакетов (D03);
  - успех не открывает мини-игру отправки: UI вызывает
    `HourDirector.connection_finished(id, true)`.
```

### TcpConnection (D53)
```gdscript
fields:
  id: String
  client_name: String
  client_id: String
  ip: String                        # случайный IPv4 для UI слота
  request_id: String                # "" — соединение idle после отправки
  slot_index: int                   # out-слот, который держит соединение
  hour: int
  connected_at: float
methods:
  func has_request() -> bool
  func display_name() -> String
  func to_dict() -> Dictionary
  static func from_dict(d: Dictionary) -> TcpConnection
invariants:
  - соединение живёт в `HourDirector.active_connections`, а не в Request;
  - создаётся только при успехе ConnectionGame и только если есть свободный слот;
  - занимает ровно один out-слот (`kind == "tcp_connection"`), слот общий с приёмом;
  - после успешной отправки `request_id` очищается, слот остаётся занятым;
  - `disconnect_connection(conn_id)` освобождает слот мгновенно, без мини-игр;
  - reject/timeout/конец часа вызывают `_release_connection()`.
```

### Slot (kind/detail) и SlotManager
```gdscript
fields Slot:
  index: int
  direction: String                 # "in" | "out"
  entity_id: String                 # packet_id / request_id / conn_id
  entity_name: String               # имя клиента для tcp_connection
  progress: float
  occupied: bool
  kind: String                      # "packet" | "request" | "tcp_connection"
  detail: String                    # tcp_connection → IP
  can_disconnect: bool
  linked_request_id: String         # запрос, который пользуется соединением
methods SlotManager:
  func reserve(direction, entity_id, entity_name = "", kind = "", detail = "",
               can_disconnect = false, linked_request_id = "") -> int
  func release(index: int) -> bool
  func release_by_entity(entity_id: String) -> int
  func active_weights(registry) -> Array
invariants:
  - всего `1 + slot_level`, максимум 5; слоты общие для приёма и отправки;
  - `tcp_connection` не хранит имена файлов/required — только клиента и IP;
  - вес канала для `tcp_connection` считается по файлам `linked_request_id`;
  - одна сущность не занимает два слота.
```

### HourDirector: соединения и UDP
```gdscript
fields:
  active_connections: Dictionary    # conn_id → TcpConnection
methods:
  func connect_request(req_id: String) -> bool          # старт ConnectionGame
  func connection_finished(req_id: String, success: bool, missed: bool = false) -> bool
  func disconnect_connection(conn_id: String) -> bool   # мгновенно, без проверок
  func disconnect_request(req_id: String) -> bool
  func get_connection(conn_id: String) -> TcpConnection
  func connection_id_for_request(req_id: String) -> String
  func udp_success_chance() -> float
invariants:
  - `attach_file` для TCP отклоняется, пока `req.connection_id == ""`;
  - успех соединения занимает out-слот; `start_send` не создаёт соединение;
  - успешная отправка отвязывает соединение (`conn.request_id = ""`), но не
    освобождает слот;
  - отключение во время передачи обнуляет прогресс, возвращает файлы,
    запрос оставляет активным;
  - UDP-провал: `−3 SLA`, файлы остаются, `udp_failures += 1`,
    `udp_retry_until = hour_elapsed + 4`, слот освобождается, streak = 0.
```
`Economy.udp_success_chance(upgrades, base, step, cap)` возвращает
`clamp(0.40 + 0.10×level, 0.40, 0.80)`; уровень берётся из `lot_udp`.

### Шоп-Shop (D13/D50/D55)
```gdscript
methods:
  func can_buy(item_id: String) -> bool
  func buy(item_id: String) -> bool
  func level(item_id: String) -> int
invariants:
  - **9 лотов** с ценами/уровнями как в `balance.json → shop`, включая `lot_udp`;
  - полное дерево — **8 825 $**;
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
scenes/Main.tscn  (корень Control + scripts/main.gd)
  └─ UI собирается кодом из scripts/ui/*.gd
       ├─ компоненты: panel90, button90, tree_panel, file_grid,
       │  file_card, packet_card, request_card, slot_cell, status_bar…
       └─ модалки: main_menu.gd, shop_modal.gd, pause_modal.gd,
          settings_modal.gd, hour_result_modal.gd, run_result_modal.gd,
          confirm_modal.gd
scripts/game_controller.gd  (menu → prep → hour → hour_result → run_result)
scripts/core/hour_director.gd  (единый тикер часа)
```

- `Main.tscn` — единственная сцена игрового потока; отдельных сцен подготовки,
  часа и базы модалок нет.
- В `.tscn` — только корень сцены; все контролы строятся `_ready()`-кодом.
- Фазами управляет `GameController`, глобальное состояние — автолоад `Game`;
  сцены не переключают друг друга.
- Модалки и мини-игры — `Control`-скрипты на `PROCESS_MODE_ALWAYS` (D03/D11).

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
  --headless --path . --script tests/run_tests.gd` (или отдельные
  `tests/test_*.gd`).
- **Web smoke:** локальный `python3 -m http.server 8000 --directory build/web`.

## 8. Распределение файлов

| Владелец | Зона |
| --- | --- |
| Lane A (core) | `scripts/autoload/*`, `scripts/core/*`, `data/balance.json` |
| Lane B (entities) | `scripts/entities/*` (FileItem, Folder, Section, Packet, Request) |
| Lane C (core/systems) | `scripts/core/*` (FileRegistry, SlotManager, HourDirector, Economy), `scripts/systems/*` (AttackDirector, Shop, SaveManager) |
| Lane D (ui/minigames) | `scripts/ui/*`, `scripts/minigames/*`, dev-сцены, `strings_ru.json` |
| Общие (не трогать) | `project.godot`, `scenes/Main.tscn`, `scripts/main.gd`, `export_presets.cfg`, шрифты, git |
