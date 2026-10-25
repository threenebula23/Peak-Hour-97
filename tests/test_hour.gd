extends SceneTree
## Headless-тест v2 HourDirector: бюджеты, веса типов, перенос файлов,
## приём с резервациями, запросы/лимиты, attach/detach, явная отправка,
## пауза таймера в мини-игре, очередь out-слота, расход файлов, конец часа
## во время мини-игры и отчёт.
##
## Запуск:
##   godot --headless --path . --script tests/test_hour.gd

const HD := preload("res://scripts/core/hour_director.gd")
const AD := preload("res://scripts/systems/attack_director.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _game = null
var _hd = null
var _name_seq: int = 0

var _hour_events: int = 0
var _hour_report: Dictionary = {}
var _minigame_shows: int = 0
var _minigame_cancels: int = 0
var _minigame_closes: int = 0
var _connection_shows: int = 0
var _connection_request_id: String = ""
var _connection_hour: int = 0
var _connection_successes: int = -1
var _frozen_events: int = 0
var _toasts: Array[String] = []


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_hd = HD.new()
	_hd.name = "HourDirectorTest"
	root.add_child(_hd)
	_hd.hour_finished.connect(_on_hour_finished)
	_hd.show_minigame.connect(_on_show_minigame)
	_hd.minigame_cancelled.connect(_on_minigame_cancelled)
	_hd.minigame_closed.connect(_on_minigame_closed)
	_hd.spawn_frozen.connect(_on_spawn_frozen)
	_hd.show_connection.connect(_on_show_connection)
	_hd.toast.connect(_on_toast)

	_test_start_hour()
	_test_budgets_and_weights()
	_test_spawn_window_budget()
	_test_carry()
	_test_receive()
	_test_receive_cancel_and_no_space()
	_test_request_caps()
	_test_starvation_guard()
	_test_attach_detach()
	_test_protocol()
	_test_send_minigame_pause()
	_test_out_slot_queue()
	_test_file_consumption()
	_test_send_timer_freeze()
	_test_timeout_preserves_files()
	_test_hour_end_during_minigame()
	_test_connection_flow()
	_test_lost_required()
	_test_modal_guard()
	_test_required_types_stable()
	_test_no_substitute_while_sending()
	_test_report()
	_test_reset_for_prep()
	_test_move_required_file()
	_finish()


# --- старт -----------------------------------------------------------------

func _test_start_hour() -> void:
	_set_case("start_hour")
	_fresh(1, true)
	_eq(_hd.hour, 1, "hour = 1")
	_approx(_hd.time_left, 300.0, 0.0001, "длительность часа 300 с")
	_ok(_hd.running, "час запущен")
	# v3: H1 плотнее — значения берём из data/balance.json → hours[0].
	var h1: Dictionary = _hour_row(1)
	_eq(_hd.files_budget, int(h1.get("files", -1)), "H1: бюджет файлов из данных")
	_eq(_hd.files_budget, 7, "H1: 7 файлов")
	_eq(_hd.files_spawned, 0, "H1: файлы ещё не спавнились")
	_eq(_hd.request_cap, int(h1.get("request_cap", -1)), "H1: кап запросов из данных")
	_eq(_hd.request_cap, 6, "H1: кап запросов 6")
	_eq(_hd.active_request_limit, int(h1.get("active_requests", -1)),
		"H1: active_requests из данных")
	_eq(_hd.active_request_limit, 2, "H1: 2 активных запроса")
	_approx(_hd.spawn_window, 300.0 * 0.75, 0.0001, "окно спавна 75% часа = 225 с")
	_eq(_hd.slots.max_slots(), 1, "H1: 1 слот")
	_eq(_hd.buffer_limit(), 6, "H1: буфер 6")
	_approx(_hd._recv_interval(), float(_difficulty_row(1).get("recv_interval", -1)),
		0.0001, "legacy recv_interval H1 из данных")
	_approx(_hd._receive_interval(), _hd.spawn_window / float(_hd.files_budget),
		0.0001, "спавн-интервал = окно / бюджет")
	_approx(_hd._send_interval(), float(h1.get("send_interval", -1)), 0.0001,
		"send_interval H1 из данных")
	_eq(_hd._max_requests(), int(h1.get("active_requests", -1)),
		"max concurrent requests H1 = active_requests")
	_eq(_hd._type_pool(), ["text", "sound"], "H1: только text/sound")
	_eq(_hd.active_packets.size(), 0, "активных пакетов нет")
	_eq(_hd.active_requests.size(), 1, "H1: стартовый запрос создан сразу")
	_eq(_hd.requests_spawned, 1, "H1: стартовый запрос учтён в капе")
	_eq(_game.registry.file_count(), 1, "H1: создан стартовый файл")
	var boot_req := str(_hd.active_requests.keys()[0])
	_eq(_hd.request_required_count(boot_req), 1, "H1: стартовый запрос на 1 файл")
	var boot_ids: Array = _hd.request_required_ids(boot_req)
	var boot_file = _game.registry.files.get(str(boot_ids[0]))
	_ok(boot_file != null and str(boot_file.type) == "text", "стартовый файл — text")
	if boot_file != null:
		_eq(str(boot_file.required_by), boot_req, "файл зарезервирован под запрос")
	_approx(float(_hd._next_spawn_at), 0.0, 0.0001, "H1: первый пакет в t=0")
	_ok(_hd.attack_director != null, "AttackDirector создан")
	_eq(_hd.attack_director._schedule.size(), 0, "H1: атак нет")
	_ok(_hd._minigame == null, "мини-игра не открыта")


# --- бюджеты и веса --------------------------------------------------------

func _test_budgets_and_weights() -> void:
	_set_case("budgets_weights")
	for h in [1, 2, 3, 4, 5, 6, 9]:
		_fresh(int(h))
		_eq(_hd.files_budget, int(_hour_row(int(h)).get("files", -1)),
			"H%d: бюджет из данных" % int(h))
	_eq(_hd.files_budget, 20, "H9: бюджет 20 файлов")
	for pair in [[1, 7], [2, 8], [3, 12], [4, 16], [5, 20], [6, 20], [9, 20]]:
		_fresh(int(pair[0]))
		_eq(_hd.files_budget, int(pair[1]),
			"H%d: бюджет %d" % [int(pair[0]), int(pair[1])])

	_fresh(1)
	var seen_h1: Dictionary = {}
	for i in range(400):
		var picked: String = str(_hd._pick_type())
		seen_h1[picked] = true
		_ok(picked == "text" or picked == "sound", "H1: вес photo/video = 0 (выбран %s)" % picked)
	_ok(seen_h1.has("text") and seen_h1.has("sound"), "H1: встречаются text и sound")

	_fresh(9)
	_eq(_hd._type_pool(), ["text", "sound", "photo", "video"], "H9: все типы открыты")
	var seen_h9: Dictionary = {}
	for i in range(400):
		seen_h9[_hd._pick_type()] = true
	_ok(seen_h9.has("photo"), "H9: photo спавнится")
	_ok(seen_h9.has("video"), "H9: video спавнится")

	_fresh(1)
	var seen_1: Dictionary = {}
	for i in range(300):
		seen_1[_hd._roll_required_count()] = true
	_ok(seen_1.size() >= 2, "H1: request_mix даёт 1 и 2 файла")
	_ok(not seen_1.has(3), "H1: request_mix 3 = 0%")

	_fresh(9)
	var seen_9: Dictionary = {}
	for i in range(400):
		seen_9[_hd._roll_required_count()] = true
	_ok(seen_9.has(1) and seen_9.has(2) and seen_9.has(3), "H9: request_mix даёт 1/2/3")
	_ok(seen_9.has(4), "H9: request_mix даёт 4 файла")


# --- перенос файлов --------------------------------------------------------

func _test_spawn_window_budget() -> void:
	_set_case("spawn_window_budget")
	_fresh(1)
	_hd.files_spawned = 0
	_hd.spawned_this_hour = 0
	_hd.requests_spawned = _hd.request_cap
	_hd.spawn_recv_accum = 0.0
	var folder_id := _folder_id()
	# Буфер H1 (6) меньше бюджета файлов (7): забираем пакеты в папку по мере
	# спавна, иначе седьмой файл законно ждёт освобождения места.
	for i in range(3000):
		_hd.tick(0.1)
		for pid in _hd.active_packets.keys().duplicate():
			var packet = _hd.active_packets.get(pid)
			if packet != null and packet.state == "waiting":
				_hd.receive_packet(str(pid), folder_id)
		if _hd.hour_elapsed >= _hd.spawn_window + 0.4:
			break
	_eq(_hd.files_spawned, _hd.files_budget, "H1: все 7 файлов успевают в окно")
	_eq(_hd.spawned_this_hour, _hd.files_budget, "H1: счётчик спавна = бюджет")
	_ok(_hd.active_packets.size() <= _hd.buffer_limit(),
		"в буфере не больше лимита буфера")
	_ok(_hd.hour_elapsed >= _hd.spawn_window and _hd.hour_elapsed <= _hd.spawn_window + 0.5,
		"спавн остановился у границы окна")
	_eq(_hd.carry_files, 0, "перенос ещё не рассчитан (час идёт)")


func _test_carry() -> void:
	_set_case("carry")
	_fresh(1)
	_eq(_hd.carry_files, 0, "старт: переноса нет")
	_hd.files_spawned = 1
	_hd.carry_files = 0
	_hd._finish_hour()
	_eq(_hd.carry_files, _hd.files_budget - 1, "недоспавненные файлы переносятся")
	_eq(int(_hd.report().get("files_carry", -1)), _hd.files_budget - 1,
		"отчёт: files_carry = бюджет − 1")

	_game.hour = 2
	_hd.start_hour(2)
	_eq(_hd.files_budget, mini(20, int(_hour_row(2).get("files", 8))
		+ int(_hour_row(1).get("files", 7)) - 1),
		"H2: базовые файлы + перенос")
	_eq(_hd.carry_files, 0, "перенос применён один раз")

	_hd.carry_files = 5
	_game.hour = 5
	_hd.start_hour(5)
	_eq(_hd.files_budget, 20, "кап 20 файлов в час")

	# Буфер полон: файл не теряется, бюджет не тратится.
	_fresh(1)
	_hd.files_budget = 8
	_hd.files_spawned = 0
	_hd.spawn_window = 999.0
	_hd._next_spawn_at = _hd.hour_elapsed
	_hd._spawn_frozen_notified = false
	_hd.spawn_recv_accum = 0.0
	var packet_ids: Array[String] = []
	for i in range(6):
		var pid := str(_hd.spawn_packet_now("text"))
		packet_ids.append(pid)
	_eq(_hd.active_packets.size(), 6, "буфер заполнен 6 пакетами")
	_frozen_events = 0
	_hd.tick(0.05)
	_eq(_hd.files_spawned, 0, "при полном буфере спавн стоит")
	_ok(_frozen_events > 0, "spawn_frozen(buffer_full) эмитится")
	_eq(_hd.active_packets.size(), 6, "пакеты не вытесняются")
	_hd._remove_packet(packet_ids[0])
	_hd._next_spawn_at = _hd.hour_elapsed
	_hd.spawn_recv_accum = 0.0
	_hd.tick(0.02)
	_eq(_hd.files_spawned, 1, "после освобождения места спавн продолжился")
	_eq(_hd.active_packets.size(), 6, "новый пакет занял освободившееся место")


# --- приём -----------------------------------------------------------------

func _test_receive() -> void:
	_set_case("receive")
	_fresh(1)
	var folder_id := _folder_id()
	_ok(not folder_id.is_empty(), "есть папка для приёма")
	var files_before: int = _game.registry.files.size()
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var packet_id := str(_hd.spawn_packet_now("text"))
	_ok(packet_id != "", "пакет заспавнен")
	var packet = _hd.active_packets[packet_id]
	_ok(not str(packet.shape_id).is_empty(), "у пакета есть фигура")
	_eq((packet.shape_cells as Array).size(), 1, "text занимает 1 клетку")
	_ok(int(packet.rotation) >= 0 and int(packet.rotation) <= 3, "rotation 0..3")

	_ok(_hd.receive_packet(packet_id, folder_id), "пакет принят в загрузку")
	_eq(str(packet.state), "loading", "state = loading")
	_eq(_hd.slots.used_count("in"), 1, "слот in занят")
	_eq(_game.registry.reservation_count(folder_id), 1, "клетки папки зарезервированы")
	_approx(_hd.channel_load(), 1.0, 0.0001, "loading text грузит канал на weight 1")

	for i in range(100):
		_hd.tick(0.1)
		if not _hd.active_packets.has(packet_id):
			break
	_ok(not _hd.active_packets.has(packet_id), "после загрузки пакет ушёл из буфера")
	_eq(_hd.slots.used_count("in"), 0, "слот in освобождён")
	_eq(_game.registry.reservation_count(folder_id), 0, "резервация снята")
	_eq(_game.registry.files.size(), files_before + 1, "файл создан")
	_eq(_game.money, money_before + 1, "recv_fee text = +1 $")
	_approx(_game.sla, sla_before, 0.0001, "приём не меняет SLA")
	var file = _game.registry.find_by_name(str(packet.file_name))
	_ok(file != null, "имя файла сохранено")
	if file != null:
		_eq(str(file.shape_id), str(packet.shape_id), "фигура файла = фигура пакета")


func _test_receive_cancel_and_no_space() -> void:
	_set_case("receive_cancel")
	_fresh(1)
	var folder_id := _folder_id()
	var packet_id := str(_hd.spawn_packet_now("text"))
	_ok(_hd.receive_packet(packet_id, folder_id), "загрузка начата")
	_hd._remove_packet(packet_id)
	_eq(_hd.slots.used_count("in"), 0, "отмена освободила слот")
	_eq(_game.registry.reservation_count(folder_id), 0, "отмена сняла резервацию")

	_set_case("receive_no_space")
	_fresh(1)
	folder_id = _folder_id()
	_fill_folder(folder_id)
	var packet2 := str(_hd.spawn_packet_now("text"))
	_ok(not _hd.receive_packet(packet2, folder_id), "полная папка отклоняет приём")
	_eq(_hd.slots.used_count("in"), 0, "отказ не занимает слот")
	_eq(_game.registry.reservation_count(folder_id), 0, "отказ не оставляет резервацию")
	_hd._remove_packet(packet2)

	_set_case("receive_slot_busy")
	_fresh(1)
	folder_id = _folder_id()
	_ok(_hd.slots.reserve("in", "blocker") >= 0, "слот занят вручную")
	var packet3 := str(_hd.spawn_packet_now("text"))
	_ok(not _hd.receive_packet(packet3, folder_id), "без слота приём отклонён")
	_eq(_game.registry.reservation_count(folder_id), 0, "слот-отказ не резервирует клетки")
	_hd.slots.release_by_entity("blocker")
	_hd._remove_packet(packet3)


# --- запросы ---------------------------------------------------------------

func _test_request_caps() -> void:
	var h1: Dictionary = _hour_row(1)
	var cap := int(h1.get("request_cap", 6))
	var active_limit := int(h1.get("active_requests", 2))

	_set_case("request_no_files")
	_fresh(1)
	_hd.requests_spawned = 0
	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	_hd.tick(30.0) # dt клампится до 0.1; 30 с малым шагом ниже
	for i in range(300):
		_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 0, "без файлов запрос не спавнится")
	_eq(_hd.requests_spawned, 0, "бюджет запросов не тратится")

	_set_case("request_active_limit")
	_fresh(1)
	for i in range(6):
		_new_file("Запрос", "text", _folder_id())
	_hd.requests_spawned = 0
	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 1, "H1: первый запрос создан")
	_eq(_hd.requests_spawned, 1, "H1: первый запрос учтён в бюджете")
	var req_id := str(_hd.active_requests.keys()[0])
	var req = _hd.active_requests[req_id]
	var required_ids: Array = _hd.request_required_ids(req_id)
	_ok(req.attached.is_empty(), "файлы не прикрепляются автоматически")
	_ok(req.required_count() == _hd.request_required_count(req_id),
		"required_count() = число слотов контейнера")
	_ok(required_ids.size() >= 1 and required_ids.size() <= 2,
		"H1: нужно 1–2 файла")
	for file_id in required_ids:
		_ok(_game.registry.files.has(file_id), "required — конкретный файл реестра")
	_eq(req.required_types.size(), required_ids.size(),
		"required_types заполнены при создании")
	_ok(not req.connected and not req.connecting, "новый TCP ещё не подключён")
	_ok(_hd.request_missing(req_id).size() == required_ids.size(),
		"request_missing = все required до прикрепления")
	_ok(_hd.request_required_names(req_id).size() == required_ids.size(),
		"request_required_names резолвит имена")
	_ok(not _hd.is_request_ready(req_id), "пустой запрос не готов")
	_ok(not req.is_ready(), "legacy Request.is_ready тоже false")
	_approx(req.time_left, req.timer_total, 0.0001,
		"таймер запроса стартует с полного значения")

	# Добираем активный лимит: после спавна интервал снова H1-й (12 с).
	for i in range(140):
		_hd.tick(0.1)
	_eq(_hd.active_requests.size(), active_limit,
		"H1: одновременно %d запроса" % active_limit)
	_eq(_hd.requests_spawned, active_limit, "H1: создано запросов = активный лимит")

	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	for i in range(20):
		_hd.tick(0.1)
	_eq(_hd.requests_spawned, active_limit,
		"при активном лимите новый запрос не появляется")

	_hd._cleanup_request(req_id, true)
	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	_hd.tick(0.15)
	_eq(_hd.active_requests.size(), active_limit,
		"после освобождения слота создан следующий запрос")
	_eq(_hd.requests_spawned, active_limit + 1,
		"освободившийся слот потратил бюджет запросов")

	# Добираем бюджет до капа: каждый новый запрос сразу освобождаем.
	for i in range(40):
		for rid in _hd.active_requests.keys().duplicate():
			_hd._cleanup_request(str(rid), true)
		_hd._send_interval_current = 0.1
		_hd.spawn_send_accum = 0.0
		_hd.tick(0.15)
		if _hd.requests_spawned >= cap:
			break
	_eq(_hd.requests_spawned, cap, "H1: кап запросов = %d" % cap)
	for rid in _hd.active_requests.keys().duplicate():
		_hd._cleanup_request(str(rid), true)
	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	_hd.tick(0.15)
	_eq(_hd.requests_spawned, cap, "сверх капа запрос не создаётся")
	_eq(_hd.active_requests.size(), 0, "лишних запросов нет")

	_set_case("request_clamp")
	_fresh(1)
	_new_file("Один", "text", _folder_id())
	var clamped_id := str(_hd.spawn_request_now(4))
	_ok(not clamped_id.is_empty(), "запрос создан при одном доступном файле")
	_eq(_hd.request_required_count(clamped_id), 1,
		"запрос на 4 файла зажат до размера пула (1)")
	_eq(_hd.request_missing(clamped_id).size(), 1, "нужен ровно один файл")


