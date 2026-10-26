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
const R := preload("res://scripts/core/file_registry.gd")
const REQUEST_CARD := preload("res://scripts/ui/request_card.gd")


## Заглушка мини-игры отправки: сигнал есть, но процесс не идёт.
class StubSendGame extends Node:
	signal finished(quality)

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
var _frozen_reasons: Array[String] = []
var _toasts: Array[String] = []


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		await _finish()
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
	_test_request_type_weights()
	_test_spawn_window_budget()
	_test_carry()
	_test_receive()
	_test_receive_cancel_and_no_space()
	_test_receive_geometry()
	_test_request_caps()
	_test_rate_no_cap_h9()
	_test_starvation_guard()
	_test_overflow_no_space()
	_test_spawn_fitting_type()
	_test_fit_anywhere_rotation_and_blocked()
	_test_duration_fallback()
	_test_attach_detach()
	_test_protocol()
	_test_send_minigame_pause()
	_test_out_slot_queue()
	_test_file_consumption()
	_test_send_timer_freeze()
	_test_timeout_preserves_files()
	_test_overtime()
	_test_overtime_complete_request()
	_test_overtime_no_requests()
	_test_hour_end_during_minigame()
	_test_connection_flow()
	_test_tcp_model_edges()
	_test_tcp_disconnect_cases()
	_test_udp_model()
	_test_spawn_request_protocol()
	_test_low_quality_retry()
	_test_lost_required()
	_test_modal_guard()
	_test_required_types_stable()
	_test_no_substitute_while_sending()
	_test_report()
	_test_report_reconcile()
	_test_reset_for_prep()
	_test_move_required_file()
	await _finish()


# --- старт -----------------------------------------------------------------

func _test_start_hour() -> void:
	_set_case("start_hour")
	_fresh(1, true)
	_eq(_hd.hour, 1, "hour = 1")
	_approx(_hd.time_left, 120.0, 0.0001, "длительность часа H1 = 120 с")
	_approx(_hd.hour_duration(), 120.0, 0.0001, "hour_duration() = 120")
	_approx(_hd.hour_seconds(), 120.0, 0.0001, "hour_seconds() = 120")
	_ok(_hd.running, "час запущен")
	# v4: значения берём из data/balance.json → hours[0].
	var h1: Dictionary = _hour_row(1)
	_eq(_hd.files_budget, int(h1.get("files", -1)), "H1: базовый темп файлов из данных")
	_eq(_hd.files_budget, 8, "H1: 8 файлов (только темп, без лимита)")
	_eq(_hd.files_spawned, 0, "H1: файлы ещё не спавнились")
	_eq(_hd.get("request_cap"), null, "request_cap удалён из HourDirector")
	_ok(not h1.has("request_cap"), "H1: request_cap удалён из данных часа")
	_ok(not h1.has("recv_interval"), "H1: recv_interval удалён из данных часа")
	_eq(_hd.active_request_limit, int(h1.get("active_requests", -1)),
		"H1: active_requests из данных")
	_eq(_hd.active_request_limit, 2, "H1: 2 активных запроса")
	_approx(_hd.spawn_window, 90.0, 0.0001, "окно спавна 75% часа = 90 с")
	_eq(_hd.slots.max_slots(), 1, "H1: 1 слот")
	_eq(_hd.buffer_limit(), 6, "H1: буфер 6")
	_approx(_hd._receive_interval(), 11.25, 0.0001, "спавн-интервал = 90 / 8 = 11.25")
	_approx(_hd._send_interval(), 20.0, 0.0001, "send_interval H1 = 20")
	_eq(_hd._max_requests(), 2, "max concurrent requests H1 = 2")
	_eq(_hd._type_pool(), ["text"], "H1: только text")
	_eq(_hd.active_packets.size(), 0, "активных пакетов нет")
	# H1 bootstrap: 1 seed-файл + 1 запрос на него.
	_eq(_hd.active_requests.size(), 1, "H1: стартовый запрос создан сразу")
	_eq(_hd.requests_spawned, 1, "H1: ровно один bootstrap-запрос")
	_eq(_game.registry.file_count(), 1, "H1: создан ровно один seed-файл")
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
	var expected_files := [8, 8, 9, 10, 11, 11, 12, 12, 12]
	var expected_duration := [120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0, 360.0]
	for h in range(1, 10):
		_fresh(int(h))
		_eq(_hd.files_budget, expected_files[h - 1],
			"H%d: бюджет %d файлов" % [h, expected_files[h - 1]])
		_approx(_hd.hour_duration(), expected_duration[h - 1], 0.0001,
			"H%d: длительность %.0f с" % [h, expected_duration[h - 1]])
		_approx(_hd.time_left, expected_duration[h - 1], 0.0001,
			"H%d: time_left = длительность часа" % h)
		_approx(_hd.spawn_window, expected_duration[h - 1] * 0.75, 0.0001,
			"H%d: окно спавна 75%% часа" % h)
		_approx(_hd._receive_interval(),
			_hd.spawn_window / float(expected_files[h - 1]), 0.0001,
			"H%d: интервал = окно / бюджет" % h)

	_fresh(1)
	var seen_h1: Dictionary = {}
	for i in range(200):
		var picked: String = str(_hd._pick_type())
		seen_h1[picked] = true
		_ok(picked == "text", "H1: только text (выбран %s)" % picked)
	_eq(seen_h1.size(), 1, "H1: пул типов = один text")
	_ok(seen_h1.has("text"), "H1: text спавнится")
	_eq(_hd._type_pool(), ["text"], "H1: _type_pool = [text]")

	# Пороги открытия типов: sound со H2, photo с H4, video с H6.
	_fresh(2)
	_eq(_hd._type_pool(), ["text", "sound"], "H2: text/sound")
	_fresh(3)
	_eq(_hd._type_pool(), ["text", "sound"], "H3: photo ещё закрыт")
	_fresh(4)
	_eq(_hd._type_pool(), ["text", "sound", "photo"], "H4: +photo")
	_fresh(6)
	_eq(_hd._type_pool(), ["text", "sound", "photo", "video"], "H6: +video")

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
	_eq(seen_1.keys(), [1], "H1: request_mix всегда 1 файл")

	_fresh(9)
	var seen_9: Dictionary = {}
	for i in range(400):
		seen_9[_hd._roll_required_count()] = true
	var keys_9: Array = seen_9.keys()
	keys_9.sort()
	_eq(keys_9, [3, 4], "H9: request_mix только 3/4 файла")
	_ok(seen_9.has(3) and seen_9.has(4), "H9: встречаются и 3, и 4 файла")


# --- веса типов в запросах -------------------------------------------------

## v5: required-файлы выбираются по request_type_weights (не по весам приёма),
## без дублей; strict filter не даёт собрать запрос из «закрытых» типов;
## пустой конфиг весов → uniform fallback.
func _test_request_type_weights() -> void:
	_set_case("request_type_weights")
	_fresh(9)
	_approx(float(_hd.request_type_weights.get("text", 0.0)), 0.10, 0.0001,
		"H9: request text 0.10")
	_approx(float(_hd.request_type_weights.get("video", 0.0)), 0.45, 0.0001,
		"H9: request video 0.45")

	# Пул из словарей: _pick_request_files понимает id/type без реестра.
	var pool: Array = []
	for type_id in ["text", "sound", "photo", "video"]:
		for i in range(2):
			pool.append({"id": "%s_%d" % [type_id, i], "type": type_id})
	var type_by_id := {}
	for item in pool:
		type_by_id[str(item.get("id", ""))] = str(item.get("type", ""))

	var counts := {"text": 0, "sound": 0, "photo": 0, "video": 0}
	for i in range(400):
		var picked: Array = _hd._pick_request_files(pool, 1)
		if picked.size() != 1:
			_fail("weighted: ожидался 1 файл, получено %d" % picked.size())
			continue
		var picked_type := str(type_by_id.get(str(picked[0]), ""))
		if counts.has(picked_type):
			counts[picked_type] = int(counts[picked_type]) + 1
	_ok(int(counts["video"]) > int(counts["text"]),
		"H9: video чаще text (%d vs %d)" % [counts["video"], counts["text"]])
	_ok(int(counts["photo"]) > int(counts["text"]),
		"H9: photo чаще text (%d vs %d)" % [counts["photo"], counts["text"]])
	_ok(int(counts["video"]) >= int(counts["photo"]),
		"H9: video — самый частый тип (%d vs %d)" % [counts["video"], counts["photo"]])

	# 4 слота: всегда 4 разных id из пула, без дублей.
	for i in range(50):
		var picked4: Array = _hd._pick_request_files(pool, 4)
		_eq(picked4.size(), 4, "weighted: выбрано 4 файла")
		var unique := {}
		for fid in picked4:
			unique[str(fid)] = true
			_ok(type_by_id.has(str(fid)), "weighted: id %s из пула" % str(fid))
		_eq(unique.size(), 4, "weighted: id не повторяются")

	# H1: строгий фильтр по text — sound в пуле игнорируется.
	_set_case("request_type_strict_filter")
	_fresh(1)
	_approx(float(_hd.request_type_weights.get("sound", -1.0)), 0.0, 0.0001,
		"H1: request sound = 0")
	_eq(_hd._pick_request_files([{"id": "s1", "type": "sound"}], 1), [],
		"H1: пул без text → пустая выборка")
	_eq(_hd._pick_request_files([
		{"id": "t1", "type": "text"},
		{"id": "s1", "type": "sound"},
	], 1), ["t1"], "H1: из смешанного пула берётся только text")

	# Реальный спавн: только sound на складе → запрос не создаётся.
	var folder_id := _folder_id()
	var sound_file = _new_file("Строгий звук", "sound", folder_id)
	_ok(sound_file != null, "sound-файл создан")
	var spawned_before := int(_hd.requests_spawned)
	_eq(_hd.spawn_request_now(1), "", "strict filter: запрос не создан")
	_eq(_hd.requests_spawned, spawned_before, "strict filter: счётчик не вырос")
	_eq(_hd.active_requests.size(), 0, "strict filter: активных запросов нет")

	# Пустой конфиг весов → uniform fallback по всему пулу.
	_set_case("request_type_uniform_fallback")
	_hd.request_type_weights = {}
	_eq(_hd._pick_request_files([{"id": "s1", "type": "sound"}], 1), ["s1"],
		"пустой конфиг: uniform fallback выбирает sound")
	var req_id := str(_hd.spawn_request_now(1))
	_ok(not req_id.is_empty(), "fallback: запрос создан")
	if not req_id.is_empty():
		_eq(_hd.active_requests[req_id].required_types, ["sound"],
			"fallback: запрос собран из sound")
		_hd._cleanup_request(req_id, true)

	# Все веса нулевые — тот же uniform fallback.
	_hd.request_type_weights = {"text": 0.0, "sound": 0.0, "photo": 0.0, "video": 0.0}
	_eq(_hd._pick_request_files([{"id": "s2", "type": "sound"}], 1), ["s2"],
		"все веса 0: uniform fallback")


# --- поток спавна ----------------------------------------------------------

