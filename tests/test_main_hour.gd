extends SceneTree
## Headless-тест экрана часа Main.tscn ↔ GameController ↔ HourDirector.
##
## Проверяет: карточки пакетов/запросов, 4 слота, статус-бар, тиканье
## таймера, переход в итоги часа и возврат в подготовку.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_hour.gd

var _checks := 0
var _fails := 0
var _finished := false


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
	for i in 3:
		_ok(game.registry.create_file("тест_%d" % i, "text", folder_id) != null,
			"файл тест_%d создан" % i)

	main._on_start_hour()
	await process_frame
	_eq(main.controller.phase, &"hour", "фаза контроллера — hour")
	_ok(main._shop_btn != null and not main._shop_btn.visible,
		"магазин скрыт во время часа")
	# Регресс: акцентная кнопка старта не должна оставаться в строке меню в час.
	_ok(main._start_btn != null and not main._start_btn.visible,
		"кнопка НАЧАТЬ ЧАС скрыта во время часа")

	var director = main.controller.hour_director
	_ok(director != null, "hour_director доступен")
	var pid: String = director.spawn_packet_now("text", "tcp")
	var rid: String = director.spawn_request_now()
	main._refresh_hour()
	await process_frame

	_ok(main.packets.size() > 0, "карточки пакетов созданы (%d)" % main.packets.size())
	_ok(main.requests.size() > 0, "карточки запросов созданы (%d)" % main.requests.size())
	_eq(main.slot_cells.size(), 4, "четыре SlotCell в полосе TCP")

	# --- Плюрализация заголовков окон: падежи счётчиков ---------------------
	_ok(not str(director.spawn_request_now()).is_empty(),
		"второй запрос создан для проверки падежа")
	main._refresh_hour()
	await process_frame
	_eq(main.send_window.title_hint, "2 ЗАПРОСА", "2 запроса — «2 ЗАПРОСА»")
	_eq(main.receive_window.title_hint, "1 ПАКЕТ", "1 пакет — «1 ПАКЕТ»")
	while director.active_packets.size() < 3:
		if str(director.spawn_packet_now("text", "tcp")).is_empty():
			break
	main._refresh_hour()
	await process_frame
	_eq(main.receive_window.title_hint, "3 ПАКЕТА", "3 пакета — «3 ПАКЕТА»")
	_eq(main._plural_ru(5, "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ"), "5 ПАКЕТОВ",
		"5 пакетов — «5 ПАКЕТОВ»")

	# --- Вместимость ОТПРАВКИ: 3 и 4 запроса должны быть видны целиком -----
	# Окно 856,320,416,276 → content 252 px. При шаге 64 карточка №4
	# уходила за нижний клип (192+64 = 256 > 252).
	var content: Control = main.send_window.content
	_eq(int(content.size.y), 252, "контент ОТПРАВКИ: высота 252 px")
	while director.active_requests.size() < 3:
		if str(director.spawn_request_now()).is_empty():
			break
	main._refresh_hour()
	await process_frame
	var cards3 := _request_cards(content)
	print("ОТПРАВКА N=3: карточек %d, низ последней %.1f / %.1f" % [
		cards3.size(), _cards_bottom(cards3), content.size.y])
	_eq(cards3.size(), 3, "3 активных запроса → 3 карточки в ОТПРАВКЕ")
	_ok(_cards_fit(cards3, content.size.y), "3 карточки целиком в клипе ОТПРАВКИ")
	_eq(main.send_window.title_hint, "3 ЗАПРОСА", "3 запроса — «3 ЗАПРОСА»")

	while director.active_requests.size() < 4:
		if str(director.spawn_request_now()).is_empty():
			break
	main._refresh_hour()
	await process_frame
	var cards4 := _request_cards(content)
	print("ОТПРАВКА N=4: карточек %d, низ последней %.1f / %.1f" % [
		cards4.size(), _cards_bottom(cards4), content.size.y])
	_eq(cards4.size(), 4, "4 активных запроса → 4 карточки в ОТПРАВКЕ")
	_ok(_cards_fit(cards4, content.size.y), "4 карточки целиком в клипе ОТПРАВКИ")
	for card in cards4:
		# Заголовок + таймер живут в верхних 40 px — они обязаны быть в клипе.
		_ok(card.position.y + 40.0 < content.size.y,
			"карточка %s: заголовок/таймер в клипе" % str(card.name))

	# Тайминги часа 1 (grace 1.5): пакет 30 с, запрос 45 с.
	if not pid.is_empty() and director.active_packets.has(pid):
		_ok(absf(float(director.active_packets[pid].timer_total) - 30.0) < 0.01,
			"таймер пакета часа 1 = 30 с (%.1f)" % float(director.active_packets[pid].timer_total))
	if not rid.is_empty() and director.active_requests.has(rid):
		_ok(absf(float(director.active_requests[rid].timer_total) - 45.0) < 0.01,
			"таймер запроса часа 1 = 45 с (%.1f)" % float(director.active_requests[rid].timer_total))
	_ok(absf(float(director.channel_load())) < 0.01,
		"канал в простое = 0 (%.2f)" % float(director.channel_load()))
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "0%",
		"статус-бар: канал 0% в простое")

	var tcp_metric := str(main.status_bar.get_metric("tcp").get("value", ""))
	var buffer_metric := str(main.status_bar.get_metric("buffer").get("value", ""))
	var hour_metric := str(main.status_bar.get_metric("hour").get("value", ""))
	var sla_metric := str(main.status_bar.get_metric("sla").get("value", ""))
	_ok(not tcp_metric.is_empty(), "статус TCP не пуст: %s" % tcp_metric)
	_ok(not buffer_metric.is_empty(), "статус буфера не пуст: %s" % buffer_metric)
	_ok(hour_metric.begins_with("ЧАС "), "статус часа: %s" % hour_metric)
	_eq(sla_metric, "128 / 200", "статус SLA — 128 / 200")

	# Таймер пакета должен уменьшаться при тике часа.
	var before := float(main.packets[0].time_left)
	main.controller.tick(1.0)
	main._refresh_hour()
	var after := float(main.packets[0].time_left)
	_ok(after < before, "таймер пакета уменьшился: %.2f → %.2f" % [before, after])

	# Принудительно завершаем час.
	director.time_left = 0.05
	main.controller.tick(0.1)
	await process_frame
	_eq(main.controller.phase, &"hour_result", "фаза — hour_result")
	_ok(main.hour_result_modal != null and main.hour_result_modal.visible,
		"модалка итогов часа показана")

	# Далее — подготовка следующего часа.
	main.controller.next_after_hour()
	_eq(main.controller.phase, &"prep", "после отчёта — снова prep")
	_ok(main.hour_result_modal == null or not main.hour_result_modal.visible,
		"модалка итогов часа скрыта в подготовке")

	# Час 2: магазин появляется в подготовке.
	_eq(int(game.hour), 2, "после первого часа Game.hour = 2")
	_ok(main._shop_btn != null and main._shop_btn.visible,
		"в подготовке часа 2 магазин виден")
	_ok(main._start_btn != null and main._start_btn.visible,
		"после возврата в prep кнопка НАЧАТЬ ЧАС снова видна")

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


## Карточки запросов в контенте ОТПРАВКИ (живые, видимые).
func _request_cards(content: Control) -> Array:
	var out: Array = []
	if content == null:
		return out
	for c in content.get_children():
		var sc = c.get_script()
		if sc == null or sc.get_global_name() != "RequestCard":
			continue
		if not (c as Control).visible or c.is_queued_for_deletion():
			continue
		out.append(c)
	return out


func _cards_bottom(cards: Array) -> float:
	var bottom := 0.0
	for c in cards:
		bottom = maxf(bottom, c.position.y + c.size.y)
	return bottom


## Все карточки целиком внутри клипа контента.
func _cards_fit(cards: Array, clip_h: float) -> bool:
	if cards.is_empty():
		return false
	for c in cards:
		if c.position.y < -0.01:
			return false
		if c.position.y + c.size.y > clip_h + 0.5:
			return false
	return true


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
