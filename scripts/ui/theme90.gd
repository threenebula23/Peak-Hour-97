class_name Theme90
extends RefCounted
## Палитра, шрифты и примитивы отрисовки в стиле shareware-программ 90-х.
##
## Никаких внешних текстур: всё рисуется кодом (фаски 2 px, гравировка,
## пиксельные иконки). Единый источник цветов/кеглей для всех UI-компонентов.

# --- Палитра ---------------------------------------------------------------
const FACE := Color(0.752941, 0.752941, 0.752941)        # #C0C0C0
const FACE_HI := Color(0.874510, 0.874510, 0.874510)     # #DFDFDF
const FACE_LO := Color(0.627451, 0.627451, 0.627451)     # #A0A0A0
const LIGHT := Color(1.0, 1.0, 1.0)                      # #FFFFFF
const SHADE := Color(0.501961, 0.501961, 0.501961)       # #808080
const DARK := Color(0.250980, 0.250980, 0.250980)        # #404040
const INK := Color(0.0, 0.0, 0.0)                        # #000000
const NAVY := Color(0.0, 0.0, 0.501961)                  # #000080
const NAVY_DEEP := Color(0.0, 0.0, 0.313726)             # #000050
const WHITE := Color(1.0, 1.0, 1.0)
const ERROR := Color(0.752941, 0.0, 0.0)                 # #C00000
const SUCCESS := Color(0.0, 0.439216, 0.0)               # #007000
const WARN := Color(0.752941, 0.501961, 0.0)             # #C08000
const ACCENT := Color(0.117647, 0.309804, 1.0)           # #1E4FFF
const ACCENT_LIGHT := Color(0.498039, 0.698039, 1.0)     # #7FB2FF
const ACCENT_PALE := Color(0.949020, 0.968627, 1.0)      # #F2F7FF

# --- Кегли ----------------------------------------------------------------
const FS_MICRO := 10
const FS_BODY := 12
const FS_HEAD := 16
const FS_LOGO := 24

const FONT_HANDJET := "res://art/fonts/Handjet-VF.ttf"
const FONT_LOGO := "res://art/fonts/PressStart2P-Regular.ttf"

const H := 24.0            # высота строки дерева / кнопки
const SCROLLBAR := 14.0    # ширина скроллбара
const BEVEL := 2.0         # толщина фаски

static var _fonts: Dictionary = {}
static var _dither: ImageTexture = null


# --- Шрифты ---------------------------------------------------------------

static func tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


## Handjet с фиксированными осями: wght 700, ELGR 2, ELSH 2.
static func ui(weight: float = 700.0, elgr: float = 2.0, elsh: float = 2.0) -> FontVariation:
	var key := "%d_%d_%d" % [weight, elgr, elsh]
	if _fonts.has(key):
		return _fonts[key]
	var base: FontFile = load(FONT_HANDJET)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {
		tag("wght"): weight,
		tag("ELGR"): elgr,
		tag("ELSH"): elsh,
	}
	_fonts[key] = fv
	return fv


static func logo() -> Font:
	if _fonts.has("logo"):
		return _fonts["logo"]
	var f: FontFile = load(FONT_LOGO)
	_fonts["logo"] = f
	return f


# --- Текст ----------------------------------------------------------------