## v5: жёсткого лимита количества файлов в часе нет — поток идёт по интервалу
## (окно / базовый темп) до конца spawn_window, счётчик — фактический.
func _test_spawn_window_budget() -> void:
	_set_case("spawn_window_budget")
	_fresh(1)
	_hd.files_spawned = 0
	_hd.spawned_this_hour = 0
	# Запросы не мешают замеру окна спавна.
	_hd.active_request_limit = 0
	_hd.spawn_recv_accum = 0.0
	var folder_id := _folder_id()
	var base_interval := float(_hd._receive_interval())
	_approx(base_interval, _hd.spawn_window / float(_hd.files_budget), 0.0001,
		"интервал = окно / базовый темп")
	var spawn_times: Array[float] = []
	var last_count := int(_hd.files_spawned)
	for i in range(3000):
		_hd.tick(0.1)
		# Забираем пакеты в папку, иначе буфер законно тормозит поток.
		for pid in _hd.active_packets.keys().duplicate():
			var packet = _hd.active_packets.get(pid)
			if packet != null and packet.state == "waiting":
				_hd.receive_packet(str(pid), folder_id)
		var now_count := int(_hd.files_spawned)
		if now_count > last_count:
			for k in range(now_count - last_count):
				spawn_times.append(float(_hd.hour_elapsed))
			last_count = now_count
		if _hd.hour_elapsed >= _hd.spawn_window + 0.4:
			break
	_ok(spawn_times.size() >= 4, "файлы идут потоком (спавнов %d)" % spawn_times.size())
	_eq(_hd.files_spawned, _hd.spawned_this_hour,
		"files_spawned = фактический счётчик часа")
	_eq(_hd.carry_files, 0, "carry_files = 0 (переноса нет)")
	_ok(_hd.active_packets.size() <= _hd.buffer_limit(),
		"в буфере не больше лимита буфера")
	for i in range(1, spawn_times.size()):
		var delta := spawn_times[i] - spawn_times[i - 1]
		_ok(delta >= base_interval * 0.8 - 0.2 and delta <= base_interval * 1.2 + 0.2,
			"интервал спавна ~%.1f с (получено %.2f)" % [base_interval, delta])
	# Джиттер интервала ±20%: последний спавн не раньше «окно − максимальный
	# интервал», иначе поток оборвался бы раньше закрытия окна.
	_ok(spawn_times[spawn_times.size() - 1] >= _hd.spawn_window - base_interval * 1.2 - 0.2,
		"поток идёт до конца окна спавна (t=%.1f)" % spawn_times[spawn_times.size() - 1])
	# За окном спавна новых файлов нет (счётчик не растёт).
	var count_at_window_end := int(_hd.files_spawned)
	for i in range(150):
		_hd.tick(0.1)
	_eq(_hd.files_spawned, count_at_window_end, "после spawn_window новых файлов нет")

	# Нет лимита количества: счётчик выше базового темпа не останавливает спавн.
	_fresh(1)
	_hd.active_request_limit = 0
	_hd.files_spawned = int(_hd.files_budget) + 3
	_hd._next_spawn_at = _hd.hour_elapsed
	_hd.spawn_recv_accum = 0.0
	_hd._spawn_frozen_notified = false
	var before := int(_hd.files_spawned)
	_hd.tick(0.05)
	_eq(_hd.files_spawned, before + 1,
		"нет лимита количества: спавн идёт выше базового темпа")
	_ok(_hd.files_spawned > _hd.files_budget,
		"files_spawned превысил базовый темп (%d > %d)" % [
			_hd.files_spawned, _hd.files_budget])

	# Полный склад: спавн стоит; освободили место — продолжается.
	_fresh(1)
	var full_folder := _folder_id()
	for raw_id in _game.registry.folders.keys():
		_fill_folder(str(raw_id))
	_hd.active_request_limit = 0
	_hd.files_spawned = int(_hd.files_budget)
	_hd._next_spawn_at = _hd.hour_elapsed
	_hd._space_ok_cache = false
	_hd._space_check_accum = 0.0
	_hd._no_space_notified = false
	_hd.spawn_recv_accum = 0.0
	_frozen_events = 0
	_frozen_reasons.clear()
	var frozen_at := int(_hd.files_spawned)
	_hd.tick(0.1)
	_eq(_hd.files_spawned, frozen_at, "полный склад: спавн стоит")
	_ok(_frozen_reasons.has("no_space"), "полный склад: spawn_frozen(no_space)")
	var victim = _file_at(full_folder, Vector2i(0, 0))
	_ok(victim != null, "нашли файл для освобождения клетки")
	if victim != null:
		_game.registry.consume_file(str(victim.id))
	# tick() клампит dt до 0.1 с: даём кэшу «есть ли место» обновиться.
	for i in range(6):
		_hd.tick(0.1)
	_ok(_hd.files_spawned > frozen_at, "после освобождения места спавн продолжился")


func _test_carry() -> void:
	_set_case("carry")
	_fresh(1)
	_eq(_hd.carry_files, 0, "старт: переноса нет")
	_hd.files_spawned = 3
	_hd._finish_hour()
	_eq(_hd.carry_files, 0, "carry отключён: недоспавненные файлы не переносятся")
	_eq(int(_hd.report().get("files_carry", -1)), 0, "отчёт: files_carry = 0")
	_eq(int(_hd.report().get("files_spawned", -1)), 3,
		"отчёт: files_spawned фактический")

	_game.hour = 2
	_hd.start_hour(2)
	_eq(_hd.files_budget, int(_hour_row(2).get("files", 8)),
		"H2: базовый темп из данных, без переноса")
	_eq(_hd.files_budget, 8, "H2: 8 базовых файлов")
	_eq(_hd.carry_files, 0, "H2: переноса нет")

	_game.hour = 5
	_hd.start_hour(5)
	_eq(_hd.files_budget, int(_hour_row(5).get("files", 0)),
		"H5: темп = строка часа, без капа и переноса")
	_eq(_hd.carry_files, 0, "H5: carry_files = 0")

	# Буфер полон: файл не теряется, счётчик не растёт.
	_fresh(1)
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


# --- приём: геометрия файла ------------------------------------------------

## Баг A (регрессия): после загрузки файл обязан быть и в registry, и в
## folder.file_ids, и владеть теми же клетками folder.cells — для всех типов
## и поворотов, включая повторный приём и save/load.
func _test_receive_geometry() -> void:
	_set_case("receive_geometry")
	for type_id in ["text", "sound", "photo", "video"]:
		for rot in range(4):
			_fresh(1)
			_hd.spawn_window = -1.0
			var folder_id := _folder_id()
			var pid := str(_hd.spawn_packet_now(str(type_id)))
			if pid.is_empty():
				_fail("%s rot%d: пакет не заспавнен" % [type_id, rot])
				continue
			var packet = _hd.active_packets[pid]
			if not _hd.receive_packet(pid, folder_id, Vector2i(-1, -1), rot):
				_fail("%s rot%d: приём отклонён" % [type_id, rot])
				continue
			for i in range(400):
				_hd.tick(0.1)
				if not _hd.active_packets.has(pid):
					break
			var file = _game.registry.find_by_name(str(packet.file_name))
			_ok(file != null, "%s rot%d: файл в registry" % [type_id, rot])
			if file == null:
				continue
			var folder = _game.registry.get_folder(folder_id)
			_ok(folder.file_ids.has(str(file.id)),
				"%s rot%d: файл в folder.file_ids" % [type_id, rot])
			_ok(_game.registry.get_folder_files(folder_id).has(file),
				"%s rot%d: get_folder_files содержит файл" % [type_id, rot])
			var want := R.shape_cells(str(file.shape_id), int(file.rotation)).size()
			var owned := _owned_cells(folder, str(file.id))
			_eq(owned, want, "%s rot%d: клетки папки принадлежат файлу" % [type_id, rot])
			_eq(str(file.folder_id), folder_id, "%s rot%d: folder_id" % [type_id, rot])
			_eq(str(file.location), "folder", "%s rot%d: location" % [type_id, rot])
			_ok(int(file.rotation) >= 0 and int(file.rotation) <= 3,
				"%s rot%d: rotation 0..3" % [type_id, rot])
			_ok(not (file.shape_cells as Array).is_empty(),
				"%s rot%d: shape_cells заполнены" % [type_id, rot])
			_eq(_game.registry.validate().size(), 0,
				"%s rot%d: инварианты: %s" % [type_id, rot,
					str(_game.registry.validate())])

			# Сохранение/загрузка: файл остаётся в папке на своих клетках.
			var snapshot: Dictionary = _game.registry.to_dict()
			var reg2 = R.new()
			_ok(reg2.from_dict(snapshot), "%s rot%d: from_dict" % [type_id, rot])
			var loaded = reg2.get_file(str(file.id))
			_ok(loaded != null, "%s rot%d: файл после load" % [type_id, rot])
			if loaded != null:
				_eq(str(loaded.folder_id), folder_id, "%s rot%d: folder_id после load" % [type_id, rot])
				_eq(str(loaded.location), "folder", "%s rot%d: location после load" % [type_id, rot])
				_ok(reg2.get_folder(folder_id).file_ids.has(str(file.id)),
					"%s rot%d: folder.file_ids после load" % [type_id, rot])
				_eq(_owned_cells(reg2.get_folder(folder_id), str(file.id)), want,
					"%s rot%d: клетки после load" % [type_id, rot])
			_eq(reg2.validate().size(), 0,
				"%s rot%d: инварианты после load: %s" % [type_id, rot, str(reg2.validate())])

	# Несколько пакетов подряд в одну папку — все файлы на месте.
	_fresh(1)
	_hd.spawn_window = -1.0
	var folder_id2 := _folder_id()
	var types := ["text", "sound", "photo"]
	var accepted := 0
	for i in range(types.size()):
		var pid2 := str(_hd.spawn_packet_now(str(types[i])))
		if pid2.is_empty():
			continue
		var p2 = _hd.active_packets[pid2]
		if not _hd.receive_packet(pid2, folder_id2):
			continue
		for j in range(400):
			_hd.tick(0.1)
			if not _hd.active_packets.has(pid2):
				break
		if _game.registry.find_by_name(str(p2.file_name)) != null:
			accepted += 1
	var folder2 = _game.registry.get_folder(folder_id2)
	_eq(accepted, types.size(), "несколько пакетов приняты")
	_eq(folder2.file_ids.size(), accepted, "все принятые файлы в папке")
	_eq(_game.registry.get_folder_files(folder_id2).size(), accepted,
		"get_folder_files возвращает все")
	_eq(_game.registry.validate().size(), 0,
		"инварианты после серии приёмов: %s" % str(_game.registry.validate()))


func _owned_cells(folder, file_id: String) -> int:
	var n := 0
	if folder == null:
		return 0
	for cell in folder.cells.keys():
		if str(folder.cells[cell]) == file_id:
			n += 1
	return n


# --- запросы ---------------------------------------------------------------

