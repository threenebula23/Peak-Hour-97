extends SceneTree
## Headless-тест GameController v2: подготовка/час/итоги, авто-возврат стола,
## блок старта часа (M4/M18), магазин 3 офферов после H1, сброс рероллов,
## полный забег на 9 часов и save/load.
##
## Запуск:
##   godot --headless --path . --script tests/test_controller.gd

const GC := preload("res://scripts/game_controller.gd")
const SM := preload("res://scripts/systems/save_system.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""

var _game = null
var _c = null
var _name_seq: int = 0

var _hour_events: int = 0
var _run_events: int = 0
var _shop_events: int = 0
var _phase_events: int = 0
var _last_report: Dictionary = {}
var _last_run: Dictionary = {}
var _phases: Array = []
var _toasts: Array = []

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
	_c.name = "GameControllerTest"
	root.add_child(_c)
	await process_frame
	_c.hour_finished.connect(_on_hour_finished)
	_c.run_finished.connect(_on_run_finished)
	_c.shop_changed.connect(_on_shop_changed)
	_c.phase_changed.connect(_on_phase_changed)
	_c.toast.connect(_on_toast)

	_test_empty_continue()
	_test_new_run()
	_test_table_return_success()
	_test_table_return_block()
	_test_hour_start_and_modal()
	_test_fast_hour_and_report()
	_test_after_hour_and_shop()
	_test_buy()
	_test_reroll_reset()
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
	_eq(int(_game.money), 50, "стартовые деньги 50 $")
	_approx(float(_game.sla), 60.0, 0.0001, "стартовый SLA 60")
	_eq(int(_game.hour), 1, "час 1")
	_eq(String(_game.phase), "prep", "Game.phase = prep")
	_ok(_c.has_save(), "автосейв на входе в prep")
	_eq(_game.shop_offers.size(), 0, "H1: магазина/офферов нет")
	_eq((_c.shop_data() as Array).size(), 0, "H1: shop_data пуст")

	var prep: Dictionary = _c.prep_data()
	_eq(int(prep.get("money", 0)), 50, "prep_data.money")
	_approx(float(prep.get("sla", 0.0)), 60.0, 0.0001, "prep_data.sla")
	_eq(int(prep.get("hour", 0)), 1, "prep_data.hour")
	var sections = prep.get("sections", [])
	_ok(sections is Array and not (sections as Array).is_empty(), "есть секции")


func _test_table_return_success() -> void:
	_set_case("table_return_ok")
	_c.new_run(11)
	var folder_id := _first_folder_id()
	var file = _game.registry.create_file("Стол-ок", "text", folder_id)
	_ok(file != null, "файл создан")
	if file == null:
		return
	_ok(_game.registry.move_file_to_table(str(file.id)), "файл убран на стол")
	_ok(_c.start_hour(), "старт часа разрешён")
	_eq(String(_c.phase), "hour", "фаза hour")
	_eq(str(file.location), "folder", "файл автоматически вернулся в папку")
	_eq(_game.registry.table_file_count(), 0, "стол пуст")


func _test_table_return_block() -> void:
	_set_case("table_return_block")
	_c.new_run(12)
	var folder_id := _first_folder_id()
	var file = _game.registry.create_file("Стол-блок", "text", folder_id)
	_ok(file != null, "файл создан")
	if file == null:
		return
	_ok(_game.registry.move_file_to_table(str(file.id)), "файл убран на стол")
	# Забиваем все папки до отказа.
	for raw_folder_id in _game.registry.folders.keys():
		_fill_folder(str(raw_folder_id))
	_eq(_game.registry.table_file_count(), 1, "на столе остался 1 файл")
	_toasts.clear()
	var started: bool = bool(_c.start_hour())
	_ok(not started, "старт часа заблокирован (M4/M18)")
	_eq(String(_c.phase), "prep", "фаза осталась prep")
	_eq(String(_game.phase), "prep", "Game.phase остался prep")
	_eq(int(_game.hour), 1, "час не сдвинулся")
	_ok(_has_toast("На столе остались файлы"), "тост о блоке старта")
	_eq(_game.registry.table_file_count(), 1, "файл не потерян")


func _test_hour_start_and_modal() -> void:
	_set_case("hour_start")
	_c.new_run(21)
	_ok(_c.start_hour(), "start_hour")
	_eq(String(_c.phase), "hour", "фаза hour")
	_ok(bool(_c.hour_director.running), "HourDirector.running")
	_ok(not _c.start_hour(), "повторный start_hour → false")
	_c.tick(0.1)

	var hd = _c.hour_director
	var status: Dictionary = _c.hour_data().get("status", {})
	_eq(int(status.get("tcp_max", 0)), 1, "1 слот на старте")
	_eq(int(status.get("buffer_max", 0)), 6, "буфер 6 на старте")
	_eq(int(status.get("hour", 0)), 1, "статус: час 1")
	_ok(float(status.get("time_left", 0.0)) > 299.0, "статус: таймер идёт")

	_set_case("hour_data_modal")
	var folder_id := _first_folder_id()
	var file = _game.registry.create_file("Тест контроллера", "text", folder_id)
	_ok(file != null, "файл создан")
	var req_id := str(hd.spawn_request_now(1))
	_ok(not req_id.is_empty(), "запрос создан")
	var packet_id := str(hd.spawn_packet_now("text"))
	_ok(not packet_id.is_empty(), "пакет создан")
	_c.tick(0.1)
	var hd_data: Dictionary = _c.hour_data()
	_eq((hd_data.get("packets", []) as Array).size(), 1, "hour_data: 1 пакет")
	_eq((hd_data.get("requests", []) as Array).size(), 1, "hour_data: 1 запрос")
	var req_data: Dictionary = (hd_data.get("requests", []) as Array)[0]
	_eq(int(req_data.get("required_count", 0)), 1, "hour_data: required_count")
	_eq(int(req_data.get("missing", -1)), 1, "hour_data: missing = 1")

	var req = hd.active_requests.get(req_id)
	var packet = hd.active_packets.get(packet_id)
	var req_time := float(req.time_left)
	var packet_time := float(packet.time_left)
	_c.set_modal_open(true)
	_ok(bool(hd.modal_open), "директор видит модалку")
	for i in range(10):
		_c.tick(0.1)
	_approx(float(req.time_left), req_time - 1.0, 0.02, "модалка: таймер запроса идёт")
	_approx(float(packet.time_left), packet_time, 0.0001, "модалка: таймер пакета стоит")
	_c.set_modal_open(false)
	_ok(not hd.modal_open, "модалка закрыта")
	hd._cleanup_request(req_id, true)
	hd._remove_packet(packet_id)


func _test_fast_hour_and_report() -> void:
	_set_case("fast_hour")
	_finish_current_hour()
	_eq(String(_c.phase), "hour_result", "час завершён → hour_result")
	_eq(_hour_events, 1, "hour_finished один раз")
	_ok(not _last_report.is_empty(), "отчёт часа не пустой")
	_eq(int(_last_report.get("hour", 0)), 1, "в отчёте час 1")
	for key in ["earned", "completed", "failed", "attacks", "attacks_failed",
			"sla_delta", "files_carry", "packets_left", "requests_left"]:
		_ok(_last_report.has(key), "отчёт содержит %s" % key)
	_eq(String(_game.phase), "hour", "Game.phase ещё hour до next_after_hour")
	_eq(int(_game.hour), 1, "Game.hour ещё 1 до next_after_hour")


func _test_after_hour_and_shop() -> void:
	_set_case("next_after_hour")
	_shop_events = 0
	_c.next_after_hour()
	_eq(String(_c.phase), "prep", "после отчёта → prep")
	_eq(String(_game.phase), "prep", "Game.phase = prep")
	_eq(int(_game.hour), 2, "следующий час = 2")
	_ok(_c.has_save(), "автосейв после часа")
	_ok(_shop_events > 0, "shop_changed при генерации офферов")

	_set_case("shop_after_h1")
	_eq(_game.shop_offer_hour, 2, "офферы сгенерированы для H2")
	_eq(_game.shop_rerolls, 0, "рероллы сброшены")
	_eq(_game.shop_offers.size(), 3, "ровно 3 оффера")
	var unique: Dictionary = {}
	for id in _game.shop_offers:
		unique[str(id)] = true
	_eq(unique.size(), 3, "офферы без дублей")
	var shop_data: Array = _c.shop_data()
	_eq(shop_data.size(), 3, "shop_data: 3 текущих предложения")
	for entry in shop_data:
		_ok(not str(entry.get("name", "")).is_empty(), "у оффера есть имя")
		_ok(int(entry.get("price", -1)) >= 0, "у оффера есть цена")
		_ok(int(entry.get("level", -1)) >= 0, "у оффера есть уровень")
	_eq(int(_last_report.get("hour", 0)), 1, "отчёт всё ещё за час 1")


func _test_buy() -> void:
	_set_case("buy")
	_game.money = 1000
	_c.shop.refresh(2, int(_game.money), true)
	var offers: Array = _c.shop_data()
	_ok(offers.size() == 3, "3 предложения для покупки")
	if offers.is_empty():
		return
	var entry: Dictionary = offers[0]
	var id := str(entry.get("id", ""))
	var price := int(entry.get("price", 0))
	var level_before := int(entry.get("level", 0))
	_shop_events = 0
	_ok(_c.buy(id), "покупка оффера")
	_eq(int(_game.money), 1000 - price, "деньги списаны по цене")
	_eq(int(_c.shop.level(id)), level_before + 1, "уровень лота +1")
	_ok(_shop_events > 0, "shop_changed после покупки")
	_eq((_c.shop_data() as Array).size(), 3, "3 предложения остаются в магазине")


func _test_reroll_reset() -> void:
	_set_case("reroll_reset")
	_game.shop_rerolls = 2
	_ok(_c.start_hour(), "старт часа 2")
	_finish_current_hour()
	_c.next_after_hour()
	_eq(String(_c.phase), "prep", "H3 prep")
	_eq(int(_game.hour), 3, "час 3")
	_eq(int(_game.shop_rerolls), 0, "рероллы сброшены после часа")
	_eq(int(_game.shop_offer_hour), 3, "офферы перегенерированы для H3")
	_eq(_game.shop_offers.size(), 3, "3 оффера на H3")


func _test_full_run() -> void:
	_set_case("full_run")
	_c.new_run(4242)
	_eq(int(_game.hour), 1, "новый забег с часа 1")
	_eq(int(_game.money), 50, "деньги нового забега")
	var hours_before: int = _hour_events
	var runs_before: int = _run_events
	for h in range(1, 10):
		_ok(_c.start_hour(), "старт часа %d" % h)
		_eq(String(_c.phase), "hour", "фаза hour в часе %d" % h)
		_finish_current_hour()
		_eq(String(_c.phase), "hour_result", "час %d: hour_result" % h)
		_c.next_after_hour()
		if h < 9:
			_eq(String(_c.phase), "prep", "час %d: prep" % h)
			_eq(int(_game.hour), h + 1, "час %d: следующий" % h)
			_eq(_game.shop_offer_hour, h + 1, "час %d: офферы для H%d" % [h, h + 1])
			_eq(_game.shop_offers.size(), 3, "час %d: 3 оффера" % h)
	_eq(_hour_events - hours_before, 9, "9 отчётов часов")
	_eq(_run_events - runs_before, 1, "run_finished один раз")
	_eq(String(_c.phase), "run_result", "9-й час → run_result")
	_eq(String(_game.phase), "results", "Game.phase = results")
	var result: Dictionary = _c.run_result()
	_ok(not result.is_empty(), "run_result не пустой")
	_ok(bool(result.get("won", false)), "победа при SLA > 0")
	_eq(str(result.get("reason", "")), "victory", "reason = victory")
	_eq(int(result.get("hours", 0)), 9, "hours = 9")
	_ok(int(result.get("score", 0)) > 0, "score > 0")
	_ok(int(result.get("money_earned", -1)) == 0, "money_earned без отправок = 0")


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
	_ok(int(_game.hour) >= 1, "continue_run восстановил час")


# --- служебное -------------------------------------------------------------

func _finish_current_hour() -> void:
	var hd = _c.hour_director
	hd.set_time_scale(60.0)
	hd.files_spawned = hd.files_budget
	hd.requests_spawned = hd.request_cap
	hd.spawn_recv_accum = 0.0
	hd.spawn_send_accum = 0.0
	if hd.attack_director != null:
		hd.attack_director._schedule.clear()
		hd.attack_director._next_index = 0
	for i in range(200):
		_game.sla = 200.0
		_c.tick(0.1)
		if String(_c.phase) != "hour":
			return


func _first_folder_id() -> String:
	var section = _game.registry.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _fill_folder(folder_id: String) -> void:
	var guard := 0
	while guard < 100:
		guard += 1
		_name_seq += 1
		var f = _game.registry.create_file("Заполнение %d" % _name_seq, "text", folder_id)
		if f == null:
			return


func _has_toast(fragment: String) -> bool:
	for text in _toasts:
		if str(text).contains(fragment):
			return true
	return false


# --- обработчики -----------------------------------------------------------

func _on_hour_finished(report: Dictionary) -> void:
	_hour_events += 1
	_last_report = report


func _on_run_finished(report: Dictionary) -> void:
	_run_events += 1
	_last_run = report


func _on_shop_changed() -> void:
	_shop_events += 1


func _on_phase_changed(phase: StringName) -> void:
	_phase_events += 1
	_phases.append(String(phase))


func _on_toast(text: String) -> void:
	_toasts.append(text)


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
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, float(actual), float(expected)])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	_restore_save()
	print("test_controller: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_controller" if _fails == 0 else "FAIL test_controller")
	quit(0 if _fails == 0 else 1)