# --- анти-голодание --------------------------------------------------------

func _test_starvation_guard() -> void:
	_set_case("starvation_guard")
	_fresh(1)
	_eq(_hd.next_request_hint(), "Нет свободных файлов для запроса",
		"без файлов подсказка объясняет простой")
	var file = _new_file("Голод", "text", _folder_id())
	_ok(file != null, "файл создан")
	_eq(_hd.next_request_hint(), "Следующий запрос ~0 с",
		"с файлом запрос может появиться сразу")
	# send_interval H1 = 12 с; спавн должен случиться на первом же тике.
	_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 1, "запрос создан без ожидания интервала")
	_eq(_hd.requests_spawned, 1, "бюджет запросов потрачен")
	# Второй свободный файл + анти-голодание: добираемся до активного лимита.
	var file2 = _new_file("Голод 2", "text", _folder_id())
	_ok(file2 != null, "второй файл создан")
	for i in range(140):
		_hd.tick(0.1)
	_eq(_hd.active_requests.size(), _hd.active_request_limit,
		"активный лимит заполнен")
	_eq(_hd.next_request_hint(), "",
		"при занятом лимите активных запросов подсказка не нужна")
	# Даже при малом пуле запрос создаётся на 1 файл (clamp).
	var rid := str(_hd.active_requests.keys()[0])
	_eq(_hd.request_required_count(rid), 1, "запрос собрался из одного файла")
	for active_id in _hd.active_requests.keys().duplicate():
		_hd._cleanup_request(str(active_id), true)


