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
	var sla_metric: Dictionary = main.status_bar.get_metric("sla")
	_eq(str(sla_metric.get("value", "")), "128 / 200", "SLA на старте — 128 / 200")
	_ok(absf(float(sla_metric.get("fill", 0.0)) - 128.0 / 200.0) < 0.01,
		"заливка SLA = 128/200 (%.2f)" % float(sla_metric.get("fill", 0.0)))

	_ok(main.main_menu.visible == false, "главное меню скрыто после старта")
	_ok(main._shop_btn != null and not main._shop_btn.visible,
		"магазин скрыт в первом приготовлении")

	# Повторная перерисовка не должна падать.
	main._refresh_prep()
	_ok(main.grid.folder_id != "", "повторная подготовка не сбросила папку")

	# --- Плюрализация заголовка ДИСКИ: 1 ПАПКА / 2 ПАПКИ / 5 ПАПОК ---------
	_eq(main.tree_window.title_hint, "1 ПАПКА", "1 папка — «1 ПАПКА»")
	_ok(game.registry.create_folder("C", "ПЛЮРАЛ 2") != null,
		"вторая папка создана для проверки падежа")
	main._refresh_prep()
	_eq(main.tree_window.title_hint, "2 ПАПКИ", "2 папки — «2 ПАПКИ»")
	while main._count_folders(main.controller.prep_data().get("sections", [])) < 5:
		if game.registry.create_folder("C",
				main._unique_folder_name("C", "ПЛЮРАЛ")) == null:
			break
	main._refresh_prep()
	_eq(main.tree_window.title_hint, "5 ПАПОК", "5 папок — «5 ПАПОК»")
	_eq(main._plural_ru(11, "ПАПКА", "ПАПКИ", "ПАПОК"), "11 ПАПОК",
		"исключение 11–14 — «11 ПАПОК»")

	_test_settings_from_menu(main)
	await _test_registry_autorefresh(main, game)
	_test_rename_folder(main, game)
	_test_folder_name_generation(main, game)
	_test_top_menu(main)

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Кнопка «Настройки» главного меню открывает SettingsModal поверх меню.
func _test_settings_from_menu(main) -> void:
	main.main_menu.visible = true
	main.main_menu.settings.emit()
	_ok(main.settings_modal.visible, "кнопка «Настройки» открывает модалку")
	_ok(main.settings_modal.get_parent() == main.modal_root,
		"настройки лежат в modal_root (поверх главного меню)")
	main.settings_modal.close()
	_ok(not main.settings_modal.visible, "настройки закрываются")
	main.main_menu.visible = false


## Изменения реестра сами обновляют сетку и счётчики дерева (без _refresh_prep).
func _test_registry_autorefresh(main, game) -> void:
	var folder_id := str(main.grid.folder_id)
	var before: int = main.grid.get_cards().size()
	var file = game.registry.create_file("авто_файл", "text", folder_id)
	_ok(file != null, "файл для автообновления создан")
	if file == null:
		return
	await process_frame
	await process_frame
	_eq(main.grid.get_cards().size(), before + 1,
		"сетка обновилась по registry_changed (%d → %d)" % [before,
			main.grid.get_cards().size()])
	var count_ok := false
	for e in main.tree.get("_rows"):
		var row = e["row"]
		if not row.is_section and str(row.folder_id) == folder_id:
			count_ok = int(row.count) == before + 1
	_ok(count_ok, "дерево обновило счётчик папки")

	# state attached приходит из prep_data и обновляет FileCard.
	_ok(game.registry.attach_file(str(file.id), "req_auto"),
		"файл прикреплён к тестовому запросу")
	await process_frame
	await process_frame
	var state := ""
	for c in main.grid.get_cards():
		if str(c.id) == str(file.id):
			state = str(c.state)
	_eq(state, "attached", "FileCard state обновился до attached")
	game.registry.detach_file(str(file.id))
	await process_frame


## Имена новых папок генерируются и остаются уникальными в секции.
func _test_folder_name_generation(main, game) -> void:
	# «Разное» уже создано setup_new_run — получаем следующее имя.
	_eq(main._unique_folder_name("C", "Разное"), "Разное 2",
		"занятое имя получает суффикс 2")
	_ok(game.registry.create_folder("C", "Разное 2") != null, "папка «Разное 2» создана")
	_eq(main._unique_folder_name("C", "Разное"), "Разное 3",
		"следующий дубль получает суффикс 3")

	# _new_folder_in больше не падает на дубле: два вызова — два имени.
	var before: int = game.registry.folder_count()
	main._new_folder_in("C")
	main._new_folder_in("C")
	_eq(game.registry.folder_count(), before + 2, "две новые папки созданы")
	var names := {}
	for folder in game.registry.folders.values():
		if str(folder.section) != "C":
			continue
		var key := str(folder.name).to_lower()
		_ok(not names.has(key), "имя папки уникально в секции: %s" % str(folder.name))
		names[key] = true

	# Лимит 12 папок: лишняя не создаётся.
	for i in 20:
		if main._section_folder_count("C") >= 12:
			break
		game.registry.create_folder("C", main._unique_folder_name("C", "Лимит"))
	_eq(main._section_folder_count("C"), 12, "в секции ровно 12 папок")
	var at_limit: int = game.registry.folder_count()
	main._new_folder_in("C")
	_eq(game.registry.folder_count(), at_limit, "сверх 12 папок в секции не создаётся")
	main._refresh_prep()


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
