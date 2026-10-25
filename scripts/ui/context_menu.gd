class_name ContextMenu90
extends PopupMenu
## Контекстное меню: светлая карточка с тонким контуром и мягкой тенью,
## hover — pale-teal строка. Пункты: Новая папка / Переименовать / Удалить…

func _ready() -> void:
	add_theme_font_override("font", Theme90.ui())
	add_theme_font_size_override("font_size", Theme90.FS_BODY)
	add_theme_constant_override("v_separation", 4)
	add_theme_constant_override("item_start_padding", 10)
	add_theme_constant_override("item_end_padding", 14)
	add_theme_color_override("font_color", Theme90.INK)
	add_theme_color_override("font_hover_color", Theme90.NAVY)
	add_theme_color_override("font_disabled_color", Theme90.SHADE)
	add_theme_stylebox_override("panel", Theme90.popup_panel_box())
	add_theme_stylebox_override("hover", Theme90.popup_hover_box())


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
