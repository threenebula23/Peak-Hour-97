extends SceneTree
## Headless-тест связки Main.tscn ↔ GameController на экране подготовки (v2).
##
## Проверяет стартовые статы, сетку 5×4, стол сортировки вместо окон
## ПРИЁМ/ОТПРАВКА, счётчики в клетках, превью фигуры пакета и магазин после H1.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_prep.gd

var _checks := 0
var _fails := 0

const SHOP := preload("res://scripts/systems/shop.gd")
const REGISTRY_SCRIPT := preload("res://scripts/core/file_registry.gd")


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
	if game == null:
		_finish()
		return

	# --- Стартовые статы v2 --------------------------------------------------
	_eq(int(game.money), 50, "стартовые деньги 50")
	_ok(absf(float(game.sla) - 60.0) < 0.01, "стартовый SLA 60")
	_ok(absf(float(game.sla_cap()) - 60.0) < 0.01, "кап SLA 60")
	_eq(int(game.connection_slots()), 1, "стартовый слот один")
	var dims: Vector2i = game.folder_dims()
	_eq(dims, Vector2i(5, 4), "стартовая сетка папки 5×4")

	# --- Дерево, сетка, заголовки -------------------------------------------
	var rows: Array = main.tree.get("_rows")
	var sections := 0
	for e in rows:
		var row = e["row"]
		if row.is_section:
			sections += 1
	_ok(sections >= 1, "дерево получило секции (>=1), получено %d" % sections)
	_ok(main.grid.folder_id != "", "выбрана первая папка для сетки")
	_ok(main.files_window.title.contains(main.grid.folder_name),
		"заголовок ФАЙЛЫ использует реальное имя папки (%s)" % main.files_window.title)
	var grid_stats: Dictionary = main.grid.stats()
	_eq(int(grid_stats.get("total", 0)), 20, "сетка 5×4 = 20 клеток")
	_eq(int(main.grid.grid_metrics().get("cols", 0)), 5, "сетка: 5 столбцов")
	_eq(int(main.grid.grid_metrics().get("rows", 0)), 4, "сетка: 4 строки")
	var footer_files := int(grid_stats.get("files", 0))
	_eq(str(main.grid.footer_text()),
		"%d %s · 20 клеток" % [footer_files, _plural_files(footer_files)],
		"подвал сетки: файлы и клетки")
	_ok(main.files_window.title_hint.is_empty(),
		"подвал ФАЙЛЫ без подписи занятости: %s" % main.files_window.title_hint)

	# --- Статус-бар ----------------------------------------------------------
	_eq(str(main.status_bar.get_metric("money").get("value", "")), "$ 50",
		"статус-бар: деньги")
	_eq(str(main.status_bar.get_metric("channel").get("value", "")), "0/10",
		"статус-бар: канал 0/10 (load/capacity)")
	_eq(str(main.status_bar.get_metric("sla").get("value", "")), "60 / 60",
		"SLA на старте — 60 / 60")
	_eq(str(main.status_bar.get_metric("tcp").get("value", "")), "0 / 1",
		"статус-бар: слоты 0 / 1")
	_eq(str(main.status_bar.get_metric("buffer").get("value", "")), "0 / 6",
		"статус-бар: буфер 0 / 6")

	# --- Правая колонка подготовки: стол сортировки -------------------------
	_ok(main.sorting_table != null, "SortingTable создан")
	if main.sorting_table != null:
		_ok(main.sorting_table.visible, "стол сортировки виден в подготовке")
		_ok(not main.receive_window.visible, "окно ПРИЁМ скрыто в подготовке")
		_ok(not main.send_window.visible, "окно ОТПРАВКА скрыто в подготовке")
		_eq(main.sorting_table.total_cells(), 24, "стол сортировки 4×6 = 24 клетки")
		_eq(main.sorting_table.grid_metrics().get("cols", 0), 4, "стол: 4 столбца")
		_eq(main.sorting_table.grid_metrics().get("rows", 0), 6, "стол: 6 строк")

	# --- Магазин в H1 скрыт --------------------------------------------------
	_ok(main._shop_btn != null and not main._shop_btn.visible,
		"магазин скрыт в первом приготовлении")
	_eq(main.controller.shop_data().size(), 0, "в H1 нет предложений магазина")

	# --- Повторная перерисовка не должна падать ------------------------------
	main._refresh_prep()
	_ok(main.grid.folder_id != "", "повторная подготовка не сбросила папку")

	# --- Счётчики дерева в клетках ------------------------------------------
	var folder_id := str(main.grid.folder_id)
	var folder_row_count := -1
	var folder_row_capacity := -1
	for e in main.tree.get("_rows"):
		var row = e["row"]
		if not row.is_section and str(row.folder_id) == folder_id:
			folder_row_count = int(row.count)
			folder_row_capacity = int(row.capacity)
	_eq(folder_row_count, int(grid_stats.get("occupied", 0)),
		"дерево: папка показывает занятые клетки (H1-затравка)")
	_eq(folder_row_capacity, 20, "дерево: вместимость папки 20 клеток")

	# --- Плюрализация заголовка ДИСКИ ---------------------------------------
	var base_folders: int = main._count_folders(main.controller.prep_data().get("sections", []))
	_eq(main.tree_window.title_hint,
		main._plural_ru(base_folders, "ПАПКА", "ПАПКИ", "ПАПОК"),
		"заголовок ДИСКИ совпадает с числом папок")
	_eq(main._plural_ru(11, "ПАПКА", "ПАПКИ", "ПАПОК"), "11 ПАПОК",
		"исключение 11–14 — «11 ПАПОК»")

	_test_start_stats(main)
	_test_settings_from_menu(main)
	await _test_registry_autorefresh(main, game)
	_test_packet_shape(main, game)
	_test_search(main)
	_test_folder_name_generation(main, game)
	_test_rename_folder(main, game)
	_test_top_menu(main)
	_test_vhs(main)
	await _test_shop_after_hour(main, game)
	await _test_free_file_destruction(main, game)

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Строка стартовой сводки главного меню соответствует v2 (50 $, SLA 60, 1 слот).
func _test_start_stats(main) -> void:
	var text := str(main.main_menu.start_stats_text())
	_ok(text.contains("50"), "сводка меню: $50 на старте (%s)" % text)
	_ok(text.contains("60 SLA"), "сводка меню: 60 SLA (%s)" % text)
	_ok(text.contains("1 слот"), "сводка меню: 1 слот (%s)" % text)
	_ok(text.contains("9 часов"), "сводка меню: 9 часов (%s)" % text)
	_ok(not text.contains("150"), "сводка меню без устаревших $150")
	_ok(not text.contains("128"), "сводка меню без устаревшего SLA 128")


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
	var before_cells: int = main.grid.occupied_cells()
	var before_files: int = main.grid.file_count()
	var file = game.registry.create_file("авто_файл", "text", folder_id)
	_ok(file != null, "файл для автообновления создан")
	if file == null:
		return
	await process_frame
	await process_frame
	_eq(main.grid.file_count(), before_files + 1,
		"сетка обновилась по registry_changed (%d → %d)" % [before_files,
			main.grid.file_count()])
	_eq(main.grid.occupied_cells(), before_cells + 1,
		"занятые клетки выросли на 1 (текст)")
	_ok(main.files_window.title_hint.is_empty(),
		"подвал ФАЙЛЫ не дублирует занятость: %s"
		% main.files_window.title_hint)
	var count_ok := false
	for e in main.tree.get("_rows"):
		var row = e["row"]
		if not row.is_section and str(row.folder_id) == folder_id:
			count_ok = int(row.count) == main.grid.occupied_cells()
	_ok(count_ok, "дерево обновило счётчик ЗАНЯТЫХ КЛЕТОК")

	# Прикрепление меняет состояние файла в реестре (сетка читает registry).
	_ok(game.registry.attach_file(str(file.id), "req_auto"),
		"файл прикреплён к тестовому запросу")
	_eq(str(file.attached_request), "req_auto", "у файла выставлен attached_request")
	await process_frame
	game.registry.detach_file(str(file.id))
	await process_frame


