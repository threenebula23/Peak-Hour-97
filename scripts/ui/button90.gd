class_name Button90
extends BaseButton
## Кнопка 90-х: высота 24 px, фаска 2 px, без скруглений.
## Нажатая — фаска выворачивается, текст сдвигается на 1 px.
## flat_style — пункт меню (подсветка синим без фаски).

enum Icon { NONE, X, MIN, MAX, PLUS, MINUS, ARROW_UP, ARROW_DOWN, CHECK, LEFT, RIGHT }

@export var caption := "":
	set(v):
		caption = v
		update_minimum_size()
		queue_redraw()
@export var caption_size := Theme90.FS_BODY:
	set(v):
		caption_size = v
		update_minimum_size()
		queue_redraw()
@export var accent := false:
	set(v):
		accent = v
		queue_redraw()
@export var danger := false:
	set(v):
		danger = v
		queue_redraw()
@export var flat_style := false:
	set(v):
		flat_style = v
		queue_redraw()
@export var icon: Icon = Icon.NONE:
	set(v):
		icon = v
		update_minimum_size()
		queue_redraw()
@export var active := false:
	set(v):
		active = v
		queue_redraw()
@export var pad := 8.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(queue_redraw)
	if not pressed.is_connected(_play_click):
		pressed.connect(_play_click)


## Клик-звук UI. Audio — autoload; в отрыве от дерева (превью) молча пропускаем.
func _play_click() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx("click")


## Справочный размер под текст — раскладка задаёт размеры явно.
func preferred_size() -> Vector2:
	if icon != Icon.NONE and caption.is_empty():
		return Vector2(14, 14)
	var f := Theme90.ui()
	var w := ceilf(f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x) + pad * 2.0
	return Vector2(maxf(w, 14.0), Theme90.H)


func set_caption(v: String) -> void:
	caption = v


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var mode := get_draw_mode()
	var dis := mode == BaseButton.DRAW_DISABLED or disabled
	var pressed := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var hover := mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_HOVER_PRESSED
	if toggle_mode and button_pressed:
		pressed = true
	var is_active := active or (toggle_mode and button_pressed)
	var f := Theme90.ui()

	if flat_style:
		if is_active or (hover and not dis):
			draw_rect(r, Theme90.NAVY)
		elif hover and not dis:
			draw_rect(r, Theme90.FACE_HI)
		var fg := Theme90.WHITE if (is_active or hover) and not dis else Theme90.INK
		if dis:
			fg = Theme90.SHADE
		_draw_content(r, f, fg, pressed, false)
		return

	var face_color := Theme90.FACE
	if accent and not dis:
		face_color = Theme90.NAVY
		if hover:
			face_color = Color(0.0, 0.0, 0.627451)
	elif danger and not dis:
		face_color = Theme90.FACE
	Theme90.draw_bevel(self, r, pressed, Theme90.BEVEL, face_color)
	if dis:
		face_color = Theme90.FACE
	# мягкая подсветка наведения
	if hover and not dis and not accent:
		draw_rect(Rect2(2, 2, size.x - 4, 1), Theme90.FACE_HI)
		draw_rect(Rect2(2, 2, 1, size.y - 4), Theme90.FACE_HI)
		Theme90.draw_bevel(self, r.grow(-2.0), true, 1.0, Theme90.FACE_HI)

	var fg := Theme90.INK
	if accent and not dis:
		fg = Theme90.WHITE
	elif danger and not dis:
		fg = Theme90.ERROR
	elif dis:
		fg = Theme90.SHADE
	elif hover:
		fg = Theme90.NAVY

	# пунктирный фокус
	if has_focus() and not dis and not flat_style:
		_draw_focus(Rect2(3, 3, size.x - 6, size.y - 6))

	_draw_content(r, f, fg, pressed, dis)


func _draw_content(r: Rect2, f: Font, fg: Color, pressed: bool, dis: bool) -> void:
	var shift := Vector2(1, 1) if pressed and not dis else Vector2.ZERO
	var icon_w := 0.0
	if icon != Icon.NONE:
		icon_w = 12.0
	var total := 0.0
	if not caption.is_empty():
		total = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
		total += icon_w + (4.0 if icon_w > 0.0 else 0.0)
	var x := roundf(r.position.x + (r.size.x - total) * 0.5) + shift.x
	var cy := roundf(r.get_center().y) + shift.y
	if icon != Icon.NONE:
		var ir := Rect2(x, cy - 6.0, 12.0, 12.0)
		_draw_icon(ir, fg)
		x += icon_w + 4.0
	if not caption.is_empty():
		var baseline := roundf(cy + f.get_ascent(caption_size) * 0.5 - 1.0)
		draw_string(f, Vector2(x, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size, fg)


func _draw_icon(ir: Rect2, fg: Color) -> void:
	match icon:
		Icon.X:
			Theme90.draw_x(self, ir, fg, 1.0)
		Icon.MIN:
			draw_rect(Rect2(ir.position.x + 3, ir.get_center().y, 6, 1), fg)
		Icon.MAX:
			draw_rect(Rect2(ir.position.x + 3, ir.position.y + 3, 7, 7), fg, false, 1.0)
			draw_rect(Rect2(ir.position.x + 3, ir.position.y + 3, 7, 2), fg)
		Icon.PLUS:
			draw_rect(Rect2(ir.get_center().x - 3, ir.get_center().y - 0.5, 7, 1), fg)
			draw_rect(Rect2(ir.get_center().x - 0.5, ir.get_center().y - 3, 1, 7), fg)
		Icon.MINUS:
			draw_rect(Rect2(ir.get_center().x - 3, ir.get_center().y - 0.5, 7, 1), fg)
		Icon.ARROW_UP:
			Theme90.draw_arrow(self, ir, 0, fg)
		Icon.ARROW_DOWN:
			Theme90.draw_arrow(self, ir, 1, fg)
		Icon.LEFT:
			Theme90.draw_arrow(self, ir, 3, fg)
		Icon.RIGHT:
			Theme90.draw_arrow(self, ir, 2, fg)
		Icon.CHECK:
			draw_line(Vector2(ir.position.x + 2, ir.position.y + 6), Vector2(ir.position.x + 5, ir.position.y + 9), fg, 2.0)
			draw_line(Vector2(ir.position.x + 5, ir.position.y + 9), Vector2(ir.position.x + 10, ir.position.y + 3), fg, 2.0)


func _draw_focus(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	while x < r.end.x:
		draw_rect(Rect2(x, y, 1, 1), Theme90.INK)
		draw_rect(Rect2(x, r.end.y - 1, 1, 1), Theme90.INK)
		x += 2
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, 1, 1), Theme90.INK)
		draw_rect(Rect2(r.end.x - 1, y, 1, 1), Theme90.INK)
		y += 2
