class_name GameController
extends Node
## Игровой контроллер без UI: связывает Game, HourDirector, Shop и SaveManager
## в законченный цикл «меню → подготовка → час → итоги часа → итоги забега».
##
## Контроллер не знает о сценах и не создаёт UI. Он тикает HourDirector вручную
## (UI вызывает tick(delta) из своего _process) и отдаёт готовые снимки данных
## через prep_data()/hour_data(). Фазы контроллера:
##   menu → prep → hour → hour_result → prep … → run_result
##
## Важно: Game.end_hour() вызывается только в next_after_hour(), чтобы UI успел
## показать отчёт часа. Если Game завершил забег сам (9-й час или SLA = 0),
## сигнал Game.run_ended переводит контроллер в run_result без дублирования.

signal phase_changed(phase: StringName)
signal prep_changed
signal hour_started(hour: int)
signal hour_finished(report: Dictionary)
signal run_finished(report: Dictionary)
signal shop_changed
signal toast(text: String)
signal show_connection(game)
signal show_minigame(game)
## Дополнительно: проброс изменения слотов (удобно для UI во время часа).
signal slot_changed

const PHASE_MENU: StringName = &"menu"
const PHASE_PREP: StringName = &"prep"
const PHASE_HOUR: StringName = &"hour"
const PHASE_HOUR_RESULT: StringName = &"hour_result"
const PHASE_RUN_RESULT: StringName = &"run_result"
const PHASE_RESULTS: StringName = &"results"

const HOURS_PER_RUN := 9
const FOLDER_CAPACITY := 16

const HOUR_DIRECTOR_SCRIPT := preload("res://scripts/core/hour_director.gd")
const SHOP_SCRIPT := preload("res://scripts/systems/shop.gd")
const SAVE_SCRIPT := preload("res://scripts/systems/save_system.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")

## menu / prep / hour / hour_result / run_result.
var phase: StringName = PHASE_MENU
## Отчёт последнего завершённого часа (из HourDirector.report()).
var current_report: Dictionary = {}
## Итог забега из _finish_run() (см. run_result()).
var last_run_result: Dictionary = {}
var paused: bool = false
var modal_open: bool = false

## Дочерний тикер часа; создаётся лениво в _bind().
var hour_director = null
var shop = null
var game = null


func _ready() -> void:
	_bind()


# --- жизненный цикл --------------------------------------------------------

func new_run(seed: int = 0) -> void:
	_bind()
	if game == null:
		return
	# Лучший счёт переживает новый забег: забираем его из старого save до сброса.
	var carried_best := _best_from_save()
	game.start_new_run(int(seed))
	if carried_best > 0:
		game.stats["best_score"] = maxi(int(game.stats.get("best_score", 0)), carried_best)
	current_report = {}
	last_run_result = {}
	paused = false
	modal_open = false
	_reset_director_state()
	_enter_prep()


func continue_run() -> bool:
	_bind()
	if game == null or not has_save():
		return false
	if not bool(game.load_game()):
		return false
	game.phase = PHASE_PREP
	current_report = {}
	last_run_result = {}
	paused = false
	modal_open = false
	_reset_director_state()
	_enter_prep()
	return true


func has_save() -> bool:
	return SAVE_SCRIPT.has_save()


func _enter_prep() -> void:
	_bind()
	phase = PHASE_PREP
	paused = false
	modal_open = false
	if game != null:
		game.phase = PHASE_PREP
		# Автосейв на входе в подготовку: прогресс не теряется между часами.
		game.save_game()
	phase_changed.emit(phase)
	prep_changed.emit()


# --- час -------------------------------------------------------------------

func start_hour() -> bool:
	_bind()
	if game == null or hour_director == null:
		return false
	# Час начинается только из подготовки (menu допустим, если Game уже в prep).
	if phase != PHASE_PREP and not (phase == PHASE_MENU and game.phase == PHASE_PREP):
		return false
	if not bool(game.start_hour()):
		return false
	hour_director.start_hour(int(game.hour))
	hour_director.set_paused(false)
	hour_director.set_modal_open(false)
	phase = PHASE_HOUR
	paused = false
	modal_open = false
	current_report = {}
	phase_changed.emit(phase)
	hour_started.emit(int(game.hour))
	return true


