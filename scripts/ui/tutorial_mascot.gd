class_name TutorialMascot
extends Control
## Маскот «БАЙТ» — оранжевый кот в фиолетовой кепке и очках.
## Картинка: art/mascot/tutor_cat.png (64×64, nearest-neighbor).
##
##   mascot.show_tutorial("ПРИЁМ", "Пакеты приходят сюда…", 1, 9)
##   mascot.set_progress(3, 9)
##   mascot.hide_message()
##
## Контрол не блокирует мышь. Высота подстраивается под облачко; кот
## прижат к нижнему левому углу, поэтому в игре его удобно ставить у края.

signal message_finished

const ROBOT := 96.0
const GAP := 10.0
const BUBBLE_W := 244.0
const CAT_PATH := "res://art/mascot/tutor_cat.png"

## Базовые отступы облачка.
const PAD_TOP := 12.0
const PAD_TOP_STEP := 25.0
const TEXT_LINE := 14.0
const BOTTOM_PAD := 10.0
const PROGRESS_H := 3.0

var is_visible := false
var step := 0
## Заголовок карточки (для интро). Пусто — облачко без заголовка.
var title := ""
var bubble_width := BUBBLE_W
## Масштаб только кота (облачко остаётся читаемым). 1.0 — базовые 96 px.
var robot_scale := 1.0
var progress_current := 0
var progress_total := 0

var _text := ""
var _lines := PackedStringArray()
var _auto_hide := -1.0
var _timer := 0.0
var _t := 0.0
var _appear := 0.0
var _blink_t := 0.0
var _cat: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cat = load(CAT_PATH) as Texture2D
	_reset_size()
	visible = false
	set_process(false)


func _reset_size() -> void:
	custom_minimum_size = _robot_size()
	size = _robot_size()


func _robot_size() -> Vector2:
	var s := ROBOT * robot_scale
	return Vector2(s, s)


## Уменьшить/увеличить только кота, не трогая кегль облачка.
func set_robot_scale(value: float) -> void:
	robot_scale = clampf(value, 0.5, 2.0)
	_reset_size()
	if not _text.is_empty():
		_relayout()
	queue_redraw()


## Показать облачко. seconds > 0 — спрятать автоматически.
func show_message(text: String, seconds: float = -1.0) -> void:
	title = ""
	_show(text, seconds)


## Показать карточку с заголовком и телом (интро-шаг).
func show_tutorial(heading: String, text: String, seconds: float = -1.0) -> void:
	title = heading
	_show(text, seconds)


func _show(text: String, seconds: float) -> void:
	_text = text
	is_visible = true
	visible = true
	_auto_hide = seconds
	_timer = 0.0
	_appear = 0.0
	_relayout()
	set_process(true)
	queue_redraw()


## Прогресс обучения: 0/0 — скрыть полосу. current нумеруется с 1.
func set_progress(current: int, total: int) -> void:
	progress_total = maxi(0, total)
	progress_current = clampi(current, 0, progress_total) if progress_total > 0 else 0
	if is_visible and not _text.is_empty():
		_relayout()
	queue_redraw()


## Спрятать маскота целиком вместе с облачком.
func hide_message() -> void:
	is_visible = false
	visible = false
	_text = ""
	title = ""
	_lines = PackedStringArray()
	_auto_hide = -1.0
	_timer = 0.0
	_appear = 0.0
	_reset_size()
	set_process(false)
	queue_redraw()


## Номер шага: 0 — без шага; 1..N показывается чипом в облачке.
func set_step(index: int) -> void:
	step = maxi(0, index)
	if is_visible and not _text.is_empty():
		_relayout()
	queue_redraw()


func _relayout() -> void:
	var f := Theme90.ui()
	var inner := bubble_width - 26.0
	_lines = Theme90.wrap(f, _text, 12, inner, 8)
	var bh := _bubble_height()
	var rs := _robot_size()
	var total := maxf(rs.y, bh)
	size = Vector2(rs.x + GAP + bubble_width, total)
	custom_minimum_size = size


func _bubble_height() -> float:
	if _text.is_empty():
		return 0.0
	var pad := PAD_TOP_STEP if step > 0 else PAD_TOP
	var h := pad + _lines.size() * TEXT_LINE + BOTTOM_PAD
	if not title.is_empty():
		h += 17.0
	if progress_total > 0:
		h += 7.0
	return maxf(58.0, h)


func _process(delta: float) -> void:
	_t += delta
	_blink_t += delta
	if _blink_t > 3.4:
		_blink_t = 0.0
	if _appear < 1.0:
		_appear = minf(1.0, _appear + delta * 5.5)
	if _auto_hide > 0.0:
		_timer += delta
		if _timer >= _auto_hide:
			hide_message()
			message_finished.emit()
			return
	queue_redraw()


