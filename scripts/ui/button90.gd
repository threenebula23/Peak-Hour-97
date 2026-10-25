class_name Button90
extends BaseButton
## Мягкая кнопка: высота 24, скругление 3, 1 px контур, тень только в покое.
## hover — бирюзовый контур и тёмный бирюзовый текст; нажатие — на 1 px внутрь.
## flat_style — пункт меню без рамки; active — мягкая teal-подсветка.

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
@export var pad := 9.0


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
		return Vector2(16, 16)
	var f := Theme90.ui()
	var w := ceilf(f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x) + pad * 2.0
	return Vector2(maxf(w, 16.0), Theme90.H)


func set_caption(v: String) -> void:
	caption = v


func _accent_border() -> Color:
	return Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.55)


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
		var bg := Color(0, 0, 0, 0)
		if is_active:
			bg = Theme90.ACCENT_PALE
		elif hover and not dis:
			bg = Color(1, 1, 1, 0.5)
		if bg.a > 0.0:
			draw_style_box(Theme90.box(bg, Color(0, 0, 0, 0), 3, 0), r)
		var fg := Theme90.INK
		if dis:
			fg = Theme90.SHADE
		elif is_active or hover:
			fg = Theme90.NAVY
		if is_active:
			draw_rect(Rect2(r.position.x + 5, r.end.y - 2, maxf(0.0, r.size.x - 10), 2),
				Theme90.ACCENT)
		_draw_content(r, f, fg, pressed, dis)
		return

	var face := Theme90.PAPER_HI
	var border := Theme90.BORDER
	var fg := Theme90.INK
	var shadow := Theme90.SHADOW
	if dis:
		face = Theme90.PAPER
		border = Theme90.BORDER_SOFT
		fg = Theme90.SHADE
		shadow = Color(0, 0, 0, 0)
	elif accent:
		face = Theme90.ACCENT.darkened(0.06) if pressed else Theme90.ACCENT
		border = Theme90.ACCENT.darkened(0.18)
		fg = Theme90.WHITE
		if hover:
			face = Theme90.ACCENT.lightened(0.04)
	elif danger:
		face = Theme90.PAPER_HI
		border = Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.42)
		fg = Theme90.ERROR
		if hover:
			face = Color(1, 1, 1, 1)
			border = Theme90.ERROR
	elif is_active:
		face = Theme90.ACCENT_PALE
		border = Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.65)
		fg = Theme90.NAVY
		if hover:
			face = Theme90.ACCENT_PALE.lerp(Theme90.WHITE, 0.35)
	else:
		if hover:
			face = Theme90.WHITE
			border = _accent_border()
			fg = Theme90.NAVY

	if pressed and not dis:
		face = face.darkened(0.05) if face.get_luminance() > 0.4 else face.darkened(0.1)
		shadow = Color(0, 0, 0, 0)

	if not (pressed and not dis):
		draw_style_box(Theme90.box(face, border, 3, 1, shadow), r)
	else:
		draw_style_box(Theme90.box(face, border, 3, 1), r)
		draw_line(Vector2(3, 1), Vector2(r.size.x - 3, 1), Color(0, 0, 0, 0.10), 1.0)

	# мягкий верхний блик
	if not pressed and not dis and face.get_luminance() > 0.55 and r.size.y >= 16.0:
		draw_line(Vector2(4, 1), Vector2(r.size.x - 4, 1), Color(1, 1, 1, 0.55), 1.0)

	# аккуратный фокус — тонкое кольцо внутри
	if has_focus() and not dis:
		draw_style_box(Theme90.box(Color(0, 0, 0, 0),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.75), 3, 1),
			r.grow(-2.0))

	_draw_content(r, f, fg, pressed, dis)


func _draw_content(r: Rect2, f: Font, fg: Color, pressed: bool, dis: bool) -> void:
	var shift := Vector2(0, 1) if pressed and not dis else Vector2.ZERO
	var icon_w := 0.0
	if icon != Icon.NONE:
		icon_w = 12.0
	var total := 0.0
	if not caption.is_empty():
		total = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
		total += icon_w + (4.0 if icon_w > 0.0 else 0.0)
	var left := r.position.x + roundf((r.size.x - total) * 0.5) + shift.x
	var x := left
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
			Theme90.draw_x(self, ir, fg, 1.2)
		Icon.MIN:
			draw_rect(Rect2(ir.position.x + 3, ir.get_center().y, 6, 1), fg)
		Icon.MAX:
			draw_style_box(Theme90.box(Color(0, 0, 0, 0), fg, 2, 1),
				Rect2(ir.position.x + 3, ir.position.y + 3, 7, 7))
			draw_rect(Rect2(ir.position.x + 3, ir.position.y + 3, 7, 2), fg)
		Icon.PLUS:
			draw_rect(Rect2(ir.get_center().x - 3, ir.get_center().y - 0.5, 7, 1.4), fg)
			draw_rect(Rect2(ir.get_center().x - 0.5, ir.get_center().y - 3, 1.4, 7), fg)
		Icon.MINUS:
			draw_rect(Rect2(ir.get_center().x - 3, ir.get_center().y - 0.5, 7, 1.4), fg)
		Icon.ARROW_UP:
			Theme90.draw_chevron(self, ir.get_center(), 0, fg, 3.2, 1.4)
		Icon.ARROW_DOWN:
			Theme90.draw_chevron(self, ir.get_center(), 1, fg, 3.2, 1.4)
		Icon.LEFT:
			Theme90.draw_chevron(self, ir.get_center(), 3, fg, 3.2, 1.4)
		Icon.RIGHT:
			Theme90.draw_chevron(self, ir.get_center(), 2, fg, 3.2, 1.4)
		Icon.CHECK:
			draw_line(Vector2(ir.position.x + 2, ir.position.y + 6), Vector2(ir.position.x + 5, ir.position.y + 9), fg, 1.8)
			draw_line(Vector2(ir.position.x + 5, ir.position.y + 9), Vector2(ir.position.x + 10, ir.position.y + 3), fg, 1.8)
