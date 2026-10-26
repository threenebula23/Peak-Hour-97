extends SceneTree
## Headless-тест GameController v2: подготовка/час/итоги, авто-возврат стола,
## блок старта часа (M4/M18), магазин 3 офферов после H1, сброс рероллов,
## полный забег на 9 часов и save/load.
##
## Запуск:
##   godot --headless --path . --script tests/test_controller.gd

const GC := preload("res://scripts/game_controller.gd")
const SM := preload("res://scripts/systems/save_system.gd")


## Минимальная заглушка мини-игры отправки: только сигнал finished.
class FakeSend:
	extends Node
	signal finished(quality: float)


## Заглушка ConnectionGame для проверки промаха: Main читает `missed`.
class FakeConnection:
	extends Node
	var missed := true


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
	_test_second_new_run_seed()
	_test_table_return_success()
	_test_table_return_block()
	_test_hour_start_and_modal()
	_test_fast_hour_and_report()
	_test_after_hour_and_shop()
	_test_buy()
	_test_reroll_reset()
	_test_full_run()
	_test_save_load()
	_test_send_modal_freeze()
	await _test_destroy_reserved_folder()
	await _test_connection_failure_toast()
	_test_continue_gate()
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


## BUG A: второй «Новый забег» должен иметь seed в подготовке, как первый.
## Регрессия: reset_for_prep() сбрасывал requests_spawned ПОСЛЕ start_hour(1),
## поэтому seed H1 создавался только в первом забеге.
func _test_second_new_run_seed() -> void:
	_set_case("second_new_run_seed")
	_c.new_run(9001)
	_eq(String(_c.phase), "prep", "забег 1: new_run → prep")
	_eq(_game.registry.files.size(), 1, "забег 1: в подготовке 1 seed-файл")
	_ok(_c.start_hour(), "забег 1: старт H1")
	var hd = _c.hour_director
	hd.set_time_scale(1.0)
	var h1_req := false
	for i in range(50):
		_c.tick(0.1)
		if not hd.active_requests.is_empty():
			h1_req = true
			break
	_ok(h1_req, "забег 1: H1 выдал запрос")
	_ok(int(hd.requests_spawned) > 0, "забег 1: requests_spawned > 0 после часа")

	_set_case("second_new_run_seed/run2")
	_c.new_run(9002)
	_eq(String(_c.phase), "prep", "забег 2: new_run → prep")
	_eq(_game.registry.files.size(), 1, "забег 2: в подготовке 1 seed-файл")
	var seed_files: Array = _game.registry.files.values()
	_ok(seed_files.size() == 1 and str(seed_files[0].required_by) == "",
		"забег 2: seed без required_by")
	_ok(hd.active_requests.is_empty(), "забег 2: нет активных запросов")
	_ok(seed_files.size() == 1 and String(seed_files[0].location) == "folder",
		"забег 2: seed лежит в папке")

	_ok(_c.start_hour(), "забег 2: старт H1")
	_eq(_game.registry.files.size(), 1, "забег 2: старт H1 не создал второй seed")
	var h1_req2 := false
	for i in range(50):
		_c.tick(0.1)
		if not hd.active_requests.is_empty():
			h1_req2 = true
			break
	_ok(h1_req2, "забег 2: H1 снова выдал запрос")


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
	_approx(float(status.get("hour_total", 0.0)), 120.0, 0.0001,
		"статус: hour_total = 120")
	var status_time := float(status.get("time_left", 0.0))
	_ok(status_time > 119.0 and status_time <= 120.0,
		"статус: time_left ≈120 после старта H1 (%.2f)" % status_time)
	_eq(int(status.get("request_limit", 0)), 2, "статус: request_limit = 2")
	_ok(int(status.get("requests_active", -1)) >= 1, "статус: есть активный запрос")
	_eq(int(status.get("attacks_active", -1)), 0, "статус: в H1 атак нет")
	_eq(int(status.get("attacks_tier", 0)), 1, "статус: attacks_tier H1 = 1")
	_eq(int(status.get("sending_count", -1)), 0, "статус: отправок нет")
	_eq(int(status.get("queued_count", -1)), 0, "статус: очередь пуста")

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
	# H1-бутстрап: к этому моменту уже есть стартовый пакет и запрос.
	_eq((hd_data.get("packets", []) as Array).size(), 2, "hour_data: 2 пакета (ботстрап + тест)")
	_eq((hd_data.get("requests", []) as Array).size(), 2, "hour_data: 2 запроса (ботстрап + тест)")
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
			"sla_delta", "files_carry", "packets_left", "requests_left",
			"hour_duration", "files_total", "files_sent", "requests_spawned",
			"requests_timed_out", "requests_rejected", "send_interval", "cells_free"]:
		_ok(_last_report.has(key), "отчёт содержит %s" % key)
	_ok(not _last_report.has("request_cap"), "отчёт без request_cap")
	_approx(float(_last_report.get("hour_duration", 0.0)), 120.0, 0.0001,
		"отчёт: hour_duration H1 = 120")
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
	# Сейв должен быть «живым» (prep, SLA>0): сейв после завершённого забега
	# больше не предлагает «Продолжить» (см. _test_continue_gate).
	_c.new_run(5150)
	_game.money = 321
	var folder_id := _first_folder_id()
	var persist = _game.registry.create_file("Сейв-файл", "text", folder_id)
	_ok(persist != null, "файл для сейва создан")
	var persist_id := str(persist.id) if persist != null else ""
	_ok(_c.save(), "save()")
	_ok(_c.has_save(), "has_save()")
	_game.money = 7
	_ok(_c.load(), "load()")
	_eq(int(_game.money), 321, "деньги восстановлены")
	_ok(_game.registry.files.has(persist_id), "load сохранил файл в реестре")
	if _game.registry.files.has(persist_id):
		var loaded = _game.registry.files[persist_id]
		_eq(str(loaded.location), "folder", "load: файл лежит в папке")
		_eq(str(loaded.required_by), "", "load: required_by пуст")
		_eq(str(loaded.attached_request), "", "load: файл не прикреплён")

	_set_case("continue_run")
	_ok(_c.can_continue(), "can_continue для живого сейва")
	_ok(_c.continue_run(), "continue_run с сейвом")
	_eq(String(_c.phase), "prep", "continue_run → prep")
	_eq(String(_game.phase), "prep", "Game.phase = prep после continue_run")
	_eq(int(_game.money), 321, "continue_run восстановил деньги")
	_ok(int(_game.hour) >= 1, "continue_run восстановил час")


