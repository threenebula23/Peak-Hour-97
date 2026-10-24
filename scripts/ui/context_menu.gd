class_name ContextMenu90
extends PopupMenu
## Контекстное меню 90-х: серая панель, фаска, тень.
## Пункты: Новая папка / Переименовать / Удалить / Уничтожить.

var _borders: Array[ColorRect] = []


func _ready() -> void:
	add_theme_font_override("font", Theme90.ui())
	add_theme_font_size_override("font_size", Theme90.FS_BODY)
	add_theme_constant_override("v_separation", 4)
	add_theme_constant_override("item_start_padding", 10)
	add_theme_constant_override("item_end_padding", 14)
	# фаска поверх служебной рамки попапа
	for i in 4:
		var cr := ColorRect.new()
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.color = Theme90.LIGHT if i < 2 else Theme90.SHADE
		add_child(cr)
		_borders.append(cr)
	if not size_changed.is_connected(_sync_borders):
		size_changed.connect(_sync_borders)
	about_to_popup.connect(_on_about)
	_sync_borders()


func _on_about() -> void:
	_sync_borders()
	await get_tree().process_frame
	_sync_borders()


func _sync_borders() -> void:
	if _borders.size() < 4:
		return
	var s := Vector2(size)
	var t := 2.0
	_borders[0].position = Vector2.ZERO
	_borders[0].size = Vector2(s.x, t)
	_borders[1].position = Vector2.ZERO
	_borders[1].size = Vector2(t, s.y)
	_borders[2].position = Vector2(0, s.y - t)
	_borders[2].size = Vector2(s.x, t)
	_borders[3].position = Vector2(s.x - t, 0)
	_borders[3].size = Vector2(t, s.y)


## Показывает меню в глобальной точке. items: [{label, id, disabled, danger} | {sep:true}]
static func show_items(parent: Node, items: Array, pos: Vector2, on_id: Callable) -> ContextMenu90:
	var m := ContextMenu90.new()
	m.name = "ContextMenu"
	var next_id := 1
	var id_map := {}
	for it in items:
		var d: Dictionary = it
		if bool(d.get("sep", false)):
			m.add_separator()
			continue
		var idx := m.item_count
		m.add_item(str(d.get("label", "")), next_id)
		id_map[next_id] = str(d.get("id", str(next_id)))
		if bool(d.get("disabled", false)):
			m.set_item_disabled(idx, true)
		if bool(d.get("danger", false)):
			m.set_item_icon(idx, Theme90.square_texture(Theme90.ERROR, 6))
		next_id += 1
	parent.add_child(m)
	m.id_pressed.connect(func(id: int) -> void:
		if id_map.has(id):
			on_id.call(id_map[id]))
	m.popup_hide.connect(m.queue_free)
	var sz := Vector2i(m.get_contents_minimum_size())
	m.popup(Rect2i(Vector2i(pos.round()), sz))
	return m
