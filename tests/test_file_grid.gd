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
	_test_draw_offsets()
	_test_input_helpers()
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
	await _test_grid_self_heal(registry, folder_id)
	await _test_grid_confirmed_reservation(registry)
	await _test_rotation_preference()
	await _test_ghost_rotation()
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


func _test_draw_offsets() -> void:
	_set_case("draw offsets")
	# BUG A: раньше paint() получал _grid_origin и все файлы падали в (0,0).
	var origin := Vector2(12, 20)
	var zero := FG.shape_origin(origin, 100.0, 6.0, Vector2i.ZERO)
	var at_32 := FG.shape_origin(origin, 100.0, 6.0, Vector2i(3, 2))
	_eq(zero, Vector2(12, 20), "origin (0,0) = grid origin")
	_eq(at_32, Vector2(330, 232), "origin (3,2) = grid origin + 3/2 шага")
	_ok(zero != at_32, "разные origin дают разные позиции рисования")
	var cell_rect := FS.cell_pixel_rect(at_32, Vector2i.ZERO, 100.0, 6.0)
	_eq(cell_rect, Rect2(327, 229, 106, 106),
		"файл в (3,2) рисует клетку (3,2), а не (0,0)")
	var table_pos := FG.shape_origin_pair(Vector2(9, 11), Vector2(99, 86), 6.0,
		Vector2i(2, 4))
	_eq(table_pos, Vector2(219, 379), "стол: origin (2,4) с прямоугольной клеткой")


func _test_input_helpers() -> void:
	_set_case("rotate input")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.keycode = KEY_K  # русская раскладка даёт другую букву
	key.pressed = true
	_ok(FG.is_rotate_key(key), "R распознаётся по physical_keycode")
	key.echo = true
	_ok(not FG.is_rotate_key(key), "echo-повтор R игнорируется")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	_ok(FG.is_rotate_click(click), "ПКМ распознаётся как поворот во время drag")
	click.pressed = false
	_ok(not FG.is_rotate_click(click), "отпускание ПКМ не вращает")


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
	_eq(grid.footer_text(), _footer(grid.stats()), "пустой подвал")
	_eq(grid.footer_text(), "0 файлов · 20 клеток",
		"подвал: файлы и клетки (с плюрализацией)")
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
		_eq(grid.footer_text(), _footer(grid.stats()),
			"подвал после создания")
		_eq(grid.footer_text(), "1 файл · 20 клеток",
			"подвал: 1 файл, 20 клеток")
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


## Self-heal: файл с folder_id папки, но выпавший из file_ids/cells, всё равно
## должен появиться в FileGrid после refresh (и получить валидную клетку).
func _test_grid_self_heal(registry, folder_id: String) -> void:
	_set_case("FileGrid self-heal")
	var grid = FG.new()
	grid.name = "TestSelfHealGrid"
	grid.size = Vector2(558, 470)
	root.add_child(grid)
	await process_frame
	grid.set_folder(folder_id, "РАЗНОЕ", "C: \\ РАЗНОЕ")
	await process_frame
	var file = registry.create_file("Self-heal 97", "text", folder_id)
	_ok(file != null, "файл создан")
	if file == null:
		root.remove_child(grid)
		grid.queue_free()
		return
	var folder = registry.get_folder(folder_id)
	# Ломаем bookkeeping: файл помнит folder_id, но папка о нём «забыла».
	folder.file_ids.erase(str(file.id))
	for cell in folder.cells.keys():
		if str(folder.cells[cell]) == str(file.id):
			folder.cells.erase(cell)
	file.origin = Vector2i(99, 99)
	grid.refresh()
	_ok(grid._by_id.has(str(file.id)), "потерянный файл снова в _by_id")
	_ok(grid._files.has(file), "потерянный файл снова в _files")
	_ok(folder.file_ids.has(str(file.id)), "file_ids восстановлен")
	_ok(file.origin.x >= 0 and file.origin.y >= 0 \
		and file.origin.x < int(folder.cols) and file.origin.y < int(folder.rows),
		"origin зажат в границы сетки: %s" % str(file.origin))
	_eq(str(folder.cells.get(file.origin, "")), str(file.id),
		"клетка origin снова принадлежит файлу")
	_eq(str(grid._cells_owner.get(file.origin, "")), str(file.id),
		"_cells_owner содержит восстановленный файл")
	_eq(registry.validate().size(), 0,
		"инварианты после self-heal: %s" % str(registry.validate()))
	root.remove_child(grid)
	grid.queue_free()


