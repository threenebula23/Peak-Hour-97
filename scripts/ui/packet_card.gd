class_name PacketCard
extends Control
## Карточка входящего пакета 400×44.
## Иконка, имя+ext, бейдж TCP/UDP, таймер (зелёный/жёлтый/красный + мигание <5 %),
## секунды и прогресс загрузки. TCP-пакет в ожидании соединяется кликом по
## карточке; перетаскивание в папку по-прежнему работает.
## Перетаскивается как {"kind": "packet", "id": ...}.

signal connect_pressed(id: String)

const CARD := Vector2(400, 44)
## Допустимое смещение мыши, при котором нажатие считается кликом, а не drag.
const CLICK_SLOP := 6.0

var id := ""
var file_name := ""
var ext := ""
var type := "text"
var protocol := "TCP"
var time_left := 20.0
var time_total := 40.0
var progress := 0.0
var size_kb := 0
var state := "normal"
## Карточка-угроза (мусор/DDoS/шифровальщик): без кнопки соединения,
## перетаскивается в щит-карантин.
var is_attack := false
var attack_kind := ""
var attack_id := ""

var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _blink := 0.0
var _blink_on := true
var _pressed := false
var _press_pos := Vector2.ZERO
var _drag_started := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	set_process(true)


func setup(p_id: String, p_name: String, p_ext: String, p_type: String, p_proto: String,
		p_left: float, p_total: float, p_progress: float = 0.0, p_size_kb: int = 0,
		p_is_attack: bool = false, p_attack_kind: String = "", p_attack_id: String = "",
		p_state: String = "waiting") -> void:
	id = p_id
	file_name = p_name
	ext = p_ext
	type = p_type
	protocol = p_proto
	time_left = p_left
	time_total = p_total
	progress = p_progress
	size_kb = p_size_kb
	is_attack = p_is_attack
	attack_kind = p_attack_kind
	attack_id = p_attack_id
	state = p_state
	_update_interaction()
	queue_redraw()


## Клик по карточке соединяет только готовый TCP-пакет.
func _clickable() -> bool:
	return not is_attack and protocol == "TCP" and state == "waiting"


func _update_interaction() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _clickable() \
		else Control.CURSOR_ARROW
	if is_attack:
		tooltip_text = "УГРОЗА: %s\nПеретащите в ЩИТ (карантин)" % _display_name()
	elif protocol == "TCP":
		tooltip_text = "%s\n%d КБ · TCP · Клик — соединиться; перетащите в папку" % [
			_display_name(), size_kb]
	else:
		tooltip_text = "%s\n%d КБ · UDP · перетащите в папку" % [_display_name(), size_kb]


