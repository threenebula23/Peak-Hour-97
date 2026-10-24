class_name Check90
extends BaseButton
## Чекбокс 90-х: квадрат 12×12 с утопленной рамкой и галочкой.
## Высота по умолчанию — 14 px, подпись шрифтом Handjet 10.

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
var check_color := Theme90.NAVY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	toggled.connect(func(on: bool) -> void:
		checked = on
		queue_redraw())


func _draw() -> void:
	var box := Rect2(1, roundf((size.y - 12.0) * 0.5), 12, 12)
	draw_rect(box, box_color)
	Theme90.draw_bevel(self, box, true, 1.0, box_color)
	draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), Theme90.SHADE)
	draw_rect(Rect2(box.position, Vector2(1, box.size.y)), Theme90.SHADE)
	if checked:
		draw_line(Vector2(box.position.x + 3, box.position.y + 6), Vector2(box.position.x + 5, box.position.y + 9), check_color, 2.0)
		draw_line(Vector2(box.position.x + 5, box.position.y + 9), Vector2(box.position.x + 9, box.position.y + 3), check_color, 2.0)
	if not caption.is_empty():
		var f := Theme90.ui()
		Theme90.text_vcenter(self, f, Rect2(17, 0, size.x - 17, size.y), caption, caption_size,
			Theme90.DARK if not disabled else Theme90.SHADE)
