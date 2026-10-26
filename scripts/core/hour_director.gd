class_name HourDirector
extends Node
## Единственный тикер часа (v2).
##
## Час — это бюджет файлов, окно спавна 75% часа, запросы по интервалу и атаки.
## «Мусорные»/шифровальщицкие пакеты и фишинговые запросы заменены
## мини-играми атак (§5.7); TCP-соединение — отдельная мини-игра-полоска.
##
## Важные правила:
## - приём занимает слот `in` + резервирует клетки фигуры в папке;
## - отправка занимает слот `out` после мини-игры, иначе запрос встаёт в
##   очередь «ОЖИДАНИЕ СЛОТА» (M15);
## - таймер запроса замирает, пока открыта ЕГО мини-игра и пока запрос в
##   очереди слота; время часа при этом идёт;
## - файлы после успешной отправки НЕ исчезают: возвращаются в папку и снова
##   доступны пулу запросов (cooldown — только из constants);
## - мини-игра отправки не ставит час на паузу (это делает только атака);
## - если час кончается с открытой мини-игрой отправки — она принудительно
##   закрывается (B5, вариант b): q=0, файлы открепляются, отправки нет.

signal packet_added(id: String)
signal packet_changed(id: String)
signal packet_removed(id: String)
## Пакет потерян по таймауту (перед удалением). UI может показать потерю.
signal packet_lost(id: String)
signal request_added(id: String)
signal request_changed(id: String)
signal request_removed(id: String)
## Запрос просрочен (перед cleanup). UI может показать потерю.
signal request_expired(id: String)
signal slot_changed
signal attack_added(id: String)
signal attack_changed(id: String)
signal attack_removed(id: String)
signal toast(text: String)
signal hour_finished(report: Dictionary)
signal show_minigame(game)
signal minigame_closed(req_id: String)
signal minigame_cancelled(req_id: String)
signal show_attack_minigame(game, kind: String)
signal attack_resolved(kind: String, success: bool, tier: int)
signal spawn_frozen(reason: String)
## TCP: показать мини-игру установления соединения.
## UI создаёт ConnectionGame и по завершении зовёт connection_finished().
signal show_connection(request_id: String, hour: int, successes: int)

const PACKET_SCRIPT := preload("res://scripts/entities/packet.gd")
const REQUEST_SCRIPT := preload("res://scripts/entities/request.gd")
const CONNECTION_SCRIPT := preload("res://scripts/entities/tcp_connection.gd")
const SLOT_MANAGER_SCRIPT := preload("res://scripts/core/slot_manager.gd")
const REGISTRY_SCRIPT := preload("res://scripts/core/file_registry.gd")
const ATTACK_SCRIPT := preload("res://scripts/systems/attack_director.gd")
const FACTORY := preload("res://scripts/minigames/minigame_factory.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")

const DEFAULT_HOUR_SECONDS := 300.0
const DEFAULT_RECV_INTERVAL := 12.0
const DEFAULT_SEND_INTERVAL := 20.0
const MAX_FILES_PER_HOUR := 20
const SPAWN_WINDOW_RATIO := 0.75
const SPAWN_JITTER := 0.2
const MAX_SPAWN_STEPS := 32
## Запросы не спавнятся в последние N секунд часа: игрок не успеет их закрыть.
const REQUEST_SPAWN_CUTOFF_SEC := 10.0
## Как часто пересчитываем «влезает ли фигура хоть в одну папку» (сек).
const FIT_CHECK_INTERVAL := 0.5
const REJECT_FINE_MONEY := -5
const REJECT_FINE_SLA := -5.0
const DEFAULT_PACKET_SLA_LOSS := 2.0
## UDP: штраф за потерянный пакет и пауза перед повтором (fallbacks для data).
const DEFAULT_UDP_FAIL_SLA := -3.0
const DEFAULT_UDP_RETRY_SEC := 4.0
const DEFAULT_UDP_SUCCESS_BASE := 0.40
const DEFAULT_UDP_SUCCESS_MAX := 0.80
## Минимальный зазор между попытками спавна запроса (анти-голодание H1).
const REQUEST_ATTEMPT_MIN_GAP := 3.0
const MAX_REQUIRED_FILES := 4
const TYPE_ORDER: Array[String] = ["text", "sound", "photo", "video"]
const DEFAULT_REQUEST_MIX := {"1": 0.76, "2": 0.24, "3": 0.0, "4": 0.0}
const DEFAULT_TYPE_WEIGHTS := {"text": 1.0, "sound": 0.0, "photo": 0.0, "video": 0.0}
## Fallback весов ТИПА файлов для required-слотов запроса (если нет JSON).
## Порядок: text, sound, photo, video.
const DEFAULT_REQUEST_TYPE_WEIGHTS := [
	[1.00, 0.00, 0.00, 0.00],
	[0.80, 0.20, 0.00, 0.00],
	[0.50, 0.50, 0.00, 0.00],
	[0.40, 0.30, 0.30, 0.00],
	[0.35, 0.35, 0.30, 0.00],
	[0.30, 0.30, 0.30, 0.10],
	[0.22, 0.23, 0.30, 0.25],
	[0.15, 0.25, 0.35, 0.25],
	[0.10, 0.15, 0.30, 0.45],
]

## Активные сущности часа.
var active_packets: Dictionary = {}
var active_requests: Dictionary = {}
## Активные TCP-соединения: id → TcpConnection. Каждое держит out-слот.
var active_connections: Dictionary = {}
var slots = null
var attack_director = null

## Бюджеты/спавн.
var hour: int = 1
var time_left: float = DEFAULT_HOUR_SECONDS
var hour_elapsed: float = 0.0
var running: bool = false
var paused: bool = false
var modal_open: bool = false
var time_scale: float = 1.0

var files_budget: int = 0
var files_spawned: int = 0
var requests_spawned: int = 0
var spawned_this_hour: int = 0
var carry_files: int = 0
var active_request_limit: int = 1
## Длительность текущего часа (кэш из start_hour; см. hour_duration()).
## 0 — ещё не вычислена, тогда используется _resolve_hour_seconds().
var _hour_duration: float = 0.0
var spawn_window: float = DEFAULT_HOUR_SECONDS * SPAWN_WINDOW_RATIO
var request_mix: Dictionary = DEFAULT_REQUEST_MIX.duplicate()
var type_weights: Dictionary = DEFAULT_TYPE_WEIGHTS.duplicate()
## Веса выбора типа файлов для required-слотов (text/sound/photo/video).
var request_type_weights: Dictionary = {"text": 1.0, "sound": 0.0, "photo": 0.0, "video": 0.0}

var spawn_recv_accum: float = 0.0
var spawn_send_accum: float = 0.0
var _recv_interval_current: float = DEFAULT_RECV_INTERVAL
var _send_interval_current: float = DEFAULT_SEND_INTERVAL
var _next_spawn_at: float = -1.0
var _spawn_frozen_notified: bool = false
## Момент последней попытки создать запрос (hour_elapsed). Нужен анти-голоданию.
var _last_request_attempt_t: float = -REQUEST_ATTEMPT_MIN_GAP

## Состояние/настройки.
var game = null
var registry = null
var rng = null
var successes_this_hour: int = 0
## Успешных TCP-соединений за забег (вход в формулу зоны ConnectionGame).
var connect_successes: int = 0
var shield_until: float = 0.0
var recv_disabled_until: float = 0.0
var send_disabled_until: float = 0.0
var channel_debuff_until: float = 0.0
## Папки, заблокированные мини-игрой «Карантин»: folder_id → hour_elapsed.
var blocked_folders: Dictionary = {}

## Инъекция фабрики для тестов: Callable(id, tier, seed, context) → Node|null.
var send_game_factory: Callable = Callable()

var _modal_count: int = 0
var _next_packet_num: int = 1
var _next_request_num: int = 1
var _next_connection_num: int = 1
var _order_counter: int = 0
var _registry_accum: float = 0.0
var _lost_check_accum: float = 0.0
## Троттлинг проверок «влезает ли фигура в папку» (D03/no_space).
var _fit_check_accum: float = 0.0
var _packet_fit_cache: Dictionary = {}
var _space_check_accum: float = 0.0
var _space_ok_cache: bool = true
var _no_space_notified: bool = false
var _finish_guard: bool = false
var _attack_paused: bool = false
## Текст последнего тоста директора. Main читает сразу после вызова, чтобы
## не дублировать отказ, который backend уже озвучил.
var last_toast_text: String = ""

var _start_money: int = 0
var _start_sla: float = 0.0
var _start_money_earned: int = 0
var _completed: int = 0
var _failed: int = 0
var _attacks_blocked: int = 0
var _attacks_failed: int = 0
var _udp_lost: int = 0
## Счётчики отчёта часа.
var requests_timed_out: int = 0
var requests_rejected: int = 0
var files_sent_this_hour: int = 0

## Тестовый крючок UDP-ролла: -1 — обычный рандом, 0.0 — успех, 1.0 — провал.
var udp_roll_override: float = -1.0

var _minigame = null
var _minigame_request_id: String = ""
var _send_queue: Array[String] = []
var _send_start_time_left: Dictionary = {}
var _send_start_timer_total: Dictionary = {}
var _processing_queue: bool = false


func _init() -> void:
	time_scale = _read_time_scale()


# --- жизненный цикл --------------------------------------------------------

func start_hour(p_hour: int) -> void:
	_bind()
	_clear_entities()
	hour = clampi(int(p_hour), 1, 24)
	# Строго до сброса счётчиков: не сеем заново при reload/continue.
	var seed_h1: bool = hour == 1 and requests_spawned == 0 \
		and registry != null and registry.files.is_empty()
	var def := _hour_def()
	_hour_duration = _resolve_hour_seconds()
	var base_files := maxi(0, int(def.get("files", 4)))
	# Ожидаемый темп файлов; жёсткого лимита количества нет — спавн идёт по
	# интервалу всё окно. Перенос между часами отключён.
	files_budget = base_files
	carry_files = 0
	files_spawned = 0
	requests_spawned = 0
	spawned_this_hour = 0
	active_request_limit = maxi(0, int(def.get("active_requests", 1)))
	request_mix = _dict_of(def.get("request_mix", DEFAULT_REQUEST_MIX))
	if request_mix.is_empty():
		request_mix = DEFAULT_REQUEST_MIX.duplicate()
	type_weights = _dict_of(def.get("type_weights", DEFAULT_TYPE_WEIGHTS))
	if type_weights.is_empty():
		type_weights = _default_type_weights(hour)
	request_type_weights = _dict_of(def.get("request_type_weights", {}))
	if request_type_weights.is_empty():
		request_type_weights = _default_request_type_weights(hour)
	spawn_window = _hour_duration * _spawn_window_ratio()

	time_left = _hour_duration
	hour_elapsed = 0.0
	spawn_recv_accum = 0.0
	spawn_send_accum = 0.0
	_lost_check_accum = 0.0
	_fit_check_accum = 0.0
	_packet_fit_cache.clear()
	_space_check_accum = 0.0
	_space_ok_cache = true
	_no_space_notified = false
	# Анти-голодание: первый запрос может появиться сразу, как только в папке
	# есть подходящий файл (а не через send_interval).
	_last_request_attempt_t = -REQUEST_ATTEMPT_MIN_GAP
	_recv_interval_current = _next_receive_interval()
	# H1: первый пакет приходит сразу, чтобы час не начинался с простоя.
	_next_spawn_at = 0.0 if hour == 1 else _recv_interval_current
	_spawn_frozen_notified = false
	_send_interval_current = _send_interval()
	_modal_count = 0
	modal_open = false
	paused = false
	_attack_paused = false
	successes_this_hour = 0
	shield_until = 0.0
	recv_disabled_until = 0.0
	send_disabled_until = 0.0
	channel_debuff_until = 0.0
	blocked_folders.clear()
	_send_queue.clear()
	_send_start_time_left.clear()
	_send_start_timer_total.clear()
	_running_reset_counters()

	slots = SLOT_MANAGER_SCRIPT.new()
	slots.changed.connect(_on_slots_changed)
	_ensure_attack_director()
	attack_director.reset(hour)

	running = true
	_finish_guard = false
	if seed_h1:
		_bootstrap_h1()
	slot_changed.emit()


