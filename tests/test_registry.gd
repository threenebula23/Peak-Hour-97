extends SceneTree
## Тесты реестра склада v2: сетка/фигуры/повороты/резервации/стол/миграция.
##
## Standalone:  godot --headless --path . --script tests/test_registry.gd
## Harness:     tests/run_tests.gd вызывает run(self) (t = раннер).

const R := preload("res://scripts/core/file_registry.gd")
const FI := preload("res://scripts/entities/file_item.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _grid_hits: int = 0


func _init() -> void:
	# При запуске раннером Engine.get_main_loop() уже существует — тесты
	# выполняет run(t) синхронно. При --script main loop ещё null.
	if Engine.get_main_loop() != null:
		return
	await process_frame
	run(self)
	print("test_registry: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_registry" if _fails == 0 else "FAIL test_registry")
	quit(0 if _fails == 0 else 1)


func run(t) -> void:
	_test_setup(t)
	_test_shapes(t)
	_test_auto_place(t)
	_test_place_collisions(t)
	_test_reservations(t)
	_test_table(t)
	_test_resize(t)
	_test_defrag(t)
	_test_consume_destroy(t)
	_test_save_roundtrip(t)
	_test_v1_migration(t)
	_test_v1_never_shrinks(t)
	_test_validate_catches_corruption(t)
	_test_signals(t)


# --- setup ------------------------------------------------------------------

func _test_setup(t) -> void:
	t.set_case("setup_new_run")
	var reg = R.new()
	reg.setup_new_run()
	t.eq(reg.sections.size(), 1, "одна стартовая секция")
	t.eq(reg.folders.size(), 2, "folders_start = 2 папки")
	t.eq(reg.files.size(), 0, "файлов нет")
	var section = reg.sections.get("C", null)
	t.ok(section != null, "секция C существует")
	if section != null:
		t.eq(section.folder_ids.size(), 2, "в секции C две папки")
	var first = _default_folder(reg)
	t.ok(first != null, "стартовая папка найдена")
	if first != null:
		t.eq(str(first.name), "Разное", "первая папка «Разное»")
		t.eq(int(first.cols), 5, "cols = 5")
		t.eq(int(first.rows), 4, "rows = 4")
		t.eq(first.total_cells(), 20, "20 клеток")
		t.eq(first.occupied_cell_count(), 0, "папка пуста")
		t.eq(first.free_cell_count(), 20, "свободно 20 клеток")
		t.eq(reg.table_cols, 4, "стол 4 колонки")
		t.eq(reg.table_rows, 6, "стол 6 строк")
		t.eq(reg.table_total_cells(), 24, "24 клетки стола")


# --- фигуры -----------------------------------------------------------------

func _test_shapes(t) -> void:
	t.set_case("shapes")
	var o1 := R.shape_cells("O1", 0)
	t.eq(o1.size(), 1, "O1 — 1 клетка")
	t.eq(R.shape_bounds(o1), Vector2i(1, 1), "O1 bounds 1x1")

	var i2h := R.shape_cells("I2H", 1)
	t.eq(i2h.size(), 2, "I2H rot1 — 2 клетки")
	t.eq(R.shape_bounds(i2h), Vector2i(1, 2), "I2H rot1 → вертикаль")
	t.ok(i2h.has(Vector2i(0, 0)) and i2h.has(Vector2i(0, 1)), "I2H rot1 клетки")

	var i2v := R.shape_cells("I2V", 1)
	t.eq(R.shape_bounds(i2v), Vector2i(2, 1), "I2V rot1 → горизонталь")
	var i2v4 := R.shape_cells("I2V", 4)
	t.eq(_sorted_cells(i2v4), _sorted_cells(R.shape_cells("I2V", 0)), "поворот 4 = 0")

	var t4c := R.shape_cells("T4c", 0)
	t.eq(t4c.size(), 4, "T4c — 4 клетки")
	t.eq(R.shape_bounds(t4c), Vector2i(2, 3), "T4c bounds 2x3")

	t.eq(R.label_cell(R.shape_cells("S4", 0)), Vector2i(1, 0), "S4: подпись в (1,0), не пустой угол")
	t.eq(R.label_cell(R.shape_cells("Z4", 0)), Vector2i(0, 0), "Z4: подпись в (0,0)")
	t.eq(R.label_cell(R.shape_cells("O1", 0)), Vector2i(0, 0), "1x1: подпись = клетка")

	# Все формы: 4 поворота, клетки в норме (min = 0), число клеток сохраняется.
	for shape_id in ["O1", "I2H", "I2V", "I3H", "I3V", "L3a", "L3b", "L3c", "L3d",
			"I4H", "I4V", "O4", "T4a", "T4b", "T4c", "T4d",
			"L4a", "L4b", "L4c", "L4d", "J4a", "J4b", "J4c", "J4d", "S4", "Z4"]:
		var base := R.shape_cells(shape_id, 0)
		for rot in range(4):
			var cells := R.shape_cells(shape_id, rot)
			t.eq(cells.size(), base.size(), "%s rot%d: число клеток" % [shape_id, rot])
			t.ok(_min_cell_axis(cells, 0) == 0 and _min_cell_axis(cells, 1) == 0,
				"%s rot%d: нормализовано" % [shape_id, rot])

	# Формы по типу из данных/фолбэка.
	t.eq(R.cells_for_type("text"), 1, "text = 1 клетка")
	t.eq(R.cells_for_type("sound"), 2, "sound = 2 клетки")
	t.eq(R.cells_for_type("photo"), 3, "photo = 3 клетки")
	t.eq(R.cells_for_type("video"), 4, "video = 4 клетки")
	t.ok(R.shape_ids_for_type("sound").size() >= 2, "sound: несколько форм")
	t.ok(R.shape_ids_for_type("photo").size() >= 2, "photo: несколько форм")
	t.ok(R.shape_ids_for_type("video").size() >= 7, "video: тетромино-набор")

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var picked := R.shape_for_type("video", rng_a)
	t.ok(R.shape_ids_for_type("video").has(picked), "shape_for_type вернул форму из набора")
	t.eq(R.shape_for_type("video", rng_b), picked, "shape_for_type детерминирован по сиду")
	t.eq(R.shape_cells(picked, 0).size(), 4, "видео-форма = 4 клетки")


# --- auto-place -------------------------------------------------------------

func _test_auto_place(t) -> void:
	t.set_case("auto_place")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)

	# 4 горизонтальных видео (4x1) занимают колонки 0..3 в каждой строке.
	for i in range(4):
		var f = _add_shape(reg, "Video %d" % i, "video", "I4H")
		t.ok(reg.place_file(f.id, fid, Vector2i(0, i), 0), "видео %d размещено" % i)
	t.eq(folder.occupied_cell_count(), 16, "занято 16 клеток")

	# Осталась колонка 4 (4 клетки); домино I2V влезает.
	var domino = _add_shape(reg, "Domino", "sound", "I2V")
	t.ok(reg.auto_place_file(domino.id, fid), "auto-place домино")
	t.eq(domino.origin, Vector2i(4, 0), "домино встало в первую свободную клетку")
	t.eq(folder.occupied_cell_count(), 18, "занято 18")

	# Текст (1 клетка) — в (4,2), затем (4,3).
	var text_a = reg.create_file("Text A", "text", fid)
	t.ok(text_a != null, "текст создан")
	if text_a != null:
		t.eq(text_a.origin, Vector2i(4, 2), "первый текст в (4,2)")
	var text_b = reg.create_file("Text B", "text", fid)
	t.ok(text_b != null, "второй текст создан")
	if text_b != null:
		t.eq(text_b.origin, Vector2i(4, 3), "второй текст в (4,3)")
	t.eq(folder.free_cell_count(), 0, "папка заполнена")
	t.ok(reg.create_file("Overflow", "text", fid) == null, "21-й файл не создаётся (нет клеток)")
	t.eq(reg.files.size(), 7, "новый файл не появился в реестре")

	# auto-place учитывает поворот: вертикальное I4V в полосу высотой 4.
	var reg2 = R.new()
	reg2.setup_new_run()
	var f2 = _default_folder(reg2)
	var v = _add_shape(reg2, "Vertical", "video", "I4V")
	t.ok(reg2.auto_place_file(v.id, f2.id), "вертикальное видео auto")
	t.eq(v.origin, Vector2i(0, 0), "вертикальное видео в (0,0)")


