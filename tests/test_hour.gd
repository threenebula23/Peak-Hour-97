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
var _frozen_events: int = 0


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

	_test_start_hour()
	_test_budgets_and_weights()
	_test_spawn_window_budget()
	_test_carry()
	_test_receive()
	_test_receive_cancel_and_no_space()
	_test_request_caps()
	_test_attach_detach()
	_test_protocol()
	_test_send_minigame_pause()
	_test_out_slot_queue()
	_test_file_consumption()
	_test_send_timer_freeze()
	_test_timeout_preserves_files()
	_test_hour_end_during_minigame()
	_test_no_connection_game()
	_test_report()
	_finish()


# --- старт -----------------------------------------------------------------

func _test_start_hour() -> void:
	_set_case("start_hour")
	_fresh(1)
	_eq(_hd.hour, 1, "hour = 1")
	_approx(_hd.time_left, 300.0, 0.0001, "длительность часа 300 с")
	_ok(_hd.running, "час запущен")
	_eq(_hd.files_budget, 4, "H1: бюджет 4 файла")
	_eq(_hd.files_spawned, 0, "H1: файлы ещё не спавнились")
	_eq(_hd.request_cap, 2, "H1: кап запросов 2")
	_eq(_hd.active_request_limit, 1, "H1: 1 активный запрос")
	_approx(_hd.spawn_window, 225.0, 0.0001, "окно спавна 75% часа = 225 с")
	_eq(_hd.slots.max_slots(), 1, "H1: 1 слот")
	_eq(_hd.buffer_limit(), 6, "H1: буфер 6")
	_approx(_hd._recv_interval(), 12.0, 0.0001, "legacy recv_interval H1 = 12")
	_approx(_hd._receive_interval(), 225.0 / 4.0, 0.0001, "спавн-интервал 225/4")
	_approx(_hd._send_interval(), 22.0, 0.0001, "send_interval H1 = 22")
	_eq(_hd._max_requests(), 1, "max concurrent requests H1 = 1")
	_eq(_hd._type_pool(), ["text", "sound"], "H1: только text/sound")
	_eq(_hd.active_packets.size(), 0, "активных пакетов нет")
	_eq(_hd.active_requests.size(), 0, "активных запросов нет")
	_ok(_hd.attack_director != null, "AttackDirector создан")
	_eq(_hd.attack_director._schedule.size(), 0, "H1: атак нет")
	_ok(_hd._minigame == null, "мини-игра не открыта")


# --- бюджеты и веса --------------------------------------------------------

func _test_budgets_and_weights() -> void:
	_set_case("budgets_weights")
	for pair in [[1, 4], [2, 8], [3, 12], [4, 16], [5, 20], [6, 20], [9, 20]]:
		_fresh(int(pair[0]))
		_eq(_hd.files_budget, int(pair[1]), "H%d: бюджет %d" % [int(pair[0]), int(pair[1])])

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


# --- перенос файлов --------------------------------------------------------

func _test_spawn_window_budget() -> void:
	_set_case("spawn_window_budget")
	_fresh(1)
	_hd.files_spawned = 0
	_hd.spawned_this_hour = 0
	_hd.requests_spawned = _hd.request_cap
	_hd.spawn_recv_accum = 0.0
	for i in range(3000):
		_hd.tick(0.1)
		if _hd.hour_elapsed >= _hd.spawn_window + 0.4:
			break
	_eq(_hd.files_spawned, 4, "H1: все 4 файла успевают в окно 225 с")
	_eq(_hd.spawned_this_hour, 4, "H1: счётчик спавна = 4")
	_ok(_hd.active_packets.size() <= 4, "в буфере не больше бюджета файлов")
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
	_eq(_hd.carry_files, 3, "недоспавненные 3 файла переносятся")
	_eq(int(_hd.report().get("files_carry", -1)), 3, "отчёт: files_carry = 3")

	_game.hour = 2
	_hd.start_hour(2)
	_eq(_hd.files_budget, 11, "H2: 8 базовых + 3 переноса")
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
	_hd.tick(0.15)
	_eq(_hd.active_requests.size(), 1, "H1: одновременно 1 запрос")
	_eq(_hd.requests_spawned, 1, "H1: запрос №1 создан")
	var req_id := str(_hd.active_requests.keys()[0])
	var req = _hd.active_requests[req_id]
	_ok(req.attached.is_empty(), "файлы не прикрепляются автоматически")
	_ok(req.required_count() == _hd.request_required_count(req_id),
		"required_count() = число слотов контейнера")
	for placeholder in req.required:
		_ok(not _game.registry.files.has(str(placeholder)), "в required нет заранее выбранных файлов")
	_ok(_hd.request_required_count(req_id) >= 1 and _hd.request_required_count(req_id) <= 2,
		"H1: нужно 1–2 файла")
	_ok(not _hd.is_request_ready(req_id), "пустой запрос не готов")
	_ok(not req.is_ready(), "legacy Request.is_ready тоже false")
	_approx(req.time_left, req.timer_total, 0.0001, "таймер запроса стартовал сразу")

	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	for i in range(20):
		_hd.tick(0.1)
	_eq(_hd.requests_spawned, 1, "при активном лимите новый запрос не появляется")

	_hd._cleanup_request(req_id, true)
	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	_hd.tick(0.15)
	_eq(_hd.active_requests.size(), 1, "после освобождения слота создан второй запрос")
	_eq(_hd.requests_spawned, 2, "H1: два запроса — кап")
	var second_id := str(_hd.active_requests.keys()[0])
	_hd._cleanup_request(second_id, true)

	_hd._send_interval_current = 0.1
	_hd.spawn_send_accum = 0.0
	_hd.tick(0.15)
	_eq(_hd.requests_spawned, 2, "H1: третий запрос не создаётся (кап 2)")
	_eq(_hd.active_requests.size(), 0, "лишних запросов нет")


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

	_ok(_hd.attach_file(req_id, str(f1.id)), "файл 1 прикреплён")
	_eq(str(f1.location), "attached", "файл 1 остался в папке (location attached)")
	_eq(req.attached.size(), 1, "attached = 1")
	_ok(not req.sending, "attach не запускает отправку")
	_ok(_hd.attach_file(req_id, str(f2.id)), "файл 2 прикреплён")
	_eq(req.attached.size(), 2, "attached = 2")
	_ok(not req.sending, "после заполнения автоотправки нет")
	_ok(_hd.is_request_ready(req_id), "собранный запрос готов")
	_ok(not _hd.attach_file(req_id, str(f3.id)), "третий файл сверх лимита отклонён")

	_ok(_hd.detach_file(req_id, str(f1.id)), "файл 1 откреплён")
	_eq(req.attached.size(), 1, "attached = 1 после detach")
	_eq(str(f1.location), "folder", "detach вернул файл в папку")
	_ok(not _hd.detach_file(req_id, str(f3.id)), "неприкреплённый файл не открепить")

	var req2: String = str(_hd.spawn_request_now(1))
	_ok(_hd.attach_file(req2, str(f3.id)), "файл 3 прикреплён к другому запросу")
	_ok(not _hd.attach_file(req_id, str(f3.id)), "занятый файл нельзя прикрепить дважды")

	var f4 = _new_file("Стол", "text", folder_id)
	if f4 != null:
		_ok(_game.registry.move_file_to_table(str(f4.id)), "файл убран на стол")
		_ok(not _hd.attach_file(req_id, str(f4.id)), "файл со стола нельзя прикрепить")
	_hd._cleanup_request(req_id, true)
	_hd._cleanup_request(req2, true)