func _test_request_caps() -> void:
	var active_limit := int(_hour_row(1).get("active_requests", 2))

	_set_case("request_no_files")
	_fresh(1)
	_hd.requests_spawned = 0
	_hd.spawn_send_accum = 0.0
	for i in range(300):
		_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 0, "без файлов запрос не спавнится")
	_eq(_hd.requests_spawned, 0, "счётчик спавна не растёт без пула")

	_set_case("request_active_limit")
	_fresh(1)
	for i in range(6):
		_new_file("Запрос", "text", _folder_id())
	_hd.requests_spawned = 0
	_hd._last_request_attempt_t = -_hd.REQUEST_ATTEMPT_MIN_GAP
	_hd.spawn_send_accum = 0.0
	_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 1, "H1: первый запрос создан анти-голоданием")
	_eq(_hd.requests_spawned, 1, "H1: первый запрос учтён")
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

	# v4: второго запроса ждём send_interval (20 с), а не «залпа».
	_hd.spawn_send_accum = 100.0
	_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 2, "H1: второй запрос по интервалу")
	_eq(_hd.requests_spawned, 2, "H1: второй запрос учтён")
	for i in range(5):
		_hd.spawn_send_accum = 100.0
		_hd.tick(0.1)
	_eq(_hd.active_requests.size(), active_limit,
		"H1: одновременно %d запроса" % active_limit)
	_eq(_hd.requests_spawned, active_limit, "H1: active_request_limit держит лимит")

	_hd._cleanup_request(req_id, true)
	_hd.spawn_send_accum = 100.0
	_hd.tick(0.1)
	_eq(_hd.active_requests.size(), active_limit,
		"после освобождения слота создан следующий запрос")
	_eq(_hd.requests_spawned, active_limit + 1,
		"нет общего cap: requests_spawned растёт")

	# Прокручиваем час до 99 с, сохраняя один активный запрос.
	while _hd.hour_elapsed < 99.0 and _hd.running:
		_hd.tick(0.1)
		_refresh_and_trim_requests()
	# Cutoff: за 10 с до конца часа новые запросы не создаются.
	var keep_id := ""
	for rid in _hd.active_requests.keys().duplicate():
		if keep_id.is_empty():
			keep_id = str(rid)
			var keep = _hd.active_requests.get(keep_id)
			if keep != null:
				keep.time_left = keep.timer_total
		else:
			_hd._cleanup_request(str(rid), true)
	_hd.spawn_send_accum = 0.0
	var spawned_before_cutoff := int(_hd.requests_spawned)
	while _hd.hour_elapsed < 110.5:
		_hd.tick(0.1)
		var live = _hd.active_requests.get(keep_id)
		if live != null:
			live.time_left = live.timer_total
	_eq(_hd.requests_spawned, spawned_before_cutoff,
		"H1: после cutoff 110 с новых запросов нет")
	_eq(_hd.next_request_hint(), "До конца часа запросов не будет",
		"H1: подсказка после cutoff")

	_set_case("request_clamp")
	_fresh(1)
	_new_file("Один", "text", _folder_id())
	var clamped_id := str(_hd.spawn_request_now(4))
	_ok(not clamped_id.is_empty(), "запрос создан при одном доступном файле")
	_eq(_hd.request_required_count(clamped_id), 1,
		"запрос на 4 файла зажат до размера пула (1)")
	_eq(_hd.request_missing(clamped_id).size(), 1, "нужен ровно один файл")


# --- v4: rate без общего cap (H9) -------------------------------------------

## H9: длительность 360, send_interval 24, cutoff 350. При большом пуле и
## освобождении активных запросов спавнов ≈ 1 + floor((360-10)/24) = 15 ±1,
## интервалы ≈24 с, после cutoff спавнов нет.
func _test_rate_no_cap_h9() -> void:
	_set_case("rate_no_cap_h9")
	_fresh(9)
	_eq(_hd.requests_spawned, 0, "H9: стартовых запросов нет")
	for i in range(100):
		_new_file("Пул", "text", _folder_id())
	_hd.active_request_limit = 20
	_hd.files_spawned = _hd.files_budget
	_hd._next_spawn_at = 99999.0
	if _hd.attack_director != null:
		_hd.attack_director._schedule.clear()
		_hd.attack_director._next_index = 0

	var spawn_times: Array[float] = []
	var last_count := int(_hd.requests_spawned)
	while _hd.hour_elapsed < 351.0 and _hd.running:
		_hd.tick(0.1)
		# Оставляем один «живой» запрос: starvation guard не спавнит залпом,
		# а таймер не истекает и не штрафует SLA.
		_refresh_and_trim_requests()
		if int(_hd.requests_spawned) > last_count:
			var delta := int(_hd.requests_spawned) - last_count
			for k in range(delta):
				spawn_times.append(float(_hd.hour_elapsed))
			last_count = int(_hd.requests_spawned)

	var spawned := int(_hd.requests_spawned)
	_ok(spawned >= 14 and spawned <= 16,
		"H9: ~15 спавнов (1+floor(350/24)), получено %d" % spawned)
	_ok(spawned > 7, "H9: общего cap нет (старый кап был 7)")
	for i in range(1, spawn_times.size()):
		_approx(spawn_times[i] - spawn_times[i - 1], 24.0, 1.0,
			"H9: интервал между запросами ≈24 с (t=%.1f → %.1f)" % [
				spawn_times[i - 1], spawn_times[i]])
	_ok(spawn_times.size() >= 2 and spawn_times[0] < 1.0,
		"H9: первый запрос появляется сразу (t=%.1f)" % (
			spawn_times[0] if not spawn_times.is_empty() else -1.0))

	var before_cutoff := int(_hd.requests_spawned)
	while _hd.hour_elapsed < 355.0 and _hd.running:
		_hd.tick(0.1)
		_refresh_and_trim_requests()
	_eq(_hd.requests_spawned, before_cutoff, "H9: после cutoff 350 запросов нет")
	_eq(_hd.next_request_hint(), "До конца часа запросов не будет",
		"H9: next_request_hint сообщает cutoff")


func _refresh_and_trim_requests() -> void:
	var ids: Array = _hd.active_requests.keys()
	for i in range(ids.size()):
		var rid := str(ids[i])
		var live = _hd.active_requests.get(rid)
		if live != null:
			live.time_left = live.timer_total
		if i > 0:
			_hd._cleanup_request(rid, true)


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
	# send_interval H1 = 20 с; спавн должен случиться на первом же тике.
	_hd.tick(0.1)
	_eq(_hd.active_requests.size(), 1, "запрос создан без ожидания интервала")
	_eq(_hd.requests_spawned, 1, "счётчик спавна вырос")
	# Второй свободный файл + анти-голодание: добираемся до активного лимита.
	var file2 = _new_file("Голод 2", "text", _folder_id())
	_ok(file2 != null, "второй файл создан")
	_hd.spawn_send_accum = 100.0
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


# --- v4: переполнение склада -----------------------------------------------

## Если waiting-пакет не влезает ни в одну папку, его таймер не тикает,
## спавн стоит с spawn_frozen("no_space"), SLA не падает. Освободили клетку —
## таймер пошёл.
func _test_overflow_no_space() -> void:
	_set_case("overflow_no_space")
	_fresh(1)
	for raw_folder_id in _game.registry.folders.keys():
		_fill_folder(str(raw_folder_id))
	var free_total := 0
	for raw_folder_id in _game.registry.folders.keys():
		free_total += int(_game.registry.free_cells(str(raw_folder_id)))
	_eq(free_total, 0, "все папки заполнены до 0 клеток")
	_hd.files_spawned = 0
	_hd._space_ok_cache = false
	_hd._space_check_accum = 0.0
	_hd._no_space_notified = false
	_frozen_events = 0
	_frozen_reasons.clear()
	var sla_before := float(_game.sla)
	var pid := str(_hd.spawn_packet_now("text"))
	_ok(not pid.is_empty(), "пакет заспавнен при полном складе")
	var packet = _hd.active_packets.get(pid)
	_ok(packet != null, "пакет в буфере")
	if packet == null:
		return
	# Даём кэшу «влезает ли фигура» обновиться (FIT_CHECK_INTERVAL = 0.5 с).
	for i in range(6):
		_hd.tick(0.1)
	var time_before := float(packet.time_left)
	for i in range(250):
		_hd.tick(0.1)
	_approx(float(packet.time_left), time_before, 0.0001,
		"переполнение: таймер пакета не уменьшился за 25 с")
	_ok(_hd.active_packets.has(pid), "пакет не сгорел по таймауту")
	_ok(_frozen_reasons.has("no_space"), "spawn_frozen(no_space) эмитится")
	_approx(float(_game.sla), sla_before, 0.001,
		"SLA не падает, пока пакет заморожен")

	# Освобождаем одну клетку в первой папке — таймер должен пойти.
	var folder_id := _folder_id()
	var victim = null
	for file in _game.registry.get_folder_files(folder_id):
		if str(file.required_by).is_empty() and str(file.attached_request).is_empty():
			victim = file
			break
	_ok(victim != null, "нашли файл для освобождения клетки")
	if victim == null:
		return
	_game.registry.consume_file(str(victim.id))
	_hd._fit_check_accum = 0.0
	var t_after_free := float(packet.time_left)
	for i in range(20):
		_hd.tick(0.1)
	_ok(float(packet.time_left) < t_after_free,
		"после освобождения клетки таймер пакета снова идёт")


# --- v4: спавн только влезающего типа/формы --------------------------------

## Нормальный spawn_packet_now() (без type_override) не должен создавать пакет,
## который некуда положить: при полном складе — "", при месте только под
## 1-клеточный text — только text. После освобождения места спавн возобновляется.
func _test_spawn_fitting_type() -> void:
	_set_case("spawn_fitting_type")
	# H2: в пуле text (1 клетка) и sound (2 клетки) — проверяем фильтр по месту.
	_fresh(2)
	var folder_ids: Array = _game.registry.folders.keys()
	_ok(folder_ids.size() >= 2, "нужно минимум 2 папки")
	if folder_ids.size() < 2:
		return
	var first_id := str(folder_ids[0])
	for raw_id in folder_ids:
		_fill_folder(str(raw_id))
	_eq(int(_game.registry.free_cells()), 0, "склад заполнен полностью")
	_ok(not _game.registry.can_fit_type_anywhere("text"),
		"полный склад: text не влезает")
	_ok(not _game.registry.can_fit_type_anywhere("sound"),
		"полный склад: sound не влезает")
	var packets_before: int = _hd.active_packets.size()
	_eq(str(_hd.spawn_packet_now()), "",
		"полный склад: нормальный спавн не создаёт невлезающий пакет")
	_eq(_hd.active_packets.size(), packets_before, "буфер не вырос")

	# Освобождаем ровно одну клетку: 1-клеточный text влезает, sound — нет.
	var victim = _file_at(first_id, Vector2i(0, 0))
	_ok(victim != null, "нашли файл в (0,0)")
	if victim == null:
		return
	_game.registry.consume_file(str(victim.id))
	_eq(int(_game.registry.free_cells()), 1, "освободилась ровно одна клетка")
	_ok(_game.registry.can_fit_type_anywhere("text"), "text влезает в одну клетку")
	_ok(not _game.registry.can_fit_type_anywhere("sound"),
		"sound не влезает в одну клетку")
	_eq(str(_game.registry.shape_for_type_fitting("text")), "O1",
		"shape_for_type_fitting(text) = O1")
	_eq(str(_game.registry.shape_for_type_fitting("sound")), "",
		"shape_for_type_fitting(sound) = пусто")
	var pid := str(_hd.spawn_packet_now())
	_ok(not pid.is_empty(), "нормальный спавн создал влезающий пакет")
	var packet = _hd.active_packets.get(pid)
	_ok(packet != null, "пакет в буфере")
	if packet != null:
		_eq(str(packet.type), "text", "спавн выбрал только влезающий тип (text)")
		_ok(_game.registry.can_fit_anywhere(str(packet.shape_id),
			int(packet.rotation)), "фигура пакета реально влезает в папку")

	# Освобождаем соседнюю клетку: теперь влезает и sound (2 клетки).
	var victim2 = _file_at(first_id, Vector2i(1, 0))
	_ok(victim2 != null, "нашли файл в (1,0)")
	if victim2 == null:
		return
	_game.registry.consume_file(str(victim2.id))
	_ok(_game.registry.can_fit_type_anywhere("sound"),
		"после освобождения места sound влезает")
	_ok(not str(_game.registry.shape_for_type_fitting("sound")).is_empty(),
		"shape_for_type_fitting(sound) непустой после освобождения места")
	var seen: Dictionary = {}
	for i in range(60):
		var spawned := str(_hd.spawn_packet_now())
		if spawned.is_empty():
			break
		var p = _hd.active_packets.get(spawned)
		if p == null:
			continue
		seen[str(p.type)] = true
		_ok(_game.registry.can_fit_anywhere(str(p.shape_id), int(p.rotation)),
			"пакет %s: фигура влезает после освобождения места" % str(p.id))
		_hd._remove_packet(spawned)
	_ok(seen.has("text"), "после освобождения места text спавнится")
	_ok(seen.has("sound"), "после освобождения места sound спавнится")


