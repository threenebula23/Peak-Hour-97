extends SceneTree
## Headless-тест интеракций экрана часа: Main.tscn ↔ GameController ↔ HourDirector (v2).
##
## Проверяет реальные обработчики main.gd:
##   • пакет: drag/drop в папку без соединения (ConnectButton удалён);
##   • запрос: attach файла, явная кнопка ОТПРАВИТЬ, модалка мини-игры,
##     пауза таймера запроса, завершение мини-игры;
##   • очередь out-слота: запрос ждёт слот, таймер стоит;
##   • отмена/таймаут запроса сохраняют файлы (расход только при успехе);
##   • отказ от запроса, переключение TCP/UDP, 5 ячеек слотов.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_interactions.gd

const MAIN_SCENE := "res://scenes/Main.tscn"
const ECONOMY := preload("res://scripts/core/economy.gd")

var _checks := 0
var _fails := 0
var _finished := false
var _main: Node = null
var _controller = null
var _director = null
var _game = null
var _folder_id := ""
var _fake_game = null


func _init() -> void:
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(_on_timeout)
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
	for i in 8:
		_ok(_game.registry.create_file("тест_%d" % i, "text", _folder_id) != null,
			"создан файл тест_%d" % i)

	_main._on_start_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")
	_eq(_main.slot_cells.size(), 5, "пять ячеек слотов")
	if _main.slot_cells.size() == 5:
		_ok(_main.slot_cells[0].state != "locked", "слот 0 доступен (база 1)")
		_eq(_main.slot_cells[4].state, "locked", "слот 5 закрыт (максимум 5)")

	await _test_packet_drop()
	await _test_attach_and_explicit_send()
	await _test_queue_pause_and_timeout()
	await _test_reject()
	_test_protocol_toggle()
	_test_prediction()
	await _test_four_slots()

	await process_frame
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


# --- сценарии ---------------------------------------------------------------

## Пакет принимается drag&drop в папку: соединения больше нет.
func _test_packet_drop() -> void:
	var pid: String = _director.spawn_packet_now("text", "tcp")
	_ok(not pid.is_empty(), "пакет для приёма заспавнен")
	if pid.is_empty():
		return
	_main._refresh_hour()
	await process_frame
	var card = _packet_card(pid)
	_ok(card != null, "карточка пакета найдена")
	if card == null:
		return
	_ok(card.get_node_or_null("ConnectButton") == null, "у пакета нет кнопки СОЕДИНИТЬСЯ")

	# Legacy-клик по пакету не открывает модалку и не занимает слот.
	_main._on_packet_connect(pid)
	_ok(_main._modal_game == null, "клик по пакету не открывает модалку")
	_eq(int(_director.slots.used_count()), 0, "клик по пакету не занимает слот")
	_eq(str(_director.active_packets[pid].state), "waiting", "пакет ждёт папку")

	var files_before: int = _game.registry.files.size()
	var buffer_before := int(_director.buffer_used())
	var payload := {
		"kind": "packet", "id": pid, "name": str(card.file_name),
		"shape_id": str(card.shape_id), "rotation": int(card.shape_rotation),
	}
	_main._on_drop_to_folder(_folder_id, payload)
	_eq(str(_director.active_packets[pid].state), "loading", "drop в папку начал загрузку")
	_eq(int(_director.slots.used_count()), 1, "загрузка занимает in-слот")
	_tick(60)
	_ok(not _director.active_packets.has(pid), "пакет ушёл из приёма после загрузки")
	_ok(_game.registry.files.size() > files_before,
		"файл появился в реестре (%d → %d)" % [files_before, _game.registry.files.size()])
	_ok(int(_director.buffer_used()) < buffer_before,
		"буфер уменьшился (%d → %d)" % [buffer_before, int(_director.buffer_used())])
	_eq(int(_director.slots.used_count()), 0, "in-слот освобождён")


