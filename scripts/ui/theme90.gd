class_name Theme90
extends RefCounted
## Палитра, шрифты и примитивы отрисовки UI. Версия 2 — «тёплая бумага»:
## тонкие 1 px контуры вместо 2 px фасок, мягкие тени, скругления 3–4 px.
##
## Почти всё рисуется кодом; исключение — пиксельные иконки файлов из
## art/icons (их можно заменить или перегенерировать generate_icons.py).
## Единый источник цветов, кеглей и StyleBox для всех UI-компонентов.

# --- Палитра ---------------------------------------------------------------
const PAPER := Color(0.913725, 0.901961, 0.866667)       # #E9E6DD
const PAPER_HI := Color(0.968627, 0.960784, 0.933333)    # #F7F5EE
const PAPER_LO := Color(0.847059, 0.827451, 0.788235)    # #D8D3C9
const LIGHT := Color(1.0, 1.0, 1.0)                      # #FFFFFF
const WHITE := Color(1.0, 1.0, 1.0)
const SHADE := Color(0.603922, 0.584314, 0.541176)       # #9A958A
const DARK := Color(0.172549, 0.164706, 0.149020)        # #2C2A26
const INK := Color(0.121569, 0.117647, 0.105882)         # #1F1E1B

const NAVY := Color(0.172549, 0.360784, 0.407843)        # #2C5C68 — «navy»-бирюза
const NAVY_DEEP := Color(0.121569, 0.274510, 0.313726)   # #1F4650
const ACCENT := Color(0.184314, 0.498039, 0.560784)      # #2F7F8F
const ACCENT_LIGHT := Color(0.513726, 0.780392, 0.831373) # #83C7D4
const ACCENT_PALE := Color(0.901961, 0.960784, 0.968627) # #E6F5F7

const ERROR := Color(0.760784, 0.356863, 0.290196)       # #C25B4A
const SUCCESS := Color(0.247059, 0.560784, 0.368627)     # #3F8F5E
const WARN := Color(0.772549, 0.541176, 0.180392)        # #C58A2E
const SHADOW := Color(0.0, 0.0, 0.0, 0.094)              # #00000018

# --- ЯРКИЕ АКЦЕНТЫ (v3) ----------------------------------------------------
# Дополнительные цвета для заголовков окон, групп, статусов и карточек
# магазина. База («тёплая бумага») остаётся прежней: акценты вводятся
# полосами, подложками 5–12 % и контурами, а не сменой фона интерфейса.
# Пары *_DEEP — текстовые: на PAPER_HI (#F7F5EE) контраст ≥ 4.5:1.
const BLUE := Color(0.196078, 0.400000, 0.588235)        # #326699
const PURPLE := Color(0.443137, 0.317647, 0.588235)      # #715196
const PINK := Color(0.741176, 0.298039, 0.462745)        # #BD4C76
const ORANGE := Color(0.788235, 0.443137, 0.145098)      # #C97125
const LIME := Color(0.364706, 0.588235, 0.239216)        # #5D963D
const GOLD := Color(0.831373, 0.650980, 0.188235)        # #D4A630

const BLUE_DEEP := Color(0.152941, 0.309804, 0.450980)   # #274F73
const PURPLE_DEEP := Color(0.305882, 0.207843, 0.419608) # #4E356B
const PINK_DEEP := Color(0.560784, 0.184314, 0.333333)   # #8F2F55
const ORANGE_DEEP := Color(0.478431, 0.290196, 0.070588) # #7A4A12
const LIME_DEEP := Color(0.247059, 0.419608, 0.164706)   # #3F6B2A
const GOLD_DEEP := Color(0.419608, 0.317647, 0.050980)   # #6B510D
const SUCCESS_DEEP := Color(0.168627, 0.407843, 0.254902) # #2B6841
const WARN_DEEP := Color(0.470588, 0.321569, 0.094118)   # #785218
const ERROR_DEEP := Color(0.552941, 0.203922, 0.156863)  # #8D3428


## Мягкая цветная подложка на бумаге: amount 0 — PAPER_HI, 1 — чистый цвет.
## Используется карточками магазина, шапками окон и групп.
static func paper_tint(c: Color, amount: float) -> Color:
	return PAPER_HI.lerp(Color(c.r, c.g, c.b), clampf(amount, 0.0, 1.0))


## Полупрозрачный оттенок акцента — для бейджей, полос и ореолов.
static func alpha_of(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))

# --- ЖАРА: температура узла ------------------------------------------------
# Аддитивный слой визуальной системы нагрева. COOL = NAVY,
# WARM = WARN.darkened(0.35), HOT = ERROR.darkened(0.15),
# CRIT = ERROR.darkened(0.30). Текст использует отдельные, более тёмные
# оттенки: на PAPER (#E9E6DD) контраст каждого ≥ 4.5:1.
const HEAT_COOL := Color(0.172549, 0.360784, 0.407843)   # #2C5C68
const HEAT_WARM := Color(0.502157, 0.351765, 0.117255)   # #804F1E
const HEAT_HOT := Color(0.646666, 0.303334, 0.246667)    # #A54D3F
const HEAT_CRIT := Color(0.532549, 0.249804, 0.203137)   # #884033


## Цвет колбы/маркера по уровню нагрева.
static func heat_color(level: int) -> Color:
	match clampi(level, 0, 3):
		1:
			return HEAT_WARM
		2:
			return HEAT_HOT
		3:
			return HEAT_CRIT
	return HEAT_COOL


## Цвет подписи/числа по уровню: затемнён для контраста ≥ 4.5:1 на бумаге.
static func heat_text_color(level: int) -> Color:
	match clampi(level, 0, 3):
		1:
			return Color(0.424902, 0.297647, 0.099216)
		2:
			return Color(0.570588, 0.267647, 0.217647)
		3:
			return Color(0.456470, 0.214118, 0.174118)
	return NAVY_DEEP


## Полное имя уровня для подсказки.
static func heat_level_name(level: int) -> String:
	match clampi(level, 0, 3):
		1:
			return "ТЕПЛО"
		2:
			return "ГОРЯЧО"
		3:
			return "КРИТ"
	return "СПОКОЙНО"


## Короткая подпись в меню-баре: 0 — ТЕМП, 3 — КРИТ.
static func heat_short_name(level: int) -> String:
	match clampi(level, 0, 3):
		1:
			return "ТЕПЛО"
		2:
			# «ГОРЯЧО» шире колбы (44 px) — в меню-баре используем «ЖАРА».
			return "ЖАРА"
		3:
			return "КРИТ"
	return "ТЕМП"