## Баг A на уровне сетки: после приёма пакета (reservation → файл) FileGrid
## обязан показать файл в _files/_by_id/_cells_owner, а не только в registry.
func _test_grid_confirmed_reservation(registry) -> void:
	_set_case("FileGrid confirmed reservation")
	var section = registry.sections.get("C", null)
	if section == null or section.folder_ids.size() < 2:
		_ok(false, "нужна вторая папка для проверки приёма")
		return
	var folder_id := str(section.folder_ids[1])
	var grid = FG.new()
	grid.name = "TestConfirmedGrid"
	grid.size = Vector2(558, 470)
	root.add_child(grid)
	await process_frame
	grid.set_folder(folder_id, "ВХОДЯЩИЕ", "C: \\ ВХОДЯЩИЕ")
	await process_frame
	_eq(grid.file_count(), 0, "папка приёма пуста")

	var res: Dictionary = registry.auto_reserve_packet("pkt_grid_reg", folder_id, "O4", 0)
	_ok(bool(res.get("ok", false)), "резервация пакета создана")
	_ok(registry.confirm_reservation("pkt_grid_reg", "Сетка 97", "video") != null,
		"резервация подтверждена в файл")
	await process_frame
	var folder = registry.get_folder(folder_id)
	var got = registry.find_by_name("Сетка 97")
	_ok(got != null, "файл в registry")
	if got == null:
		root.remove_child(grid)
		grid.queue_free()
		return
	_eq(grid.file_count(), 1, "файл сразу в _files сетки")
	_ok(grid._by_id.has(str(got.id)), "файл в _by_id сетки")
	_eq(str(grid._cells_owner.get(Vector2i(got.origin), "")), str(got.id),
		"клетка origin принадлежит файлу в _cells_owner")
	_eq(grid.stats()["occupied"], folder.cells.size(),
		"занятые клетки сетки = cells папки")

	# Второй пакет с другой формой/поворотом — сетка обновляется, ничего не теряется.
	var res2: Dictionary = registry.auto_reserve_packet("pkt_grid_reg_2", folder_id, "I4V", 0)
	_ok(bool(res2.get("ok", false)), "вторая резервация создана")
	_ok(registry.confirm_reservation("pkt_grid_reg_2", "Сетка 98", "video") != null,
		"вторая резервация подтверждена")
	await process_frame
	var got2 = registry.find_by_name("Сетка 98")
	_ok(got2 != null and grid._by_id.has(str(got2.id)),
		"второй принятый файл виден в сетке")
	_eq(grid.file_count(), 2, "в сетке оба принятых файла")
	_eq(registry.validate().size(), 0,
		"инварианты после приёма: %s" % str(registry.validate()))
	root.remove_child(grid)
	grid.queue_free()


## Поворот пользователя главнее: сначала requested, авто — только если не влез.
func _test_rotation_preference() -> void:
	_set_case("rotation preference")
	var grid = FG.new()
	grid.name = "TestRotationGrid"
	grid.size = Vector2(558, 470)
	root.add_child(grid)
	await process_frame
	grid._folder = null
	var payload := {"kind": "file", "id": "probe", "shape_id": "I4H",
		"rotation": 0, "from": "folder"}
	var exact: Dictionary = grid._resolve_placement(payload, Vector2i(0, 0), 0)
	_ok(bool(exact.get("ok", false)), "I4H влезает в (0,0) горизонтально")
	_eq(int(exact.get("rotation", -1)), 0, "выбранный поворот сохранён")
	_ok(not bool(exact.get("auto", true)), "без автоповорота auto = false")
	var turned: Dictionary = grid._resolve_placement(payload, Vector2i(4, 0), 0)
	_ok(bool(turned.get("ok", false)), "у правого края находится поворот")
	_eq(int(turned.get("rotation", -1)), 1, "авто-поворот выбрал вертикаль")
	_ok(bool(turned.get("auto", false)), "автоповорот помечен auto = true")
	var kept: Dictionary = grid._resolve_placement(payload, Vector2i(0, 0), 1)
	_eq(int(kept.get("rotation", -1)), 1, "requested=1 уважается, если влезает")
	root.remove_child(grid)
	grid.queue_free()