## Attach не запускает отправку. ОТПРАВИТЬ открывает мини-игру, таймер стоит.
func _test_attach_and_explicit_send() -> void:
	var rid: String = _director.spawn_request_now(1)
	_ok(not rid.is_empty(), "запрос заспавнен")
	if rid.is_empty():
		return
	var req = _director.active_requests[rid]
	_eq(int(_director.request_required_count(rid)), 1, "запросу нужен 1 файл")
	var missing: Array = _director.request_missing(rid)
	_ok(missing.size() >= 1, "есть конкретный required-файл для attach")
	if missing.is_empty():
		return
	var fid := str(missing[0])

	_main._on_file_to_request(rid, 0, {"kind": "file", "id": fid, "from": "folder"})
	_eq(req.attached.size(), 1, "файл прикреплён через UI")
	_ok(req.attached.has(fid), "req.attached содержит required-файл")
	_ok(not req.sending, "attach НЕ запускает отправку")
	_ok(not req.minigame_active, "attach НЕ открывает мини-игру")
	_ok(_main._modal_game == null, "после attach модалки нет")

	_main._refresh_hour()
	await process_frame
	var card = _request_card(rid)
	_ok(card != null, "карточка запроса найдена")
	if card == null:
		return
	_ok(card.get_node_or_null("ConnectButton") == null,
		"у запроса нет legacy-кнопки ConnectButton")
	_ok(card.can_send(), "кнопка доступна после attach")
	_ok(not card.send_disabled(), "кнопка включена после attach")
	_eq(card._send_btn.caption, "СОЕДИНИТЬСЯ",
		"TCP без соединения: кнопка СОЕДИНИТЬСЯ")

	# Подменная мини-игра: реальный путь connection → show_minigame → modal_root.
	var holder := {"game": null}
	_director.send_game_factory = func(_id, _tier, _seed, _ctx):
		var g := FakeGame.new()
		holder["game"] = g
		return g
	card._send_btn.pressed.emit()
	await process_frame
	_ok(req.connecting, "нажатие запускает TCP-соединение")
	_ok(_main._modal_game != null and str(_main._modal_kind) == "connection",
		"показана модалка соединения")
	var conn_game = _main._modal_game
	_main._on_connection_finished(true, rid, conn_game)
	await process_frame
	await process_frame
	_fake_game = holder.get("game")
	_ok(req.connected, "соединение установлено")
	_ok(_fake_game != null, "мини-игра отправки создана")
	_ok(req.minigame_active, "после соединения включается мини-игра")
	_ok(_main._modal_game == _fake_game, "Main запомнил модалку мини-игры")
	if _fake_game != null:
		_ok(_fake_game.get_parent() == _main.modal_root, "мини-игра лежит в modal_root")
	_ok(bool(_controller.modal_open), "controller.modal_open = true на мини-игре")

	# Пока мини-игра открыта, таймер запроса не идёт.
	var left_before := float(req.time_left)
	_tick(10)
	_approx(float(req.time_left), left_before, 0.001,
		"таймер запроса стоит во время мини-игры")

	if _fake_game != null:
		_fake_game.finished.emit(0.8)
		await process_frame
		await process_frame
	_eq(_main._modal_game, null, "после finished модалка снята")
	_ok(not bool(_controller.modal_open), "controller.modal_open сброшен")
	_ok(not req.minigame_active, "мини-игра снята с запроса")
	_ok(req.sending or _director.is_request_queued(rid),
		"после мини-игры запрос отправляется или ждёт слот")

	# Успешная отправка: файл расходуется, деньги растут.
	var money_before := int(_game.money)
	_tick(120)
	_ok(not _director.active_requests.has(rid), "запрос закрыт после отправки")
	_ok(not _game.registry.files.has(fid), "файл израсходован при успешной отправке")
	_ok(int(_game.money) > money_before,
		"деньги выросли (%d → %d)" % [money_before, int(_game.money)])
	_director.send_game_factory = Callable()
	_fake_game = null
	holder.clear()