# Совместимость со старыми именами: поверхности теперь бумажные.
const FACE := PAPER
const FACE_HI := PAPER_HI
const FACE_LO := PAPER_LO

# Линии: тонкие, тёплые, с прозрачностью — не «фаски».
const BORDER := Color(0.254902, 0.239216, 0.203922, 0.22)
const BORDER_SOFT := Color(0.254902, 0.239216, 0.203922, 0.12)
const HAIRLINE := Color(0.254902, 0.239216, 0.203922, 0.10)

# --- Кегли ----------------------------------------------------------------
# Шкала 11/13/17/26 зафиксирована проверкой ui_smoke.gd — менять только вместе
# с ней. Кегли крупнее 26 px передаются на местах вызова (24/28/34/46).
const FS_MICRO := 11
const FS_BODY := 13
const FS_HEAD := 17
const FS_LOGO := 26

## Основной шрифт — Kechusilka Regular. Нормализован под метрики Golos Text
## (x-height 0.530 em, те же пропорции строки), поэтому шкала 11/13/17/26
## работает без пересчёта вёрстки. Статический: оси wght нет.
const FONT_UI := "res://art/fonts/Kechusilka-Regular.otf"
## Крупный текст: логотип, заголовки 18 px и выше, «ПОБЕДА»/«ПОРАЖЕНИЕ».
## Не для тела текста и не для живых счётчиков (см. display()).
const FONT_DISPLAY := "res://art/fonts/DisplayOTF.otf"
## Числовой и брендовый акцент — Press Start 2P. Цифры ровно 1 em,
## поэтому счётчики не «дрожат» при смене значения.
const FONT_LOGO := "res://art/fonts/PressStart2P-Regular.ttf"
## Страховка для глифов, которых нет в Kechusilka и DisplayOTF:
## № – … · × ← → ↑ ↓ ≤ ≥ § ° € • © ± ≈ −. Golos Text закрывает их все.
const FONT_FALLBACK := "res://art/fonts/GolosText-VF.ttf"
## Kechusilka статическая (fvar нет): wght не запрашиваем, иначе вариация
## уходит в файл, где такой оси нет.
const FONT_UI_HAS_WGHT := false

const ICON_DIR := "res://art/icons"

const H := 24.0            # высота строки дерева / кнопки
const SCROLLBAR := 14.0    # ширина скроллбара
const BEVEL := 1.0         # оставлено для совместимости: толщина линии
const RADIUS := 3          # базовое скругление карточек и кнопок

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}
static var _dither: ImageTexture = null
static var _boxes: Dictionary = {}


# --- Шрифты ---------------------------------------------------------------

static func tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


## Страховочный шрифт: подхватывает символы, которых нет в Kechusilka
## (№ – … · × ← → и т.п.) и в DisplayOTF. Кэшируется один раз.
static func fallback_font() -> Font:
	if _fonts.has("fallback"):
		return _fonts["fallback"]
	var f: FontFile = load(FONT_FALLBACK)
	_fonts["fallback"] = f
	return f


## Основной UI-шрифт — всегда FontVariation: этого ожидают тема и ui_smoke.
## База — Kechusilka, к ней прицеплен Golos Text как fallback, чтобы редкие
## символы (№, –, …, ·, ×, стрелки) не превращались в «квадратики».
## weight — 400–900 только для variable-шрифта. Сейчас FONT_UI_HAS_WGHT =
## false (Kechusilka статическая), поэтому значение принимается, но не
## применяется; акценты делаются цветом и кеглем, а не «жирным».
## elgr/elsh оставлены в сигнатуре для совместимости со старыми вызовами
## Handjet — у Golos Text и DisplayOTF таких осей нет, значения игнорируются.
static func ui(weight: float = 600.0, _elgr: float = 1.0, _elsh: float = 1.0) -> FontVariation:
	var w := clampf(weight, 400.0, 900.0)
	if not FONT_UI_HAS_WGHT:
		w = 400.0
	var key := "ui_%d" % int(roundf(w))
	if _fonts.has(key):
		return _fonts[key]
	var base: FontFile = load(FONT_UI)
	var fv := FontVariation.new()
	fv.base_font = base
	if FONT_UI_HAS_WGHT:
		fv.variation_opentype = {
			tag("wght"): w,
		}
	fv.fallbacks = [fallback_font()]
	_fonts[key] = fv
	return fv


## Крупный текст — DisplayOTF: узкий плотный рисунок в духе цифрового табло,
## та же «машинная» интонация, что у Press Start 2P, но с характером.
## Только 16 px и выше: мельче насечки сливаются.
## Цифры пропорциональные и без кернинга (GPOS в файле нет), поэтому
## живые счётчики и часы остаются на logo().
static func display() -> Font:
	if _fonts.has("display"):
		return _fonts["display"]
	var fv := FontVariation.new()
	fv.base_font = load(FONT_DISPLAY)
	fv.fallbacks = [fallback_font()]
	_fonts["display"] = fv
	return fv


## Числовой и брендовый акцент — Press Start 2P. Цифры моноширинные (1 em),
## поэтому num_line()/num_right() и часы в шапке не меняют ширину при
## обновлении значения. Для крупного текста — display().
static func logo() -> Font:
	if _fonts.has("logo"):
		return _fonts["logo"]
	var fv := FontVariation.new()
	fv.base_font = load(FONT_LOGO)
	# Не мутируем общий FontFile: fallback только для отсутствующих глифов.
	fv.fallbacks = [fallback_font()]
	_fonts["logo"] = fv
	return fv


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


