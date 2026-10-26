extends SceneTree
## Headless-тест экрана часа Main.tscn ↔ GameController ↔ HourDirector (v2).
##
## Проверяет: окна ПРИЁМ/ОТПРАВКА, 5 ячеек слотов (база 1), превью фигуры
## пакета, прикрепление/отправку запроса, предсказание мини-игры, TCP/UDP,
## канал load/capacity, отсутствие карточек/оверлеев атак и магазин после H1.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_hour.gd

const MG := preload("res://scripts/minigames/minigame_base.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")
const SM := preload("res://scripts/systems/save_system.gd")

var _checks := 0
var _fails := 0
var _finished := false
var _fake_game = null


func _init() -> void:
	# Страховка от зависания: тест обязан завершиться за 60 секунд.
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(_on_timeout)
	await process_frame
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("не удалось загрузить Main.tscn")
		_finish()
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame

	main._start_new_run()
	await process_frame

	var game = root.get_node_or_null("Game")
	_ok(game != null, "autoload Game доступен")
	if game == null or main.controller == null:
		_finish()
		return

	# Реестр нового забега пуст — создаём файлы, из которых спавнятся запросы.
	var folder_id := ""
	for section in game.registry.sections.values():
		if not section.folder_ids.is_empty():
			folder_id = str(section.folder_ids[0])
			break
	_ok(folder_id != "", "в реестре есть папка для файлов")
	var file_ids: Array = []
	for i in 4:
		var f = game.registry.create_file("тест_%d" % i, "text", folder_id)
		_ok(f != null, "файл тест_%d создан" % i)
		if f != null:
			file_ids.append(str(f.id))

	main._on_start_hour()
	await process_frame
	_eq(main.controller.phase, &"hour", "фаза контроллера — hour")
	_ok(main._shop_btn != null and not main._shop_btn.visible,
		"магазин скрыт во время часа")
	_ok(main._start_btn != null and not main._start_btn.visible,
		"кнопка НАЧАТЬ ЧАС скрыта во время часа")
	_ok(main.receive_window.visible, "окно ПРИЁМ видно в час")
	_ok(main.send_window.visible, "окно ОТПРАВКА видно в час")
	_ok(main.sorting_table != null and not main.sorting_table.visible,
		"стол сортировки скрыт в час")

	var director = main.controller.hour_director
	_ok(director != null, "hour_director доступен")

	# --- Стартовые статы H1 --------------------------------------------------
	_eq(str(main.status_bar.get_metric("sla").get("value", "")), "60 / 60",
		"статус SLA — 60 / 60")
	_eq(str(main.status_bar.get_metric("tcp").get("value", "")), "0 / 1",
		"статус слотов — 0 / 1")
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "0/10",
		"статус канала — load/capacity 0/10")
	# H1: первый пакет спавнится в t=0, поэтому буфер сверяем с директором.
	_eq(str(main.status_bar.get_metric("buffer").get("value", "")),
		"%d / %d" % [director.active_packets.size(), director.buffer_limit()],
		"статус буфера — занято/лимит")

	# --- Пакет: карточка с фигурой и клетками --------------------------------
	var pid: String = director.spawn_packet_now("sound", "tcp")
	_ok(not pid.is_empty(), "пакет создан")
	var rid: String = director.spawn_request_now(1)
	_ok(not rid.is_empty(), "запрос на 1 файл создан")
	main._refresh_hour()
	await process_frame

	_ok(main.packets.size() > 0, "карточки пакетов созданы (%d)" % main.packets.size())
	_ok(main.requests.size() > 0, "карточки запросов созданы (%d)" % main.requests.size())
	_eq(main.slot_cells.size(), 5, "пять ячеек слотов")
	if main.slot_cells.size() == 5:
		_ok(main.slot_cells[0].state != "locked", "слот 0 доступен (база 1)")
		_eq(main.slot_cells[4].state, "locked", "слот 5 закрыт (максимум 5)")
	# v3: счётчик слотов — logo()-шрифт, 10 px.
	_ok(main.slot_count_label != null, "счётчик слотов создан")
	if main.slot_count_label != null:
		_eq(main.slot_count_label.get_theme_font("font"), Theme90.logo(),
			"счётчик слотов: шрифт logo()")
		_eq(int(main.slot_count_label.get_theme_font_size("font_size")), 10,
			"счётчик слотов: кегль 10 px")
	var pcard = _packet_card(main, pid)
	_ok(pcard != null, "карточка пакета найдена")
	var pkt = director.active_packets.get(pid)
	_ok(pkt != null, "пакет есть в директоре")
	if pkt != null and pcard != null:
		_eq(float(pkt.timer_total), 20.0,
			"таймер пакета H1 = 20 с (%.1f)" % float(pkt.timer_total))
		_eq(str(pcard.shape_id), str(pkt.shape_id), "карточка показывает shape_id пакета")
		_ok(pcard.cells_count() >= 2, "звук занимает минимум 2 клетки")
		_ok(pcard.cells_text().begins_with("ЗАЙМЁТ"),
			"карточка пакета: %s" % pcard.cells_text())
		_ok(pcard.get("is_attack") == null, "в карточке пакета нет атаки")
	var req0 = director.active_requests.get(rid)
	if req0 != null:
		_eq(float(req0.timer_total), 30.0,
			"таймер запроса H1 = 30 с (%.1f)" % float(req0.timer_total))

	# --- Запрос: ОТПРАВИТЬ всегда кликабельна, TCP ждёт соединения ----------
	var card = _request_card(main, rid)
	_ok(card != null, "карточка запроса найдена")
	if card == null:
		_finish()
		return
	_eq(card.required_count, 1, "запросу нужен 1 файл")
	_eq(card.attached_count(), 0, "прикреплено 0 файлов")
	_ok(card.can_send(), "ОТПРАВИТЬ доступна без файлов (backend даст тост)")
	_ok(not card.send_disabled(), "кнопка ОТПРАВИТЬ не заблокирована без файлов")
	_eq(card._send_btn.caption, "ОТПРАВИТЬ", "caption ОТПРАВИТЬ постоянный")
	_eq(card._send_btn.position, Vector2(8, 104), "ОТПРАВИТЬ: позиция 8,104")
	_eq(card._send_btn.size, Vector2(92, 18), "ОТПРАВИТЬ: размер 92×18")
	_eq(card._reject_btn.position, Vector2(104, 104), "ОТКЛОНИТЬ: позиция 104,104")
	_eq(card._reject_btn.size, Vector2(90, 18), "ОТКЛОНИТЬ: размер 90×18")
	_ok(not _card_has_caption(card, "ОТКРЕПИТЬ"), "кнопки ОТКРЕПИТЬ в карточке нет")
	_ok(card._connect_btn.visible, "TCP: кнопка ПОДКЛЮЧИТЬСЯ видна")
	_eq(card._connect_btn.position, Vector2(292, 104), "ПОДКЛЮЧИТЬСЯ: позиция 292,104")
	_eq(card._connect_btn.size, Vector2(100, 18), "ПОДКЛЮЧИТЬСЯ: размер 100×18")
	_eq(card._connect_btn.caption, "ПОДКЛЮЧИТЬСЯ",
		"TCP без соединения: caption ПОДКЛЮЧИТЬСЯ")
	_ok(not card._connect_btn.disabled, "ПОДКЛЮЧИТЬСЯ доступна без соединения")
	_ok(not card._connect_disabled(), "connect не заблокирован без соединения")
	# TCP без соединения не принимает файлы (drop-гейт карточки).
	_ok(not card._can_drop_data(Vector2(10, 30), {"kind": "file", "id": "x"}),
		"TCP без соединения: drop файла отклонён")
	_eq(card._drop_slot, -1, "TCP без соединения: слот drop не подсвечен")
	# ОТПРАВИТЬ кликабельна: эмитит сигнал, backend показывает короткий тост.
	var sent_ids: Array = []
	card.send_pressed.connect(func(sid: String) -> void: sent_ids.append(sid))
	card._send_btn.pressed.emit()
	await process_frame
	_eq(sent_ids, [rid], "ОТПРАВИТЬ эмитит send_pressed(id)")
	_ok(main._modal_game == null, "без соединения модалка не открылась")
	# Debugger убрал дубль Main: остаётся один точный тост backend.
	_eq(_last_toast(main), "СНАЧАЛА УСТАНОВИТЕ СОЕДИНЕНИЕ",
		"send без соединения: один точный тост backend")
	_eq(card.attached_count(), 0, "файл не появился сам")
	_ok(card.minigame_text().contains("МИНИ-ИГРА"),
		"прогноз мини-игры виден до прикрепления: %s" % card.minigame_text())
	_ok(not card.minigame_text().contains("—"),
		"прогноз считается по типам required-файлов")
	var pred_expected: Dictionary = ECONOMY.send_minigame_for(req0.required_types)
	_eq(int(card.prediction().get("sum", -1)), int(pred_expected.get("sum", -2)),
		"прогноз: сумма коэффициентов")
	_eq(str(card.prediction().get("id", "")), str(pred_expected.get("id", "")),
		"прогноз: игра из Economy")
	_eq(int(card.prediction().get("tier", -1)), int(pred_expected.get("tier", -2)),
		"прогноз: ступень из Economy")
	_eq(card.protocol, "TCP", "протокол по умолчанию TCP")

	# --- Раскладка v3: карточка 400×128, скролл вмещает 4 запроса ------------
	var content: Control = main.send_window.content
	_eq(int(content.size.y), 252, "контент ОТПРАВКИ: высота 252 px")
	_eq(card.size, Vector2(400, 128), "RequestCard v3: 400×128")
	_ok(card.position.y + 24.0 <= content.size.y + 0.5,
		"карточка %s: заголовок/таймер в клипе" % str(card.name))
	main._sync_send_scroll(4)
	_ok(main._send_bar != null and main._send_bar.visible,
		"при 4 запросах в ОТПРАВКЕ появляется скролл")
	_ok(main._send_bar != null and main._send_bar._limit() > 0.0,
		"скролл позволяет показать все 4 карточки")
	main._sync_send_scroll(main.requests.size())
	main._send_scroll = 0.0
	main._layout_request_cards(main.requests.size())

	# --- TCP/UDP: UDP не требует соединения и не имеет connect-кнопки --------
	main._on_request_protocol_toggle(rid)
	await process_frame
	main._refresh_hour()
	_eq(str(director.active_requests[rid].protocol), "udp", "протокол переключён на UDP")
	_eq(card.protocol, "UDP", "карточка показывает UDP")
	_ok(not card._connect_btn.visible, "UDP: кнопки ПОДКЛЮЧИТЬСЯ нет")
	_ok(card._can_drop_data(Vector2(10, 30), {"kind": "file", "id": "x"}),
		"UDP: drop файла разрешён без соединения")
	main._on_request_protocol_toggle(rid)
	await process_frame
	main._refresh_hour()
	_eq(str(director.active_requests[rid].protocol), "tcp", "протокол вернулся на TCP")

	# --- TCP без соединения: attach и drop отклонены -------------------------
	var missing: Array = director.request_missing(rid)
	_ok(missing.size() == 1, "у запроса есть конкретный required-файл")
	if missing.is_empty():
		_finish()
		return
	var attach_id := str(missing[0])
	_ok(not director.attach_file(rid, attach_id),
		"TCP без соединения: backend не прикрепляет файл")
	_eq(card.attached_count(), 0, "до соединения карточка показывает 0/1")

	# --- TCP: ПОДКЛЮЧИТЬСЯ -> ConnectionGame -> слот соединения -------------
	card._connect_btn.pressed.emit()
	await process_frame
	var req_live = director.active_requests.get(rid)
	_ok(req_live != null and req_live.connecting,
		"ПОДКЛЮЧИТЬСЯ запускает установку TCP-соединения")
	_ok(main._modal_game != null, "модалка соединения показана")
	_eq(str(main._modal_kind), "connection", "показана модалка соединения")
	_eq(card._connect_btn.caption, "СОЕДИНЕНИЕ…", "connecting: caption СОЕДИНЕНИЕ…")
	_ok(card._connect_btn.disabled, "connecting: ПОДКЛЮЧИТЬСЯ заблокирована")
	var conn_game = main._modal_game
	_ok(conn_game != null, "ConnectionGame создан контроллером")
	main._on_connection_finished(true, rid, conn_game)
	await process_frame
	await process_frame
	var conn_id := str(req_live.connection_id)
	_ok(req_live.connected, "соединение установлено")
	_ok(not conn_id.is_empty(), "connection_id заполнен")
	_ok(not req_live.minigame_active,
		"после соединения мини-игра отправки НЕ открывается")
	_ok(main._modal_game == null, "модалка соединения закрыта")
	_ok(_last_toast(main).begins_with("СОЕДИНЕНИЕ УСТАНОВЛЕНО"),
		"тост СОЕДИНЕНИЕ УСТАНОВЛЕНО: %s" % _last_toast(main))
	_eq(card._connect_btn.caption, "ПОДКЛЮЧЕНО", "после успеха caption ПОДКЛЮЧЕНО")
	_ok(card._connect_btn.disabled, "после успеха ПОДКЛЮЧИТЬСЯ заблокирована")
	_ok(card._can_drop_data(Vector2(10, 30), {"kind": "file", "id": attach_id}),
		"TCP с соединением: drop разрешён")

	var conn_cell = _slot_by_kind(main, "tcp_connection")
	_ok(conn_cell != null, "слот TCP-соединения показан")
	if conn_cell != null:
		_eq(conn_cell.kind, "tcp_connection", "kind слота — tcp_connection")
		_eq(conn_cell.id, conn_id, "слот хранит id соединения, а не запроса")
		_eq(conn_cell.file_name, str(req_live.client_name), "слот: имя клиента")
		_eq(conn_cell.detail.split(".").size(), 4,
			"слот: IP клиента (%s)" % conn_cell.detail)
		_ok(conn_cell.can_disconnect, "слот: can_disconnect = true")
		var disc_btn = conn_cell.get_node_or_null("DisconnectButton") as Button90
		_ok(disc_btn != null and disc_btn.visible, "в слоте видна кнопка ОТКЛЮЧИТЬ")
		if disc_btn != null:
			_eq(disc_btn.position, Vector2(146, 4), "ОТКЛЮЧИТЬ: позиция 146,4")
			_eq(disc_btn.size, Vector2(84, 16), "ОТКЛЮЧИТЬ: размер 84×16")
			_eq(disc_btn.caption_size, 10, "ОТКЛЮЧИТЬ: кегль 10")
		var close_btn = conn_cell.get_node_or_null("CloseButton") as Control
		_ok(close_btn != null and not close_btn.visible,
			"старый крестик в connection-слоте скрыт")
	_eq(str(main.status_bar.get_metric("tcp").get("value", "")), "1 / 1",
		"соединение занимает слот (1 / 1)")

	# --- attach через drop карточки: без автостарта --------------------------
	main._on_file_to_request(rid, 0, {"kind": "file", "id": attach_id,
		"from": "folder"})
	await process_frame
	main._refresh_hour()
	var req = director.active_requests.get(rid)
	_ok(req != null, "запрос жив после прикрепления")
	if req != null:
		_eq(req.attached.size(), 1, "файл прикреплён после соединения")
		_ok(req.attached.has(attach_id), "прикреплён именно required-файл")
		_ok(not req.minigame_active, "attach НЕ запускает мини-игру")
		_ok(not req.sending, "attach НЕ запускает отправку")
		_ok(director.request_missing(rid).is_empty(), "required-файл больше не missing")
	_ok(card.can_send(), "ОТПРАВИТЬ доступна после прикрепления")
	_ok(not card.send_disabled(), "кнопка ОТПРАВИТЬ включена")
	_ok(card.minigame_text().contains("МИНИ-ИГРА"), "подсказка мини-игры: %s"
		% card.minigame_text())
	var attached_sum := int(ECONOMY.send_minigame_for(
		[game.registry.files[attach_id].type]).get("sum", -1))
	_eq(card.difficulty_text(), "СУММА: %d" % attached_sum,
		"на карточке сумма коэффициентов")
	_eq(card.attached_count(), 1, "карточка: прикреплено 1/1")

	# --- ОТПРАВИТЬ -> мини-игра; после успеха запрос исчезает, слот остаётся -
	var holder := {"game": null}
	director.send_game_factory = func(_id, _tier, _seed, _ctx):
		var g := FakeGame.new()
		holder["game"] = g
		return g
	card._send_btn.pressed.emit()
	await process_frame
	_fake_game = holder.get("game")
	_ok(_fake_game != null, "подменная мини-игра создана")
	_ok(req_live.minigame_active, "ОТПРАВИТЬ открывает мини-игру отправки")
	_ok(card.send_disabled(), "во время мини-игры ОТПРАВИТЬ заблокирована")
	_ok(card._connect_btn.disabled, "во время мини-игры ПОДКЛЮЧИТЬСЯ заблокирована")
	_ok(main._modal_game != null, "модалка мини-игры показана")
	_ok(bool(main.controller.modal_open), "controller.modal_open = true на мини-игре")
	var left_before := float(req_live.time_left)
	for i in 10:
		main.controller.tick(0.1)
	_approx(float(req_live.time_left), left_before, 0.001,
		"таймер запроса стоит во время мини-игры")
	if _fake_game != null:
		_fake_game.finished.emit(0.8)
		await process_frame
		await process_frame
	_ok(main._modal_game == null, "мини-игра закрыта и освобождена")
	_ok(not bool(main.controller.modal_open), "controller.modal_open = false после игры")
	_ok(not req_live.minigame_active, "мини-игра снята с запроса")
	_ok(req_live.sending, "после мини-игры TCP-запрос сразу отправляется")
	var money_before := int(game.money)
	for i in 400:
		if not director.active_requests.has(rid):
			break
		main.controller.tick(0.1)
	_ok(not director.active_requests.has(rid), "после успешной TCP-отправки запрос исчез")
	_ok(int(game.money) > money_before,
		"деньги выросли (%d → %d)" % [money_before, int(game.money)])
	_ok(game.registry.files.has(attach_id), "файл остался после отправки")
	var sent_file = game.registry.files.get(attach_id)
	if sent_file != null:
		_eq(str(sent_file.location), "folder", "файл вернулся в папку")
		_eq(str(sent_file.attached_request), "", "файл откреплён от запроса")
	main._refresh_hour()
	var live_cell = _slot_by_kind(main, "tcp_connection")
	_ok(live_cell != null, "слот соединения остаётся после отправки")
	_ok(director.active_connections.has(conn_id), "соединение живо после отправки")
	# ОТКЛЮЧИТЬ — клик по кнопке слота, а не прямой вызов обработчика.
	if live_cell != null:
		var live_disc = live_cell.get_node_or_null("DisconnectButton") as Button90
		_ok(live_disc != null, "у слота есть кнопка ОТКЛЮЧИТЬ")
		if live_disc != null:
			live_disc.pressed.emit()
			await process_frame
	_ok(not director.active_connections.has(conn_id),
		"клик ОТКЛЮЧИТЬ вызвал disconnect_connection")
	_ok(_slot_by_kind(main, "tcp_connection") == null,
		"после ОТКЛЮЧИТЬ слот свободен")
	_eq(str(main.status_bar.get_metric("tcp").get("value", "")), "0 / 1",
		"счётчик слотов после отключения — 0 / 1")
	director.send_game_factory = Callable()
	_fake_game = null
	holder.clear()

	# --- Drop пакета в точную клетку сетки ----------------------------------
	var drop_id: String = director.spawn_packet_now("text", "tcp")
	_ok(not drop_id.is_empty(), "пакет для drop создан")
	var folder = game.registry.folders[folder_id]
	var target := Vector2i(-1, -1)
	for r in folder.rows:
		for c in folder.cols:
			if game.registry.can_place(folder, "O1", Vector2i(c, r), 0):
				target = Vector2i(c, r)
				break
		if target.x >= 0:
			break
	_ok(target.x >= 0, "найдена свободная клетка для drop")
	main._on_grid_packet_drop({"kind": "packet", "id": drop_id,
		"shape_id": "O1", "rotation": 0}, target, 0)
	await process_frame
	var drop_pkt = director.active_packets.get(drop_id)
	_ok(drop_pkt != null, "пакет остаётся в буфере до конца загрузки")
	if drop_pkt != null:
		_eq(str(drop_pkt.state), "loading", "drop в сетку начал загрузку")
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "1/10",
		"канал после старта приёма: 1/10")
	var in_cell = null
	for cell in main.slot_cells:
		if cell.state == "active":
			in_cell = cell
	_ok(in_cell != null, "занятый слот показан")
	if in_cell != null:
		_eq(in_cell.direction, "down", "слот приёма смотрит вниз")
	# Клик по занятому слоту больше не прерывает передачу.
	if drop_pkt != null:
		main._on_slot_close(drop_id)
		_eq(str(drop_pkt.state), "loading", "клик по слоту не отменяет загрузку")
		# Быстро завершаем загрузку, чтобы слот снова стал свободен.
		drop_pkt.loading_progress = float(drop_pkt.loading_duration) + 0.01
		director.tick(0.1)
		await process_frame
	_ok(not director.active_packets.has(drop_id), "пакет завершил загрузку")
	_eq(int(director.slots.used_count()), 0, "in-слот освобождён после загрузки")

	# Перегрузка канала: красный сегмент и подпись load/capacity.
	main._refresh_hour_status({"tcp_used": 1, "tcp_max": 1, "channel": 12.0,
		"channel_factor": 1.25, "sla": 60.0, "buffer_used": 1, "buffer_max": 6,
		"money": int(game.money), "hour": 1, "time_left": 120.0})
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "12/10",
		"перегрузка канала показана как 12/10")
	_ok(bool(main.status_bar.get_metric("channel").get("danger", false)),
		"перегруженный канал помечен красным")
	main._refresh_hour()

	# --- Нет карточек/оверлеев атак -----------------------------------------
	_ok(not main.has_method("_refresh_attacks"), "метод _refresh_attacks удалён")
	_ok(main.get("_ddos_overlay") == null, "оверлея DDoS нет")
	_ok(not main.has_method("_on_quarantine_drop"), "карантин-drop удалён")
	_ok(not main.has_method("_on_shield_press"), "удержание щита удалено")
	_ok(main.requests.size() > 0 and main.requests[0].get("is_attack") == null,
		"в RequestCard нет ветки атаки")
	_ok(main.packets.size() > 0 and main.packets[0].get("is_attack") == null,
		"в PacketCard нет ветки атаки")
	_ok(director.attack_added.get_connections().is_empty(),
		"UI не подключён к attack_added")
	_ok(director.attack_changed.get_connections().is_empty(),
		"UI не подключён к attack_changed")
	_ok(director.attack_removed.get_connections().is_empty(),
		"UI не подключён к attack_removed")

	# --- UDP-карточка: шанс 40%, lot_udp → 50%, повтор после потери ----------
	var udp_file = game.registry.create_file("udp_chance_file", "text", folder_id)
	_ok(udp_file != null, "UDP-файл создан")
	if udp_file != null:
		var udp_rid := str(director._create_request(1, "udp",
			[str(udp_file.id)], true))
		_ok(not udp_rid.is_empty(), "UDP-запрос создан")
		_ok(director.attach_file(udp_rid, str(udp_file.id)),
			"UDP: файл прикрепляется без соединения")
		main._refresh_hour()
		await process_frame
		var ucard = _request_card(main, udp_rid)
		_ok(ucard != null, "UDP-карточка найдена")
		if ucard != null:
			_eq(ucard.protocol, "UDP", "UDP-карточка: протокол UDP")
			_ok(not ucard._connect_btn.visible, "UDP: кнопки ПОДКЛЮЧИТЬСЯ нет")
			_approx(ucard.udp_chance, 0.4, 0.0001,
				"UDP · ШАНС 40%% (udp_chance = %.2f)" % ucard.udp_chance)
			_approx(director.udp_success_chance(), 0.4, 0.0001,
				"базовый шанс UDP = 40%")
			# lot_udp: +1 уровень → 50%.
			var udp_level_before := int(game.upgrades.get("udp_level", 0))
			game.upgrades["udp_level"] = udp_level_before + 1
			main._refresh_hour()
			await process_frame
			_approx(ucard.udp_chance, 0.5, 0.0001,
				"после lot_udp шанс 50%% (udp_chance = %.2f)" % ucard.udp_chance)
			_approx(director.udp_success_chance(), 0.5, 0.0001,
				"директор: после lot_udp шанс 50%")
			game.upgrades["udp_level"] = udp_level_before
			# Потеря пакета: retry-строка «ПОТЕРЯ ПАКЕТА · ПОВТОР N с».
			var udp_req = director.active_requests.get(udp_rid)
			_ok(udp_req != null, "UDP-запрос жив")
			if udp_req != null:
				udp_req.udp_retry_until = float(director.hour_elapsed) + 4.0
				main._refresh_hour()
				await process_frame
				_ok(ucard.udp_retry_left > 0.0,
					"UDP: retry_left > 0 после потери (%.1f с)" % ucard.udp_retry_left)
				_eq(int(ceilf(ucard.udp_retry_left)), 4,
					"UDP: повтор через 4 с")
		director._cleanup_request(udp_rid, true)

	# --- AttackDirector.cancel_active(): нода queue_free + attack_resolved ----
	var fake_attack := Node.new()
	main._show_modal_game(fake_attack)
	_ok(main._modal_game == fake_attack, "модалка атаки установлена")
	fake_attack.queue_free()
	main.controller.attack_resolved.emit("junk", true, 1)
	await process_frame
	_ok(main._modal_game == null, "attack_resolved снял _modal_game")
	_ok(not bool(main.controller.modal_open), "attack_resolved сбросил modal_open")

	# --- D2 (§5.5): экран результата до клика ПРОДОЛЖИТЬ --------------------
	var modal_mg = MG.new()
	modal_mg.start("dots", 1, 4242, {})
	var finish_count := [0]
	modal_mg.finished.connect(func(_q: float) -> void: finish_count[0] += 1)
	main._show_modal_game(modal_mg)
	await process_frame
	_ok(bool(modal_mg.defer_finish_signal), "Main включает defer_finish_signal")
	modal_mg._finish(0.8)
	await process_frame
	await process_frame
	_ok(is_instance_valid(modal_mg) and not modal_mg.is_queued_for_deletion(),
		"после _finish нода жива — виден экран результата")
	_eq(finish_count[0], 0, "finished НЕ эмитится до ПРОДОЛЖИТЬ")
	_ok(modal_mg.is_finished(), "мини-игра помечена завершённой")
	_ok(absf(float(modal_mg.quality()) - 0.8) < 0.0001, "качество 80% сохранено")
	modal_mg._continue_clicked()
	await process_frame
	await process_frame
	_eq(finish_count[0], 1, "finished эмитится ровно один раз по ПРОДОЛЖИТЬ")
	_ok(not is_instance_valid(modal_mg) or modal_mg.is_queued_for_deletion(),
		"после ПРОДОЛЖИТЬ нода освобождается")
	_ok(main._modal_game == null, "_modal_game снят после ПРОДОЛЖИТЬ")
	_ok(not bool(main.controller.modal_open), "modal_open сброшен после ПРОДОЛЖИТЬ")

	# --- M8: spawn_frozen подключён к UI и троттлится ----------------------
	_ok(director.spawn_frozen.get_connections().size() > 0,
		"M8: spawn_frozen подключён к тосту UI")
	main._spawn_frozen_toast_ms = -100000
	main._on_spawn_frozen_ui("buffer_full")
	var frozen_ms := int(main._spawn_frozen_toast_ms)
	main._on_spawn_frozen_ui("buffer_full")
	_eq(int(main._spawn_frozen_toast_ms), frozen_ms,
		"M8: повторный spawn_frozen в пределах 5 с не спамит")

	# --- M2: шаг обучения «send» засчитывается на пути закрытия мини-игры ---
	main._tutorial_reset()
	main._tutorial_active = true
	main._tutorial_shown = true
	main._tutorial_step = 3  # «send» в TUTORIAL_STEPS
	main._tutorial_step_elapsed = 0.0
	main._tutorial_ack_left = 0.0
	var tut_mg = MG.new()
	tut_mg.start("dots", 1, 777, {})
	_ok(main._show_modal_game(tut_mg, "send"), "M2: send-модалка открыта")
	main._on_minigame_closed_ui("tut_req")
	_eq(main._tutorial_step, 4,
		"M2: шаг send завершён через _on_minigame_closed_ui")
	main._on_minigame_closed_ui("tut_req")
	_eq(main._tutorial_step, 4, "M2: повторный close не двигает обучение дважды")
	main._on_modal_game_finished(null, tut_mg)
	_eq(main._tutorial_step, 4, "M2: finished не дублирует уведомление send")
	tut_mg.queue_free()
	main._tutorial_reset()
	main._modal_game = null
	main._modal_kind = ""
	main.controller.set_modal_open(false)
	await process_frame

	# --- C1: ввод под модалкой не открывает вторую мини-игру -----------------
	var guard_modal := Node.new()
	_ok(main._show_modal_game(guard_modal, "attack"),
		"C1: тестовая модалка атаки открыта")
	var guard_file = game.registry.create_file("guard_modal", "text", folder_id)
	var guard_rid := ""
	if guard_file != null:
		guard_rid = str(director._create_request(
			1, "udp", [str(guard_file.id)], true))
		_ok(not guard_rid.is_empty(), "C1: тестовый UDP-запрос создан")
		_ok(director.attach_file(guard_rid, str(guard_file.id)),
			"C1: файл тестового запроса прикреплён")
		main._on_request_send(guard_rid)
		await process_frame
		var guard_req = director.active_requests.get(guard_rid)
		_ok(main._modal_game == guard_modal,
			"C1: чужая (атакующая) модалка не освобождена")
		_ok(director._minigame == null,
			"C1: вторая мини-игра за модалкой не создана")
		_ok(guard_req != null and not bool(guard_req.minigame_active),
			"C1: minigame_active у заблокированного запроса не выставлен")
		# Belt-and-braces: даже если директор всё же эмитит show_minigame,
		# Main отказывает и откатывает мини-игру, не трогая чужую модалку.
		_ok(director._launch_send_minigame(guard_rid),
			"C1: директор принудительно эмитил мини-игру")
		await process_frame
		_ok(main._modal_game == guard_modal,
			"C1: откат send не освободил чужую модалку")
		_ok(director._minigame == null,
			"C1: send-мини-игра откатана force_close_send_minigame")
		_ok(guard_req != null and not bool(guard_req.minigame_active),
			"C1: minigame_active снят откатом send")
		# То же для соединения: эмитим show_connection в обход UI-гарда.
		var conn_file = game.registry.create_file("guard_conn", "text", folder_id)
		if conn_file != null:
			var conn_rid := str(director._create_request(
				1, "tcp", [str(conn_file.id)], false))
			_ok(not conn_rid.is_empty(), "C1: TCP-запрос для отката создан")
			var conn_req = director.active_requests.get(conn_rid)
			director._begin_connection(conn_req)
			await process_frame
			_ok(main._modal_game == guard_modal,
				"C1: откат connection не освободил чужую модалку")
			_ok(conn_req != null and not bool(conn_req.connecting),
				"C1: connecting снят connection_finished(false)")
			director._cleanup_request(conn_rid, true)
		director._cleanup_request(guard_rid, true)
	guard_modal.queue_free()
	await process_frame
	main._clear_modal_if_dead()
	main.controller.set_modal_open(false)
	main._refresh_hour()

	# --- H1: detach по required-индексу, а не по порядку вложений -----------
	var det_a = game.registry.create_file("detach_a", "text", folder_id)
	var det_b = game.registry.create_file("detach_b", "sound", folder_id)
	if det_a != null and det_b != null:
		var detach_rid := str(director._create_request(
			2, "udp", [str(det_a.id), str(det_b.id)], true))
		var detach_req = director.active_requests.get(detach_rid)
		_ok(detach_req != null, "H1: запрос на 2 required создан")
		# Прикрепляем ВТОРОЙ required первым: attached != required по порядку.
		_ok(director.attach_file(detach_rid, str(det_b.id)),
			"H1: второй required прикреплён первым")
		_eq(detach_req.attached, [str(det_b.id)],
			"H1: attached хранится в порядке вложения")
		# v3: открепление — двойной клик по чипу, кнопки ОТКРЕПИТЬ нет.
		main._refresh_hour()
		await process_frame
		var dcard = _request_card(main, detach_rid)
		_ok(dcard != null, "H1: карточка запроса найдена")
		if dcard != null:
			var dbl := InputEventMouseButton.new()
			dbl.button_index = MOUSE_BUTTON_LEFT
			dbl.pressed = true
			dbl.double_click = true
			dbl.position = dcard._slot_rect(1).get_center()
			dcard._gui_input(dbl)
		await process_frame
		_ok(detach_req != null and not detach_req.attached.has(str(det_b.id)),
			"H1: двойной клик по чипу 1 снял второй файл")
		_eq(detach_req.attached.size(), 0, "H1: attached пуст после detach")
		director._cleanup_request(detach_rid, true)

	# --- Конец часа при открытой мини-игре: не оставляем висячий _modal_game --
	var rid3: String = director.spawn_request_now(1)
	_ok(not rid3.is_empty(), "третий запрос создан для проверки конца часа")
	var missing3: Array = director.request_missing(rid3) if not rid3.is_empty() else []
	var leftover_id := str(missing3[0]) if not missing3.is_empty() else ""
	if not rid3.is_empty() and not leftover_id.is_empty():
		_ok(director.set_request_protocol(rid3, "udp"),
			"третий запрос переведён на UDP (без соединения)")
		_ok(director.attach_file(rid3, leftover_id), "файл прикреплён к третьему запросу")
		var holder2 := {"game": null}
		director.send_game_factory = func(_id, _tier, _seed, _ctx):
			var g := FakeGame.new()
			holder2["game"] = g
			return g
		main._on_request_send(rid3)
		await process_frame
		var ghost = holder2.get("game")
		_ok(ghost != null and main._modal_game == ghost,
			"мини-игра открыта перед концом часа")
		director.time_left = 0.05
		main.controller.tick(0.1)
		await process_frame
		await process_frame
		_eq(main.controller.phase, &"hour_result", "час завершился с открытой мини-игрой")
		_ok(main._modal_game == null, "force_close очистил _modal_game")
		_ok(not bool(main.controller.modal_open), "modal_open сброшен при force-close")
		_ok(ghost == null or not is_instance_valid(ghost) or ghost.is_queued_for_deletion(),
			"нода принудительно закрытой мини-игры освобождена")
		director.send_game_factory = Callable()
		holder2.clear()

	# --- Завершение часа и магазин ------------------------------------------
	director.time_left = 0.0
	main.controller.tick(0.1)
	await process_frame
	_eq(main.controller.phase, &"hour_result", "фаза — hour_result")
	_ok(main.hour_result_modal != null and main.hour_result_modal.visible,
		"модалка итогов часа показана")

	main.controller.next_after_hour()
	await process_frame
	_eq(main.controller.phase, &"prep", "после отчёта — снова prep")
	_eq(int(game.hour), 2, "после первого часа Game.hour = 2")
	_ok(main._shop_btn != null and main._shop_btn.visible,
		"в подготовке часа 2 магазин виден")
	_ok(main._start_btn != null and main._start_btn.visible,
		"после возврата в prep кнопка НАЧАТЬ ЧАС снова видна")
	_ok(main.sorting_table != null and main.sorting_table.visible,
		"в подготовке часа 2 стол сортировки виден")
	_eq(main.controller.shop_data().size(), 3, "после H1 — 3 предложения магазина")

	# --- Реальный переход по сигналу phase_changed (без ручного _on_phase) ---
	var started: bool = main.controller.start_hour()
	_ok(started, "controller.start_hour() запускает час 2")
	await process_frame
	_eq(main.controller.phase, &"hour", "start_hour() → фаза hour через phase_changed")
	_ok(main._start_btn != null and not main._start_btn.visible,
		"phase_changed(hour) скрывает кнопку НАЧАТЬ ЧАС")
	var director2 = main.controller.hour_director
	_ok(director2 != null, "hour_director часа 2 доступен")
	if director2 != null:
		director2.time_left = 0.05
		main.controller.tick(0.1)
		await process_frame
	_eq(main.controller.phase, &"hour_result", "час 2 → hour_result")
	main.controller.next_after_hour()
	await process_frame
	_eq(main.controller.phase, &"prep", "час 2 закрыт → prep")
	_ok(main._start_btn != null and main._start_btn.visible,
		"phase_changed(prep) возвращает кнопку НАЧАТЬ ЧАС")

	# --- Регрессия BUG 2: SLA 0 при открытой send-мини-игре ------------------
	# Debugger: _finish_run("sla") обязан остановить час, закрыть модалку и не
	# эмитить hour_finished/новые спавны. «Продолжить» после этого недоступно.
	var hf_count := [0]
	main.controller.hour_finished.connect(func(_r: Dictionary) -> void: hf_count[0] += 1)
	var started3: bool = main.controller.start_hour()
	_ok(started3, "SLA 0: час 3 запущен")
	await process_frame
	var director3 = main.controller.hour_director
	_ok(director3 != null and director3.running, "SLA 0: hour_director.running = true")
	var sla_file = game.registry.create_file("sla_zero_file", "text", folder_id)
	_ok(sla_file != null, "SLA 0: файл для запроса создан")
	if director3 != null and sla_file != null:
		var sla_rid := str(director3._create_request(1, "udp",
			[str(sla_file.id)], true))
		_ok(director3.attach_file(sla_rid, str(sla_file.id)),
			"SLA 0: файл прикреплён")
		var holder3 := {"game": null}
		director3.send_game_factory = func(_id, _tier, _seed, _ctx):
			var g := FakeGame.new()
			holder3["game"] = g
			return g
		main._on_request_send(sla_rid)
		await process_frame
		_ok(main._modal_game != null and str(main._modal_kind) == "send",
			"SLA 0: send-мини-игра открыта")

		var packets_before: int = director3.active_packets.size()
		var requests_before: int = director3.active_requests.size()
		var attacks_before := _attack_count(director3)
		var time_before := float(director3.time_left)
		var hour_before := int(game.hour)
		game.add_sla(-float(game.sla))
		await process_frame
		_ok(not director3.running, "SLA 0: hour_director остановлен")
		_ok(main._modal_game == null, "SLA 0: _modal_game снят (окно закрыто)")
		_ok(not bool(main.controller.modal_open), "SLA 0: modal_open сброшен")
		_eq(main.controller.phase, &"run_result", "SLA 0: контроллер в run_result")
		_ok(main.run_result_modal != null and main.run_result_modal.visible,
			"SLA 0: экран итогов забега показан")
		_eq(hf_count[0], 0, "SLA 0: hour_finished не эмитится")
		_ok(not main.controller.can_continue(), "SLA 0: controller.can_continue = false")
		_ok(not SM.can_continue(), "SLA 0: SaveManager.can_continue = false")

		# Тик после остановки не спавнит пакеты/запросы/атаки и не жжёт время.
		director3.tick(1.0)
		main.controller.tick(1.0)
		await process_frame
		_eq(director3.active_packets.size(), packets_before,
			"SLA 0: новых пакетов после tick нет")
		_eq(director3.active_requests.size(), requests_before,
			"SLA 0: новых запросов после tick нет")
		_eq(_attack_count(director3), attacks_before,
			"SLA 0: новых атак после tick нет")
		_approx(float(director3.time_left), time_before, 0.0001,
			"SLA 0: время часа стоит")
		_eq(int(game.hour), hour_before, "SLA 0: час не сменился")
		director3.send_game_factory = Callable()
		holder3.clear()

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Карточка пакета по id (в ПРИЁМЕ могут быть и автоспавненные пакеты).
func _packet_card(main, packet_id: String):
	for c in main.packets:
		if c != null and is_instance_valid(c) and str(c.id) == packet_id:
			return c
	return null


