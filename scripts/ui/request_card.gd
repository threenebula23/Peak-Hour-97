class_name RequestCard
extends Control
## Карточка запроса клиента 400×64. Светлая карточка, три слота файлов.
## TCP-запрос в ожидании соединяется кликом по самой карточке; X отклоняет,
## двойной клик по файлу отсоединяет его. attached-файл помечается зелёной
## галочкой, пустой слот — пунктиром и мигающим «ожидается».

signal connect_pressed(id: String)
signal reject_pressed(id: String)
signal file_dropped(request_id: String, slot_index: int, payload: Dictionary)
signal detach_pressed(request_id: String, slot_index: int)

const CARD := Vector2(400, 64)
const SLOT_X := 40.0
const SLOT_STEP := 72.0
const SLOT_Y := 36.0
const SLOT_W := 68.0
const SLOT_H := 20.0

var id := ""
var client_name := ""
var client_id := ""
var protocol := "TCP"
var slots: Array = []
var slot_count := 3
var time_left := 30.0
var time_total := 60.0
var progress := 0.0
var avatar_muted := false
var connected := false
## Запрос-угроза (фишинг): приглушённый аватар и бейдж «???».
var is_attack := false
var attack_kind := ""
var attack_id := ""
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _reject: Button90
var _blink := 0.0
var _blink_on := true
var _hover_slot := -1
var _drop_slot := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void:
		hovered = false
		_hover_slot = -1)

	_reject = Button90.new()
	_reject.name = "RejectButton"
	_reject.icon = Button90.Icon.X
	_reject.position = Vector2(386, 38)
	_reject.size = Vector2(14, 14)
	_reject.tooltip_text = "Отклонить запрос"
	add_child(_reject)
	_reject.pressed.connect(func() -> void: reject_pressed.emit(id))
	set_process(true)


func setup(p_id: String, p_client: String, p_client_id: String, p_proto: String,
		p_slots: Array, p_left: float, p_total: float, p_progress: float = 0.0,
		p_is_attack: bool = false, p_attack_kind: String = "", p_attack_id: String = "",
		p_avatar_muted: bool = false) -> void:
	id = p_id
	client_name = p_client
	client_id = p_client_id
	protocol = p_proto
	slots = p_slots
	slot_count = maxi(p_slots.size(), 1)
	time_left = p_left
	time_total = p_total
	progress = p_progress
	is_attack = p_is_attack
	attack_kind = p_attack_kind
	attack_id = p_attack_id
	avatar_muted = p_avatar_muted
	_update_interaction()
	if is_attack and attack_kind == "phishing":
		tooltip_text = "ПОДОЗРИТЕЛЬНЫЙ ЗАПРОС · %s" % client_id
	else:
		tooltip_text = "%s · %s" % [client_name, client_id]
	custom_minimum_size = Vector2(CARD.x, 0)
	queue_redraw()


## Клик по карточке (не по слоту и не по X) соединяет TCP-запрос.
func _clickable() -> bool:
	return not is_attack and protocol == "TCP" and not connected


func _update_interaction() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _clickable() \
		else Control.CURSOR_ARROW


func ratio() -> float:
	if time_total <= 0.0:
		return 0.0
	return clampf(time_left / time_total, 0.0, 1.0)


func _process(delta: float) -> void:
	_blink += delta
	var on := int(_blink * 2.0) % 2 == 0
	if on != _blink_on:
		_blink_on = on
		queue_redraw()


func _slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_X + i * SLOT_STEP, SLOT_Y, SLOT_W, SLOT_H)