## Центрирует одиночный глиф по видимым (ink) границам, а не по строковым
## метрикам. Нужен для «?» в квадратных well/бейджах: у Press Start 2P
## верхний вынос больше нижнего, а боковой bearing отрицательный, поэтому
## text_vcenter оставляет знак выше и левее геометрического центра.
## Для строк из 2+ символов — обычный text_vcenter.
static func glyph_center(ci: CanvasItem, f: Font, rect: Rect2, s: String, size: int,
		color: Color) -> void:
	if s.is_empty():
		return
	var ts := TextServerManager.get_primary_interface()
	if s.length() > 1 or ts == null or f.get_rids().is_empty():
		text_vcenter(ci, f, rect, s, size, color, -1, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var rid: RID = f.get_rids()[0]
	var gi := ts.font_get_glyph_index(rid, size, s.unicode_at(0), 0)
	var ink: Rect2
	if gi > 0:
		ink = Rect2(ts.font_get_glyph_offset(rid, Vector2i(size, 0), gi),
			ts.font_get_glyph_size(rid, Vector2i(size, 0), gi))
	else:
		var asc := f.get_ascent(size)
		ink = Rect2(0.0, -asc,
			f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
			asc + f.get_descent(size))
	var origin := Vector2(
		rect.position.x + roundf((rect.size.x - ink.size.x) * 0.5) - ink.position.x,
		rect.position.y + roundf((rect.size.y - ink.size.y) * 0.5) - ink.position.y)
	ci.draw_string(f, origin.round(), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Совместимость: раньше «гравировка» с белой тенью. Теперь — спокойный текст.
static func text_engraved(ci: CanvasItem, f: Font, top_left: Vector2, s: String, size: int,
		color: Color = SHADE) -> void:
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


# --- StyleBox -------------------------------------------------------------

## Кэшированный StyleBoxFlat: бумажная поверхность, 1 px контур, мягкая тень.
static func box(bg: Color, border: Color = BORDER, radius: int = RADIUS, border_w: int = 1,
		shadow: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%s" % [bg.to_html(), border.to_html(), radius, border_w, shadow.to_html()]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.corner_detail = 4
	sb.anti_aliasing = true
	if shadow.a > 0.0:
		sb.shadow_color = shadow
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0.0, 2.0)
	_boxes[key] = sb
	return sb


## Спокойная заливка без контура (фоны полос, подложки).
static func fill_box(bg: Color, radius: int = 0) -> StyleBoxFlat:
	return box(bg, Color(0, 0, 0, 0), radius, 0)


## Мягкая «карточка»: панель, окно, карточка файла.
static func card_box(bg: Color = PAPER_HI) -> StyleBoxFlat:
	return box(bg, BORDER, 4, 1, SHADOW)


## Верхняя полоса с скруглёнными верхними углами (титлбар окна).
static func top_box(bg: Color = WHITE, radius: int = 4) -> StyleBoxFlat:
	var key := "top|%s|%d" % [bg.to_html(), radius]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_detail = 4
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb


## Единый светлый титлбар модалки: тонкая полоса, тёмный текст, teal-точка.
## Высота по умолчанию 20 px — как у старых TITLE_H, чтобы не двигать контент.
static func modal_header(ci: CanvasItem, rect: Rect2, title: String, hint: String = "",
		h: float = 20.0) -> void:
	var tr := Rect2(rect.position.x + 1.0, rect.position.y + 1.0,
		maxf(0.0, rect.size.x - 2.0), h)
	ci.draw_style_box(top_box(PAPER_HI, 6), tr)
	ci.draw_rect(Rect2(tr.position.x + 1.0, tr.end.y, tr.size.x - 2.0, 1.0), HAIRLINE)
	ci.draw_circle(Vector2(tr.position.x + 10.0, tr.position.y + h * 0.5), 2.5, ACCENT)
	var f := ui()
	var th := f.get_height(FS_BODY)
	text(ci, f, Vector2(tr.position.x + 18.0,
		tr.position.y + roundf((h - th) * 0.5)), title, FS_BODY, NAVY_DEEP,
		tr.size.x - 90.0)
	if not hint.is_empty():
		var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_MICRO).x
		text(ci, f, Vector2(tr.end.x - hw - 34.0, tr.position.y + roundf((h - 12.0) * 0.5)),
			hint, FS_MICRO, SHADE)


## Утопленная поверхность (поля ввода, дорожки, пустые слоты).
static func well_box(bg: Color = PAPER_HI) -> StyleBoxFlat:
	return box(bg, BORDER_SOFT, 3, 1)


static func accent_line_color() -> Color:
	return ACCENT


# --- Контуры и панели -----------------------------------------------------

## Карточка/кнопка: заливка + 1 px контур + 1 px блик + мягкая тень.
## pressed — на 1 px темнее и с тонкой внутренней линией сверху.
static func draw_bevel(ci: CanvasItem, rect: Rect2, pressed: bool = false, thick: float = BEVEL,
		face: Color = FACE, light: Color = LIGHT, shade: Color = SHADE) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	if r.size.x < 2.0 or r.size.y < 2.0:
		ci.draw_rect(r, face)
		return
	var dark_surface := face.get_luminance() < 0.55
	var border := Color(0, 0, 0, 0.16) if dark_surface else BORDER
	if pressed:
		var sunk := face.darkened(0.045) if not dark_surface else face.darkened(0.10)
		ci.draw_style_box(box(sunk, border, RADIUS, 1), r)
		if r.size.y >= 10.0:
			ci.draw_line(Vector2(r.position.x + 3, r.position.y + 1),
				Vector2(r.end.x - 3, r.position.y + 1), Color(0, 0, 0, 0.10), 1.0)
		return
	ci.draw_style_box(box(face, border, RADIUS, 1, SHADOW), r)
	if r.size.y >= 16.0 and thick > 0.0:
		var hi := Color(1, 1, 1, 0.42) if not dark_surface else Color(1, 1, 1, 0.12)
		ci.draw_line(Vector2(r.position.x + 3, r.position.y + 1),
			Vector2(r.end.x - 3, r.position.y + 1), hi, 1.0)


## Совместимость: двойная фаска больше не нужна — оставляем один контур.
static func draw_bevel_double(ci: CanvasItem, rect: Rect2, pressed: bool = false) -> void:
	draw_bevel(ci, rect, pressed, BEVEL, FACE)


## Утопленное поле: светлая поверхность, тонкий контур, без объёма.
static func draw_sunken(ci: CanvasItem, rect: Rect2, thick: float = BEVEL) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	ci.draw_style_box(well_box(FACE_HI), r)
	if r.size.y > 8.0:
		ci.draw_line(Vector2(r.position.x + 3, r.position.y + 1),
			Vector2(r.end.x - 3, r.position.y + 1), Color(0, 0, 0, 0.055), 1.0)


## Вертикальный градиент (мягкие акценты, без «стекла 90-х»).
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


## Очень мягкая «сетка» для заблокированных областей.
static func draw_hatch(ci: CanvasItem, rect: Rect2, color: Color, step: float = 4.0) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(maxf(x, r.position.x), r.position.y + maxf(0.0, r.position.x - x))
		var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + minf(r.size.y, r.end.x - x))
		if b.x > a.x:
			ci.draw_line(a, b, color, 1.0)
		x += step