## Карточка пакета показывает превью фигуры и «ЗАЙМЁТ N КЛЕТОК».
func _test_packet_shape(main, game) -> void:
	var director = main.controller.hour_director
	_ok(director != null, "hour_director доступен в подготовке")
	if director == null:
		return
	var pid: String = director.spawn_packet_now("sound", "tcp")
	_ok(not pid.is_empty(), "пакет для превью создан")
	if pid.is_empty() or not director.active_packets.has(pid):
		return
	var pkt = director.active_packets[pid]
	var card := PacketCard.new()
	main.receive_window.content.add_child(card)
	card.setup(str(pkt.id), str(pkt.file_name), "wav", str(pkt.type), "TCP",
		20.0, 20.0, 0.0, 512, "waiting", str(pkt.shape_id), int(pkt.rotation))
	_eq(card.cells_count(), 2, "звук занимает 2 клетки")
	_ok(card.cells_text().begins_with("ЗАЙМЁТ 2"), "подпись карточки: %s"
		% card.cells_text())
	_ok(not card.shape_id.is_empty(), "у карточки есть shape_id")
	var payload = card._get_drag_data(Vector2.ZERO)
	_ok(payload is Dictionary, "drag-данные карточки — словарь")
	if payload is Dictionary:
		_eq(str(payload.get("kind", "")), "packet", "payload kind = packet")
		_eq(str(payload.get("id", "")), str(pkt.id), "payload id пакета")
		_eq(str(payload.get("shape_id", "")), str(pkt.shape_id),
			"payload содержит shape_id")
		_ok(payload.has("rotation"), "payload содержит rotation")
	card.queue_free()
	await process_frame