## H1-затравка: один text-файл в первой папке + сразу запрос на него.
func _bootstrap_h1() -> void:
	if registry == null or not registry.files.is_empty():
		# Защита от двойного сида: если в реестре уже есть файлы (например,
		# seed, созданный reset_for_prep()), новый не создаём.
		return
	var folder_id := _first_folder_id()
	if folder_id.is_empty():
		return
	var file = registry.create_file(_make_file_name(), "text", folder_id)
	if file == null:
		return
	var req_id := _create_request(1, "tcp", [str(file.id)])
	if req_id.is_empty():
		return
	requests_spawned += 1
	_last_request_attempt_t = hour_elapsed


func _first_folder_id() -> String:
	if registry == null:
		return ""
	for section in registry.sections.values():
		for folder_id in section.folder_ids:
			if registry.folders.has(str(folder_id)):
				return str(folder_id)
	for folder_id in registry.folders.keys():
		return str(folder_id)
	return ""


## Сброс переноса неразобранных файлов. Вызывается на новом забеге/загрузке.
func reset_carry() -> void:
	carry_files = 0
	connect_successes = 0


## Чистое состояние директора для экрана подготовки перед H1.
##
## Выполняет обычный start_hour(1) (создаёт seed-файл H1), но затем убирает
## активные запросы/пакеты и все резервации required_by. В подготовке игрок
## не видит запросов, поэтому зарезервированный seed нельзя оставлять:
## «уничтожить содержимое» не смогло бы его удалить, а SLA списался бы.
## Сам запрос появится при старте часа — через starvation guard, либо через
## bootstrap, если игрок успел уничтожить seed и реестр опустел.
func reset_for_prep() -> void:
	_bind()
	# BUG A: счётчики спавна сбрасываем ДО start_hour(1). start_hour сеет seed
	# H1 только при requests_spawned == 0, а после сыгранного часа он > 0 —
	# иначе второй и последующие «Новые забеги» оставались без seed-файла в
	# подготовке (асимметрия с первым забегом).
	_reset_spawn_counters()
	start_hour(1)
	_clear_entities()
	# Чистое состояние подготовки: bootstrap-запрос снят, счётчики пусты.
	_reset_spawn_counters()
	if registry != null:
		for file in registry.files.values():
			if file != null:
				file.required_by = ""
	running = false


## Счётчики спавна, которые должны быть нулевыми перед/после подготовки.
func _reset_spawn_counters() -> void:
	requests_spawned = 0
	spawned_this_hour = 0
	_last_request_attempt_t = -REQUEST_ATTEMPT_MIN_GAP


func tick(delta: float) -> void:
	if not running or _finish_guard:
		return
	if paused or _attack_paused:
		return
	var dt := minf(maxf(delta, 0.0), 0.1) * maxf(0.01, time_scale)
	if dt <= 0.0:
		return
	_bind()
	hour_elapsed += dt
	time_left = maxf(0.0, time_left - dt)

	_tick_requests(dt)
	if not running or _finish_guard:
		return
	if not modal_open:
		_tick_packets(dt)
		if not running or _finish_guard:
			return
		_tick_spawns(dt)
		if not running or _finish_guard:
			return
		_tick_request_spawns(dt)
		if not running or _finish_guard:
			return
		_tick_attacks(dt)
		if not running or _finish_guard:
			return
	_tick_registry(dt)
	if not running or _finish_guard:
		return
	_tick_folder_blocks()
	if time_left <= 0.0:
		_finish_hour()


func set_paused(value: bool) -> void:
	paused = bool(value)


## Принудительная остановка часа при завершении забега (SLA=0).
## Не эмитит hour_finished: отчёт часа уже не нужен, итог показывает
## GameController. Закрывает мини-игру/очередь и снимает атаку, чтобы над
## экраном итогов не осталось живой модалки.
func stop_for_run_end() -> void:
	if _finish_guard:
		return
	_finish_guard = true
	running = false
	paused = true
	force_close_send_minigame()
	_send_queue.clear()
	set_modal_open(false)
	if attack_director != null:
		if attack_director.has_method("cancel_active"):
			attack_director.cancel_active()
		if attack_director.has_method("set_allow_spawn"):
			attack_director.set_allow_spawn(false)
	set_attack_paused(true)


func set_modal_open(value: bool) -> void:
	modal_open = bool(value)
	_modal_count = 1 if modal_open else 0


## Полная пауза часа на время мини-игры атаки (H6: ставится ДО показа окна).
## Дублируется в публичном `paused`, чтобы старый UI/Ambient видели паузу.
func set_attack_paused(value: bool) -> void:
	_attack_paused = bool(value)
	paused = bool(value)


func is_attack_paused() -> bool:
	return _attack_paused


func set_time_scale(value: float) -> void:
	time_scale = maxf(0.01, float(value))


func is_minigame_active() -> bool:
	# Пока TCP-запрос соединяется, открыта модалка мини-игры соединения.
	# Флаг мини-игры ещё не выставлен (_minigame == null), поэтому атаки
	# считали, что экран свободен, и могли наложить второй модал.
	for req in active_requests.values():
		if req != null and bool(req.get("connecting")):
			return true
	return _minigame != null


func has_packet(id: String) -> bool:
	return active_packets.has(id)


func has_request(id: String) -> bool:
	return active_requests.has(id)


func get_packet(id: String):
	return active_packets.get(id)


func get_request(id: String):
	return active_requests.get(id)


func get_connection(conn_id: String):
	return active_connections.get(str(conn_id))


## id соединения, которое сейчас обслуживает запрос ("" — нет).
func connection_id_for_request(req_id: String) -> String:
	var clean := str(req_id)
	if clean.is_empty():
		return ""
	for conn_id in active_connections.keys():
		var conn = active_connections[conn_id]
		if conn != null and str(conn.request_id) == clean:
			return str(conn_id)
	return ""


func get_attack(id: String):
	if attack_director == null:
		return null
	return attack_director.active_attacks.get(id)


# --- публичные расчёты для UI ----------------------------------------------

## Длительность текущего часа в секундах (кэш start_hour, иначе resolve).
func hour_duration() -> float:
	return _hour_seconds()


## Совместимый псевдоним: UI/Ambient могут звать публичный метод.
func hour_seconds() -> float:
	return _hour_seconds()


## Публичный геттер очереди отправки (для статуса UI).
func send_queue_count() -> int:
	return _send_queue.size()


func buffer_limit() -> int:
	return _buffer_limit()


func buffer_used() -> int:
	return _buffer_used()


func channel_factor() -> float:
	return _channel_factor()


func channel_load() -> float:
	if slots == null:
		return 0.0
	return ECONOMY.channel_load(hour, 0, _active_weights(), _upgrades())


## Шанс успешной UDP-отправки с учётом лота «UDP-повторитель».
func udp_success_chance() -> float:
	return ECONOMY.udp_success_chance(
		_upgrades(),
		_const_float("udp_success_base", DEFAULT_UDP_SUCCESS_BASE),
		_udp_step(),
		_const_float("udp_success_max", DEFAULT_UDP_SUCCESS_MAX)
	)


func max_slots() -> int:
	if slots == null:
		return 0
	return slots.max_slots()


func request_required_count(req_id: String) -> int:
	var req = active_requests.get(req_id)
	return _required_count(req)


## Конкретные файлы, которые требует запрос (в порядке required).
func request_required_ids(req_id: String) -> Array[String]:
	var out: Array[String] = []
	var req = active_requests.get(req_id)
	if req == null:
		return out
	for file_id in req.required:
		out.append(str(file_id))
	return out


func request_required_names(req_id: String) -> Array[String]:
	var out: Array[String] = []
	for file_id in request_required_ids(req_id):
		out.append(request_file_name(file_id))
	return out


## Отображаемое имя файла или «ПОТЕРЯН», если файла уже нет в реестре.
func request_file_name(file_id: String) -> String:
	if registry != null and registry.files.has(str(file_id)):
		var file = registry.files[str(file_id)]
		if file != null:
			return str(file.display_name())
	return "ПОТЕРЯН"


## required-файлы, которые ещё не прикреплены (id).
func request_missing(req_id: String) -> Array[String]:
	var out: Array[String] = []
	var req = active_requests.get(req_id)
	if req == null:
		return out
	for file_id in req.required:
		if not req.attached.has(str(file_id)):
			out.append(str(file_id))
	return out


func request_missing_names(req_id: String) -> Array[String]:
	var out: Array[String] = []
	for file_id in request_missing(req_id):
		out.append(request_file_name(file_id))
	return out