func _icon_rect(i: int) -> Rect2:
	return Rect2(SLOT_X + i * SLOT_STEP + 1, SLOT_Y + 1, 18, 18)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var bg := Theme90.WHITE if hovered else Theme90.PAPER_HI
	var border := Theme90.ACCENT_LIGHT if hovered else Theme90.BORDER
	draw_style_box(Theme90.box(bg, border, 4, 1,
		Color(0, 0, 0, 0.11) if hovered else Theme90.SHADOW), r)

	_draw_avatar(Rect2(8, 8, 24, 24))

	Theme90.text(self, f, Vector2(40, 4), Theme90.fit(f, client_name, 12, 146), 12,
		Theme90.INK, 146)
	Theme90.text(self, f, Vector2(40, 19), Theme90.fit(f, client_id, 10, 148), 10,
		Theme90.SHADE, 148)

	# протокол — маленький цветной чип
	var chip := Rect2(190, 7, 34, 13)
	if is_attack and attack_kind == "phishing":
		draw_style_box(Theme90.box(Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.12),
			Color(0, 0, 0, 0), 3, 0), chip)
		Theme90.text_vcenter(self, f, chip, "???", 10, Theme90.ERROR, -1,
			HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var pcol := Theme90.NAVY if protocol == "TCP" else Theme90.WARN
		draw_style_box(Theme90.box(Color(pcol.r, pcol.g, pcol.b, 0.12),
			Color(0, 0, 0, 0), 3, 0), chip)
		Theme90.text_vcenter(self, f, chip, protocol, 10, pcol, -1,
			HORIZONTAL_ALIGNMENT_CENTER)

	for i in slot_count:
		_draw_slot(i, f)

	# таймер / прогресс отправки
	var tr := Rect2(300, 4, 92, 12)
	var label := "ОТПРАВКА" if progress > 0.0 else "ОСТАЛОСЬ"
	var value := "%d%%" % int(roundf(progress * 100.0)) if progress > 0.0 \
		else "%d с" % int(ceilf(time_left))
	Theme90.text(self, f, Vector2(tr.position.x, tr.position.y), label, 10, Theme90.SHADE)
	var vw := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(tr.end.x - vw, tr.position.y), value, 10,
		_time_color())
	var bar := Rect2(300, 20, 92, 4)
	var fill := progress if progress > 0.0 else ratio()
	var bcol := Theme90.ACCENT if progress > 0.0 else _time_color()
	Theme90.draw_meter(self, bar, fill, bcol)

	# маленькая подсказка-статус в правом нижнем углу (не кнопка)
	var hint := ""
	var hint_color := Theme90.ACCENT
	if is_attack:
		hint = ""
	elif progress > 0.0:
		hint = "ОТПРАВКА…"
	elif protocol != "TCP":
		hint = "UDP · АВТО"
		hint_color = Theme90.WARN
	elif connected:
		hint = "ПОДКЛЮЧЁН"
		hint_color = Theme90.SUCCESS
	else:
		hint = "КЛИК — СОЕДИНИТЬСЯ"
	if not hint.is_empty():
		Theme90.text_vcenter(self, f, Rect2(288, 42, 88, 16), hint, 8,
			hint_color, -1, HORIZONTAL_ALIGNMENT_RIGHT)

	if hovered and _drop_slot < 0:
		draw_style_box(Theme90.box(Color(0, 0, 0, 0), Theme90.ACCENT_LIGHT, 4, 1),
			r.grow(-1.0))
	if _drop_slot >= 0:
		Theme90.draw_dashed_box(self, Rect2(2, 2, size.x - 4, size.y - 4),
			Theme90.ACCENT, 4.0, 1.2)


func _time_color() -> Color:
	if ratio() < 0.2:
		return Theme90.ERROR
	if ratio() < 0.5:
		return Theme90.WARN
	return Theme90.SUCCESS


func _draw_avatar(r: Rect2) -> void:
	var bg := Theme90.PAPER_LO if avatar_muted else Theme90.ACCENT
	var fg := Theme90.SHADE if avatar_muted else Theme90.WHITE
	draw_style_box(Theme90.box(bg, Color(0, 0, 0, 0), 5, 0), r)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x, r.position.y + 5), _monogram(), 14, fg,
		r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	draw_circle(Vector2(r.end.x - 4, r.end.y - 4), 3.0, Theme90.PAPER_HI)
	draw_circle(Vector2(r.end.x - 4, r.end.y - 4), 2.0,
		Theme90.SHADE if avatar_muted else Theme90.SUCCESS)


