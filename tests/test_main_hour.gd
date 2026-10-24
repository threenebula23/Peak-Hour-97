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


func _init() -> void:
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

	var director = main.controller.hour_director
	_ok(director != null, "hour_director доступен")
	director.spawn_packet_now("text", "tcp")
	director.spawn_request_now()
	main._refresh_hour()
	await process_frame

	_ok(main.packets.size() > 0, "карточки пакетов созданы (%d)" % main.packets.size())
	_ok(main.requests.size() > 0, "карточки запросов созданы (%d)" % main.requests.size())
	_eq(main.slot_cells.size(), 4, "четыре SlotCell в полосе TCP")

	var tcp_metric := str(main.status_bar.get_metric("tcp").get("value", ""))
	var buffer_metric := str(main.status_bar.get_metric("buffer").get("value", ""))
	var hour_metric := str(main.status_bar.get_metric("hour").get("value", ""))
	_ok(not tcp_metric.is_empty(), "статус TCP не пуст: %s" % tcp_metric)
	_ok(not buffer_metric.is_empty(), "статус буфера не пуст: %s" % buffer_metric)
	_ok(hour_metric.begins_with("ЧАС "), "статус часа: %s" % hour_metric)

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

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


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