# --- attach/detach ---------------------------------------------------------

func _test_attach_detach() -> void:
	_set_case("attach_detach")
	_fresh(1)
	var folder_id := _folder_id()
	var f1 = _new_file("Файл", "text", folder_id)
	var f2 = _new_file("Файл", "text", folder_id)
	var f3 = _new_file("Файл", "text", folder_id)
	_ok(f1 != null and f2 != null and f3 != null, "три файла созданы")
	if f1 == null or f2 == null or f3 == null:
		return
	var req_id: String = str(_hd.spawn_request_now(2))
	_ok(not req_id.is_empty(), "запрос на 2 файла создан")
	_eq(_hd.request_required_count(req_id), 2, "required_count = 2")
	var req = _hd.active_requests[req_id]
	var ids: Array = _hd.request_required_ids(req_id)
	_eq(ids.size(), 2, "required содержит 2 конкретных файла")

	_ok(_hd.attach_file(req_id, ids[0]), "файл 1 прикреплён")
	_eq(str(_game.registry.files[ids[0]].location), "attached",
		"файл 1 остался в папке (location attached)")
	_eq(req.attached.size(), 1, "attached = 1")
	_ok(not req.sending, "attach не запускает отправку")
	_ok(_hd.attach_file(req_id, ids[1]), "файл 2 прикреплён")
	_eq(req.attached.size(), 2, "attached = 2")
	_ok(not req.sending, "после заполнения автоотправки нет")
	_ok(_hd.is_request_ready(req_id), "собранный запрос готов")
	_eq(_hd.request_missing(req_id).size(), 0, "missing = 0 у собранного")

	# Лишний файл, которого нет в required, отклоняется.
	var extra_id := ""
	for file in [f1, f2, f3]:
		if not ids.has(str(file.id)):
			extra_id = str(file.id)
			break
	_ok(not extra_id.is_empty(), "есть файл вне required")
	_toasts.clear()
	_ok(not _hd.attach_file(req_id, extra_id), "файл вне required отклонён")
	_ok(_has_toast("Нужен файл:"), "тост «Нужен файл: …»")

	_ok(_hd.detach_file(req_id, ids[0]), "файл 1 откреплён")
	_eq(req.attached.size(), 1, "attached = 1 после detach")
	_eq(str(_game.registry.files[ids[0]].location), "folder",
		"detach вернул файл в папку")
	_eq(_hd.request_required_ids(req_id), ids, "detach не меняет required")
	_ok(not _hd.is_request_ready(req_id), "после detach запрос не готов")
	_ok(_hd.attach_file(req_id, ids[0]), "файл 1 прикреплён повторно")
	_ok(not _hd.detach_file(req_id, extra_id), "неприкреплённый файл не открепить")

	var req2: String = str(_hd.spawn_request_now(1))
	_ok(not req2.is_empty(), "второй запрос создан")
	var ids2: Array = _hd.request_required_ids(req2)
	_ok(ids2.size() == 1 and not ids.has(ids2[0]),
		"второй запрос берёт файл, не занятый первым")
	_ok(_hd.attach_file(req2, ids2[0]), "свободный файл прикреплён к другому запросу")
	_ok(not _hd.attach_file(req2, ids[0]),
		"файл, требуемый другим запросом, нельзя прикрепить")

	var f4 = _new_file("Резерв", "text", folder_id)
	if f4 != null:
		var fid4 := str(f4.id)
		var req3: String = str(_hd._create_request(1, "tcp", [fid4], false))
		_ok(not req3.is_empty(), "третий запрос создан")
		_eq(str(_game.registry.files[fid4].required_by), req3,
			"required_by выставлен при создании запроса")
		_ok(not _game.registry.move_file_to_table(fid4),
			"required-файл нельзя унести на стол")
		_ok(not _game.registry.remove_file(fid4, true),
			"required-файл нельзя удалить")
		_ok(_hd.attach_file(req3, fid4), "свой запрос может прикрепить резерв")
		_hd._cleanup_request(req3, true)
		_eq(str(_game.registry.files[fid4].required_by), "",
			"cleanup снял required_by")

	var f5 = _new_file("Стол", "text", folder_id)
	if f5 != null:
		var fid5 := str(f5.id)
		_ok(_game.registry.move_file_to_table(fid5), "свободный файл убран на стол")
		var req4: String = str(_hd._create_request(1, "tcp", [fid5], false))
		_ok(not _hd.attach_file(req4, fid5), "файл со стола нельзя прикрепить")
		_hd._cleanup_request(req4, true)
	_hd._cleanup_request(req_id, true)
	_hd._cleanup_request(req2, true)