## Карточка запроса по id (живая, видимая).
func _request_card(main, req_id: String):
	for c in main.requests:
		if c != null and is_instance_valid(c) and str(c.id) == req_id:
			return c
	return null


## Есть ли в карточке кнопка с такой подписью (у Button90 нет имён).
func _card_has_caption(card, caption: String) -> bool:
	for child in card.get_children():
		if child is Button90 and str((child as Button90).caption) == caption:
			return true
	return false


## Занятая ячейка слота нужного вида.
func _slot_by_kind(main, kind: String):
	for c in main.slot_cells:
		if c != null and is_instance_valid(c) and str(c.kind) == kind \
				and str(c.state) == "active":
			return c
	return null


## Текст последнего тоста (ToastLayer.ToastItem.txt).
func _last_toast(main) -> String:
	var layer = main.toast_layer
	if layer == null or layer._items.is_empty():
		return ""
	var item = layer._items[layer._items.size() - 1]
	if item == null or not is_instance_valid(item):
		return ""
	return str(item.get("txt"))


## Число активных атак (0, если AttackDirector ещё не создан).
func _attack_count(director) -> int:
	if director == null or director.attack_director == null:
		return 0
	var active = director.attack_director.get("active_attacks")
	return (active as Dictionary).size() if active is Dictionary else 0


func _on_timeout() -> void:
	if _finished:
		return
	print("FAIL: тест превысил 60 секунд")
	_finished = true
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_stop_audio()
	# Даём AudioServer отпустить playback и освобождаем сам autoload Audio.
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		audio.queue_free()
	await process_frame
	await process_frame
	await process_frame
	# Небольшая пауза, чтобы AudioServer гарантированно отпустил playback.
	await create_timer(0.1).timeout
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


## Гасим AudioStreamPlayer перед выходом: иначе Godot ругается на утечку WAV.
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


## Минимальная мини-игра для теста отправки: сигнал finished(q).
class FakeGame:
	extends Node

	signal finished(quality: float)

	var running := true
	var id := "fake"