## BUG 2: «Продолжить» только для незавершённого забега. Сейв с phase="results"
## (победа/итоги) или SLA=0 не должен возобновляться ни SaveManager, ни UI.
func _test_continue_gate() -> void:
	_set_case("continue_gate")
	# Живой час: продолжение разрешено.
	_c.new_run(6060)
	_ok(_c.start_hour(), "continue_gate: час запущен")
	_eq(String(_game.phase), "hour", "continue_gate: Game.phase = hour")
	_ok(float(_game.sla) > 0.0, "continue_gate: SLA > 0")
	_ok(_c.save(), "continue_gate: сейв живого часа")
	_ok(SM.can_continue(), "живой час: SaveManager.can_continue = true")
	_ok(_c.can_continue(), "живой час: controller.can_continue = true")

	# SLA 0: продолжать нечего.
	_game.sla = 0.0
	_ok(_c.save(), "continue_gate: сейв со SLA 0")
	_ok(not SM.can_continue(), "SLA 0: SaveManager.can_continue = false")
	_ok(not _c.can_continue(), "SLA 0: controller.can_continue = false")
	_ok(not _c.continue_run(), "SLA 0: continue_run = false")

	# phase="results" при живом SLA: забег завершён.
	_game.sla = 60.0
	_game.phase = "results"
	_ok(_c.save(), "continue_gate: сейв с phase=results")
	_ok(not SM.can_continue(), "results: SaveManager.can_continue = false")
	_ok(not _c.can_continue(), "results: controller.can_continue = false")
	_ok(not _c.continue_run(), "results: continue_run = false")

	# После _finish_run("sla") «Продолжить» недоступно.
	_c.new_run(7070)
	_ok(_c.start_hour(), "continue_gate: час для поражения")
	_game.sla = 0.0
	_c._finish_run("sla")
	_eq(String(_c.phase), "run_result", "_finish_run sla → run_result")
	_ok(not SM.can_continue(), "_finish_run sla: SaveManager false")
	_ok(not _c.can_continue(), "_finish_run sla: controller false")
	_ok(not _c.continue_run(), "_finish_run sla: continue_run false")

	# Победный сейв (SLA>0, phase=results) тоже не продолжается.
	_c.new_run(8080)
	_ok(_c.start_hour(), "continue_gate: час для победы")
	_game.sla = 60.0
	_c._finish_run("victory")
	_eq(String(_c.phase), "run_result", "_finish_run victory → run_result")
	_ok(bool(_c.run_result().get("won", false)), "победа помечена won")
	_ok(not SM.can_continue(), "победный сейв: SaveManager false")
	_ok(not _c.can_continue(), "победный сейв: controller false")
	_ok(not _c.continue_run(), "победный сейв: continue_run false")