# --- коллизии/поворот -------------------------------------------------------

func _test_place_collisions(t) -> void:
	t.set_case("collisions")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)
	var a = reg.create_file("A", "text", fid)
	t.ok(a != null, "A создан")
	var b = _add_shape(reg, "B", "text", "O1")
	t.ok(not reg.place_file(b.id, fid, a.origin, 0), "точное размещение на занятую клетку запрещено")
	t.ok(not reg.place_file(b.id, fid, Vector2i(5, 0), 0), "выход за правую границу запрещён")
	t.ok(not reg.place_file(b.id, fid, Vector2i(0, 4), 0), "выход за нижнюю границу запрещён")
	t.ok(reg.place_file(b.id, fid, Vector2i(1, 1), 0), "свободная клетка разрешена")
	t.eq(reg.file_origin(b.id), Vector2i(1, 1), "origin B")
	t.eq(reg.file_label_cell(b.id), Vector2i(1, 1), "label B")

	var photo = _add_shape(reg, "Photo", "photo", "I3H")
	t.ok(reg.place_file(photo.id, fid, Vector2i(2, 1), 1), "I3H rot1 (вертикаль) размещён")
	t.eq(R.shape_bounds(reg.file_shape_cells(photo.id)), Vector2i(1, 3), "повёрнутая форма вертикальна")
	t.eq(reg.file_rotation(photo.id), 1, "rotation сохранён")
	t.ok(not reg.place_file(photo.id, fid, Vector2i(4, 2), 1), "вертикаль не влезает по высоте")
	t.ok(reg.place_file(photo.id, fid, Vector2i(4, 1), 1), "перемещение в (4,1) rot1")
	t.eq(reg.file_origin(photo.id), Vector2i(4, 1), "origin после перемещения")