## Тонкий индикатор/шкала: дорожка + заливка, скруглённые.
static func draw_meter(ci: CanvasItem, rect: Rect2, ratio: float, color: Color,
		track: Color = PAPER_LO) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	var rad := int(maxf(1.0, floorf(r.size.y * 0.5)))
	ci.draw_style_box(fill_box(track, rad), r)
	var w := floorf(r.size.x * clampf(ratio, 0.0, 1.0))
	if w >= 2.0:
		ci.draw_style_box(fill_box(color, rad), Rect2(r.position, Vector2(w, r.size.y)))


# --- Пиксельные иконки ----------------------------------------------------

## Категория расширения файла: doc / pdf / image / audio / video / archive /
## program / table. Пустая строка — расширение неизвестно.
static func ext_category(ext: String) -> String:
	var e := ext.strip_edges().to_lower()
	while e.begins_with("."):
		e = e.substr(1)
	match e:
		"txt", "md", "doc", "docx", "rtf", "odt":
			return "doc"
		"pdf":
			return "pdf"
		"jpg", "jpeg", "png", "gif", "bmp", "webp", "tif", "tiff":
			return "image"
		"mp3", "wav", "ogg", "flac", "m4a", "aac":
			return "audio"
		"mp4", "avi", "mov", "mkv", "webm":
			return "video"
		"zip", "rar", "7z", "gz", "tar":
			return "archive"
		"exe", "msi", "bat", "sh", "com":
			return "program"
		"csv", "xls", "xlsx", "ods":
			return "table"
	return ""


## Цвет категории — только из палитры Theme90, совпадает со type_color().
static func ext_color(cat: String) -> Color:
	match cat:
		"doc", "pdf":
			return ACCENT
		"image", "table":
			return SUCCESS
		"audio", "archive":
			return WARN
		"video":
			return ERROR
		"program":
			return NAVY
	return ACCENT


## Пиксельные иконки 32×32 из art/icons (generate_icons.py). Ключи — те же
## имена типов, что и в FileShape (text/sound/photo/video), плюс folder/packet.
const ICON_FILES := {
	"text": "file_text",
	"doc": "file_text",
	"pdf": "file_text",
	"sound": "file_sound",
	"audio": "file_sound",
	"photo": "file_photo",
	"image": "file_photo",
	"video": "file_video",
	"folder": "folder",
	"packet": "packet",
}

## Иконки лотов магазина (см. shop_icon_path). Ключ — id лота, fallback — effect.
const SHOP_ICON_DIR := "res://art/icons/shop"
const SHOP_ICON_BY_EFFECT := {
	"connection_slots": "lot_slots",
	"transfer_speed": "lot_speed",
	"sla_cap": "lot_sla",
	"shield_charge": "lot_shield",
	"money_mult": "lot_money",
	"folder_cells": "lot_folder",
	"channel_capacity": "lot_channel",
	"request_timer": "lot_timer",
	"udp_success": "lot_udp",
}


## Текстура иконки по типу (кэшируется). null — файла нет или тип неизвестен.
static func file_icon(kind: String) -> Texture2D:
	var key := kind.strip_edges().to_lower()
	if _icons.has(key):
		return _icons[key]
	var tex: Texture2D = null
	var file_name: String = str(ICON_FILES.get(key, ""))
	if not file_name.is_empty():
		var path := ICON_DIR + "/" + file_name + ".png"
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	_icons[key] = tex
	return tex


## Рисует иконку по центру rect с ближайшей фильтрацией (пиксели остаются
## резкими при 16/24/32 px). false — если текстуры нет, рисуйте draw_doc_icon.
static func draw_file_icon(ci: CanvasItem, rect: Rect2, kind: String,
		modulate: Color = Color.WHITE) -> bool:
	var tex := file_icon(kind)
	if tex == null:
		return false
	var s := minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return false
	var side := roundf(s)
	var top_left := (rect.position + (rect.size - Vector2(side, side)) * 0.5).round()
	var target := Rect2(top_left, Vector2(side, side))
	var prev := ci.texture_filter
	if prev != CanvasItem.TEXTURE_FILTER_NEAREST:
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.draw_texture_rect(tex, target, false, modulate)
	if prev != CanvasItem.TEXTURE_FILTER_NEAREST:
		ci.texture_filter = prev
	return true


## Путь к иконке лота: имя файла — id лота (lot_*), для legacy-каталога
## без id — fallback по effect. "" — иконки нет.
static func shop_icon_path(id: String, effect: String = "") -> String:
	var key := id.strip_edges().to_lower()
	if not key.begins_with("lot_"):
		key = str(SHOP_ICON_BY_EFFECT.get(effect.strip_edges().to_lower(), ""))
	if key.is_empty():
		return ""
	var path := SHOP_ICON_DIR + "/" + key + ".png"
	return path if ResourceLoader.exists(path) else ""


## Текстура иконки лота (кэшируется). null — иконки нет, рисуйте без неё.
static func shop_icon(id: String, effect: String = "") -> Texture2D:
	var path := shop_icon_path(id, effect)
	if path.is_empty():
		return null
	if _icons.has(path):
		return _icons[path]
	var tex := load(path) as Texture2D
	_icons[path] = tex
	return tex


## Рисует иконку лота по центру rect с ближайшей фильтрацией (pixel art).
## false — если текстуры нет: карточка остаётся без иконки.
static func draw_shop_icon(ci: CanvasItem, rect: Rect2, id: String,
		effect: String = "") -> bool:
	var tex := shop_icon(id, effect)
	if tex == null:
		return false
	var s := minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return false
	var side := roundf(s)
	var target := Rect2(
		(rect.position + (rect.size - Vector2(side, side)) * 0.5).round(),
		Vector2(side, side))
	var prev := ci.texture_filter
	if prev != CanvasItem.TEXTURE_FILTER_NEAREST:
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.draw_texture_rect(tex, target, false)
	if prev != CanvasItem.TEXTURE_FILTER_NEAREST:
		ci.texture_filter = prev
	return true


