extends SceneTree
## Интеграция v2: полный час на ускоренном времени, 9 часов подряд,
## слоты/очередь, явная отправка с мини-игрой, приём фигуры в папку.
##
## Запуск:
##   godot --headless --path . --script tests/test_integration.gd
##
## Атакующие мини-игры автоматически завершаются успешно, иначе час встал бы
## на паузе. Мини-игра отправки завершается сразу с q=0.8.

const HD := preload("res://scripts/core/hour_director.gd")

var _checks: int = 0
var _fails: int = 0
var _known: int = 0
var _case: String = ""
var _game = null
var _hd = null
var _hour_events: int = 0
var _reports: Array = []
var _attack_marks: Array = []
var _send_minigames: int = 0
var _seq: int = 0


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_hd = HD.new()
	_hd.hour_finished.connect(_on_hour_finished)
	_hd.attack_added.connect(_on_attack_added)
	_hd.show_attack_minigame.connect(_on_show_attack_minigame)
	_hd.show_minigame.connect(_on_show_minigame)
	_test_full_hour()
	_test_nine_hours()
	_test_slots_and_queue()
	_test_explicit_send()
	_test_receive_to_folder()
	_finish()


# --- один час --------------------------------------------------------------

func _test_full_hour() -> void:
	_set_case("full_hour")
	_game.start_new_run(1234)
	_hd.start_hour(1)
	_hd.set_time_scale(16.0)
	_hour_events = 0
	_reports.clear()
	_attack_marks.clear()
	var ticks := 0
	while _hd.running and ticks < 3000:
		_hd.tick(0.1)
		ticks += 1
	_ok(not _hd.running, "час завершился")
	_ok(ticks < 3000, "час завершился за отведённые тики (ticks=%d)" % ticks)
	_eq(_hour_events, 1, "hour_finished ровно один раз")
	if _reports.is_empty():
		return
	var report: Dictionary = _reports[0]
	_eq(int(report.get("hour", 0)), 1, "отчёт за час 1")
	for key in ["earned", "completed", "failed", "attacks", "sla_delta"]:
		_ok(report.has(key), "в отчёте есть %s" % key)
	_ok(not is_nan(float(report.get("sla_delta", 0.0))), "sla_delta не NaN")
	_ok(not is_nan(float(_game.sla)), "SLA не NaN")
	_ok(float(_game.sla) <= 200.0 + 0.0001, "SLA ≤ 200")
	_eq(_hd.slots.used_count(), 0, "все слоты освобождены после конца часа")
	_ok(_hd.active_packets.is_empty(), "после конца часа нет активных пакетов")
	_ok(_hd.active_requests.is_empty(), "после конца часа нет активных запросов")
	_ok(report.get("packets_left") == _hd.active_packets.size(), "packets_left в отчёте")
	_ok(report.get("requests_left") == _hd.active_requests.size(), "requests_left в отчёте")


# --- девять часов ----------------------------------------------------------

func _test_nine_hours() -> void:
	_set_case("nine_hours")
	_game.start_new_run(2026)
	# Высокий кап SLA, чтобы стресс-прогон не проигрался на таймаутах пакетов.
	_game.set_lot_level("lot_sla", 4)
	var expected: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4]
	for h in range(1, 10):
		_game.sla = _game.sla_cap()
		_game.phase = &"hour"
		_hour_events = 0
		_reports.clear()
		_attack_marks.clear()
		_hd.start_hour(h)
		_hd.set_time_scale(8.0)
		_eq(_game.hour, h, "Game.hour = %d" % h)
		_eq(_hd.slots.used_count(), 0, "час %d: слоты свободны на старте" % h)
		var ticks := 0
		while _hd.running and ticks < 4000:
			_hd.tick(0.1)
			ticks += 1
		_ok(not _hd.running, "час %d завершился" % h)
		_eq(_hour_events, 1, "час %d: hour_finished один раз" % h)
		if _reports.is_empty():
			continue
		var report: Dictionary = _reports[0]
		_eq(int(report.get("hour", 0)), h, "час %d: номер в отчёте" % h)
		for key in ["earned", "completed", "failed", "attacks", "sla_delta"]:
			_ok(report.has(key), "час %d: в отчёте есть %s" % [h, key])
		_ok(not is_nan(float(report.get("sla_delta", 0.0))), "час %d: sla_delta не NaN" % h)
		_ok(not is_nan(float(_game.sla)), "час %d: SLA не NaN" % h)
		_ok(float(_game.sla) <= 200.0 + 0.0001, "час %d: SLA ≤ 200" % h)
		_ok(int(_game.money) >= 0, "час %d: money >= 0" % h)
		_eq(_attack_marks.size(), expected[h - 1], "час %d: атак по расписанию" % h)
		for mark in _attack_marks:
			var t: float = float(mark.get("t", -1.0))
			_ok(t >= 58.0 and t <= 242.0, "час %d: окно спавна 60–240 (t=%.1f)" % [h, t])
		# Нет дедлока слотов: занятый слот всегда указывает на живую сущность.
		for slot in _hd.slots.slots:
			if slot.occupied:
				_ok(_hd.active_packets.has(slot.entity_id) or _hd.active_requests.has(slot.entity_id),
					"час %d: слот не висит на мёртвой сущности" % h)
		_game.phase = &"hour"
		_ok(_game.end_hour(), "час %d: end_hour()" % h)
		if h < 9:
			_eq(_game.hour, h + 1, "после часа %d Game.hour = %d" % [h, h + 1])
		else:
			_eq(_game.phase, &"results", "после 9-го часа фаза results")
	_eq(int(_game.stats.get("hours_done", 0)), 9, "stats.hours_done = 9")