# --- протокол --------------------------------------------------------------

func _test_protocol() -> void:
	_set_case("protocol")
	_fresh(1)
	var file = _new_file("Протокол", "text", _folder_id())
	var req_id: String = str(_hd._create_request(1, "tcp", [str(file.id)], false))
	_eq(str(_hd.active_requests[req_id].protocol), "tcp", "по умолчанию tcp")
	_ok(_hd.set_request_protocol(req_id, "udp"), "неподключённый tcp → udp разрешён")
	_eq(str(_hd.active_requests[req_id].protocol), "udp", "протокол udp")
	_ok(not _hd.set_request_protocol(req_id, "smtp"), "неизвестный протокол отклонён")
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_ok(_hd.start_send(req_id), "UDP: мини-игра отправки открыта")
	_ok(not _hd.set_request_protocol(req_id, "tcp"), "после старта мини-игры протокол не меняется")
	_hd.force_close_send_minigame()
	_hd._cleanup_request(req_id, true)

	_set_case("protocol_connected")
	var file2 = _new_file("Подключён", "text", _folder_id())
	var req2: String = str(_hd._create_request(1, "tcp", [str(file2.id)], true))
	_eq(str(_hd.active_requests[req2].protocol), "tcp", "TCP-запрос создан подключённым")
	_ok(not _hd.set_request_protocol(req2, "udp"),
		"connected-запрос нельзя переключить на UDP")
	_hd._cleanup_request(req2, true)


# --- мини-игра отправки ----------------------------------------------------

func _test_send_minigame_pause() -> void:
	_set_case("send_minigame_pause")
	_fresh(1)
	var file = _new_file("Мини", "text", _folder_id())
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_minigame_shows = 0
	_ok(_hd.start_send(req_id), "start_send → true")
	_eq(_minigame_shows, 1, "show_minigame эмитится")
	var req = _hd.active_requests[req_id]
	_ok(req.minigame_active, "minigame_active = true")
	_ok(_hd.is_minigame_active(), "директор видит открытую мини-игру")
	_ok(not _hd.is_request_ready(req_id), "запрос не готов во время мини-игры")
	var req_time: float = float(req.time_left)
	var hour_time: float = float(_hd.time_left)
	for i in range(10):
		_hd.tick(0.1)
	_approx(float(req.time_left), req_time, 0.0001, "таймер запроса заморожен мини-игрой")
	_approx(float(_hd.time_left), hour_time - 1.0, 0.02, "время часа продолжает идти")
	_hd.force_close_send_minigame()
	_hd._cleanup_request(req_id, true)


