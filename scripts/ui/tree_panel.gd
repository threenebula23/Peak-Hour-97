class_name TreePanel
extends Control
## Дерево дисков и папок: светлая поверхность, строки 24 px, скролл 14 px,
## кнопка «Новая папка» и контекстное меню по правой кнопке.

signal folder_selected(folder_id: String)
signal file_dropped(folder_id: String, payload: Dictionary)
signal packet_dropped(folder_id: String, payload: Dictionary)
signal context_menu_requested(folder_id: String, global_pos: Vector2)
signal new_folder_requested
signal hover_open_requested(folder_id: String)

var _view: Control
var _content: Control
var _bar: ScrollBar90
var _new_btn: Button90
var _rows: Array[Dictionary] = []
var _selected := ""
var _drag: Node = null
var _folder_price := 0
var _price_known := false
var _price_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view = Control.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_PASS
	_view.clip_contents = true
	add_child(_view)

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_view.add_child(_content)

	_bar = ScrollBar90.new()
	_bar.name = "Scroll"
	add_child(_bar)
	_bar.value_changed.connect(_on_scroll)

	_new_btn = Button90.new()
	_new_btn.name = "NewFolderButton"
	_new_btn.caption = "НОВАЯ ПАПКА"
	_new_btn.icon = Button90.Icon.PLUS
	_new_btn.caption_size = Theme90.FS_BODY
	add_child(_new_btn)
	_new_btn.pressed.connect(func() -> void:
		_pulse_new_button()
		new_folder_requested.emit())
	_set_price_caption(0)

	resized.connect(_relayout)
	_relayout()
	call_deferred("_bind_drag_controller")
	set_process(true)


func _view_rect() -> Rect2:
	return Rect2(2, 2, maxf(0.0, size.x - 18.0), maxf(0.0, size.y - 48.0))


func _footer_rect() -> Rect2:
	return Rect2(2, size.y - 44.0, maxf(0.0, size.x - 4.0), 14.0)


func _relayout() -> void:
	if _view == null:
		return
	var vr := _view_rect()
	_view.position = vr.position
	_view.size = vr.size
	_bar.position = Vector2(size.x - 16.0, vr.position.y + 4.0)
	_bar.size = Vector2(Theme90.SCROLLBAR, maxf(8.0, vr.size.y - 8.0))
	_bar.set_metrics(vr.size.y, maxf(vr.size.y, _content_height()))
	_new_btn.position = Vector2(4, size.y - 27.0)
	_new_btn.size = Vector2(size.x - 8.0, 24.0)
	_apply_layout()
	queue_redraw()


func _content_height() -> float:
	var y := 0.0
	for e in _rows:
		var row: FolderRow = e["row"]
		var vis: bool = e["visible"]
		if vis:
			y += row.custom_minimum_size.y
	return maxf(y + 2.0, 0.0)


## sections: [{id, name, free|free_cells, folders: [
##   {id, name, count|occupied_cells, capacity|total_cells, files, locked}]}]
func set_data(sections: Array) -> void:
	for c in _content.get_children():
		c.queue_free()
	_rows.clear()
	for sec in sections:
		var sid: String = str(sec.get("id", ""))
		var srow := FolderRow.new()
		srow.setup(sid, str(sec.get("name", "")), 0, true)
		srow.free_text = _section_free_text(sec)
		srow.custom_minimum_size = Vector2(0, FolderRow.SECTION_H)
		srow.expanded = true
		srow.expansion_toggled.connect(_on_toggle)
		srow.folder_selected.connect(_on_section_clicked)
		srow.context_menu_requested.connect(_on_context)
		_content.add_child(srow)
		_rows.append({"row": srow, "section": sid, "visible": true})
		for fol in sec.get("folders", []):
			var frow := FolderRow.new()
			var fid: String = str(fol.get("id", ""))
			frow.setup(fid, str(fol.get("name", "")), 1, false)
			frow.count = _folder_occupied(fol)
			frow.capacity = _folder_total(fol)
			frow.files_count = _folder_files(fol)
			frow.tooltip_text = _folder_tooltip(frow.files_count, frow.count, frow.capacity)
			frow.locked = bool(fol.get("locked", false))
			frow.custom_minimum_size = Vector2(0, FolderRow.ROW_H)
			frow.folder_selected.connect(_on_folder_clicked)
			frow.expansion_toggled.connect(_on_toggle)
			frow.file_dropped.connect(_on_drop)
			frow.packet_dropped.connect(_on_packet_drop)
			frow.context_menu_requested.connect(_on_context)
			frow.hover_open_requested.connect(_on_row_hover_open)
			_content.add_child(frow)
			_rows.append({"row": frow, "section": sid, "visible": true})
	_apply_layout()
	_relayout()
	if not _selected.is_empty():
		select_folder(_selected)
	call_deferred("_bind_drag_controller")