# --- слоты и очередь -------------------------------------------------------

func _test_slots_and_queue() -> void:
	_set_case("slots_queue")
	_game.start_new_run(777)
	_hd.start_hour(1)
	_hd.set_time_scale(1.0)
	_hd._next_spawn_at = 9999.0
	_eq(_hd.slots.max_slots(), 1, "на старте 1 слот")
	var folder_id := _first_folder()

	var p1 := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(_hd.receive_packet(p1, folder_id), "пакет 1 принят в загрузку")
	_eq(_hd.slots.used_count(), 1, "пакет 1 занял слот")
	var p2 := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(not _hd.receive_packet(p2, folder_id), "второй пакет не влезает в единственный слот")
	_eq(_hd.slots.used_count(), 1, "после отказа слот не изменился")
	_tick_until_packet_gone(p1, 200)
	_eq(_hd.slots.used_count(), 0, "после загрузки пакета 1 слот свободен")
	_ok(_hd.receive_packet(p2, folder_id), "пакет 2 принимается после освобождения слота")
	_tick_until_packet_gone(p2, 200)

	# Занимаем слот приёмом снова, чтобы отправить запрос в очередь.
	var p3 := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(_hd.receive_packet(p3, folder_id), "пакет 3 занял слот")
	var file = _game.registry.create_file("queue.txt", "text", folder_id)
	_ok(file != null, "файл для запроса создан")
	if file == null:
		return
	var req_id := str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_ok(_hd.start_send(req_id), "мини-игра отправки открыта")
	_ok(_hd.is_minigame_active(), "мини-игра активна")
	_hd._on_send_minigame_finished(0.8)
	_ok(_hd.is_request_queued(req_id), "запрос встал в очередь out-слота")
	var req = _hd.active_requests.get(req_id)
	_ok(req != null and not req.sending, "в очереди запрос не отправляется")

	_tick_until_packet_gone(p3, 200)
	_ok(req != null and req.sending, "очередь выдала слот после загрузки пакета")
	_tick_until_request_gone(req_id, 300)
	_ok(not _hd.active_requests.has(req_id), "запрос завершён отправкой")
	_ok(not _game.registry.files.has(str(file.id)), "файл израсходован успешной отправкой")


# --- явная отправка --------------------------------------------------------

func _test_explicit_send() -> void:
	_set_case("explicit_send")
	_send_minigames = 0
	_game.start_new_run(778)
	_hd.start_hour(1)
	_hd.set_time_scale(1.0)
	_hd._next_spawn_at = 9999.0
	var folder_id := _first_folder()
	var file = _game.registry.create_file("explicit.txt", "text", folder_id)
	_ok(file != null, "файл для явной отправки создан")
	if file == null:
		return
	var req_id := str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	var req = _hd.active_requests.get(req_id)
	_ok(req != null, "запрос создан")
	_ok(req != null and not req.sending, "attach не запускает отправку")
	_ok(req != null and not req.minigame_active, "attach не открывает мини-игру")
	_eq(_send_minigames, 0, "мини-игр отправки ещё не было")

	var money_before := int(_game.money)
	_ok(_hd.start_send(req_id), "start_send запускает мини-игру")
	_eq(_send_minigames, 1, "show_minigame эмитится один раз")
	if req != null:
		_ok(req.minigame_active, "запрос в состоянии мини-игры")
		_ok(not req.sending, "отправка начнётся после мини-игры")
	_hd._on_send_minigame_finished(0.8)
	if req != null:
		_ok(not req.minigame_active, "мини-игра снята")
		_ok(req.sending or _hd.is_request_queued(req_id),
			"после мини-игры отправка или очередь")
	_tick_until_request_gone(req_id, 300)
	_ok(not _hd.active_requests.has(req_id), "запрос завершён отправкой")
	_ok(not _game.registry.files.has(str(file.id)), "файл израсходован при успехе")
	_ok(int(_game.money) > money_before, "деньги выросли при отправке")

	# Отмена мини-игры (force close) не расходует файл.
	var file2 = _game.registry.create_file("cancel.txt", "text", folder_id)
	_ok(file2 != null, "файл для отмены создан")
	if file2 == null:
		return
	var req_id2 := str(_hd._make_request([file2], "udp", false, "", ""))
	_ok(_hd.attach_file(req_id2, str(file2.id)), "файл отмены прикреплён")
	_ok(_hd.start_send(req_id2), "мини-игра отмены открыта")
	_hd.force_close_send_minigame()
	_ok(_game.registry.files.has(str(file2.id)), "отмена мини-игры сохранила файл")
	_ok(_hd.reject_request(req_id2), "запрос можно отклонить после отмены")
	_ok(_game.registry.files.has(str(file2.id)), "отказ не расходует файл")


