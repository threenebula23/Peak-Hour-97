class_name Check90
extends BaseButton
## Чекбокс: скруглённый квадрат 13×13, 1 px контур, teal-заливка при выборе.
## Подпись — Handjet 10.

var checked := false:
	set(v):
		checked = v
		queue_redraw()
var caption := "":
	set(v):
		caption = v
		queue_redraw()
var caption_size := Theme90.FS_MICRO
var box_color := Theme90.WHITE
var check_color := Theme90.WHITE

var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	toggled.connect(func(on: bool) -> void:
		checked = on
		queue_redraw())


func _draw() -> void:
	var box := Rect2(1, roundf((size.y - 13.0) * 0.5), 13, 13)
	if checked:
		draw_style_box(Theme90.box(Theme90.ACCENT, Color(0, 0, 0, 0), 3, 0), box)
		draw_line(Vector2(box.position.x + 3, box.position.y + 6.5),
			Vector2(box.position.x + 5.5, box.position.y + 9), check_color, 1.7)
		draw_line(Vector2(box.position.x + 5.5, box.position.y + 9),
			Vector2(box.position.x + 10, box.position.y + 3.5), check_color, 1.7)
	else:
		var border := Theme90.ACCENT_LIGHT if _hover else Theme90.BORDER
		draw_style_box(Theme90.box(box_color, border, 3, 1), box)
	if not caption.is_empty():
		var f := Theme90.ui()
		Theme90.text_vcenter(self, f, Rect2(19, 0, maxf(0.0, size.x - 19), size.y),
			caption, caption_size,
			Theme90.NAVY if _hover and not disabled else (Theme90.DARK if not disabled else Theme90.SHADE))