## Ручной тик: UI зовёт его из _process, пока контроллер в фазе hour.
func tick(delta: float) -> void:
	if phase != PHASE_HOUR or paused:
		return
	if hour_director == null:
		_bind()
	if hour_director == null:
		return
	hour_director.tick(delta)


func set_paused(value: bool) -> void:
	paused = bool(value)
	if hour_director != null:
		hour_director.set_paused(paused)


func set_modal_open(value: bool) -> void:
	modal_open = bool(value)
	if hour_director != null:
		hour_director.set_modal_open(modal_open)


## Вызывается UI после показа отчёта часа. Здесь (и только здесь) двигаем Game.
func next_after_hour() -> void:
	_bind()
	if game == null or phase != PHASE_HOUR_RESULT:
		return
	game.end_hour()
	# 9-й час: Game сам завершил забег и emit-нул run_ended — обработчик уже всё сделал.
	if phase == PHASE_RUN_RESULT:
		return
	# Страховка, если Game выставил results без сигнала.
	if game.phase == PHASE_RESULTS:
		_finish_run("victory")
		return
	_enter_prep()


# --- магазин и сохранения --------------------------------------------------

func buy(id: String) -> bool:
	_bind()
	if shop == null or game == null:
		return false
	var bought := bool(shop.buy(id))
	if bought:
		game.save_game()
		shop_changed.emit()
	return bought


func save() -> bool:
	_bind()
	if game == null:
		return false
	return bool(game.save_game())


func load() -> bool:
	_bind()
	if game == null:
		return false
	var loaded := bool(game.load_game())
	if loaded:
		shop_changed.emit()
	return loaded


# --- снимки данных для UI --------------------------------------------------

## Данные экрана подготовки. files — словарь folder_id → массив файлов;
## state: stored / attached / locked / malicious / failed (как ждёт FileGrid).
func prep_data() -> Dictionary:
	_bind()
	var sections_data: Array = []
	var files_map: Dictionary = {}
	var pending: Array = []
	var registry = game.registry if game != null else null
	if registry != null:
		for section in registry.sections.values():
			var folders_data: Array = []
			var free_slots := 0
			var capacity_total := 0
			for folder_id in section.folder_ids:
				var folder = registry.folders.get(folder_id)
				if folder == null:
					continue
				var folder_files: Array = []
				for file in registry.get_folder_files(str(folder.id)):
					folder_files.append(_file_entry(file))
				files_map[str(folder.id)] = folder_files
				capacity_total += FOLDER_CAPACITY
				free_slots += maxi(0, FOLDER_CAPACITY - folder.count() - int(folder.reserved))
				folders_data.append({
					"id": str(folder.id),
					"name": str(folder.name),
					"count": folder.count(),
					"capacity": FOLDER_CAPACITY,
				})
			sections_data.append({
				"id": str(section.id),
				"name": str(section.name),
				"free": free_slots,
				"capacity": capacity_total,
				"folders": folders_data,
			})
		for file in registry.get_pending_files():
			pending.append(_file_entry(file))
	return {
		"sections": sections_data,
		"files": files_map,
		"pending": pending,
		"money": int(game.money) if game != null else 0,
		"sla": float(game.sla) if game != null else 0.0,
		"hour": int(game.hour) if game != null else 1,
		"upgrades": game.upgrades.duplicate(true) if game != null else {},
	}


