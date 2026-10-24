extends SceneTree
## Headless-тест интеракций экрана часа: Main.tscn ↔ GameController ↔ HourDirector.
##
## Проверяет реальные обработчики main.gd:
##   • TCP-пакет: соединение через модалку ConnectionGame → приём в папку;
##   • UDP-пакет: приём без соединения;
##   • запрос: прикрепление файлов, соединение (TCP), мини-игра отправки, выплата;
##   • отказ от запроса;
##   • занятость TCP-слотов и освобождение через _on_slot_close.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_interactions.gd

const MAIN_SCENE := "res://scenes/Main.tscn"
const CONNECTION_SCRIPT := preload("res://scripts/minigames/connection_game.gd")
const MINIGAME_SCRIPT := preload("res://scripts/minigames/minigame_base.gd")

var _checks := 0
var _fails := 0
var _main: Node = null
var _controller = null
var _director = null
var _game = null
var _folder_id := ""


func _init() -> void:
	await process_frame
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("не удалось загрузить Main.tscn")
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame

	_main._start_new_run()
	await process_frame

	_game = root.get_node_or_null("Game")
	_ok(_game != null, "autoload Game доступен")
	_ok(_main.controller != null, "controller создан")
	if _game == null or _main.controller == null:
		_finish()
		return
	_controller = _main.controller
	_director = _controller.hour_director
	_ok(_director != null, "hour_director доступен")
	if _director == null:
		_finish()
		return

	_folder_id = _first_folder_id()
	_ok(not _folder_id.is_empty(), "в реестре есть папка")
	for i in 3:
		_ok(_game.registry.create_file("тест_%d" % i, "text", _folder_id) != null,
			"создан файл тест_%d" % i)

	_main._on_start_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")

	_test_tcp_packet()
	_test_udp_packet()
	_test_request_send()
	_test_reject()
	_test_slots()

	# Дать queue_free из последнего сценария отработать до выхода.
	await process_frame
	await process_frame

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


# --- сценарии ---------------------------------------------------------------

func _test_tcp_packet() -> void:
	var pid: String = _director.spawn_packet_now("text", "tcp")
	_ok(not pid.is_empty(), "TCP-пакет заспавнен")
	if pid.is_empty():
		return
	_main._refresh_hour()
	var buffer_before := int(_director.buffer_used())
	var files_before: int = _game.registry.files.size()
	_eq(str(_director.active_packets[pid].state), "waiting", "пакет ждёт соединения")

	_main._on_packet_connect(pid)
	var conn = _find_modal(CONNECTION_SCRIPT)
	_ok(conn != null, "ConnectionGame добавлен в modal_root")
	_ok(_main._modal_game == conn, "Main запомнил активную модалку")
	_eq(int(_director.slots.used_count()), 1, "TCP-слот занят соединением")

	# Пользователь прошёл полосу — директор уже обработал успех.
	_director._on_connection_finished(true, pid)
	_main._on_modal_game_finished(true, pid, conn)
	_eq(str(_director.active_packets[pid].state), "connected", "пакет соединён")
	_ok(_main._modal_game == null, "ссылка на модалку очищена")

	_main._on_drop_to_folder(_folder_id, {"kind": "packet", "id": pid, "name": "тест"})
	_ok(str(_director.active_packets[pid].state) == "loading", "пакет начал загрузку в папку")
	_tick(40)
	_ok(_game.registry.files.size() > files_before,
		"файл появился в реестре (%d → %d)" % [files_before, _game.registry.files.size()])
	_ok(int(_director.buffer_used()) < buffer_before,
		"буфер уменьшился (%d → %d)" % [buffer_before, int(_director.buffer_used())])
	_ok(not _director.active_packets.has(pid), "пакет ушёл из приёма")


func _test_udp_packet() -> void:
	var pid: String = _director.spawn_packet_now("text", "udp")
	_ok(not pid.is_empty(), "UDP-пакет заспавнен")
	if pid.is_empty():
		return
	# UDP-потеря (20%) — карточка возвращается через 1.5 с; для теста ждём сразу.
	if str(_director.active_packets[pid].state) == "lost":
		_director.active_packets[pid].state = "waiting"
	var files_before: int = _game.registry.files.size()

	_main._on_packet_connect(pid)
	_ok(_find_modal(CONNECTION_SCRIPT) == null, "для UDP модалка соединения не открывается")

	_main._on_drop_to_folder(_folder_id, {"kind": "packet", "id": pid, "name": "udp"})
	_ok(str(_director.active_packets[pid].state) == "loading", "UDP-пакет грузится без соединения")
	_tick(40)
	_ok(_game.registry.files.size() > files_before,
		"UDP-файл появился в реестре (%d → %d)" % [files_before, _game.registry.files.size()])
	_ok(not _director.active_packets.has(pid), "UDP-пакет ушёл из приёма")