## can_fit_anywhere учитывает повороты и заблокированные папки.
func _test_fit_anywhere_rotation_and_blocked() -> void:
	_set_case("fit_anywhere_rotation")
	_fresh(1)
	var folder_ids: Array = _game.registry.folders.keys()
	_ok(folder_ids.size() >= 2, "нужно минимум 2 папки")
	if folder_ids.size() < 2:
		return
	var first_id := str(folder_ids[0])
	for raw_id in folder_ids:
		_fill_folder(str(raw_id))
	_ok(not _game.registry.can_fit_anywhere("I2H", 0),
		"полный склад: I2H не влезает ни в каком повороте")
	# Оставляем только вертикальный зазор 1x2: горизонтальная I2H влезает
	# исключительно после поворота в I2V.
	var top = _file_at(first_id, Vector2i(0, 0))
	var bottom = _file_at(first_id, Vector2i(0, 1))
	_ok(top != null and bottom != null, "нашли файлы (0,0) и (0,1)")
	if top == null or bottom == null:
		return
	_game.registry.consume_file(str(top.id))
	_game.registry.consume_file(str(bottom.id))
	_eq(int(_game.registry.free_cells()), 2, "освободился вертикальный зазор 1x2")
	_ok(_game.registry.can_fit_anywhere("I2H", 0),
		"can_fit_anywhere учитывает поворот: вертикальный зазор под I2V")
	_ok(not _game.registry.can_fit_anywhere("I2H", 0, {first_id: true}),
		"can_fit_anywhere не учитывает заблокированную папку с местом")
	_ok(_game.registry.can_fit_anywhere("I2H", 0, {"fold_нет": true}),
		"чужая блокировка не мешает размещению")
	# Директор использует те же блокировки при спавне.
	_hd.blocked_folders = {first_id: 100000.0}
	_eq(str(_hd.spawn_packet_now()), "",
		"все папки с местом заблокированы → спавн не создаёт пакет")
	_hd.blocked_folders.clear()
	_ok(not str(_hd.spawn_packet_now()).is_empty(),
		"после снятия блокировки спавн возобновился")


# --- v4: duration/fallback --------------------------------------------------

## Все 9 часов берут duration из hours[]; без duration — constants.hour_seconds.
func _test_duration_fallback() -> void:
	_set_case("duration_all_hours")
	var expected := [120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0, 360.0]
	for h in range(1, 10):
		_fresh(int(h))
		_approx(_hd.hour_duration(), expected[h - 1], 0.0001,
			"H%d: duration %.0f" % [h, expected[h - 1]])
		_approx(float(_hour_row(int(h)).get("duration", -1.0)), expected[h - 1],
			0.0001, "H%d: duration в данных" % h)

	_set_case("duration_fallback")
	var data := root.get_node_or_null("Data")
	_ok(data != null, "Data доступен")
	if data == null:
		return
	var row: Dictionary = (data.hours as Array)[0]
	_ok(row.has("duration"), "H1 содержит duration")
	row.erase("duration")
	_hd.hour = 1
	_approx(_hd._hour_seconds(), 300.0, 0.0001,
		"без duration → constants.hour_seconds = 300")
	_hd.start_hour(1)
	_approx(_hd.time_left, 300.0, 0.0001, "без duration час длится 300 с")
	row["duration"] = 120
	_hd.hour = 1
	_approx(_hd._hour_seconds(), 120.0, 0.0001, "duration восстановлен")


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
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")

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
	_ok(_hd.set_request_protocol(req2, "udp"),
		"второй запрос переведён на UDP (слот занят соединением)")
	var ids2: Array = _hd.request_required_ids(req2)
	_ok(ids2.size() == 1 and not ids.has(ids2[0]),
		"второй запрос берёт файл, не занятый первым")
	_ok(_hd.attach_file(req2, ids2[0]), "свободный файл прикреплён к другому запросу")
	_ok(not _hd.attach_file(req2, ids[0]),
		"файл, требуемый другим запросом, нельзя прикрепить")

	var f4 = _new_file("Резерв", "text", folder_id)
	if f4 != null:
		var fid4 := str(f4.id)
		var req3: String = str(_hd._create_request(1, "udp", [fid4], false))
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
		var req4: String = str(_hd._create_request(1, "udp", [fid5], false))
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
	_eq(str(_hd.active_requests[req2].protocol), "tcp", "TCP-запрос создан")
	_ok(not _hd.active_requests[req2].connected,
		"legacy p_connected не подключает TCP")
	_ok(_connect_tcp(req2), "TCP-соединение установлено")
	_ok(not _hd.set_request_protocol(req2, "udp"),
		"connected-запрос нельзя переключить на UDP")
	_eq(str(_hd.active_requests[req2].protocol), "tcp",
		"протокол остался tcp")
	_hd._cleanup_request(req2, true)

	_set_case("protocol_attached")
	var file3 = _new_file("С файлами", "text", _folder_id())
	var req3: String = str(_hd._create_request(1, "tcp", [str(file3.id)], false))
	_ok(_connect_tcp(req3), "соединение для запроса с файлами")
	_ok(_hd.attach_file(req3, str(file3.id)), "файл прикреплён")
	_toasts.clear()
	_ok(not _hd.set_request_protocol(req3, "udp"),
		"смена протокола с прикреплёнными файлами → false")
	_ok(_has_toast("СНАЧАЛА ОТКРЕПИТЕ ФАЙЛЫ"), "тост об откреплении файлов")
	_eq(str(_hd.active_requests[req3].protocol), "tcp", "протокол не изменился")
	_hd._cleanup_request(req3, true)

	_set_case("protocol_udp_retry_reset")
	var file4 = _new_file("Ретрай", "text", _folder_id())
	var req4: String = str(_hd._create_request(1, "udp", [str(file4.id)], false))
	var live4 = _hd.active_requests[req4]
	live4.udp_retry_until = 42.0
	_ok(_hd.set_request_protocol(req4, "tcp"), "UDP → TCP разрешён без файлов")
	_approx(float(live4.udp_retry_until), 0.0, 0.0001,
		"UDP → TCP сбрасывает кулдаун повтора")
	_ok(not live4.has_connection(), "TCP после смены ещё не подключён")
	_hd._cleanup_request(req4, true)


# --- мини-игра отправки ----------------------------------------------------

func _test_send_minigame_pause() -> void:
	_set_case("send_minigame_pause")
	_fresh(1)
	var file = _new_file("Мини", "text", _folder_id())
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
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
	_set_case("udp_no_slot_queue")
	_fresh(1)
	# v5: UDP после мини-игры не занимает out-слот и не встаёт в очередь —
	# отправка стартует сразу, даже если все слоты заняты.
	_hd.udp_roll_override = 0.0
	var file = _new_file("Очередь", "text", _folder_id())
	var req_id: String = str(_hd._make_request([file], "udp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	var blocker := int(_hd.slots.reserve("out", "blocker"))
	_ok(blocker >= 0, "слот занят другим запросом")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests[req_id]
	_ok(bool(req.sending), "UDP без слота: отправка стартовала сразу")
	_ok(not _hd.is_request_queued(req_id), "UDP не встаёт в очередь")
	_ok(not req.minigame_active, "мини-игра закрыта")
	_ok(not bool(req.slot_reserved), "UDP не резервирует out-слот")
	var blocker_slot = _hd.slots.get_slot(blocker)
	_ok(blocker_slot != null and bool(blocker_slot.occupied),
		"чужой blocker остаётся в слоте")
	_eq(_hd.slots.used_count("out"), 1, "UDP не добавил занятый слот")

	var money_before: int = _game.money
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "UDP завершился без очереди")
	_ok(_game.money > money_before, "выплата за отправку начислена")
	var kept_blocker = _hd.slots.get_slot(blocker)
	_ok(kept_blocker != null and bool(kept_blocker.occupied),
		"UDP не освободил чужой out-слот")
	_eq(_hd.slots.used_count("out"), 1, "после UDP занят только blocker")
	_ok(_hd.slots.release(blocker), "blocker освобождён вручную")
	_eq(_hd.slots.used_count("out"), 0, "после освобождения blocker слотов нет")
	_hd.udp_roll_override = -1.0


# --- файлы после отправки (v4: НЕ исчезают) --------------------------------

func _test_file_consumption() -> void:
	_set_case("files_persist_after_send")
	_fresh(1)
	# Замораживаем автоспавн запросов: проверяем именно судьбу файла.
	_hd.active_request_limit = 0
	var folder_id := _folder_id()
	var folder = _game.registry.get_folder(folder_id)
	var file = _new_file("Расход", "text", folder_id)
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests[req_id]
	_ok(req.sending, "отправка пошла после мини-игры")
	var conn_id := str(req.connection_id)
	_ok(not conn_id.is_empty(), "TCP-отправка идёт через соединение")
	var money_before: int = _game.money
	var streak_before: int = int(_game.streak)
	var free_before: int = folder.free_cell_count()
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "запрос закрыт")
	_ok(_game.money > money_before, "выплата начислена")
	_eq(int(_game.streak), streak_before + 1, "streak увеличен")
	_eq(_hd._completed, 1, "completed = 1")
	_eq(_hd.files_sent_this_hour, 1, "files_sent = 1")

	# v4: файл возвращается в папку и остаётся доступным пулу.
	_ok(_game.registry.files.has(file_id), "файл остался в реестре после отправки")
	var kept = _game.registry.files.get(file_id)
	if kept != null:
		_eq(str(kept.location), "folder", "файл снова в папке")
		_eq(str(kept.attached_request), "", "файл откреплён")
		_eq(str(kept.required_by), "", "required_by снят")
		_approx(float(kept.cooldown_until), 0.0, 0.0001, "cooldown = 0")
	_eq(folder.free_cell_count(), free_before, "клетки не освободились")
	# Повторный запрос может требовать тот же файл.
	var req2 := str(_hd._create_request(1, "udp", [file_id], false))
	_ok(not req2.is_empty(), "новый запрос на тот же файл создан")
	if not req2.is_empty():
		_eq(str(kept.required_by), req2, "файл снова зарезервирован")
		_ok(_hd.attach_file(req2, file_id), "файл снова прикрепляется")
		_hd._cleanup_request(req2, true)
		_eq(str(kept.required_by), "", "cleanup снял required_by")

	# TCP: слот соединения остаётся занятым после отправки.
	_eq(_hd.slots.used_count("out"), 1, "TCP: слот соединения остаётся занятым")
	var slot = _hd.slots.get_slot(0)
	_ok(slot != null and str(slot.kind) == "tcp_connection",
		"в слоте tcp_connection")
	var conn = _hd.get_connection(conn_id)
	_ok(conn != null, "соединение живо после отправки")
	if conn != null:
		_eq(str(conn.request_id), "", "соединение отвязано от запроса")
		if slot != null:
			_approx(float(slot.progress), 0.0, 0.0001, "progress слота сброшен")
			_eq(str(slot.entity_name), str(conn.client_name),
				"в слоте только имя клиента")
			_eq(str(slot.detail), str(conn.ip), "в слоте IP клиента")
			_ok(not str(slot.detail).is_empty(), "detail (IP) заполнен")
			_ok(bool(slot.can_disconnect), "слот можно отключить")
		_ok(_hd.disconnect_connection(conn_id), "disconnect idle-соединения")
		_eq(_hd.slots.used_count(), 0, "после disconnect слот свободен")
		_ok(not _hd.active_connections.has(conn_id), "соединение закрыто")