## Имя для показа: атака-шифровальщик приходит уже с расширением (.exe),
## поэтому не добавляем тип повторно.
func _display_name() -> String:
	if is_attack and file_name.contains("."):
		# шифровальщик приходит как «счёт.exe» — расширение уже в имени
		return file_name
	if ext.is_empty():
		return file_name
	return "%s.%s" % [file_name, ext]


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

	if is_attack:
		_draw_attack_icon(Rect2(6, 12, 20, 20))
	else:
		var tc := FileCard.type_color(type)
		Theme90.draw_doc_icon(self, Rect2(6, 12, 20, 20), type, tc)
	Theme90.text(self, f, Vector2(32, 2), _display_name(), 12,
		Theme90.ERROR if is_attack else Theme90.INK, 186)

	# бейдж протокола / тип угрозы
	var badge := Rect2(222, 4, 28, 13)
	draw_style_box(Theme90.well_box(Theme90.WHITE), badge)
	if is_attack:
		var mark := "???"
		var mark_color := Theme90.SHADE
		match attack_kind:
			"ddos":
				mark = "???"
				mark_color = Theme90.ERROR
			"ransomware":
				mark = "EXE"
				mark_color = Theme90.ERROR
			"junk":
				mark = "??"
				mark_color = Theme90.SHADE
			_:
				mark = "!"
				mark_color = Theme90.WARN
		Theme90.text_vcenter(self, f, badge, mark, 10, mark_color, -1, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		Theme90.text_vcenter(self, f, badge, protocol, 10,
			Theme90.NAVY if protocol == "TCP" else Theme90.WARN, -1, HORIZONTAL_ALIGNMENT_CENTER)

	# таймер
	var tr := Rect2(32, 19, 160, 5)
	var col := timer_color()
	if not _blink_on:
		col = Theme90.ERROR.lerp(Theme90.FACE, 0.45)
	Theme90.draw_meter(self, tr, ratio(), col, Theme90.PAPER_LO)

	# секунды + размер
	var w := Theme90.num_line(self, Vector2(197, 17), str(int(ceilf(time_left))), 8, timer_color(), " с", 10)
	Theme90.text(self, f, Vector2(197 + w + 3, 19), "·", 10, Theme90.SHADE)
	Theme90.num_line(self, Vector2(197 + w + 8, 17), str(size_kb), 8, Theme90.SHADE, " КБ", 10)

	# состояние
	var status := "В ОЧЕРЕДИ"
	var status_color := Theme90.DARK
	if is_attack:
		status = "УГРОЗА · В ЩИТ"
		status_color = Theme90.ERROR
		if attack_kind == "junk":
			status = "МУСОР · В ЩИТ"
			status_color = Theme90.SHADE
		elif attack_kind == "ransomware":
			status = "ВИРУС · В ЩИТ"
		elif attack_kind == "ddos":
			status = "DDoS · ДЕРЖИТЕ ЩИТ"
	elif progress > 0.0:
		status = "ПЕРЕДАЧА ИДЁТ"
		status_color = Theme90.ACCENT
	elif protocol != "TCP":
		status = "ОДНОСТОРОННЯЯ ПЕРЕДАЧА"
	else:
		status = "ГОТОВ К СОЕДИНЕНИЮ"
	Theme90.text(self, f, Vector2(32, 29), status, 10, status_color, 220)

	# прогресс загрузки (справа под кнопкой); у угроз — метка щита
	if is_attack:
		Theme90.text(self, f, Vector2(300, 29), "ЩИТ", 10, Theme90.ERROR, 76)
		return
	var pr := Rect2(300, 27, 76, 4)
	Theme90.draw_meter(self, pr, progress, Theme90.ACCENT, Theme90.PAPER_LO)
	Theme90.num_line(self, Vector2(380, 21), str(int(progress * 100.0)), 8, Theme90.DARK, "%", 8)


func _draw_attack_icon(r: Rect2) -> void:
	var f := Theme90.ui()
	var soft := Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.12)
	match attack_kind:
		"junk":
			draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 4, 1), r)
			Theme90.text(self, f, Vector2(r.position.x, r.position.y + 2), "?", 14,
				Theme90.SHADE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		"ddos":
			draw_style_box(Theme90.box(soft, Color(0, 0, 0, 0), 4, 0), r)
			for i in 3:
				draw_rect(Rect2(r.position.x + 4, r.position.y + 5 + i * 4, r.size.x - 8, 1.5),
					Theme90.ERROR)
		"ransomware":
			draw_style_box(Theme90.box(soft, Color(0, 0, 0, 0), 4, 0), r)
			draw_rect(Rect2(r.position.x + 4, r.position.y + 4, 12, 12), Theme90.ERROR, false, 1.0)
			draw_rect(Rect2(r.position.x + 9, r.position.y + 9, 4, 4), Theme90.ERROR)
		_:
			draw_style_box(Theme90.box(soft, Color(0, 0, 0, 0), 4, 0), r)
			Theme90.text(self, f, Vector2(r.position.x, r.position.y + 2), "!", 14,
				Theme90.ERROR, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
			_drag_started = false
			return
		if not _pressed:
			return
		_pressed = false
		# Drag начинается через _get_drag_data; отпускание после него — не клик.
		if _drag_started or event.position.distance_to(_press_pos) > CLICK_SLOP:
			_drag_started = false
			return
		if _clickable():
			connect_pressed.emit(id)
			accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if event.position.distance_to(_press_pos) > CLICK_SLOP:
			_drag_started = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_pressed = false
		_drag_started = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	_drag_started = true
	var ghost := Theme90.DragGhost.new(_display_name(),
		("УГРОЗА · В ЩИТ" if is_attack else "%d КБ · %s" % [size_kb, protocol]), "packet")
	ghost.size = Vector2(168, 30)
	set_drag_preview(ghost)
	return {
		"kind": "packet",
		"id": id,
		"name": file_name,
		"protocol": protocol,
		"type": type,
		"is_attack": is_attack,
		"attack_kind": attack_kind,
		"attack_id": attack_id,
	}


func _can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	return false