# --- резервации -------------------------------------------------------------

func _test_reservations(t) -> void:
	t.set_case("reservations")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)

	t.ok(reg.reserve_packet("pkt_1", fid, "O4", 0, Vector2i(0, 0)), "резервация O4 (0,0)")
	t.eq(reg.reservation_count(fid), 1, "одна резервация")
	t.ok(folder.cell_occupied(0, 0), "cell_occupied(0,0) true для резервации (M14)")
	t.ok(folder.cell_occupied(1, 1), "cell_occupied(1,1) true для резервации (M14)")
	t.ok(folder.is_reserved_cell(0, 0), "is_reserved_cell")
	t.eq(folder.occupied_cell_count(), 4, "резервация занимает 4 клетки")
	t.eq(folder.free_cell_count(), 16, "свободно 16")

	# Файл нельзя положить на зарезервированную клетку.
	var probe = _add_shape(reg, "Probe", "text", "O1")
	t.ok(not reg.place_file(probe.id, fid, Vector2i(1, 1), 0), "файл не встаёт на reserved-клетку")
	t.ok(not reg.can_place(folder, "O1", Vector2i(0, 0), 0), "can_place на reserved — false")

	var auto := reg.auto_reserve_packet("pkt_2", fid, "I2H", 0)
	t.ok(bool(auto.get("ok", false)), "auto_reserve_packet успешен")
	t.ok(folder.cells.size() == 6, "две резервации занимают 6 клеток")
	var res1 := reg.get_reservation("pkt_1")
	t.ok(bool(res1.get("ok", false)), "get_reservation pkt_1")
	t.eq(res1.get("origin", Vector2i(-1, -1)), Vector2i(0, 0), "origin резервации")

	# Приём: резервация превращается в файл на тех же клетках.
	var got = reg.confirm_reservation("pkt_1", "Принятый", "video")
	t.ok(got != null, "confirm_reservation создал файл")
	if got != null:
		t.eq(got.origin, Vector2i(0, 0), "файл на месте резервации")
		t.eq(got.shape_id, "O4", "форма из резервации")
		t.eq(str(got.location), "folder", "location folder")
		t.ok(folder.file_ids.has(got.id), "файл в папке")
		t.eq(folder.owner_at(0, 0), got.id, "клетка принадлежит файлу")
	t.eq(reg.reservation_count(fid), 1, "после confirm осталась одна резервация")
	t.ok(not reg.confirm_reservation("pkt_nope", "Нет", "text"), "confirm без резервации — null")

	var got2 = reg.confirm_reservation("pkt_2", "Принятый", "sound")
	t.ok(got2 == null, "confirm с дублем имени — null")
	t.eq(reg.reservation_count(fid), 1, "резервация сохранена при ошибке имени")

	t.ok(reg.cancel_reservation("pkt_2"), "cancel_reservation")
	t.eq(reg.reservation_count(fid), 0, "резерваций нет")
	t.ok(not folder.cell_occupied(2, 0), "клетки резервации освобождены")
	t.ok(not reg.cancel_reservation("pkt_2"), "повторный cancel — false")

	# Приём не должен занимать клетки существующего файла.
	var card = reg.create_file("Card", "text", fid)
	t.ok(not reg.reserve_packet("pkt_3", fid, "O1", 0, card.origin), "резервация на файл запрещена")
	var auto2 := reg.auto_reserve_packet("pkt_4", fid, "O4", 0)
	t.ok(bool(auto2.get("ok", false)), "auto_reserve учитывает файлы")


