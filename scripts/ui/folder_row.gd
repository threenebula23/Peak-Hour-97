class_name FolderRow
extends Control
## Строка дерева 24 px: мягкий шеврон, папка, имя, счётчик «3/16».
## Выделение — светлая teal-подложка с тонкой полоской слева, без инверсии.
## Секции C:/D:/E: — спокойная строка с волосяной линией снизу.

signal folder_selected(folder_id: String)
signal expansion_toggled(folder_id: String)
signal file_dropped(folder_id: String, payload: Dictionary)
signal packet_dropped(folder_id: String, payload: Dictionary)
signal context_menu_requested(folder_id: String, global_pos: Vector2)
## Папка раскрыта/открыта наведением во время drag (250 мс).
signal hover_open_requested(folder_id: String)

const ROW_H := 24.0
const SECTION_H := 22.0

# --- Motion (Lane B) -------------------------------------------------------
const HOVER_DUR := 0.10
const SELECT_DUR := 0.12
const WAVE_DUR := 0.8
const ACCEPT_DUR := 0.20
## Отскок полоски выделения.
const SEL_BOUNCE_DUR := 0.18

var folder_id := ""
var folder_name := ""
## v2: count — занятые КЛЕТКИ, capacity — всего клеток.
var count := 0
var capacity := 16
## Число файлов (для тултипа «N файлов · X из Y клеток»).
var files_count := 0
var free_text := ""
var depth := 0
var is_section := false
var expandable := true
var hover_open := false:
	set(v):
		if hover_open == v:
			return
		hover_open = v
		queue_redraw()
		if v and not is_section:
			hover_open_requested.emit(folder_id)
var expanded := true:
	set(v):
		expanded = v
		queue_redraw()
var selected := false:
	set(v):
		if v and not selected:
			_sel_clock = 0.0
		selected = v
		set_process(true)
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		set_process(true)
		queue_redraw()
var drop_active := false:
	set(v):
		if drop_active != v:
			drop_active = v
			_wave = 0.0
			set_process(true)
			queue_redraw()
var locked := false

var _hover_amt := 0.0
var _sel_amt := 0.0
var _wave := 0.0
var _accept_clock := -1.0
var _sel_clock := -1.0
var _motion_on := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	custom_minimum_size = Vector2(0, SECTION_H if is_section else ROW_H)
	if size.y == 0.0:
		size.y = custom_minimum_size.y
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	set_process(false)


# --- motion (Lane B) -------------------------------------------------------

## Внешний переключатель движения (Lane A / настройки).
func set_motion_enabled(on: bool) -> void:
	_motion_on = on
	if _reduced():
		_hover_amt = 1.0 if hovered else 0.0
		_sel_amt = 1.0 if selected else 0.0
		_accept_clock = -1.0
	queue_redraw()


func _reduced() -> bool:
	return not _motion_on or UiMotion.reduced


func _process(delta: float) -> void:
	var hov := 1.0 if hovered else 0.0
	var sel := 1.0 if selected else 0.0
	if _reduced():
		_hover_amt = hov
		_sel_amt = sel
		_wave = 0.0
	else:
		if not is_equal_approx(_hover_amt, hov):
			_hover_amt = move_toward(_hover_amt, hov, delta / HOVER_DUR)
		if not is_equal_approx(_sel_amt, sel):
			_sel_amt = move_toward(_sel_amt, sel, delta / SELECT_DUR)
		if drop_active:
			_wave = fmod(_wave + delta, WAVE_DUR)
	if _accept_clock >= 0.0:
		_accept_clock += delta
		if _accept_clock >= ACCEPT_DUR:
			_accept_clock = -1.0
	if _sel_clock >= 0.0:
		_sel_clock += delta
		if _sel_clock >= SEL_BOUNCE_DUR:
			_sel_clock = -1.0
	queue_redraw()
	if not drop_active and _accept_clock < 0.0 and _sel_clock < 0.0 \
			and is_equal_approx(_hover_amt, hov) and is_equal_approx(_sel_amt, sel):
		set_process(false)


## 0..1 → 0 отскок полоски выделения.
func _sel_bounce() -> float:
	if _sel_clock < 0.0:
		return 0.0
	return sin(PI * clampf(_sel_clock / SEL_BOUNCE_DUR, 0.0, 1.0))