# --- очередь out-слота -----------------------------------------------------

func _test_out_slot_queue() -> void:
	_set_case("out_slot_queue")
	_fresh(1)
	var file = _new_file("Очередь", "text", _folder_id())
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	var blocker := int(_hd.slots.reserve("out", "blocker"))
	_ok(blocker >= 0, "слот занят другим запросом")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests[req_id]
	_ok(_hd.is_request_queued(req_id), "нет слота → запрос в очереди")
	_ok(not req.sending, "отправка ещё не идёт")
	_ok(not req.minigame_active, "мини-игра закрыта")
	var frozen: float = float(req.time_left)
	for i in range(10):
		_hd.tick(0.1)
	_approx(float(req.time_left), frozen, 0.0001, "таймер в очереди заморожен")

	_hd.slots.release(blocker)
	_ok(not _hd.is_request_queued(req_id), "слот освободился — запрос снят с очереди")
	_ok(req.sending, "отправка стартовала автоматически")
	var money_before: int = _game.money
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "запрос завершён после очереди")
	_ok(_game.money > money_before, "выплата за отправку начислена")


# --- расход файлов ---------------------------------------------------------

func _test_file_consumption() -> void:
	_set_case("consume_on_send")
	_fresh(1)
	var file = _new_file("Расход", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests[req_id]
	_ok(req.sending, "отправка пошла после мини-игры")
	var money_before: int = _game.money
	var streak_before: int = int(_game.streak)
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "запрос закрыт")
	_ok(not _game.registry.files.has(file_id), "успешная отправка израсходовала файл")
	_ok(_game.money > money_before, "выплата начислена")
	_eq(int(_game.streak), streak_before + 1, "streak увеличен")
	_eq(_hd._completed, 1, "completed = 1")
	_ok(_hd.slots.used_count("out") == 0, "out-слот освобождён")