# --- приём -----------------------------------------------------------------

func _test_receive_to_folder() -> void:
	_set_case("receive_to_folder")
	_game.start_new_run(888)
	_hd.start_hour(1)
	_hd.set_time_scale(1.0)
	_hd._next_spawn_at = 9999.0
	_game.sla = 150.0
	var registry = _game.registry
	var folder_id := _first_folder()
	var folder = registry.get_folder(folder_id)
	var files_before: int = registry.file_count()
	var cells_before: int = folder.occupied_cell_count()
	var money_before: int = _game.money
	var sla_before := float(_game.sla)
	var pid := str(_hd.spawn_packet_now("text", "tcp"))
	var expected_name := str(_hd.active_packets[pid].file_name)
	_ok(_hd.receive_packet(pid, folder_id), "пакет принят в загрузку")
	_ok(str(_hd.active_packets[pid].state) == "loading", "состояние loading")
	_eq(int(folder.reserved.size()), 1, "папка зарезервировала фигуру")
	for i in range(100):
		_hd.tick(0.1)
		if not _hd.active_packets.has(pid):
			break
	_ok(not _hd.active_packets.has(pid), "пакет ушёл из буфера после загрузки")
	_eq(registry.file_count(), files_before + 1, "файл появился в реестре")
	_ok(registry.find_by_name(expected_name) != null, "имя файла сохранено")
	var recv_fee := 1
	var data = root.get_node_or_null("Data")
	if data != null and data.get("balance") is Dictionary:
		var types = (data.balance as Dictionary).get("types", {})
		if types is Dictionary and (types as Dictionary).get("text") is Dictionary:
			recv_fee = int(((types as Dictionary)["text"] as Dictionary).get("recv_fee", 1))
	_eq(_game.money, money_before + recv_fee, "recv_fee text = +%d $" % recv_fee)
	_approx(float(_game.sla), sla_before, 0.0001, "приём не меняет SLA")
	_eq(_hd._buffer_used(), 0, "буфер освобождён")
	_eq(int(folder.reserved.size()), 0, "резерв папки снят")
	_ok(folder.occupied_cell_count() > cells_before, "клетки папки заняты файлом")

	# Заполненная папка отклоняет приём.
	_seq = 0
	while folder.free_cell_count() > 0:
		_seq += 1
		var filler = registry.create_file("fill_%d" % _seq, "text", folder_id)
		if filler == null:
			break
	_eq(folder.free_cell_count(), 0, "папка заполнена до 0 свободных клеток")
	var pid2 := str(_hd.spawn_packet_now("sound", "tcp"))
	var packets_before: int = _hd.active_packets.size()
	var money_before_full: int = _game.money
	_ok(not _hd.receive_packet(pid2, folder_id), "приём в заполненную папку отклонён")
	_ok(_hd.active_packets.has(pid2), "отклонённый пакет остался в буфере")
	_eq(_hd.active_packets.size(), packets_before, "буфер не изменился при отказе")
	_eq(_game.money, money_before_full, "при отказе деньги не меняются")
	_eq(int(folder.reserved.size()), 0, "при отказе резерв не выставлен")


# --- обработчики -----------------------------------------------------------

## Атаки в стресс-прогоне отражаются мгновенно, иначе час стоит на паузе.
func _on_show_attack_minigame(_game_node, _kind: String) -> void:
	if _hd.attack_director != null and _hd.attack_director.is_minigame_active():
		_hd.attack_director._on_minigame_finished(1.0)


func _on_show_minigame(_game_node) -> void:
	_send_minigames += 1


# --- служебное -------------------------------------------------------------

func _tick_until_packet_gone(pid: String, limit: int) -> void:
	for i in limit:
		if not _hd.active_packets.has(pid):
			return
		_hd.tick(0.1)


func _tick_until_request_gone(req_id: String, limit: int) -> void:
	for i in limit:
		if not _hd.active_requests.has(req_id):
			return
		_hd.tick(0.1)


func _first_folder() -> String:
	var section = _game.registry.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _on_hour_finished(report: Dictionary) -> void:
	_hour_events += 1
	_reports.append(report)


func _on_attack_added(_id: String) -> void:
	_attack_marks.append({"t": float(_hd.hour_elapsed), "hour": int(_hd.hour)})


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
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	if _hd != null:
		_hd.free()
		_hd = null
	_stop_audio()
	await process_frame
	await process_frame
	await process_frame
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		audio.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("test_integration: проверок %d, провалов %d, known bug %d" % [_checks, _fails, _known])
	print("PASS test_integration" if _fails == 0 else "FAIL test_integration")
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