## Out-слот занят приёмом → запрос в очереди; таймер стоит; таймаут сохраняет файл.
func _test_queue_pause_and_timeout() -> void:
	var pid: String = _director.spawn_packet_now("text", "tcp")
	_ok(not pid.is_empty(), "пакет для занятия слота создан")
	if pid.is_empty():
		return
	_ok(_director.receive_packet(pid, _folder_id), "пакет занял in-слот")
	_eq(int(_director.slots.used_count()), 1, "in-слот занят")

	var rid: String = _director.spawn_request_now(1)
	var req = _director.active_requests.get(rid)
	_ok(req != null, "запрос для очереди создан")
	if req == null:
		return
	var missing_q: Array = _director.request_missing(rid)
	_ok(missing_q.size() >= 1, "есть required-файл для запроса в очередь")
	if missing_q.is_empty():
		return
	var fid := str(missing_q[0])
	_ok(_director.attach_file(rid, fid), "файл прикреплён к запросу очереди")
	_ok(_director.set_request_protocol(rid, "udp"),
		"запрос очереди переведён на UDP")

	var holder := {"game": null}
	_director.send_game_factory = func(_id, _tier, _seed, _ctx):
		var g := FakeGame.new()
		holder["game"] = g
		return g
	_main._on_request_send(rid)
	await process_frame
	var fake = holder.get("game")
	_ok(fake != null, "мини-игра запроса очереди создана")
	if fake != null:
		fake.finished.emit(0.8)
		await process_frame
		await process_frame
	_ok(_director.is_request_queued(rid), "запрос встал в очередь «ОЖИДАНИЕ СЛОТА»")
	_ok(not req.sending, "в очереди запрос ещё не отправляется")

	var left_before := float(req.time_left)
	_tick(10)
	_approx(float(req.time_left), left_before, 0.001,
		"таймер запроса стоит, пока он в очереди")

	# Загрузка пакета завершается → очередь получает слот.
	for i in 200:
		if not _director.active_packets.has(pid):
			break
		_tick(1)
	_ok(not _director.active_packets.has(pid), "пакет освободил слот")
	_ok(req.sending, "после освобождения слота запрос начал отправку")

	# D2: после старта отправки таймер заморожен — низкий time_left не
	# обрывает передачу, файл доходит до клиента.
	req.time_left = 0.01
	var money_send: int = _game.money
	_tick(1)
	_ok(_director.active_requests.has(rid),
		"отправка не падает по таймауту при time_left=0.01")
	_ok(req.sending, "запрос всё ещё отправляется")
	_ok(_game.registry.files.has(fid), "файл не израсходован до конца передачи")
	for i in 200:
		if not _director.active_requests.has(rid):
			break
		_tick(1)
	_ok(not _director.active_requests.has(rid), "запрос завершился успешно")
	_ok(_game.money > money_send, "выплата за отправку начислена")
	_ok(not _game.registry.files.has(fid), "файл израсходован успешной отправкой")
	_director.send_game_factory = Callable()
	_fake_game = null
	holder.clear()


## Отказ: −5 $ / −5 SLA, прикреплённый файл возвращается в папку.
func _test_reject() -> void:
	var rid: String = _director.spawn_request_now(1)
	var req = _director.active_requests.get(rid)
	_ok(req != null, "запрос для отказа создан")
	if req == null:
		return
	var missing_r: Array = _director.request_missing(rid)
	var fid := str(missing_r[0]) if not missing_r.is_empty() else ""
	if not fid.is_empty():
		_ok(_director.attach_file(rid, fid), "required-файл прикреплён перед отказом")
	var money_before := int(_game.money)
	var sla_before := float(_game.sla)
	_main._on_request_reject(rid)
	_ok(not _director.active_requests.has(rid), "отклонённый запрос исчез")
	_eq(int(_game.money), money_before - 5, "отказ: −5 $")
	_approx(float(_game.sla), sla_before - 5.0, 0.001, "отказ: −5 SLA")
	if not fid.is_empty():
		_ok(_game.registry.files.has(fid), "файл не израсходован при отказе")


func _test_protocol_toggle() -> void:
	var rid: String = _director.spawn_request_now(1)
	var req = _director.active_requests.get(rid)
	_ok(req != null, "запрос для смены протокола создан")
	if req == null:
		return
	_eq(str(req.protocol), "tcp", "по умолчанию TCP")
	_main._on_request_protocol_toggle(rid)
	_eq(str(req.protocol), "udp", "переключение на UDP")
	_main._on_request_protocol_toggle(rid)
	_eq(str(req.protocol), "tcp", "переключение обратно на TCP")
	_director.reject_request(rid)