# --- стол -------------------------------------------------------------------

func _test_table(t) -> void:
	t.set_case("table")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)
	var file = _add_shape(reg, "Table file", "video", "O4")
	t.ok(reg.place_file(file.id, fid, Vector2i(0, 0), 0), "файл в папке")
	var folder_free: int = folder.free_cell_count()

	t.ok(reg.move_file_to_table(file.id), "move_file_to_table")
	t.eq(str(file.location), "table", "location table")
	t.eq(reg.table_occupied_cells(), 4, "стол занят 4 клетки")
	t.eq(reg.table_free_cells(), 20, "стол свободен 20")
	t.eq(folder.free_cell_count(), folder_free + 4, "клетки папки освободились")
	t.ok(reg.is_table_file(file.id), "is_table_file")
	t.ok(not folder.file_ids.has(file.id), "стол-файл не в folder.file_ids")
	t.ok(not reg.get_available_files(1000.0).has(file), "стол-файл недоступен для attach")
	t.ok(not reg.attach_file(file.id, "req_1", 1000.0), "attach со стола отклонён")

	# Точная позиция на столе + возврат в папку.
	t.ok(reg.move_file_to_table(file.id, Vector2i(1, 2), 1), "точное перемещение по столу")
	t.eq(reg.file_origin(file.id), Vector2i(1, 2), "origin на столе")
	t.eq(reg.file_rotation(file.id), 1, "rotation на столе")
	t.ok(reg.move_from_table(file.id), "move_from_table")
	t.eq(str(file.location), "folder", "location folder после возврата")
	t.eq(reg.table_occupied_cells(), 0, "стол пуст")
	t.eq(file.origin, Vector2i(0, 0), "auto-place в папке после возврата")

	# auto_return_table.
	var f2 = _add_shape(reg, "Table 2", "photo", "I3H")
	t.ok(reg.place_file(f2.id, fid, Vector2i(2, 2), 0), "второй файл")
	t.ok(reg.move_file_to_table(f2.id), "второй на стол")
	var f3 = _add_shape(reg, "Table 3", "sound", "I2H")
	t.ok(reg.place_file(f3.id, fid, Vector2i(0, 3), 0), "третий файл")
	t.ok(reg.move_file_to_table(f3.id), "третий на стол")
	t.eq(reg.table_file_count(), 2, "два файла на столе")
	t.ok(reg.auto_return_table(), "auto_return_table успешен")
	t.eq(reg.table_file_count(), 0, "стол пуст после auto_return")
	t.eq(reg.validate().size(), 0, "инварианты после стола: %s" % str(reg.validate()))

	# Заполненный стол.
	var reg2 = R.new()
	reg2.setup_new_run()
	var table_full := 0
	for i in range(24):
		var tf = reg2.create_file("T %02d" % i, "text", "", &"table")
		if tf != null:
			table_full += 1
	t.eq(table_full, 24, "24 текста заняли весь стол")
	t.ok(reg2.create_file("T 25", "text", "", &"table") == null, "25-й файл на стол не влезает")

	# Мягкий сценарий: папки полны, файл со стола вернуть некуда.
	var reg3 = R.new()
	reg3.setup_new_run()
	var f3a = _default_folder(reg3)
	var second_id := _folder_id_at(reg3, 1)
	for i in range(20):
		reg3.create_file("A %02d" % i, "text", f3a.id)
		reg3.create_file("B %02d" % i, "text", second_id)
	t.eq(f3a.free_cell_count(), 0, "первая папка полна")
	var stranded = reg3.create_file("Stranded", "text", "", &"table")
	t.ok(stranded != null, "файл на столе создан")
	t.ok(not reg3.auto_return_table(), "auto_return false, если места нет")
	t.eq(str(stranded.location), "table", "файл остался на столе (без потери)")


