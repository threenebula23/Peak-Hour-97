extends SceneTree
## Полный забег 9 часов без UI: GameController + HourDirector + детерминированный бот.
##
## Запуск:
##   godot --headless --path . --script tests/test_full_playthrough.gd
##
## Бот v2: принимает пакеты drag&drop-эквивалентом, прикрепляет доступные файлы,
## явно жмёт start_send, сразу завершает мини-игру отправки q=0.8 и отражает
## атаки q=1.0. Проверяются сиды 1, 42, 777: 9 часов, run_result won, SLA>0,
## хотя бы одна успешная отправка, никакого soft-lock.

const GC := preload("res://scripts/game_controller.gd")

const SEEDS: Array[int] = [1, 42, 777]
const MAX_ITER_PER_HOUR := 20000
const HOURS: int = 9
const BUY_ORDER: Array[String] = [
	"lot_sla",
	"lot_channel",
	"lot_money",
	"lot_speed",
	"lot_timer",
	"lot_folder",
	"lot_slots",
	"lot_shield",
	"lot_udp",
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
	# Глобальный RNG (магазин/утилиты) тоже детерминируем по сиду забега.
	seed(int(seed))
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
		if not _controller.start_hour():
			_fail("seed %d: start_hour() для часа %d вернул false" % [seed, hour_index])
			break
		hours_played += 1
		var hd = _controller.hour_director
		hd.set_time_scale(16.0)
		# Детерминированные мини-игры: без реального ожидания и wall time.
		hd.send_game_factory = func(_id, _tier, _seed, _ctx):
			return StubGame.new()
		if hd.attack_director != null:
			hd.attack_director.create_game_override = func(_kind, _tier, _seed, _ctx):
				return StubGame.new()
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

		if str(_controller.phase) == "hour_result":
			var report: Dictionary = _controller.current_report
			_eq(int(report.get("hour", 0)), hour_index, "seed %d: отчёт за час %d" % [seed, hour_index])
			_ok(report.has("earned") and report.has("completed") and report.has("failed")
				and report.has("attacks") and report.has("sla_delta"),
				"seed %d, час %d: отчёт содержит ключи" % [seed, hour_index])
			_ok(not is_nan(float(report.get("sla_delta", 0.0))),
				"seed %d, час %d: sla_delta не NaN" % [seed, hour_index])
			_ok(hd.active_packets.is_empty(),
				"seed %d, час %d: нет активных пакетов после часа" % [seed, hour_index])
			_ok(hd.active_requests.is_empty(),
				"seed %d, час %d: нет активных запросов после часа" % [seed, hour_index])
			if hd.slots != null:
				_eq(int(hd.slots.used_count()), 0,
					"seed %d, час %d: слоты свободны после часа" % [seed, hour_index])
			_ok(int(report.get("packets_left", -1)) == 0,
				"seed %d, час %d: packets_left = 0" % [seed, hour_index])
			# requests_left — состояние ДО очистки конца часа: запрос, заспавненный
			# у cutoff, может законно дожить до финиша. Проверяем баланс.
			_ok(int(report.get("requests_left", -1)) >= 0,
				"seed %d, час %d: requests_left >= 0 (получено %s)" % [
					seed, hour_index, str(report.get("requests_left", "?"))])
			_eq(int(report.get("requests_spawned", -1)),
				int(report.get("completed", 0)) + int(report.get("requests_timed_out", 0))
					+ int(report.get("requests_rejected", 0)) + int(report.get("requests_left", 0)),
				"seed %d, час %d: reconcile requests_spawned" % [seed, hour_index])
			_ok(int(_game.money) >= 0, "seed %d, час %d: money >= 0" % [seed, hour_index])
			_ok(not is_nan(float(_game.sla)),
				"seed %d, час %d: SLA не NaN" % [seed, hour_index])
			_controller.next_after_hour()
		else:
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
	_ok(int(_game.stats.get("requests_done", 0)) > 0, "seed %d: files sent > 0" % seed)
	_ok(int(result.get("money_earned", 0)) > 0, "seed %d: earned > 0" % seed)
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


# --- действия бота ---------------------------------------------------------

func _play_tick() -> void:
	var hd = _controller.hour_director
	if hd == null:
		return

	# 1. Атака: мгновенно отражаем, иначе час стоит на паузе.
	var ad = hd.attack_director
	if ad != null and ad.is_minigame_active():
		ad._on_minigame_finished(1.0)

	# 2. Мини-игра отправки: сразу q=0.8.
	if hd.is_minigame_active():
		hd._on_send_minigame_finished(0.8)

	# 3. Запросы (v3): TCP — сначала соединение, затем контейнер и отправка.
	# Idle-соединения держат слот после успешной отправки — закрываем их, иначе
	# при одном слоте следующий запрос не сможет подключиться.
	_disconnect_idle_connections(hd)
	for req_id in hd.active_requests.keys().duplicate():
		if not hd.active_requests.has(req_id):
			continue
		var req = hd.active_requests[req_id]
		if req.sending or req.minigame_active or req.connecting or hd.is_request_queued(req_id):
			continue
		if str(req.protocol) == "tcp" and not req.has_connection():
			if not hd.connect_request(req_id):
				if float(req.time_left) < 2.0:
					hd.reject_request(req_id)
				continue
			# Бот мгновенно проходит мини-игру соединения (UI-слой не подключён).
			# Контроллер открыл модалку в _on_show_connection — закрываем её,
			# как это сделал бы экран ConnectionGame после finished.
			hd.connection_finished(req_id, true)
			_controller.set_modal_open(false)
			req = hd.active_requests.get(req_id)
			if req == null:
				continue
			if not req.has_connection():
				if float(req.time_left) < 2.0:
					hd.reject_request(req_id)
				continue
		var missing: Array = hd.request_missing(req_id)
		for fid in missing:
			if not hd.attach_file(req_id, str(fid)):
				break
		if hd.request_missing(req_id).is_empty():
			if hd.start_send(req_id):
				if hd.is_minigame_active():
					hd._on_send_minigame_finished(0.8)
		elif float(req.time_left) < 2.0:
			hd.reject_request(req_id)

	# 4. Пакеты: принимаем в первую подходящую папку (или создаём новую).
	# Слот общий с TCP-соединениями, поэтому приём идёт после запросов: иначе
	# поток пакетов навсегда занимает единственный слот и соединение не встаёт.
	for packet_id in hd.active_packets.keys().duplicate():
		if not hd.active_packets.has(packet_id):
			continue
		var packet = hd.active_packets[packet_id]
		if str(packet.state) != "waiting":
			continue
		_try_receive(hd, str(packet_id))


## Соединения без активного запроса (после успешной отправки) занимают слот.
func _disconnect_idle_connections(hd) -> void:
	if hd == null:
		return
	for conn_id in hd.active_connections.keys().duplicate():
		var conn = hd.active_connections.get(conn_id)
		if conn == null:
			continue
		if not conn.has_request() or not hd.active_requests.has(str(conn.request_id)):
			hd.disconnect_connection(str(conn_id))


func _try_receive(hd, packet_id: String) -> bool:
	var registry = hd.registry
	if registry == null:
		return false
	for folder in registry.folders.values():
		if hd.is_folder_locked(str(folder.id)):
			continue
		if hd.receive_packet(packet_id, str(folder.id)):
			return true
	# Ни одна папка не подошла по фигуре — расширяем склад.
	for section in registry.sections.values():
		var count := int(registry._folder_count_in_section(str(section.id)))
		if count >= 12:
			continue
		_folder_seq += 1
		var folder = registry.create_folder(str(section.id), "auto_%d" % _folder_seq)
		if folder != null:
			return hd.receive_packet(packet_id, str(folder.id))
	return false


func _available_file(hd) -> String:
	if hd.registry == null:
		return ""
	for file in hd.registry.get_available_files():
		if str(file.location) == "folder" and str(file.attached_request).is_empty():
			return str(file.id)
	return ""


func _prepare() -> void:
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
		_controller = null
	_stop_audio()
	await process_frame
	await process_frame
	await process_frame
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		audio.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("test_full_playthrough: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_full_playthrough" if _fails == 0 else "FAIL test_full_playthrough")
	quit(0 if _fails == 0 else 1)


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


## Мини-игра-заглушка: соединение finished есть, но игра сама не тикает.
class StubGame:
	extends Node

	signal finished(quality: float)

	var running := true
	var id := "stub"