## Поиск использует grid.set_filter и не схлопывает клетки.
func _test_search(main) -> void:
	main._search_edit.visible = true
	main._search_edit.text = "авто_файл"
	main._on_search_changed("авто_файл")
	_eq(main._filtered_files().size(), 1, "поиск нашёл один файл")
	_ok(main.files_window.title_hint.contains("найдено 1"),
		"заголовок показывает результат фильтра: %s" % main.files_window.title_hint)
	main._search_edit.text = "нет_такого"
	main._on_search_changed("нет_такого")
	_eq(main._filtered_files().size(), 0, "поиск без совпадений — 0 файлов")
	main._search_edit.text = ""
	main._on_search_changed("")
	main._search_edit.visible = false
	main._apply_file_filter()


## Имена новых папок генерируются и остаются уникальными в секции.
## v5: цена динамическая — Game.folder_price() 150/250/350…; прежний лимит
## 6 папок из constants больше не применяется (registry safety = 24).
func _test_folder_name_generation(main, game) -> void:
	_eq(main._unique_folder_name("C", "Разное"), "Разное 2",
		"занятое имя получает суффикс 2")

	var folders_max_legacy := int(_const_value("folders_max", 6))
	var folder_new_cost := int(_const_value("folder_new_cost", 180))
	var before: int = game.registry.folder_count()
	_eq(before, 2, "на старте ровно 2 папки")
	_eq(game.folder_price(), 150, "3-я папка стоит 150")
	_eq(int(game.folder_price()), int(main.tree.get_new_folder_price()),
		"ценник дерева = Game.folder_price()")
	_ok(int(game.folder_price()) != folder_new_cost,
		"цена не старый folder_new_cost=%d" % folder_new_cost)

	# Без денег третья папка не создаётся.
	game.money = 0
	main._new_folder_in("C")
	_eq(game.registry.folder_count(), before, "без денег папка не создаётся")
	_eq(int(game.money), 0, "неудачная покупка не уводит деньги в минус")

	# 3-я папка: 150 $.
	var expected_prices := [150, 250, 350]
	var expected_counts := [3, 4, 5]
	var price3 := int(game.folder_price())
	_eq(price3, 150, "3-я папка: цена 150 $")
	game.add_money(price3)
	main._new_folder_in("C")
	_eq(game.registry.folder_count(), 3, "3-я папка создана за 150 $")
	_eq(int(game.money), 0, "3-я папка списала 150 $")
	var third_id := str(main.grid.folder_id)
	_ok(game.registry.rename_folder(third_id, "Разное 2"),
		"третья папка переименована для проверки имён")
	_eq(main._unique_folder_name("C", "Разное"), "Разное 3",
		"следующий дубль получает суффикс 3")

	# 4-я и 5-я папки: 250 / 350 $.
	for i in range(1, 3):
		var price := int(game.folder_price())
		_eq(price, int(expected_prices[i]),
			"%d-я папка: цена %d $" % [expected_counts[i], price])
		game.add_money(price)
		main._new_folder_in("C")
		_eq(game.registry.folder_count(), int(expected_counts[i]),
			"%d-я папка создана за %d $" % [expected_counts[i], price])
		_eq(int(game.money), 0,
			"%d-я папка списала %d $" % [expected_counts[i], price])
	_eq(int(main.tree.get_new_folder_price()), 450,
		"после 5 папок ценник 450")

	# 6-я и 7-я папки создаются: лимит 6 больше не действует.
	for expected in [6, 7]:
		var price := int(game.folder_price())
		_ok(price > 0, "%d-я папка: цена > 0 (%d $)" % [expected, price])
		_ok(price != folder_new_cost, "%d-я папка: цена не 180 $" % expected)
		game.add_money(price)
		main._new_folder_in("C")
		_eq(game.registry.folder_count(), expected,
			"%d-я папка создана за %d $" % [expected, price])
		_eq(int(game.money), 0, "%d-я папка списала %d $" % [expected, price])
	_ok(game.registry.folder_count() > folders_max_legacy,
		"лимита %d папок нет (создано %d)" % [
			folders_max_legacy, game.registry.folder_count()])
	_eq(int(REGISTRY_SCRIPT.MAX_FOLDERS_PER_SECTION), 24,
		"registry safety = 24 папки в секции")
	_eq(game.folder_price(7), 650, "8-я папка стоит 650")
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