## Документ с цветным глифом. ext (необязательный) выбирает значок по
## расширению: строки, горы, волна, play, молния, терминал, сетка.
## Пустое/неизвестное расширение — прежний глиф типа (text/sound/photo/video).
static func draw_doc_icon(ci: CanvasItem, rect: Rect2, kind: String, color: Color,
		ext: String = "") -> void:
	var s := minf(rect.size.x, rect.size.y)
	var tile := Rect2(rect.position.round() + Vector2(roundf((rect.size.x - s) * 0.5),
		roundf((rect.size.y - s) * 0.5)), Vector2(s, s))
	var rad := int(clampf(s * 0.24, 4.0, 7.0))
	ci.draw_style_box(fill_box(Color(color.r, color.g, color.b, 0.13), rad), tile)
	var w := clampf(roundf(s * 0.48), 10.0, 16.0)
	var h := clampf(roundf(s * 0.64), 13.0, 21.0)
	var x := roundf(tile.get_center().x - w * 0.5)
	var y := roundf(tile.get_center().y - h * 0.5)
	var page := Rect2(x, y, w, h)
	ci.draw_style_box(box(WHITE, Color(color.r, color.g, color.b, 0.45), 1, 1), page)
	# загнутый уголок
	var fold := clampf(roundf(s * 0.17), 3.0, 5.0)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x + w - fold, y + 1), Vector2(x + w - 1, y + fold),
		Vector2(x + w - fold, y + fold)]),
		Color(color.r, color.g, color.b, 0.22))
	match ext_category(ext):
		"doc":
			_glyph_doc(ci, page, color)
		"pdf":
			_glyph_pdf(ci, page, color)
		"image":
			_glyph_image(ci, page, color)
		"audio":
			_glyph_audio(ci, page, color)
		"video":
			_glyph_video(ci, page, color)
		"archive":
			_glyph_archive(ci, page, color)
		"program":
			_glyph_program(ci, page, color)
		"table":
			_glyph_table(ci, page, color)
		_:
			_glyph_kind(ci, page, kind, color)


## Масштаб глифа: 1.0 при иконке 24×24, меньше на мелких (20×20).
static func _glyph_unit(page: Rect2) -> float:
	return clampf(minf(page.size.x / 12.0, page.size.y / 15.0), 0.7, 1.4)


## Документ: строки текста.
static func _glyph_doc(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var gx := page.position.x + roundf(2.0 * u)
	var gy := page.position.y + roundf(5.0 * u)
	var gw := roundf(8.0 * u)
	for i in 3:
		var lw := gw - (2.0 * u if i == 1 else 0.0)
		ci.draw_rect(Rect2(gx, gy + roundf(i * 3.0 * u), lw, 1.0), color)


## PDF: короткие строки + красная метка в правом нижнем углу страницы.
static func _glyph_pdf(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var gx := page.position.x + roundf(2.0 * u)
	var gy := page.position.y + roundf(3.0 * u)
	ci.draw_rect(Rect2(gx, gy, roundf(6.0 * u), 1.0), color)
	ci.draw_rect(Rect2(gx, gy + roundf(3.0 * u), roundf(4.0 * u), 1.0), color)
	var tag := Rect2(page.position.x + page.size.x - roundf(7.0 * u),
		page.position.y + page.size.y - roundf(6.0 * u),
		roundf(6.0 * u), roundf(5.0 * u))
	var tag_col := Color(ERROR.r, ERROR.g, ERROR.b, 0.92)
	if color.s < 0.2:
		tag_col = Color(color.r, color.g, color.b, 0.5)
	ci.draw_style_box(fill_box(tag_col, 1), tag)
	ci.draw_rect(Rect2(tag.position.x + roundf(1.5 * u), tag.position.y + roundf(2.0 * u),
		roundf(3.0 * u), 1.0), WHITE)


## Изображение: горы и солнце.
static func _glyph_image(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var p := page.position
	ci.draw_rect(Rect2(roundf(p.x + 2.8 * u), roundf(p.y + 2.8 * u),
		maxf(1.0, roundf(1.8 * u)), maxf(1.0, roundf(1.8 * u))), color)
	var yb := p.y + page.size.y - roundf(2.8 * u)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(p.x + 1.6 * u, yb),
		Vector2(p.x + 4.0 * u, yb - 5.0 * u),
		Vector2(p.x + 5.9 * u, yb - 2.2 * u),
		Vector2(p.x + 7.5 * u, yb - 4.0 * u),
		Vector2(p.x + 10.4 * u, yb)]), color)


## Аудио: волна из четырёх полос.
static func _glyph_audio(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var p := page.position
	var baseline := p.y + page.size.y - roundf(3.5 * u)
	var bw := maxf(1.0, roundf(1.2 * u))
	var hs := [3.0, 6.0, 4.5, 2.5]
	for i in 4:
		var bx := p.x + roundf(2.3 * u + i * 1.9 * u)
		var hh := maxf(1.0, roundf(hs[i] * u))
		ci.draw_rect(Rect2(bx, baseline - hh, bw, hh), color)


## Видео: перфорация плёнки и play.
static func _glyph_video(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var p := page.position
	for i in 3:
		ci.draw_rect(Rect2(p.x + roundf((3.0 + i * 2.6) * u), p.y + roundf(3.4 * u),
			maxf(1.0, roundf(1.3 * u)), maxf(1.0, roundf(1.2 * u))), color)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(p.x + 2.8 * u, p.y + 5.8 * u),
		Vector2(p.x + 2.8 * u, p.y + 12.6 * u),
		Vector2(p.x + 9.2 * u, p.y + 9.2 * u)]), color)


## Архив: молния.
static func _glyph_archive(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var p := page.position
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(p.x + 7.6 * u, p.y + 2.6 * u),
		Vector2(p.x + 3.2 * u, p.y + 8.4 * u),
		Vector2(p.x + 5.9 * u, p.y + 8.4 * u),
		Vector2(p.x + 4.4 * u, p.y + 12.4 * u),
		Vector2(p.x + 8.8 * u, p.y + 6.4 * u),
		Vector2(p.x + 6.1 * u, p.y + 6.4 * u)]), color)


