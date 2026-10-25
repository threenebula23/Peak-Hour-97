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
const DRAG_CONTROLLER = preload("res://scripts/ui/drag_controller.gd")
const PREVIEW_CELL := 6.0
const PREVIEW_GAP := 1.0

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

var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _blink := 0.0
var _blink_on := true


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


## Совместимая сигнатура: первые 9 аргументов как в v1, затем состояние и
## форма пакета. Атаки удалены — их аргументов здесь нет.
func setup(p_id: String, p_name: String, p_ext: String, p_type: String, p_proto: String,
		p_left: float, p_total: float, p_progress: float = 0.0, p_size_kb: int = 0,
		p_state: String = "waiting", p_shape_id: String = "O1",
		p_rotation: int = 0) -> void:
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
	_update_tooltip()
	queue_redraw()


func set_time(left: float, total: float) -> void:
	time_left = left
	time_total = total
	queue_redraw()


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
	return FR.shape_cells(shape_id, shape_rotation)


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
	var shape_line := "%s · %s" % [_display_name(), cells_text().to_lower()]
	if state == "loading":
		tooltip_text = "%s\n%d КБ · %s · загрузка в папку" % [shape_line, size_kb, protocol]
	else:
		tooltip_text = "%s\n%d КБ · %s · перетащите в папку" % [shape_line, size_kb, protocol]


func _process(delta: float) -> void:
	# мигание только у «горящих» пакетов (<5 %)
	if ratio() < 0.05:
		_blink += delta
		var on := int(_blink * 4.0) % 2 == 0
		if on != _blink_on:
			_blink_on = on
			queue_redraw()
	else:
		_blink_on = true


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var face := Theme90.WHITE if hovered else Theme90.PAPER_HI
	var border := Theme90.ACCENT_LIGHT if hovered else Theme90.BORDER
	draw_style_box(Theme90.box(face, border, 4, 1,
		Color(0, 0, 0, 0.11) if hovered else Theme90.SHADOW), r)

	_draw_shape_preview(Rect2(4, 10, 30, 30))

	Theme90.text(self, f, Vector2(40, 2), Theme90.fit(f, _display_name(), 12, 168), 12,
		Theme90.INK, 168)

	# бейдж протокола
	var badge := Rect2(214, 4, 30, 13)
	draw_style_box(Theme90.well_box(Theme90.WHITE), badge)
	Theme90.text_vcenter(self, f, badge, protocol, 10,
		Theme90.NAVY if protocol == "TCP" else Theme90.WARN, -1,
		HORIZONTAL_ALIGNMENT_CENTER)

	# таймер
	var tr := Rect2(40, 20, 140, 5)
	var col := timer_color()
	if not _blink_on:
		col = Theme90.ERROR.lerp(Theme90.FACE, 0.45)
	Theme90.draw_meter(self, tr, ratio(), col, Theme90.PAPER_LO)
	var w := Theme90.num_line(self, Vector2(186, 17), str(int(ceilf(time_left))), 8,
		timer_color(), " с", 10)
	Theme90.text(self, f, Vector2(186 + w + 3, 19), "·", 10, Theme90.SHADE)
	Theme90.num_line(self, Vector2(186 + w + 8, 17), str(size_kb), 8,
		Theme90.SHADE, " КБ", 10)

	# состояние + сколько клеток займёт
	Theme90.text(self, f, Vector2(40, 31), _state_caption(), 10, _state_color(), 160)
	Theme90.text(self, f, Vector2(204, 31), cells_text(), 10, Theme90.DARK, 150)

	# прогресс загрузки справа
	var pr := Rect2(310, 42, 80, 4)
	Theme90.draw_meter(self, pr, progress, Theme90.ACCENT, Theme90.PAPER_LO)
	Theme90.num_line(self, Vector2(348, 31), str(int(progress * 100.0)), 8,
		Theme90.DARK, "%", 8)


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
		preview.setup(type, shape_id, shape_rotation, file_name, ext, 36.0)
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
