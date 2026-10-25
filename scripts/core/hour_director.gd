class_name HourDirector
extends Node
## Единственный тикер часа (D03/D05/D11/D12).
##
## Все таймеры (пакеты, запросы, спавны, атаки) двигаются здесь.
## При открытой модалке спавн приёма и таймеры пакетов стоят, а таймер
## активного запроса продолжает идти (D03). `delta` всегда ≤ 0.1.
## Ускорение времени для headless-тестов: PEAKHOUR_TIMESCALE или
## свойство time_scale.

signal packet_added(id: String)
signal packet_changed(id: String)
signal packet_removed(id: String)
signal request_added(id: String)
signal request_changed(id: String)
signal request_removed(id: String)
signal slot_changed
signal attack_added(id: String)
signal attack_changed(id: String)
signal attack_removed(id: String)
signal toast(text: String)
signal hour_finished(report: Dictionary)
signal show_connection(game)
signal show_minigame(game)
signal spawn_frozen(reason: String)

const PACKET_SCRIPT := preload("res://scripts/entities/packet.gd")
const REQUEST_SCRIPT := preload("res://scripts/entities/request.gd")
const SLOT_MANAGER_SCRIPT := preload("res://scripts/core/slot_manager.gd")
const REGISTRY_SCRIPT := preload("res://scripts/core/file_registry.gd")
const CONNECTION_SCRIPT := preload("res://scripts/minigames/connection_game.gd")
const MINIGAME_SCRIPT := preload("res://scripts/minigames/minigame_base.gd")
const ATTACK_SCRIPT := preload("res://scripts/systems/attack_director.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")

const DEFAULT_HOUR_SECONDS := 300.0
const DEFAULT_RECV_INTERVAL := 12.0
const DEFAULT_SEND_INTERVAL := 22.0
const DEFAULT_MAX_REQUESTS := 2
const MAX_SPAWN_STEPS := 32
const FILE_COOLDOWN := 20.0
const FAILED_FILE_FINE_MONEY := -15
const FAILED_FILE_FINE_SLA := -10.0
const REJECT_FINE_MONEY := -5
const REJECT_FINE_SLA := -5.0
## Fallback, если у обычного пакета нет типа/sla_loss: минимальный штраф.
const DEFAULT_PACKET_SLA_LOSS := 2.0
## Пакеты атак (junk/ransomware) не штрафуются повторно: их урон ведёт
## AttackDirector (fail_sla/auto_unlock_sla), а не потеря карточки.
const ATTACK_PACKET_SLA_LOSS := 0.0
const RECV_FEE_SLA := 0.5
const SEND_SLA := 1.0

var active_packets: Dictionary = {}
var active_requests: Dictionary = {}
var slots = null
var attack_director = null

var spawn_recv_accum: float = 0.0
var spawn_send_accum: float = 0.0
var hour: int = 1
var time_left: float = DEFAULT_HOUR_SECONDS
var paused: bool = false
var successes_this_hour: int = 0
var shield_until: float = 0.0
var recv_disabled_until: float = 0.0
var channel_debuff_until: float = 0.0
var rng = null

## Дополнительное состояние/настройки.
var game = null
var registry = null
var modal_open: bool = false
var time_scale: float = 1.0
var running: bool = false
var hour_elapsed: float = 0.0
var send_disabled_until: float = 0.0
## Папки, заблокированные шифровальщиком: folder_id → hour_elapsed, до которого блок.
var blocked_folders: Dictionary = {}

var _modal_count: int = 0
var _next_packet_num: int = 1
var _next_request_num: int = 1
var _order_counter: int = 0
var _recv_interval_current: float = DEFAULT_RECV_INTERVAL
var _registry_accum: float = 0.0
var _finish_guard: bool = false

var _start_money: int = 0
var _start_sla: float = 0.0
var _start_money_earned: int = 0
var _completed: int = 0
var _failed: int = 0
var _attacks_blocked: int = 0
var _attacks_failed: int = 0

var _connection_games: Dictionary = {}
var _minigame = null
var _minigame_request_id: String = ""


func _init() -> void:
	time_scale = _read_time_scale()


# --- жизненный цикл --------------------------------------------------------

func start_hour(p_hour: int) -> void:
	_bind()
	hour = clampi(int(p_hour), 1, 24)
	_clear_entities()
	_bind()
	time_left = _hour_seconds()
	hour_elapsed = 0.0
	spawn_recv_accum = 0.0
	spawn_send_accum = 0.0
	_recv_interval_current = _recv_interval() * _jitter()
	paused = false
	modal_open = false
	_modal_count = 0
	successes_this_hour = 0
	shield_until = 0.0
	recv_disabled_until = 0.0
	channel_debuff_until = 0.0
	send_disabled_until = 0.0
	blocked_folders.clear()
	_running_reset_counters()
	slots = SLOT_MANAGER_SCRIPT.new()
	slots.changed.connect(_on_slots_changed)
	_ensure_attack_director()
	attack_director.reset(hour)
	running = true
	_finish_guard = false
	time_scale = _read_time_scale()
	slot_changed.emit()


func tick(delta: float) -> void:
	if not running or _finish_guard:
		return
	if paused:
		return
	var dt := minf(maxf(delta, 0.0), 0.1) * maxf(0.01, time_scale)
	if dt <= 0.0:
		return
	_bind()
	hour_elapsed += dt
	time_left = maxf(0.0, time_left - dt)
	_tick_requests(dt)
	if not modal_open:
		_tick_packets(dt)
		_tick_spawns(dt)
		_tick_attacks(dt)
	_tick_registry(dt)
	_tick_folder_blocks()
	if time_left <= 0.0:
		_finish_hour()


func set_paused(value: bool) -> void:
	paused = value


func set_modal_open(value: bool) -> void:
	modal_open = bool(value)
	_modal_count = 1 if modal_open else 0


func set_time_scale(value: float) -> void:
	time_scale = maxf(0.01, float(value))


func is_minigame_active() -> bool:
	return _minigame != null


func has_packet(id: String) -> bool:
	return active_packets.has(id)


func has_request(id: String) -> bool:
	return active_requests.has(id)


func get_packet(id: String):
	return active_packets.get(id)


func get_request(id: String):
	return active_requests.get(id)