## Рисует строку от верхнего левого угла (а не от базовой линии).
static func text(ci: CanvasItem, f: Font, top_left: Vector2, s: String, size: int, color: Color,
		width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if s.is_empty():
		return
	var baseline := roundf(top_left.y + f.get_ascent(size))
	ci.draw_string(f, Vector2(roundf(top_left.x), baseline), s, align, width, size, color)


static func text_vcenter(ci: CanvasItem, f: Font, rect: Rect2, s: String, size: int, color: Color,
		width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT, pad_left: float = 0.0) -> void:
	var h := f.get_height(size)
	var y := rect.position.y + roundf((rect.size.y - h) * 0.5)
	var x := rect.position.x + pad_left
	if width <= 0.0:
		width = rect.size.x - pad_left
	text(ci, f, Vector2(x, y), s, size, color, width, align)


## Гравировка: светлая тень на +1/+1 под тёмными буквами.
static func text_engraved(ci: CanvasItem, f: Font, top_left: Vector2, s: String, size: int,
		color: Color = SHADE) -> void:
	text(ci, f, top_left + Vector2(1, 1), s, size, LIGHT)
	text(ci, f, top_left, s, size, color)


## Обрезка с многоточием под заданную ширину.
static func fit(f: Font, s: String, size: int, width: float) -> String:
	if width <= 0.0 or s.is_empty():
		return s
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	var ell := "…"
	var lo := 0
	var hi := s.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		var probe := s.substr(0, mid).strip_edges() + ell
		if f.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			lo = mid
		else:
			hi = mid - 1
	return s.substr(0, lo).strip_edges() + ell


## Перенос по словам с ограничением строк (последняя — с многоточием).
static func wrap(f: Font, s: String, size: int, width: float, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	if s.is_empty():
		return out
	var words := s.split(" ", false)
	var cur := ""
	for w in words:
		var cand := w if cur.is_empty() else cur + " " + w
		if f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			cur = cand
		else:
			if not cur.is_empty():
				out.append(cur)
			cur = w
	var rest := cur
	if not rest.is_empty():
		out.append(rest)
	if out.size() > max_lines:
		var kept := PackedStringArray()
		for i in max_lines:
			kept.append(out[i])
		kept[max_lines - 1] = fit(f, kept[max_lines - 1] + " " + out[max_lines], size, width)
		out = kept
	else:
		for i in out.size():
			if f.get_string_size(out[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				out[i] = fit(f, out[i], size, width)
	return out


# --- Фаски ----------------------------------------------------------------

## Фаска: светлая сверху-слева, тёмная снизу-справа. pressed — наоборот.
static func draw_bevel(ci: CanvasItem, rect: Rect2, pressed: bool = false, thick: float = BEVEL,
		face: Color = FACE, light: Color = LIGHT, shade: Color = SHADE) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	ci.draw_rect(r, face)
	var tl := shade if pressed else light
	var br := light if pressed else shade
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, thick)), tl)
	ci.draw_rect(Rect2(r.position, Vector2(thick, r.size.y)), tl)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - thick), Vector2(r.size.x, thick)), br)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - thick, 0), Vector2(thick, r.size.y)), br)


## Дополнительная 1 px внутренняя подсветка — «двойная» фаска больших панелей.
static func draw_bevel_double(ci: CanvasItem, rect: Rect2, pressed: bool = false) -> void:
	draw_bevel(ci, rect, pressed)
	if pressed:
		ci.draw_rect(Rect2(rect.position + Vector2(BEVEL, BEVEL), Vector2(rect.size.x - BEVEL * 2.0, 1)), DARK)
		ci.draw_rect(Rect2(rect.position + Vector2(BEVEL, BEVEL), Vector2(1, rect.size.y - BEVEL * 2.0)), DARK)
	else:
		var inner := rect.grow(-BEVEL)
		ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), FACE_HI)
		ci.draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), FACE_HI)


static func draw_sunken(ci: CanvasItem, rect: Rect2, thick: float = BEVEL) -> void:
	draw_bevel(ci, rect, true, thick)


## Вертикальный градиент (для титлбаров и «стеклянных» акцентов).
static func draw_vgrad(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	ci.draw_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([top, top, bottom, bottom]))


