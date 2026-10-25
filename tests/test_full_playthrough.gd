extends SceneTree
## Полный забег 9 часов без UI: GameController + HourDirector + автоигрок.
##
## Запуск:
##   godot --headless --path . --script tests/test_full_playthrough.gd
##
## Игрок: соединяет TCP, принимает пакеты в папки, прикрепляет required,
## отправляет запросы, отражает атаки (щит/карантин/отказ от фишинга),
## покупает апгрейды и расширяет склад. Проверяются 3 сида: 1, 42, 777.

const GC := preload("res://scripts/game_controller.gd")

const SEEDS: Array[int] = [1, 42, 777]
const MAX_ITER_PER_HOUR := 20000
const HOURS: int = 9
const BUY_ORDER: Array[String] = [
	"shop_sla",
	"shop_buffer",
	"shop_slot3",
	"shop_timer",
	"shop_channel",
	"shop_slot4",
	"shop_zone",
	"shop_search",
	"shop_shield",
]

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _game = null
var _controller = null
var _folder_seq: int = 0
var _seed_results: Array = []


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_controller = GC.new()
	root.add_child(_controller)
	await process_frame
	for seed in SEEDS:
		_run_seed(seed)
	_finish()


# --- один забег ------------------------------------------------------------

func _run_seed(seed: int) -> void:
	_set_case("seed_%d" % seed)
	_folder_seq = 0
	_controller.new_run(seed)
	_eq(str(_controller.phase), "prep", "seed %d: после new_run фаза prep" % seed)
	var hours_played := 0
	var lost_at_hour := 0
	var loss_reason := ""
	var hung_hour := 0

	for hour_index in range(1, HOURS + 1):
		if str(_controller.phase) == "run_result":
			break
		if str(_controller.phase) != "prep":
			_fail("seed %d: перед часом %d фаза %s" % [seed, hour_index, _controller.phase])
			break
		_prepare()
		_folder_seq = maxi(_folder_seq, 0)
		if not _controller.start_hour():
			_fail("seed %d: start_hour() для часа %d вернул false" % [seed, hour_index])
			break
		hours_played += 1
		var hd = _controller.hour_director
		hd.set_time_scale(16.0)
		var iterations := 0
		while str(_controller.phase) == "hour" and iterations < MAX_ITER_PER_HOUR:
			_controller.tick(0.1)
			if str(_controller.phase) != "hour":
				break
			_play_tick()
			iterations += 1
		if str(_controller.phase) == "hour":
			hung_hour = hour_index
			_fail("seed %d: час %d не завершился за %d итераций (time_left=%.2f, packets=%d, requests=%d)" % [
				seed, hour_index, MAX_ITER_PER_HOUR, float(hd.time_left),
				hd.active_packets.size(), hd.active_requests.size(),
			])
			break

		# Час завершён (hour_result) или забег проигран (run_result).
		if str(_controller.phase) == "hour_result":
			var report: Dictionary = _controller.current_report
			_eq(int(report.get("hour", 0)), hour_index, "seed %d: отчёт за час %d" % [seed, hour_index])
			_ok(report.has("earned") and report.has("completed") and report.has("failed")
				and report.has("attacks") and report.has("sla_delta"),
				"seed %d, час %d: отчёт содержит ключи" % [seed, hour_index])
			_ok(not is_nan(float(report.get("sla_delta", 0.0))), "seed %d, час %d: sla_delta не NaN" % [seed, hour_index])
			# После _finish_hour сущности уже очищены.
			_ok(hd.active_packets.is_empty(), "seed %d, час %d: нет активных пакетов после часа" % [seed, hour_index])
			_ok(hd.active_requests.is_empty(), "seed %d, час %d: нет активных запросов после часа" % [seed, hour_index])
			if hd.slots != null:
				_eq(int(hd.slots.used_count()), 0, "seed %d, час %d: слоты свободны после часа" % [seed, hour_index])
			_ok(int(report.get("packets_left", -1)) == 0, "seed %d, час %d: packets_left = 0" % [seed, hour_index])
			_ok(int(report.get("requests_left", -1)) == 0, "seed %d, час %d: requests_left = 0" % [seed, hour_index])
			_ok(int(_game.money) >= 0, "seed %d, час %d: money >= 0" % [seed, hour_index])
			_ok(not is_nan(float(_game.sla)), "seed %d, час %d: SLA не NaN" % [seed, hour_index])
			_controller.next_after_hour()
		else:
			# Поражение до конца часа (обычно SLA = 0).
			lost_at_hour = hour_index
			loss_reason = str(_controller.run_result().get("reason", "unknown"))
			_ok(false, "seed %d: забег завершён досрочно в часе %d (reason=%s, SLA=%.1f)" % [
				seed, hour_index, loss_reason, float(_game.sla),
			])

		if str(_controller.phase) == "run_result":
			break

	var result: Dictionary = _controller.run_result()
	var won := bool(result.get("won", false))
	var stats_hours := int(_game.stats.get("hours_done", 0))
	var lost_hour := lost_at_hour if lost_at_hour > 0 else (hung_hour if hung_hour > 0 else 0)
	if lost_hour == 0 and not won and hours_played >= HOURS:
		lost_hour = HOURS

	_eq(hours_played, HOURS, "seed %d: пройдено часов" % seed)
	_eq(stats_hours, HOURS, "seed %d: Game.stats.hours_done = 9" % seed)
	_ok(won, "seed %d: run_result().won = true (получено reason=%s, SLA=%.1f)" % [
		seed, str(result.get("reason", "")), float(_game.sla),
	])
	_ok(int(result.get("hours", 0)) == HOURS, "seed %d: run_result().hours = 9" % seed)
	_ok(int(_game.money) >= 0, "seed %d: money >= 0" % seed)
	_ok(float(_game.sla) > 0.0, "seed %d: SLA > 0" % seed)
	_ok(str(_controller.phase) == "run_result", "seed %d: финальная фаза run_result" % seed)

	_seed_results.append({
		"seed": seed,
		"hours": hours_played,
		"stats_hours": stats_hours,
		"won": won,
		"reason": str(result.get("reason", "")),
		"lost_hour": lost_hour,
		"money": int(_game.money),
		"earned": int(result.get("money_earned", 0)),
		"sla": float(_game.sla),
		"score": int(result.get("score", 0)),
	})