## Верхнее меню: одна рабочая кнопка МЕНЮ без демо-пунктов.
func _test_top_menu(main) -> void:
	_ok(main._menu_btn != null, "кнопка МЕНЮ создана")
	if main._menu_btn != null:
		_eq(main._menu_btn.caption, "МЕНЮ", "подпись кнопки — МЕНЮ")
		_eq(main._menu_btn.size, Vector2(72, 18), "кнопка МЕНЮ 72×18")
	for old in ["ФАЙЛ", "ВИД", "СПРАВКА"]:
		_ok(not main._menus.has(old), "меню без демо-пункта %s" % old)
	var items: Array = main._main_menu_items()
	_ok(items.has("Настройки"), "меню содержит «Настройки»")
	_ok(items.has("О программе"), "меню содержит «О программе»")
	_ok(items.has("В главное меню"), "меню содержит выход в главное меню")
	for item in items:
		_ok(not str(item).contains("ДЕМО"), "меню без пометки ДЕМО: %s" % str(item))

	main._on_menu_pick("Параметры узла")
	_ok(main.settings_modal.visible, "«Параметры узла» открывают настройки")
	main.settings_modal.close()
	_ok(not main.settings_modal.visible, "настройки закрываются")
	_ok(not bool(main.controller.paused), "закрытие настроек не оставляет паузу")

	main._on_menu_pick("О программе")
	_ok(main.confirm_modal.visible, "«О программе» открывает окно")
	main.confirm_modal._answer(true)
	_ok(not main.confirm_modal.visible, "окно «О программе» закрылось")
	_ok(main.main_menu.visible == false,
		"OK в «О программе» не выкидывает в главное меню")

	# Выход из подготовки через верхнее меню.
	main._on_menu_pick("В главное меню")
	_ok(main.confirm_modal.visible, "«В главное меню» просит подтверждение")
	main.confirm_modal._answer(true)
	_ok(main.main_menu.visible, "подтверждение возвращает в главное меню из подготовки")
	_ok(not bool(main.controller.paused), "в подготовке пауза не включается")
	main.main_menu.visible = false


## D2 (M16): без денег и с SLA=1 обычный файл можно уничтожить в подготовке
## после подтверждения (без штрафа SLA) и начать час — soft-lock исключён.
func _test_free_file_destruction(main, game) -> void:
	_eq(main.controller.phase, &"prep", "перед тестом удаления — подготовка")
	var folder_id := str(main.grid.folder_id)
	if folder_id.is_empty():
		_ok(false, "нет выбранной папки для теста удаления")
		return
	var file = game.registry.create_file("Удаляемый", "text", folder_id)
	_ok(file != null, "файл для удаления создан")
	if file == null:
		return
	var fid := str(file.id)
	game.money = 0
	game.sla = 1.0
	var sla_before := float(game.sla)
	main._destroy_selected_file(fid)
	_ok(main.confirm_modal != null and main.confirm_modal.visible,
		"удаление обычного файла просит подтверждение")
	if main.confirm_modal == null:
		return
	main.confirm_modal._answer(true)
	_ok(not game.registry.files.has(fid), "файл уничтожен после подтверждения")
	_eq(int(game.money), 0, "удаление файла не стоит денег")
	_approx(float(game.sla), sla_before, 0.001, "удаление файла не стоит SLA")
	main._on_start_hour()
	await process_frame
	_eq(main.controller.phase, &"hour",
		"после удаления файла час всё равно начинается")


## VHS-слой: только главное меню, не мешает вводу и не строится в headless.
func _test_vhs(main) -> void:
	var overlay = main.main_menu.vhs
	_ok(overlay != null, "VHS-слой создан")
	if overlay == null:
		return
	_ok(overlay.get_parent() == main.main_menu, "VHS-слой — ребёнок главного меню")
	_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE, "VHS не ловит мышь")
	_eq(overlay.process_mode, Node.PROCESS_MODE_ALWAYS, "VHS работает при паузе")
	_ok(not overlay.is_available(), "в headless VHS-материал не создаётся")
	_ok(main.main_menu.is_vhs_enabled(), "VHS включён по умолчанию")

	main.main_menu.set_vhs_enabled(false)
	_ok(not main.main_menu.vhs.enabled, "set_vhs_enabled(false) отключает эффект")
	main.main_menu.set_vhs_enabled(true)