# --- resize -----------------------------------------------------------------

func _test_resize(t) -> void:
	t.set_case("resize")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)
	var a = _add_shape(reg, "R1", "video", "O4")
	t.ok(reg.place_file(a.id, fid, Vector2i(3, 2), 0), "файл до роста")
	reg.resize_folders(Vector2i(6, 4))
	t.eq(folder.cols, 6, "cols вырос до 6")
	t.eq(folder.rows, 4, "rows остался 4")
	t.eq(folder.total_cells(), 24, "24 клетки после роста")
	t.eq(a.origin, Vector2i(3, 2), "origin сохранён при росте")
	t.eq(reg.file_shape_cells(a.id).size(), 4, "форма на месте")
	t.ok(reg.can_place(folder, "O4", Vector2i(4, 0), 0), "новая колонка свободна")

	reg.resize_folders(Vector2i(4, 3))
	t.eq(folder.cols, 6, "сетка не уменьшается (cols)")
	t.eq(folder.rows, 4, "сетка не уменьшается (rows)")


# --- defrag -----------------------------------------------------------------

func _test_defrag(t) -> void:
	t.set_case("defrag")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)
	var positions := [Vector2i(4, 3), Vector2i(3, 3), Vector2i(2, 3), Vector2i(0, 2)]
	var files: Array = []
	for i in range(positions.size()):
		var f = _add_shape(reg, "D %d" % i, "text", "O1")
		t.ok(reg.place_file(f.id, fid, positions[i], 0), "файл %d размещён вручную" % i)
		files.append(f)
	t.eq(folder.occupied_cell_count(), 4, "4 занятые клетки")
	t.ok(reg.defrag_folder(fid), "defrag_folder успешен")
	t.eq(folder.occupied_cell_count(), 4, "после defrag те же 4 клетки")
	var labels := {}
	for f in files:
		labels[f.origin] = true
	for i in range(4):
		t.ok(labels.has(Vector2i(i, 0)), "первый ряд упакован: (i,0)")
	t.eq(reg.validate().size(), 0, "инварианты после defrag")


# --- расход/удаление --------------------------------------------------------

func _test_consume_destroy(t) -> void:
	t.set_case("consume")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)
	var file = reg.create_file("Consume me", "text", fid)
	t.ok(reg.attach_file(file.id, "req_1", 1000.0), "файл прикреплён")
	var free_before: int = folder.free_cell_count()
	t.ok(reg.consume_file(file.id), "consume_file для attached")
	t.ok(not reg.files.has(file.id), "файл удалён из реестра")
	t.ok(not folder.file_ids.has(file.id), "файл убран из папки")
	t.eq(folder.free_cell_count(), free_before + 1, "клетка освобождена")
	t.ok(not reg.consume_file("file_nope"), "consume несуществующего — false")

	var normal = reg.create_file("Normal", "text", fid)
	t.ok(not reg.remove_file(normal.id), "обычный remove_file запрещён")
	t.ok(reg.destroy_file(normal.id), "destroy_file(force) разрешён (M16)")
	t.ok(not reg.files.has(normal.id), "уничтоженный файл удалён")

	var attached = reg.create_file("Attached", "text", fid)
	reg.attach_file(attached.id, "req_2", 1000.0)
	t.ok(not reg.destroy_file(attached.id), "attached нельзя уничтожить")

	var failed = reg.create_file("Failed", "text", fid)
	reg.mark_failed(failed.id)
	t.ok(reg.remove_file(failed.id), "failed удаляется старым путём")
	t.eq(reg.validate().size(), 0, "инварианты после удалений")


# --- save/load v2 -----------------------------------------------------------

