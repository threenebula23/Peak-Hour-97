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

## Тайминги состояний (UiMotion). Только draw-only: position/size не меняются.
const HOVER_IN := 0.10
const HOVER_OUT := 0.12
const PRESS_IN := 0.06
const PRESS_OUT := 0.08
const FOCUS_DUR := 0.12
## Насколько сдвигается содержимое в нажатом состоянии, px.
const PRESS_SHIFT := 1.0

var _hover_amt := 0.0
var _press_amt := 0.0
var _focus_amt := 0.0
## Локальный выключатель движения (Lane A / настройки). UiMotion.reduced тоже.
var _motion_on := true


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(_touch)
	mouse_exited.connect(_touch)
	button_down.connect(_touch)
	button_up.connect(_touch)
	focus_entered.connect(_touch)
	focus_exited.connect(_touch)
	resized.connect(queue_redraw)
	if not pressed.is_connected(_play_click):
		pressed.connect(_play_click)


## Разбудить плавные состояния. Дальше _process сам остановится на цели.
func _touch() -> void:
	set_process(true)
	queue_redraw()


## Внешний переключатель (Lane A вызывает через has_method).
func set_motion_enabled(on: bool) -> void:
	_motion_on = on
	if _reduced():
		_snap()
	queue_redraw()


func _reduced() -> bool:
	return not _motion_on or UiMotion.reduced


func _targets() -> Vector3:
	var mode := get_draw_mode()
	var dis := mode == BaseButton.DRAW_DISABLED or disabled
	var hover := (mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_HOVER_PRESSED) and not dis
	var press := (mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED) and not dis
	if toggle_mode and button_pressed:
		press = true
	return Vector3(
		1.0 if hover else 0.0,
		1.0 if press else 0.0,
		1.0 if has_focus() and not dis else 0.0)


func _snap() -> void:
	var t := _targets()
	_hover_amt = t.x
	_press_amt = t.y
	_focus_amt = t.z


func _process(delta: float) -> void:
	var t := _targets()
	if _reduced():
		if not _at(t):
			_snap()
			queue_redraw()
		set_process(false)
		return
	var changed := false
	if not is_equal_approx(_hover_amt, t.x):
		_hover_amt = move_toward(_hover_amt, t.x, delta / (HOVER_IN if t.x > _hover_amt else HOVER_OUT))
		changed = true
	if not is_equal_approx(_press_amt, t.y):
		_press_amt = move_toward(_press_amt, t.y, delta / (PRESS_IN if t.y > _press_amt else PRESS_OUT))
		changed = true
	if not is_equal_approx(_focus_amt, t.z):
		_focus_amt = move_toward(_focus_amt, t.z, delta / FOCUS_DUR)
		changed = true
	if changed:
		queue_redraw()
	# Цель достигнута — не крутим _process зря.
	if _at(t):
		_hover_amt = t.x
		_press_amt = t.y
		_focus_amt = t.z
		set_process(false)


func _at(t: Vector3) -> bool:
	return is_equal_approx(_hover_amt, t.x) \
		and is_equal_approx(_press_amt, t.y) \
		and is_equal_approx(_focus_amt, t.z)


## Значения для _draw: в reduced — мгновенные, иначе текущие плавные.
func _amts() -> Vector3:
	if _reduced():
		return _targets()
	var t := _targets()
	if not is_processing() and not _at(t):
		set_process(true)
	return Vector3(_hover_amt, _press_amt, _focus_amt)


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
	var amts := _amts()
	var hov := amts.x
	var prs := amts.y
	var foc := amts.z
	var r := Rect2(Vector2.ZERO, size)
	var mode := get_draw_mode()
	var dis := mode == BaseButton.DRAW_DISABLED or disabled
	var is_active := active or (toggle_mode and button_pressed)
	var f := Theme90.ui()

	if flat_style:
		var bg := Color(0, 0, 0, 0)
		if is_active:
			bg = Theme90.ACCENT_PALE
		elif hov > 0.001 and not dis:
			bg = Color(1, 1, 1, 0.5 * hov)
		if bg.a > 0.0:
			draw_style_box(Theme90.box(bg, Color(0, 0, 0, 0), 3, 0), r)
		var fg := Theme90.INK
		if dis:
			fg = Theme90.SHADE
		elif is_active:
			fg = Theme90.NAVY
		else:
			fg = Theme90.INK.lerp(Theme90.NAVY, hov)
		if is_active:
			draw_rect(Rect2(r.position.x + 5, r.end.y - 2, maxf(0.0, r.size.x - 10), 2),
				Theme90.ACCENT)
		_draw_content(r, f, fg, PRESS_SHIFT * roundf(prs), dis)
		return

	var face := Theme90.PAPER_HI
	var border := Theme90.BORDER
	var fg := Theme90.INK
	var shadow := Theme90.SHADOW
	var hover_face := Theme90.WHITE
	var hover_border := _accent_border()
	var hover_fg := Theme90.NAVY
	if dis:
		face = Theme90.PAPER
		border = Theme90.BORDER_SOFT
		fg = Theme90.SHADE
		shadow = Color(0, 0, 0, 0)
		hover_face = face
		hover_border = border
		hover_fg = fg
	elif accent:
		face = Theme90.ACCENT
		border = Theme90.ACCENT.darkened(0.18)
		fg = Theme90.WHITE
		hover_face = Theme90.ACCENT.lightened(0.04)
		hover_border = border
		hover_fg = fg
	elif danger:
		face = Theme90.PAPER_HI
		border = Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.42)
		fg = Theme90.ERROR
		hover_face = Color(1, 1, 1, 1)
		hover_border = Theme90.ERROR
		hover_fg = fg
	elif is_active:
		face = Theme90.ACCENT_PALE
		border = Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.65)
		fg = Theme90.NAVY
		hover_face = Theme90.ACCENT_PALE.lerp(Theme90.WHITE, 0.35)
		hover_border = border
		hover_fg = fg

	face = face.lerp(hover_face, hov)
	border = border.lerp(hover_border, hov)
	fg = fg.lerp(hover_fg, hov)

	if prs > 0.0 and not dis:
		var dv := 0.05 if face.get_luminance() > 0.4 else 0.1
		face = face.darkened(dv * prs)
		shadow = shadow.lerp(Color(0, 0, 0, 0), prs)

	if prs < 0.5 or dis:
		draw_style_box(Theme90.box(face, border, 3, 1, shadow), r)
	else:
		draw_style_box(Theme90.box(face, border, 3, 1), r)
		draw_line(Vector2(3, 1), Vector2(r.size.x - 3, 1), Color(0, 0, 0, 0.10), 1.0)

	# мягкий верхний блик
	if prs < 0.5 and not dis and face.get_luminance() > 0.55 and r.size.y >= 16.0:
		draw_line(Vector2(4, 1), Vector2(r.size.x - 4, 1), Color(1, 1, 1, 0.55), 1.0)

	# аккуратный фокус — тонкое кольцо внутри, α плавно проявляется
	if foc > 0.01 and not dis:
		draw_style_box(Theme90.box(Color(0, 0, 0, 0),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.75 * foc), 3, 1),
			r.grow(-2.0))

	_draw_content(r, f, fg, PRESS_SHIFT * roundf(prs), dis)


func _draw_content(r: Rect2, f: Font, fg: Color, shift_y: float, _dis: bool) -> void:
	var shift := Vector2(0, shift_y)
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