# --- действия игрока -------------------------------------------------------

func _play_tick() -> void:
	var hd = _controller.hour_director
	# 1. Атаки: сначала защита, чтобы не занести шифровальщик/мусор.
	if hd.attack_director != null:
		for attack_id in hd.attack_director.active_attacks.keys().duplicate():
			if not hd.attack_director.active_attacks.has(attack_id):
				continue
			var kind := str(hd.attack_director.active_attacks[attack_id].get("kind", ""))
			if kind == "ddos":
				hd.hold_shield(1.6)
			elif kind == "phishing":
				var request_id := str(hd.attack_director.active_attacks[attack_id].get("request_id", ""))
				if hd.active_requests.has(request_id):
					hd.reject_request(request_id)
				else:
					hd.quarantine_attack(str(attack_id))
			else:
				hd.quarantine_attack(str(attack_id))

	# 2. Пакеты: TCP сначала соединяем, затем принимаем. Пакеты-атаки
	#    обрабатываются выше (карантин), в папку их не несём.
	for packet_id in hd.active_packets.keys().duplicate():
		if not hd.active_packets.has(packet_id):
			continue
		var packet = hd.active_packets[packet_id]
		if packet.is_attack:
			continue
		var folder_id := _find_folder(hd)
		if folder_id.is_empty():
			_ensure_storage()
			folder_id = _find_folder(hd)
			if folder_id.is_empty():
				continue
		if str(packet.protocol) == "tcp" and str(packet.state) == "waiting":
			if not hd.connect_packet(str(packet_id)):
				continue
			_finish_connection(str(packet_id))
		if str(packet.state) == "connected" or str(packet.protocol) == "udp":
			hd.receive_packet(str(packet_id), folder_id)

	# 3. Запросы: прикрепить required, соединить TCP, отправить.
	for req_id in hd.active_requests.keys().duplicate():
		if not hd.active_requests.has(req_id):
			continue
		var req = hd.active_requests[req_id]
		if req.is_attack:
			# Фишинг уже обработан в блоке атак; на всякий случай не отправляем.
			if req.is_phishing():
				hd.reject_request(str(req_id))
			continue
		for file_id in req.required:
			var file = hd.registry.files.get(str(file_id))
			if file == null:
				continue
			if str(file.location) == "folder" or str(file.location) == "registry":
				if str(file.attached_request).is_empty():
					hd.attach_file(str(req_id), str(file_id))
		if str(req.protocol) == "tcp" and not bool(req.connected) and not bool(req.sending):
			if hd.connect_request(str(req_id)):
				_finish_connection(str(req_id))
		# Отправка автоматическая: udp стартует после attach, tcp — после
		# успешного соединения. Если файлы собрать не удалось — отказ.
		if not req.is_ready() and float(req.time_left) < 3.0:
			hd.reject_request(str(req_id))