func _test_request_send() -> void:
	# Свежие файлы: предыдущие принятые могут быть на cooldown/прикреплены.
	for i in 3:
		_game.registry.create_file("запрос_%d" % i, "text", _folder_id)

	var rid: String = _director.spawn_request_now()
	_ok(not rid.is_empty(), "запрос заспавнен")
	if rid.is_empty():
		return
	var req = _director.active_requests[rid]
	_ok(req.required.size() > 0, "у запроса есть required-файлы")

	# Прикрепляем каждый required-файл через UI-обработчик.
	for i in req.required.size():
		var fid := str(req.required[i])
		_main._on_file_to_request(rid, i, {"kind": "file", "id": fid})
		_ok(req.attached.has(fid), "файл %s прикреплён" % fid)
	_eq(req.attached.size(), req.required.size(), "все файлы прикреплены")

	var is_tcp := str(req.protocol).to_lower() == "tcp"
	if is_tcp:
		_main._on_request_connect(rid)
		var conn = _find_modal(CONNECTION_SCRIPT)
		_ok(conn != null, "для TCP-запроса открыта ConnectionGame")
		_ok(req.slot_reserved, "слот запроса зарезервирован")
		_director._on_connection_finished(true, rid)
		_main._on_modal_game_finished(true, rid, conn)
		_ok(req.connected, "TCP-запрос подключён")

	_main._maybe_start_send(rid)
	_ok(req.minigame_active, "мини-игра отправки активна")
	_ok(_director._minigame != null, "директор держит _minigame")
	_ok(_find_modal(MINIGAME_SCRIPT) != null, "MiniGame добавлен в modal_root")

	# Мини-игра: quality 1.0. UDP может потерять пакет и перезапустить игру.
	var guard := 0
	while req.minigame_active and guard < 10:
		guard += 1
		# Освобождаем UI-модалку до вызова директора: при UDP-перезапуске
		# директор сразу создаст новую MiniGame.
		var mg = _main._modal_game
		if mg != null:
			_main._on_modal_game_finished(null, null, mg)
		_director._on_minigame_finished(1.0)
	_ok(not req.minigame_active, "мини-игра завершена")
	_ok(req.sending, "отправка началась")

	var money_before := int(_game.money)
	var ticks := int(ceil(maxf(0.1, float(req.send_duration)) / 0.1)) + 10
	_tick(ticks)
	_ok(not _director.active_requests.has(rid), "запрос закрыт после отправки")
	_ok(req.attached.is_empty(), "attached очищен после отправки")
	_ok(int(_game.money) > money_before,
		"деньги выросли (%d → %d)" % [money_before, int(_game.money)])


func _test_reject() -> void:
	for i in 2:
		_game.registry.create_file("отказ_%d" % i, "text", _folder_id)
	var rid: String = _director.spawn_request_now()
	_ok(not rid.is_empty(), "запрос для отказа заспавнен")
	if rid.is_empty():
		return
	_main._on_request_reject(rid)
	_ok(not _director.active_requests.has(rid), "отклонённый запрос исчез")


func _test_slots() -> void:
	var ids: Array[String] = []
	for i in 3:
		var pid: String = _director.spawn_packet_now("text", "tcp")
		_ok(not pid.is_empty(), "слотовый TCP-пакет %d заспавнен" % i)
		ids.append(pid)
	if ids.size() != 3:
		return

	# Два первых соединения занимают оба базовых слота.
	for i in 2:
		_main._on_packet_connect(ids[i])
		var conn = _find_modal(CONNECTION_SCRIPT)
		_ok(conn != null, "слот %d: модалка открыта" % i)
		_director._on_connection_finished(true, ids[i])
		_main._on_modal_game_finished(true, ids[i], conn)
	_eq(int(_director.slots.used_count()), 2, "оба TCP-слота заняты")

	# Третий не должен подключиться.
	_main._on_packet_connect(ids[2])
	_eq(int(_director.slots.used_count()), 2, "третий пакет слот не занял")
	_eq(str(_director.active_packets[ids[2]].state), "waiting", "третий пакет ждёт")
	_ok(_find_modal(CONNECTION_SCRIPT) == null, "для третьего модалки нет")

	# Закрываем первый слот — третий должен подключиться.
	_main._on_slot_close(ids[0])
	_eq(int(_director.slots.used_count()), 1, "слот освобождён")
	_eq(str(_director.active_packets[ids[0]].state), "waiting", "пакет вернулся в ожидание")

	_main._on_packet_connect(ids[2])
	var conn3 = _find_modal(CONNECTION_SCRIPT)
	_ok(conn3 != null, "третий пакет подключился после освобождения слота")
	_eq(int(_director.slots.used_count()), 2, "снова заняты два слота")
	_director._on_connection_finished(true, ids[2])
	_main._on_modal_game_finished(true, ids[2], conn3)


# --- хелперы ----------------------------------------------------------------

func _tick(count: int) -> void:
	for i in count:
		_controller.tick(0.1)


func _first_folder_id() -> String:
	if _game == null or _game.registry == null:
		return ""
	for section in _game.registry.sections.values():
		if not section.folder_ids.is_empty():
			return str(section.folder_ids[0])
	return ""


func _find_modal(script) -> Node:
	if _main == null or _main.modal_root == null:
		return null
	for c in _main.modal_root.get_children():
		# Узлы, удалённые в этом же кадре (queue_free), ещё висят в дереве.
		if c.is_queued_for_deletion():
			continue
		if c.get_script() == script:
			return c
	return null


func _finish() -> void:
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_fails += 1
	print("FAIL: %s" % message)


func _eq(actual, expected, message: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_fails += 1
	print("FAIL: %s — получено %s, ожидалось %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)