## После первого часа: 3 лота, кнопка МАГАЗИН и open_prep.
func _test_shop_after_hour(main, game) -> void:
	main._on_start_hour()
	await process_frame
	_eq(main.controller.phase, &"hour", "час 1 запущен")
	_ok(main.receive_window.visible, "ПРИЁМ виден в час")
	_ok(main.send_window.visible, "ОТПРАВКА видна в час")
	_ok(main.sorting_table != null and not main.sorting_table.visible,
		"стол сортировки скрыт в час")
	var director = main.controller.hour_director
	director.time_left = 0.05
	main.controller.tick(0.1)
	await process_frame
	_eq(main.controller.phase, &"hour_result", "час 1 завершён")
	main.controller.next_after_hour()
	await process_frame
	_eq(main.controller.phase, &"prep", "после отчёта — подготовка часа 2")
	_eq(int(game.hour), 2, "Game.hour = 2")
	_ok(main._shop_btn != null and main._shop_btn.visible,
		"магазин виден после первого часа")
	var offers: Array = main.controller.shop_data()
	_eq(offers.size(), 3, "после H1 — 3 предложения")
	_ok(main.sorting_table.visible, "стол снова виден в подготовке")
	main._on_shop()
	_ok(main.shop_modal.visible, "магазин открывается в подготовке")
	_eq(main.shop_modal.card_ids().size(), 3, "в магазине 3 карточки")

	# --- v3: каталог 9 лотов, среди них UDP-повторитель ---------------------
	var catalog = SHOP.new()
	_eq(catalog.items().size(), 9, "каталог магазина — 9 лотов")
	var lot_ids: Array = []
	for item in catalog.items():
		lot_ids.append(str(item.get("id", "")))
	_ok(lot_ids.has("lot_udp"), "в каталоге есть lot_udp")
	var udp_lot: Dictionary = catalog.get_item("lot_udp")
	_eq(str(udp_lot.get("name_ru", "")), "UDP-повторитель",
		"lot_udp называется UDP-повторитель")
	_eq(int(udp_lot.get("max_level", 0)), 4, "lot_udp: 4 уровня")

	# Карточка lot_udp: 40% → 50%, на максимуме 80% → 80%.
	var saved_offers: Array[String] = game.shop_offers.duplicate()
	var saved_udp := int(game.upgrades.get("udp_level", 0))
	game.shop_offers.clear()
	game.shop_offers.append("lot_udp")
	main.shop_modal.refresh()
	var udp_cards: Array = main.shop_modal.card_infos()
	_eq(udp_cards.size(), 1, "карточка lot_udp показана")
	if not udp_cards.is_empty():
		var udp_info: Dictionary = udp_cards[0]
		_eq(str(udp_info.get("now_text", "")), "40%",
			"UDP-повторитель: сейчас 40%")
		_eq(str(udp_info.get("after_text", "")), "50%",
			"UDP-повторитель: после покупки 50%")
		_ok(not bool(udp_info.get("maxed", false)),
			"UDP-повторитель не на максимуме")
	game.upgrades["udp_level"] = 4
	main.shop_modal.refresh()
	var maxed_cards: Array = main.shop_modal.card_infos()
	_eq(maxed_cards.size(), 1, "карточка maxed lot_udp показана")
	if not maxed_cards.is_empty():
		var maxed_info: Dictionary = maxed_cards[0]
		_eq(str(maxed_info.get("now_text", "")), "80%",
			"UDP-повторитель на максимуме: 80%")
		_eq(str(maxed_info.get("after_text", "")), "80%",
			"UDP-повторитель на максимуме: 80% → 80%")
		_ok(bool(maxed_info.get("maxed", false)),
			"UDP-повторитель на максимуме помечен maxed")
	game.upgrades["udp_level"] = saved_udp
	game.shop_offers.clear()
	for id in saved_offers:
		game.shop_offers.append(id)
	main.shop_modal.refresh()

	main.shop_modal.close()
	_ok(not main.shop_modal.visible, "магазин закрывается")
	main._shop_btn.visible = true


## Плюрализация «файл/файла/файлов» — как в FileGrid.
func _plural_files(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "файл"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "файла"
	return "файлов"


func _const_value(key: String, fallback = null):
	var data := root.get_node_or_null("Data")
	if data != null and data.has_method("const_value"):
		return data.const_value(key, fallback)
	return fallback


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


func _approx(actual: float, expected: float, eps: float, message: String) -> void:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return
	_fails += 1
	print("FAIL: %s — получено %.6f, ожидалось %.6f" % [message, float(actual), float(expected)])


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)
