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

	_test_rename_folder(main, game)
	_test_top_menu(main)

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Критерий 17: переименование папки из контекстного меню подготовки.
func _test_rename_folder(main, game) -> void:
	var folder = game.registry.create_folder("C", "СТАРОЕ")
	_ok(folder != null, "папка для переименования создана")
	if folder == null:
		return
	var fid := str(folder.id)

	main._on_tree_menu("rename", fid)
	_ok(main.rename_modal != null and main.rename_modal.visible,
		"модалка переименования открыта")
	if main.rename_modal == null:
		return
	_eq(main.rename_modal.get_text(), "СТАРОЕ", "в поле — текущее имя папки")
	_eq(main.rename_modal.edit.max_length, 16, "поле ограничено 16 символами")

	main.rename_modal.edit.text = "НОВОЕ"
	main.rename_modal._submit()
	_ok(not main.rename_modal.visible, "модалка закрылась после ОК")
	_eq(str(game.registry.folders[fid].name), "НОВОЕ", "имя папки изменилось")

	# Пробелы обрезаются.
	main._on_tree_menu("rename", fid)
	main.rename_modal.edit.text = "  ОБРЕЗАНО  "
	main.rename_modal._submit()
	_eq(str(game.registry.folders[fid].name), "ОБРЕЗАНО", "strip_edges применился")

	# Пустое имя не применяется.
	main._on_tree_menu("rename", fid)
	main.rename_modal.edit.text = "   "
	main.rename_modal._submit()
	_eq(str(game.registry.folders[fid].name), "ОБРЕЗАНО", "пустое имя отклонено")

	# Дубль в той же секции не применяется.
	_ok(game.registry.create_folder("C", "ЗАНЯТО") != null, "папка-дубль создана")
	main._on_tree_menu("rename", fid)
	main.rename_modal.edit.text = "занято"
	main.rename_modal._submit()
	_eq(str(game.registry.folders[fid].name), "ОБРЕЗАНО", "дубль имени отклонён")

	# Длиннее 16 символов не применяется (LineEdit режет ввод, проверяем обработчик).
	main._on_tree_menu("rename", fid)
	main._on_rename_confirmed("ЭТО_СЛИШКОМ_ДЛИННОЕ_ИМЯ")
	main.rename_modal.visible = false
	_eq(str(game.registry.folders[fid].name), "ОБРЕЗАНО", "имя длиннее 16 отклонено")


## Верхнее меню: «Параметры узла» → настройки, «О программе» → окно.
func _test_top_menu(main) -> void:
	main._on_menu_pick("Параметры узла")
	_ok(main.settings_modal.visible, "«Параметры узла» открывают настройки")
	main.settings_modal.close()
	_ok(not main.settings_modal.visible, "настройки закрываются")

	main._on_menu_pick("О программе")
	_ok(main.confirm_modal.visible, "«О программе» открывает окно")
	main.confirm_modal._answer(true)
	_ok(not main.confirm_modal.visible, "окно «О программе» закрылось")
	_ok(main.main_menu.visible == false,
		"OK в «О программе» не выкидывает в главное меню")

	# Штатное подтверждение выхода по-прежнему работает.
	main._confirm_to_menu()
	main.confirm_modal._answer(true)
	_ok(main.main_menu.visible, "подтверждение выхода открывает главное меню")


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
