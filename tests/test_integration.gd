extends SceneTree
## Интеграция: полный час на ускоренном времени, 9 часов подряд,
## слоты соединений и приём пакета в папку.
##
## Запуск:
##   godot --headless --path . --script tests/test_integration.gd
##
## Тест не открывает мини-игры, поэтому «игрок» не мешает автоспавну:
## проверяется именно устойчивость тикера, таймеров, слотов и атак.

const HD := preload("res://scripts/core/hour_director.gd")
const AD := preload("res://scripts/systems/attack_director.gd")

var _checks: int = 0
var _fails: int = 0
var _known: int = 0
var _case: String = ""
var _game = null
var _hd = null
var _hour_events: int = 0
var _reports: Array = []
var _attack_marks: Array = []
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
	_test_full_hour()
	_test_nine_hours()
	_test_three_tcp_slots()
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
	_game.hour = 1
	_game.phase = &"hour"
	var expected: Array[int] = [1, 1, 1, 2, 2, 3, 3, 4, 4]
	for h in range(1, 10):
		_game.sla = 200.0
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
		# Переход Game.hour через end_hour.
		_game.phase = &"hour"
		_ok(_game.end_hour(), "час %d: end_hour()" % h)
		if h < 9:
			_eq(_game.hour, h + 1, "после часа %d Game.hour = %d" % [h, h + 1])
		else:
			_eq(_game.phase, &"results", "после 9-го часа фаза results")
	_eq(int(_game.stats.get("hours_done", 0)), 9, "stats.hours_done = 9")


# --- слоты -----------------------------------------------------------------

func _test_three_tcp_slots() -> void:
	_set_case("three_tcp_slots")
	_game.start_new_run(777)
	_hd.start_hour(1)
	_hd.set_time_scale(1.0)
	_hd._recv_interval_current = 9999.0
	_hd.spawn_recv_accum = 0.0
	_eq(_hd.slots.max_slots(), 2, "на старте 2 слота")
	var p1 := str(_hd.spawn_packet_now("text", "tcp"))
	var p2 := str(_hd.spawn_packet_now("text", "tcp"))
	var p3 := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(_hd.connect_packet(p1), "пакет 1 соединяется")
	_finish_connection(p1)
	_ok(_hd.connect_packet(p2), "пакет 2 соединяется")
	_finish_connection(p2)
	_eq(_hd.slots.used_count(), 2, "оба слота заняты")
	_ok(not _hd.connect_packet(p3), "третий TCP-пакет не соединяется при 2 слотах")
	_eq(_hd.slots.used_count(), 2, "после отказа слоты не изменились")
	# Завершение первого пакета освобождает его слот.
	_hd._remove_packet(p1)
	_eq(_hd.slots.used_count(), 1, "после завершения первого пакета слот свободен")
	_ok(_hd.connect_packet(p3), "третий пакет соединяется после освобождения слота")
	_finish_connection(p3)


# --- приём -----------------------------------------------------------------

func _test_receive_to_folder() -> void:
	_set_case("receive_to_folder")
	_game.start_new_run(888)
	_hd.start_hour(1)
	_hd.set_time_scale(1.0)
	_hd._recv_interval_current = 9999.0
	_hd.spawn_recv_accum = 0.0
	_game.sla = 150.0
	var registry = _game.registry
	var folder_id := _first_folder()
	var folder = registry.get_folder(folder_id)
	var files_before: int = registry.file_count()
	var folder_before: int = folder.count()
	var money_before: int = _game.money
	var pid := str(_hd.spawn_packet_now("text", "tcp"))
	var expected_name := str(_hd.active_packets[pid].file_name)
	_ok(_hd.receive_packet(pid, folder_id), "пакет принят в загрузку")
	_ok(str(_hd.active_packets[pid].state) == "loading", "состояние loading")
	_eq(int(folder.reserved), 1, "папка зарезервировала слот")
	for i in range(100):
		_hd.tick(0.1)
		if not _hd.active_packets.has(pid):
			break
	_ok(not _hd.active_packets.has(pid), "пакет ушёл из буфера после загрузки")
	_eq(registry.file_count(), files_before + 1, "файл появился в реестре")
	_ok(registry.find_by_name(expected_name) != null, "имя файла сохранено")
	_eq(_game.money, money_before + 2, "recv_fee text = +2 $")
	_approx(float(_game.sla), 150.5, 0.0001, "приём: +0.5 SLA")
	_eq(_hd._buffer_used(), 0, "буфер освобождён")
	_eq(int(folder.reserved), 0, "резерв папки снят")
	_eq(folder.count(), folder_before + 1, "файл лежит в папке")

	# Заполненная папка отклоняет приём.
	var need: int = 16 - folder.count()
	for i in range(need):
		_seq += 1
		var filler = registry.create_file("fill_%d" % _seq, "text", folder_id)
		_ok(filler != null, "заполнение папки %d/16" % (folder.count()))
	_eq(folder.count(), 16, "папка заполнена до 16")
	var pid2 := str(_hd.spawn_packet_now("text", "tcp"))
	var packets_before: int = _hd.active_packets.size()
	var money_before_full: int = _game.money
	_ok(not _hd.receive_packet(pid2, folder_id), "приём в заполненную папку отклонён")
	_ok(_hd.active_packets.has(pid2), "отклонённый пакет остался в буфере")
	_eq(_hd.active_packets.size(), packets_before, "буфер не изменился при отказе")
	_eq(_game.money, money_before_full, "при отказе деньги не меняются")
	_eq(int(folder.reserved), 0, "при отказе резерв не выставлен")


# --- служебное -------------------------------------------------------------

func _finish_connection(entity_id: String) -> void:
	var node = _hd._connection_games.get(entity_id)
	_hd._on_connection_finished(true, entity_id)
	if node != null and is_instance_valid(node):
		node.free()


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
	print("test_integration: проверок %d, провалов %d, known bug %d" % [_checks, _fails, _known])
	print("PASS test_integration" if _fails == 0 else "FAIL test_integration")
	quit(0 if _fails == 0 else 1)