## Данные идущего часа: активные сущности + статус-бар.
func hour_data() -> Dictionary:
	_bind()
	var packets: Array = []
	var requests: Array = []
	var slots_data: Array = []
	var status := {
		"tcp_used": 0,
		"tcp_max": 0,
		"channel": 0.0,
		"channel_factor": 1.0,
		"channel_percent": 0.0,
		"sla": float(game.sla) if game != null else 0.0,
		"buffer_used": 0,
		"buffer_max": 0,
		"money": int(game.money) if game != null else 0,
		"hour": int(game.hour) if game != null else 1,
		"time_left": 0.0,
	}
	if hour_director == null:
		return {"packets": packets, "requests": requests, "slots": slots_data, "status": status}

	var packet_ids: Array = hour_director.active_packets.keys()
	packet_ids.sort_custom(func(a, b) -> bool:
		return int(hour_director.active_packets[a].order) < int(hour_director.active_packets[b].order))
	for id in packet_ids:
		var packet = hour_director.active_packets[id]
		var entry: Dictionary = packet.to_dict()
		entry["display_name"] = packet.display_name()
		entry["time_ratio"] = packet.time_ratio()
		packets.append(entry)

	for id in hour_director.active_requests.keys():
		var request = hour_director.active_requests[id]
		var req_entry: Dictionary = request.to_dict()
		req_entry["ready"] = request.is_ready()
		req_entry["time_ratio"] = request.time_ratio()
		req_entry["missing"] = request.missing_count()
		requests.append(req_entry)

	var used := 0
	var max_slots := 0
	if hour_director.slots != null:
		used = int(hour_director.slots.used_count())
		max_slots = int(hour_director.slots.max_slots())
		for slot in hour_director.slots.slots:
			slots_data.append(slot.to_dict())

	var channel_load := float(hour_director.channel_load())
	var capacity := float(ECONOMY.channel_capacity(game.upgrades if game != null else {}))
	var percent := 0.0
	if capacity > 0.0:
		percent = channel_load / capacity * 100.0

	status = {
		"tcp_used": used,
		"tcp_max": max_slots,
		"channel": channel_load,
		"channel_factor": float(hour_director.channel_factor()),
		"channel_percent": percent,
		"sla": float(game.sla) if game != null else 0.0,
		"buffer_used": int(hour_director.buffer_used()),
		"buffer_max": int(hour_director.buffer_limit()),
		"money": int(game.money) if game != null else 0,
		"hour": int(game.hour) if game != null else int(hour_director.hour),
		"time_left": float(hour_director.time_left),
	}
	return {"packets": packets, "requests": requests, "slots": slots_data, "status": status}


## Каталог магазина с текущими уровнями/ценами — для модалки магазина.
func shop_data() -> Array:
	_bind()
	var out: Array = []
	if shop == null:
		return out
	for item in shop.items():
		var id := str(item.get("id", ""))
		var item_name := str(item.get("name_ru", ""))
		if item_name.is_empty():
			item_name = str(item.get("name", id))
		out.append({
			"id": id,
			"name": item_name,
			"price": int(shop.price(id)),
			"level": int(shop.level(id)),
			"max_level": int(shop.max_level(id)),
			"can_buy": bool(shop.can_buy(id)),
		})
	return out


func run_result() -> Dictionary:
	return last_run_result.duplicate(true)


# --- обработчики -----------------------------------------------------------

func _on_hour_finished(report: Dictionary) -> void:
	# Если забег уже проигран (SLA = 0), отчёт часа не должен перетирать run_result.
	if phase == PHASE_RUN_RESULT:
		return
	current_report = report.duplicate(true)
	paused = false
	modal_open = false
	phase = PHASE_HOUR_RESULT
	phase_changed.emit(phase)
	hour_finished.emit(current_report)


func _on_game_run_ended(reason: String) -> void:
	_finish_run(str(reason))


func _on_hour_toast(text: String) -> void:
	toast.emit(text)


func _on_show_connection(game_node) -> void:
	modal_open = true
	show_connection.emit(game_node)


func _on_show_minigame(game_node) -> void:
	modal_open = true
	show_minigame.emit(game_node)


func _on_slot_changed() -> void:
	slot_changed.emit()