func get_attack(id: String):
	if attack_director == null:
		return null
	return attack_director.active_attacks.get(id)


# --- публичные расчёты для UI ----------------------------------------------

func buffer_limit() -> int:
	return _buffer_limit()


func buffer_used() -> int:
	return _buffer_used()


func channel_factor() -> float:
	return _channel_factor()


func channel_load() -> float:
	if slots == null:
		return 0.0
	# Слоты не грузят канал: учитываются только активные передачи (_active_weights).
	return ECONOMY.channel_load(hour, 0, _active_weights(), _upgrades())


func max_slots() -> int:
	if slots == null:
		return 0
	return slots.max_slots()


# --- приём -----------------------------------------------------------------

## Спавн случайного пакета (используется таймером и тестами).
func spawn_packet_now(type_override: String = "", protocol_override: String = "") -> String:
	return _spawn_random_packet(type_override, protocol_override)


func _spawn_random_packet(type_override: String = "", protocol_override: String = "") -> String:
	var file_type := type_override
	if file_type.is_empty():
		file_type = _pick_type()
	var protocol := protocol_override
	if protocol.is_empty():
		var tcp_chance := clampf(0.50 + 0.025 * float(hour - 1), 0.50, 0.70)
		protocol = "tcp" if _randf() < tcp_chance else "udp"
	var def := _type_def(file_type)
	var p = PACKET_SCRIPT.new()
	p.id = "pkt_%d" % _next_packet_num
	_next_packet_num += 1
	p.type = file_type
	p.protocol = protocol
	p.file_name = _make_file_name()
	p.timer_total = ECONOMY.packet_timer(hour, _upgrades())
	p.time_left = p.timer_total
	p.size_kb = int(def.get("size_kb", 0))
	p.state = PACKET_SCRIPT.STATE_WAITING
	p.order = _order_counter
	_order_counter += 1
	if protocol == "udp" and _randf() < PACKET_SCRIPT.UDP_LOST_CHANCE:
		p.state = PACKET_SCRIPT.STATE_LOST
		p.lost_left = PACKET_SCRIPT.UDP_LOST_SEC
	if not _add_packet(p):
		return ""
	_play_sfx(&"tick")
	return p.id


## Мусорный пакет: карточка в приёме, занимает буфер, без типа и таймера.
func spawn_junk_packet(attack_id: String) -> String:
	var p = PACKET_SCRIPT.new()
	p.id = "pkt_%d" % _next_packet_num
	_next_packet_num += 1
	p.type = ""
	p.protocol = ""
	p.file_name = "?"
	p.timer_total = 0.0
	p.time_left = 0.0
	p.size_kb = 0
	p.state = PACKET_SCRIPT.STATE_WAITING
	p.order = _order_counter
	_order_counter += 1
	p.is_attack = true
	p.attack_kind = "junk"
	p.attack_id = attack_id
	if not _add_packet(p):
		return ""
	return p.id


## Принудительный спавн пакета-атаки (шифровальщик).
func spawn_ransomware_packet(attack_id: String) -> String:
	var p = PACKET_SCRIPT.new()
	p.id = "pkt_%d" % _next_packet_num
	_next_packet_num += 1
	p.type = "text"
	p.protocol = "tcp"
	p.file_name = "счёт.exe"
	p.timer_total = ECONOMY.packet_timer(hour, _upgrades())
	p.time_left = p.timer_total
	p.size_kb = 0
	p.state = PACKET_SCRIPT.STATE_WAITING
	p.order = _order_counter
	_order_counter += 1
	p.is_attack = true
	p.attack_kind = "ransomware"
	p.attack_id = attack_id
	if not _add_packet(p, true):
		return ""
	_emit_toast("ШИФРОВАЛЬЩИК: пакет .exe в приёме")
	return p.id


func receive_packet(packet_id: String, folder_id: String) -> bool:
	var packet = active_packets.get(packet_id)
	if packet == null or not packet.can_receive():
		return false
	if str(packet.attack_kind) == "junk":
		return false
	if registry == null or not registry.folders.has(folder_id):
		_emit_toast("Нет такой папки")
		return false
	if is_folder_locked(folder_id):
		_emit_toast("Папка заблокирована шифровальщиком")
		return false
	if not registry.reserve_slot(folder_id):
		_emit_toast("Папка заполнена — приём отклонён")
		return false
	var def := _type_def(packet.type)
	var duration := ECONOMY.recv_time(def, _channel_factor(), _upgrades())
	packet.state = PACKET_SCRIPT.STATE_LOADING
	packet.loading_folder_id = folder_id
	packet.loading_progress = 0.0
	packet.loading_duration = maxf(0.1, duration)
	packet_changed.emit(packet_id)
	_play_sfx(&"drop")
	return true


func connect_packet(packet_id: String) -> bool:
	var packet = active_packets.get(packet_id)
	if packet == null or not packet.can_connect() or slots == null or modal_open:
		return false
	if _connection_games.has(packet_id):
		return false
	var index: int = int(slots.reserve("in", packet.id, packet.file_name))
	if index < 0:
		_emit_toast("Все слоты соединения заняты")
		return false
	var game_node = CONNECTION_SCRIPT.new()
	_connection_games[packet_id] = game_node
	game_node.finished.connect(_on_connection_finished)
	_push_modal()
	game_node.start(hour, successes_this_hour, _zone_level(), packet_id)
	show_connection.emit(game_node)
	if game_node.get_parent() == null:
		add_child(game_node)
	return true


## Уничтожить пакет-атаку (шифровальщик) до заноса.
func destroy_attack_packet(packet_id: String) -> bool:
	var packet = active_packets.get(packet_id)
	if packet == null or not packet.is_attack:
		return false
	if str(packet.attack_kind) == "junk":
		var junk_rewarded := false
		if attack_director != null:
			junk_rewarded = attack_director.on_junk_packet_destroyed(packet_id)
		_remove_packet(packet_id)
		return junk_rewarded
	var rewarded := false
	if attack_director != null:
		rewarded = attack_director.on_ransomware_packet_destroyed(packet_id)
	_remove_packet(packet_id)
	return rewarded


# --- запросы ---------------------------------------------------------------

func spawn_request_now() -> String:
	return _spawn_random_request()