## D2: после старта отправки time_left заморожен, даже если до нуля оставалось
## 1 с, а передача длится 3 с — запрос обязан дойти, а не упасть по таймауту.
func _test_send_timer_freeze() -> void:
	_set_case("send_timer_freeze")
	_fresh(1)
	_hd.active_request_limit = 0
	var file = _new_file("Заморозка", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
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
	_ok(_game.registry.files.has(file_id), "файл остался после успешной отправки")
	var kept = _game.registry.files.get(file_id)
	if kept != null:
		_eq(str(kept.location), "folder", "файл вернулся в папку (D2)")
	_ok(int(_game.money) > money_before,
		"выплата начислена (%d → %d)" % [money_before, int(_game.money)])
	_approx(float(_game.sla), sla_before, 0.001,
		"таймаут не списал SLA во время отправки")
	_eq(_hd._failed, 0, "провалов нет")


func _test_timeout_preserves_files() -> void:
	_set_case("timeout_keeps_files")
	_fresh(1)
	_hd.active_request_limit = 0
	var file = _new_file("Таймаут", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	var req = _hd.active_requests.get(req_id)
	_ok(req != null and not req.sending, "запрос ещё НЕ отправляется")
	var conn_id := str(req.connection_id) if req != null else ""
	_ok(not conn_id.is_empty(), "у запроса есть соединение")
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	req.time_left = 0.05
	_hd.tick(0.1)
	_ok(not _hd.active_requests.has(req_id), "неотправленный запрос снят по таймауту")
	_ok(_game.registry.files.has(file_id), "при таймауте файл НЕ расходуется")
	var kept = _game.registry.files.get(file_id)
	if kept != null:
		_eq(str(kept.location), "folder", "файл вернулся в папку")
		_eq(str(kept.required_by), "", "таймаут снял required_by")
	_eq(_game.money, money_before, "штраф только по SLA, без денег")
	_approx(_game.sla, sla_before - 12.0, 0.001, "таймаут H1: −(10+2×1) SLA")
	_eq(_hd._failed, 1, "провал учтён")
	_ok(not _hd.active_connections.has(conn_id), "таймаут закрыл TCP-соединение")
	_eq(_hd.slots.used_count(), 0, "таймаут освободил слот соединения")


# --- overtime: время вышло, но запросы ещё активны -------------------------

## Время дошло до 0 с активным запросом: час НЕ завершается, новые файлы и
## запросы не спавнятся, загрузка пакета/таймеры продолжаются. После
## отклонения последнего запроса — hour_finished.
func _test_overtime() -> void:
	_set_case("overtime_with_request")
	_fresh(1)
	_hd.active_request_limit = 0
	var pending_file = _new_file("Overtime ожидание", "text", _folder_id())
	_ok(pending_file != null, "файл для запроса создан")
	if pending_file == null:
		return
	var req_id: String = str(_hd._make_request([pending_file], "udp", false, "", ""))
	_ok(not req_id.is_empty(), "активный UDP-запрос создан")
	if req_id.is_empty():
		return
	var req = _hd.active_requests[req_id]
	req.time_left = 999.0

	# Свободный файл: пул запроса непуст, starvation guard «готов» сработать.
	var spare = _new_file("Overtime резерв", "text", _folder_id())
	_ok(spare != null, "свободный файл для пула запросов создан")

	# Пакет в загрузке: в overtime приём должен доехать до файла.
	var folder_id := _folder_id()
	var packet_id := str(_hd.spawn_packet_now("text"))
	_ok(not packet_id.is_empty(), "пакет заспавнен до overtime")
	_ok(_hd.receive_packet(packet_id, folder_id), "пакет загружается")
	var files_before := int(_game.registry.files.size())

	_hd.time_left = 0.05
	_hd.spawn_window = 99999.0
	_hd.active_request_limit = 10
	_hd.tick(0.1)
	_ok(_hd.is_overtime(), "time_left→0: overtime выставлен")
	_ok(_hd.running, "час не завершён с активным запросом")
	_eq(_hour_events, 0, "hour_finished не эмитится")
	_approx(_hd.time_left, 0.0, 0.0001, "в overtime time_left = 0")
	_eq(_hd.next_request_hint(), "ЧАС ЗАВЕРШЁН · ЗАВЕРШИТЕ ЗАПРОСЫ",
		"overtime: подсказка про завершение запросов")
	_ok(_has_toast("ЧАС ЗАВЕРШЁН · ЗАВЕРШИТЕ ЗАПРОСЫ"), "overtime: тост")

	# Спавн «готов» сработать (окно открыто, аккумуляторы полны), но overtime
	# не даёт создавать ни файлы, ни запросы.
	_hd._next_spawn_at = _hd.hour_elapsed
	_hd.spawn_recv_accum = 0.0
	_hd.spawn_send_accum = 100.0
	_hd._last_request_attempt_t = -9999.0
	var spawned_files := int(_hd.files_spawned)
	var spawned_requests := int(_hd.requests_spawned)
	var elapsed_before := float(_hd.hour_elapsed)
	for i in range(40):
		req.time_left = 999.0
		_hd.tick(0.1)
	_ok(_hd.is_overtime() and _hd.running, "overtime продолжается")
	_ok(_hd.hour_elapsed > elapsed_before, "таймеры часа идут дальше")
	_eq(int(_hd.files_spawned), spawned_files, "overtime: новые файлы не спавнятся")
	_eq(int(_hd.requests_spawned), spawned_requests,
		"overtime: новые запросы не спавнятся")
	_eq(_hd.next_request_hint(), "ЧАС ЗАВЕРШЁН · ЗАВЕРШИТЕ ЗАПРОСЫ",
		"overtime: подсказка не меняется")
	_ok(not _hd.active_packets.has(packet_id), "overtime: загрузка пакета продолжилась")
	_eq(_game.registry.files.size(), files_before + 1, "overtime: файл догрузился")

	# Отклонение закрывает последний запрос → час финиширует.
	_ok(_hd.reject_request(req_id), "overtime: запрос можно отклонить")
	_ok(_hd.active_requests.is_empty(), "после отклонения запросов нет")
	_hd.tick(0.1)
	_ok(not _hd.running, "после пустых запросов час завершён")
	_eq(_hour_events, 1, "hour_finished ровно один раз")
	_ok(bool(_hour_report.get("overtime", false)), "отчёт: overtime = true")


## Успешная отправка, стартовавшая до конца времени, доигрывается в overtime
## и завершает час без штрафа за недоделанный запрос.
func _test_overtime_complete_request() -> void:
	_set_case("overtime_complete_request")
	_fresh(1)
	_hd.active_request_limit = 0
	var file = _new_file("Overtime отправка", "text", _folder_id())
	_ok(file != null, "файл для запроса создан")
	if file == null:
		return
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "udp", false, "", ""))
	_ok(not req_id.is_empty(), "UDP-запрос создан")
	if req_id.is_empty():
		return
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён")
	_hd.udp_roll_override = 0.0
	_ok(_hd.start_send(req_id), "мини-игра отправки открыта")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests.get(req_id)
	_ok(req != null and bool(req.sending), "отправка идёт")
	if req == null:
		return
	req.send_duration = 2.0
	req.send_progress = 0.0
	_hd.time_left = 0.05
	_hd.tick(0.1)
	_ok(_hd.is_overtime(), "overtime начался во время передачи")
	_ok(_hd.running, "час ждёт завершения отправки")
	var sla_before := float(_game.sla)
	for i in range(60):
		_hd.tick(0.1)
		if not _hd.running:
			break
	_ok(not _hd.running, "отправка завершила час")
	_eq(_hour_events, 1, "hour_finished ровно один раз")
	_eq(int(_hour_report.get("completed", 0)), 1, "запрос засчитан отправленным")
	_eq(int(_hour_report.get("requests_left", -1)), 0, "в отчёте нет брошенных запросов")
	_ok(float(_game.sla) >= sla_before - 0.001,
		"overtime не штрафует доигранный запрос")


## Без активных запросов час завершается сразу в тике, когда вышло время.
func _test_overtime_no_requests() -> void:
	_set_case("overtime_no_requests")
	_fresh(1)
	_eq(_hd.active_requests.size(), 0, "активных запросов нет")
	_hd.time_left = 0.05
	_hour_events = 0
	_hd.tick(0.1)
	_ok(not _hd.running, "без запросов час завершается сразу")
	_eq(_hour_events, 1, "hour_finished ровно один раз")
	_ok(_hd.is_overtime(), "overtime зафиксирован")
	_ok(bool(_hour_report.get("overtime", false)), "отчёт: overtime = true")


# --- конец часа во время мини-игры (B5b) -----------------------------------