## BUG 1: открытие мини-игры отправки через контроллер обязано поднять
## modal_open и в HourDirector; пакетный таймер стоит под модалкой.
func _test_send_modal_freeze() -> void:
	_set_case("send_modal_freeze")
	_c.new_run(731)
	_ok(_c.start_hour(), "старт часа для модалки отправки")
	var hd = _c.hour_director
	_c.tick(0.1)
	var packet_id := ""
	if not hd.active_packets.is_empty():
		packet_id = str(hd.active_packets.keys()[0])
	_ok(not packet_id.is_empty(), "пакет для проверки таймера есть")
	var packet = hd.get_packet(packet_id)
	var folder_id := _first_folder_id()
	var file = _game.registry.create_file("Модалка отправки", "text", folder_id)
	_ok(file != null, "файл создан")
	if file == null or packet == null:
		return
	var req_id := str(hd._create_request(1, "udp", [str(file.id)], true))
	_ok(not req_id.is_empty(), "UDP-запрос создан")
	_ok(hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	var holder := {"game": null}
	hd.send_game_factory = func(_id, _tier, _seed, _ctx):
		var g := FakeSend.new()
		holder["game"] = g
		return g
	_ok(hd.start_send(req_id), "мини-игра отправки открыта")
	_ok(bool(_c.modal_open), "controller.modal_open = true")
	_ok(bool(hd.modal_open), "director.modal_open = true (BUG 1)")
	var t_before := float(packet.time_left)
	for i in range(10):
		_c.tick(0.1)
	_approx(float(packet.time_left), t_before, 0.0001,
		"пакетный таймер заморожен под мини-игрой отправки")
	var fake = holder.get("game")
	_ok(fake != null, "подменная мини-игра создана")
	if fake != null:
		fake.finished.emit(0.8)
		await process_frame
	_ok(not bool(_c.modal_open), "controller.modal_open = false после закрытия")
	_ok(not bool(hd.modal_open), "director.modal_open = false после закрытия")
	t_before = float(packet.time_left)
	for i in range(10):
		_c.tick(0.1)
	_ok(float(packet.time_left) < t_before, "пакетный таймер снова идёт после закрытия")
	hd._cleanup_request(req_id, true)
	hd._remove_packet(packet_id)
	hd.send_game_factory = Callable()


## BUG 3c: папка, где остался только зарезервированный файл, не уничтожается
## и НЕ списывает SLA. Обычные файлы в той же папке по-прежнему удаляются.
func _test_destroy_reserved_folder() -> void:
	_set_case("destroy_reserved_folder")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_ok(false, "Main.tscn загружается")
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main._start_new_run()
	await process_frame
	var folder_id := ""
	var section = _game.registry.sections.get("C")
	if section != null and section.folder_ids.size() >= 2:
		folder_id = str(section.folder_ids[1])
	_ok(not folder_id.is_empty(), "вторая папка для теста найдена")
	if folder_id.is_empty():
		return
	var reserved = _game.registry.create_file("Резерв destroy", "text", folder_id)
	_ok(reserved != null, "зарезервированный файл создан")
	if reserved == null:
		return
	var rid := str(reserved.id)
	reserved.required_by = "req_destroy_test"
	var sla_before := float(_game.sla)
	main._destroy_folder_contents(folder_id)
	_ok(_game.registry.files.has(rid), "зарезервированный файл пережил уничтожение папки")
	_approx(float(_game.sla), sla_before, 0.001,
		"папка только из резерва: SLA не списан")
	_eq(str(_game.registry.files[rid].location), "folder",
		"зарезервированный файл не помечен malicious")

	# Контроль: обычный файл рядом — уничтожается, SLA −5.
	var normal = _game.registry.create_file("Обычный destroy", "text", folder_id)
	_ok(normal != null, "обычный файл создан")
	if normal == null:
		return
	main._destroy_folder_contents(folder_id)
	_ok(not _game.registry.files.has(str(normal.id)), "обычный файл уничтожен")
	_ok(_game.registry.files.has(rid), "резерв остался нетронутым")
	_approx(float(_game.sla), sla_before - 5.0, 0.001,
		"реальное удаление списало SLA −5")
	main.queue_free()
	await process_frame


## BUG B: неуспешное TCP-соединение даёт РОВНО один тост
## «СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО» (от HourDirector), а не два (директор + Main).
func _test_connection_failure_toast() -> void:
	_set_case("connection_failure_toast")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_ok(false, "Main.tscn загружается")
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main._start_new_run()
	await process_frame
	var director = main.controller.hour_director
	if director == null:
		_ok(false, "hour_director доступен")
		main.queue_free()
		return
	var folder_id := ""
	for section in _game.registry.sections.values():
		if not section.folder_ids.is_empty():
			folder_id = str(section.folder_ids[0])
			break
	_ok(not folder_id.is_empty(), "папка для TCP-запроса найдена")
	if folder_id.is_empty():
		main.queue_free()
		return
	main._on_start_hour()
	await process_frame
	_eq(String(main.controller.phase), "hour", "час запущен (сигналы UI подключены)")
	var file = _game.registry.create_file("conn_fail", "text", folder_id)
	_ok(file != null, "файл для TCP-запроса создан")
	if file == null:
		main.queue_free()
		return
	var rid := str(director._create_request(1, "tcp", [str(file.id)], false))
	_ok(not rid.is_empty(), "TCP-запрос создан")
	var req = director.active_requests.get(rid)
	if req == null:
		_ok(false, "TCP-запрос активен")
		main.queue_free()
		return
	req.connecting = true
	var fail_before := _count_toasts(main, "СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО")
	var sla_before := float(_game.sla)
	var fake := FakeConnection.new()
	main._on_connection_finished(false, rid, fake)
	await process_frame
	_eq(_count_toasts(main, "СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО") - fail_before, 1,
		"неуспешное соединение: ровно 1 тост (BUG B)")
	_approx(float(_game.sla), sla_before - 4.0, 0.001,
		"штраф за промах −4 SLA сохранён")

	# Успешный тост Main остаётся (директор его не дублирует).
	req.connecting = true
	var ok_before := _count_toasts(main, "СОЕДИНЕНИЕ УСТАНОВЛЕНО")
	main._on_connection_finished(true, rid, null)
	await process_frame
	_eq(_count_toasts(main, "СОЕДИНЕНИЕ УСТАНОВЛЕНО") - ok_before, 1,
		"успешное соединение: тост Main сохранён")
	director._cleanup_request(rid, true)
	main.queue_free()
	await process_frame


# --- служебное -------------------------------------------------------------

func _finish_current_hour() -> void:
	var hd = _c.hour_director
	hd.set_time_scale(60.0)
	hd.files_spawned = hd.files_budget
	hd._next_spawn_at = 999999.0
	hd.active_request_limit = 0
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


## Считает реально показанные UI-тосты Main, содержащие fragment.
func _count_toasts(main, fragment: String) -> int:
	var count := 0
	if main == null or main.toast_layer == null:
		return count
	for item in main.toast_layer._items:
		if is_instance_valid(item) and str(item.txt).contains(fragment):
			count += 1
	return count


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
