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

	# --- Стартовые статы H1 --------------------------------------------------
	_eq(str(main.status_bar.get_metric("sla").get("value", "")), "60 / 60",
		"статус SLA — 60 / 60")
	_eq(str(main.status_bar.get_metric("tcp").get("value", "")), "0 / 1",
		"статус слотов — 0 / 1")
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "0/10",
		"статус канала — load/capacity 0/10")
	_eq(str(main.status_bar.get_metric("buffer").get("value", "")), "0 / 6",
		"статус буфера — 0 / 6")

	var director = main.controller.hour_director
	_ok(director != null, "hour_director доступен")

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
	if not main.packets.is_empty():
		var pcard = main.packets[0]
		var pkt = director.active_packets.get(pid)
		_ok(pkt != null, "пакет есть в директоре")
		if pkt != null:
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
	_ok(card.minigame_text().contains("—"), "мини-игра не определена без файлов")
	_eq(card.protocol, "TCP", "протокол по умолчанию TCP")

	# --- Раскладка v2: карточка 108 px, скролл вмещает 4 запроса -------------
	var content: Control = main.send_window.content
	_eq(int(content.size.y), 252, "контент ОТПРАВКИ: высота 252 px")
	_eq(float(card.size.y), 108.0, "RequestCard v2: высота 108 px")
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
	main._on_file_to_request(rid, 0, {"kind": "file", "id": str(file_ids[0]),
		"from": "folder"})
	await process_frame
	main._refresh_hour()
	var req = director.active_requests.get(rid)
	_ok(req != null, "запрос жив после прикрепления")
	if req != null:
		_eq(req.attached.size(), 1, "файл прикреплён")
		_ok(not req.minigame_active, "attach НЕ запускает мини-игру")
		_ok(not req.sending, "attach НЕ запускает отправку")
	_ok(card.can_send(), "ОТПРАВИТЬ доступна после прикрепления")
	_ok(not card.send_disabled(), "кнопка ОТПРАВИТЬ включена")
	_ok(card.minigame_text().contains("МИНИ-ИГРА"), "подсказка мини-игры: %s"
		% card.minigame_text())
	_eq(card.difficulty_text(), "СЛОЖНОСТЬ: 1", "сложность текста = 1")
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

	# --- Мини-игра отправки через подменную фабрику -------------------------
	var holder := {"game": null}
	director.send_game_factory = func(_id, _tier, _seed, _ctx):
		var g := FakeGame.new()
		holder["game"] = g
		return g
	main._on_request_send(rid)
	await process_frame
	_ok(director.active_requests[rid].minigame_active, "ОТПРАВИТЬ открывает мини-игру")
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

	# --- Конец часа при открытой мини-игре: не оставляем висячий _modal_game --
	var rid3: String = director.spawn_request_now(1)
	_ok(not rid3.is_empty(), "третий запрос создан для проверки конца часа")
	var leftover_id := ""
	for f in game.registry.files.values():
		if str(f.attached_request).is_empty() and str(f.location) == "folder":
			leftover_id = str(f.id)
			break
	if not rid3.is_empty() and not leftover_id.is_empty():
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

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


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