## Программа: окно терминала с приглашением «>_».
static func _glyph_program(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var p := page.position
	var frame := Rect2(p.x + roundf(1.8 * u), p.y + roundf(4.2 * u),
		roundf(8.4 * u), roundf(7.6 * u))
	ci.draw_rect(frame, color, false, 1.0)
	ci.draw_rect(Rect2(frame.position.x + 1.0, frame.position.y + roundf(2.2 * u),
		frame.size.x - 2.0, 1.0), color)
	var px := frame.position.x
	var py := frame.position.y + roundf(3.6 * u)
	ci.draw_line(Vector2(px + roundf(2.2 * u), py),
		Vector2(px + roundf(3.4 * u), py + roundf(1.3 * u)), color, 1.0)
	ci.draw_line(Vector2(px + roundf(3.4 * u), py + roundf(1.3 * u)),
		Vector2(px + roundf(2.2 * u), py + roundf(2.6 * u)), color, 1.0)
	ci.draw_rect(Rect2(px + roundf(4.6 * u), py + roundf(1.9 * u),
		roundf(2.2 * u), 1.0), color)


## Таблица: сетка 3×3.
static func _glyph_table(ci: CanvasItem, page: Rect2, color: Color) -> void:
	var u := _glyph_unit(page)
	var p := page.position
	var frame := Rect2(p.x + roundf(1.8 * u), p.y + roundf(4.2 * u),
		roundf(8.4 * u), roundf(7.6 * u))
	ci.draw_rect(frame, color, false, 1.0)
	for i in 2:
		ci.draw_rect(Rect2(frame.position.x + roundf((2.8 + i * 2.8) * u),
			frame.position.y + 1.0, 1.0, frame.size.y - 2.0), color)
		ci.draw_rect(Rect2(frame.position.x + 1.0,
			frame.position.y + roundf((2.5 + i * 2.5) * u),
			frame.size.x - 2.0, 1.0), color)


## Прежний глиф по типу: text / sound / photo / video.
static func _glyph_kind(ci: CanvasItem, page: Rect2, kind: String, color: Color) -> void:
	var u := _glyph_unit(page)
	var gx := page.position.x + roundf(2.4 * u)
	var gy := page.position.y + roundf(6.2 * u)
	var gw := page.size.x - roundf(5.0 * u)
	match kind:
		"text":
			for i in 3:
				var lw := gw - (i if i == 2 else 0)
				ci.draw_rect(Rect2(gx, gy + roundf(i * 2.6 * u), lw, 1.0), color)
		"sound":
			ci.draw_rect(Rect2(gx, gy + 2.0 * u, 2.4 * u, 2.4 * u), color)
			ci.draw_rect(Rect2(gx + 2.0 * u, gy - 1.0 * u, 1.0, 5.4 * u), color)
			ci.draw_rect(Rect2(gx + 3.0 * u, gy - 1.0 * u, 2.0 * u, 1.0), color)
		"photo":
			ci.draw_rect(Rect2(gx - 1.0 * u, gy - 1.0 * u, gw, 4.6 * u), color, false, 1.0)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(gx - 0.5 * u, gy + 3.2 * u), Vector2(gx + 2.0 * u, gy + 0.6 * u),
				Vector2(gx + 4.5 * u, gy + 3.2 * u)]), color)
			ci.draw_circle(Vector2(gx + gw - 1.5 * u, gy - 0.2 * u), 0.9 * u, color)
		"video":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(gx - 0.8 * u, gy - 1.8 * u), Vector2(gx + 5.2 * u, gy + 1.0 * u),
				Vector2(gx - 0.8 * u, gy + 3.8 * u)]), color)
		_:
			for i in 3:
				ci.draw_rect(Rect2(gx, gy + roundf(i * 2.6 * u), gw, 1.0), color)


## Папка 14×11: мягкая цветная форма, без «дырки» и фаски.
static func draw_folder_icon(ci: CanvasItem, pos: Vector2, color: Color = WARN, open: bool = false) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_style_box(fill_box(color, 2), Rect2(x + 1, y + 2, 12, 8))
	ci.draw_style_box(fill_box(color.lightened(0.18), 1), Rect2(x, y, 6, 4))
	if open:
		ci.draw_rect(Rect2(x + 2, y + 5, 10, 2), Color(1, 1, 1, 0.34))
	else:
		ci.draw_line(Vector2(x + 3, y + 6), Vector2(x + 11, y + 6), Color(1, 1, 1, 0.45), 1.0)


## Диск/секция: 12×9.
static func draw_drive_icon(ci: CanvasItem, pos: Vector2, color: Color = NAVY) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_style_box(fill_box(color, 2), Rect2(x, y, 12, 9))
	ci.draw_rect(Rect2(x + 1, y + 1, 10, 2), Color(1, 1, 1, 0.28))
	ci.draw_circle(Vector2(x + 3, y + 7), 1.0, Color(1, 1, 1, 0.75))
	ci.draw_circle(Vector2(x + 6, y + 7), 1.0, Color(1, 1, 1, 0.45))


## Замок 9×10: тонкая дужка + мягкий корпус.
static func draw_lock_icon(ci: CanvasItem, pos: Vector2, color: Color = DARK) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_arc(Vector2(x + 4.5, y + 3.5), 2.6, PI, TAU, 10, color, 1.2)
	ci.draw_style_box(fill_box(color, 2), Rect2(x, y + 4, 9, 6))
	ci.draw_circle(Vector2(x + 4.5, y + 7), 1.0, Color(1, 1, 1, 0.65))


## Конверт/пакет 14×10.
static func draw_packet_icon(ci: CanvasItem, pos: Vector2, color: Color = ACCENT) -> void:
	var x := roundf(pos.x)
	var y := roundf(pos.y)
	ci.draw_style_box(box(WHITE, Color(color.r, color.g, color.b, 0.55), 2, 1),
		Rect2(x, y, 14, 10))
	ci.draw_line(Vector2(x + 2, y + 2), Vector2(x + 7, y + 5.6), color, 1.0)
	ci.draw_line(Vector2(x + 12, y + 2), Vector2(x + 7, y + 5.6), color, 1.0)


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


## Тонкий шеврон — для скроллбара и строк дерева.
static func draw_chevron(ci: CanvasItem, center: Vector2, dir: int, color: Color,
		size: float = 3.5, thick: float = 1.4) -> void:
	var c := center.round()
	match dir:
		0:
			ci.draw_line(c + Vector2(-size, size * 0.5), c + Vector2(0, -size * 0.5), color, thick)
			ci.draw_line(c + Vector2(0, -size * 0.5), c + Vector2(size, size * 0.5), color, thick)
		1:
			ci.draw_line(c + Vector2(-size, -size * 0.5), c + Vector2(0, size * 0.5), color, thick)
			ci.draw_line(c + Vector2(0, size * 0.5), c + Vector2(size, -size * 0.5), color, thick)
		2:
			ci.draw_line(c + Vector2(-size * 0.5, -size), c + Vector2(size * 0.5, 0), color, thick)
			ci.draw_line(c + Vector2(size * 0.5, 0), c + Vector2(-size * 0.5, size), color, thick)
		_:
			ci.draw_line(c + Vector2(size * 0.5, -size), c + Vector2(-size * 0.5, 0), color, thick)
			ci.draw_line(c + Vector2(-size * 0.5, 0), c + Vector2(size * 0.5, size), color, thick)


