class_name PacketCard
extends Control
## Карточка входящего пакета 400×52 (v2).
##
## Показывает мини-превью ФИГУРЫ, которую пакет займёт в папке, и текст
## «ЗАЙМЁТ N КЛЕТОК». Карточка перетаскивается в сетку папки или на строку
## папки: payload {"kind": "packet", "id", "shape_id", "rotation", …}.
## Соединений/атак больше нет — карточка только источник drag&drop.

signal connect_pressed(id: String)  # legacy: соединение удалено, не эмитится

const CARD := Vector2(400, 52)
const FR = preload("res://scripts/core/file_registry.gd")
const FILE_SHAPE = preload("res://scripts/ui/file_shape.gd")
const FILE_ICONS = preload("res://scripts/ui/file_icons.gd")
const DRAG_CONTROLLER = preload("res://scripts/ui/drag_controller.gd")
const PREVIEW_CELL := 6.0
const PREVIEW_GAP := 1.0

# --- Motion (Lane B) -------------------------------------------------------
const ENTER_DUR := 0.14
const ENTER_SCALE_FROM := 0.98
const HOVER_DUR := 0.10
const METER_TAU := 0.15
const ALERT_PULSE := 0.9
const ERROR_SHAKE_DUR := 0.16
## play_loss: десатурация → X-sweep → alpha/высота.
const LOSS_DESAT_DUR := 0.10
const LOSS_SWEEP_DUR := 0.20
const LOSS_FADE_DUR := 0.28
## Приём: короткая вспышка слева; таймер <20 % слегка «дрожит».
const RECV_PULSE_DUR := 0.30
const WOBBLE_PX := 1.5

var id := ""
var file_name := ""
var ext := ""
var type := "text"
var protocol := "TCP"
var time_left := 20.0
var time_total := 20.0
var progress := 0.0
var size_kb := 0
var state := "waiting"
var shape_id := "O1"
var shape_rotation := 0
## Индекс иконки из атласа FileIcons (0..63); -1 — иконка типа.
var icon_id := -1

var hovered := false:
	set(v):
		hovered = v
		set_process(true)
		queue_redraw()

var _blink := 0.0
var _blink_on := true

var _hover_amt := 0.0
var _enter_elapsed := ENTER_DUR
var _err_shake := 0.0
var _meter := 0.0
var _meter_ready := false
var _pulse := 0.0
var _motion_on := true
## play_loss: -1 — не запущен, иначе секунды с начала.
var _loss_clock := -1.0
var _loss_sweep := 0.0
var _recv_clock := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	set_process(true)
	_update_tooltip()
	enter(0)
	_recv_clock = 0.0


## Совместимая сигнатура: первые 9 аргументов как в v1, затем состояние,
## форма пакета и иконка (icon_id из атласа FileIcons, -1 — иконка типа).
## Атаки удалены — их аргументов здесь нет.
func setup(p_id: String, p_name: String, p_ext: String, p_type: String, p_proto: String,
		p_left: float, p_total: float, p_progress: float = 0.0, p_size_kb: int = 0,
		p_state: String = "waiting", p_shape_id: String = "O1",
		p_rotation: int = 0, p_icon_id: int = -1) -> void:
	id = p_id
	file_name = p_name
	ext = p_ext
	type = p_type
	protocol = str(p_proto).to_upper()
	time_left = p_left
	time_total = p_total
	progress = clampf(p_progress, 0.0, 1.0)
	size_kb = p_size_kb
	state = p_state
	shape_id = p_shape_id if not p_shape_id.is_empty() else "O1"
	shape_rotation = posmod(int(p_rotation), 4)
	icon_id = p_icon_id
	_update_tooltip()
	if not _meter_ready:
		_meter = ratio()
		_meter_ready = true
	set_process(true)
	queue_redraw()


func set_time(left: float, total: float) -> void:
	time_left = left
	time_total = total
	set_process(true)
	queue_redraw()


# --- motion (Lane B) -------------------------------------------------------

## Появление: alpha 0.14 c + scale 0.98 → 1.
func enter(_index: int = 0) -> void:
	if _reduced():
		_enter_elapsed = ENTER_DUR
		modulate.a = 1.0
		scale = Vector2.ONE
		return
	_enter_elapsed = 0.0
	modulate.a = 0.0
	_apply_enter()
	set_process(true)


## Потеря пакета: десатурация → X-sweep → alpha/высота, затем self-free.
## Обычное удаление main'ом работает как раньше — play_loss опционален.
func play_loss() -> void:
	if _loss_clock >= 0.0:
		return
	_loss_clock = 0.0
	_loss_sweep = 0.0
	pivot_offset = size * 0.5
	set_process(true)