func _finish_connection(entity_id: String) -> void:
	var hd = _controller.hour_director
	var node = hd._connection_games.get(entity_id)
	hd._on_connection_finished(true, entity_id)
	if node != null and is_instance_valid(node):
		node.free()


func _find_folder(hd) -> String:
	if hd.registry == null:
		return ""
	for folder in hd.registry.folders.values():
		if hd.is_folder_locked(str(folder.id)):
			continue
		if folder.has_free_slot(16):
			return str(folder.id)
	return ""


func _ensure_storage() -> void:
	var registry = _game.registry
	if registry == null:
		return
	if not _find_folder(_controller.hour_director).is_empty():
		return
	# Свободная папка в существующей секции.
	for section in registry.sections.values():
		var count := int(registry._folder_count_in_section(str(section.id)))
		if count < 12:
			_folder_seq += 1
			registry.create_folder(str(section.id), "auto_%d" % _folder_seq)
			return
	# Все секции заполнены — покупаем новую секцию (если хватает денег).
	if _controller.buy("shop_section"):
		for section in registry.sections.values():
			if int(registry._folder_count_in_section(str(section.id))) < 12:
				_folder_seq += 1
				registry.create_folder(str(section.id), "auto_%d" % _folder_seq)
				return


func _prepare() -> void:
	_ensure_storage()
	for item_id in BUY_ORDER:
		var guard := 0
		while _controller.buy(item_id) and guard < 8:
			guard += 1


# --- служебное -------------------------------------------------------------

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


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	print("")
	print("seed | часов | won  | reason    | потерян час | money | earned | SLA   | score")
	print("-----+-------+------+-----------+-------------+-------+--------+-------+------")
	for row in _seed_results:
		print("%4d | %5d | %-4s | %-9s | %11d | %5d | %6d | %5.1f | %d" % [
			int(row.get("seed", 0)),
			int(row.get("hours", 0)),
			"yes" if bool(row.get("won", false)) else "no",
			str(row.get("reason", "")),
			int(row.get("lost_hour", 0)),
			int(row.get("money", 0)),
			int(row.get("earned", 0)),
			float(row.get("sla", 0.0)),
			int(row.get("score", 0)),
		])
	print("")
	if _controller != null:
		_controller.free()
	print("test_full_playthrough: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_full_playthrough" if _fails == 0 else "FAIL test_full_playthrough")
	quit(0 if _fails == 0 else 1)