## Крестик.
static func draw_x(ci: CanvasItem, rect: Rect2, color: Color, thick: float = 1.2) -> void:
	var r := rect.grow(-3.0)
	ci.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x - 1, r.end.y - 1), color, thick)
	ci.draw_line(Vector2(r.end.x - 1, r.position.y), Vector2(r.position.x, r.end.y - 1), color, thick)


## Галочка в круге (attached-бейджи).
static func draw_check_badge(ci: CanvasItem, center: Vector2, radius: float = 6.5,
		color: Color = SUCCESS, mark: Color = WHITE) -> void:
	ci.draw_circle(center, radius, color)
	var k := radius / 6.5
	ci.draw_line(center + Vector2(-3.0, 0.2) * k, center + Vector2(-0.8, 2.4) * k, mark, 1.6 * k)
	ci.draw_line(center + Vector2(-0.8, 2.4) * k, center + Vector2(3.2, -2.2) * k, mark, 1.6 * k)


## Засечки-«решётка» для заблокированных превью.
static func draw_scanlines(ci: CanvasItem, rect: Rect2, color: Color, step: float = 2.0) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	var y := r.position.y
	while y < r.end.y:
		ci.draw_rect(Rect2(r.position.x, y, r.size.x, 1), color)
		y += step


# --- Текстура фона --------------------------------------------------------

## Тёплая бумага: бесшовный тайл с очень слабыми пастельными пятнами и зерном.
static func dither_texture() -> ImageTexture:
	if _dither != null:
		return _dither
	const S := 48
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var teal := Color(0.835, 0.925, 0.925)
	var peach := Color(0.980, 0.925, 0.895)
	var base := PAPER
	for yy in S:
		for xx in S:
			var u := TAU * float(xx) / float(S)
			var v := TAU * float(yy) / float(S)
			var a := 0.5 + 0.5 * sin(u * 2.0 + 0.4) * cos(v)
			var b := 0.5 + 0.5 * sin(v * 2.0 + 1.1) * cos(u * 3.0)
			var c := base
			c = c.lerp(teal, 0.055 * a)
			c = c.lerp(peach, 0.045 * b)
			var grain := float((xx * 73 + yy * 151 + 17) % 13) / 13.0 - 0.5
			c = c.lerp(Color(0.42, 0.40, 0.34), 0.012 * absf(grain))
			img.set_pixel(xx, yy, c)
	_dither = ImageTexture.create_from_image(img)
	return _dither


# --- Слой для произвольного Control --------------------------------------

## Слой, который рисует только мягкий контур поверх Control.
class BevelLayer:
	extends Control
	var pressed := false
	var thick := 1.0
	var face := Color(0.913725, 0.901961, 0.866667)
	var sunken_background := false

	func _init(p_pressed: bool = false) -> void:
		pressed = p_pressed
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		if sunken_background:
			Theme90.draw_bevel(self, Rect2(Vector2.ZERO, size), pressed, thick, face)
		else:
			draw_style_box(Theme90.box(Color(0, 0, 0, 0), Theme90.BORDER, 3, 1),
				Rect2(Vector2.ZERO, size))


## Добавляет контур к любому Control (не меняя его собственный _draw).
static func apply_bevel(control: Control, pressed: bool = false, thick: float = 1.0,
		sunken_background: bool = false) -> BevelLayer:
	var layer := BevelLayer.new(pressed)
	layer.thick = thick
	layer.sunken_background = sunken_background
	layer.face = FACE
	control.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer


# --- Тема (используется art/fonts/ui_theme.tres) --------------------------

static func _circle_tex(fill: Color, border: Color, size: int = 12) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (float(size) - 1.0) * 0.5
	var r := float(size) * 0.5 - 1.0
	for yy in size:
		for xx in size:
			var d := Vector2(float(xx) - c, float(yy) - c).length()
			if d <= r:
				img.set_pixel(xx, yy, border if d > r - 1.15 else fill)
	return ImageTexture.create_from_image(img)


static func _check_tex(fill: Color, border: Color, size: int = 14) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rad := 3.0
	var half := float(size) * 0.5 - 1.0
	var c := (float(size) - 1.0) * 0.5
	for yy in size:
		for xx in size:
			var dx := maxf(absf(float(xx) - c) - half + rad, 0.0)
			var dy := maxf(absf(float(yy) - c) - half + rad, 0.0)
			var d := Vector2(dx, dy).length()
			if d <= rad:
				img.set_pixel(xx, yy, border if d > rad - 1.0 else fill)
	# галочка
	var a := Vector2(float(size) * 0.27, float(size) * 0.52)
	var b := Vector2(float(size) * 0.44, float(size) * 0.68)
	var e := Vector2(float(size) * 0.74, float(size) * 0.33)
	for yy in size:
		for xx in size:
			var p := Vector2(float(xx), float(yy))
			if _dist_seg(p, a, b) <= 1.2 or _dist_seg(p, b, e) <= 1.2:
				img.set_pixel(xx, yy, WHITE)
	return ImageTexture.create_from_image(img)


static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _arrow_tex(dir: int, color: Color, size: int = 9) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in int(size / 2) + 1:
		for j in range(-i, i + 1):
			var x := j
			var y := i
			if dir == 0:
				x = j + int(size / 2)
				y = i
			elif dir == 1:
				x = j + int(size / 2)
				y = size - 1 - i
			elif dir == 2:
				x = size - 1 - i
				y = j + int(size / 2)
			else:
				x = i
				y = j + int(size / 2)
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func popup_panel_box() -> StyleBoxFlat:
	var sb := box(FACE_HI, BORDER, 4, 1, Color(0, 0, 0, 0.16))
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.set_content_margin_all(5)
	return sb


static func popup_hover_box() -> StyleBoxFlat:
	var sb := box(ACCENT_PALE, Color(0, 0, 0, 0), 3, 0)
	sb.set_content_margin_all(2)
	return sb