## Предсказание RequestCard совпадает с реальным выбором Economy: сумма
## коэффициентов 1/2/4/8, 27 достижимых сумм, 3 ступени, без «wires».
func _test_prediction() -> void:
	var cases := [
		{"types": ["text"], "sum": 1, "id": "text", "tier": 1},
		{"types": ["text", "sound"], "sum": 3, "id": "dots", "tier": 1},
		{"types": ["photo"], "sum": 4, "id": "photo", "tier": 1},
		{"types": ["video"], "sum": 8, "id": "video", "tier": 1},
		{"types": ["video", "video", "video"], "sum": 24, "id": "dots", "tier": 3},
		{"types": ["video", "video", "video", "video"], "sum": 32, "id": "video", "tier": 3},
	]
	for entry in cases:
		var tc: Dictionary = entry
		var types: Array = tc["types"]
		var slots: Array = []
		for t in types:
			slots.append({"type": str(t), "attached": true})
		var card := RequestCard.new()
		root.add_child(card)
		card.setup("req_pred", "Клиент", "cli_1", "TCP", slots, 30.0, 30.0,
			0.0, slots.size())
		var p: Dictionary = card.prediction()
		var expected: Dictionary = ECONOMY.send_minigame_for(types)
		_eq(str(p.get("id", "")), str(expected.get("id", "")),
			"S=%d: id совпадает с Economy" % int(tc["sum"]))
		_eq(int(p.get("tier", 0)), int(expected.get("tier", 0)),
			"S=%d: tier совпадает с Economy" % int(tc["sum"]))
		_eq(int(p.get("sum", 0)), int(expected.get("sum", 0)),
			"S=%d: sum совпадает с Economy" % int(tc["sum"]))
		_eq(str(p.get("id", "")), str(tc["id"]), "S=%d: ожидаемая игра" % int(tc["sum"]))
		_eq(int(p.get("tier", 0)), int(tc["tier"]), "S=%d: ожидаемая ступень" % int(tc["sum"]))
		_ok(str(p.get("id", "")) != "wires", "S=%d: wires не выбирается" % int(tc["sum"]))
		card.free()


## v3: карточка держит контейнер до 4 обязательных файлов и сумму 4 text.
func _test_four_slots() -> void:
	var ids: Array = []
	for i in 4:
		var f = _game.registry.create_file("слот_%d" % i, "text", _folder_id)
		if f != null:
			ids.append(str(f.id))
	_eq(ids.size(), 4, "созданы 4 файла для контейнера")
	if ids.size() < 4:
		return
	var rid := str(_director._create_request(4, "tcp", ids, true))
	_ok(not rid.is_empty(), "запрос на 4 файла создан")
	_main._refresh_hour()
	await process_frame
	var card = _request_card(rid)
	_ok(card != null, "карточка 4-слотового запроса найдена")
	if card == null:
		_director._cleanup_request(rid, true)
		return
	_eq(card.required_count, 4, "контейнер на 4 обязательных файла")
	_eq(card.slots.size(), 4, "в карточке 4 слота")
	var expected: Dictionary = ECONOMY.send_minigame_for(["text", "text", "text", "text"])
	_eq(int(card.prediction().get("sum", -1)), int(expected.get("sum", -2)),
		"сумма 4 text = 4")
	_eq(str(card.prediction().get("id", "")), str(expected.get("id", "")),
		"игра для S=4 из Economy")
	_eq(int(card.prediction().get("tier", -1)), int(expected.get("tier", -2)),
		"ступень для S=4 из Economy")
	_eq(card.difficulty_text(), "СУММА: %d" % int(expected.get("sum", 0)),
		"подпись суммы на карточке")
	_director._cleanup_request(rid, true)


# --- хелперы ----------------------------------------------------------------

func _tick(count: int) -> void:
	for i in count:
		_controller.tick(0.1)


func _available_file() -> String:
	if _game == null or _game.registry == null:
		return ""
	for file in _game.registry.get_available_files():
		if str(file.location) == "folder" and str(file.attached_request).is_empty():
			return str(file.id)
	return ""


func _first_folder_id() -> String:
	if _game == null or _game.registry == null:
		return ""
	for section in _game.registry.sections.values():
		if not section.folder_ids.is_empty():
			return str(section.folder_ids[0])
	return ""


func _packet_card(id: String):
	for c in _main.packets:
		if c != null and is_instance_valid(c) and str(c.id) == id:
			return c
	return null


func _request_card(id: String):
	for c in _main.requests:
		if c != null and is_instance_valid(c) and str(c.id) == id:
			return c
	return null


func _on_timeout() -> void:
	if _finished:
		return
	print("FAIL: тест превысил 90 секунд")
	_finished = true
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	_stop_audio()
	await process_frame
	await process_frame
	await process_frame
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		audio.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


## Гасим AudioStreamPlayer перед выходом, чтобы не было утечки WAV.
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


func _approx(actual: float, expected: float, eps: float, message: String) -> void:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return
	_fails += 1
	print("FAIL: %s — получено %.6f, ожидалось %.6f" % [message, actual, expected])


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)


## Минимальная мини-игра для теста: сигнал finished(q) и running для Main.
class FakeGame:
	extends Node

	signal finished(quality: float)

	var running := true
	var id := "fake"