## Пунктирная рамка (пустые слоты/папка).
static func draw_dashed_box(ci: CanvasItem, rect: Rect2, color: Color = SHADE, dash: float = 3.0,
		thick: float = 1.0) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	ci.draw_dashed_line(r.position, Vector2(r.end.x - 1, r.position.y), color, thick, dash)
	ci.draw_dashed_line(Vector2(r.end.x - 1, r.position.y), Vector2(r.end.x - 1, r.end.y - 1), color, thick, dash)
	ci.draw_dashed_line(Vector2(r.end.x - 1, r.end.y - 1), Vector2(r.position.x, r.end.y - 1), color, thick, dash)
	ci.draw_dashed_line(Vector2(r.position.x, r.end.y - 1), r.position, color, thick, dash)


## Классическая «сетка» выделения/дизейбла поверх области.
static func draw_hatch(ci: CanvasItem, rect: Rect2, color: Color, step: float = 4.0) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(maxf(x, r.position.x), r.position.y + maxf(0.0, r.position.x - x))
		var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + minf(r.size.y, r.end.x - x))
		if b.x > a.x:
			ci.draw_line(a, b, color, 1.0)
		x += step


# --- Пиксельные иконки ----------------------------------------------------

## Страница документа с глифом типа: text / sound / photo / video.
static func draw_doc_icon(ci: CanvasItem, rect: Rect2, kind: String, color: Color) -> void:
	var w := 14.0
	var h := 18.0
	var x := roundf(rect.position.x + (rect.size.x - w) * 0.5)
	var y := roundf(rect.position.y + (rect.size.y - h) * 0.5)
	ci.draw_rect(Rect2(x, y, w, h), WHITE)
	ci.draw_rect(Rect2(x, y, w, h), color, false, 1.0)
	# загнутый уголок
	ci.draw_rect(Rect2(x + w - 4, y + 1, 3, 3), FACE)
	ci.draw_line(Vector2(x + w - 4, y + 3), Vector2(x + w - 2, y + 1), color, 1.0)
	ci.draw_rect(Rect2(x + w - 4, y + 1, 1, 1), FACE)
	var gx := x + 3
	var gy := y + 7
	match kind:
		"text":
			for i in 3:
				ci.draw_rect(Rect2(gx, gy + i * 3, 8 - i, 1), color)
		"sound":
			ci.draw_rect(Rect2(gx + 1, gy + 6, 3, 3), color)
			ci.draw_rect(Rect2(gx + 4, gy, 1, 8), color)
			ci.draw_rect(Rect2(gx + 5, gy, 2, 1), color)
			ci.draw_rect(Rect2(gx + 6, gy + 1, 1, 2), color)
		"photo":
			ci.draw_rect(Rect2(gx, gy + 1, 9, 7), color, false, 1.0)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(gx + 1, gy + 7), Vector2(gx + 4, gy + 3), Vector2(gx + 7, gy + 7)]), color)
			ci.draw_rect(Rect2(gx + 6, gy + 2, 2, 2), color)
		"video":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(gx + 1, gy + 1), Vector2(gx + 9, gy + 5), Vector2(gx + 1, gy + 9)]), color)
		_:
			for i in 3:
				ci.draw_rect(Rect2(gx, gy + i * 3, 8, 1), color)


## Папка 14×11.
static func draw_folder_icon(ci: CanvasItem, pos: Vector2, color: Color = WARN, open: bool = false) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_rect(Rect2(x, y, 6, 2), color)
	ci.draw_rect(Rect2(x, y + 2, 13, 8), color)
	ci.draw_rect(Rect2(x + 1, y + 3, 11, 6), WHITE)
	if open:
		ci.draw_rect(Rect2(x + 1, y + 7, 11, 2), color)
	else:
		ci.draw_rect(Rect2(x + 1, y + 5, 11, 1), FACE_HI)


## Диск/секция: 12×9.
static func draw_drive_icon(ci: CanvasItem, pos: Vector2, color: Color = NAVY) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_rect(Rect2(x, y, 12, 9), color)
	ci.draw_rect(Rect2(x + 1, y + 1, 10, 4), WHITE)
	ci.draw_rect(Rect2(x + 2, y + 6, 3, 1), WHITE)
	ci.draw_rect(Rect2(x + 7, y + 6, 3, 1), WHITE)