## Ghost и drop используют поворот из DragController, а не из payload.
func _test_ghost_rotation() -> void:
	_set_case("ghost rotation")
	var grid = FG.new()
	grid.name = "TestGhostGrid"
	grid.size = Vector2(558, 470)
	root.add_child(grid)
	await process_frame
	var dc = DC.new()
	dc.name = "TestGhostDragController"
	root.add_child(dc)
	await process_frame
	grid.drag_controller = dc
	var preview = FS.new()
	preview.setup("text", "I4H", 0, "Договор", "txt", 20.0)
	dc.begin(preview, "shape", 0)
	var payload := {"kind": "file", "id": "probe", "shape_id": "I4H",
		"rotation": 0, "from": "folder"}
	var pos: Vector2 = grid._cell_rect(4, 0).get_center()
	_ok(grid._can_drop_data(pos, payload), "can_drop у правого края")
	_eq(int(grid._ghost_rotation), 1, "ghost сам повернулся у края")
	_eq(int(grid._drag_rotation), 0, "requested поворот ещё 0")
	dc.set_rotation(1)
	_eq(int(grid._drag_rotation), 1, "rotation_changed обновил сетку")
	_eq(int(grid._ghost_rotation), 1, "ghost показывает выбранный поворот")
	_ok(not bool(grid._ghost_auto), "ручной поворот без auto")
	grid._can_drop_data(pos, payload)
	_eq(int(grid._drag_rotation), 1, "can_drop не сбрасывает поворот из payload")
	# Ghost обязан честно показывать каждый из 4 выбранных поворотов.
	var square_payload := {"kind": "file", "id": "probe2", "shape_id": "L3a",
		"rotation": 0, "from": "folder"}
	var center: Vector2 = grid._cell_rect(2, 2).get_center()
	for rot in 4:
		dc.set_rotation(rot)
		_ok(grid._can_drop_data(center, square_payload),
			"can_drop для поворота %d" % rot)
		_eq(int(grid._ghost_rotation), rot, "ghost показывает поворот %d" % rot)
		_eq(int(grid._drag_rotation), rot, "сетка приняла поворот %d" % rot)
	var expected_rot := int(grid._ghost_rotation)
	var dropped: Array = []
	grid.packet_dropped.connect(func(_p: Dictionary, _origin: Vector2i,
			rot: int) -> void: dropped.append(rot))
	grid._drop_data(pos, {"kind": "packet", "id": "p", "shape_id": "I4H",
		"rotation": 0, "from": "packet"})
	_eq(dropped.size(), 1, "drop пакета эмитится")
	if dropped.size() > 0:
		_eq(int(dropped[0]), expected_rot, "drop сохранил поворот ghost")
	dc.end()
	root.remove_child(grid)
	grid.queue_free()
	root.remove_child(dc)
	dc.queue_free()


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
	_eq(table.footer_text(), "24 клетки", "подвал пустого стола")
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
		_eq(table.footer_text(), "24 клетки", "подвал стола с файлом")
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

	var spin = FS.new()
	spin.setup("text", "I4H", 2, "Договор", "txt", 20.0)
	dc.begin(spin, "shape", 2)
	_ok(dc.is_active(), "is_active() при живом превью")
	_eq(dc.rotation(), 2, "begin(initial_rotation) сохраняет поворот")
	var r1: int = int(dc.rotate_cw())
	_eq(r1, 3, "rotate_cw() → 3")
	await process_frame
	_eq(int(dc.rotate_cw()), 0, "rotate_cw() 3 → 0 (posmod)")
	_eq(spin.shape_rotation, 0, "поворот сразу применяется к превью")
	dc.set_rotation(5)
	_eq(dc.rotation(), 1, "set_rotation нормализует 5 → 1")
	_eq(spin.shape_rotation, 1, "set_rotation обновляет превью")
	# Пакет (PacketCard) зовёт begin() без третьего аргумента — поворот
	# должен подхватиться из shape_rotation превью.
	var packet_preview = FS.new()
	packet_preview.setup("photo", "L3a", 3, "Пакет", "jpg", 20.0)
	dc.begin(packet_preview, "shape")
	_eq(dc.rotation(), 3, "пакет: поворот засеян из превью")
	dc.end()
	_eq(dc.rotation(), 0, "end() сбрасывает поворот")
	_ok(not dc.is_active(), "is_active() false без превью")
	root.remove_child(dc)
	dc.queue_free()


func _test_file_shape() -> void:
	_set_case("FileShape")
	_eq(FS.label_font_size(56.0), 12, "подпись < 72 px → 12")
	_eq(FS.label_font_size(71.9), 12, "подпись 71.9 px → 12")
	_eq(FS.label_font_size(72.0), 14, "подпись 72 px → 14")
	_eq(FS.label_font_size(96.0), 14, "подпись 96 px → 14")
	_eq(FS.label_font_size(96.1), 16, "подпись > 96 px → 16")
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
	_eq(tree.footer_text(), "2 папки · 2 файла",
		"подвал дерева: папки/файлы")
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
		_eq(folder_row.tooltip_text, "2 файла · 5 из 20 клеток",
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
		_eq(tree.footer_text(), "2 папки · 3 файла",
			"подвал после update_stats")
	root.remove_child(tree)
	tree.queue_free()


# --- helpers ---------------------------------------------------------------

## Подвал FileGrid v3: «N файлов · M клеток» (плюрализация клеток).
func _footer(stats: Dictionary) -> String:
	var total := int(stats.get("total", 0))
	var files := int(stats.get("files", 0))
	return "%d %s · %d %s" % [files, FG.plural_files(files), total,
		FG.plural_cells(total)]


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