func _draw_hover() -> float:
	if _reduced():
		return 1.0 if hovered else 0.0
	return _hover_amt


func _draw_sel() -> float:
	if _reduced():
		return 1.0 if selected else 0.0
	return _sel_amt


## Цвет секции диска: стабильный оттенок по имени (C:/D:/E:), чтобы группы
## отличались, а не сливались в один teal.
func _section_color() -> Color:
	var palette: Array[Color] = [Theme90.BLUE, Theme90.PURPLE, Theme90.LIME,
		Theme90.ORANGE, Theme90.PINK]
	var idx := absi(hash(folder_name)) % palette.size()
	return palette[idx]


## Флэш «файл принят» после drop — 0.20 c.
func _start_accept() -> void:
	_accept_clock = 0.0
	set_process(true)


## Волна drop_active и вспышка приёма — только отрисовка, layout не меняется.
func _draw_effects(r: Rect2) -> void:
	if drop_active and not _reduced() and not is_section:
		var p := clampf(_wave / WAVE_DUR, 0.0, 1.0)
		var w := 22.0
		var x := lerpf(-w, size.x, p)
		var a := 0.06 + 0.20 * (1.0 - p)
		draw_rect(Rect2(x, 2, w, maxf(0.0, size.y - 4)),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, a))
	if _accept_clock >= 0.0:
		var ae := clampf(1.0 - _accept_clock / ACCEPT_DUR, 0.0, 1.0)
		draw_style_box(Theme90.box(Color(0, 0, 0, 0),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.9 * ae), 3, 1),
			Rect2(2, 1, maxf(0.0, size.x - 4), maxf(0.0, size.y - 2)))


func setup(p_id: String, p_name: String, p_depth: int, p_section: bool = false) -> void:
	folder_id = p_id
	folder_name = p_name
	depth = p_depth
	is_section = p_section
	custom_minimum_size.y = SECTION_H if p_section else ROW_H
	if size.y < custom_minimum_size.y:
		size.y = custom_minimum_size.y
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var hov := _draw_hover()
	if is_section:
		_draw_section(r, f, hov)
		_draw_effects(r)
		return

	var sel := _draw_sel()
	if sel > 0.001:
		draw_style_box(Theme90.box(
			Color(Theme90.ACCENT_PALE.r, Theme90.ACCENT_PALE.g, Theme90.ACCENT_PALE.b, sel),
			Color(0, 0, 0, 0), 3, 0), Rect2(2, 1, size.x - 4, size.y - 2))
		var bar_h := size.y - 10.0 + 4.0 * _sel_bounce()
		draw_rect(Rect2(2, (size.y - bar_h) * 0.5, 2, bar_h),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, sel))
	if hov > 0.02:
		# Мягкое свечение строки при наведении (draw-only) + цветная кромка.
		draw_rect(Rect2(2, 1, size.x - 4, size.y - 2),
			Color(Theme90.ACCENT_LIGHT.r, Theme90.ACCENT_LIGHT.g,
				Theme90.ACCENT_LIGHT.b, 0.16 * hov))
		draw_rect(Rect2(2, 4, 2.0, maxf(0.0, size.y - 8)),
			Theme90.alpha_of(Theme90.ACCENT, 0.55 * hov))
	if drop_active:
		draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.ACCENT, 3, 1),
			Rect2(2, 1, size.x - 4, size.y - 2))
	elif hover_open:
		draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.ACCENT_LIGHT, 3, 1),
			Rect2(2, 1, size.x - 4, size.y - 2))
		draw_rect(Rect2(2, 5, 2, size.y - 10), Theme90.ACCENT_LIGHT)
	elif hov > 0.02 and sel < 0.5:
		draw_rect(Rect2(2, 1, size.x - 4, size.y - 2), Color(1, 1, 1, 0.30 * hov))

	var fg := Theme90.INK.lerp(Theme90.NAVY, sel)
	var sub := Theme90.SHADE.lerp(Theme90.ACCENT, sel)
	var sx := 5.0 + depth * 12.0

	# тонкий шеврон вместо объёмного квадрата
	if expandable:
		Theme90.draw_chevron(self, Vector2(sx + 6, size.y * 0.5), 1 if expanded else 2,
			sub, 3.0, 1.3)
	else:
		draw_circle(Vector2(sx + 6, size.y * 0.5), 1.2, sub)

	# иконка папки
	var icon_x := sx + 15.0
	var pop := clampf(hov, 0.0, 1.0)
	Theme90.draw_folder_icon(self, Vector2(icon_x - pop * 0.5, 7.0 - pop),
		Theme90.ACCENT if not locked else Theme90.SHADE, expanded and not is_section)

	# имя
	var tx := icon_x + 17.0
	var name_w := maxf(20.0, size.x - tx - 56.0)
	var label := Theme90.fit(f, folder_name, 12, name_w)
	Theme90.text_vcenter(self, f, Rect2(tx, 0, name_w, size.y), label, 12, fg)

	# счётчик — спокойные цифры без «логотипного» шрифта
	if capacity > 0:
		var cnt := "%d/%d" % [count, capacity]
		var cw := f.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text_vcenter(self, f, Rect2(size.x - cw - 8.0, 0, cw + 2, size.y),
			cnt, 10, sub)

	if locked:
		Theme90.draw_lock_icon(self, Vector2(size.x - 58, 8), Theme90.SHADE)
	_draw_effects(r)


