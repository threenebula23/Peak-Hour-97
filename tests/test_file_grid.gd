extends SceneTree
## Headless-тест клеточной сетки v2: чистая математика (cell size, label cell,
## поворот, hit-test, payload) + headless-инстансы FileGrid / SortingTable /
## DragController / FileShape без крашей.
##
## Запуск:
##   godot --headless --path . --script tests/test_file_grid.gd

const FG = preload("res://scripts/ui/file_grid.gd")
const ST = preload("res://scripts/ui/sorting_table.gd")
const DC = preload("res://scripts/ui/drag_controller.gd")
const FS = preload("res://scripts/ui/file_shape.gd")
const FR = preload("res://scripts/core/file_registry.gd")
const TP = preload("res://scripts/ui/tree_panel.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""


func _init() -> void:
	await process_frame
	var game = root.get_node_or_null("Game")
	if game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_test_cell_sizes()
	_test_hit_test()
	_test_labels_and_rotation()
	_test_payload_and_edges()
	_test_plural()
	game.start_new_run(1)
	await process_frame
	var registry = game.registry
	var folder_id := _first_folder_id(registry)
	if folder_id.is_empty():
		_fail("нет стартовой папки")
		_finish()
		return
	await _test_file_grid(registry, folder_id)
	await _test_sorting_table(registry)
	await _test_drag_controller(folder_id)
	await _test_file_shape()
	await _test_tree_panel()
	_finish()


# --- математика ------------------------------------------------------------

func _test_cell_sizes() -> void:
	_set_case("cell size")
	var view := Vector2(558, 470)
	_eq(FG.cell_size(view, 5, 4), 104.0, "5×4 при 558×470 → 104")
	_eq(FG.cell_size(view, 6, 4), 88.0, "6×4 → 88")
	_eq(FG.cell_size(view, 6, 5), 88.0, "6×5 → 88")
	_eq(FG.cell_size(view, 7, 5), 74.0, "7×5 → 74 (floor)")
	_eq(FG.cell_size(view, 7, 6), 73.0, "7×6 → 73")
	_eq(FG.cell_size(view, 8, 6), 64.0, "8×6 → 64")
	_eq(FG.cell_size(Vector2(20, 20), 5, 4), 56.0, "clamp снизу 56")
	_eq(FG.cell_size(Vector2(4000, 4000), 5, 4), 104.0, "clamp сверху 104")
	var table := FG.cell_size_pair(Vector2(416, 548), 4, 6, 6.0, 56.0, 110.0)
	_eq(table, Vector2(99, 86), "стол 4×6 при 416×548 → 99×86")
	_eq(ST.cell_size(Vector2(416, 548), 4, 6), Vector2(99, 86),
		"SortingTable.cell_size → 99×86")
	var table_min := FG.cell_size_pair(Vector2(100, 100), 4, 6, 6.0, 56.0, 110.0)
	_eq(table_min, Vector2(56, 56), "стол clamp снизу 56")
	var gs := FG.grid_size_of(5, 4, 104.0, 6.0)
	_eq(gs, Vector2(544, 434), "размер поля 5×4 при cell=104")
	var gs2 := FG.grid_size_pair(4, 6, Vector2(99, 86), 6.0)
	_eq(gs2, Vector2(414, 546), "размер стола 4×6 при 99×86")


func _test_hit_test() -> void:
	_set_case("hit test")
	var o := Vector2.ZERO
	_eq(FG.cell_at(Vector2(5, 5), o, 100.0, 10.0, 5, 4), Vector2i(0, 0),
		"точка в первой клетке")
	_eq(FG.cell_at(Vector2(115, 5), o, 100.0, 10.0, 5, 4), Vector2i(1, 0),
		"точка во второй клетке")
	_eq(FG.cell_at(Vector2(105, 5), o, 100.0, 10.0, 5, 4), Vector2i(-1, -1),
		"зазор — не клетка")
	_eq(FG.cell_at(Vector2(-1, 0), o, 100.0, 10.0, 5, 4), Vector2i(-1, -1),
		"вне поля слева")
	_eq(FG.cell_at(Vector2(560, 5), o, 100.0, 10.0, 5, 4), Vector2i(-1, -1),
		"вне поля справа")
	_eq(FG.nearest_cell(Vector2(106, 5), o, 100.0, 10.0, 5, 4), Vector2i(1, 0),
		"drop в зазоре прилипает к ближней клетке")
	_eq(FG.nearest_cell(Vector2(-30, -30), o, 100.0, 10.0, 5, 4),
		Vector2i(-1, -1), "drop вне поля → auto-place")
	var r := FG.cell_at_rect(Vector2(97, 95), o, Vector2(99, 86), 6.0, 4, 6)
	_eq(r, Vector2i(0, 1), "прямоугольный hit-test стола")


func _test_labels_and_rotation() -> void:
	_set_case("label cell")
	_eq(FR.label_cell(FR.shape_cells("S4", 0)), Vector2i(1, 0),
		"S: верхняя левая ЗАНЯТАЯ, не пустой угол bbox")
	_eq(FR.label_cell(FR.shape_cells("Z4", 0)), Vector2i(0, 0), "Z: label (0,0)")
	_eq(FR.label_cell(FR.shape_cells("L3c", 0)), Vector2i(1, 0),
		"L3c: label (1,0), не угол bbox")
	_eq(FR.label_cell(FR.shape_cells("T4a", 0)), Vector2i(0, 0), "T: label (0,0)")
	_eq(FR.label_cell(FR.shape_cells("I4V", 0)), Vector2i(0, 0), "I4V: label (0,0)")
	_eq(FG.label_cell(FG.shape_cells("S4", 0)), Vector2i(1, 0),
		"FileGrid.label_cell делегирует реестру")
	_eq(FG.anchor_origin(Vector2i(2, 2), "S4", 0), Vector2i(1, 2),
		"origin для S при клике в (2,2)")
	_eq(FG.anchor_origin(Vector2i(3, 3), "I4V", 0), Vector2i(3, 3),
		"origin для I4V по label-клетке")

	_set_case("rotation fit")
	var r := FG.best_rotation("I4H", 0, func(rot: int) -> bool: return rot == 1)
	_eq(r, 1, "первый подходящий поворот после текущего")
	var r2 := FG.best_rotation("I4H", 3, func(rot: int) -> bool: return rot == 0)
	_eq(r2, 0, "перебор 3→0")
	var none := FG.best_rotation("I4H", 0, func(_rot: int) -> bool: return false)
	_eq(none, -1, "ни один поворот не подходит")


func _test_payload_and_edges() -> void:
	_set_case("payload / contour")
	var p := FG.shape_payload_for("f1", "Договор", "text", "txt", "O1", 0,
		Vector2i(2, 3), "folder")
	_eq(str(p["kind"]), "file", "payload.kind")
	_eq(str(p["id"]), "f1", "payload.id")
	_eq(str(p["shape_id"]), "O1", "payload.shape_id")
	_eq(p["origin"], Vector2i(2, 3), "payload.origin")
	_eq(str(p["from"]), "folder", "payload.from")
	_eq((p["cells"] as Array).size(), 1, "payload.cells")
	_eq(FS.outer_edges(FR.shape_cells("O1", 0)).size(), 4, "O1: 4 внешних ребра")
	_eq(FS.outer_edges(FR.shape_cells("O4", 0)).size(), 8, "O4: 8 внешних рёбер")
	_eq(FS.outer_edges(FR.shape_cells("I4H", 0)).size(), 10, "I4H: 10 внешних рёбер")
	var s_cells := FR.shape_cells("S4", 0)
	var lbl := FR.label_cell(s_cells)
	var top_empty := true
	for cell in s_cells:
		if int(cell.y) == 0 and int(cell.x) < lbl.x:
			top_empty = false
	_ok(top_empty, "левее label в верхней строке S нет занятых клеток")


func _test_plural() -> void:
	_set_case("plural")
	_eq(FG.plural_cells(1), "клетка", "1 клетка")
	_eq(FG.plural_cells(2), "клетки", "2 клетки")
	_eq(FG.plural_cells(24), "клетки", "24 клетки")
	_eq(FG.plural_cells(20), "клеток", "20 клеток")
	_eq(FG.plural_cells(11), "клеток", "11 клеток")
	_eq(FG.plural_cells(21), "клетка", "21 клетка")


# --- headless-компоненты ---------------------------------------------------

func _test_file_grid(registry, folder_id: String) -> void:
	_set_case("FileGrid")
	var grid = FG.new()
	grid.name = "TestFileGrid"
	grid.size = Vector2(558, 470)
	root.add_child(grid)
	await process_frame
	grid.set_folder(folder_id, "РАЗНОЕ", "C: \\ РАЗНОЕ")
	await process_frame

	_eq(grid.get_folder_id(), folder_id, "folder_id установлен")
	_eq(grid.total_cells(), 20, "5×4 = 20 клеток")
	_eq(grid.occupied_cells(), 0, "пустая папка: 0 клеток")
	_eq(grid.file_count(), 0, "пустая папка: 0 файлов")
	_eq(grid.footer_text(), "занято 0 из 20 · свободно 20", "пустой подвал")
	var m: Dictionary = grid.grid_metrics()
	_eq(float(m["cell"]), 104.0, "cell при 558×470 → 104")
	_eq(int(m["cols"]), 5, "cols = 5")
	_eq(int(m["rows"]), 4, "rows = 4")
	_ok(grid.get_cards().is_empty(), "legacy get_cards() → []")
	grid.set_files([{"id": "legacy", "name": "Старый"}])
	_ok(grid.get_cards().is_empty(), "legacy set_files не строит карточки")

	var file = registry.create_file("Договор 97", "text", folder_id)
	_ok(file != null, "файл создан в папке")
	if file != null:
		grid.refresh()
		_eq(grid.file_count(), 1, "после создания 1 файл")
		_eq(grid.occupied_cells(), 1, "текст занимает 1 клетку")
		_eq(grid.footer_text(), "занято 1 из 20 · свободно 19",
			"подвал после создания")
		_eq(grid.hidden_count(), 0, "опасных файлов нет")

		var selected: Array = []
		grid.selection_changed.connect(func(id: String) -> void: selected.append(id))
		grid.select_file(str(file.id))
		_eq(selected.size(), 1, "select_file → selection_changed")
		_eq(str(selected[0]), str(file.id), "selection_changed с id")
		grid.clear_selection()
		_eq(selected.size(), 2, "clear_selection → второе событие")
		_eq(str(selected[1]), "", "clear_selection шлёт пустой id")

		var drops: Array = []
		grid.file_dropped.connect(func(payload: Dictionary) -> void: drops.append(payload))
		_ok(grid.accept_dropped_file({"kind": "file", "id": "x"}),
			"legacy accept_dropped_file(file) → true")
		_eq(drops.size(), 1, "legacy drop эмитит file_dropped")

		var fit: Dictionary = grid._resolve_placement({
			"kind": "file", "id": str(file.id), "shape_id": "O1",
			"rotation": 0, "from": "folder",
		}, Vector2i(4, 3), 0)
		_ok(bool(fit.get("ok", false)), "точное размещение 1×1 в (4,3)")
		_eq(fit.get("origin"), Vector2i(4, 3), "origin = клетка под курсором")
		_eq(int(fit.get("rotation", -1)), 0, "поворот сохранён")

		var ghost_fit: Dictionary = grid._resolve_placement({
			"kind": "file", "id": str(file.id), "shape_id": "O1",
			"rotation": 1, "from": "folder",
		}, Vector2i(-1, -1), 1)
		_ok(bool(ghost_fit.get("ok", false)), "auto-place находит место")

		var rejected: Array = []
		grid.drop_rejected.connect(func(reason: String) -> void: rejected.append(reason))
		_ok(rejected.is_empty(), "без drop отказа нет")

		registry.mark_failed(str(file.id))
		grid.refresh()
		_eq(grid.hidden_count(), 1, "failed считается опасным")
		var sf: Array = []
		grid.service_filter_changed.connect(func(on: bool) -> void: sf.append(on))
		grid.set_service_filter(true)
		_eq(sf.size(), 1, "service_filter_changed эмитится")
		_ok(bool(sf[0]), "service_filter_changed(true)")
	root.remove_child(grid)
	grid.queue_free()


func _test_sorting_table(registry) -> void:
	_set_case("SortingTable")
	var table = ST.new()
	table.name = "TestSortingTable"
	table.size = Vector2(416, 548)
	root.add_child(table)
	await process_frame
	table.refresh()
	await process_frame
	_eq(table.total_cells(), 24, "стол 4×6 = 24 клетки")
	_eq(table.occupied_cells(), 0, "пустой стол")
	_eq(table.footer_text(), "24 клетки · занято 0", "подвал пустого стола")
	var m: Dictionary = table.grid_metrics()
	_eq(m["cell"], Vector2(99, 86), "cell стола 99×86")
	_eq(int(m["cols"]), 4, "стол: 4 колонки")
	_eq(int(m["rows"]), 6, "стол: 6 строк")

	var file = registry.create_file("Стол 1", "text", "", &"table")
	_ok(file != null, "файл создан на столе")
	if file != null:
		table.refresh()
		_eq(table.file_count(), 1, "на столе 1 файл")
		_eq(table.occupied_cells(), 1, "на столе 1 клетка")
		_eq(table.footer_text(), "24 клетки · занято 1", "подвал стола с файлом")
		var fit: Dictionary = table._resolve_placement({
			"kind": "file", "id": str(file.id), "shape_id": "O1",
			"rotation": 0, "from": "table",
		}, Vector2i(3, 5), 0)
		_ok(bool(fit.get("ok", false)), "точное размещение на столе")
		var auto: Dictionary = table._resolve_placement({
			"kind": "file", "id": str(file.id), "shape_id": "O1",
			"rotation": 0, "from": "folder",
		}, Vector2i(-1, -1), 0)
		_ok(bool(auto.get("ok", false)), "auto-place на столе")
		var bad: Dictionary = table._resolve_placement({
			"kind": "file", "id": str(file.id), "shape_id": "I4H",
			"rotation": 0, "from": "folder",
		}, Vector2i(3, 5), 0)
		_ok(not bool(bad.get("ok", false)), "I4H не влезает в правый край стола")
		table.set_visible_data(false)
		_ok(not table.visible, "set_visible_data(false) скрывает стол")
		table.set_visible_data(true)
		_ok(table.visible, "set_visible_data(true) показывает стол")
	root.remove_child(table)
	table.queue_free()


func _test_drag_controller(folder_id: String) -> void:
	_set_case("DragController")
	var dc = DC.new()
	dc.name = "TestDragController"
	root.add_child(dc)
	await process_frame
	dc.begin(null, "shape")
	_eq(dc.mode(), "shape", "режим shape")
	_ok(dc.preview() == null, "begin(null) не создаёт превью")
	dc.set_mode("square")
	_eq(dc.mode(), "square", "режим square")
	dc.set_mode("nonsense")
	_eq(dc.mode(), "shape", "неизвестный режим → shape")

	var opened: Array = []
	dc.hover_open.connect(func(id: String) -> void: opened.append(id))
	dc.hover_folder(folder_id)
	dc._process(0.10)
	_eq(opened.size(), 0, "250 мс ещё не истекли")
	dc._process(0.20)
	_eq(opened.size(), 1, "hover_open через 250 мс")
	_eq(str(opened[0]), folder_id, "hover_open с folder_id")
	dc.hover_folder(folder_id)
	dc._process(0.50)
	_eq(opened.size(), 1, "повторный hover не дублирует open")
	dc.reset_hover()
	dc._process(0.50)
	_eq(opened.size(), 1, "reset_hover отменяет таймер")
	dc.hover_folder("другая")
	dc._process(0.30)
	_eq(opened.size(), 2, "новая папка открывается отдельно")

	var preview = FS.new()
	preview.setup("video", "O4", 0, "Видео", "mp4", 40.0)
	_eq(preview.custom_minimum_size, Vector2(80, 80), "превью O4 40 px → 80×80")
	dc.begin(preview, "shape")
	_ok(dc.preview() == preview, "begin сохраняет превью")
	dc.set_mode("square")
	_eq(preview.get_mode(), "square", "set_mode(SQUARE) обновляет превью")
	_eq(preview.custom_minimum_size, Vector2(40, 40), "square 1×1 = 40×40")
	dc.end()
	_ok(dc.preview() == null, "end() освобождает превью")
	dc.end()
	_ok(dc.preview() == null, "повторный end() не падает")
	root.remove_child(dc)
	dc.queue_free()


func _test_file_shape() -> void:
	_set_case("FileShape")
	var shape = FS.new()
	shape.setup("photo", "L3a", 0, "Фото", "jpg", 48.0)
	_eq(shape.custom_minimum_size, Vector2(96, 96), "L3a bbox 2×2 при 48 px")
	shape.set_mode("square")
	_eq(shape.custom_minimum_size, Vector2(48, 48), "square → 1×1")
	shape.set_mode("shape")
	shape.shape_rotation = 1
	shape.queue_redraw()
	root.add_child(shape)
	shape.queue_redraw()
	await process_frame
	_ok(shape.size.x > 0.0, "FileShape отрисован без краша")
	root.remove_child(shape)
	shape.queue_free()


func _test_tree_panel() -> void:
	_set_case("TreePanel / FolderRow")
	var tree = TP.new()
	tree.name = "TestTreePanel"
	tree.size = Vector2(280, 400)
	root.add_child(tree)
	await process_frame
	tree.set_data([{
		"id": "C", "name": "C:", "free_cells": 7,
		"folders": [
			{"id": "f1", "name": "Разное", "files": 2,
				"occupied_cells": 5, "total_cells": 20},
			{"id": "f2", "name": "Входящие", "files": 0,
				"occupied_cells": 0, "total_cells": 20},
		],
	}])
	await process_frame
	_eq(tree.footer_text(), "2 папок · 2 файлов · 5 клеток занято",
		"подвал дерева: папки/файлы/клетки")
	var section_row = null
	var folder_row = null
	for e in tree.get("_rows"):
		var row = e["row"]
		if row.is_section:
			section_row = row
		elif row.folder_id == "f1":
			folder_row = row
	_ok(section_row != null, "секция построена")
	if section_row != null:
		_eq(section_row.free_text, "свободно 7 клеток", "секция: свободно 7 клеток")
	_ok(folder_row != null, "папка построена")
	if folder_row != null:
		_eq(folder_row.count, 5, "FolderRow.count = занятые клетки")
		_eq(folder_row.capacity, 20, "FolderRow.capacity = всего клеток")
		_eq(folder_row.files_count, 2, "FolderRow.files_count = файлы")
		_eq(folder_row.tooltip_text, "2 файлов · 5 из 20 клеток",
			"тултип папки в клетках")
		var opened: Array = []
		tree.folder_selected.connect(func(id: String) -> void: opened.append(id))
		folder_row.set_hover(true)
		_eq(opened.size(), 1, "hover-open открывает папку через сигнал")
		_eq(str(opened[0]), "f1", "hover-open с folder_id")
		_ok(folder_row.hover_open, "визуал hover_open включён")
		folder_row.set_hover(false)
		var packets: Array = []
		tree.packet_dropped.connect(func(fid: String, payload: Dictionary) -> void:
			packets.append([fid, payload]))
		folder_row._drop_data(Vector2.ZERO, {"kind": "packet", "id": "p1"})
		_eq(packets.size(), 1, "packet drop из FolderRow")
		_eq(str(packets[0][0]), "f1", "packet drop: folder_id")
		tree.update_stats("f1", 3, 7, 24)
		_eq(folder_row.count, 7, "update_stats обновляет клетки")
		_eq(folder_row.capacity, 24, "update_stats обновляет ёмкость")
		_eq(tree.footer_text(), "2 папок · 3 файлов · 7 клеток занято",
			"подвал после update_stats")
	root.remove_child(tree)
	tree.queue_free()


# --- helpers ---------------------------------------------------------------

func _first_folder_id(registry) -> String:
	if registry == null:
		return ""
	for sec in registry.sections.values():
		if sec.folder_ids.size() > 0:
			return str(sec.folder_ids[0])
	return ""


func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message + " — ожидалось true")
	return false


func _eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_fail("%s — получено %s, ожидалось %s" % [_case + ": " + message,
		str(actual), str(expected)])
	return false


func _fail(message: String) -> void:
	_fails += 1
	printerr("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	if _fails == 0:
		print("PASS test_file_grid")
		quit(0)
	else:
		print("FAIL test_file_grid")
		quit(1)