# --- протокол --------------------------------------------------------------

func _test_protocol() -> void:
	_set_case("protocol")
	_fresh(1)
	var file = _new_file("Протокол", "text", _folder_id())
	var req_id: String = str(_hd.spawn_request_now(1))
	_eq(str(_hd.active_requests[req_id].protocol), "tcp", "по умолчанию tcp")
	_ok(_hd.set_request_protocol(req_id, "udp"), "tcp → udp разрешён")
	_eq(str(_hd.active_requests[req_id].protocol), "udp", "протокол udp")
	_ok(not _hd.set_request_protocol(req_id, "smtp"), "неизвестный протокол отклонён")
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра отправки открыта")
	_ok(not _hd.set_request_protocol(req_id, "tcp"), "после старта мини-игры протокол не меняется")
	_hd.force_close_send_minigame()
	_hd._cleanup_request(req_id, true)


# --- мини-игра отправки ----------------------------------------------------

func _test_send_minigame_pause() -> void:
	_set_case("send_minigame_pause")
	_fresh(1)
	var file = _new_file("Мини", "text", _folder_id())
	var req_id: String = str(_hd.spawn_request_now(1))
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
	var req_id: String = str(_hd.spawn_request_now(1))
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
	var req_id: String = str(_hd.spawn_request_now(1))
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
	var req_id: String = str(_hd.spawn_request_now(1))
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
	var req_id: String = str(_hd.spawn_request_now(1))
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
	var req_id: String = str(_hd.spawn_request_now(1))
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


# --- соединение удалено ----------------------------------------------------

func _test_no_connection_game() -> void:
	_set_case("no_connection")
	_fresh(1)
	_connection_shows = 0
	var packet_id := str(_hd.spawn_packet_now("text"))
	_ok(not _hd.connect_packet(packet_id), "connect_packet — заглушка false")
	_ok(not _hd.connect_request("req_x"), "connect_request — заглушка false")
	_ok(_hd.receive_packet(packet_id, _folder_id()), "приём работает без соединения")
	for i in range(100):
		_hd.tick(0.1)
		if not _hd.active_packets.has(packet_id):
			break
	_eq(_connection_shows, 0, "show_connection ни разу не эмитится")
	_ok(_hd._minigame == null, "Connection/MiniGame не создаётся для приёма")


# --- отчёт -----------------------------------------------------------------

func _test_report() -> void:
	_set_case("report")
	_fresh(2)
	_eq(_hd.request_cap, 5, "H2: кап запросов из данных = 5")
	_eq(_hd.active_request_limit, 2, "H2: 2 активных запроса")
	var file = _new_file("Отчёт", "sound", _folder_id())
	var req_id: String = str(_hd.spawn_request_now(1))
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


# --- служебное -------------------------------------------------------------

func _fresh(hour: int) -> void:
	_game.start_new_run(1000 + int(hour) * 17)
	_game.hour = int(hour)
	_game.phase = &"hour"
	_game.money = 500
	_game.sla = 100.0
	_game.upgrades["sla_level"] = 4
	_hd.reset_carry()
	_hd.start_hour(int(hour))
	_hd.set_time_scale(1.0)
	if _hd.attack_director != null:
		_hd.attack_director._schedule.clear()
		_hd.attack_director._next_index = 0
	_hour_events = 0
	_hour_report = {}
	_minigame_cancels = 0


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


func _on_show_connection(_game_node) -> void:
	_connection_shows += 1


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