func _test_save_roundtrip(t) -> void:
	t.set_case("save_roundtrip")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var fid := str(folder.id)
	var a = _add_shape(reg, "A", "text", "O1")
	var b = _add_shape(reg, "B", "photo", "I3H")
	var c = _add_shape(reg, "C", "video", "O4")
	t.ok(reg.place_file(a.id, fid, Vector2i(0, 0), 0), "A (0,0)")
	t.ok(reg.place_file(b.id, fid, Vector2i(2, 0), 0), "B (2,0)")
	t.ok(reg.place_file(c.id, fid, Vector2i(0, 2), 0), "C (0,2) rot0")
	t.ok(reg.move_file(c.id, fid, Vector2i(3, 2), 1), "C rot1 (3,2)")
	var d = _add_shape(reg, "D", "sound", "I2V")
	t.ok(reg.move_file_to_table(d.id, Vector2i(1, 1), 1), "D на столе rot1")
	t.ok(reg.reserve_packet("pkt_r", fid, "O1", 0, Vector2i(0, 1)), "резервация перед save")

	var data: Dictionary = reg.to_dict()
	var folder_raw: Dictionary = data.get("folders", {}).get(fid, {})
	t.eq(int(folder_raw.get("cols", 0)), 5, "save: cols")
	t.eq(int(folder_raw.get("rows", 0)), 4, "save: rows")
	var placements: Array = folder_raw.get("files", [])
	t.eq(placements.size(), 3, "save: 3 placement в папке")
	var meta: Dictionary = data.get("files", {}).get(c.id, {})
	t.ok(not meta.has("origin"), "save: в files нет origin (M12)")
	t.eq(str(meta.get("shape_id", "")), "O4", "save: shape_id в метаданных")
	t.eq((data.get("table", []) as Array).size(), 1, "save: один файл на столе")

	var reg2 = R.new()
	t.ok(reg2.from_dict(data), "from_dict v2")
	t.eq(reg2.files.size(), reg.files.size(), "файлы восстановлены")
	t.eq(reg2.folders.size(), reg.folders.size(), "папки восстановлены")
	var folder2 = reg2.folders.get(fid, null)
	t.ok(folder2 != null, "папка восстановлена")
	if folder2 != null:
		t.eq(int(folder2.cols), 5, "cols восстановлены")
		t.eq(int(folder2.rows), 4, "rows восстановлены")
	t.eq(reg2.file_origin(a.id), Vector2i(0, 0), "A origin сохранён")
	t.eq(reg2.file_origin(b.id), Vector2i(2, 0), "B origin сохранён")
	t.eq(reg2.file_origin(c.id), Vector2i(3, 2), "C origin сохранён")
	t.eq(reg2.file_rotation(c.id), 1, "C rotation сохранён")
	t.eq(reg2.file_shape_cells(c.id), reg.file_shape_cells(c.id), "C клетки после поворота")
	t.eq(str(reg2.get_file(d.id).location), "table", "D на столе после load")
	t.eq(reg2.file_origin(d.id), Vector2i(1, 1), "D origin на столе")
	t.eq(reg2.file_rotation(d.id), 1, "D rotation на столе")
	t.eq(reg2.reservation_count(fid), 1, "резервация восстановлена")
	t.eq(reg2.validate().size(), 0, "инварианты после load: %s" % str(reg2.validate()))

	var fresh = reg2.create_file("Fresh", "text", fid)
	t.ok(fresh != null, "create_file после load")
	t.eq(reg2.validate().size(), 0, "инварианты после нового файла")
	t.eq(reg2.files.size(), 5, "id не пересекается со старыми")


# --- миграция v1 ------------------------------------------------------------

