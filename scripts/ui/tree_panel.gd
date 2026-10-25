class_name TreePanel
extends Control
## Дерево дисков и папок: светлая поверхность, строки 24 px, скролл 14 px,
## кнопка «Новая папка» и контекстное меню по правой кнопке.

signal folder_selected(folder_id: String)
signal file_dropped(folder_id: String, payload: Dictionary)
signal context_menu_requested(folder_id: String, global_pos: Vector2)
signal new_folder_requested

var _view: Control
var _content: Control
var _bar: ScrollBar90
var _new_btn: Button90
var _rows: Array[Dictionary] = []
var _selected := ""


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
	_new_btn.pressed.connect(func() -> void: new_folder_requested.emit())

	resized.connect(_relayout)
	_relayout()


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


## sections: [{id, name, free, folders: [{id, name, count, capacity, locked}]}]
func set_data(sections: Array) -> void:
	for c in _content.get_children():
		c.queue_free()
	_rows.clear()
	for sec in sections:
		var sid: String = str(sec.get("id", ""))
		var srow := FolderRow.new()
		srow.setup(sid, str(sec.get("name", "")), 0, true)
		srow.free_text = str(sec.get("free", ""))
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
			frow.count = int(fol.get("count", 0))
			frow.capacity = int(fol.get("capacity", 16))
			frow.tooltip_text = "Папка заполнена" if frow.count >= frow.capacity \
				else "%d из %d объектов" % [frow.count, frow.capacity]
			frow.locked = bool(fol.get("locked", false))
			frow.custom_minimum_size = Vector2(0, FolderRow.ROW_H)
			frow.folder_selected.connect(_on_folder_clicked)
			frow.expansion_toggled.connect(_on_toggle)
			frow.file_dropped.connect(_on_drop)
			frow.context_menu_requested.connect(_on_context)
			_content.add_child(frow)
			_rows.append({"row": frow, "section": sid, "visible": true})
	_apply_layout()
	_relayout()
	if not _selected.is_empty():
		select_folder(_selected)


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
			row.count = count
			row.queue_redraw()


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


func _on_context(folder_id: String, global_pos: Vector2) -> void:
	context_menu_requested.emit(folder_id, global_pos)


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

	# подвал: одна спокойная строка вместо двух «счётчиков»
	var folders := 0
	var objs := 0
	for e in _rows:
		var row: FolderRow = e["row"]
		if not row.is_section:
			folders += 1
			objs += row.count
	Theme90.text(self, f, Vector2(fr.position.x + 6, fr.position.y + 1),
		"%d папок · %d объектов" % [folders, objs], 10, Theme90.SHADE, fr.size.x - 120)
	var free := "8,5 МБ"
	var fw := f.get_string_size(free, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(fr.end.x - fw - 6, fr.position.y + 1), free, 10,
		Theme90.SHADE)