## Замок 9×10.
static func draw_lock_icon(ci: CanvasItem, pos: Vector2, color: Color = DARK) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_rect(Rect2(x + 2, y, 5, 1), color)
	ci.draw_rect(Rect2(x + 1, y + 1, 1, 3), color)
	ci.draw_rect(Rect2(x + 7, y + 1, 1, 3), color)
	ci.draw_rect(Rect2(x, y + 4, 9, 6), color)
	ci.draw_rect(Rect2(x + 4, y + 6, 1, 2), FACE)


## Конверт/пакет 14×10.
static func draw_packet_icon(ci: CanvasItem, pos: Vector2, color: Color = NAVY) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_rect(Rect2(x, y, 14, 10), WHITE)
	ci.draw_rect(Rect2(x, y, 14, 10), color, false, 1.0)
	ci.draw_line(Vector2(x + 1, y + 1), Vector2(x + 6, y + 5), color, 1.0)
	ci.draw_line(Vector2(x + 12, y + 1), Vector2(x + 7, y + 5), color, 1.0)


## Стрелка в квадрате: dir 0 вверх, 1 вниз, 2 вправо, 3 влево.
static func draw_arrow(ci: CanvasItem, rect: Rect2, dir: int, color: Color) -> void:
	var c := rect.get_center().round()
	var s := 3.0
	var pts: PackedVector2Array
	match dir:
		0:
			pts = PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.4), c + Vector2(-s, s * 0.4)])
		1:
			pts = PackedVector2Array([c + Vector2(0, s), c + Vector2(s, -s * 0.4), c + Vector2(-s, -s * 0.4)])
		2:
			pts = PackedVector2Array([c + Vector2(s, 0), c + Vector2(-s * 0.4, s), c + Vector2(-s * 0.4, -s)])
		_:
			pts = PackedVector2Array([c + Vector2(-s, 0), c + Vector2(s * 0.4, s), c + Vector2(s * 0.4, -s)])
	ci.draw_colored_polygon(pts, color)


## Крестик.
static func draw_x(ci: CanvasItem, rect: Rect2, color: Color, thick: float = 1.0) -> void:
	var r := rect.grow(-3.0)
	ci.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x - 1, r.end.y - 1), color, thick)
	ci.draw_line(Vector2(r.end.x - 1, r.position.y), Vector2(r.position.x, r.end.y - 1), color, thick)


## Засечки-«решётка» для заблокированных превью.
static func draw_scanlines(ci: CanvasItem, rect: Rect2, color: Color, step: float = 2.0) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	var y := r.position.y
	while y < r.end.y:
		ci.draw_rect(Rect2(r.position.x, y, r.size.x, 1), color)
		y += step


# --- Текстура фона --------------------------------------------------------

## Слабый «дизеринг» 4×4 для рабочего стола (эпоха 8-битных обоев).
static func dither_texture() -> ImageTexture:
	if _dither != null:
		return _dither
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var a := Color(0.729412, 0.729412, 0.729412)
	var b := Color(0.752941, 0.752941, 0.752941)
	for yy in 4:
		for xx in 4:
			img.set_pixel(xx, yy, a if ((xx + yy) % 4 == 0) else b)
	_dither = ImageTexture.create_from_image(img)
	return _dither


# --- Фаска для произвольного Control --------------------------------------