func _test_v1_migration(t) -> void:
	t.set_case("v1_migration")
	var v1 := _make_v1_payload(16, "text", "v1")
	var reg = R.new()
	t.ok(reg.from_dict(v1), "v1 принят")
	var folder_id := "fold_1"
	t.eq(reg.files.size(), 16, "все 16 файлов мигрированы")
	var folder = reg.folders.get(folder_id, null)
	t.ok(folder != null, "папка v1 восстановлена")
	if folder != null:
		t.eq(folder.file_ids.size(), 16, "файлы разложены")
		t.eq(folder.cols, 5, "cols по текущей сетке")
		t.eq(folder.rows, 4, "rows по текущей сетке")
		t.ok(folder.total_cells() >= 16, "ёмкость не меньше старых 16 файлов")
	for file in reg.files.values():
		t.ok(not str(file.shape_id).is_empty(), "shape_id назначен: %s" % file.id)
		t.eq(R.shape_cells(file.shape_id, file.rotation).size(), 1, "text-форма = 1 клетка")
	t.eq(reg.validate().size(), 0, "инварианты миграции: %s" % str(reg.validate()))

	# Детерминированность форм при миграции.
	var reg_b = R.new()
	reg_b.from_dict(v1)
	for fid in reg.files.keys():
		t.eq(str(reg_b.files[fid].shape_id), str(reg.files[fid].shape_id), "форма детерминирована: %s" % fid)
		t.eq(reg_b.files[fid].origin, reg.files[fid].origin, "позиция детерминирована: %s" % fid)

	# v1состояния: attached/locked/registry.
	var v1b := _make_v1_payload(2, "text", "state")
	v1b["files"]["file_1"]["location"] = "attached"
	v1b["files"]["file_1"]["attached_request"] = "req_9"
	v1b["files"]["file_2"]["location"] = "registry"
	v1b["files"]["file_2"]["folder_id"] = ""
	v1b["folders"]["fold_1"]["file_ids"] = ["file_1"]
	var reg_states = R.new()
	t.ok(reg_states.from_dict(v1b), "v1 со состояниями принят")
	t.eq(str(reg_states.files["file_1"].location), "attached", "attached сохранён")
	t.eq(str(reg_states.files["file_1"].attached_request), "req_9", "attached_request сохранён")
	t.eq(str(reg_states.files["file_2"].location), "registry", "registry сохранён")
	t.eq(reg_states.validate().size(), 0, "инварианты v1-состояний")

	# v1: folder_id только на файлах, без folder.file_ids.
	var v1c := _make_v1_payload(3, "photo", "only")
	v1c["folders"]["fold_1"].erase("file_ids")
	var reg_only = R.new()
	t.ok(reg_only.from_dict(v1c), "v1 без folder.file_ids принят")
	t.eq(reg_only.files.size(), 3, "файлы не потеряны")
	var only_folder = reg_only.folders.get("fold_1", null)
	if only_folder != null:
		t.eq(only_folder.file_ids.size(), 3, "placements восстановлены по folder_id файла")
	t.eq(reg_only.validate().size(), 0, "инварианты v1 без file_ids")


func _test_v1_never_shrinks(t) -> void:
	t.set_case("v1_never_shrinks")
	# 16 sound-файлов = 32 клетки: 5x4 мало, папка должна вырасти.
	var v1 := _make_v1_payload(16, "sound", "grow")
	var reg = R.new()
	t.ok(reg.from_dict(v1), "v1 sound принят")
	var folder = reg.folders.get("fold_1", null)
	t.ok(folder != null, "папка есть")
	if folder != null:
		t.ok(folder.total_cells() >= 32, "сетка выросла под 16 sound (%d клеток)" % folder.total_cells())
		t.ok(folder.cols >= 5 and folder.rows >= 4, "рост только вверх")
		t.eq(folder.file_ids.size(), 16, "все 16 sound разложены")
	t.eq(reg.files.size(), 16, "файлы не потеряны")
	t.eq(reg.validate().size(), 0, "инварианты после роста: %s" % str(reg.validate()))

	# Уже большая папка не уменьшается.
	var v1_big := _make_v1_payload(3, "text", "big")
	v1_big["folders"]["fold_1"]["cols"] = 7
	v1_big["folders"]["fold_1"]["rows"] = 5
	var reg2 = R.new()
	t.ok(reg2.from_dict(v1_big), "v2-подобная папка 7x5 принята")
	var big = reg2.folders.get("fold_1", null)
	if big != null:
		t.ok(big.cols >= 7 and big.rows >= 5, "7x5 не уменьшилась")


# --- валидация --------------------------------------------------------------

func _test_validate_catches_corruption(t) -> void:
	t.set_case("validate")
	var reg = R.new()
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var file = reg.create_file("V", "text", folder.id)
	t.eq(reg.validate().size(), 0, "чистый реестр валиден")

	folder.cells[Vector2i(4, 3)] = "ghost"
	t.ok(reg.validate().size() > 0, "лишняя клетка обнаружена")
	folder.cells.erase(Vector2i(4, 3))

	var backup: Vector2i = file.origin
	file.origin = Vector2i(9, 9)
	t.ok(reg.validate().size() > 0, "выход за границы обнаружен")
	file.origin = backup

	# Пересечение при загрузке чинится, а не остаётся.
	var other = reg.create_file("W", "text", folder.id)
	var data: Dictionary = reg.to_dict()
	var folder_raw: Dictionary = data["folders"][folder.id]
	var files_arr: Array = folder_raw["files"]
	files_arr.append({
		"id": other.id,
		"shape_id": "O1",
		"origin": [backup.x, backup.y],
		"rotation": 0,
	})
	folder_raw["files"] = files_arr
	var reg2 = R.new()
	t.ok(reg2.from_dict(data), "данные с пересечением загружены")
	t.eq(reg2.validate().size(), 0, "пересечение при load разрешено: %s" % str(reg2.validate()))