func _test_hour_end_during_minigame() -> void:
	_set_case("hour_end_minigame")
	_fresh(1)
	var file = _new_file("Конец", "text", _folder_id())
	var file_id := str(file.id)
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
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
	# v4: время вышло, но запрос активен — час уходит в overtime и ждёт игрока.
	# Мини-игра при этом не закрывается принудительно, пока запрос жив.
	_ok(_hd.running, "час не завершился при открытой мини-игре")
	_ok(_hd.is_overtime(), "time_left=0 → overtime")
	_eq(_hour_events, 0, "hour_finished не эмитится в overtime")
	_ok(_hd.is_minigame_active(), "мини-игра остаётся открытой в overtime")
	_ok(_hd.active_requests.has(req_id), "запрос ещё активен в overtime")
	_eq(_game.money, money_before, "в overtime выплаты ещё нет")
	# Отклонение возможно только после закрытия мини-игры; force-close снимает
	# последний запрос → час финиширует.
	_hd.force_close_send_minigame()
	_eq(_minigame_cancels, 1, "minigame_cancelled эмитится при закрытии")
	_ok(_hd.reject_request(req_id), "запрос отклонён в overtime")
	_hd.tick(0.1)
	_ok(not _hd.running, "после пустых запросов час завершился")
	_eq(_hour_events, 1, "hour_finished эмитится один раз")
	_ok(_hd._minigame == null, "мини-игра принудительно закрыта")
	_ok(not _hd.active_requests.has(req_id), "запрос не отправлен и снят")
	_ok(_game.registry.files.has(file_id), "файл не израсходован")
	_eq(_game.money, money_before - 5, "выплаты нет, только штраф за отказ")
	_ok(_hd.active_connections.is_empty(), "конец часа закрыл TCP-соединения")
	_eq(_hd.slots.used_count(), 0, "конец часа освободил все слоты")
	_ok(_hour_report.has("files_carry"), "отчёт содержит files_carry")
	_ok(_hour_report.has("packets_left"), "отчёт содержит packets_left")


# --- TCP-соединение --------------------------------------------------------

func _test_connection_flow() -> void:
	_set_case("connection")
	_fresh(1)
	_hd.active_request_limit = 0
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
	_ok(not req.has_connection(), "connection_id пуст до соединения")
	_ok(not req.is_ready(), "Request.is_ready = false без connection_id")
	_ok(not _hd.is_request_connected(req_id), "is_request_connected = false")

	# v3: контейнер нельзя собирать до соединения.
	_toasts.clear()
	_ok(not _hd.attach_file(req_id, file_id),
		"attach до соединения → false")
	_ok(_has_toast("СНАЧАЛА УСТАНОВИТЕ СОЕДИНЕНИЕ"),
		"тост «сначала установите соединение»")
	_eq(req.attached.size(), 0, "файл не прикреплён")

	var money_before := int(_game.money)
	_connection_shows = 0
	# Соединение первично: контейнер ещё пуст.
	_ok(_hd.connect_request(req_id), "connect_request без файлов → true")
	_eq(_connection_shows, 1, "show_connection эмитится один раз")
	_eq(_connection_request_id, req_id, "show_connection: request_id")
	_eq(_connection_hour, _hd.hour, "show_connection: hour")
	_eq(_connection_successes, 0, "show_connection: successes за забег")
	_ok(req.connecting and not req.minigame_active,
		"connecting=true, мини-игра отправки не открыта")
	_eq(req.connect_attempts, 1, "connect_attempts = 1")
	_ok(not _hd.start_send(req_id), "start_send во время connecting → false")
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
	_ok(not _hd.is_request_ready(req_id),
		"после неудачи TCP всё ещё не готов (нет соединения)")
	_toasts.clear()
	_ok(not _hd.connect_request(req_id), "connect_request во время кулдауна → false")
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
	_ok(req.has_connection(), "connection_id заполнен")
	_approx(float(req.connect_cooldown_until), 0.0, 0.001, "успех снял кулдаун")
	_eq(_hd.connect_successes, 1, "connect_successes = 1")
	_eq(_minigame_shows, 0, "успех соединения НЕ открывает мини-игру отправки")
	_ok(not req.minigame_active, "мини-игра отправки не активна")
	_eq(_hd.slots.used_count(), 1, "соединение заняло out-слот")
	var conn = _hd.get_connection(str(req.connection_id))
	_ok(conn != null, "TcpConnection создан")
	if conn != null:
		_eq(str(_hd.connection_id_for_request(req_id)), str(conn.id),
			"connection_id_for_request находит соединение")
		_eq(str(conn.request_id), req_id, "соединение привязано к запросу")
		_ok(not str(conn.ip).is_empty(), "у соединения есть IP")
		var conn_slot = _hd.slots.get_slot(int(conn.slot_index))
		_ok(conn_slot != null and bool(conn_slot.occupied), "слот соединения занят")
		if conn_slot != null:
			_eq(str(conn_slot.kind), "tcp_connection", "kind = tcp_connection")
			_eq(str(conn_slot.entity_id), str(conn.id), "entity_id = conn")
			_eq(str(conn_slot.entity_name), str(conn.client_name),
				"entity_name = имя клиента")
			_eq(str(conn_slot.detail), str(conn.ip), "detail = IP")
			_ok(bool(conn_slot.can_disconnect), "can_disconnect = true")
			_eq(str(conn_slot.linked_request_id), req_id,
				"linked_request_id = запрос")

	# После соединения контейнер собирается.
	_ok(_hd.attach_file(req_id, file_id), "файл прикреплён после соединения")
	_ok(_hd.is_request_ready(req_id), "запрос готов к отправке")
	_toasts.clear()
	_ok(_hd.attach_file(req_id, file_id), "повторный attach идемпотентен")
	_ok(not _hd.connect_request(req_id), "повторный connect_request при соединении → false")
	_ok(_hd.start_send(req_id), "start_send открывает мини-игру отправки")
	_eq(_minigame_shows, 1, "show_minigame отправки")
	_ok(req.minigame_active, "мини-игра отправки активна")
	var send_conn_id := str(req.connection_id)
	_hd._on_send_minigame_finished(0.8)
	_ok(req.sending, "после мини-игры TCP отправляется")
	_eq(_hd.slots.used_count(), 1, "TCP-отправка не резервирует второй слот")
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "запрос удалён после успешной отправки")
	_ok(_game.registry.files.has(file_id), "файл остался в реестре после TCP-отправки")
	var sent_kept = _game.registry.files.get(file_id)
	if sent_kept != null:
		_eq(str(sent_kept.location), "folder", "TCP: файл вернулся в папку")
	_eq(_hd.slots.used_count(), 1, "после TCP-отправки слот остаётся занятым")
	var idle_conn = _hd.get_connection(send_conn_id)
	_ok(idle_conn != null, "соединение пережило запрос")
	if idle_conn != null:
		_eq(str(idle_conn.request_id), "", "conn.request_id очищен")
		var idle_slot = _hd.slots.get_slot(int(idle_conn.slot_index))
		if idle_slot != null:
			_approx(float(idle_slot.progress), 0.0, 0.0001, "slot.progress = 0")
			_eq(str(idle_slot.linked_request_id), "", "linked_request_id очищен")
		_ok(_hd.disconnect_connection(send_conn_id), "disconnect освобождает слот")
		_eq(_hd.slots.used_count(), 0, "после disconnect 0 занятых слотов")
	_eq(_hd.active_requests.size(), 0, "активных запросов не осталось")

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


# --- v3: граничные случаи TCP-соединений -----------------------------------

## Соединение нельзя начать без свободного слота; успех не запускает
## отправку автоматически; attach доступен только после соединения.
func _test_tcp_model_edges() -> void:
	_set_case("tcp_send_without_connection")
	_fresh(1)
	var no_conn_file = _new_file("Без соединения", "text", _folder_id())
	var no_conn_req := str(_hd._create_request(1, "tcp", [str(no_conn_file.id)], false))
	_toasts.clear()
	_ok(not _hd.start_send(no_conn_req), "TCP start_send без соединения → false")
	_ok(_has_toast("СНАЧАЛА УСТАНОВИТЕ СОЕДИНЕНИЕ"),
		"start_send без соединения: тост")
	_ok(not bool(_hd.active_requests[no_conn_req].sending),
		"отправка не началась")
	_ok(not bool(_hd.active_requests[no_conn_req].minigame_active),
		"мини-игра отправки не открыта")
	_hd._cleanup_request(no_conn_req, true)

	_set_case("tcp_no_slot")
	_fresh(1)
	var file = _new_file("Нет слота", "text", _folder_id())
	var req_id := str(_hd._create_request(1, "tcp", [str(file.id)], false))
	var blocker := int(_hd.slots.reserve("out", "blocker"))
	_ok(blocker >= 0, "единственный слот занят")
	_toasts.clear()
	_ok(not _hd.connect_request(req_id), "нет свободного слота → connect_request false")
	_ok(_has_toast("ВСЕ КАНАЛЫ ЗАНЯТЫ"), "тост о занятых каналах")
	_ok(not bool(_hd.active_requests[req_id].connecting),
		"connecting не выставлен при отказе")
	_hd.slots.release(blocker)
	_hd._cleanup_request(req_id, true)

	_set_case("tcp_success_no_autosend")
	_fresh(1)
	var file2 = _new_file("Без авто", "text", _folder_id())
	var rid := str(_hd._create_request(1, "tcp", [str(file2.id)], false))
	_minigame_shows = 0
	_ok(_connect_tcp(rid), "соединение установлено")
	_eq(_minigame_shows, 0, "после connection_finished(true) мини-игры нет")
	_ok(not bool(_hd.active_requests[rid].sending), "отправка не началась сама")
	_ok(not bool(_hd.active_requests[rid].minigame_active), "мини-игра отправки не открыта")
	# Пустой контейнер: start_send объясняет, чего не хватает.
	_toasts.clear()
	_ok(not _hd.start_send(rid), "start_send без файлов → false")
	_ok(_has_toast("НЕ ВСЕ ФАЙЛЫ ПРИКРЕПЛЕНЫ"), "тост о неполном контейнере")
	_ok(_has_toast("0/1"), "тост показывает 0/1")
	_hd._cleanup_request(rid, true)

	_set_case("tcp_attach_after_reconnect")
	_fresh(1)
	var file3 = _new_file("Переподключение", "text", _folder_id())
	var rid3 := str(_hd._create_request(1, "tcp", [str(file3.id)], false))
	_ok(_connect_tcp(rid3), "первое соединение")
	var conn_id := str(_hd.active_requests[rid3].connection_id)
	_ok(_hd.disconnect_connection(conn_id), "disconnect до отправки")
	_ok(not _hd.active_requests[rid3].has_connection(),
		"после disconnect connection_id пуст")
	_ok(not _hd.attach_file(rid3, str(file3.id)),
		"attach снова требует соединения")
	_ok(_connect_tcp(rid3), "повторное соединение")
	_ok(_hd.attach_file(rid3, str(file3.id)), "attach после повторного соединения")
	_hd._cleanup_request(rid3, true)

	_set_case("start_hour_clears_connections")
	_fresh(1)
	var file4 = _new_file("Новый час", "text", _folder_id())
	var rid4 := str(_hd._create_request(1, "tcp", [str(file4.id)], false))
	_ok(_connect_tcp(rid4), "соединение перед рестартом часа")
	_eq(_hd.slots.used_count(), 1, "слот занят соединением")
	_hd.start_hour(1)
	_ok(_hd.active_connections.is_empty(), "start_hour закрыл соединения")
	_eq(_hd.slots.used_count(), 0, "start_hour освободил слоты")