## Отказ/ошибка: draw-only тряска ±SHAKE, position не меняется.
func flash_error() -> void:
	_err_shake = 0.0 if _reduced() else ERROR_SHAKE_DUR
	set_process(true)
	queue_redraw()


## Внешний переключатель движения (Lane A / настройки).
func set_motion_enabled(on: bool) -> void:
	_motion_on = on
	if _reduced():
		_hover_amt = 1.0 if hovered else 0.0
		_enter_elapsed = ENTER_DUR
		modulate.a = 1.0
		scale = Vector2.ONE
		_err_shake = 0.0
		_pulse = 0.0
	queue_redraw()


func _reduced() -> bool:
	return not _motion_on or UiMotion.reduced


func _apply_enter() -> void:
	var p := clampf(_enter_elapsed / ENTER_DUR, 0.0, 1.0)
	pivot_offset = size * 0.5
	var s := lerpf(ENTER_SCALE_FROM, 1.0, p)
	scale = Vector2(s, s)
	modulate.a = p


func _shake_offset() -> Vector2:
	if _err_shake <= 0.0:
		return Vector2.ZERO
	var p := 1.0 - _err_shake / ERROR_SHAKE_DUR
	return Vector2(sin(p * PI * 3.0) * UiMotion.SHAKE * (1.0 - p), 0.0)


func _alert_alpha() -> float:
	if _reduced() or time_total <= 0.0 or ratio() >= 0.2:
		return 1.0
	return 0.72 + 0.28 * (0.5 + 0.5 * sin(_pulse / ALERT_PULSE * TAU))


## 0..1 — вспышка «пакет принят» по левой кромке.
func _recv_alpha() -> float:
	if _recv_clock < 0.0 or _reduced():
		return 0.0
	return clampf(1.0 - _recv_clock / RECV_PULSE_DUR, 0.0, 1.0)


## Draw-only дрожь таймера в последних 20 %.
func _timer_wobble() -> float:
	if _reduced() or _loss_clock >= 0.0 or time_total <= 0.0 or ratio() >= 0.2:
		return 0.0
	return sin(_pulse / ALERT_PULSE * TAU * 2.0) * WOBBLE_PX


func _draw_hover() -> float:
	if _reduced():
		return 1.0 if hovered else 0.0
	return _hover_amt


## Конец play_loss: узел уходит сам, чужие ссылки на него больше не нужны.
func _finish_loss() -> void:
	_loss_clock = -1.0
	modulate = Color(1, 1, 1, 0)
	visible = false
	queue_free()


func ratio() -> float:
	if time_total <= 0.0:
		return 0.0
	return clampf(time_left / time_total, 0.0, 1.0)


func timer_color() -> Color:
	var r := ratio()
	if r < 0.2:
		return Theme90.ERROR
	if r < 0.5:
		return Theme90.WARN
	return Theme90.SUCCESS


## Клетки фигуры этого пакета (для тестов/подсказки).
func cells() -> Array:
	var cs: Array = FR.shape_cells(shape_id, shape_rotation)
	if cs.is_empty():
		cs = [Vector2i.ZERO]
	return cs


func cells_count() -> int:
	return cells().size()


## «ЗАЙМЁТ N КЛЕТОК» — сколько места пакет займёт в папке.
func cells_text() -> String:
	var n := cells_count()
	var word := "КЛЕТОК"
	if n % 10 == 1 and n % 100 != 11:
		word = "КЛЕТКУ"
	elif n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14):
		word = "КЛЕТКИ"
	return "ЗАЙМЁТ %d %s" % [n, word]


func _display_name() -> String:
	if ext.is_empty():
		return file_name
	return "%s.%s" % [file_name, ext]


func _update_tooltip() -> void:
	# Полное имя одной строкой (без переноса): ОС-подсказка не обрезает его.
	tooltip_text = "%s · %s · %s" % [_display_name(), FileCard.type_title(type), protocol]


func _process(delta: float) -> void:
	var busy := _animate(delta)
	# мигание только у «горящих» пакетов (<5 %) и только без reduced
	var hot := ratio() < 0.05 and not _reduced()
	if hot:
		_blink += delta
		var on := int(_blink * 4.0) % 2 == 0
		if on != _blink_on:
			_blink_on = on
			queue_redraw()
			busy = true
	elif not _blink_on:
		_blink_on = true
		queue_redraw()
	if time_total > 0.0 and ratio() < 0.2 and not _reduced() and _loss_clock < 0.0:
		_pulse = fmod(_pulse + delta, ALERT_PULSE)
		queue_redraw()
		busy = true
	if not busy:
		set_process(false)