# --- сигналы ----------------------------------------------------------------

func _test_signals(t) -> void:
	t.set_case("signals")
	_grid_hits = 0
	var reg = R.new()
	reg.grid_changed.connect(_on_grid_changed)
	reg.registry_changed.connect(_on_registry_changed)
	reg.setup_new_run()
	var folder = _default_folder(reg)
	var file = reg.create_file("Signal", "text", folder.id)
	t.ok(_grid_hits >= 1, "grid_changed при создании файла")
	reg.move_file(file.id, folder.id, Vector2i(2, 2), 0)
	t.ok(_grid_hits >= 2, "grid_changed при перемещении")


func _on_grid_changed(_folder_id) -> void:
	_grid_hits += 1


func _on_registry_changed() -> void:
	pass


# --- assert-хелперы ---------------------------------------------------------

func set_case(name: String) -> void:
	_case = name


func ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	fail(message + " — ожидалось true")
	return false


func eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	fail("%s — получено %s, ожидалось %s" % [message, _fmt(actual), _fmt(expected)])
	return false


func ne(actual, unexpected, message: String) -> bool:
	_checks += 1
	if actual != unexpected:
		return true
	fail("%s — получено %s, не ожидалось %s" % [message, _fmt(actual), _fmt(unexpected)])
	return false


func approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return true
	fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _fmt(value) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % str(value)
	return str(value)


# --- утилиты ----------------------------------------------------------------

func _default_folder(reg):
	var section = reg.sections.get("C", null)
	if section == null or section.folder_ids.is_empty():
		return null
	return reg.folders.get(str(section.folder_ids[0]), null)


func _folder_id_at(reg, index: int) -> String:
	var section = reg.sections.get("C", null)
	if section == null or index >= section.folder_ids.size():
		return ""
	return str(section.folder_ids[index])


## Файл-метаданные без размещения (shape задаётся вручную для теста).
func _add_shape(reg, name: String, type: String, shape_id: String):
	var file = reg.create_file(name, type, "", &"registry")
	if file == null:
		return null
	file.shape_id = shape_id
	file.shape_cells = R.shape_cells(shape_id, 0)
	file.rotation = 0
	return file


func _sorted_cells(cells: Array) -> Array:
	var out: Array = []
	for cell in cells:
		out.append(Vector2i(cell))
	out.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


func _min_cell_axis(cells: Array, axis: int) -> int:
	var best := 2147483647
	for cell in cells:
		var v := Vector2i(cell)
		best = mini(best, v.x if axis == 0 else v.y)
	return best


## Синтетический v1-сейв: плоские folder.file_ids + files[*].folder_id.
func _make_v1_payload(count: int, type: String, prefix: String) -> Dictionary:
	var file_ids: Array = []
	var raw_files := {}
	var ext := "txt"
	if type == "sound":
		ext = "mp3"
	if type == "photo":
		ext = "jpg"
	if type == "video":
		ext = "mp4"
	for i in range(count):
		var fid := "file_%d" % (i + 1)
		file_ids.append(fid)
		raw_files[fid] = {
			"id": fid,
			"name": "%s %02d" % [prefix, i],
			"ext": ext,
			"type": type,
			"folder_id": "fold_1",
			"location": "folder",
			"attached_request": "",
			"malicious_kind": "",
			"lock_until": 0.0,
			"cooldown_until": 0.0,
			"size_kb": 1,
			"created_at": 0.0,
		}
	return {
		"rng_seed": 4242,
		"next_folder_id": 2,
		"next_file_id": count + 1,
		"sections": {
			"C": {"id": "C", "letter": "C", "name": "Секция C", "folder_ids": ["fold_1"]},
		},
		"folders": {
			"fold_1": {
				"id": "fold_1",
				"section": "C",
				"name": "Разное",
				"file_ids": file_ids,
			},
		},
		"files": raw_files,
	}