func _finish_run(reason: String) -> void:
	if phase == PHASE_RUN_RESULT:
		return
	_bind()
	if game == null:
		return
	phase = PHASE_RUN_RESULT
	paused = false
	modal_open = false
	game.phase = PHASE_RESULTS
	# Мета-прогресс: награды за число отработанных часов (переживают новый забег).
	var hours_done := int(game.stats.get("hours_done", 0)) if game.stats is Dictionary else 0
	# Часть наград уже выдана в end_hour — собираем их вместе с добираемыми на финише,
	# чтобы итоговый экран показал все открытия этого забега (без дублей, с сохранением порядка).
	var unlocked: Array = []
	if game.get("run_meta_awards") is Array:
		unlocked = (game.run_meta_awards as Array).duplicate()
	if game.has_method("award_meta_for_run"):
		for key in game.award_meta_for_run(hours_done):
			if not unlocked.has(key):
				unlocked.append(key)
	last_run_result = _make_run_result(str(reason))
	last_run_result["unlocked"] = unlocked.duplicate()
	last_run_result["meta_unlocks"] = (game.meta_unlocks as Dictionary).duplicate(true) \
		if game.meta_unlocks is Dictionary else {}
	# Сохраняем забег вместе с best_score (лежит в stats) и мета-открытиями.
	game.save_game()
	phase_changed.emit(phase)
	run_finished.emit(last_run_result)


# --- служебное -------------------------------------------------------------

func _bind() -> void:
	if game == null:
		game = _autoload("Game")
	if shop == null:
		shop = SHOP_SCRIPT.new()
	if hour_director == null:
		hour_director = HOUR_DIRECTOR_SCRIPT.new()
		hour_director.name = "HourDirector"
		add_child(hour_director)
		hour_director.hour_finished.connect(_on_hour_finished)
		hour_director.toast.connect(_on_hour_toast)
		hour_director.show_connection.connect(_on_show_connection)
		hour_director.show_minigame.connect(_on_show_minigame)
		hour_director.slot_changed.connect(_on_slot_changed)
	if game != null and not game.run_ended.is_connected(_on_game_run_ended):
		game.run_ended.connect(_on_game_run_ended)


## Приводит HourDirector к пустому состоянию между забегами/загрузками.
func _reset_director_state() -> void:
	if hour_director == null:
		return
	hour_director.start_hour(1)
	hour_director.running = false
	hour_director.paused = false
	hour_director.set_modal_open(false)


func _make_run_result(reason: String) -> Dictionary:
	var stats: Dictionary = game.stats if game.stats is Dictionary else {}
	var hours := int(stats.get("hours_done", 0))
	var money_earned := int(stats.get("money_earned", 0))
	var sla := float(game.sla)
	var score := int(ECONOMY.score(hours, money_earned, sla))
	var best := maxi(int(stats.get("best_score", 0)), score)
	stats["best_score"] = best
	game.stats = stats
	var won := sla > 0.0 and (reason == "victory" or hours >= HOURS_PER_RUN)
	return {
		"won": won,
		"reason": reason,
		"score": score,
		"hours": hours,
		"money": int(game.money),
		"money_earned": money_earned,
		"sla": sla,
		"best": best,
	}


func _file_entry(file) -> Dictionary:
	return {
		"id": str(file.id),
		"name": str(file.name),
		"ext": str(file.ext),
		"size_kb": int(file.size_kb),
		"type": str(file.type),
		"state": _file_state(file),
	}


## FileGrid рисует state: stored / attached / locked / malicious / failed.
func _file_state(file) -> String:
	var location := String(file.location)
	if location == "folder" or location == "registry":
		return "stored"
	return location


func _best_from_save() -> int:
	var data: Dictionary = SAVE_SCRIPT.load()
	if data.is_empty():
		return 0
	var stats = data.get("stats", null)
	if not (stats is Dictionary):
		return 0
	return maxi(0, int((stats as Dictionary).get("best_score", 0)))


func _autoload(node_name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(node_name)
	return null