func _spawn_random_request() -> String:
	if registry == null:
		return ""
	var available: Array = registry.get_available_files()
	if available.is_empty():
		return ""
	# Файлы из заблокированных папок недоступны для запросов.
	var filtered: Array = []
	for file in available:
		if not is_folder_locked(str(file.folder_id)):
			filtered.append(file)
	available = filtered
	if available.is_empty():
		return ""
	var count := _roll_required_count()
	count = mini(count, available.size())
	var pool: Array = available.duplicate()
	var files: Array = []
	for i in range(count):
		var idx := _randi_range(0, pool.size() - 1)
		files.append(pool[idx])
		pool.remove_at(idx)
	var protocol := "tcp" if _randf() < 0.5 else "udp"
	return _make_request(files, protocol, false, "", "")


func spawn_phishing_request(attack_id: String) -> String:
	if registry == null:
		return ""
	var available: Array = registry.get_available_files()
	var filtered: Array = []
	for file in available:
		if not is_folder_locked(str(file.folder_id)):
			filtered.append(file)
	available = filtered
	var files: Array = []
	if not available.is_empty():
		var count := mini(_randi_range(1, 2), available.size())
		var pool: Array = available.duplicate()
		for i in range(count):
			var idx := _randi_range(0, pool.size() - 1)
			files.append(pool[idx])
			pool.remove_at(idx)
	return _make_request(files, "tcp", true, "phishing", attack_id)


func _make_request(files: Array, protocol: String, is_attack: bool, attack_kind: String, attack_id: String) -> String:
	var req = REQUEST_SCRIPT.new()
	req.id = "req_%d" % _next_request_num
	_next_request_num += 1
	req.protocol = protocol.to_lower()
	req.timer_total = ECONOMY.request_timer(hour, _upgrades())
	req.time_left = req.timer_total
	req.is_attack = is_attack
	req.attack_kind = attack_kind
	req.attack_id = attack_id
	for file in files:
		if file == null:
			continue
		req.required.append(str(file.id))
		req.required_types.append(str(file.type))
	if is_attack and attack_kind == "phishing":
		req.client_name = "Служба доставки"
		req.client_id = "id_7F3К" # кириллическая К — видимый телл D08
		req.avatar = "?"
	else:
		req.client_name = _pick_org()
		req.client_id = "id_%04X" % _next_request_num
		req.avatar = req.client_name.substr(0, 1).to_upper()
	active_requests[req.id] = req
	request_added.emit(req.id)
	_play_sfx(&"request_ready")
	return req.id