func _draw() -> void:
	var bob := 0.0
	if not UiMotion.reduced:
		bob = sin(_t * 2.1) * 1.4
	var rs := _robot_size()
	var ry := size.y - rs.y + bob
	_draw_cat(ry)
	if not _text.is_empty() and _appear > 0.0:
		_draw_bubble(ry)


# --------------------------------------------------------------------------
# Кот
# --------------------------------------------------------------------------

func _draw_cat(ry: float) -> void:
	var s := _robot_size().x
	var appear := clampf(_appear * 1.15, 0.0, 1.0)
	var bob_scale := 1.0
	if not UiMotion.reduced:
		bob_scale = 1.0 + sin(_t * 1.35) * 0.012
	var entry := lerpf(0.86, 1.0, ease(appear, 0.35))
	var draw_size := s * bob_scale * entry
	var cx := s * 0.5
	var bottom := ry + s
	var rect := Rect2(cx - draw_size * 0.5, bottom - draw_size, draw_size, draw_size)

	# Мягкая тень под котом.
	var shadow_w := draw_size * 0.52
	draw_style_box(Theme90.fill_box(Color(0, 0, 0, 0.10), 4),
		Rect2(cx - shadow_w * 0.5, bottom - 5.0, shadow_w, 5.0))

	if _cat != null:
		draw_texture_rect(_cat, rect, false, Color(1, 1, 1, appear))
		_draw_blink(rect, appear)
	else:
		_draw_cat_fallback(rect, appear)

	# Подпись-чип «БАЙТ» на груди.
	var label := "БАЙТ"
	var f := Theme90.ui()
	var fs := 8
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var chip := Rect2(cx - tw * 0.5 - 5.0, bottom - 19.0, tw + 10.0, 12.0)
	draw_style_box(Theme90.box(Color(1, 1, 1, 0.92 * appear),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, 0.9 * appear),
		3, 1), chip)
	Theme90.text(self, f, Vector2(chip.position.x + 5.0, chip.position.y + 1.0),
		label, fs, Color(Theme90.NAVY.r, Theme90.NAVY.g, Theme90.NAVY.b, appear))

	# Номер шага без облачка — бейдж в углу.
	if step > 0 and _text.is_empty() and appear > 0.5:
		var badge := Rect2(rect.end.x - 15.0, rect.position.y + 2.0, 14.0, 14.0)
		draw_circle(badge.get_center(), 7.0, Theme90.ACCENT)
		var sn := str(step)
		var sw := f.get_string_size(sn, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		Theme90.text(self, f, Vector2(badge.get_center().x - sw * 0.5,
			badge.position.y + 1.0), sn, 9, Theme90.WHITE)


## Короткое моргание: две полоски поверх глаз (изображение остаётся целым).
func _draw_blink(rect: Rect2, alpha: float) -> void:
	if UiMotion.reduced:
		return
	if _blink_t < 3.22 or _blink_t > 3.34:
		return
	var lid := Color(0.36, 0.20, 0.09, 0.92 * alpha)
	var w := rect.size.x * 0.145
	var h := maxf(1.5, rect.size.y * 0.035)
	var y := rect.position.y + rect.size.y * 0.355
	draw_rect(Rect2(rect.position.x + rect.size.x * 0.255, y, w, h), lid)
	draw_rect(Rect2(rect.position.x + rect.size.x * 0.60, y, w, h), lid)


## Аварийный запас, если PNG не импортирован: оранжевый кот-силуэт.
func _draw_cat_fallback(rect: Rect2, alpha: float) -> void:
	var coat := Color(0.93, 0.55, 0.17, alpha)
	var ink := Color(0.25, 0.16, 0.10, alpha)
	var cap := Color(0.48, 0.32, 0.78, alpha)
	draw_style_box(Theme90.box(coat, ink, 10, 2), Rect2(rect.position.x + rect.size.x * 0.08,
		rect.position.y + rect.size.y * 0.20, rect.size.x * 0.84, rect.size.y * 0.74))
	# уши
	draw_colored_polygon(PackedVector2Array([
		Vector2(rect.position.x + rect.size.x * 0.08, rect.position.y + rect.size.y * 0.28),
		Vector2(rect.position.x + rect.size.x * 0.18, rect.position.y + rect.size.y * 0.04),
		Vector2(rect.position.x + rect.size.x * 0.34, rect.position.y + rect.size.y * 0.22)]), coat)
	draw_colored_polygon(PackedVector2Array([
		Vector2(rect.position.x + rect.size.x * 0.92, rect.position.y + rect.size.y * 0.28),
		Vector2(rect.position.x + rect.size.x * 0.82, rect.position.y + rect.size.y * 0.04),
		Vector2(rect.position.x + rect.size.x * 0.66, rect.position.y + rect.size.y * 0.22)]), coat)
	# кепка
	draw_rect(Rect2(rect.position.x + rect.size.x * 0.22, rect.position.y + rect.size.y * 0.12,
		rect.size.x * 0.56, rect.size.y * 0.12), cap)
	# очки
	draw_style_box(Theme90.box(Color(0.98, 0.98, 0.95, alpha), cap, 3, 2),
		Rect2(rect.position.x + rect.size.x * 0.22, rect.position.y + rect.size.y * 0.32,
			rect.size.x * 0.25, rect.size.y * 0.15))
	draw_style_box(Theme90.box(Color(0.98, 0.98, 0.95, alpha), cap, 3, 2),
		Rect2(rect.position.x + rect.size.x * 0.53, rect.position.y + rect.size.y * 0.32,
			rect.size.x * 0.25, rect.size.y * 0.15))
	draw_circle(Vector2(rect.position.x + rect.size.x * 0.34, rect.position.y + rect.size.y * 0.39),
		rect.size.x * 0.035, ink)
	draw_circle(Vector2(rect.position.x + rect.size.x * 0.65, rect.position.y + rect.size.y * 0.39),
		rect.size.x * 0.035, ink)


# --------------------------------------------------------------------------
# Облачко
# --------------------------------------------------------------------------

func _draw_bubble(_ry: float) -> void:
	var a := _appear
	var bh := _bubble_height()
	var bx := _robot_size().x + GAP
	var by := roundf((size.y - bh) * 0.5)
	var rect := Rect2(bx, by, bubble_width, bh)
	var f := Theme90.ui()

	# Хвостик к коту.
	var tail_y := by + bh * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(bx + 2, tail_y - 7), Vector2(bx - 8, tail_y), Vector2(bx + 2, tail_y + 7)]),
		Color(1, 1, 1, a))
	draw_line(Vector2(bx + 2, tail_y - 7), Vector2(bx - 8, tail_y),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, a * 0.9), 1.0)
	draw_line(Vector2(bx - 8, tail_y), Vector2(bx + 2, tail_y + 7),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, a * 0.9), 1.0)

	draw_style_box(Theme90.box(Color(1, 1, 1, a),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, a), 8, 1,
		Color(0, 0, 0, 0.08 * a)), rect)

	var top := PAD_TOP_STEP if step > 0 else PAD_TOP
	if step > 0:
		var chip_w := 64.0 if progress_total > 0 else 40.0
		var chip := Rect2(bx + 12, by + 8, chip_w, 14)
		draw_style_box(Theme90.box(Color(Theme90.ACCENT_PALE.r, Theme90.ACCENT_PALE.g,
			Theme90.ACCENT_PALE.b, a), Color(0, 0, 0, 0), 3, 0), chip)
		var chip_text := "ШАГ %d" % step
		if progress_total > 0:
			chip_text = "ШАГ %d / %d" % [step, progress_total]
		Theme90.text(self, f, Vector2(chip.position.x + 6, chip.position.y + 1),
			chip_text, 9, Theme90.NAVY, -1, HORIZONTAL_ALIGNMENT_LEFT)
		if progress_total > 0:
			var pc := clampi(progress_current, 1, progress_total)
			var pw := float(pc) / float(progress_total)
			var track := Rect2(bx + 12, by + bh - 8, bubble_width - 24, PROGRESS_H)
			draw_style_box(Theme90.box(Color(Theme90.ACCENT_PALE.r, Theme90.ACCENT_PALE.g,
				Theme90.ACCENT_PALE.b, a), Color(0, 0, 0, 0), 2, 0), track)
			if pw > 0.0:
				var fill := Rect2(track.position, Vector2(maxf(2.0, track.size.x * pw),
					track.size.y))
				draw_style_box(Theme90.box(Color(Theme90.ACCENT.r, Theme90.ACCENT.g,
					Theme90.ACCENT.b, a), Color(0, 0, 0, 0), 2, 0), fill)

	var ty := by + top
	var ink := Color(Theme90.INK.r, Theme90.INK.g, Theme90.INK.b, a)
	if not title.is_empty():
		var navy := Color(Theme90.NAVY.r, Theme90.NAVY.g, Theme90.NAVY.b, a)
		Theme90.text(self, f, Vector2(bx + 13, ty), title, 11, navy,
			bubble_width - 26.0)
		ty += 17.0
	for i in _lines.size():
		Theme90.text(self, f, Vector2(bx + 13, ty + i * TEXT_LINE), _lines[i], 12, ink,
			bubble_width - 26.0)
