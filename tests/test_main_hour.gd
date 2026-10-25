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

	# --- Запрос: до прикрепления кнопка ОТПРАВИТЬ выключена ------------------
	var card = _request_card(main, rid)
	_ok(card != null, "карточка запроса найдена")
	if card == null:
		_finish()
		return
	_eq(card.required_count, 1, "запросу нужен 1 файл")
	_eq(card.attached_count(), 0, "прикреплено 0 файлов")
	_ok(card.send_disabled(), "ОТПРАВИТЬ выключена без файлов")
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

	# --- attach через drop карточки: без автостарта --------------------------
	var missing: Array = director.request_missing(rid)
	_ok(missing.size() == 1, "у запроса есть конкретный required-файл")
	if missing.is_empty():
		_finish()
		return
	var attach_id := str(missing[0])
	main._on_file_to_request(rid, 0, {"kind": "file", "id": attach_id,
		"from": "folder"})
	await process_frame
	main._refresh_hour()
	var req = director.active_requests.get(rid)
	_ok(req != null, "запрос жив после прикрепления")
	if req != null:
		_eq(req.attached.size(), 1, "файл прикреплён")
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

	# --- TCP/UDP -------------------------------------------------------------
	main._on_request_protocol_toggle(rid)
	await process_frame
	main._refresh_hour()
	_eq(str(director.active_requests[rid].protocol), "udp", "протокол переключён на UDP")
	_eq(card.protocol, "UDP", "карточка показывает UDP")
	main._on_request_protocol_toggle(rid)
	await process_frame
	main._refresh_hour()
	_eq(str(director.active_requests[rid].protocol), "tcp", "протокол вернулся на TCP")

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

	# Перегрузка канала: красный сегмент и подпись load/capacity.
	main._refresh_hour_status({"tcp_used": 1, "tcp_max": 1, "channel": 12.0,
		"channel_factor": 1.25, "sla": 60.0, "buffer_used": 1, "buffer_max": 6,
		"money": int(game.money), "hour": 1, "time_left": 120.0})
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "12/10",
		"перегрузка канала показана как 12/10")
	_ok(bool(main.status_bar.get_metric("channel").get("danger", false)),
		"перегруженный канал помечен красным")
	main._refresh_hour()

	# --- TCP: кнопка СОЕДИНИТЬСЯ → ConnectionGame → мини-игра отправки ------
	var holder := {"game": null}
	director.send_game_factory = func(_id, _tier, _seed, _ctx):
		var g := FakeGame.new()
		holder["game"] = g
		return g
	_eq(card._send_btn.caption, "СОЕДИНИТЬСЯ",
		"TCP без соединения: кнопка СОЕДИНИТЬСЯ")
	card._send_btn.pressed.emit()
	await process_frame
	var req_live = director.active_requests.get(rid)
	_ok(req_live != null and req_live.connecting,
		"нажатие запускает установку TCP-соединения")
	_ok(main._modal_game != null, "модалка соединения показана")
	_eq(str(main._modal_kind), "connection", "показана модалка соединения")
	var conn_game = main._modal_game
	_ok(conn_game != null, "ConnectionGame создан контроллером")
	main._on_connection_finished(true, rid, conn_game)
	await process_frame
	await process_frame
	_ok(req_live != null and req_live.connected, "соединение установлено")
	_ok(req_live != null and req_live.minigame_active,
		"после соединения открылась мини-игра отправки")
	_ok(main._modal_game != null, "модалка мини-игры показана")
	_ok(bool(main.controller.modal_open), "controller.modal_open = true на мини-игре")
	_fake_game = holder.get("game")
	_ok(_fake_game != null, "подменная мини-игра создана")
	if _fake_game != null:
		_fake_game.finished.emit(0.8)
		await process_frame
		await process_frame
	_ok(main._modal_game == null, "мини-игра закрыта и освобождена")
	_ok(not bool(main.controller.modal_open), "controller.modal_open = false после игры")
	director.send_game_factory = Callable()
	_fake_game = null
	holder.clear()
	var req2 = director.active_requests.get(rid)
	if req2 != null:
		_ok(not req2.minigame_active, "мини-игра снята с запроса")
		# out-слот занят приёмом → запрос встаёт в очередь «ОЖИДАНИЕ СЛОТА».
		_ok(req2.sending or director.is_request_queued(rid),
			"после игры запрос отправляется или ждёт слот")
	main._refresh_hour()
	if req2 != null and director.is_request_queued(rid):
		var qcard = _request_card(main, rid)
		if qcard != null:
			_ok(qcard.queued, "карточка показывает ожидание слота")

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
			_ok(director.attach_file(conn_rid, str(conn_file.id)),
				"C1: файл для отката соединения прикреплён")
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
		main._on_request_detach(detach_rid, 1)
		await process_frame
		_ok(detach_req != null and not detach_req.attached.has(str(det_b.id)),
			"H1: X по required-индексу 1 снял второй файл")
		_eq(detach_req.attached.size(), 0, "H1: attached пуст после detach")
		director._cleanup_request(detach_rid, true)

	# --- Конец часа при открытой мини-игре: не оставляем висячий _modal_game --
	var rid3: String = director.spawn_request_now(1)
	_ok(not rid3.is_empty(), "третий запрос создан для проверки конца часа")
	var missing3: Array = director.request_missing(rid3) if not rid3.is_empty() else []
	var leftover_id := str(missing3[0]) if not missing3.is_empty() else ""
	if not rid3.is_empty() and not leftover_id.is_empty():
		_ok(director.attach_file(rid3, leftover_id), "файл прикреплён к третьему запросу")
		_ok(director.set_request_protocol(rid3, "udp"),
			"третий запрос переведён на UDP (без соединения)")
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