## disconnect во время sending / reject / timeout: запрос и файлы живы,
## соединение закрыто, слот свободен, выплаты нет.
func _test_tcp_disconnect_cases() -> void:
	_set_case("tcp_disconnect_sending")
	_fresh(1)
	var file = _new_file("Отключение", "text", _folder_id())
	var fid := str(file.id)
	var rid := str(_hd._create_request(1, "tcp", [fid], false))
	_ok(_connect_tcp(rid), "соединение установлено")
	_ok(_hd.attach_file(rid, fid), "файл прикреплён")
	var req = _hd.active_requests[rid]
	var conn_id := str(req.connection_id)
	_ok(_hd.start_send(rid), "мини-игра отправки открыта")
	_hd._on_send_minigame_finished(1.0)
	_ok(bool(req.sending), "отправка идёт")
	req.send_duration = 100.0
	req.send_progress = 0.0
	var money_before := int(_game.money)
	_ok(_hd.disconnect_connection(conn_id), "disconnect во время sending")
	_ok(_hd.active_requests.has(rid), "запрос остаётся активным")
	_ok(not bool(req.sending), "отправка прервана")
	_ok(_game.registry.files.has(fid), "файл не израсходован")
	var kept = _game.registry.files.get(fid)
	if kept != null:
		_eq(str(kept.location), "folder", "файл откреплён и вернулся в папку")
	_eq(int(_game.money), money_before, "выплаты нет")
	_eq(str(req.connection_id), "", "connection_id сброшен")
	_eq(_hd.slots.used_count(), 0, "слот освобождён")
	var t0 := float(req.time_left)
	_hd.tick(0.1)
	_approx(float(req.time_left), t0 - 0.1, 0.001, "таймер запроса снова идёт")
	_hd._cleanup_request(rid, true)

	_set_case("tcp_reject_closes")
	_fresh(1)
	var file2 = _new_file("Отказ", "text", _folder_id())
	var fid2 := str(file2.id)
	var rid2 := str(_hd._create_request(1, "tcp", [fid2], false))
	_ok(_connect_tcp(rid2), "соединение установлено")
	_ok(_hd.attach_file(rid2, fid2), "файл прикреплён")
	var conn2 := str(_hd.active_requests[rid2].connection_id)
	_ok(_hd.reject_request(rid2), "reject_request")
	_ok(not _hd.active_requests.has(rid2), "запрос удалён")
	_ok(not _hd.active_connections.has(conn2), "reject закрыл соединение")
	_eq(_hd.slots.used_count(), 0, "reject освободил слот")
	_ok(_game.registry.files.has(fid2), "файл не израсходован")
	var kept2 = _game.registry.files.get(fid2)
	if kept2 != null:
		_eq(str(kept2.location), "folder", "файл вернулся в папку")

	_set_case("tcp_timeout_closes")
	_fresh(1)
	var file3 = _new_file("Таймаут conn", "text", _folder_id())
	var fid3 := str(file3.id)
	var rid3 := str(_hd._create_request(1, "tcp", [fid3], false))
	_ok(_connect_tcp(rid3), "соединение установлено")
	_ok(_hd.attach_file(rid3, fid3), "файл прикреплён")
	var conn3 := str(_hd.active_requests[rid3].connection_id)
	_hd.active_requests[rid3].time_left = 0.05
	_hd.tick(0.1)
	_ok(not _hd.active_requests.has(rid3), "таймаут снял запрос")
	_ok(not _hd.active_connections.has(conn3), "timeout закрыл соединение")
	_eq(_hd.slots.used_count(), 0, "timeout освободил слот")
	_ok(_game.registry.files.has(fid3), "файл не израсходован")


# --- v3: UDP-надёжность ------------------------------------------------------

func _test_udp_model() -> void:
	_set_case("udp_chance")
	_fresh(1)
	for lvl in range(5):
		_game.set_lot_level("lot_udp", int(lvl))
		_approx(_hd.udp_success_chance(), 0.40 + 0.10 * float(lvl), 0.0001,
			"UDP chance при lot_udp=%d" % lvl)
	_game.upgrades["udp_level"] = 9
	_game.upgrades["lot_udp"] = 9
	_approx(_hd.udp_success_chance(), 0.80, 0.0001, "UDP chance кап 80%")
	_game.upgrades.erase("udp_level")
	_game.upgrades.erase("lot_udp")
	_approx(_hd.udp_success_chance(), 0.40, 0.0001, "без лота UDP chance 40%")

	_set_case("udp_success")
	_fresh(1)
	var file = _new_file("UDP успех", "text", _folder_id())
	var fid := str(file.id)
	var rid := str(_hd._create_request(1, "udp", [fid], false))
	_ok(_hd.attach_file(rid, fid), "UDP-файл прикреплён")
	_hd.udp_roll_override = 0.0
	var money_before := int(_game.money)
	var sla_before := float(_game.sla)
	_ok(_hd.start_send(rid), "UDP мини-игра открыта")
	_hd._on_send_minigame_finished(1.0)
	_ok(bool(_hd.active_requests[rid].sending), "UDP отправка началась")
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(rid):
			break
	_ok(not _hd.active_requests.has(rid), "успешный UDP завершил запрос")
	_ok(_game.registry.files.has(fid), "успешный UDP сохранил файл")
	var udp_kept = _game.registry.files.get(fid)
	if udp_kept != null:
		_eq(str(udp_kept.location), "folder", "UDP: файл вернулся в папку")
	_ok(int(_game.money) > money_before, "успешный UDP выплатил деньги")
	_approx(float(_game.sla), sla_before, 0.001, "успешный UDP не штрафует SLA")
	_eq(_hd.slots.used_count(), 0, "успешный UDP освободил слот")
	_eq(int(_hd._udp_lost), 0, "успешный UDP без потерь")
	_hd.udp_roll_override = -1.0

	_set_case("udp_fail_retry")
	_fresh(1)
	var file2 = _new_file("UDP провал", "text", _folder_id())
	var fid2 := str(file2.id)
	var rid2 := str(_hd._create_request(1, "udp", [fid2], false))
	_ok(_hd.attach_file(rid2, fid2), "UDP-файл прикреплён")
	_game.streak = 5
	_hd.udp_roll_override = 1.0
	var money2 := int(_game.money)
	var sla2 := float(_game.sla)
	_ok(_hd.start_send(rid2), "UDP мини-игра открыта (провал)")
	_hd._on_send_minigame_finished(1.0)
	var req = _hd.active_requests.get(rid2)
	_ok(req != null and bool(req.sending), "UDP отправка началась")
	for i in range(200):
		_hd.tick(0.1)
		if not bool(req.sending):
			break
	_ok(_hd.active_requests.has(rid2), "при UDP-провале запрос остаётся")
	_ok(_game.registry.files.has(fid2), "при UDP-провале файл жив")
	_eq(int(_game.money), money2, "при UDP-провале выплаты нет")
	_approx(float(_game.sla), sla2 - 3.0, 0.001, "UDP-провал: −3 SLA")
	_eq(int(req.udp_failures), 1, "udp_failures = 1")
	_approx(float(req.udp_retry_until), float(_hd.hour_elapsed) + 4.0, 0.01,
		"udp_retry_until = elapsed + 4")
	_eq(int(_game.streak), 0, "UDP-провал сбрасывает streak")
	_eq(int(_hd._udp_lost), 1, "UDP-провал учтён в _udp_lost")
	_eq(_hd.slots.used_count(), 0, "UDP-провал освободил слот")
	_ok(_has_toast("ПАКЕТ ПОТЕРЯН"), "тост о потере UDP-пакета")
	_toasts.clear()
	_ok(not _hd.start_send(rid2), "повтор UDP до кулдауна → false")
	_ok(_has_toast("ПОВТОР ЧЕРЕЗ"), "тост о кулдауне UDP")
	# После кулдауна повтор проходит.
	_hd.hour_elapsed = float(req.udp_retry_until) + 0.01
	_hd.udp_roll_override = 0.0
	_ok(_hd.start_send(rid2), "повтор UDP после кулдауна → true")
	_hd._on_send_minigame_finished(1.0)
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(rid2):
			break
	_ok(not _hd.active_requests.has(rid2), "повторный UDP завершился успешно")
	_ok(_game.registry.files.has(fid2), "повторный UDP сохранил файл")
	_eq(_hd.slots.used_count(), 0, "повторный UDP освободил слот")
	_hd.udp_roll_override = -1.0

	# v5: третья попытка гарантированно успешна, даже если ролл форсит провал.
	_set_case("udp_third_attempt_guaranteed")
	_fresh(1)
	var file3 = _new_file("UDP третья", "text", _folder_id())
	if file3 == null:
		return
	var fid3 := str(file3.id)
	var rid3 := str(_hd._create_request(1, "udp", [fid3], false))
	_ok(_hd.attach_file(rid3, fid3), "UDP-файл прикреплён")
	var req3 = _hd.active_requests.get(rid3)
	if req3 == null:
		return
	_hd.udp_roll_override = 1.0
	for attempt in [1, 2]:
		_ok(_hd.start_send(rid3), "попытка %d: мини-игра открыта" % attempt)
		_hd._on_send_minigame_finished(1.0)
		_ok(bool(req3.sending), "попытка %d: отправка идёт" % attempt)
		for i in range(200):
			_hd.tick(0.1)
			if not bool(req3.sending):
				break
		_ok(_hd.active_requests.has(rid3), "попытка %d: запрос жив" % attempt)
		_eq(int(req3.udp_failures), attempt,
			"попытка %d: udp_failures = %d" % [attempt, attempt])
		_eq(int(_hd._udp_lost), attempt, "попытка %d: потеря учтена" % attempt)
		_hd.hour_elapsed = float(req3.udp_retry_until) + 0.01
	_eq(int(req3.udp_failures), 2, "после двух провалов udp_failures = 2")
	var money3 := int(_game.money)
	var sla3 := float(_game.sla)
	_ok(_hd.start_send(rid3), "третья попытка стартует (override=1.0)")
	_hd._on_send_minigame_finished(1.0)
	_ok(bool(req3.sending), "третья попытка: отправка идёт")
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(rid3):
			break
	_ok(not _hd.active_requests.has(rid3), "третья попытка завершила запрос успехом")
	_ok(int(_game.money) > money3, "третья попытка выплатила деньги")
	_approx(float(_game.sla), sla3, 0.001, "третья попытка без штрафа SLA")
	_eq(int(_hd._udp_lost), 2, "третья попытка не добавила потерь")
	_ok(_game.registry.files.has(fid3), "файл вернулся после третьей попытки")
	_hd.udp_roll_override = -1.0


# --- v5: протокол нового запроса -------------------------------------------

