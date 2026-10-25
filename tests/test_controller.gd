extends SceneTree
## Headless-тест GameController: полный цикл prep → hour → hour_result → prep,
## магазин, 9 часов до run_result, save/load и continue_run.
## Запуск: godot --headless --path . --script tests/test_controller.gd

const GC := preload("res://scripts/game_controller.gd")
const SM := preload("res://scripts/systems/save_system.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""

var _game = null
var _c = null

var _hour_events: int = 0
var _run_events: int = 0
var _shop_events: int = 0
var _phase_events: int = 0
var _last_report: Dictionary = {}
var _last_run: Dictionary = {}

var _had_save: bool = false
var _backup: String = ""


func _init() -> void:
	_backup_save()
	if SM.has_save():
		SM.delete_save()
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_c = GC.new()
	_c.name = "GameController"
	root.add_child(_c)
	await process_frame
	_c.hour_finished.connect(_on_hour_finished)
	_c.run_finished.connect(_on_run_finished)
	_c.shop_changed.connect(_on_shop_changed)
	_c.phase_changed.connect(_on_phase_changed)

	_test_empty_continue()
	_test_new_run()
	_test_hour_start_and_modal()
	_test_fast_hour()
	_test_after_hour()
	_test_buy()
	_test_full_run()
	_test_save_load()
	_finish()


# --- кейсы -----------------------------------------------------------------

func _test_empty_continue() -> void:
	_set_case("empty_continue")
	_ok(not _c.has_save(), "сейва нет")
	_ok(not _c.continue_run(), "continue_run без сейва → false")
	_eq(String(_c.phase), "menu", "фаза осталась menu")


func _test_new_run() -> void:
	_set_case("new_run")
	_c.new_run(1)
	_eq(String(_c.phase), "prep", "new_run → prep")
	_eq(int(_game.money), 150, "стартовые деньги")
	_approx(float(_game.sla), 128.0, 0.0001, "стартовый SLA")
	_eq(int(_game.hour), 1, "час 1")
	_eq(String(_game.phase), "prep", "Game.phase = prep")
	_ok(_c.has_save(), "автосейв на входе в prep")

	var prep: Dictionary = _c.prep_data()
	_eq(int(prep.get("money", 0)), 150, "prep_data.money")
	_approx(float(prep.get("sla", 0.0)), 128.0, 0.0001, "prep_data.sla")
	_eq(int(prep.get("hour", 0)), 1, "prep_data.hour")
	_ok(prep.get("upgrades") is Dictionary, "prep_data.upgrades")

	var sections = prep.get("sections", [])
	_ok(sections is Array and not (sections as Array).is_empty(), "есть секции")
	var sec_c: Dictionary = _find_section(sections, "C")
	_ok(not sec_c.is_empty(), "есть секция C")
	if sec_c.is_empty():
		return
	var folders = sec_c.get("folders", [])
	_ok(folders is Array and not (folders as Array).is_empty(), "в C есть папка")
	if folders is Array and not (folders as Array).is_empty():
		var folder: Dictionary = folders[0]
		_eq(str(folder.get("name", "")), "Разное", "стартовая папка «Разное»")
		var folder_id := str(folder.get("id", ""))
		var files: Dictionary = prep.get("files", {})
		_ok(files.has(folder_id), "prep_data.files содержит папку")
		_ok(files.get(folder_id) is Array, "файлы папки — массив")


func _test_hour_start_and_modal() -> void:
	_set_case("hour_start")
	_ok(_c.start_hour(), "start_hour")
	_eq(String(_c.phase), "hour", "фаза hour")
	_ok(bool(_c.hour_director.running), "HourDirector.running")
	_ok(not _c.start_hour(), "повторный start_hour → false")
	_c.tick(0.1)

	var hd = _c.hour_director
	var hd_data: Dictionary = _c.hour_data()
	var status: Dictionary = hd_data.get("status", {})
	_eq(int(status.get("tcp_max", 0)), 2, "2 TCP-слота на старте")
	_eq(int(status.get("buffer_max", 0)), 4, "буфер 4 на старте")
	_eq(int(status.get("hour", 0)), 1, "статус: час 1")
	_ok(float(status.get("time_left", 0.0)) > 299.0, "статус: таймер идёт")

	# Пакет и запрос, чтобы проверить hour_data и заморозку модалкой.
	_set_case("hour_data")
	var packet_id := str(hd.spawn_packet_now("text", "tcp"))
	_ok(not packet_id.is_empty(), "пакет заспавнен")
	var folder_id := _first_folder_id()
	var file = _game.registry.create_file("Тест контроллера", "text", folder_id)
	_ok(file != null, "файл создан")
	var req_id := str(hd.spawn_request_now())
	_ok(not req_id.is_empty(), "запрос создан")
	_c.tick(0.1)
	hd_data = _c.hour_data()
	_eq((hd_data.get("packets", []) as Array).size(), 1, "hour_data: 1 пакет")
	_eq((hd_data.get("requests", []) as Array).size(), 1, "hour_data: 1 запрос")
	_eq((hd_data.get("slots", []) as Array).size(), 2, "hour_data: 2 слота")
	if not (hd_data.get("packets", []) as Array).is_empty():
		_eq(str(hd_data["packets"][0].get("id", "")), packet_id, "hour_data: id пакета")

	_set_case("modal")
	var req = hd.active_requests.get(req_id)
	_ok(req != null, "запрос в активных")
	if req == null:
		return
	var req_time := float(req.time_left)
	_c.set_modal_open(true)
	_ok(bool(hd.modal_open), "директор видит модалку")
	var packets_before: int = hd.active_packets.size()
	var accum_before: float = float(hd.spawn_recv_accum)
	for i in range(10):
		_c.tick(0.1)
	_eq(hd.active_packets.size(), packets_before, "модалка: пакеты не спавнятся")
	_approx(float(hd.spawn_recv_accum), accum_before, 0.0001, "модалка: спавн-аккумулятор стоит")
	_approx(float(req.time_left), req_time - 1.0, 0.02, "модалка: таймер запроса идёт")
	_c.set_modal_open(false)
	_ok(not hd.modal_open, "модалка закрыта")
	hd.reject_request(req_id)
	_ok(not hd.active_requests.has(req_id), "запрос убран после reject")


func _test_fast_hour() -> void:
	_set_case("fast_hour")
	_c.hour_director.set_time_scale(60.0)
	for i in range(100):
		# Изолируем переход фазы от автопотерь SLA в ускоренном прогоне.
		_game.sla = 200.0
		_c.tick(0.1)
		if String(_c.phase) != "hour":
			break
	_eq(String(_c.phase), "hour_result", "час завершён → hour_result")
	_eq(_hour_events, 1, "hour_finished эмитится один раз")
	_ok(not _last_report.is_empty(), "отчёт часа не пустой")
	_eq(int(_last_report.get("hour", 0)), 1, "в отчёте час 1")
	_ok(_last_report.has("earned"), "в отчёте есть earned")
	_ok(_last_report.has("completed"), "в отчёте есть completed")
	_ok(_last_report.has("failed"), "в отчёте есть failed")
	_ok(_last_report.has("sla_delta"), "в отчёте есть sla_delta")
	_eq(String(_game.phase), "hour", "Game.phase ещё hour до next_after_hour")
	_eq(int(_game.hour), 1, "Game.hour ещё 1 до next_after_hour")
	_ok(not _c.current_report.is_empty(), "current_report заполнен")


func _test_after_hour() -> void:
	_set_case("next_after_hour")
	_c.next_after_hour()
	_eq(String(_c.phase), "prep", "после отчёта → prep")
	_eq(String(_game.phase), "prep", "Game.phase = prep")
	_eq(int(_game.hour), 2, "следующий час = 2")
	_ok(_c.has_save(), "автосейв после часа")
	# Повторный next_after_hour в prep ничего не двигает.
	_c.next_after_hour()
	_eq(int(_game.hour), 2, "next_after_hour вне hour_result игнорируется")


func _test_buy() -> void:
	_set_case("buy")
	_game.money = 1000
	var shop_before: int = _shop_events
	_ok(_c.buy("shop_slot3"), "покупка третьего слота")
	_eq(int(_game.money), 750, "списано 250")
	_eq(int(_game.upgrades.get("slot_level", 0)), 1, "slot_level = 1")
	_eq(_shop_events, shop_before + 1, "shop_changed эмитится")
	_ok(not _c.buy("shop_slot3"), "повторная покупка → false")
	_eq(int(_game.money), 750, "деньги не списаны повторно")
	_eq((_c.shop_data() as Array).size(), 10, "shop_data: 10 позиций")


func _test_full_run() -> void:
	_set_case("full_run")
	_c.new_run(4242)
	_eq(int(_game.hour), 1, "новый забег с часа 1")
	_eq(int(_game.money), 150, "деньги нового забега")

	var hours_before: int = _hour_events
	var runs_before: int = _run_events
	for h in range(1, 10):
		_ok(_c.start_hour(), "старт часа %d" % h)
		_eq(String(_c.phase), "hour", "фаза hour в часе %d" % h)
		var hd = _c.hour_director
		hd.set_time_scale(60.0)
		# Изоляция механики контроллера: без массовых спавнов ускоренный
		# прогон не должен упираться в SLA. Атаки остаются штатными.
		hd.recv_disabled_until = 9999.0
		hd.send_disabled_until = 9999.0
		var finished := false
		for i in range(100):
			_game.sla = 200.0
			_c.tick(0.1)
			if String(_c.phase) != "hour":
				finished = true
				break
		_ok(finished, "час %d завершился" % h)
		_eq(String(_c.phase), "hour_result", "час %d: hour_result" % h)
		_c.next_after_hour()
		if h < 9:
			_eq(String(_c.phase), "prep", "час %d: prep" % h)
			_eq(int(_game.hour), h + 1, "час %d: следующий" % h)
	_eq(_hour_events - hours_before, 9, "9 отчётов часов")
	_eq(_run_events - runs_before, 1, "run_finished эмитится один раз")
	_eq(String(_c.phase), "run_result", "9-й час → run_result")
	_eq(String(_game.phase), "results", "Game.phase = results")

	var result: Dictionary = _c.run_result()
	_ok(not result.is_empty(), "run_result не пустой")
	_ok(bool(result.get("won", false)), "победа при SLA > 0")
	_eq(str(result.get("reason", "")), "victory", "reason = victory")
	_eq(int(result.get("hours", 0)), 9, "hours = 9")
	_eq(int(result.get("money_earned", -1)), 0, "money_earned без отправок = 0")
	_ok(int(result.get("score", 0)) > 0, "score > 0")
	_ok(int(result.get("best", 0)) >= int(result.get("score", 0)), "best >= score")
	_ok(not _last_run.is_empty(), "run_finished пришёл с данными")
	_eq(int(_last_run.get("score", -1)), int(result.get("score", 0)), "сигнал = run_result()")
	# Награды выданы по ходу часов, но итоговый экран должен их показать.
	var unlocked: Array = result.get("unlocked", [])
	_ok(unlocked.has("complete_run"), "unlocked: complete_run на победе")
	_ok(unlocked.has("survive_hour_3") and unlocked.has("survive_hour_5"),
		"unlocked: все награды текущего забега")
	_eq(unlocked.size(), 3, "unlocked без дублей после победы")
	_eq((_last_run.get("unlocked", []) as Array).size(), 3, "unlocked в сигнале run_finished")


func _test_save_load() -> void:
	_set_case("save_load")
	_game.money = 321
	_ok(_c.save(), "save()")
	_ok(_c.has_save(), "has_save()")
	_game.money = 7
	_ok(_c.load(), "load()")
	_eq(int(_game.money), 321, "деньги восстановлены")

	_set_case("continue_run")
	_ok(_c.continue_run(), "continue_run с сейвом")
	_eq(String(_c.phase), "prep", "continue_run → prep")
	_eq(String(_game.phase), "prep", "Game.phase = prep после continue_run")
	_eq(int(_game.money), 321, "continue_run восстановил деньги")


# --- обработчики -----------------------------------------------------------

func _on_hour_finished(report: Dictionary) -> void:
	_hour_events += 1
	_last_report = report


func _on_run_finished(report: Dictionary) -> void:
	_run_events += 1
	_last_run = report


func _on_shop_changed() -> void:
	_shop_events += 1


func _on_phase_changed(_phase: StringName) -> void:
	_phase_events += 1


# --- служебное -------------------------------------------------------------

func _first_folder_id() -> String:
	var section = _game.registry.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _find_section(sections: Array, id: String) -> Dictionary:
	for section in sections:
		if section is Dictionary and str(section.get("id", "")) == id:
			return section
	return {}


func _backup_save() -> void:
	_had_save = SM.has_save()
	if _had_save:
		_backup = FileAccess.get_file_as_string(SM.SAVE_PATH)


func _restore_save() -> void:
	if _had_save:
		var file = FileAccess.open(SM.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup)
			file.flush()
			file.close()
	else:
		SM.delete_save()
	if FileAccess.file_exists(SM.TMP_PATH):
		DirAccess.remove_absolute(SM.TMP_PATH)


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
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	_restore_save()
	print("test_controller: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_controller" if _fails == 0 else "FAIL test_controller")
	quit(0 if _fails == 0 else 1)