## Слой-фаска, который живёт поверх Control и рисует только рамку.
class BevelLayer:
	extends Control
	var pressed := false
	var thick := 2.0
	var face := Color(0.752941, 0.752941, 0.752941)
	var sunken_background := false

	func _init(p_pressed: bool = false) -> void:
		pressed = p_pressed
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		if sunken_background:
			Theme90.draw_bevel(self, Rect2(Vector2.ZERO, size), pressed, thick, face)
		else:
			var r := Rect2(Vector2.ZERO, size)
			var tl := Theme90.SHADE if pressed else Theme90.LIGHT
			var br := Theme90.LIGHT if pressed else Theme90.SHADE
			draw_rect(Rect2(r.position, Vector2(r.size.x, thick)), tl)
			draw_rect(Rect2(r.position, Vector2(thick, r.size.y)), tl)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - thick), Vector2(r.size.x, thick)), br)
			draw_rect(Rect2(r.position + Vector2(r.size.x - thick, 0), Vector2(thick, r.size.y)), br)


## Добавляет фаску к любому Control (не меняя его собственный _draw).
static func apply_bevel(control: Control, pressed: bool = false, thick: float = 2.0,
		sunken_background: bool = false) -> BevelLayer:
	var layer := BevelLayer.new(pressed)
	layer.thick = thick
	layer.sunken_background = sunken_background
	control.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer


# --- Тема (используется art/fonts/ui_theme.tres) --------------------------

static func popup_panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FACE
	sb.border_color = DARK
	sb.set_border_width_all(1)
	sb.set_content_margin_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(3, 3)
	return sb


static func popup_hover_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY
	sb.set_content_margin_all(2)
	return sb


static func sunken_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FACE
	sb.border_color = SHADE
	sb.set_border_width_all(2)
	return sb


static func build_theme() -> Theme:
	var t := Theme.new()
	var f := ui()
	t.default_font = f
	t.default_font_size = FS_BODY

	# Label — базовый текст
	t.set_font("font", "Label", f)
	t.set_font_size("font_size", "Label", FS_BODY)
	t.set_color("font_color", "Label", INK)

	# Button (обычные кнопки внутри PopupMenu/диалогов)
	t.set_font("font", "Button", f)
	t.set_font_size("font_size", "Button", FS_BODY)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", SHADE)
	t.set_stylebox("normal", "Button", sunken_box())
	t.set_stylebox("hover", "Button", sunken_box())
	t.set_stylebox("pressed", "Button", sunken_box())
	t.set_stylebox("disabled", "Button", sunken_box())
	t.set_stylebox("focus", "Button", sunken_box())

	# PopupMenu — меню 90-х
	t.set_font("font", "PopupMenu", f)
	t.set_font_size("font_size", "PopupMenu", FS_BODY)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", WHITE)
	t.set_color("font_pressed_color", "PopupMenu", WHITE)
	t.set_color("font_disabled_color", "PopupMenu", SHADE)
	t.set_color("font_accelerator_color", "PopupMenu", DARK)
	t.set_color("font_separator_color", "PopupMenu", DARK)
	t.set_color("font_outline_color", "PopupMenu", LIGHT)
	t.set_stylebox("panel", "PopupMenu", popup_panel_box())
	t.set_stylebox("hover", "PopupMenu", popup_hover_box())
	t.set_constant("v_separation", "PopupMenu", 4)
	t.set_constant("h_separation", "PopupMenu", 6)
	t.set_constant("item_start_padding", "PopupMenu", 8)
	t.set_constant("item_end_padding", "PopupMenu", 12)
	t.set_constant("separator_outline_size", "PopupMenu", 0)

	# Подсказки
	t.set_stylebox("panel", "TooltipPanel", popup_panel_box())
	t.set_font("font", "TooltipLabel", f)
	t.set_font_size("font_size", "TooltipLabel", FS_MICRO)
	t.set_color("font_color", "TooltipLabel", INK)

	# LineEdit — на будущее (поиск/переименование)
	t.set_font("font", "LineEdit", f)
	t.set_font_size("font_size", "LineEdit", FS_BODY)
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("normal", "LineEdit", sunken_box())
	t.set_stylebox("focus", "LineEdit", sunken_box())

	# Panel
	t.set_stylebox("panel", "Panel", sunken_box())

	# Вариации под кегли 10/12/16/24 — единая шкала для разметки.
	t.set_type_variation("MicroLabel", "Label")
	t.set_font_size("font_size", "MicroLabel", FS_MICRO)
	t.set_color("font_color", "MicroLabel", DARK)
	t.set_type_variation("HeadLabel", "Label")
	t.set_font_size("font_size", "HeadLabel", FS_HEAD)
	t.set_font("font", "HeadLabel", f)
	t.set_type_variation("LogoLabel", "Label")
	t.set_font_size("font_size", "LogoLabel", FS_LOGO)
	t.set_font("font", "LogoLabel", logo())
	t.set_color("font_color", "LogoLabel", NAVY)
	t.set_type_variation("NumLabel", "Label")
	t.set_font("font", "NumLabel", logo())
	t.set_font_size("font_size", "NumLabel", FS_BODY)
	return t