## spawn_request_now(1, "udp") → UDP без TCP; spawn_request_now(1) → TCP.
## Готовность UDP не требует соединения (RequestCard тоже).
func _test_spawn_request_protocol() -> void:
	_set_case("spawn_request_udp")
	_fresh(2)
	var folder_id := _folder_id()
	_ok(_new_file("UDP спавн", "text", folder_id) != null, "файл для UDP создан")
	_ok(_new_file("TCP спавн", "text", folder_id) != null, "файл для TCP создан")
	var udp_id := str(_hd.spawn_request_now(1, "udp"))
	_ok(not udp_id.is_empty(), "spawn_request_now(1, udp) создал запрос")
	if udp_id.is_empty():
		return
	var udp_req = _hd.active_requests[udp_id]
	_eq(str(udp_req.protocol), "udp", "форс-спавн: протокол udp")
	_ok(not udp_req.has_connection(), "UDP: connection_id пуст")
	_ok(not udp_req.connected, "UDP: connected = false")
	var udp_ids: Array = _hd.request_required_ids(udp_id)
	_eq(udp_ids.size(), 1, "UDP: один required")
	_ok(_hd.attach_file(udp_id, udp_ids[0]), "UDP: attach без TCP разрешён")
	_ok(_hd.is_request_ready(udp_id), "UDP готов без TCP")
	_ok(not _hd.is_request_connected(udp_id), "UDP: is_request_connected = false")
	_minigame_shows = 0
	_ok(_hd.start_send(udp_id), "UDP: start_send без TCP")
	_eq(_minigame_shows, 1, "UDP: мини-игра отправки открыта")

	# RequestCard: для UDP нет ожидания TCP и кнопка соединения скрыта.
	var card = REQUEST_CARD.new()
	root.add_child(card)
	card.setup(udp_id, "Клиент", "cli_udp", "UDP",
		[{"type": "text", "attached": true}], 30.0, 30.0, 0.0, 1,
		false, false, 1, "text", 1, false, true, false, false, "", 0.5, 0.0)
	_ok(not card._tcp_waiting(), "RequestCard UDP: не ждёт TCP")
	_ok(not card._connect_btn.visible, "RequestCard UDP: кнопки соединения нет")
	_ok(card.can_send(), "RequestCard UDP: can_send = true")
	_ok(not card.send_disabled(), "RequestCard UDP: ОТПРАВИТЬ активна")
	card.free()
	_hd.force_close_send_minigame()
	_hd._cleanup_request(udp_id, true)

	_set_case("spawn_request_tcp_default")
	_fresh(2)
	_new_file("TCP по умолчанию", "text", _folder_id())
	var tcp_id := str(_hd.spawn_request_now(1))
	_ok(not tcp_id.is_empty(), "spawn_request_now(1) создал запрос")
	if tcp_id.is_empty():
		return
	_eq(str(_hd.active_requests[tcp_id].protocol), "tcp", "без override → tcp")
	_ok(not _hd.active_requests[tcp_id].has_connection(), "TCP: соединения ещё нет")
	var tcp_ids: Array = _hd.request_required_ids(tcp_id)
	_ok(not _hd.attach_file(tcp_id, tcp_ids[0]), "TCP: attach без соединения запрещён")
	_ok(not _hd.is_request_ready(tcp_id), "TCP без соединения не готов")
	_ok(not _hd.is_request_connected(tcp_id), "TCP: is_request_connected = false")
	_hd._cleanup_request(tcp_id, true)


# --- v5: низкое качество мини-игры -----------------------------------------

## q < send_quality_min: передача не стартует, файлы и TCP-соединение целы.
## Повторная отправка с q=0.8 доходит до выплаты.
func _test_low_quality_retry() -> void:
	_set_case("send_low_quality")
	_fresh(1)
	_hd.active_request_limit = 0
	var file = _new_file("Качество", "text", _folder_id())
	_ok(file != null, "файл создан")
	if file == null:
		return
	var fid := str(file.id)
	var req_id := str(_hd._create_request(1, "tcp", [fid], false))
	_ok(not req_id.is_empty(), "TCP-запрос создан")
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
	var req = _hd.active_requests.get(req_id)
	if req == null:
		return
	var conn_id := str(req.connection_id)
	_ok(not conn_id.is_empty(), "соединение привязано")
	_ok(_hd.attach_file(req_id, fid), "файл прикреплён")

	_hd.send_game_factory = func(_id, _tier, _seed, _ctx): return StubSendGame.new()
	_minigame_shows = 0
	_ok(_hd.start_send(req_id), "старт отправки со stub-игрой")
	_eq(_minigame_shows, 1, "stub-мини-игра показана")
	var attached_before: Array = req.attached.duplicate()
	_toasts.clear()
	_hd._on_send_minigame_finished(0.2)

	_ok(_hd.active_requests.has(req_id), "q=0.2: запрос остаётся активным")
	_eq(req.attached, attached_before, "q=0.2: attached не изменился")
	_ok(_hd.active_connections.has(conn_id), "q=0.2: соединение живо")
	_ok(_hd._connection_open(conn_id), "q=0.2: соединение открыто")
	_ok(not req.sending, "q=0.2: отправка не начата")
	_ok(not req.minigame_active, "q=0.2: мини-игра закрыта")
	_approx(float(req.quality), 0.2, 0.0001, "q=0.2: качество сохранено")
	_ok(_hd.is_request_ready(req_id), "q=0.2: запрос снова готов")
	_ok(_has_toast("НИЗКОЕ КАЧЕСТВО"), "q=0.2: тост о низком качестве")

	# Повторная отправка с нормальным качеством проходит до выплаты.
	var money_before := int(_game.money)
	var streak_before := int(_game.streak)
	_minigame_shows = 0
	_ok(_hd.start_send(req_id), "повторная отправка стартует")
	_eq(_minigame_shows, 1, "повторная stub-мини-игра показана")
	_hd._on_send_minigame_finished(0.8)
	_ok(bool(req.sending), "q=0.8: отправка пошла")
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "q=0.8: запрос завершён")
	_ok(int(_game.money) > money_before,
		"q=0.8: выплата начислена (%d → %d)" % [money_before, int(_game.money)])
	_eq(int(_game.streak), streak_before + 1, "q=0.8: streak увеличен")
	_ok(_game.registry.files.has(fid), "q=0.8: файл вернулся в папку")
	_hd.send_game_factory = Callable()


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
	_ok(_connect_tcp(req_id), "соединение установлено для прикрепления замены")
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
	_connection_shows = 0
	_hd.set_modal_open(true)
	_ok(not _hd.connect_request(req2), "C2: connect_request при modal_open → false")
	var req2_live = _hd.active_requests.get(req2)
	_ok(req2_live != null and not bool(req2_live.connecting),
		"C2: connecting не выставлен")
	_eq(_connection_shows, 0, "C2: show_connection не эмитился")
	_ok(_has_toast("закройте текущее окно"), "C2: тост о занятом окне для TCP")
	_hd.set_modal_open(false)
	_ok(_connect_tcp(req2), "C2: после закрытия модалки соединение установлено")
	_ok(_hd.attach_file(req2, str(file2.id)), "TCP-файл прикреплён после соединения")
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
	_eq(_hd.get("request_cap"), null, "request_cap удалён из директора")
	_ok(not _hour_row(2).has("request_cap"), "H2: request_cap удалён из данных")
	_eq(_hd.active_request_limit, int(_hour_row(2).get("active_requests", -1)),
		"H2: активный лимит из данных")
	var file = _new_file("Отчёт", "sound", _folder_id())
	var req_id: String = str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_connect_tcp(req_id), "TCP-соединение установлено")
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
	for key in ["hour", "hour_duration", "earned", "money_delta", "completed",
			"failed", "attacks", "attacks_failed", "sla_delta", "time_left",
			"packets_left", "requests_left", "files_carry", "files_budget",
			"files_total", "files_spawned", "files_sent", "cells_free",
			"requests_spawned", "requests_timed_out", "requests_rejected",
			"send_interval"]:
		_ok(_hour_report.has(key), "отчёт содержит %s" % key)
	_ok(not _hour_report.has("request_cap"), "отчёт без request_cap")
	_eq(int(_hour_report.get("hour", 0)), 2, "отчёт: hour = 2")
	_eq(int(_hour_report.get("completed", 0)), 1, "отчёт: completed = 1")
	_eq(int(_hour_report.get("files_budget", 0)), 8, "отчёт: files_budget H2 = 8")
	_eq(int(_hour_report.get("files_total", 0)), 8, "отчёт: files_total H2 = 8")
	_approx(float(_hour_report.get("hour_duration", 0.0)), 150.0, 0.0001,
		"отчёт: hour_duration H2 = 150")
	_approx(float(_hour_report.get("send_interval", 0.0)), 24.0, 0.0001,
		"отчёт: send_interval H2 = 24")
	_eq(int(_hour_report.get("files_sent", 0)), 1, "отчёт: files_sent = 1")
	_ok(int(_hour_report.get("cells_free", -1)) >= 0, "отчёт: cells_free")
	_eq(int(_hour_report.get("files_carry", -1)), 0,
		"отчёт: files_carry = 0 (переноса нет)")
	_eq(int(_hour_report.get("files_spawned", -1)), int(_hd.files_spawned),
		"отчёт: files_spawned фактический")


## v4: любой спавн запроса заканчивается completed/timed_out/rejected/left.
func _test_report_reconcile() -> void:
	_set_case("report_reconcile")
	_fresh(1)
	for i in range(20):
		_new_file("Сверка", "text", _folder_id())
	_hd.files_spawned = _hd.files_budget
	_hd._next_spawn_at = 99999.0
	if _hd.attack_director != null:
		_hd.attack_director._schedule.clear()
		_hd.attack_director._next_index = 0
	_hour_events = 0
	_hour_report = {}
	while _hd.running:
		_hd.tick(0.1)
	_eq(_hour_events, 1, "час завершился один раз")
	var spawned := int(_hour_report.get("requests_spawned", -1))
	var completed := int(_hour_report.get("completed", -1))
	var timed_out := int(_hour_report.get("requests_timed_out", -1))
	var rejected := int(_hour_report.get("requests_rejected", -1))
	var left := int(_hour_report.get("requests_left", -1))
	_ok(spawned > 0, "requests_spawned > 0 (получено %d)" % spawned)
	_ok(timed_out > 0, "часть запросов истекла по таймауту")
	_eq(spawned, completed + timed_out + rejected + left,
		"reconcile: spawned = completed + timed_out + rejected + left")


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
	var seed_files: Array = _game.registry.files.values()
	if seed_files.size() == 1:
		_eq(str(seed_files[0].location), "folder", "reset_for_prep: seed лежит в папке")
		_eq(str(seed_files[0].required_by), "", "reset_for_prep: seed без резерва")
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
	_hd.udp_roll_override = -1.0
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
	_hd._next_spawn_at = 999999.0
	_hd.active_request_limit = 0
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


## Файл, занимающий конкретную клетку папки (для точного освобождения места).
func _file_at(folder_id: String, origin: Vector2i):
	for file in _game.registry.get_folder_files(folder_id):
		if Vector2i(file.origin) == origin:
			return file
	return null


## v3: TCP-запрос можно собрать только после установленного соединения.
func _connect_tcp(req_id: String) -> bool:
	var req = _hd.active_requests.get(req_id)
	if req == null:
		return false
	if req.has_connection():
		return true
	if not _hd.connect_request(req_id):
		return false
	return bool(_hd.connection_finished(req_id, true))


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


func _on_spawn_frozen(reason: String) -> void:
	_frozen_events += 1
	_frozen_reasons.append(str(reason))


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
		_hd = null
	_stop_audio()
	await process_frame
	await process_frame
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		audio.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("test_hour: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_hour" if _fails == 0 else "FAIL test_hour")
	quit(0 if _fails == 0 else 1)


## Гасим аудио, чтобы Godot не считал WAV-ресурсы утёкшими.
func _stop_audio() -> void:
	var audio = root.get_node_or_null("Audio")
	if audio == null:
		return
	if audio.has_method("stop_music"):
		audio.call("stop_music")
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.stop()
			player.stream = null
	if audio.get("_sfx_streams") is Dictionary:
		(audio.get("_sfx_streams") as Dictionary).clear()
	if audio.get("_music_streams") is Dictionary:
		(audio.get("_music_streams") as Dictionary).clear()