## v2-готовность: собраны все слоты, запрос не занят мини-игрой/очередью.
## Request.is_ready() остался legacy (проверяет TCP-connect) — не используем.
func is_request_ready(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	return _request_ready(req)


func is_request_queued(req_id: String) -> bool:
	return _send_queue.has(str(req_id))


# --- приём -----------------------------------------------------------------

func spawn_packet_now(type_override: String = "", protocol_override: String = "") -> String:
	return _spawn_random_packet(type_override, protocol_override)


func _spawn_random_packet(type_override: String = "", protocol_override: String = "") -> String:
	var file_type := str(type_override)
	var forced_shape := ""
	if file_type.is_empty():
		# Нормальный спавн: берём только реально влезающую форму, иначе пакет
		# застрянет в буфере с замороженным таймером.
		var fitting := _pick_fitting_spawn()
		if fitting.is_empty():
			return ""
		file_type = str(fitting.get("type", ""))
		forced_shape = str(fitting.get("shape", ""))
	if _type_def(file_type).is_empty() and not TYPE_ORDER.has(file_type):
		# Явный невалидный override (dev/тесты) — как раньше, дефолт text.
		file_type = "text"
		forced_shape = ""
	var protocol := str(protocol_override)
	if protocol.is_empty():
		protocol = "tcp"
	var def := _type_def(file_type)
	var p = PACKET_SCRIPT.new()
	p.id = "pkt_%d" % _next_packet_num
	_next_packet_num += 1
	p.type = file_type
	p.protocol = protocol.to_lower()
	p.file_name = _make_file_name()
	p.timer_total = ECONOMY.packet_timer(hour, _upgrades())
	p.time_left = p.timer_total
	p.size_kb = int(def.get("size_kb", 0))
	p.state = PACKET_SCRIPT.STATE_WAITING
	p.order = _order_counter
	_order_counter += 1
	p.shape_id = forced_shape if not forced_shape.is_empty() \
		else REGISTRY_SCRIPT.shape_for_type(file_type, rng)
	p.rotation = 0 if not forced_shape.is_empty() else _randi_range(0, 3)
	p.icon_id = _randi_range(0, REGISTRY_SCRIPT.FILE_ICON_COUNT - 1)
	p.shape_cells = REGISTRY_SCRIPT.shape_cells(p.shape_id, p.rotation)
	if not _add_packet(p):
		return ""
	_play_sfx(&"tick")
	return p.id


## Выбрать тип по type_weights среди типов, у которых есть влезающая форма.
## {} — ни один доступный тип/форма не влезает (пакет не создаём).
func _pick_fitting_spawn() -> Dictionary:
	if registry == null:
		var fallback_type := _pick_type()
		return {"type": fallback_type, "shape": REGISTRY_SCRIPT.shape_for_type(fallback_type, rng)}
	if not registry.has_method("shape_for_type_fitting"):
		return {}
	var candidates: Array = []
	var weights: Array = []
	var total := 0.0
	for type_id in _type_pool():
		var shape := str(registry.shape_for_type_fitting(str(type_id), blocked_folders, rng))
		if shape.is_empty():
			continue
		var weight := maxf(0.0, float(type_weights.get(str(type_id), 0.0)))
		candidates.append({"type": str(type_id), "shape": shape})
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return {}
	if total <= 0.0:
		return candidates[0]
	var roll := _randf() * total
	var acc := 0.0
	for i in range(candidates.size()):
		acc += float(weights[i])
		if roll < acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


## Приём пакета в папку. origin=(-1,-1) — auto-fit по фигуре.
func receive_packet(packet_id: String, folder_id: String,
		origin: Vector2i = Vector2i(-1, -1), rotation: int = -1) -> bool:
	var packet = active_packets.get(packet_id)
	if packet == null or not packet.can_receive():
		return false
	if registry == null or not registry.folders.has(folder_id):
		_emit_toast("Нет такой папки")
		return false
	if is_folder_locked(folder_id):
		_emit_toast("Папка заблокирована")
		return false
	if hour_elapsed < recv_disabled_until:
		_emit_toast("Приём временно недоступен")
		return false
	if slots == null:
		return false
	var slot_index: int = int(slots.reserve("in", packet_id, packet.file_name))
	if slot_index < 0:
		_emit_toast("ВСЕ КАНАЛЫ ЗАНЯТЫ")
		return false

	var use_rotation := int(packet.rotation) if rotation < 0 else posmod(int(rotation), 4)
	var reserved: Dictionary = {}
	if origin.x < 0 or origin.y < 0:
		reserved = registry.auto_reserve_packet(packet_id, folder_id, packet.shape_id, use_rotation)
	else:
		if registry.reserve_packet(packet_id, folder_id, packet.shape_id, use_rotation, origin):
			reserved = registry.get_reservation(packet_id)
	if reserved.is_empty() or not bool(reserved.get("ok", false)):
		slots.release(slot_index)
		_emit_toast("НЕТ МЕСТА В ПАПКЕ")
		return false

	packet.shape_id = str(reserved.get("shape_id", packet.shape_id))
	packet.rotation = int(reserved.get("rotation", packet.rotation))
	packet.shape_cells = REGISTRY_SCRIPT.shape_cells(packet.shape_id, packet.rotation)
	var def := _type_def(str(packet.type))
	var duration := ECONOMY.recv_transfer_time(def, _channel_factor(), _speed_level())
	packet.state = PACKET_SCRIPT.STATE_LOADING
	packet.loading_folder_id = folder_id
	packet.loading_progress = 0.0
	packet.loading_duration = maxf(0.1, duration)
	packet_changed.emit(packet_id)
	_play_sfx(&"drop")
	return true


# --- запросы ---------------------------------------------------------------

## Тестовый/dev-спавн: по умолчанию TCP (protocol_override="").
## Протокол можно форсировать: spawn_request_now(1, "udp").
func spawn_request_now(count_override: int = 0, protocol_override: String = "") -> String:
	return _spawn_random_request(true, int(count_override), protocol_override)


## Пул файлов, из которых можно собрать запрос: лежат в разблокированной
## папке, не прикреплены и ещё не затребованы другим активным запросом.
func _request_file_pool() -> Array:
	var pool: Array = []
	if registry == null:
		return pool
	var claimed: Dictionary = {}
	for req in active_requests.values():
		for file_id in req.required:
			claimed[str(file_id)] = true
	for file in registry.files.values():
		if str(file.location) != "folder":
			continue
		if not str(file.attached_request).is_empty():
			continue
		if claimed.has(str(file.id)):
			continue
		if not str(file.required_by).is_empty():
			continue
		if not file.is_available():
			continue
		if is_folder_locked(str(file.folder_id)):
			continue
		pool.append(file)
	return pool


## Выбрать N конкретных файлов взвешенно по ТИПУ (request_type_weights),
## без повторов.
## Если в конфиге есть положительные веса — берём ТОЛЬКО файлы этих типов;
## нет ни одного такого файла в пуле → [] (запрос не создаётся).
## Uniform fallback — только когда конфиг весов пуст/все нули.
func _pick_request_files(pool: Array, count: int) -> Array[String]:
	var out: Array[String] = []
	var want := clampi(int(count), 1, MAX_REQUIRED_FILES)
	if pool.is_empty():
		return out
	var allowed := _weighted_types()
	var candidates: Array = []
	if allowed.is_empty():
		candidates = pool.duplicate()
	else:
		for item in pool:
			if allowed.has(_pool_item_type(item)):
				candidates.append(item)
	if candidates.is_empty():
		return out
	want = mini(want, candidates.size())
	while out.size() < want and not candidates.is_empty():
		var idx := _pick_weighted_file_index(candidates)
		out.append(_pool_item_id(candidates[idx]))
		candidates.remove_at(idx)
	return out


## Типы с положительным весом в request_type_weights (пусто — веса не заданы).
func _weighted_types() -> Array:
	var out: Array = []
	for type_id in TYPE_ORDER:
		if float(request_type_weights.get(type_id, 0.0)) > 0.0:
			out.append(type_id)
	return out


## id элемента пула (FileItem или Dictionary).
func _pool_item_id(item) -> String:
	if item is Dictionary:
		return str((item as Dictionary).get("id", ""))
	return str(item.id)


## Тип элемента пула (FileItem или Dictionary).
func _pool_item_type(item) -> String:
	if item is Dictionary:
		return str((item as Dictionary).get("type", ""))
	return str(item.type)


## Индекс файла в пуле по весам типов. Fallback — uniform.
func _pick_weighted_file_index(items: Array) -> int:
	var total := 0.0
	var weights: Array = []
	for item in items:
		var w := maxf(0.0, float(request_type_weights.get(_pool_item_type(item), 0.0)))
		weights.append(w)
		total += w
	if total <= 0.0:
		return _randi_range(0, items.size() - 1)
	var roll := _randf() * total
	var acc := 0.0
	var last_positive := -1
	for i in range(items.size()):
		var w := float(weights[i])
		if w <= 0.0:
			continue
		last_positive = i
		acc += w
		if roll < acc:
			return i
	if last_positive >= 0:
		return last_positive
	return _randi_range(0, items.size() - 1)


func _shuffle_array(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func _spawn_random_request(force: bool = false, count_override: int = 0,
		protocol_override: String = "") -> String:
	if registry == null:
		return ""
	if not force:
		if hour_elapsed >= _hour_duration - REQUEST_SPAWN_CUTOFF_SEC:
			return ""
		if _normal_request_count() >= active_request_limit:
			return ""
	var pool := _request_file_pool()
	if pool.is_empty():
		return ""
	var count := count_override if count_override > 0 else _roll_required_count()
	count = clampi(count, 1, MAX_REQUIRED_FILES)
	count = mini(count, pool.size())
	if count <= 0:
		return ""
	var file_ids := _pick_request_files(pool, count)
	if file_ids.is_empty():
		return ""
	var req_id := _create_request(count, _request_spawn_protocol(force, protocol_override), file_ids)
	if req_id.is_empty():
		return ""
	requests_spawned += 1
	return req_id


## Протокол нового запроса: override → как задано; force/dev → TCP;
## нормальный спавн → UDP с шансом constants.udp_request_ratio.
func _request_spawn_protocol(force: bool, protocol_override: String) -> String:
	var forced := _clean_protocol(protocol_override)
	if not forced.is_empty():
		return forced
	if force:
		return "tcp"
	var ratio := clampf(_const_float("udp_request_ratio", 0.35), 0.0, 1.0)
	return "udp" if _randf() < ratio else "tcp"


## Legacy-хелпер: создать запрос на переданные файлы (уже подключённый TCP).
func _make_request(files: Array, protocol: String, _is_attack: bool,
		_attack_kind: String, _attack_id: String) -> String:
	var file_ids: Array[String] = []
	for file in files:
		if file != null:
			file_ids.append(str(file.id))
	var count := maxi(1, file_ids.size())
	return _create_request(count, protocol, file_ids, true)


## Создать запрос с КОНКРЕТНЫМИ required-файлами.
## file_ids пустой → попытаться выбрать из пула (count будет зажат).
## connected=false — для TCP потребуется мини-игра соединения.
func _create_request(count: int, protocol: String, file_ids: Array = [],
		p_connected: bool = false) -> String:
	if registry == null:
		return ""
	var ids: Array[String] = []
	for file_id in file_ids:
		if ids.size() >= MAX_REQUIRED_FILES:
			break
		if registry.files.has(str(file_id)) and not ids.has(str(file_id)):
			ids.append(str(file_id))
	if ids.is_empty():
		var pool := _request_file_pool()
		if pool.is_empty():
			return ""
		var want := clampi(int(count), 1, MAX_REQUIRED_FILES)
		ids = _pick_request_files(pool, mini(want, pool.size()))
	if ids.is_empty():
		return ""
	var req = REQUEST_SCRIPT.new()
	req.id = "req_%d" % _next_request_num
	_next_request_num += 1
	req.protocol = _clean_protocol(protocol)
	req.timer_total = ECONOMY.request_timer(hour, _upgrades())
	req.time_left = req.timer_total
	req.client_name = _pick_org()
	req.client_id = "id_%04X" % _next_request_num
	req.avatar = req.client_name.substr(0, 1).to_upper()
	req.is_attack = false
	req.attack_kind = ""
	req.attack_id = ""
	req.required.clear()
	for file_id in ids:
		req.required.append(file_id)
		var file = registry.files.get(str(file_id))
		if file != null and (file.required_by.is_empty() or file.required_by == req.id):
			file.required_by = req.id
	req.attached.clear()
	req.required_types = _types_for_ids(ids)
	# TCP всегда стартует как TCP_NEW: соединения ещё нет. Legacy-флаг
	# p_connected осмыслен только для UDP (там соединение не нужно).
	req.connected = bool(p_connected) and req.protocol != "tcp"
	req.connection_id = ""
	req.connecting = false
	req.connect_attempts = 0
	req.udp_failures = 0
	req.udp_retry_until = 0.0
	req.set_meta("required_count", ids.size())
	req.set_meta("queued", false)
	active_requests[req.id] = req
	request_added.emit(req.id)
	_play_sfx(&"request_ready")
	return req.id


func _types_for_ids(file_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if registry == null:
		return out
	for file_id in file_ids:
		var file = registry.files.get(str(file_id))
		if file != null:
			out.append(str(file.type))
	return out


func attach_file(req_id: String, file_id: String) -> bool:
	last_toast_text = ""
	var req = active_requests.get(req_id)
	if req == null or registry == null:
		return false
	# TCP: контейнер можно собирать только через установленное соединение.
	if str(req.protocol) == "tcp" and not req.has_connection():
		_emit_toast("СНАЧАЛА УСТАНОВИТЕ СОЕДИНЕНИЕ")
		return false
	if req.sending or req.minigame_active or req.connecting or _send_queue.has(req_id):
		return false
	if req.attached.has(file_id):
		return true
	if not req.required.has(file_id):
		var missing := request_missing(req_id)
		var shown := file_id
		if not missing.is_empty():
			shown = str(missing[0])
		_emit_toast("Нужен файл: %s" % request_file_name(shown))
		return false
	var need := _required_count(req)
	if req.attached.size() >= need:
		_emit_toast("Контейнер заполнен")
		return false
	var file = registry.files.get(file_id)
	if file == null:
		return false
	if is_folder_locked(str(file.folder_id)):
		_emit_toast("Папка заблокирована")
		return false
	if str(file.location) == "table":
		_emit_toast("Файл на столе — сначала верните его в папку")
		return false
	if not str(file.attached_request).is_empty() and str(file.attached_request) != req_id:
		_emit_toast("Файл уже прикреплён к другому запросу")
		return false
	if not registry.attach_file(file_id, req_id):
		return false
	req.attached.append(file_id)
	# M4: required_types описывает типы required-слотов, а не порядок вложений.
	request_changed.emit(req_id)
	return true


func detach_file(req_id: String, file_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null or registry == null:
		return false
	if req.sending or req.minigame_active or req.connecting or _send_queue.has(req_id):
		return false
	if not req.attached.has(file_id):
		return false
	if registry.files.has(file_id):
		registry.detach_file(file_id)
	req.attached.erase(file_id)
	# M4: порядок вложений не должен переписывать типы required-слотов.
	request_changed.emit(req_id)
	return true


func reject_request(req_id: String) -> bool:
	last_toast_text = ""
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if req.sending or req.minigame_active or req.connecting:
		_emit_toast("Запрос уже в работе")
		return false
	_add_money(REJECT_FINE_MONEY)
	_add_sla(REJECT_FINE_SLA)
	_failed += 1
	requests_rejected += 1
	_add_stat("failed", 1)
	_emit_toast("Запрос отклонён: −5 $, −5 SLA")
	_cleanup_request(req_id, true)
	return true


## Legacy: соединения пакетов нет.
func connect_packet(_packet_id: String) -> bool:
	return false


## Начать установку TCP-соединения (мини-игра «полоска»).
## Контейнер собирать не обязательно: соединение первично. Зато нужен
## свободный слот — его займёт соединение.
func connect_request(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if not running or _finish_guard:
		return false
	if req.protocol != "tcp" or req.connected or req.connecting:
		return false
	if req.has_connection():
		return false
	if req.sending or req.minigame_active or _send_queue.has(req_id):
		return false
	# C1/C2: пока любая модалка владеет экраном, второй мини-игры не создаём.
	if modal_open:
		_emit_toast("Сначала закройте текущее окно")
		return false
	if _minigame != null:
		_emit_toast("Сначала закройте мини-игру")
		return false
	if hour_elapsed < send_disabled_until:
		_emit_toast("Отправка временно недоступна")
		return false
	if hour_elapsed < req.connect_cooldown_until:
		_emit_toast("СОЕДИНЕНИЕ: ПОВТОР ЧЕРЕЗ %d с" % int(ceil(req.connect_cooldown_until - hour_elapsed)))
		return false
	if slots == null or int(slots.free_count()) <= 0:
		_emit_toast("ВСЕ КАНАЛЫ ЗАНЯТЫ · ОТКЛЮЧИТЕ СЛОТ")
		return false
	return _begin_connection(req)


## Открыть мини-игру соединения. Возвращает false, если она уже идёт.
func _begin_connection(req) -> bool:
	if req == null or req.connected or req.connecting:
		return false
	req.connecting = true
	req.connect_attempts += 1
	request_changed.emit(str(req.id))
	show_connection.emit(str(req.id), hour, connect_successes)
	return true


## UI закрыл мини-игру соединения. missed=true — промах (штраф SLA и 8 с),
## missed=false (Esc/отмена) — только 4 с паузы, без штрафа.
## Совместимость: старый вызов с двумя аргументами трактуется как отмена.
##
## Успех только создаёт TcpConnection и занимает out-слот: мини-игра отправки
## сама не запускается (её открывает start_send).
func connection_finished(req_id: String, success: bool, missed: bool = false) -> bool:
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if not req.connecting:
		return false
	req.connecting = false
	if not bool(success):
		if bool(missed):
			req.connect_cooldown_until = hour_elapsed + 8.0
			_add_sla(-4.0)
		else:
			req.connect_cooldown_until = hour_elapsed + 4.0
		request_changed.emit(req_id)
		_emit_toast("СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО")
		return true

	# Слот могли занять, пока шла мини-игра: тогда соединения не будет.
	var conn = _create_connection(req)
	if conn == null:
		_emit_toast("НЕТ СВОБОДНОГО СЛОТА")
		request_changed.emit(req_id)
		return true

	req.connection_id = str(conn.id)
	req.connected = true
	req.slot_reserved = true
	req.connecting = false
	req.connect_cooldown_until = 0.0
	connect_successes += 1
	request_changed.emit(req_id)
	slot_changed.emit()
	return true


## Создать TcpConnection и занять под него out-слот.
## null — свободного слота нет (гонка между проверкой и успехом).
func _create_connection(req):
	if req == null or slots == null:
		return null
	if int(slots.free_count()) <= 0:
		return null
	var conn = CONNECTION_SCRIPT.new()
	conn.id = "conn_%d" % _next_connection_num
	conn.client_name = str(req.client_name)
	conn.client_id = str(req.client_id)
	conn.ip = _random_ip()
	conn.request_id = str(req.id)
	conn.hour = hour
	conn.connected_at = hour_elapsed
	var slot_index: int = int(slots.reserve(
		"out", conn.id, conn.client_name, "tcp_connection", conn.ip, true, str(req.id)
	))
	if slot_index < 0:
		return null
	conn.slot_index = slot_index
	_next_connection_num += 1
	active_connections[conn.id] = conn
	return conn


## Соединение живо и всё ещё держит свой out-слот.
func _connection_open(conn_id: String) -> bool:
	var key := str(conn_id)
	var conn = active_connections.get(key)
	if conn == null or slots == null:
		return false
	var slot = slots.get_slot(int(conn.slot_index))
	if slot == null or not bool(slot.occupied):
		return false
	if str(slot.entity_id) != str(conn.id):
		return false
	return str(slot.kind) == "tcp_connection"


## Закрыть соединение и освободить его слот (без тоста и без открепления
## файлов — это делает вызывающая сторона).
func _release_connection(conn_id: String) -> bool:
	var key := str(conn_id)
	var conn = active_connections.get(key)
	if conn == null:
		return false
	active_connections.erase(key)
	var req_id := str(conn.request_id)
	var req = active_requests.get(req_id) if not req_id.is_empty() else null
	if slots != null:
		var released := false
		var slot = slots.get_slot(int(conn.slot_index))
		if slot != null and bool(slot.occupied) and str(slot.entity_id) == str(conn.id):
			released = bool(slots.release(int(conn.slot_index)))
		if not released:
			slots.release_by_entity(str(conn.id))
	if req != null:
		if str(req.connection_id) == key:
			req.connection_id = ""
		req.connected = false
		req.slot_reserved = false
		req.sending = false
		req.send_progress = 0.0
		_send_queue.erase(req_id)
		_send_start_time_left.erase(req_id)
		_send_start_timer_total.erase(req_id)
		req.set_meta("queued", false)
		request_changed.emit(req_id)
	slot_changed.emit()
	return true


## Игрок закрыл соединение: мгновенно, без проверок и мини-игр.
## Запрос остаётся активным (таймер идёт), файлы возвращаются в папки.
func disconnect_connection(conn_id: String) -> bool:
	var key := str(conn_id)
	var conn = active_connections.get(key)
	if conn == null:
		return false
	var req_id := str(conn.request_id)
	var req = active_requests.get(req_id) if not req_id.is_empty() else null
	if req != null:
		# Прерываем передачу без выплаты и без расхода файлов.
		if req.sending:
			req.sending = false
			req.send_progress = 0.0
			_send_queue.erase(req_id)
			_send_start_time_left.erase(req_id)
			_send_start_timer_total.erase(req_id)
			req.set_meta("queued", false)
		if req.minigame_active:
			if _minigame_request_id == req_id:
				force_close_send_minigame()
			else:
				req.minigame_active = false
				req.quality = 0.0
				request_changed.emit(req_id)
		if registry != null:
			for file_id in req.attached.duplicate():
				if registry.files.has(str(file_id)):
					registry.detach_file(str(file_id))
		req.attached.clear()
		req.connected = false
		req.connection_id = ""
		req.slot_reserved = false
		req.set_meta("queued", false)
	_release_connection(key)
	_emit_toast("СОЕДИНЕНИЕ ЗАКРЫТО · СЛОТ СВОБОДЕН")
	return true


## Закрыть соединение, привязанное к запросу (если оно есть).
func disconnect_request(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null:
		return false
	var conn_id := str(req.connection_id)
	if conn_id.is_empty():
		conn_id = connection_id_for_request(req_id)
	if conn_id.is_empty():
		return false
	return disconnect_connection(conn_id)


## UDP-провал в конце передачи: без выплаты и без расхода файлов.
## Запрос остаётся активным и получает 4-секундный кулдаун повтора.
func _handle_udp_failure(req) -> void:
	if req == null:
		return
	var req_id := str(req.id)
	var sla_fine := _const_float("udp_fail_sla", DEFAULT_UDP_FAIL_SLA)
	var retry_sec := _const_float("udp_retry_cooldown_sec", DEFAULT_UDP_RETRY_SEC)
	req.udp_failures += 1
	req.udp_retry_until = hour_elapsed + retry_sec
	req.sending = false
	req.send_progress = 0.0
	req.slot_reserved = false
	req.set_meta("queued", false)
	_send_queue.erase(req_id)
	_send_start_time_left.erase(req_id)
	_send_start_timer_total.erase(req_id)
	_add_sla(sla_fine)
	if game != null:
		game.streak = 0
	_udp_lost += 1
	_add_stat("udp_lost", 1)
	if slots != null:
		slots.release_by_entity(req_id)
	request_changed.emit(req_id)
	var loss := int(roundf(absf(sla_fine)))
	_emit_toast("UDP: ПАКЕТ ПОТЕРЯН · −%d SLA · ПОВТОР ЧЕРЕЗ %d с" % [loss, int(roundf(retry_sec))])


## Ролл UDP: true — пакет дошёл. udp_roll_override подменяет randf() для тестов.
## Третья попытка (udp_failures >= 2) гарантированно успешна: override может
## форсировать провал только на первых двух попытках.
func _roll_udp_success(req) -> bool:
	if req == null:
		return true
	if int(req.udp_failures) >= 2:
		return true
	var chance := udp_success_chance()
	var roll := _randf()
	if udp_roll_override >= 0.0:
		roll = clampf(udp_roll_override, 0.0, 0.999999)
	return roll < chance


## Валидный IPv4 из rng: последний октет 1..254, без 127/8 и 169.254/16.
func _random_ip() -> String:
	for _i in range(16):
		var a := _randi_range(1, 223)
		if a == 127:
			continue
		var b := _randi_range(0, 255)
		if a == 169 and b == 254:
			continue
		var c := _randi_range(0, 255)
		var d := _randi_range(1, 254)
		return "%d.%d.%d.%d" % [a, b, c, d]
	return "203.0.113.%d" % _randi_range(1, 254)


func _send_ready_error(req) -> String:
	if req == null:
		return "Контейнер не собран"
	var need := _required_count(req)
	if need <= 0 or req.attached.size() < need:
		return "Контейнер не собран"
	if not _attached_files_valid(req):
		return "Файл контейнера недоступен"
	return ""


func is_request_connected(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	return req != null and bool(req.connected)


func set_request_protocol(req_id: String, protocol: String) -> bool:
	last_toast_text = ""
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if req.sending or req.minigame_active or req.connecting or _send_queue.has(req_id):
		return false
	var clean := _clean_protocol(protocol)
	if clean.is_empty():
		return false
	if clean == req.protocol:
		return true
	# Любой протокол с уже прикреплёнными файлами меняем только после
	# открепления: TCP без connection_id с attached нарушает инвариант.
	if not req.attached.is_empty():
		_emit_toast("СНАЧАЛА ОТКРЕПИТЕ ФАЙЛЫ")
		return false
	# Активное TCP-соединение не даёт сменить протокол.
	if req.connected or req.has_connection():
		return false
	if clean == "tcp":
		# UDP → TCP: соединение ещё нужно установить, retry UDP сбрасываем.
		req.udp_retry_until = 0.0
	req.protocol = clean
	request_changed.emit(req_id)
	return true


## Явная отправка запроса. Автостарта при attach_file больше нет.
## TCP: соединение должно быть уже установлено (start_send его не создаёт).
func start_send(req_id: String) -> bool:
	last_toast_text = ""
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if not running or _finish_guard:
		return false
	if req.sending or req.minigame_active or req.connecting or _send_queue.has(req_id):
		return false
	# C1/C2: модалка (атака/отправка/соединение) уже занимает экран.
	if modal_open:
		_emit_toast("Сначала закройте текущее окно")
		return false
	if _minigame != null:
		_emit_toast("Сначала закройте мини-игру")
		return false
	if hour_elapsed < send_disabled_until:
		_emit_toast("Отправка временно недоступна")
		return false
	if req.protocol == "tcp":
		if not req.has_connection():
			_emit_toast("СНАЧАЛА УСТАНОВИТЕ СОЕДИНЕНИЕ")
			return false
		if hour_elapsed < req.connect_cooldown_until:
			_emit_toast("СОЕДИНЕНИЕ: ПОВТОР ЧЕРЕЗ %d с" % int(ceil(req.connect_cooldown_until - hour_elapsed)))
			return false
	if req.protocol == "udp" and hour_elapsed < req.udp_retry_until:
		_emit_toast("UDP: ПОВТОР ЧЕРЕЗ %d с" % maxi(1, int(ceil(req.udp_retry_until - hour_elapsed))))
		return false
	var need := _required_count(req)
	if need <= 0 or req.attached.size() < need:
		_emit_toast("НЕ ВСЕ ФАЙЛЫ ПРИКРЕПЛЕНЫ · %d/%d" % [req.attached.size(), need])
		return false
	if not _attached_files_valid(req):
		_emit_toast("ФАЙЛ КОНТЕЙНЕРА НЕДОСТУПЕН")
		return false
	return _launch_send_minigame(req_id)


## Собранный запрос проходит в обычную мини-игру отправки.
func _launch_send_minigame(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null:
		return false
	var problem := _send_ready_error(req)
	if not problem.is_empty():
		_emit_toast(problem)
		return false
	var types := _attached_types(req)
	var selection: Dictionary = ECONOMY.send_minigame_for(types)
	req.send_sum = int(selection.get("sum", 0))
	req.minigame_id = str(selection.get("id", "dots"))
	req.minigame_tier = clampi(int(selection.get("tier", 1)), 1, 4)
	req.minigame_active = true
	request_changed.emit(req_id)

	var context := {
		"request_id": req_id,
		"client_name": req.client_name,
		"types": types,
		"sum": req.send_sum,
		"protocol": req.protocol,
		"reward_text": "КОНТЕЙНЕР УХОДИТ",
		"briefing": true,
	}
	var seed_value := _randi_range(1, 2147483646)
	var game_node = null
	if send_game_factory.is_valid():
		game_node = send_game_factory.call(req.minigame_id, req.minigame_tier, seed_value, context)
	else:
		game_node = FACTORY.create_send(req.minigame_id, req.minigame_tier, seed_value, context)
	if game_node == null:
		# Фабрика ещё не готова: не блокируем игрока, качество среднее.
		req.minigame_active = false
		req.quality = 0.5
		request_changed.emit(req_id)
		_emit_toast("Мини-игра недоступна: качество 50%")
		_start_send_after_minigame(req_id)
		return true

	_minigame = game_node
	_minigame_request_id = req_id
	if game_node.has_signal("finished"):
		game_node.finished.connect(_on_send_minigame_finished)
	if game_node is Node and game_node.get_parent() == null:
		add_child(game_node)
	show_minigame.emit(game_node)
	return true


func _on_send_minigame_finished(quality: float) -> void:
	var req_id := _minigame_request_id
	_clear_send_game_node()
	var req = active_requests.get(req_id)
	if req == null:
		return
	req.minigame_active = false
	req.quality = clampf(float(quality), 0.0, 1.0)
	# Слишком грязный результат: передача не начинается. Файлы остаются в
	# контейнере, соединение не трогаем — игрок жмёт ОТПРАВИТЬ ещё раз.
	if req.quality < _const_float("send_quality_min", 0.45):
		req.sending = false
		req.set_meta("queued", false)
		request_changed.emit(req_id)
		if running and not _finish_guard:
			_emit_toast("НИЗКОЕ КАЧЕСТВО · ОТПРАВКА ОТМЕНЕНА · ПОВТОРИТЕ")
		return
	request_changed.emit(req_id)
	if not running or _finish_guard:
		return
	_start_send_after_minigame(req_id)


## После мини-игры: TCP использует слот уже открытого соединения; UDP
## слот не занимает и в очередь не встаёт — отправка стартует сразу.
func _start_send_after_minigame(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null or req.sending:
		return
	if str(req.protocol) == "tcp":
		var conn_id := str(req.connection_id)
		if conn_id.is_empty() or not _connection_open(conn_id):
			_emit_toast("СНАЧАЛА УСТАНОВИТЕ СОЕДИНЕНИЕ")
			return
		req.slot_reserved = true
		req.set_meta("queued", false)
		_begin_send(req_id)
		return
	if str(req.protocol) == "udp":
		req.slot_reserved = false
		req.set_meta("queued", false)
		_begin_send(req_id)
		return
	if slots == null:
		_queue_request(req_id)
		return
	var slot_index: int = int(slots.reserve("out", req_id, req.client_name, "request"))
	if slot_index < 0:
		_queue_request(req_id)
		return
	req.slot_reserved = true
	req.set_meta("queued", false)
	_begin_send(req_id)


func _queue_request(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null:
		return
	# Страховка: UDP никогда не занимает out-слот и не стоит в очереди.
	if str(req.protocol) == "udp":
		req.set_meta("queued", false)
		req.slot_reserved = false
		_begin_send(req_id)
		return
	req.sending = false
	req.slot_reserved = false
	req.set_meta("queued", true)
	if not _send_queue.has(req_id):
		_send_queue.append(req_id)
	request_changed.emit(req_id)
	_emit_toast("ОЖИДАНИЕ СЛОТА")


func _begin_send(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null or req.sending:
		return
	var factor := _channel_factor()
	var duration := 0.0
	var base_sum := 0.0
	var n := 0
	for file_id in req.attached:
		var file = registry.files.get(str(file_id)) if registry != null else null
		if file == null:
			continue
		var def := _type_def(str(file.type))
		duration += ECONOMY.send_transfer_time(def, factor, _speed_level(), req.protocol)
		base_sum += float(def.get("base_pay", 0))
		n += 1
	if n == 0:
		_cleanup_request(req_id, true)
		return
	req.send_duration = maxf(0.1, duration)
	req.send_base_sum = base_sum
	req.send_progress = 0.0
	req.sending = true
	req.slot_reserved = (str(req.protocol) == "tcp")
	req.set_meta("queued", false)
	_send_start_time_left[req_id] = float(req.time_left)
	_send_start_timer_total[req_id] = float(req.timer_total)
	request_changed.emit(req_id)
	_play_sfx(&"modem")
	_emit_toast("Отправка началась")


func _process_send_queue() -> void:
	if _processing_queue or not running or slots == null:
		return
	if _send_queue.is_empty():
		return
	_processing_queue = true
	for req_id in _send_queue.duplicate():
		if not active_requests.has(req_id):
			_send_queue.erase(req_id)
			continue
		var req = active_requests[req_id]
		# Страховка: UDP не занимает out-слот — стартует сразу.
		if str(req.protocol) == "udp":
			_send_queue.erase(req_id)
			req.set_meta("queued", false)
			req.slot_reserved = false
			_begin_send(req_id)
			continue
		var slot_index: int = int(slots.reserve("out", req_id, req.client_name, "request"))
		if slot_index < 0:
			break
		_send_queue.erase(req_id)
		req.set_meta("queued", false)
		req.slot_reserved = true
		_begin_send(req_id)
	_processing_queue = false


# --- атаки -----------------------------------------------------------------

func spawn_attack_now(kind: String = "") -> String:
	if attack_director == null:
		_ensure_attack_director()
	return attack_director.spawn_attack(kind)


## Legacy-методы карточек атак: безопасные заглушки (UI-волна их удалит).
func destroy_attack(_id: String) -> bool:
	return false


func quarantine_attack(_id: String) -> bool:
	return false


func destroy_attack_packet(_packet_id: String) -> bool:
	return false


func destroy_attack_file(_file_id: String) -> bool:
	return false


func spawn_junk_packet(_attack_id: String) -> String:
	return ""


func spawn_ransomware_packet(_attack_id: String) -> String:
	return ""


func spawn_phishing_request(_attack_id: String) -> String:
	return ""


func hold_shield(_seconds: float = 0.1) -> bool:
	return false


func use_shield(_seconds: float = 0.1) -> bool:
	return false


func notify_file_destroyed(_file_id: String) -> bool:
	return false


func junk_auto_carry(_packet_id: String, _attack_id: String) -> void:
	pass


func register_ransomware_file(_file_id: String, _attack_id: String) -> void:
	pass


func attack_disable_recv(seconds: float) -> void:
	recv_disabled_until = hour_elapsed + maxf(0.0, seconds)


func attack_disable_send(seconds: float) -> void:
	send_disabled_until = hour_elapsed + maxf(0.0, seconds)


func attack_channel_debuff(seconds: float) -> void:
	channel_debuff_until = hour_elapsed + maxf(0.0, seconds)


func attack_lose_packets(_count: int) -> void:
	pass


func attack_lock_random_file(seconds: float) -> void:
	if registry == null:
		return
	var candidates: Array = []
	for file in registry.get_available_files():
		if not is_folder_locked(str(file.folder_id)):
			candidates.append(file)
	if candidates.is_empty():
		return
	var file = candidates[_randi_range(0, candidates.size() - 1)]
	registry.lock_file(str(file.id), seconds)
	_emit_toast("Фишинг: файл заблокирован на %d с" % int(seconds))


func is_folder_locked(folder_id: String) -> bool:
	if folder_id.is_empty() or not blocked_folders.has(folder_id):
		return false
	return hour_elapsed < float(blocked_folders[folder_id])


func lock_random_folder(seconds: float) -> String:
	if registry == null or registry.folders.is_empty():
		return ""
	var ids: Array = registry.folders.keys()
	var folder_id := str(ids[_randi_range(0, ids.size() - 1)])
	blocked_folders[folder_id] = hour_elapsed + maxf(0.1, seconds)
	_emit_toast("Карантин: папка заблокирована на %d с" % int(seconds))
	return folder_id


func lock_ransomware_folder(folder_id: String, _file_id: String, seconds: float) -> void:
	if folder_id.is_empty():
		return
	blocked_folders[folder_id] = hour_elapsed + maxf(0.1, seconds)


func unlock_ransomware_folder(folder_id: String) -> void:
	if not folder_id.is_empty():
		blocked_folders.erase(folder_id)


# --- отчёт -----------------------------------------------------------------

func report(packets_left_override: int = -1, requests_left_override: int = -1) -> Dictionary:
	var earned := 0
	if game != null:
		earned = maxi(0, int(game.stats.get("money_earned", 0)) - _start_money_earned)
	var sla_delta := 0.0
	var money_delta := 0
	if game != null:
		sla_delta = float(game.sla) - _start_sla
		money_delta = int(game.money) - _start_money
	var packets_left := active_packets.size()
	if packets_left_override >= 0:
		packets_left = packets_left_override
	var requests_left := active_requests.size()
	if requests_left_override >= 0:
		requests_left = requests_left_override
	return {
		"hour": hour,
		"hour_duration": _hour_seconds(),
		"earned": earned,
		"money_delta": money_delta,
		"completed": _completed,
		"failed": _failed,
		"attacks": _attacks_blocked,
		"attacks_failed": _attacks_failed,
		"udp_lost": _udp_lost,
		"sla_delta": sla_delta,
		"time_left": time_left,
		"packets_left": packets_left,
		"requests_left": requests_left,
		"files_carry": 0,
		"files_budget": files_budget,
		"files_total": files_budget,
		"files_spawned": files_spawned,
		"files_sent": files_sent_this_hour,
		"cells_free": _cells_free(),
		"requests_spawned": requests_spawned,
		"requests_timed_out": requests_timed_out,
		"requests_rejected": requests_rejected,
		"send_interval": _send_interval(),
	}


# --- тик -------------------------------------------------------------------

func _tick_requests(dt: float) -> void:
	_check_failed_files()
	_lost_check_accum += dt
	if _lost_check_accum >= 0.5:
		_lost_check_accum = 0.0
		_check_lost_required()
	for id in active_requests.keys():
		if not active_requests.has(id):
			continue
		var req = active_requests[id]
		if req.minigame_active or req.connecting or _send_queue.has(str(id)):
			continue
		# D2: отправка уже началась — игрок не может на неё повлиять, поэтому
		# таймер запроса замирает и тикает только прогресс передачи. Таймаут
		# остаётся для запросов, которые ещё не отправляются.
		if req.sending:
			req.send_progress += dt
			if req.send_progress >= req.send_duration:
				_complete_send(str(id))
			continue
		req.time_left = maxf(0.0, req.time_left - dt)
		if req.time_left <= 0.0:
			_timeout_request(str(id))


func _tick_packets(dt: float) -> void:
	_fit_check_accum += dt
	var refresh := _fit_check_accum >= FIT_CHECK_INTERVAL
	if refresh:
		_fit_check_accum = 0.0
	for id in active_packets.keys():
		if not active_packets.has(id):
			continue
		var packet = active_packets[id]
		if packet.state == PACKET_SCRIPT.STATE_LOADING:
			packet.loading_progress += dt
			if packet.loading_progress >= packet.loading_duration:
				_finish_loading(str(id))
			continue
		if refresh:
			_packet_fit_cache[id] = _packet_can_fit(packet)
		# Переполнение склада: если фигуру некуда положить, таймер пакета
		# замирает — он не сгорает, пока игрок не освободит место.
		if not bool(_packet_fit_cache.get(id, true)):
			continue
		packet.time_left = maxf(0.0, packet.time_left - dt)
		if packet.time_left <= 0.0:
			_timeout_packet(str(id))


## Может ли фигура waiting-пакета влезть хоть в одну незаблокированную папку.
func _packet_can_fit(packet) -> bool:
	if packet == null or registry == null:
		return true
	if not registry.has_method("can_fit_anywhere"):
		return true
	return bool(registry.can_fit_anywhere(
		str(packet.shape_id), int(packet.rotation), blocked_folders
	))


func _tick_spawns(dt: float) -> void:
	if hour_elapsed < recv_disabled_until:
		return
	# Полный склад: ни одна незаблокированная папка не вмещает ни одной фигуры
	# доступного типа. Спавн стоит, следующий слот не сдвигаем.
	_space_check_accum += dt
	if _space_check_accum >= FIT_CHECK_INTERVAL:
		_space_check_accum = 0.0
		_space_ok_cache = _can_spawn_into_any_folder()
	if not _space_ok_cache:
		if not _no_space_notified:
			spawn_frozen.emit("no_space")
			_no_space_notified = true
		return
	_no_space_notified = false
	if _next_spawn_at < 0.0:
		_next_spawn_at = hour_elapsed + _next_receive_interval()
	spawn_recv_accum = maxf(0.0, hour_elapsed - _next_spawn_at)
	var steps := 0
	while steps < MAX_SPAWN_STEPS:
		if _next_spawn_at > spawn_window + 0.0001:
			return
		if _spawn_frozen_notified and hour_elapsed > spawn_window:
			# Окно закрылось, пока буфер был полон: файл переносится на час.
			return
		if hour_elapsed < _next_spawn_at:
			return
		steps += 1
		if _buffer_used() >= _buffer_limit():
			# Не теряем файл: не двигаем _next_spawn_at, пока буфер полон.
			if not _spawn_frozen_notified:
				spawn_frozen.emit("buffer_full")
				_spawn_frozen_notified = true
			return
		if _spawn_random_packet() == "":
			return
		files_spawned += 1
		spawned_this_hour += 1
		_spawn_frozen_notified = false
		var interval := _next_receive_interval()
		_recv_interval_current = interval
		_next_spawn_at = maxf(_next_spawn_at + interval, hour_elapsed + interval)
		spawn_recv_accum = 0.0


## Есть ли место под фигуру хотя бы одного типа из доступных в этом часе.
func _can_spawn_into_any_folder() -> bool:
	if registry == null or not registry.has_method("can_fit_type_anywhere"):
		return true
	for type_id in _type_pool():
		if bool(registry.can_fit_type_anywhere(str(type_id), blocked_folders)):
			return true
	return false


func _tick_request_spawns(dt: float) -> void:
	if _request_spawn_cutoff_reached():
		spawn_send_accum = 0.0
		return
	if _normal_request_count() >= active_request_limit:
		# Слот занят: «заряд» не копим, чтобы после освобождения соблюсти
		# интервал между запросами.
		spawn_send_accum = 0.0
	else:
		spawn_send_accum += dt
		var steps := 0
		while spawn_send_accum >= _send_interval_current and steps < MAX_SPAWN_STEPS:
			steps += 1
			spawn_send_accum -= _send_interval_current
			_last_request_attempt_t = hour_elapsed
			var req_id := _spawn_random_request()
			_send_interval_current = _send_interval()
			if not req_id.is_empty():
				spawn_send_accum = 0.0
				break
			if _request_spawn_cutoff_reached() \
					or _normal_request_count() >= active_request_limit:
				spawn_send_accum = 0.0
				break
	# Анти-голодание: пока запросов нет, не ждём полный интервал.
	_maybe_starvation_spawn()


## Последние секунды часа: новые запросы не создаются (игрок не успеет).
func _request_spawn_cutoff_reached() -> bool:
	return hour_elapsed >= _hour_seconds() - REQUEST_SPAWN_CUTOFF_SEC


func _request_starvation_ready() -> bool:
	# Guard нужен только для первого запроса часа: дальше темп задаёт
	# send_interval (H1 bootstrap уже создаёт requests_spawned=1).
	if requests_spawned > 0:
		return false
	if not active_requests.is_empty():
		return false
	if _request_spawn_cutoff_reached():
		return false
	if _normal_request_count() >= active_request_limit:
		return false
	if hour_elapsed - _last_request_attempt_t < REQUEST_ATTEMPT_MIN_GAP:
		return false
	return not _request_file_pool().is_empty()


func _maybe_starvation_spawn() -> void:
	if not _request_starvation_ready():
		return
	_last_request_attempt_t = hour_elapsed
	if not _spawn_random_request().is_empty():
		spawn_send_accum = 0.0


## Подсказка для пустого экрана запросов. "" — подсказка неуместна.
func next_request_hint() -> String:
	if not running or _finish_guard:
		return ""
	if _request_spawn_cutoff_reached():
		return "До конца часа запросов не будет"
	if _normal_request_count() >= active_request_limit:
		return ""
	if _request_file_pool().is_empty():
		return "Нет свободных файлов для запроса"
	if _request_starvation_ready():
		return "Следующий запрос ~0 с"
	var wait := maxf(0.0, _send_interval_current - spawn_send_accum)
	if active_requests.is_empty():
		var gap_left := maxf(0.0,
			REQUEST_ATTEMPT_MIN_GAP - (hour_elapsed - _last_request_attempt_t))
		wait = minf(wait, gap_left)
	return "Следующий запрос ~%d с" % int(ceil(wait))


func _tick_attacks(dt: float) -> void:
	if attack_director == null:
		return
	attack_director.set_allow_spawn(not is_minigame_active())
	attack_director.tick(dt)


func _tick_registry(dt: float) -> void:
	if registry == null or not registry.has_method("tick"):
		return
	_registry_accum += dt
	if _registry_accum < 0.5:
		return
	_registry_accum = 0.0
	registry.tick(Time.get_unix_time_from_system())


func _tick_folder_blocks() -> void:
	for folder_id in blocked_folders.keys():
		if hour_elapsed >= float(blocked_folders[folder_id]):
			blocked_folders.erase(folder_id)


# --- завершение сущностей --------------------------------------------------

func _finish_loading(packet_id: String) -> void:
	var packet = active_packets.get(packet_id)
	if packet == null or registry == null:
		return
	var file = registry.confirm_reservation(packet_id, packet.file_name, packet.type, packet.icon_id)
	packet.state = PACKET_SCRIPT.STATE_WAITING
	packet.loading_folder_id = ""
	if slots != null:
		slots.release_by_entity(packet_id)
	if file == null:
		_remove_packet(packet_id)
		_emit_toast("Не удалось сохранить файл")
		return
	var def := _type_def(str(packet.type))
	_add_money(int(def.get("recv_fee", 0)))
	_add_stat("files_received", 1)
	_add_stat("recv_done", 1)
	_remove_packet(packet_id)
	_play_sfx(&"recv")
	_emit_toast("Файл принят: %s" % file.display_name())
	_process_send_queue()


func _timeout_packet(packet_id: String) -> void:
	var packet = active_packets.get(packet_id)
	if packet == null:
		return
	var loss := _packet_sla_loss(packet)
	if loss > 0.0:
		_add_sla(-loss)
	_failed += 1
	_add_stat("failed", 1)
	_emit_toast("Пакет потерян по таймауту: −%s SLA" % _format_loss(loss))
	packet_lost.emit(packet_id)
	_remove_packet(packet_id)


func _remove_packet(packet_id: String) -> void:
	if not active_packets.has(packet_id):
		return
	var packet = active_packets[packet_id]
	if packet.state == PACKET_SCRIPT.STATE_LOADING:
		if registry != null:
			registry.cancel_reservation(packet_id)
		if slots != null:
			slots.release_by_entity(packet_id)
		packet.loading_folder_id = ""
	active_packets.erase(packet_id)
	_packet_fit_cache.erase(packet_id)
	if slots != null:
		slots.release_by_entity(packet_id)
	packet_removed.emit(packet_id)
	if running:
		_process_send_queue()


func _timeout_request(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null:
		return
	var fine := -(10.0 + 2.0 * float(hour))
	_add_sla(fine)
	_failed += 1
	requests_timed_out += 1
	_add_stat("failed", 1)
	_emit_toast("Запрос просрочен: %.0f SLA" % fine)
	request_expired.emit(req_id)
	_cleanup_request(req_id, true)


func _complete_send(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null:
		return
	req.sending = false
	var n := 0
	for file_id in req.attached:
		if registry != null and registry.files.has(str(file_id)):
			n += 1
	if n <= 0:
		_cleanup_request(req_id, true)
		return
	# UDP: ролл в конце передачи, до выплаты. Провал — без денег и без
	# расхода файлов; запрос остаётся активным с кулдауном повтора.
	if str(req.protocol) == "udp" and not _roll_udp_success(req):
		_handle_udp_failure(req)
		return
	var tcp_conn_id := str(req.connection_id)
	var streak := int(game.streak) if game != null else 0
	var time_at_start := float(_send_start_time_left.get(req_id, req.time_left))
	var total := float(_send_start_timer_total.get(req_id, req.timer_total))
	var payout := ECONOMY.payout(
		req.send_base_sum,
		n,
		time_at_start,
		total,
		req.quality,
		req.protocol,
		streak,
		_upgrades()
	)
	_add_money(payout)
	_completed += 1
	if game != null:
		game.streak = streak + 1
	_add_stat("requests_done", 1)
	var files_word := "файлов"
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		files_word = "файл"
	elif n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		files_word = "файла"
	_emit_toast("ОТПРАВЛЕНО: %d %s · +%d $" % [n, files_word, payout])
	_play_sfx(&"money_up")
	files_sent_this_hour += n

	# Файлы после отправки НЕ исчезают: возвращаются в папку и снова доступны
	# пулу запросов. Кулдаун — только если задан в constants.
	if registry != null:
		for file_id in req.attached.duplicate():
			if registry.files.has(str(file_id)):
				registry.detach_file(str(file_id))
		var cooldown := _const_float("file_cooldown_after_send_sec", 0.0)
		if cooldown > 0.0:
			for file_id in req.attached.duplicate():
				if registry.files.has(str(file_id)):
					registry.set_cooldown(str(file_id), cooldown)
	req.attached.clear()
	req.required_types.clear()

	# TCP: соединение остаётся занятым, но больше не привязано к запросу.
	# Ссылки чистим ДО cleanup, иначе он освободит слот соединения.
	if str(req.protocol) == "tcp":
		var conn = active_connections.get(tcp_conn_id) if not tcp_conn_id.is_empty() else null
		if conn != null:
			conn.request_id = ""
			if slots != null:
				var slot = slots.get_slot(int(conn.slot_index))
				if slot != null:
					slot.progress = 0.0
					slot.linked_request_id = ""
		req.connection_id = ""
	_cleanup_request(req_id, false)
	slot_changed.emit()


func _cleanup_request(req_id: String, detach: bool) -> void:
	if not active_requests.has(req_id):
		return
	var req = active_requests[req_id]
	if detach and registry != null:
		for file_id in req.attached.duplicate():
			if registry.files.has(str(file_id)):
				registry.detach_file(str(file_id))
	if registry != null:
		for file_id in req.required:
			var file = registry.files.get(str(file_id))
			if file != null and file.required_by == req_id:
				file.required_by = ""
	req.attached.clear()
	req.required_types.clear()
	_send_queue.erase(req_id)
	_send_start_time_left.erase(req_id)
	_send_start_timer_total.erase(req_id)
	if _minigame_request_id == req_id:
		force_close_send_minigame()
	# TCP: соединение переживает запрос, но при отмене/таймауте его надо
	# закрыть и освободить слот. Успешная отправка уже отвязала connection_id.
	var conn_id := str(req.connection_id)
	if conn_id.is_empty():
		conn_id = connection_id_for_request(req_id)
	if not conn_id.is_empty():
		_release_connection(conn_id)
		req.connection_id = ""
	if slots != null:
		slots.release_by_entity(req_id)
	req.sending = false
	req.slot_reserved = false
	req.minigame_active = false
	req.connecting = false
	req.set_meta("queued", false)
	active_requests.erase(req_id)
	request_removed.emit(req_id)
	if running:
		_process_send_queue()


func _check_failed_files() -> void:
	if registry == null:
		return
	for req_id in active_requests.keys():
		if not active_requests.has(req_id):
			continue
		var req = active_requests[req_id]
		var changed := false
		for file_id in req.attached.duplicate():
			var file = registry.files.get(str(file_id))
			if file == null:
				req.attached.erase(file_id)
				_clear_required_slot(req, str(file_id))
				changed = true
				continue
			var loc := str(file.location)
			if loc == "failed" or loc == "malicious":
				req.attached.erase(file_id)
				_clear_required_slot(req, str(file_id))
				changed = true
		if changed:
			request_changed.emit(str(req_id))


func _check_lost_required() -> void:
	if registry == null or active_requests.is_empty():
		return
	for req_id in active_requests.keys().duplicate():
		if not active_requests.has(req_id):
			continue
		var req = active_requests[req_id]
		if req == null:
			continue
		# M5: во время активной передачи файлы уже «в пути» — потерю не
		# подменяем и не начисляем выплату за уничтоженный посреди отправки файл.
		if bool(req.sending):
			continue
		var changed := false
		for i in range(req.required.size()):
			var fid := str(req.required[i])
			var file = registry.files.get(fid)
			var lost := file == null
			if file != null:
				var loc := str(file.location)
				lost = loc == "failed" or loc == "malicious"
			if not lost:
				continue
			var lost_type := ""
			if file != null:
				lost_type = str(file.type)
			elif i < req.required_types.size() and req.required_types.size() == req.required.size():
				lost_type = str(req.required_types[i])
			if req.attached.has(fid):
				req.attached.erase(fid)
				if file != null and str(file.attached_request) == str(req_id):
					registry.detach_file(fid)
				changed = true
			if file != null and file.required_by == str(req_id):
				file.required_by = ""
			var replacement := _find_substitute(lost_type)
			if replacement.is_empty():
				# Оставляем дырку: запрос можно отклонить, отправка невозможна.
				continue
			req.required[i] = replacement
			var substitute = registry.files.get(replacement)
			if substitute != null:
				substitute.required_by = str(req_id)
				if i < req.required_types.size():
					req.required_types[i] = str(substitute.type)
				else:
					req.required_types.append(str(substitute.type))
			changed = true
		if changed:
			request_changed.emit(str(req_id))


## Замена потерянного required-файла: равномерный пул, приоритет — тот же тип.
func _find_substitute(preferred_type: String) -> String:
	var pool := _request_file_pool()
	if pool.is_empty():
		return ""
	_shuffle_array(pool)
	if not preferred_type.is_empty():
		for file in pool:
			if str(file.type) == preferred_type:
				return str(file.id)
	return str(pool[0].id)


func force_close_send_minigame() -> void:
	var req_id := _minigame_request_id
	if _minigame == null and req_id.is_empty():
		return
	_clear_send_game_node()
	var req = active_requests.get(req_id)
	if req != null:
		req.minigame_active = false
		req.quality = 0.0
		request_changed.emit(req_id)
	minigame_cancelled.emit(req_id)


# --- конец часа ------------------------------------------------------------

func _finish_hour() -> void:
	if _finish_guard:
		return
	_finish_guard = true
	running = false

	var packets_left := active_packets.size()
	var requests_left := active_requests.size()

	# B5b: мини-игра отправки не должна софтлокать конец часа.
	force_close_send_minigame()
	# Если атака успела открыться в последнем тике, снимаем её без штрафа,
	# чтобы не оставить открытую модалку после конца часа.
	if attack_director != null and attack_director.has_method("cancel_active"):
		attack_director.cancel_active()

	# Очередь и все активные запросы проваливаются по SLA (без потери файлов).
	_send_queue.clear()
	for req_id in active_requests.keys().duplicate():
		var fine := -(10.0 + 2.0 * float(hour))
		_add_sla(fine)
		_failed += 1
		_add_stat("failed", 1)
		_cleanup_request(str(req_id), true)

	# Пакеты в буфере/загрузке просто снимаются, без дополнительных штрафов.
	for packet_id in active_packets.keys().duplicate():
		_remove_packet(str(packet_id))

	# TCP-соединения не переживают час: освобождаем их слоты принудительно.
	for conn_id in active_connections.keys().duplicate():
		_release_connection(str(conn_id))
	active_connections.clear()

	if slots != null:
		for slot in slots.slots:
			if slot.occupied:
				slots.release(slot.index)

	blocked_folders.clear()
	_attack_paused = false
	paused = false
	modal_open = false
	_modal_count = 0
	carry_files = 0

	var summary := report(packets_left, requests_left)
	hour_finished.emit(summary)


# --- модалки/мини-игры -----------------------------------------------------

func _clear_send_game_node() -> void:
	var node = _minigame
	var req_id := _minigame_request_id
	_minigame = null
	_minigame_request_id = ""
	if node != null and is_instance_valid(node):
		node.queue_free()
	minigame_closed.emit(req_id)


# --- спавн/буфер -----------------------------------------------------------

func _add_packet(packet) -> bool:
	if _buffer_used() >= _buffer_limit():
		spawn_frozen.emit("buffer_full")
		return false
	active_packets[packet.id] = packet
	packet_added.emit(packet.id)
	return true


func _buffer_used() -> int:
	return active_packets.size()


## Свободно клеток во всех папках (для отчёта часа).
func _cells_free() -> int:
	if registry == null or not registry.has_method("free_cells"):
		return 0
	return maxi(0, int(registry.free_cells()))


func _buffer_limit() -> int:
	if game != null and game.has_method("buffer_limit"):
		return maxi(1, int(game.buffer_limit()))
	return maxi(1, ECONOMY.buffer_limit(_upgrades()))


func _packet_sla_loss(packet) -> float:
	if packet == null:
		return DEFAULT_PACKET_SLA_LOSS
	var type := str(packet.type)
	if type.is_empty():
		return DEFAULT_PACKET_SLA_LOSS
	var def := _type_def(type)
	return maxf(0.0, float(def.get("sla_loss", DEFAULT_PACKET_SLA_LOSS)))


func _format_loss(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


# --- тайминги/данные -------------------------------------------------------

func _hour_seconds() -> float:
	if _hour_duration <= 0.0:
		return _resolve_hour_seconds()
	# Кэш из start_hour. Дешёвая сверка с сырой строкой Data (без полного
	# _hour_def()) — чтобы dev/тесты, правящие hours[] на лету, видели новое
	# значение; в обычном кадре Ambient просто получает кэш.
	var raw := _raw_hour_duration()
	if raw > 0.0:
		if is_equal_approx(raw, _hour_duration):
			return _hour_duration
		return _resolve_hour_seconds()
	if raw == 0.0:
		var legacy := maxf(1.0, _const_float("hour_seconds", DEFAULT_HOUR_SECONDS))
		if is_equal_approx(legacy, _hour_duration):
			return _hour_duration
		return _resolve_hour_seconds()
	return _hour_duration


## duration текущей строки hours[] без duplicate: >0 — есть, 0 — нет ключа,
## -1 — Data/hours недоступны (тогда доверяем кэшу).
func _raw_hour_duration() -> float:
	var data = _data()
	if data == null or not (data.get("hours") is Array):
		return -1.0
	var rows: Array = data.hours
	if rows.is_empty():
		return -1.0
	var row = rows[clampi(hour - 1, 0, rows.size() - 1)]
	if row is Dictionary:
		return float((row as Dictionary).get("duration", 0.0))
	return -1.0


## Разрешить длительность часа из данных: hours[].duration → legacy
## constants.hour_seconds → DEFAULT_HOUR_SECONDS. Вызывается в start_hour;
## в тике используется кэш _hour_duration (Ambient зовёт каждый кадр).
func _resolve_hour_seconds() -> float:
	var duration := float(_hour_def().get("duration", 0.0))
	if duration > 0.0:
		return duration
	# Legacy: старый constants.hour_seconds (300), если в строке часа нет duration.
	return maxf(1.0, _const_float("hour_seconds", DEFAULT_HOUR_SECONDS))


## Доля часа, в течение которой спавнятся файлы (constants.spawn_window_ratio).
func _spawn_window_ratio() -> float:
	return clampf(_const_float("spawn_window_ratio", SPAWN_WINDOW_RATIO), 0.01, 1.0)


## Числовая константа из balance.json → constants с безопасным fallback.
func _const_float(key: String, fallback_value: float) -> float:
	var data = _data()
	if data != null and data.get("constants") is Dictionary:
		var consts: Dictionary = data.constants
		if consts.has(key):
			return float(consts[key])
	return float(fallback_value)


## Шаг UDP-надёжности за уровень лота (data → shop[lot_udp].value).
func _udp_step() -> float:
	var data = _data()
	if data != null and data.has_method("lot_def"):
		var def = data.lot_def("lot_udp")
		if def is Dictionary and def.has("value"):
			return maxf(0.0, float(def.get("value", 0.10)))
	return 0.10


func _hour_def() -> Dictionary:
	var data = _data()
	if data != null and data.has_method("hour_def"):
		var def = data.hour_def(hour)
		if def is Dictionary:
			return def
	return {
		"hour": hour,
		"duration": 120 + 30 * maxi(0, hour - 1),
		"files": 6,
		"active_requests": 1,
		"send_interval": DEFAULT_SEND_INTERVAL,
		"type_weights": _default_type_weights(hour),
		"request_mix": DEFAULT_REQUEST_MIX.duplicate(),
		"request_type_weights": _default_request_type_weights(hour),
	}


## Legacy-значение из таблицы часа (для UI/старых тестов).
func _recv_interval() -> float:
	return maxf(0.2, float(_hour_def().get("recv_interval", DEFAULT_RECV_INTERVAL)))


## Фактический интервал спавна: окно / ожидаемый темп файлов.
func _receive_interval() -> float:
	var budget := maxi(1, files_budget)
	return maxf(0.2, spawn_window / float(budget))


## Следующий интервал с джиттером ±20%. Темп постоянный: без остатка бюджета
## и без жёсткого лимита количества файлов.
func _next_receive_interval() -> float:
	return maxf(0.2, _receive_interval() * _jitter())


func _send_interval() -> float:
	return maxf(0.5, float(_hour_def().get("send_interval", DEFAULT_SEND_INTERVAL)))


func _max_requests() -> int:
	return active_request_limit


func _normal_request_count() -> int:
	return active_requests.size()


func _jitter() -> float:
	return 1.0 + _randf_range(-SPAWN_JITTER, SPAWN_JITTER)


func _pick_type() -> String:
	var keys: Array = []
	var weights: Array = []
	for type_id in TYPE_ORDER:
		var w := maxf(0.0, float(type_weights.get(type_id, 0.0)))
		if w <= 0.0:
			continue
		keys.append(type_id)
		weights.append(w)
	if keys.is_empty():
		for type_id in TYPE_ORDER:
			var fallback := maxf(0.0, float(DEFAULT_TYPE_WEIGHTS.get(type_id, 0.0)))
			if fallback > 0.0:
				keys.append(type_id)
				weights.append(fallback)
	if keys.is_empty():
		return "text"
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return str(keys[0])
	var roll := _randf() * total
	var acc := 0.0
	for i in range(keys.size()):
		acc += float(weights[i])
		if roll < acc:
			return str(keys[i])
	return str(keys[keys.size() - 1])


func _type_pool() -> Array:
	var out: Array = []
	for type_id in TYPE_ORDER:
		if float(type_weights.get(type_id, 0.0)) > 0.0:
			out.append(type_id)
	if out.is_empty():
		out = ["text"]
	return out


func _default_type_weights(p_hour: int) -> Dictionary:
	var idx := clampi(int(p_hour) - 1, 0, 8)
	# Держим равными весам запросов: пул приёма соответствует спросу.
	var table := [
		[1.00, 0.00, 0.00, 0.00],
		[0.80, 0.20, 0.00, 0.00],
		[0.50, 0.50, 0.00, 0.00],
		[0.40, 0.30, 0.30, 0.00],
		[0.35, 0.35, 0.30, 0.00],
		[0.30, 0.30, 0.30, 0.10],
		[0.22, 0.23, 0.30, 0.25],
		[0.15, 0.25, 0.35, 0.25],
		[0.10, 0.15, 0.30, 0.45],
	]
	var row: Array = table[idx]
	var out := {}
	for i in range(TYPE_ORDER.size()):
		out[TYPE_ORDER[i]] = float(row[i])
	return out


## Fallback весов типов required-файлов, если в строке часа их нет.
func _default_request_type_weights(p_hour: int) -> Dictionary:
	var idx := clampi(int(p_hour) - 1, 0, 8)
	var row: Array = DEFAULT_REQUEST_TYPE_WEIGHTS[idx]
	var out := {}
	for i in range(TYPE_ORDER.size()):
		out[TYPE_ORDER[i]] = float(row[i])
	return out


func _required_count(req) -> int:
	if req == null:
		return 0
	var count := 0
	if req.required is Array:
		count = (req.required as Array).size()
	if count <= 0 and req.has_meta("required_count"):
		count = int(req.get_meta("required_count"))
	return clampi(count, 0, MAX_REQUIRED_FILES)


## Legacy-совместимость: required теперь хранит конкретные id, слоты не меняем.
func _fill_required_slot(_req, _file_id: String) -> void:
	pass


func _clear_required_slot(_req, _file_id: String) -> void:
	pass


func _blank_required_slots(_req) -> void:
	pass


func _request_ready(req) -> bool:
	if req == null:
		return false
	if req.sending or req.minigame_active:
		return false
	if _send_queue.has(str(req.id)):
		return false
	if str(req.protocol) == "tcp" and not req.has_connection():
		return false
	var need := _required_count(req)
	if need <= 0:
		return false
	for file_id in req.required:
		if not req.attached.has(str(file_id)):
			return false
	return true


func _attached_files_valid(req) -> bool:
	if req == null or registry == null:
		return false
	# Исчезнувший required-файл (consume/remove) делает запрос неотправляемым.
	for file_id in req.required:
		if not registry.files.has(str(file_id)):
			return false
	for file_id in req.attached:
		var file = registry.files.get(str(file_id))
		if file == null:
			return false
		if is_folder_locked(str(file.folder_id)):
			return false
		var loc := str(file.location)
		if loc == "locked" or loc == "table" or loc == "failed" or loc == "malicious":
			return false
	return true


func _attached_types(req) -> Array[String]:
	var out: Array[String] = []
	if req == null or registry == null:
		return out
	for file_id in req.attached:
		var file = registry.files.get(str(file_id))
		if file != null:
			out.append(str(file.type))
	return out


func _request_types(req) -> Array[String]:
	return _attached_types(req)


func _roll_required_count() -> int:
	var dist := request_mix
	if dist.is_empty():
		dist = _dict_of(_hour_def().get("request_mix", DEFAULT_REQUEST_MIX))
	if dist.is_empty():
		dist = DEFAULT_REQUEST_MIX.duplicate()
	var total := 0.0
	var keys: Array = dist.keys()
	keys.sort()
	var weights: Array = []
	for key in keys:
		var w := maxf(0.0, float(dist[key]))
		weights.append(w)
		total += w
	if total <= 0.0:
		return 1
	var roll := _randf() * total
	var acc := 0.0
	for i in range(keys.size()):
		acc += float(weights[i])
		if roll < acc:
			return clampi(int(str(keys[i])), 1, MAX_REQUIRED_FILES)
	return clampi(int(str(keys[keys.size() - 1])), 1, MAX_REQUIRED_FILES)


# --- канал -----------------------------------------------------------------

func _channel_factor() -> float:
	var load := channel_load()
	var factor := ECONOMY.channel_factor(load, _upgrades())
	if hour_elapsed < channel_debuff_until:
		factor *= 1.4
	return factor


func _active_weights() -> Array:
	var weights: Array = []
	if registry == null:
		return weights
	for packet in active_packets.values():
		if packet.state == PACKET_SCRIPT.STATE_LOADING:
			weights.append(_type_weight(str(packet.type)))
	for req in active_requests.values():
		if req.sending:
			for file_id in req.attached:
				var file = registry.files.get(str(file_id))
				if file != null:
					weights.append(_type_weight(str(file.type)))
	return weights


func _type_weight(type: String) -> float:
	return maxf(0.0, float(_type_def(type).get("weight", 0.0)))


func _type_def(type: String) -> Dictionary:
	var data = _data()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(type)
		if def is Dictionary:
			return def
	return {}


func _speed_level() -> int:
	return _level("speed_level")


func _level(key: String) -> int:
	if game != null and game.has_method("level"):
		return int(game.level(key))
	if game != null and game.get("upgrades") is Dictionary:
		return int((game.upgrades as Dictionary).get(key, 0))
	return 0


func _upgrades() -> Dictionary:
	if game != null and game.get("upgrades") is Dictionary:
		return game.upgrades
	return {}


# --- имена/клиенты ---------------------------------------------------------

func _make_file_name() -> String:
	var base := "файл"
	var data = _data()
	if data != null and data.get("names") is Dictionary:
		var names: Dictionary = data.names
		var adjectives = names.get("adjectives", [])
		var nouns = names.get("nouns", [])
		if adjectives is Array and not (adjectives as Array).is_empty() \
				and nouns is Array and not (nouns as Array).is_empty():
			var adj := str(adjectives[_randi_range(0, adjectives.size() - 1)])
			var noun := str(nouns[_randi_range(0, nouns.size() - 1)])
			base = "%s %s" % [adj, noun]
			base = base.substr(0, 1).to_upper() + base.substr(1)
	return _unique_file_name(base)


func _unique_file_name(base: String, exclude_packet_id: String = "") -> String:
	var probe := base
	if not _name_taken(probe, exclude_packet_id):
		return probe
	var i := 2
	while _name_taken(probe, exclude_packet_id):
		probe = "%s %d" % [base, i]
		i += 1
		if i > 500:
			break
	return probe


func _name_taken(name: String, exclude_packet_id: String = "") -> bool:
	if registry != null and registry.has_method("find_by_name") and registry.find_by_name(name) != null:
		return true
	for packet in active_packets.values():
		if not exclude_packet_id.is_empty() and str(packet.id) == exclude_packet_id:
			continue
		if str(packet.file_name).to_lower() == name.to_lower():
			return true
	return false


func _pick_org() -> String:
	var data = _data()
	if data != null and data.get("names") is Dictionary:
		var names: Dictionary = data.names
		var orgs = names.get("organizations", [])
		if orgs is Array and not (orgs as Array).is_empty():
			return str(orgs[_randi_range(0, orgs.size() - 1)])
	return "Клиент"


# --- служебное -------------------------------------------------------------

func _bind() -> void:
	if game == null:
		game = _autoload("Game")
	if game != null and game.get("registry") != null:
		registry = game.registry
	if registry == null:
		registry = REGISTRY_SCRIPT.new()
		registry.setup_new_run()
		if game != null:
			game.registry = registry
	if rng == null:
		rng = _autoload("Rng")
		if rng == null:
			var local := RandomNumberGenerator.new()
			local.randomize()
			rng = local


func _ensure_attack_director() -> void:
	if attack_director != null and is_instance_valid(attack_director):
		if attack_director.get_parent() == self:
			remove_child(attack_director)
		attack_director.free()
	attack_director = ATTACK_SCRIPT.new()
	attack_director.setup(self)
	add_child(attack_director)
	attack_director.attack_added.connect(_on_attack_added)
	attack_director.attack_changed.connect(_on_attack_changed)
	attack_director.attack_removed.connect(_on_attack_removed)
	attack_director.toast.connect(_on_attack_toast)
	attack_director.resolved.connect(_on_attack_resolved)
	attack_director.attack_resolved.connect(_on_attack_resolved_detail)
	attack_director.show_attack_minigame.connect(_on_show_attack_minigame)


func _clear_entities() -> void:
	force_close_send_minigame()
	_send_queue.clear()
	_send_start_time_left.clear()
	_send_start_timer_total.clear()
	for req_id in active_requests.keys().duplicate():
		var req = active_requests[req_id]
		if req.has_meta("queued"):
			req.set_meta("queued", false)
		if registry != null:
			for file_id in req.attached.duplicate():
				if registry.files.has(str(file_id)):
					registry.detach_file(str(file_id))
			for file_id in req.required:
				var file = registry.files.get(str(file_id))
				if file != null and file.required_by == str(req_id):
					file.required_by = ""
		req.attached.clear()
		req.sending = false
		req.minigame_active = false
		req.connecting = false
		req.slot_reserved = false
	for packet_id in active_packets.keys().duplicate():
		_remove_packet(str(packet_id))
	active_requests.clear()
	active_packets.clear()
	_packet_fit_cache.clear()
	_no_space_notified = false
	for conn_id in active_connections.keys().duplicate():
		_release_connection(str(conn_id))
	active_connections.clear()
	if slots != null:
		for slot in slots.slots:
			if slot.occupied:
				slots.release(slot.index)
	blocked_folders.clear()
	modal_open = false
	_modal_count = 0
	_attack_paused = false


func _running_reset_counters() -> void:
	_start_money = int(game.money) if game != null else 0
	_start_sla = float(game.sla) if game != null else 0.0
	_start_money_earned = int(game.stats.get("money_earned", 0)) if game != null else 0
	_completed = 0
	_failed = 0
	_attacks_blocked = 0
	_attacks_failed = 0
	_udp_lost = 0
	requests_timed_out = 0
	requests_rejected = 0
	files_sent_this_hour = 0
	_next_connection_num = 1


func _on_slots_changed() -> void:
	slot_changed.emit()
	if running and not _processing_queue:
		_process_send_queue()


func _on_attack_added(id: String) -> void:
	attack_added.emit(id)


func _on_attack_changed(id: String) -> void:
	attack_changed.emit(id)


func _on_attack_removed(id: String) -> void:
	attack_removed.emit(id)


func _on_attack_toast(text: String) -> void:
	_emit_toast(text)


func _on_attack_resolved(_id: String, _success: bool) -> void:
	# Детальный счёт — из attack_resolved(kind, success, tier).
	pass


func _on_attack_resolved_detail(kind: String, success: bool, tier: int) -> void:
	if success:
		_attacks_blocked += 1
		_add_stat("attacks_blocked", 1)
	else:
		_attacks_failed += 1
		_add_stat("attacks_failed", 1)
	attack_resolved.emit(kind, success, tier)


func _on_show_attack_minigame(game_node, kind: String) -> void:
	show_attack_minigame.emit(game_node, kind)


## Legacy-хук больше не используется: UI зовёт connection_finished(req_id, success).


func _add_money(delta: int) -> void:
	if game == null:
		return
	if game.has_method("add_money"):
		game.add_money(int(delta), "hour")
	else:
		game.money = maxi(0, int(game.money) + int(delta))


func _add_sla(delta: float) -> void:
	if game == null:
		return
	if game.has_method("add_sla"):
		game.add_sla(float(delta), "hour")


func _add_stat(key: String, delta: int) -> void:
	if game != null and game.has_method("add_stat"):
		game.add_stat(key, delta)


func _emit_toast(text: String) -> void:
	last_toast_text = text
	toast.emit(text)


func _clean_protocol(protocol: String) -> String:
	var clean := str(protocol).strip_edges().to_lower()
	if clean == "udp":
		return "udp"
	if clean == "tcp":
		return "tcp"
	return ""


func _randf() -> float:
	if rng != null and rng.has_method("randf"):
		return clampf(float(rng.randf()), 0.0, 0.999999)
	return clampf(randf(), 0.0, 0.999999)


func _randf_range(from: float, to: float) -> float:
	if rng != null and rng.has_method("randf_range"):
		return float(rng.randf_range(from, to))
	return randf_range(from, to)


func _randi_range(from: int, to: int) -> int:
	if to < from:
		return from
	if rng != null and rng.has_method("randi_range"):
		return int(rng.randi_range(from, to))
	return randi_range(from, to)


func _read_time_scale() -> float:
	var raw := OS.get_environment("PEAKHOUR_TIMESCALE")
	if raw.is_valid_float():
		return clampf(float(raw), 0.01, 100.0)
	return 1.0


func _play_sfx(id: StringName) -> void:
	var audio = _autoload("Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(str(id))


func _data():
	return _autoload("Data")


func _dict_of(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _autoload(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null