## Призрак перетаскивания (alpha 0.7) — для файлов и пакетов.
class DragGhost:
	extends Control
	var label_text := ""
	var sub_text := ""
	var kind := "file"
	var tint := Color(1, 1, 1, 1)

	func _init(p_label: String, p_sub: String = "", p_kind: String = "file",
			p_tint: Color = Color(1, 1, 1, 1), p_icon := "text") -> void:
		label_text = p_label
		sub_text = p_sub
		kind = p_kind
		tint = p_tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate.a = 0.7
		var w := 168.0
		size = Vector2(w, 30)
		custom_minimum_size = size
		if kind == "packet":
			tint = Theme90.NAVY
		if p_icon == "packet":
			kind = "packet"

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, 0.95))
		Theme90.draw_bevel(self, r, false, 2.0, Color(1, 1, 1, 0.95))
		if kind == "packet":
			Theme90.draw_packet_icon(self, Vector2(6, 10), Theme90.NAVY)
		else:
			Theme90.draw_doc_icon(self, Rect2(3, 3, 24, 24), "text", tint)
		var f := Theme90.ui()
		Theme90.text(self, f, Vector2(32, 3), Theme90.fit(f, label_text, 12, size.x - 38), 12, Theme90.INK)
		if not sub_text.is_empty():
			Theme90.text(self, f, Vector2(32, 17), Theme90.fit(f, sub_text, 10, size.x - 38),
				10, Theme90.DARK)


## Числовая строка: цифры — Press Start 2P (чистые 0), суффикс — Handjet.
## Базовая линия суффикса совпадает с базовой линией цифр.
static func num_line(ci: CanvasItem, top_left: Vector2, number: String, size: int, color: Color,
		suffix: String = "", suffix_size: int = -1) -> float:
	var nf := logo()
	var sf := ui()
	var ss := size if suffix_size < 0 else suffix_size
	var baseline := roundf(top_left.y + sf.get_ascent(ss))
	ci.draw_string(nf, Vector2(roundf(top_left.x), baseline), number, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	var w := nf.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if not suffix.is_empty():
		ci.draw_string(sf, Vector2(roundf(top_left.x + w + 1.0), baseline), suffix,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ss, color)
		w += sf.get_string_size(suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	return w


## Ширина числовой строки (для выравнивания).
static func num_width(number: String, size: int, suffix: String = "", suffix_size: int = -1) -> float:
	var ss := size if suffix_size < 0 else suffix_size
	var w := logo().get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if not suffix.is_empty():
		w += 1.0 + ui().get_string_size(suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	return w


## Числовая строка, выровненная по правому краю.
static func num_right(ci: CanvasItem, right_x: float, top_left_y: float, number: String, size: int,
		color: Color, suffix: String = "", suffix_size: int = -1) -> float:
	var w := num_width(number, size, suffix, suffix_size)
	num_line(ci, Vector2(right_x - w, top_left_y), number, size, color, suffix, suffix_size)
	return w


## Маленькая процедурная иконка-квадрат (для пунктов меню).
static func square_texture(color: Color, px: int = 8) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
