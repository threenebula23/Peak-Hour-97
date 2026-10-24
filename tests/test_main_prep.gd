extends SceneTree
## Headless-тест связки Main.tscn ↔ GameController на экране подготовки.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_prep.gd

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

	_ok(main.controller != null, "controller создан")
	if main.controller == null:
		_finish()
		return
	_eq(main.controller.phase, &"prep", "фаза контроллера — prep")

	var game = root.get_node_or_null("Game")
	_ok(game != null, "autoload Game доступен")
	if game != null:
		_eq(int(game.money), 150, "стартовые деньги 150")

	var rows: Array = main.tree.get("_rows")
	var sections := 0
	for e in rows:
		var row = e["row"]
		if row.is_section:
			sections += 1
	_ok(sections >= 1, "дерево получило секции (>=1), получено %d" % sections)
	_ok(main.grid.folder_id != "", "выбрана первая папка для сетки")
	_eq(str(main.status_bar.get_metric("money").get("value", "")), "$ 150", "статус-бар: деньги")
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "0%", "статус-бар: канал 0%")

	_ok(main.main_menu.visible == false, "главное меню скрыто после старта")

	# Повторная перерисовка не должна падать.
	main._refresh_prep()
	_ok(main.grid.folder_id != "", "повторная подготовка не сбросила папку")

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