func _draw_section(r: Rect2, f: Font, hov: float) -> void:
	var sc := _section_color()
	if hov > 0.02:
		draw_rect(r, Theme90.alpha_of(sc, 0.08 * hov))
	# Цветная полоса секции: диск читается как отдельная группа.
	draw_rect(Rect2(2, 3, maxf(0.0, size.x - 4), 1.5),
		Theme90.alpha_of(sc, 0.65))
	draw_rect(Rect2(2, size.y - 1, maxf(0.0, size.x - 4), 1),
		Theme90.alpha_of(sc, 0.22))
	var sx := 4.0
	if expandable:
		Theme90.draw_chevron(self, Vector2(sx + 6, size.y * 0.5), 1 if expanded else 2,
			sc, 3.0, 1.3)
	Theme90.draw_drive_icon(self, Vector2(sx + 16, 6), sc)
	var fg := Theme90.INK.lerp(sc.darkened(0.2), _draw_sel())
	Theme90.text_vcenter(self, f, Rect2(sx + 32, 0, size.x - 80, size.y),
		Theme90.fit(f, folder_name, 12, size.x - 110), 12, fg)
	if not free_text.is_empty():
		var tw := f.get_string_size(free_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text(self, f, Vector2(size.x - tw - 8, 6), free_text, 10,
			Theme90.alpha_of(sc.darkened(0.35), 0.9))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_start_accept()
			var sx := 5.0 + (0.0 if is_section else depth * 12.0)
			if expandable and Rect2(sx, 5, 12, 12).has_point(event.position):
				expanded = not expanded
				expansion_toggled.emit(folder_id)
			else:
				if not is_section:
					folder_selected.emit(folder_id)
				else:
					expanded = not expanded
					expansion_toggled.emit(folder_id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_menu_requested.emit(folder_id, get_global_mouse_position())
			accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var k: String = data.get("kind", "")
	if k != "file" and k != "packet":
		return false
	drop_active = true
	if not is_section:
		_request_hover_open()
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_active = false
	hover_open = false
	_reset_hover_timer()
	if is_section or not (data is Dictionary):
		return
	_start_accept()
	if str(data.get("kind", "")) == "packet":
		packet_dropped.emit(folder_id, data)
	else:
		file_dropped.emit(folder_id, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_active = false
		hover_open = false
		_reset_hover_timer()
	elif what == NOTIFICATION_MOUSE_EXIT:
		if drop_active or hover_open:
			drop_active = false
			hover_open = false
			_reset_hover_timer()


func set_hover(on: bool) -> void:
	hover_open = on


func _request_hover_open() -> void:
	if not is_inside_tree():
		return
	var dc := get_tree().get_first_node_in_group("drag_controller")
	if dc != null and dc.has_method("hover_folder"):
		dc.call("hover_folder", folder_id)


func _reset_hover_timer() -> void:
	if not is_inside_tree():
		return
	var dc := get_tree().get_first_node_in_group("drag_controller")
	if dc != null and dc.has_method("reset_hover"):
		dc.call("reset_hover")