func _plural_folders(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "папка"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "папки"
	return "папок"


func _plural_files(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "файл"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "файла"
	return "файлов"


func _plural_cells(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "клетка"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "клетки"
	return "клеток"


func _section_free_text(sec: Dictionary) -> String:
	var raw = sec.get("free_text", null)
	if raw is String:
		return str(raw)
	var cells_raw = sec.get("free_cells", sec.get("free", null))
	if cells_raw is int or cells_raw is float:
		var free_cells := int(cells_raw)
		return "свободно %d %s" % [free_cells, _plural_cells(free_cells)]
	if cells_raw is String:
		return str(cells_raw)
	return ""


func _folder_occupied(fol: Dictionary) -> int:
	return _pick_int(fol, ["occupied_cells", "occupied", "count_cells", "count"], 0)


func _folder_total(fol: Dictionary) -> int:
	var total := _pick_int(fol, ["total_cells", "cells_total", "capacity"], 16)
	return total if total > 0 else 16


func _folder_files(fol: Dictionary) -> int:
	return _pick_int(fol, ["files", "file_count", "count"], 0)


func _pick_int(fol: Dictionary, keys: Array, fallback: int) -> int:
	for key in keys:
		var value = fol.get(key, null)
		if value is int or value is float:
			return int(value)
	return fallback


func _folder_tooltip(files: int, occupied: int, total: int) -> String:
	return "%d %s · %d из %d клеток" % [files, _plural_files(files), occupied, total]


## Ценник всегда на кнопке: «НОВАЯ ПАПКА · $184». 0 — без цены.
func set_new_folder_price(price: int) -> void:
	var next := maxi(0, int(price))
	var changed := next != _folder_price
	_folder_price = next
	_set_price_caption(_folder_price)
	if changed and _price_known and _folder_price > 0:
		_pulse_new_button()
	_price_known = true


func get_new_folder_price() -> int:
	return _folder_price


func _set_price_caption(price: int) -> void:
	if _new_btn == null:
		return
	if price > 0:
		_new_btn.caption = "НОВАЯ ПАПКА · $%d" % price
		_new_btn.tooltip_text = "Создать папку за $%d" % price
	else:
		_new_btn.caption = "НОВАЯ ПАПКА"
		_new_btn.tooltip_text = "Создать папку"
	_new_btn.queue_redraw()


func _pulse_new_button() -> void:
	if _new_btn == null or UiMotion.reduced \
			or DisplayServer.get_name() == "headless":
		return
	if _price_tween != null and _price_tween.is_valid():
		_price_tween.kill()
	_new_btn.modulate = Color(1.14, 1.14, 1.14, 1.0)
	_price_tween = create_tween()
	_price_tween.tween_property(_new_btn, "modulate", Color(1, 1, 1, 1),
		UiMotion.DUR_UI)


func _apply_layout() -> void:
	var y := 0.0
	var section_open := true
	var w := _view.size.x if _view != null else size.x
	for e in _rows:
		var row: FolderRow = e["row"]
		if row.is_section:
			section_open = row.expanded
			e["visible"] = true
		else:
			e["visible"] = section_open
		row.visible = bool(e["visible"])
		if row.visible:
			row.position = Vector2(0, y)
			row.size = Vector2(w, row.custom_minimum_size.y)
			y += row.custom_minimum_size.y
	if _bar != null and _view != null:
		_bar.set_metrics(_view.size.y, maxf(_view.size.y, y + 2.0))
		if _bar.value > _bar.max_value - _bar.page:
			_content.position.y = -_bar.value


func _on_scroll(v: float) -> void:
	if _content == null:
		return
	_content.position = Vector2(0, -v)


func _on_folder_clicked(folder_id: String) -> void:
	select_folder(folder_id)
	folder_selected.emit(folder_id)


func _on_section_clicked(_section_id: String) -> void:
	pass


func select_folder(folder_id: String) -> void:
	_selected = folder_id
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section:
			row.selected = row.folder_id == folder_id


func update_count(folder_id: String, count: int) -> void:
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section and row.folder_id == folder_id:
			row.files_count = count
			row.tooltip_text = _folder_tooltip(row.files_count, row.count, row.capacity)
			row.queue_redraw()
			break


func update_stats(folder_id: String, files: int, occupied: int, total: int) -> void:
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section and row.folder_id == folder_id:
			row.files_count = files
			row.count = occupied
			row.capacity = total if total > 0 else row.capacity
			row.tooltip_text = _folder_tooltip(row.files_count, row.count, row.capacity)
			row.queue_redraw()
			queue_redraw()
			break


func footer_text() -> String:
	var folders := 0
	var files := 0
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section:
			folders += 1
			files += row.files_count
	return "%d %s · %d %s" % [folders, _plural_folders(folders), files, _plural_files(files)]


func _on_toggle(folder_id: String) -> void:
	for e in _rows:
		var row: FolderRow = e["row"]
		if row.folder_id == folder_id and row.is_section:
			row.expanded = not row.expanded
			break
	_apply_layout()
	_relayout()


func _on_drop(folder_id: String, payload: Dictionary) -> void:
	file_dropped.emit(folder_id, payload)


func _on_packet_drop(folder_id: String, payload: Dictionary) -> void:
	packet_dropped.emit(folder_id, payload)


func _on_context(folder_id: String, global_pos: Vector2) -> void:
	context_menu_requested.emit(folder_id, global_pos)


## DragController: 250 мс над папкой истекли — раскрываем секцию и визуал.
func _bind_drag_controller() -> void:
	if not is_inside_tree():
		return
	var dc := get_tree().get_first_node_in_group("drag_controller")
	if dc == null or _drag == dc:
		return
	_drag = dc
	if dc.has_signal("hover_open") \
			and not dc.is_connected("hover_open", Callable(self, "_on_hover_open")):
		dc.connect("hover_open", Callable(self, "_on_hover_open"))


func _process(_delta: float) -> void:
	if _drag != null and is_instance_valid(_drag):
		set_process(false)
		return
	_drag = null
	_bind_drag_controller()
	if _drag != null:
		set_process(false)


func _on_hover_open(folder_id: String) -> void:
	var row := _row_for(folder_id)
	if row == null:
		return
	row.set_hover(true)


## FolderRow.hover_open_requested: открываем папку без повторного set_hover.
func _on_row_hover_open(folder_id: String) -> void:
	if _selected != folder_id:
		select_folder(folder_id)
	_expand_section_of(folder_id)
	folder_selected.emit(folder_id)
	hover_open_requested.emit(folder_id)


func _row_for(folder_id: String) -> FolderRow:
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section and row.folder_id == folder_id:
			return row
	return null


func _expand_section_of(folder_id: String) -> void:
	var target_section := ""
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section and row.folder_id == folder_id:
			target_section = str(e.get("section", ""))
			break
	if target_section.is_empty():
		return
	for e in _rows:
		var row: FolderRow = e["row"]
		if row.is_section and row.folder_id == target_section and not row.expanded:
			row.expanded = true
			_apply_layout()
			_relayout()
			return


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_bar.value -= 32.0
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_bar.value += 32.0
			accept_event()


func _draw() -> void:
	var vr := _view_rect()
	var fr := _footer_rect()
	var f := Theme90.ui()
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), vr)

	# подвал: папки · файлы · занятые клетки
	Theme90.text(self, f, Vector2(fr.position.x + 6, fr.position.y + 1),
		footer_text(), 10, Theme90.SHADE, fr.size.x - 6.0)