static func sunken_box() -> StyleBoxFlat:
	var sb := well_box(WHITE)
	sb.set_content_margin_all(2)
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
	t.set_color("font_hover_color", "Button", NAVY)
	t.set_color("font_pressed_color", "Button", NAVY_DEEP)
	t.set_color("font_disabled_color", "Button", SHADE)
	var b_normal := box(PAPER_HI, BORDER, 3, 1, SHADOW)
	var b_hover := box(WHITE, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55), 3, 1, SHADOW)
	var b_pressed := box(PAPER_LO, BORDER, 3, 1)
	t.set_stylebox("normal", "Button", b_normal)
	t.set_stylebox("hover", "Button", b_hover)
	t.set_stylebox("pressed", "Button", b_pressed)
	t.set_stylebox("disabled", "Button", box(PAPER, BORDER_SOFT, 3, 1))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7), 3, 1))

	# PopupMenu — светлое меню
	t.set_font("font", "PopupMenu", f)
	t.set_font_size("font_size", "PopupMenu", FS_BODY)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_color("font_pressed_color", "PopupMenu", NAVY_DEEP)
	t.set_color("font_disabled_color", "PopupMenu", SHADE)
	t.set_color("font_accelerator_color", "PopupMenu", SHADE)
	t.set_color("font_separator_color", "PopupMenu", Color(SHADE.r, SHADE.g, SHADE.b, 0.5))
	t.set_stylebox("panel", "PopupMenu", popup_panel_box())
	t.set_stylebox("hover", "PopupMenu", popup_hover_box())
	t.set_constant("v_separation", "PopupMenu", 3)
	t.set_constant("h_separation", "PopupMenu", 6)
	t.set_constant("item_start_padding", "PopupMenu", 8)
	t.set_constant("item_end_padding", "PopupMenu", 12)
	t.set_constant("separator_outline_size", "PopupMenu", 0)

	# Подсказки
	t.set_stylebox("panel", "TooltipPanel", popup_panel_box())
	t.set_font("font", "TooltipLabel", f)
	t.set_font_size("font_size", "TooltipLabel", FS_MICRO)
	t.set_color("font_color", "TooltipLabel", INK)

	# LineEdit — поиск/переименование
	t.set_font("font", "LineEdit", f)
	t.set_font_size("font_size", "LineEdit", FS_BODY)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", SHADE)
	t.set_stylebox("normal", "LineEdit", sunken_box())
	t.set_stylebox("focus", "LineEdit", box(WHITE, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), 3, 1))

	# Panel
	t.set_stylebox("panel", "Panel", box(FACE_HI, BORDER, 4, 1, SHADOW))

	# HSlider — тонкая бумажная дорожка, teal-заливка, круглый бегунок.
	t.set_stylebox("slider", "HSlider", box(PAPER_LO, BORDER_SOFT, 2, 1))
	t.set_stylebox("grabber_area", "HSlider", fill_box(ACCENT_LIGHT, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_box(ACCENT, 2))
	var knob := _circle_tex(WHITE, ACCENT_LIGHT, 12)
	var knob_hi := _circle_tex(WHITE, ACCENT, 12)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob_hi)
	t.set_icon("grabber_disabled", "HSlider", _circle_tex(PAPER, BORDER_SOFT, 12))
	t.set_constant("grabber_offset", "HSlider", 0)

	# CheckBox — скруглённый квадрат и галочка.
	var cb_off := _check_tex(WHITE, BORDER, 14)
	var cb_on := _check_tex(ACCENT, ACCENT, 14)
	t.set_icon("unchecked", "CheckBox", cb_off)
	t.set_icon("checked", "CheckBox", cb_on)
	t.set_icon("radio_unchecked", "CheckBox", _circle_tex(WHITE, BORDER, 14))
	t.set_icon("radio_checked", "CheckBox", _circle_tex(ACCENT, ACCENT, 14))
	t.set_stylebox("normal", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("hover", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("pressed", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("focus", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", NAVY)
	t.set_color("font_pressed_color", "CheckBox", NAVY_DEEP)
	t.set_color("font_disabled_color", "CheckBox", SHADE)

	# ScrollBar — без серых дефолтов; в игре используются ScrollBar90.
	var sb_track := box(PAPER_LO, BORDER_SOFT, 2, 1)
	var sb_thumb := box(Color(SHADE.r, SHADE.g, SHADE.b, 0.30), Color(0, 0, 0, 0), 2, 0)
	var sb_thumb_hi := box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55),
		Color(0, 0, 0, 0), 2, 0)
	for bar_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar_type, sb_track)
		t.set_stylebox("scroll_focus", bar_type, sb_track)
		t.set_stylebox("grabber", bar_type, sb_thumb)
		t.set_stylebox("grabber_highlight", bar_type, sb_thumb_hi)
		t.set_stylebox("grabber_pressed", bar_type, sb_thumb_hi)
		t.set_icon("increment", bar_type, _arrow_tex(1, SHADE, 9))
		t.set_icon("increment_highlight", bar_type, _arrow_tex(1, NAVY, 9))
		t.set_icon("decrement", bar_type, _arrow_tex(0, SHADE, 9))
		t.set_icon("decrement_highlight", bar_type, _arrow_tex(0, NAVY, 9))

	# Вариации под единую шкалу 11/13/17/26 — источник правды для разметки.
	t.set_type_variation("MicroLabel", "Label")
	t.set_font_size("font_size", "MicroLabel", FS_MICRO)
	t.set_color("font_color", "MicroLabel", DARK)
	t.set_type_variation("HeadLabel", "Label")
	t.set_font_size("font_size", "HeadLabel", FS_HEAD)
	t.set_font("font", "HeadLabel", f)
	t.set_type_variation("LogoLabel", "Label")
	t.set_font_size("font_size", "LogoLabel", FS_LOGO)
	t.set_font("font", "LogoLabel", display())
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
	var ext := ""

	func _init(p_label: String, p_sub: String = "", p_kind: String = "file",
			p_tint: Color = Color(1, 1, 1, 1), p_icon := "text", p_ext := "") -> void:
		label_text = p_label
		sub_text = p_sub
		kind = p_kind
		tint = p_tint
		ext = p_ext
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate.a = 0.78
		var w := 172.0
		size = Vector2(w, 32)
		custom_minimum_size = size
		if kind == "packet":
			tint = Theme90.ACCENT
		if p_icon == "packet":
			kind = "packet"

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		Theme90.draw_bevel(self, r, false, 1.0, Color(1, 1, 1, 0.96))
		if kind == "packet":
			Theme90.draw_packet_icon(self, Vector2(8, 11), Theme90.ACCENT)
		else:
			Theme90.draw_doc_icon(self, Rect2(5, 4, 24, 24), "text", tint, ext)
		var f := Theme90.ui()
		Theme90.text(self, f, Vector2(36, 4), Theme90.fit(f, label_text, 12, size.x - 42), 12, Theme90.INK)
		if not sub_text.is_empty():
			Theme90.text(self, f, Vector2(36, 18), Theme90.fit(f, sub_text, 10, size.x - 42),
				10, Theme90.SHADE)


## Числовая строка: цифры — Press Start 2P (чистые 0), суффикс — Golos Text.
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