## Все плавные состояния. true — нужен ещё кадр.
func _animate(delta: float) -> bool:
	var changed := false
	var hov := 1.0 if hovered else 0.0
	if _reduced():
		if not is_equal_approx(_hover_amt, hov):
			_hover_amt = hov
			changed = true
	elif not is_equal_approx(_hover_amt, hov):
		_hover_amt = move_toward(_hover_amt, hov, delta / HOVER_DUR)
		changed = true

	if _enter_elapsed < ENTER_DUR:
		_enter_elapsed = minf(ENTER_DUR, _enter_elapsed + delta)
		_apply_enter()
		changed = true

	if _err_shake > 0.0:
		_err_shake = maxf(0.0, _err_shake - delta)
		changed = true

	if _recv_clock >= 0.0:
		_recv_clock += delta
		if _recv_clock >= RECV_PULSE_DUR:
			_recv_clock = -1.0
		changed = true

	if _loss_clock >= 0.0:
		_animate_loss(delta)
		changed = true
	else:
		var mt := ratio()
		if not _meter_ready:
			_meter = mt
			_meter_ready = true
		elif not is_equal_approx(_meter, mt):
			if _reduced():
				_meter = mt
			else:
				_meter = lerpf(_meter, mt, UiMotion.k(delta, METER_TAU))
				if absf(_meter - mt) < 0.002:
					_meter = mt
			changed = true

	if changed:
		queue_redraw()
	return changed


func _animate_loss(delta: float) -> void:
	_loss_clock += delta
	var t := _loss_clock
	var desat := clampf(t / LOSS_DESAT_DUR, 0.0, 1.0)
	var fade := clampf((t - LOSS_DESAT_DUR - LOSS_SWEEP_DUR) / LOSS_FADE_DUR, 0.0, 1.0)
	_loss_sweep = clampf((t - LOSS_DESAT_DUR) / LOSS_SWEEP_DUR, 0.0, 1.0)
	if _reduced():
		# Без движения: мгновенная десатурация, X сразу, только fade.
		desat = 1.0
		_loss_sweep = 1.0
		fade = clampf(t / LOSS_FADE_DUR, 0.0, 1.0)
	var g := lerpf(1.0, 0.62, desat)
	modulate = Color(g, g, g, 1.0 - fade)
	# «Высота» — только scale (pivot в центре): layout карточки не меняется.
	scale = Vector2(1.0, 1.0 - 0.35 * fade)
	if fade >= 1.0:
		_finish_loss()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var hov := _draw_hover()
	var off := _shake_offset()
	if off.x != 0.0:
		draw_set_transform(off, 0.0, Vector2.ONE)
	var face := Theme90.PAPER_HI.lerp(Theme90.WHITE, hov)
	var border := Theme90.BORDER.lerp(Theme90.ACCENT_LIGHT, hov)
	var shadow := Theme90.SHADOW.lerp(Color(0, 0, 0, 0.11), hov)
	draw_style_box(Theme90.box(face, border, 4, 1, shadow), r)
	# «Пакет принят»: короткая вспышка у левой кромки (draw-only).
	var recv := _recv_alpha()
	if recv > 0.01:
		draw_rect(Rect2(1, 2, 2, maxf(0.0, size.y - 4)),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.75 * recv))
		draw_rect(r, Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.05 * recv))

	_draw_shape_preview(Rect2(4, 10, 30, 30))

	# Иконка из атласа (по icon_id) 14×14 сразу слева от имени файла;
	# старые пакеты без icon_id — прежняя иконка типа.
	if not FILE_ICONS.draw(self, Rect2(40, 2, 14, 14), icon_id) and not type.is_empty():
		Theme90.draw_file_icon(self, Rect2(40, 2, 14, 14), type)

	Theme90.text(self, f, Vector2(57, 2), Theme90.fit(f, _display_name(), 13, 151), 13,
		Theme90.INK, 151)

	# бейдж протокола
	var badge := Rect2(214, 4, 30, 13)
	draw_style_box(Theme90.well_box(Theme90.WHITE), badge)
	Theme90.text_vcenter(self, f, badge, protocol, 10,
		Theme90.NAVY if protocol == "TCP" else Theme90.WARN, -1,
		HORIZONTAL_ALIGNMENT_CENTER)

	# таймер (в последних 20 % слегка «дрожит» — draw-only сдвиг координат)
	var wob := _timer_wobble()
	var tr := Rect2(40 + wob, 20, 140, 5)
	var col := timer_color()
	if not _blink_on:
		col = Theme90.ERROR.lerp(Theme90.FACE, 0.45)
	var pulse := _alert_alpha()
	var mcol := col
	mcol.a *= pulse
	Theme90.draw_meter(self, tr, _meter if _meter_ready else ratio(), mcol, Theme90.PAPER_LO)
	var tcol := timer_color()
	tcol.a *= pulse
	var w := Theme90.num_line(self, Vector2(186 + wob, 17), str(int(ceilf(time_left))), 8,
		tcol, " с", 10)
	Theme90.text(self, f, Vector2(186 + wob + w + 3, 19), "·", 10, Theme90.SHADE)
	Theme90.num_line(self, Vector2(186 + wob + w + 8, 17), str(size_kb), 8,
		Theme90.SHADE, " КБ", 10)

	# состояние + сколько клеток займёт
	Theme90.text(self, f, Vector2(40, 31), _state_caption(), 10, _state_color(), 160)
	Theme90.text(self, f, Vector2(204, 31), cells_text(), 10, Theme90.DARK, 150)

	# прогресс загрузки справа
	var pr := Rect2(310, 42, 80, 4)
	Theme90.draw_meter(self, pr, progress, Theme90.ACCENT, Theme90.PAPER_LO)
	Theme90.num_line(self, Vector2(348, 31), str(int(progress * 100.0)), 8,
		Theme90.DARK, "%", 8)

	# Потеря: X-sweep поверх карточки (draw-only, position не меняется).
	if _loss_sweep > 0.0:
		var lc := Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.85)
		var inner := r.grow(-6.0)
		var c := inner.get_center()
		var half := inner.size * 0.5 * _loss_sweep
		draw_line(c - half, c + half, lc, 2.0)
		draw_line(c + Vector2(half.x, -half.y), c + Vector2(-half.x, half.y), lc, 2.0)
	if off.x != 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _state_caption() -> String:
	if state == "loading" or progress > 0.0:
		return "ЗАГРУЗКА В ПАПКУ"
	if protocol != "TCP":
		return "UDP · ЖДЁТ ПАПКУ"
	return "ЖДЁТ ПАПКУ"