## D2: после старта отправки time_left заморожен, даже если до нуля оставалось
## 1 с, а передача длится 3 с — запрос обязан дойти, а не упасть по таймауту.
func _test_send_timer_freeze() -> void:
	_set_case("send_timer_freeze")
	_fresh(1)
	var file = _new_file("Заморозка", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests.get(req_id)
	_ok(req != null, "запрос жив после мини-игры")
	if req == null:
		return
	_ok(req.sending, "отправка идёт")
	req.time_left = 1.0
	req.send_duration = 3.0
	req.send_progress = 0.0
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	for i in range(31):
		_hd.tick(0.1)
	_ok(not _hd.active_requests.has(req_id),
		"запрос завершился успешно, а не по таймауту")
	_ok(not _game.registry.files.has(file_id), "файл израсходован успешной отправкой")
	_ok(int(_game.money) > money_before,
		"выплата начислена (%d → %d)" % [money_before, int(_game.money)])
	_approx(float(_game.sla), sla_before, 0.001,
		"таймаут не списал SLA во время отправки")
	_eq(_hd._failed, 0, "провалов нет")


func _test_timeout_preserves_files() -> void:
	_set_case("timeout_keeps_files")
	_fresh(1)
	var file = _new_file("Таймаут", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	var req = _hd.active_requests.get(req_id)
	_ok(req != null and not req.sending, "запрос ещё НЕ отправляется")
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	req.time_left = 0.05
	_hd.tick(0.1)
	_ok(not _hd.active_requests.has(req_id), "неотправленный запрос снят по таймауту")
	_ok(_game.registry.files.has(file_id), "при таймауте файл НЕ расходуется")
	var kept = _game.registry.files.get(file_id)
	if kept != null:
		_eq(str(kept.location), "folder", "файл вернулся в папку")
	_eq(_game.money, money_before, "штраф только по SLA, без денег")
	_approx(_game.sla, sla_before - 12.0, 0.001, "таймаут H1: −(10+2×1) SLA")
	_eq(_hd._failed, 1, "провал учтён")


# --- конец часа во время мини-игры (B5b) -----------------------------------

func _test_hour_end_during_minigame() -> void:
	_set_case("hour_end_minigame")
	_fresh(1)
	var file = _new_file("Конец", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	_hd.time_left = 5.0
	_ok(_hd.start_send(req_id), "мини-игра открыта на 295-й секунде")
	_ok(_hd.is_minigame_active(), "мини-игра активна")
	_hour_events = 0
	_minigame_cancels = 0
	var money_before: int = _game.money
	for i in range(80):
		_hd.tick(0.1)
		if not _hd.running:
			break
	_ok(not _hd.running, "час завершился при открытой мини-игре")
	_eq(_hour_events, 1, "hour_finished эмитится один раз")
	_eq(_minigame_cancels, 1, "minigame_cancelled эмитится")
	_ok(_hd._minigame == null, "мини-игра принудительно закрыта")
	_ok(not _hd.active_requests.has(req_id), "запрос не отправлен и снят")
	_ok(_game.registry.files.has(file_id), "файл не израсходован")
	_eq(_game.money, money_before, "выплаты нет")
	_ok(_hour_report.has("files_carry"), "отчёт содержит files_carry")
	_ok(_hour_report.has("packets_left"), "отчёт содержит packets_left")


# --- TCP-соединение --------------------------------------------------------

func _test_connection_flow() -> void:
	_set_case("connection")
	_fresh(1)
	var folder_id := _folder_id()
	var file = _new_file("Соединение", "text", folder_id)
	_ok(file != null, "файл создан")
	if file == null:
		return
	var file_id := str(file.id)
	var req_id := str(_hd._create_request(1, "tcp", [file_id], false))
	_ok(not req_id.is_empty(), "TCP-запрос создан")
	var req = _hd.active_requests.get(req_id)
	_ok(req != null and not req.connected and not req.connecting,
		"новый TCP не подключён")
	_ok(not _hd.is_request_connected(req_id), "is_request_connected = false")
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")

	var money_before := int(_game.money)
	_connection_shows = 0
	_ok(_hd.start_send(req_id), "start_send запускает соединение")
	_eq(_connection_shows, 1, "show_connection эмитится один раз")
	_eq(_connection_request_id, req_id, "show_connection: request_id")
	_eq(_connection_hour, _hd.hour, "show_connection: hour")
	_eq(_connection_successes, 0, "show_connection: successes за забег")
	_ok(req.connecting and not req.minigame_active,
		"connecting=true, мини-игра отправки не открыта")
	_eq(req.connect_attempts, 1, "connect_attempts = 1")
	_ok(not _hd.start_send(req_id), "повторный start_send во время connecting → false")
	_ok(not _hd.connect_request(req_id), "connect_request во время connecting → false")

	var req_time := float(req.time_left)
	var hour_time := float(_hd.time_left)
	for i in range(10):
		_hd.tick(0.1)
	_approx(float(req.time_left), req_time, 0.0001,
		"таймер запроса заморожен во время соединения")
	_approx(float(_hd.time_left), hour_time - 1.0, 0.02, "время часа идёт")

	var sla_before_fail := float(_game.sla)
	_toasts.clear()
	_ok(_hd.connection_finished(req_id, false, true),
		"connection_finished(false, missed=true) принят")
	_ok(not req.connecting and not req.connected, "неудача сбрасывает connecting")
	_ok(_has_toast("СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО"), "тост о неустановленном соединении")
	_eq(int(_game.money), money_before, "неудача соединения без денежного штрафа")
	_approx(float(_game.sla), sla_before_fail - 4.0, 0.001,
		"промах соединения: −4 SLA")
	_approx(float(req.connect_cooldown_until), float(_hd.hour_elapsed) + 8.0, 0.01,
		"промах: кулдаун 8 с")
	_ok(_hd.is_request_ready(req_id), "после неудачи запрос готов к повтору")
	_toasts.clear()
	_ok(not _hd.start_send(req_id), "start_send во время кулдауна → false")
	_ok(_has_toast("ПОВТОР ЧЕРЕЗ"), "тост о кулдауне соединения")

	_hd.hour_elapsed = float(req.connect_cooldown_until) + 0.01
	var sla_after_miss := float(_game.sla)
	_connection_shows = 0
	_ok(_hd.connect_request(req_id), "connect_request запускает повтор")
	_eq(req.connect_attempts, 2, "connect_attempts = 2")
	_eq(_connection_shows, 1, "повторный show_connection")
	_ok(_hd.connection_finished(req_id, false, false),
		"connection_finished(false, missed=false) — отмена")
	_approx(float(_game.sla), sla_after_miss, 0.001, "отмена соединения без SLA")
	_approx(float(req.connect_cooldown_until), float(_hd.hour_elapsed) + 4.0, 0.01,
		"отмена: кулдаун 4 с")

	_hd.hour_elapsed = float(req.connect_cooldown_until) + 0.01
	_connection_shows = 0
	_ok(_hd.connect_request(req_id), "третья попытка соединения")
	_eq(req.connect_attempts, 3, "connect_attempts = 3")
	_eq(_connection_shows, 1, "show_connection на третью попытку")
	_minigame_shows = 0
	_ok(_hd.connection_finished(req_id, true), "connection_finished(true) принят")
	_ok(req.connected, "connected = true после успеха")
	_approx(float(req.connect_cooldown_until), 0.0, 0.001, "успех снял кулдаун")
	_eq(_hd.connect_successes, 1, "connect_successes = 1")
	_eq(_minigame_shows, 1, "после соединения открылась мини-игра отправки")
	_ok(req.minigame_active, "мини-игра отправки активна")
	_hd.force_close_send_minigame()
	_hd._cleanup_request(req_id, true)

	# UDP не требует соединения: сразу мини-игра отправки.
	var file2 = _new_file("УДП", "text", folder_id)
	if file2 != null:
		var rid2 := str(_hd._create_request(1, "udp", [str(file2.id)], false))
		_ok(_hd.attach_file(rid2, str(file2.id)), "UDP-файл прикреплён")
		_connection_shows = 0
		_ok(_hd.start_send(rid2), "UDP стартует отправку")
		_eq(_connection_shows, 0, "UDP не показывает соединение")
		_ok(bool(_hd.active_requests[rid2].minigame_active), "UDP: мини-игра отправки")
		_hd.force_close_send_minigame()
		_hd._cleanup_request(rid2, true)

	# Исчезновение required-файла: запрос остаётся отклоняемым.
	var file3 = _new_file("Пропажа", "text", folder_id)
	if file3 != null:
		var fid3 := str(file3.id)
		var rid3 := str(_hd._create_request(1, "udp", [fid3], true))
		_ok(_hd.attach_file(rid3, fid3), "файл прикреплён")
		_game.registry.consume_file(fid3)
		_hd.tick(0.1)
		_eq(_hd.request_missing(rid3), [fid3], "исчезнувший файл снова в missing")
		_eq(_hd.request_missing_names(rid3), ["ПОТЕРЯН"], "имя потерянного файла")
		_ok(not _hd.start_send(rid3), "запрос без required-файла не отправить")
		_ok(_hd.reject_request(rid3), "запрос можно отклонить")

	_ok(not _hd.connect_packet("pkt_x"), "connect_packet — заглушка false")
	_eq(_connection_shows, 0, "приём пакетов не требует соединения")


# --- потерянные required-файлы ---------------------------------------------

func _test_lost_required() -> void:
	_set_case("lost_required_substitute")
	_fresh(1)
	var folder_id := _folder_id()
	var f1 = _new_file("Потеря", "text", folder_id)
	var f2 = _new_file("Замена", "text", folder_id)
	_ok(f1 != null and f2 != null, "два файла созданы")
	if f1 == null or f2 == null:
		return
	var fid1 := str(f1.id)
	var fid2 := str(f2.id)
	var req_id := str(_hd._create_request(1, "tcp", [fid1], false))
	_eq(str(_game.registry.files[fid1].required_by), req_id, "резерв на первом файле")
	_game.registry.mark_failed(fid1)
	for i in range(6):
		_hd.tick(0.1)
	var ids: Array = _hd.request_required_ids(req_id)
	_eq(ids.size(), 1, "required не раздулся")
	_eq(str(ids[0]), fid2, "потерянный файл заменён однотипным")
	_eq(str(_game.registry.files[fid1].required_by), "", "required_by старого снят")
	_eq(str(_game.registry.files[fid2].required_by), req_id, "required_by нового выставлен")
	_eq(_hd.request_missing(req_id), [fid2], "новый файл ожидает прикрепления")
	_ok(_hd.attach_file(req_id, fid2), "замену можно прикрепить")
	_hd._cleanup_request(req_id, true)

	_set_case("lost_required_none")
	_fresh(1)
	folder_id = _folder_id()
	var only = _new_file("Единственный", "text", folder_id)
	if only == null:
		return
	var fid_only := str(only.id)
	var rid2 := str(_hd._create_request(1, "udp", [fid_only], true))
	_game.registry.consume_file(fid_only)
	for i in range(6):
		_hd.tick(0.1)
	_eq(_hd.request_required_ids(rid2), [fid_only], "без замены required остаётся прежним")
	_eq(_hd.request_missing(rid2), [fid_only], "файл числится missing")
	_eq(_hd.request_missing_names(rid2), ["ПОТЕРЯН"], "имя потерянного файла")
	_ok(not _hd.start_send(rid2), "запрос без файла не отправить")
	_ok(_hd.reject_request(rid2), "запрос можно отклонить")


# --- C1/C2: модалка блокирует второй старт --------------------------------

func _test_modal_guard() -> void:
	_set_case("modal_guard")
	_fresh(1)
	var file = _new_file("Модалка", "text", _folder_id())
	if file == null:
		return
	var req_id := str(_hd._make_request([file], "udp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_minigame_shows = 0
	_hd.set_modal_open(true)
	_ok(not _hd.start_send(req_id), "C2: start_send при modal_open → false")
	_ok(_hd._minigame == null, "C2: вторая мини-игра не создана")
	_ok(str(_hd._minigame_request_id).is_empty(), "C2: request_id мини-игры пуст")
	var req = _hd.active_requests.get(req_id)
	_ok(req != null and not bool(req.minigame_active),
		"C2: minigame_active не выставлен")
	_eq(_minigame_shows, 0, "C2: show_minigame не эмитился")
	_ok(_has_toast("закройте текущее окно"), "C2: тост о занятом окне")
	_hd.set_modal_open(false)
	_ok(_hd.start_send(req_id), "после закрытия модалки отправка стартует")
	_hd.force_close_send_minigame()
	_hd._cleanup_request(req_id, true)

	# То же для TCP-соединения: модалка не даёт начать connecting.
	_fresh(1)
	var file2 = _new_file("Модалка TCP", "text", _folder_id())
	if file2 == null:
		return
	var req2 := str(_hd._make_request([file2], "tcp", false, "", ""))
	_ok(_hd.attach_file(req2, str(file2.id)), "TCP-файл прикреплён")
	_connection_shows = 0
	_hd.set_modal_open(true)
	_ok(not _hd.connect_request(req2), "C2: connect_request при modal_open → false")
	var req2_live = _hd.active_requests.get(req2)
	_ok(req2_live != null and not bool(req2_live.connecting),
		"C2: connecting не выставлен")
	_eq(_connection_shows, 0, "C2: show_connection не эмитился")
	_hd.set_modal_open(false)
	_hd._cleanup_request(req2, true)


# --- M4: required_types принадлежат слотам, а не порядку вложений ----------

func _test_required_types_stable() -> void:
	_set_case("required_types_stable")
	_fresh(1)
	var folder := _folder_id()
	var f_text = _new_file("Слот текст", "text", folder)
	var f_sound = _new_file("Слот звук", "sound", folder)
	if f_text == null or f_sound == null:
		return
	var t_id := str(f_text.id)
	var s_id := str(f_sound.id)
	var req_id := str(_hd._create_request(2, "udp", [t_id, s_id], true))
	var req = _hd.active_requests.get(req_id)
	if req == null:
		return
	var expected: Array = req.required_types.duplicate()
	_eq(expected, ["text", "sound"], "required_types по слотам при создании")
	# Прикрепляем в обратном порядке: раньше это перезаписывало типы слотов.
	_ok(_hd.attach_file(req_id, s_id), "прикреплён sound")
	_ok(_hd.attach_file(req_id, t_id), "прикреплён text")
	_eq(req.required_types, expected,
		"M4: attach не перезаписывает required_types порядком вложений")
	_ok(_hd.start_send(req_id), "UDP-мини-игра открыта")
	_eq(req.required_types, expected,
		"M4: start_send не перезаписывает required_types вложенными типами")
	_hd.force_close_send_minigame()
	_hd._cleanup_request(req_id, true)


# --- M5: во время передачи потеря не подменяется ---------------------------

func _test_no_substitute_while_sending() -> void:
	_set_case("no_substitute_while_sending")
	_fresh(1)
	var folder := _folder_id()
	var f1 = _new_file("В пути", "text", folder)
	var f2 = _new_file("Резерв замены", "text", folder)
	if f1 == null or f2 == null:
		return
	var fid := str(f1.id)
	var req_id := str(_hd._make_request([f1], "udp", false, "", ""))
	_ok(_hd.attach_file(req_id, fid), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests.get(req_id)
	if req == null:
		return
	_ok(bool(req.sending), "передача началась")
	req.send_duration = 100.0
	req.send_progress = 0.0
	_game.registry.mark_failed(fid)
	for i in range(12):
		_hd.tick(0.1)
	_eq(_hd.request_required_ids(req_id), [fid],
		"M5: во время отправки потерянный required не подменяется")
	_ok(not _hd.request_required_ids(req_id).has(str(f2.id)),
		"M5: резервный файл не встал в required")
	_hd._cleanup_request(req_id, true)


# --- отчёт -----------------------------------------------------------------

func _test_report() -> void:
	_set_case("report")
	_fresh(2)
	_eq(_hd.request_cap, int(_hour_row(2).get("request_cap", -1)),
		"H2: кап запросов из данных")
	_eq(_hd.active_request_limit, int(_hour_row(2).get("active_requests", -1)),
		"H2: активный лимит из данных")
	var file = _new_file("Отчёт", "sound", _folder_id())
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_minigame_shows = 0
	_hd._on_send_minigame_finished(0.8)
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_hour_events = 0
	_hd._finish_hour()
	_eq(_hour_events, 1, "hour_finished один раз")
	for key in ["hour", "earned", "money_delta", "completed", "failed", "attacks",
			"attacks_failed", "sla_delta", "time_left", "packets_left",
			"requests_left", "files_carry"]:
		_ok(_hour_report.has(key), "отчёт содержит %s" % key)
	_eq(int(_hour_report.get("hour", 0)), 2, "отчёт: hour = 2")
	_eq(int(_hour_report.get("completed", 0)), 1, "отчёт: completed = 1")
	_ok(int(_hour_report.get("files_budget", 0)) == 8, "отчёт: files_budget H2 = 8")


# --- подготовка перед H1 ---------------------------------------------------

## reset_for_prep() оставляет seed-файл, но без активных запросов и резерваций;
## старт H1 после этого всё равно выдаёт запрос (starvation guard / bootstrap).
func _test_reset_for_prep() -> void:
	_set_case("reset_for_prep")
	_game.start_new_run(515)
	_game.hour = 1
	_game.phase = &"hour"
	_hd.reset_carry()
	_hd.reset_for_prep()
	_eq(_hd.hour, 1, "reset_for_prep: час 1")
	_eq(_hd.active_requests.size(), 0, "reset_for_prep: нет активных запросов")
	_eq(_hd.active_packets.size(), 0, "reset_for_prep: нет активных пакетов")
	_eq(_hd.requests_spawned, 0, "reset_for_prep: requests_spawned = 0")
	_ok(not _hd.running, "reset_for_prep: директор не запущен")
	_eq(_game.registry.file_count(), 1, "reset_for_prep: seed-файл остался")
	var reserved: Array = []
	for file in _game.registry.files.values():
		if file != null and not str(file.required_by).is_empty():
			reserved.append(str(file.id))
	_eq(reserved.size(), 0, "reset_for_prep: ни один файл не зарезервирован")

	# Старт реального часа: seed уже есть → bootstrap не дублируется,
	# запрос создаёт starvation guard на первом же тике.
	_hd.start_hour(1)
	_eq(_game.registry.file_count(), 1, "старт H1: второй seed не создан")
	var spawned_at := -1.0
	for i in range(50):
		_hd.tick(0.1)
		if not _hd.active_requests.is_empty():
			spawned_at = float(_hd.hour_elapsed)
			break
	_eq(_hd.active_requests.size(), 1, "старт H1: запрос появился")
	_ok(spawned_at >= 0.0 and spawned_at <= 0.5,
		"H1: запрос сразу на старте (t=%.1f)" % spawned_at)
	if not _hd.active_requests.is_empty():
		var req_id := str(_hd.active_requests.keys()[0])
		var ids: Array = _hd.request_required_ids(req_id)
		_ok(ids.size() >= 1, "H1: запрос требует файл")
		for fid in ids:
			var file = _game.registry.files.get(str(fid))
			_ok(file != null and str(file.required_by) == req_id,
				"H1: required_by снова выставлен")


# --- перемещение зарезервированного файла -----------------------------------

## Решение (BUG 4): зарезервированный файл можно переносить между папками.
## Запрос ищет файл по id, поэтому остаётся выполнимым из любой папки.
func _test_move_required_file() -> void:
	_set_case("move_required_file")
	_game.start_new_run(616)
	_game.hour = 1
	_game.phase = &"hour"
	_hd.reset_carry()
	_hd.reset_for_prep()
	var folder_ids: Array = _game.registry.folders.keys()
	if folder_ids.size() < 2:
		_ok(false, "нужно минимум 2 папки")
		return
	var from_id := str(folder_ids[0])
	var to_id := str(folder_ids[1])
	var file = _new_file("Перемещаемый резерв", "text", from_id)
	_ok(file != null, "файл создан")
	if file == null:
		return
	var fid := str(file.id)
	var req_id := str(_hd._create_request(1, "udp", [fid], true))
	_ok(not req_id.is_empty(), "запрос создан")
	if req_id.is_empty():
		return
	_eq(str(file.required_by), req_id, "файл зарезервирован")
	_ok(bool(_game.registry.move_file(fid, to_id)),
		"move_file зарезервированного файла разрешён")
	_eq(str(_game.registry.files[fid].folder_id), to_id,
		"файл переехал в другую папку")
	_eq(str(_game.registry.files[fid].required_by), req_id,
		"резерв сохранился после перемещения")
	_ok(_hd.attach_file(req_id, fid), "запрос всё ещё может прикрепить файл")
	_ok(_hd.is_request_ready(req_id), "запрос готов к отправке после перемещения")
	_hd._cleanup_request(req_id, true)


# --- служебное -------------------------------------------------------------

## Строка hours[] из data/balance.json (null-safe для --script прогона).
func _hour_row(hour: int) -> Dictionary:
	var data := root.get_node_or_null("Data")
	if data != null and data.has_method("hour_def"):
		return data.hour_def(int(hour))
	return {}


func _difficulty_row(hour: int) -> Dictionary:
	var data := root.get_node_or_null("Data")
	if data != null and data.has_method("difficulty_for"):
		return data.difficulty_for(int(hour))
	return {}


func _fresh(hour: int, keep_seed: bool = false) -> void:
	_game.start_new_run(1000 + int(hour) * 17)
	_game.hour = int(hour)
	_game.phase = &"hour"
	_game.money = 500
	_game.sla = 100.0
	_game.upgrades["sla_level"] = 4
	_hd.reset_carry()
	_hd.start_hour(int(hour))
	_hd.set_time_scale(1.0)
	if hour == 1 and not keep_seed:
		_drop_bootstrap_seed()
	if _hd.attack_director != null:
		_hd.attack_director._schedule.clear()
		_hd.attack_director._next_index = 0
	_hour_events = 0
	_hour_report = {}
	_minigame_cancels = 0
	_toasts.clear()


## Убирает H1-затравку (файл+запрос), чтобы старые кейсы стартовали с пустого склада.
func _drop_bootstrap_seed() -> void:
	for req_id in _hd.active_requests.keys().duplicate():
		_hd._cleanup_request(str(req_id), true)
	for file in _game.registry.files.values().duplicate():
		_game.registry.consume_file(str(file.id))
	_hd.requests_spawned = 0
	_hd._last_request_attempt_t = -_hd.REQUEST_ATTEMPT_MIN_GAP
	_hd.spawn_send_accum = 0.0
	_hd.spawn_recv_accum = 0.0
	_hd._next_spawn_at = 0.0


func _reset(hour: int) -> void:
	_fresh(hour)
	_hd.files_spawned = _hd.files_budget
	_hd.requests_spawned = _hd.request_cap
	_hd.spawn_recv_accum = 0.0
	_hd.spawn_send_accum = 0.0


func _folder_id() -> String:
	var section = _game.registry.sections.get("C")
	if section == null:
		return ""
	if section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _new_file(base: String, type: String, folder_id: String):
	_name_seq += 1
	return _game.registry.create_file("%s %d" % [base, _name_seq], type, folder_id)


func _fill_folder(folder_id: String) -> void:
	var guard := 0
	while guard < 100:
		guard += 1
		_name_seq += 1
		var f = _game.registry.create_file("Заполнение %d" % _name_seq, "text", folder_id)
		if f == null:
			return


func _on_hour_finished(report: Dictionary) -> void:
	_hour_events += 1
	_hour_report = report


func _on_show_minigame(_game_node) -> void:
	_minigame_shows += 1


func _on_minigame_cancelled(_req_id: String) -> void:
	_minigame_cancels += 1


func _on_minigame_closed(_req_id: String) -> void:
	_minigame_closes += 1


func _on_spawn_frozen(_reason: String) -> void:
	_frozen_events += 1


func _on_show_connection(request_id: String, hour: int, successes: int) -> void:
	_connection_shows += 1
	_connection_request_id = request_id
	_connection_hour = hour
	_connection_successes = successes


func _on_toast(text: String) -> void:
	_toasts.append(text)


func _has_toast(fragment: String) -> bool:
	for text in _toasts:
		if str(text).contains(fragment):
			return true
	return false


# --- assert-хелперы --------------------------------------------------------

func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message)
	return false


func _eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_fail("%s — получено %s, ожидалось %s" % [message, str(actual), str(expected)])
	return false


func _approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, float(actual), float(expected)])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	if _hd != null and is_instance_valid(_hd):
		_hd.free()
	print("test_hour: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_hour" if _fails == 0 else "FAIL test_hour")
	quit(0 if _fails == 0 else 1)