func attach_file(req_id: String, file_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null or registry == null:
		return false
	var file = registry.files.get(file_id)
	if file == null:
		return false
	if req.sending or req.minigame_active:
		return false
	if is_folder_locked(str(file.folder_id)):
		_emit_toast("Папка заблокирована шифровальщиком")
		return false
	if not req.required.has(file_id):
		_add_sla(-2.0)
		_emit_toast("Этот файл не требуется запросом (−2 SLA)")
		return false
	if not file.attached_request.is_empty() and file.attached_request != req_id:
		_emit_toast("Файл уже прикреплён к другому запросу")
		return false
	if req.attached.has(file_id):
		return true
	if not registry.attach_file(file_id, req_id):
		return false
	req.attached.append(file_id)
	request_changed.emit(req_id)
	# Отправка автоматическая: последний прикреплённый файл запускает её без
	# отдельного клика. TCP ждёт успешного соединения (is_ready), UDP — сразу.
	if req.is_ready() and not req.sending:
		_begin_send(req_id)
	return true


func detach_file(req_id: String, file_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null or registry == null:
		return false
	if req.sending or req.minigame_active:
		return false
	if not req.attached.has(file_id):
		return false
	registry.detach_file(file_id)
	req.attached.erase(file_id)
	request_changed.emit(req_id)
	return true


func reject_request(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if req.is_attack and req.attack_kind == "phishing":
		if attack_director != null:
			attack_director.resolve_phishing(req_id, "rejected")
	else:
		_add_money(REJECT_FINE_MONEY)
		_add_sla(REJECT_FINE_SLA)
		_emit_toast("Запрос отклонён: −5 $, −5 SLA")
	_failed += 1
	_cleanup_request(req_id, true)
	return true


func connect_request(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null or req.protocol != "tcp" or req.connected or slots == null or modal_open:
		return false
	if _connection_games.has(req_id):
		return false
	if req.slot_reserved:
		return false
	var index: int = int(slots.reserve("out", req.id, req.client_name))
	if index < 0:
		_emit_toast("Все слоты соединения заняты")
		return false
	req.slot_reserved = true
	var game_node = CONNECTION_SCRIPT.new()
	_connection_games[req_id] = game_node
	game_node.finished.connect(_on_connection_finished)
	_push_modal()
	game_node.start(hour, successes_this_hour, _zone_level(), req_id)
	show_connection.emit(game_node)
	if game_node.get_parent() == null:
		add_child(game_node)
	request_changed.emit(req_id)
	return true


## Отправка запускается сразу, без окна-заглушки MiniGame. Окно мини-игры
## остаётся на будущее (_on_minigame_finished), но в текущем цикле не
## создаётся: качество считается полным (1.0).
func start_send(req_id: String) -> bool:
	var req = active_requests.get(req_id)
	if req == null:
		return false
	if req.minigame_active or req.sending:
		return false
	if _minigame != null:
		return false
	# Пока открыта ConnectionGame (своя или другого запроса), отправку не
	# стартуем: иначе TCP-запрос уйдёт без полоски соединения. Успешное
	# соединение вызывает _begin_send уже после _pop_modal.
	if modal_open:
		return false
	if hour_elapsed < send_disabled_until:
		_emit_toast("Отправка временно недоступна")
		return false
	if not req.is_ready():
		_emit_toast("Запрос не готов к отправке")
		return false
	# TCP отправляется только после успешного соединения (иначе запрос ушёл бы
	# без полоски соединения). UDP можно отправлять сразу.
	if req.protocol == "tcp" and not req.connected:
		_emit_toast("Сначала подключитесь к клиенту")
		return false
	for file_id in req.required:
		if registry != null and registry.files.has(str(file_id)):
			var required_file = registry.files[str(file_id)]
			if is_folder_locked(str(required_file.folder_id)):
				_emit_toast("Папка заблокирована шифровальщиком")
				return false
	if req.required_types.is_empty():
		req.required_types = _request_types(req)
	req.quality = 1.0
	req.minigame_active = false
	_begin_send(req_id)
	return true


# --- атаки -----------------------------------------------------------------

func spawn_attack_now(kind: String = "") -> String:
	if attack_director == null:
		_ensure_attack_director()
	return attack_director.spawn_attack(kind)


func destroy_attack(id: String) -> bool:
	if attack_director == null:
		return false
	return attack_director.destroy(id)


func quarantine_attack(id: String) -> bool:
	if attack_director == null:
		return false
	return attack_director.quarantine(id)


func hold_shield(seconds: float = 0.1) -> bool:
	shield_until = hour_elapsed + maxf(0.0, seconds)
	if attack_director == null:
		return false
	return attack_director.hold_shield(seconds)


func use_shield(seconds: float = 0.1) -> bool:
	return hold_shield(seconds)


func attack_disable_recv(seconds: float) -> void:
	recv_disabled_until = hour_elapsed + maxf(0.0, seconds)


func attack_disable_send(seconds: float) -> void:
	send_disabled_until = hour_elapsed + maxf(0.0, seconds)


func attack_channel_debuff(seconds: float) -> void:
	channel_debuff_until = hour_elapsed + maxf(0.0, seconds)


func attack_lose_packets(count: int) -> void:
	var lost := 0
	var sla_loss := 0.0
	for id in active_packets.keys():
		if lost >= maxi(0, count):
			break
		var packet = active_packets[id]
		if packet.is_attack:
			continue
		sla_loss += _packet_sla_loss(packet)
		_remove_packet(str(id))
		_failed += 1
		lost += 1
	if lost > 0:
		if sla_loss > 0.0:
			_add_sla(-sla_loss)
		_emit_toast("DDoS: потеряно пакетов — %d (−%s SLA)" % [lost, _format_loss(sla_loss)])


func attack_lock_random_file(seconds: float) -> void:
	if registry == null:
		return
	var candidates: Array = registry.get_available_files()
	if candidates.is_empty():
		return
	var file = candidates[_randi_range(0, candidates.size() - 1)]
	registry.lock_file(file.id, seconds)
	_emit_toast("Фишинг: файл заблокирован на %d с" % int(seconds))


# --- блокировка папки шифровальщиком --------------------------------------

func is_folder_locked(folder_id: String) -> bool:
	if folder_id.is_empty() or not blocked_folders.has(folder_id):
		return false
	return hour_elapsed < float(blocked_folders[folder_id])


## Через folder_block_delay_sec папка становится недоступной, файл — locked.
func lock_ransomware_folder(folder_id: String, file_id: String, seconds: float) -> void:
	if folder_id.is_empty():
		return
	blocked_folders[folder_id] = hour_elapsed + maxf(0.1, seconds)
	if registry != null and registry.files.has(file_id):
		# FileRegistry.lock_file не принимает malicious, а шифровальщик уже
		# помечен malicious. Переводим файл в locked напрямую (D08/D09).
		var file = registry.files[file_id]
		var prev: StringName = &"folder" if not str(file.folder_id).is_empty() else &"registry"
		file._location_before_lock = prev
		file.location = &"locked"
		file.lock_until = Time.get_unix_time_from_system() + maxf(0.1, seconds)
		registry.file_changed.emit(file)
		registry.registry_changed.emit()
	_emit_toast("Шифровальщик: папка заблокирована на %d с" % int(seconds))


func unlock_ransomware_folder(folder_id: String) -> void:
	if not folder_id.is_empty():
		blocked_folders.erase(folder_id)


## Авто-занос мусора: карточка уходит из приёма, появляется malicious/fake.
func junk_auto_carry(packet_id: String, _attack_id: String) -> void:
	_remove_packet(packet_id)
	if registry == null:
		return
	var folder_id := _random_folder_with_space()
	var file = null
	if not folder_id.is_empty():
		file = registry.create_file(_unique_file_name("fake"), "text", folder_id, &"folder")
	if file == null:
		file = registry.create_file(_unique_file_name("fake"), "text", "", &"registry")
	if file != null:
		# У мусора нет типа/расширения — только malicious/fake.
		file.type = ""
		file.ext = ""
		registry.mark_malicious(str(file.id), "junk")


## Файл-шифровальщик создан на складе — передаём в AttackDirector.
func register_ransomware_file(file_id: String, attack_id: String) -> void:
	if attack_director != null:
		attack_director.on_ransomware_file(file_id, attack_id)


## Файл уничтожен пользователем (D08): если это шифровальщик — награда.
func notify_file_destroyed(file_id: String) -> bool:
	if attack_director == null:
		return false
	return attack_director.on_file_destroyed(file_id)


## Уничтожение malicious/locked файла атаки из UI (D08 остаётся кликабельным).
func destroy_attack_file(file_id: String) -> bool:
	if registry == null or not registry.files.has(file_id):
		return false
	var file = registry.files[file_id]
	if str(file.location) == "locked":
		registry.unlock_file(file_id)
		if registry.files.has(file_id):
			registry.mark_malicious(file_id, "ransomware")
	var destroyed: bool = bool(registry.destroy_malicious(file_id))
	if destroyed:
		notify_file_destroyed(file_id)
	return destroyed


# --- отчёт -----------------------------------------------------------------

func report() -> Dictionary:
	var earned := 0
	if game != null:
		earned = maxi(0, int(game.stats.get("money_earned", 0)) - _start_money_earned)
	var sla_delta := 0.0
	var money_delta := 0
	if game != null:
		sla_delta = float(game.sla) - _start_sla
		money_delta = int(game.money) - _start_money
	return {
		"hour": hour,
		"earned": earned,
		"money_delta": money_delta,
		"completed": _completed,
		"failed": _failed,
		"attacks": _attacks_blocked,
		"attacks_failed": _attacks_failed,
		"sla_delta": sla_delta,
		"time_left": time_left,
		"packets_left": active_packets.size(),
		"requests_left": active_requests.size(),
	}


# --- тик -------------------------------------------------------------------

func _tick_requests(dt: float) -> void:
	_check_failed_files()
	for id in active_requests.keys():
		if not active_requests.has(id):
			continue
		var req = active_requests[id]
		req.time_left = maxf(0.0, req.time_left - dt)
		if req.time_left <= 0.0:
			_timeout_request(str(id))
			continue
		if req.sending:
			req.send_progress += dt
			if req.send_progress >= req.send_duration:
				_complete_send(str(id))


func _tick_packets(dt: float) -> void:
	for id in active_packets.keys():
		if not active_packets.has(id):
			continue
		var packet = active_packets[id]
		# Мусор не имеет таймера — им управляет AttackDirector (15 с авто-занос).
		if str(packet.attack_kind) == "junk":
			continue
		if packet.state == PACKET_SCRIPT.STATE_LOST:
			packet.lost_left = maxf(0.0, packet.lost_left - dt)
			if packet.lost_left <= 0.0:
				packet.state = PACKET_SCRIPT.STATE_WAITING
				packet_changed.emit(str(id))
			continue
		if packet.state == PACKET_SCRIPT.STATE_LOADING:
			packet.loading_progress += dt
			if packet.loading_progress >= packet.loading_duration:
				_finish_loading(str(id))
			continue
		if packet.state == PACKET_SCRIPT.STATE_WAITING or packet.state == PACKET_SCRIPT.STATE_CONNECTED:
			packet.time_left = maxf(0.0, packet.time_left - dt)
			if packet.time_left <= 0.0:
				_timeout_packet(str(id))


func _tick_spawns(dt: float) -> void:
	# Приём.
	if hour_elapsed >= recv_disabled_until:
		spawn_recv_accum += dt
		var steps := 0
		while spawn_recv_accum >= _recv_interval_current and steps < MAX_SPAWN_STEPS:
			steps += 1
			spawn_recv_accum -= _recv_interval_current
			_recv_interval_current = _recv_interval() * _jitter()
			if _buffer_used() >= _buffer_limit():
				spawn_frozen.emit("buffer_full")
				spawn_recv_accum = 0.0
				break
			_spawn_random_packet()
	else:
		spawn_recv_accum = 0.0

	# Отправка.
	if hour_elapsed < send_disabled_until:
		spawn_send_accum = 0.0
		return
	spawn_send_accum += dt
	var send_steps := 0
	while spawn_send_accum >= _send_interval() and send_steps < MAX_SPAWN_STEPS:
		send_steps += 1
		spawn_send_accum -= _send_interval()
		if _normal_request_count() >= _max_requests():
			spawn_send_accum = 0.0
			break
		_spawn_random_request()


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


func _random_folder_with_space() -> String:
	if registry == null:
		return ""
	var ids: Array = registry.folders.keys()
	if ids.is_empty():
		return ""
	var start := _randi_range(0, ids.size() - 1)
	for step in range(ids.size()):
		var folder_id := str(ids[(start + step) % ids.size()])
		var folder = registry.folders[folder_id]
		if not is_folder_locked(folder_id) and folder.count() < 16:
			return folder_id
	return ""


# --- завершение сущностей --------------------------------------------------

func _finish_loading(packet_id: String) -> void:
	var packet = active_packets.get(packet_id)
	if packet == null or registry == null:
		return
	var folder_id: String = packet.loading_folder_id
	# reserve_slot держит место; перед create_file его нужно снять.
	registry.release_slot(folder_id)
	packet.loading_folder_id = ""
	var base_name: String = packet.file_name
	if packet.is_attack and packet.attack_kind == "ransomware":
		base_name = base_name.trim_suffix(".exe")
	var file = registry.create_file(_unique_file_name(base_name, packet_id), packet.type, folder_id, &"folder")
	if file == null:
		_remove_packet(packet_id)
		_emit_toast("Не удалось сохранить файл")
		return
	if packet.is_attack and packet.attack_kind == "ransomware":
		file.ext = "exe"
		registry.file_changed.emit(file)
		_remove_packet(packet_id)
		register_ransomware_file(str(file.id), packet.attack_id)
		_emit_toast("Шифровальщик на складе: уничтожьте файл")
		return
	var def := _type_def(packet.type)
	_add_money(int(def.get("recv_fee", 0)))
	_add_sla(RECV_FEE_SLA)
	if game != null and game.has_method("add_stat"):
		game.add_stat("files_received", 1)
	if game != null and game.has_method("add_stat"):
		game.add_stat("recv_done", 1)
	_remove_packet(packet_id)
	_play_sfx(&"recv")
	_emit_toast("Файл принят: %s" % file.display_name())


func _timeout_packet(packet_id: String) -> void:
	var packet = active_packets.get(packet_id)
	if packet == null:
		return
	if packet.is_attack:
		# Атака не нанесла урона: карточка уходит, AttackDirector уберёт запись.
		_remove_packet(packet_id)
		return
	var loss := _packet_sla_loss(packet)
	_add_sla(-loss)
	_failed += 1
	# Плата за приём не начисляется: пакет не дошёл до папки (failed).
	_emit_toast("Пакет потерян по таймауту: −%s SLA" % _format_loss(loss))
	_remove_packet(packet_id)


func _remove_packet(packet_id: String) -> void:
	if not active_packets.has(packet_id):
		return
	var packet = active_packets[packet_id]
	# Прерванная загрузка должна вернуть резерв папки (D05).
	if packet.state == PACKET_SCRIPT.STATE_LOADING and not str(packet.loading_folder_id).is_empty() and registry != null:
		registry.release_slot(str(packet.loading_folder_id))
		packet.loading_folder_id = ""
	if _connection_games.has(packet_id):
		var node = _connection_games[packet_id]
		_connection_games.erase(packet_id)
		if is_instance_valid(node):
			node.queue_free()
		_pop_modal()
	active_packets.erase(packet_id)
	if slots != null:
		slots.release_by_entity(packet_id)
	packet_removed.emit(packet_id)


func _timeout_request(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null:
		return
	if req.is_attack and req.attack_kind == "phishing":
		if attack_director != null:
			attack_director.resolve_phishing(req_id, "timeout")
		_failed += 1
	else:
		var fine := -(10.0 + 2.0 * float(hour))
		_add_sla(fine)
		_failed += 1
		_emit_toast("Запрос просрочен: %.0f SLA" % fine)
	_cleanup_request(req_id, true)


func _complete_send(req_id: String) -> void:
	var req = active_requests.get(req_id)
	if req == null:
		return
	req.sending = false
	var payout := 0
	if req.is_attack and req.attack_kind == "phishing":
		_failed += 1
		if attack_director != null:
			attack_director.resolve_phishing(req_id, "sent")
		_emit_toast("Фишинг отправлен: −40 $, −10 SLA")
	else:
		var streak := 0
		if game != null:
			streak = int(game.streak)
		payout = ECONOMY.payout(
			req.send_base_sum,
			req.required.size(),
			req.time_left,
			req.timer_total,
			req.quality,
			req.protocol,
			streak,
			_upgrades()
		)
		_add_money(payout)
		_add_sla(SEND_SLA)
		_completed += 1
		if game != null:
			game.streak = streak + 1
			if game.has_method("add_stat"):
				game.add_stat("requests_done", 1)
		_emit_toast("Отправлено: +%d $, +1 SLA" % payout)
		_play_sfx(&"money_up")
	# D02: файлы не расходуются, но получают cooldown 20 с.
	for file_id in req.required:
		if registry != null and registry.files.has(file_id):
			registry.set_cooldown(file_id, FILE_COOLDOWN)
	_cleanup_request(req_id, true)


func _cleanup_request(req_id: String, detach: bool) -> void:
	if not active_requests.has(req_id):
		return
	var req = active_requests[req_id]
	if detach and registry != null:
		for file_id in req.attached.duplicate():
			registry.detach_file(str(file_id))
	req.attached.clear()
	if _minigame_request_id == req_id:
		_close_minigame()
	if _connection_games.has(req_id):
		var node = _connection_games[req_id]
		_connection_games.erase(req_id)
		if is_instance_valid(node):
			node.queue_free()
		_pop_modal()
	if slots != null:
		slots.release_by_entity(req_id)
	req.slot_reserved = false
	active_requests.erase(req_id)
	request_removed.emit(req_id)


func _check_failed_files() -> void:
	if registry == null:
		return
	for req_id in active_requests.keys():
		if not active_requests.has(req_id):
			continue
		var req = active_requests[req_id]
		var broken := false
		for file_id in req.required:
			var file = registry.files.get(str(file_id))
			if file == null or str(file.location) == "failed":
				broken = true
				break
		if not broken:
			continue
		_add_money(FAILED_FILE_FINE_MONEY)
		_add_sla(FAILED_FILE_FINE_SLA)
		_failed += 1
		_emit_toast("Файл запроса сбойный — запрос отменён: −15 $, −10 SLA")
		_cleanup_request(str(req_id), true)


func _finish_hour() -> void:
	if _finish_guard:
		return
	_finish_guard = true
	running = false
	# Отчёт фиксируем ДО очистки, чтобы earned/completed/failed/attacks были
	# посчитаны по фактическому часу. Затем все сущности отменяются без штрафов.
	var summary := report()
	_cleanup_hour_entities()
	summary["packets_left"] = active_packets.size()
	summary["requests_left"] = active_requests.size()
	hour_finished.emit(summary)


## Конец часа: снять всё без штрафов SLA (пакеты, запросы, слоты, резервы).
func _cleanup_hour_entities() -> void:
	if slots != null:
		for slot in slots.slots:
			if slot.occupied:
				slots.release(slot.index)
	for id in active_requests.keys():
		_cleanup_request(str(id), true)
	for id in active_packets.keys():
		_remove_packet(str(id))
	_close_all_modals()
	blocked_folders.clear()
	_modal_count = 0
	modal_open = false


func _close_all_modals() -> void:
	for node in _connection_games.values():
		if is_instance_valid(node):
			node.queue_free()
	_connection_games.clear()
	_close_minigame()
	_modal_count = 0
	modal_open = false


# --- модалки ---------------------------------------------------------------

func _on_connection_finished(success: bool, entity_id: String) -> void:
	_connection_games.erase(entity_id)
	_pop_modal()
	if active_packets.has(entity_id):
		var packet = active_packets[entity_id]
		if success:
			packet.state = PACKET_SCRIPT.STATE_CONNECTED
			successes_this_hour += 1
			packet_changed.emit(entity_id)
			_play_sfx(&"modem")
		else:
			if slots != null:
				slots.release_by_entity(entity_id)
			packet_changed.emit(entity_id)
		return
	if active_requests.has(entity_id):
		var req = active_requests[entity_id]
		if success:
			req.connected = true
			req.slot_reserved = true
			successes_this_hour += 1
			_play_sfx(&"modem")
			request_changed.emit(entity_id)
			# TCP отправляется сразу после соединения, если файлы уже собраны.
			if req.is_ready() and not req.sending:
				_begin_send(entity_id)
			return
		req.connected = false
		req.slot_reserved = false
		if slots != null:
			slots.release_by_entity(entity_id)
		request_changed.emit(entity_id)


func _on_minigame_finished(quality: float) -> void:
	var req_id := _minigame_request_id
	_minigame = null
	_minigame_request_id = ""
	_pop_modal()
	var req = active_requests.get(req_id)
	if req == null:
		return
	req.minigame_active = false
	req.quality = clampf(quality, 0.0, 1.0)
	request_changed.emit(req_id)
	_begin_send(req_id)


func _begin_send(req_id: String, allow_retry: bool = true) -> void:
	var req = active_requests.get(req_id)
	if req == null or req.sending:
		return
	# Пока открыта чужая модалка (ConnectionGame), авто-путь не стартует.
	# Своё соединение к этому моменту уже закрыло модалку (_pop_modal).
	if modal_open:
		return
	# Защита авто-пути: TCP не стартует без установленного соединения.
	if req.protocol == "tcp" and not req.connected:
		return
	if req.protocol == "udp" and allow_retry and _randf() < 0.25:
		# UDP-потеря при отправке: один повтор без мини-игры, чтобы
		# автоотправка не могла зациклиться на серии потерь.
		req.quality = 1.0
		req.minigame_active = false
		_emit_toast("UDP-потеря: отправляем заново")
		_begin_send(req_id, false)
		return
	var types := _request_types(req)
	if types.is_empty():
		for value in req.required_types:
			types.append(str(value))
	req.required_types = types
	var factor := _channel_factor()
	var duration := 0.0
	var base_sum := 0.0
	for file_id in req.required:
		if registry == null or not registry.files.has(str(file_id)):
			continue
		var file = registry.files[str(file_id)]
		var def := _type_def(str(file.type))
		duration += ECONOMY.send_time(def, factor, _upgrades())
		base_sum += float(def.get("base_pay", 0))
	req.send_duration = maxf(0.1, duration)
	req.send_base_sum = base_sum
	req.sending = true
	req.send_progress = 0.0
	request_changed.emit(req_id)
	_play_sfx(&"modem")
	_emit_toast("Отправка началась")


func _close_minigame() -> void:
	var had := _minigame != null or not _minigame_request_id.is_empty()
	if _minigame != null and is_instance_valid(_minigame):
		_minigame.queue_free()
	_minigame = null
	_minigame_request_id = ""
	if had:
		_pop_modal()


# --- спавн/буфер -----------------------------------------------------------

func _add_packet(packet, _force: bool = false) -> bool:
	if _packet_uses_buffer(packet) and _buffer_used() >= _buffer_limit():
		var oldest := _oldest_packet()
		if oldest.is_empty():
			spawn_frozen.emit("buffer_full")
			return false
		var evicted = active_packets.get(oldest)
		var loss := _packet_sla_loss(evicted)
		_remove_packet(oldest)
		if loss > 0.0:
			_add_sla(-loss)
		_failed += 1
		_emit_toast("Буфер переполнен: старый пакет потерян, −%s SLA" % _format_loss(loss))
	active_packets[packet.id] = packet
	packet_added.emit(packet.id)
	return true


## Штраф SLA за потерю пакета — по типу (п.13): text 2 / sound 4 / photo 8 /
## video 16. Пакеты атак не штрафуются повторно (их урон считает
## AttackDirector), неизвестный/пустой тип обычного пакета → fallback 2.
func _packet_sla_loss(packet) -> float:
	if packet == null:
		return DEFAULT_PACKET_SLA_LOSS
	if bool(packet.is_attack):
		return ATTACK_PACKET_SLA_LOSS
	var type := str(packet.type)
	if type.is_empty():
		return DEFAULT_PACKET_SLA_LOSS
	var def := _type_def(type)
	return maxf(0.0, float(def.get("sla_loss", DEFAULT_PACKET_SLA_LOSS)))


func _format_loss(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


## Мусор занимает место в приёме, остальные атаки — отдельный слой (D07).
func _packet_uses_buffer(packet) -> bool:
	if not packet.is_attack:
		return true
	return str(packet.attack_kind) == "junk"


func _buffer_used() -> int:
	var count := 0
	for packet in active_packets.values():
		if _packet_uses_buffer(packet):
			count += 1
	return count


func _oldest_packet() -> String:
	var oldest_id := ""
	var oldest_order := 2147483647
	for id in active_packets.keys():
		var packet = active_packets[id]
		if not _packet_uses_buffer(packet):
			continue
		if int(packet.order) < oldest_order:
			oldest_order = int(packet.order)
			oldest_id = str(id)
	return oldest_id


func _buffer_limit() -> int:
	var base := 4
	var per := 2
	var cap := 8
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var constants = data.balance.get("constants", null)
		if constants is Dictionary:
			base = int(constants.get("buffer_base", base))
			per = int(constants.get("buffer_per_upgrade", per))
			cap = int(constants.get("buffer_max", cap))
	return clampi(base + per * _buffer_level(), base, cap)


func _buffer_level() -> int:
	var upgrades := _upgrades()
	for key in ["buffer_level", "buffer_slots", "shop_buffer", "buffer"]:
		if upgrades.has(key):
			return int(upgrades[key])
	return 0


# --- тайминги/данные -------------------------------------------------------

func _hour_seconds() -> float:
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var constants = data.balance.get("constants", null)
		if constants is Dictionary:
			return maxf(1.0, float(constants.get("hour_seconds", DEFAULT_HOUR_SECONDS)))
	return DEFAULT_HOUR_SECONDS


func _difficulty() -> Dictionary:
	var data = _data()
	if data != null and data.has_method("difficulty_for"):
		return data.difficulty_for(hour)
	return {}


func _recv_interval() -> float:
	var interval := float(_difficulty().get("recv_interval", DEFAULT_RECV_INTERVAL))
	if hour > 8:
		var periods := int(floor(float(hour - 8) / 2.0))
		interval /= (1.0 + 0.05 * float(periods))
	return maxf(0.2, interval)


func _send_interval() -> float:
	return maxf(0.5, float(_difficulty().get("send_interval", DEFAULT_SEND_INTERVAL)))


func _max_requests() -> int:
	return maxi(1, int(_difficulty().get("max_requests", DEFAULT_MAX_REQUESTS)))


func _normal_request_count() -> int:
	var count := 0
	for req in active_requests.values():
		if not req.is_attack:
			count += 1
	return count


func _jitter() -> float:
	return _randf_range(0.8, 1.2)


const TYPE_ORDER: Array[String] = ["text", "sound", "photo", "video"]


func _pick_type() -> String:
	var pool := _type_pool()
	if pool.is_empty():
		return _fallback_minigame_type()
	return str(pool[_randi_range(0, pool.size() - 1)])


## Пул типов с учётом открытий (п.16): minigame_text/sound/photo/video.
func _type_pool() -> Array:
	var raw_pool: Array = []
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var spawn = data.balance.get("spawn", null)
		if spawn is Dictionary:
			var by_hour = spawn.get("type_pool_by_hour", null)
			if by_hour is Dictionary:
				var key := "1" if hour <= 1 else ("2" if hour == 2 else "3+")
				var pool = by_hour.get(key, null)
				if pool is Array and not (pool as Array).is_empty():
					raw_pool = pool
	if raw_pool.is_empty():
		raw_pool = ["text", "sound"] if hour <= 1 else ["text", "sound", "photo", "video"]
	var out: Array = []
	for type in raw_pool:
		var type_id := str(type)
		if _type_unlocked(type_id):
			out.append(type_id)
	if out.is_empty():
		for type_id in TYPE_ORDER:
			if _type_unlocked(type_id):
				out.append(type_id)
	if out.is_empty():
		out = ["text"]
	return out


## Открыт ли тип: проверяются minigame_<type> и (если задан) type_<type>.
func _type_unlocked(type: String) -> bool:
	if not _feature_unlocked("minigame_" + type):
		return false
	return _feature_unlocked("type_" + type)


## Первый открытый тип мини-игры (text открыт с часа 1).
func _fallback_minigame_type() -> String:
	for type_id in TYPE_ORDER:
		if _feature_unlocked("minigame_" + type_id):
			return type_id
	return "text"


func _feature_unlocked(id: String) -> bool:
	if game == null:
		_bind()
	if game != null and game.has_method("feature_unlocked"):
		return bool(game.feature_unlocked(id))
	return true


func _type_def(type: String) -> Dictionary:
	var data = _data()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(type)
		if def is Dictionary:
			return def
	return {}


func _request_types(req) -> Array[String]:
	var out: Array[String] = []
	if registry == null:
		return out
	for file_id in req.required:
		var file = registry.files.get(str(file_id))
		if file != null:
			out.append(str(file.type))
	return out


func _make_file_name() -> String:
	var base := "файл"
	var data = _data()
	if data != null and data.get("names") is Dictionary:
		var names: Dictionary = data.names
		var adjectives = names.get("adjectives", [])
		var nouns = names.get("nouns", [])
		if adjectives is Array and not (adjectives as Array).is_empty() and nouns is Array and not (nouns as Array).is_empty():
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


## Сколько файлов требует запрос. На старте меньше: час 1 — всегда 1 файл,
## час 2 — 1 (0.75) или 2 (0.25), час 3+ — 1/2/3 (0.6/0.3/0.1).
## Данные — balance.spawn.required_count_by_hour, fallback — size_distribution.
func _roll_required_count() -> int:
	var dist := _required_count_distribution()
	if dist.is_empty():
		dist = {"1": 0.6, "2": 0.3, "3": 0.1}
	var total := 0.0
	var keys: Array = dist.keys()
	keys.sort()
	var weights: Array = []
	for key in keys:
		var weight := maxf(0.0, float(dist[key]))
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return 1
	var roll := _randf() * total
	var acc := 0.0
	for i in range(keys.size()):
		acc += float(weights[i])
		if roll < acc:
			return clampi(int(str(keys[i])), 1, 3)
	return clampi(int(str(keys[keys.size() - 1])), 1, 3)


func _required_count_distribution() -> Dictionary:
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var spawn = data.balance.get("spawn", null)
		if spawn is Dictionary:
			var by_hour = spawn.get("required_count_by_hour", null)
			if by_hour is Dictionary:
				var key := "1" if hour <= 1 else ("2" if hour == 2 else "3+")
				var dist = by_hour.get(key, null)
				if dist is Dictionary and not (dist as Dictionary).is_empty():
					return dist
			var fallback = spawn.get("required_size_distribution", null)
			if fallback is Dictionary:
				return fallback
	return {}


# --- канал -----------------------------------------------------------------

func _channel_factor() -> float:
	if slots == null:
		return 1.0
	var load := ECONOMY.channel_load(hour, 0, _active_weights(), _upgrades())
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
			for file_id in req.required:
				var file = registry.files.get(str(file_id))
				if file != null:
					weights.append(_type_weight(str(file.type)))
	return weights


func _type_weight(type: String) -> float:
	return maxf(0.0, float(_type_def(type).get("weight", 0.0)))


func _upgrades() -> Dictionary:
	if game == null or not (game.upgrades is Dictionary):
		return {}
	return game.upgrades


func _zone_level() -> int:
	var upgrades := _upgrades()
	for key in ["zone_level", "zone_width", "shop_zone", "zone"]:
		if upgrades.has(key):
			return int(upgrades[key])
	return 0


# --- служебное -------------------------------------------------------------

func _bind() -> void:
	if game == null:
		game = _autoload("Game")
	if game != null:
		if game.registry != null:
			registry = game.registry
	if registry == null:
		registry = REGISTRY_SCRIPT.new()
		registry.setup_new_run()
	if rng == null:
		rng = _autoload("Rng")
		if rng == null:
			var local := RandomNumberGenerator.new()
			local.randomize()
			rng = local


func _ensure_attack_director() -> void:
	if attack_director != null:
		return
	attack_director = ATTACK_SCRIPT.new()
	attack_director.setup(self)
	add_child(attack_director)
	attack_director.attack_added.connect(_on_attack_added)
	attack_director.attack_changed.connect(_on_attack_changed)
	attack_director.attack_removed.connect(_on_attack_removed)
	attack_director.toast.connect(_on_attack_toast)
	attack_director.resolved.connect(_on_attack_resolved)


func _clear_entities() -> void:
	_cleanup_hour_entities()
	active_packets.clear()
	active_requests.clear()
	# Старые слоты заменяются новыми в start_hour.


func _running_reset_counters() -> void:
	_start_money = int(game.money) if game != null else 0
	_start_sla = float(game.sla) if game != null else 0.0
	_start_money_earned = int(game.stats.get("money_earned", 0)) if game != null else 0
	_completed = 0
	_failed = 0
	_attacks_blocked = 0
	_attacks_failed = 0


func _push_modal() -> void:
	_modal_count += 1
	modal_open = true


func _pop_modal() -> void:
	_modal_count = maxi(0, _modal_count - 1)
	modal_open = _modal_count > 0


func _on_slots_changed() -> void:
	slot_changed.emit()


func _on_attack_added(id: String) -> void:
	attack_added.emit(id)


func _on_attack_changed(id: String) -> void:
	attack_changed.emit(id)


func _on_attack_removed(id: String) -> void:
	attack_removed.emit(id)


func _on_attack_toast(text: String) -> void:
	_emit_toast(text)


func _on_attack_resolved(_id: String, success: bool) -> void:
	if success:
		_attacks_blocked += 1
		if game != null and game.has_method("add_stat"):
			game.add_stat("attacks_blocked", 1)
	else:
		_attacks_failed += 1


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


func _emit_toast(text: String) -> void:
	toast.emit(text)


func _randf() -> float:
	if rng != null and rng.has_method("randf"):
		return float(rng.randf())
	return randf()


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


func _autoload(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null