func _state_color() -> Color:
	if state == "loading" or progress > 0.0:
		return Theme90.ACCENT
	return Theme90.DARK


func _draw_shape_preview(rect: Rect2) -> void:
	# Лёгкая подложка 4×4, чтобы фигура читалась как «место в папке».
	var grid_w := 4.0 * PREVIEW_CELL + 3.0 * PREVIEW_GAP
	var origin := rect.position + Vector2(
		roundf((rect.size.x - grid_w) * 0.5),
		roundf((rect.size.y - grid_w) * 0.5))
	for r in 4:
		for c in 4:
			var cell := Rect2(origin + Vector2(
				float(c) * (PREVIEW_CELL + PREVIEW_GAP),
				float(r) * (PREVIEW_CELL + PREVIEW_GAP)),
				Vector2(PREVIEW_CELL, PREVIEW_CELL))
			draw_rect(cell, Color(0, 0, 0, 0.045), true)
	var cs := cells()
	if cs.is_empty():
		return
	var bounds := FR.shape_bounds(cs)
	var shape_w := float(bounds.x) * (PREVIEW_CELL + PREVIEW_GAP) - PREVIEW_GAP
	var shape_h := float(bounds.y) * (PREVIEW_CELL + PREVIEW_GAP) - PREVIEW_GAP
	var pos := origin + Vector2(
		roundf((grid_w - shape_w) * 0.5),
		roundf((grid_w - shape_h) * 0.5))
	FILE_SHAPE.paint(self, pos, cs, PREVIEW_CELL, {
		"type": type,
		"icon_id": icon_id,
		"alpha": 0.95,
		"show_label": false,
		"gap": PREVIEW_GAP,
	})


func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload := {
		"kind": "packet",
		"id": id,
		"name": file_name,
		"protocol": protocol,
		"type": type,
		"ext": ext,
		"icon_id": icon_id,
		"size_kb": size_kb,
		"shape_id": shape_id,
		# Внутреннее поле — shape_rotation (Control.rotation занят), но ключ
		# payload остаётся "rotation": это контракт FileGrid/TreePanel/HourDirector.
		"rotation": shape_rotation,
		"from": "packet",
	}
	var dc := _drag_controller()
	if dc != null:
		var preview := FILE_SHAPE.new()
		preview.setup(type, shape_id, shape_rotation, file_name, ext, 36.0, icon_id)
		preview.set_mode("shape")
		dc.begin(preview, "shape")
	else:
		# Без контроллера остаётся нативный ghost с фигурой-плашкой.
		var ghost := Theme90.DragGhost.new(_display_name(), cells_text().to_lower(), "packet")
		ghost.size = Vector2(176, 30)
		set_drag_preview(ghost)
	return payload


func _drag_controller() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("drag_controller")


func _can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		var dc := _drag_controller()
		if dc != null and dc.has_method("end"):
			dc.call("end")