func _monogram() -> String:
	if is_attack:
		return "?"
	var parts := client_name.replace("«", " ").replace("»", " ").split(" ", false)
	if parts.is_empty():
		return "?"
	var last := str(parts[parts.size() - 1])
	if last.length() == 0:
		return "?"
	return last.substr(0, 1).to_upper()


func _draw_slot(i: int, f: Font) -> void:
	var cell := _slot_rect(i)
	var ir := _icon_rect(i)
	var data: Variant = slots[i] if i < slots.size() else null
	var drop := _drop_slot == i
	if data == null:
		Theme90.draw_dashed_box(self, cell, Color(Theme90.SHADE.r, Theme90.SHADE.g,
			Theme90.SHADE.b, 0.55), 2.5, 1.0)
		Theme90.text(self, f, Vector2(cell.position.x + 5, cell.position.y + 4), "+", 12,
			Theme90.SHADE)
		if _blink_on:
			Theme90.text(self, f, Vector2(cell.position.x + 15, cell.position.y + 5),
				"ожидается", 10, Theme90.WARN)
		if drop:
			Theme90.draw_dashed_box(self, cell.grow(1), Theme90.ACCENT, 2.5, 1.4)
		return
	var d: Dictionary = data
	var t := str(d.get("type", "text"))
	var col := FileCard.type_color(t)
	draw_style_box(Theme90.box(Theme90.WHITE, Color(col.r, col.g, col.b, 0.5), 3, 1),
		cell)
	Theme90.draw_doc_icon(self, ir, t, col)
	var nm := "%s.%s" % [str(d.get("name", "")), str(d.get("ext", ""))]
	Theme90.text(self, f, Vector2(cell.position.x + 22, cell.position.y + 5),
		Theme90.fit(f, nm, 10, SLOT_W - 24.0), 10, Theme90.INK, SLOT_W - 24.0)
	if bool(d.get("attached", false)):
		Theme90.draw_check_badge(self, Vector2(cell.position.x + 17, cell.position.y + 2),
			4.5)
	# подсказка «отсоединить» на наведении
	if _hover_slot == i or drop:
		var xr := Rect2(cell.end.x - 12, cell.position.y + 1, 11, 11)
		draw_circle(xr.get_center(), 5.5, Color(Theme90.ERROR.r, Theme90.ERROR.g,
			Theme90.ERROR.b, 0.92))
		Theme90.draw_x(self, xr, Theme90.WHITE, 1.0)
	if drop:
		Theme90.draw_dashed_box(self, cell.grow(1), Theme90.ACCENT, 2.5, 1.4)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hover_slot
		_hover_slot = _slot_at(event.position)
		if prev != _hover_slot:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var i := _slot_at(event.position)
			if i >= 0:
				# Слоты (и X отсоединения) не должны запускать соединение.
				if event.double_click and i < slots.size() and slots[i] != null:
					detach_pressed.emit(id, i)
					accept_event()
				return
			accept_event()
			if _clickable():
				connect_pressed.emit(id)


func _slot_at(pos: Vector2) -> int:
	for i in slot_count:
		if _slot_rect(i).has_point(pos):
			return i
	return -1


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("kind", "") != "file":
		return false
	var i := _slot_at(at_position)
	if i < 0:
		i = _first_empty()
	_drop_slot = i
	queue_redraw()
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var i := _slot_at(at_position)
	if i < 0:
		i = _first_empty()
	_drop_slot = -1
	queue_redraw()
	file_dropped.emit(id, i, data)


func _first_empty() -> int:
	for i in slot_count:
		if i >= slots.size() or slots[i] == null:
			return i
	return slot_count - 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_slot = -1
		queue_redraw()
