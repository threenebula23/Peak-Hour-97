class_name RequestCard
extends Control
## Карточка запроса клиента 400×64 (compact — 56 при 5+ запросах).
## Аватар 24×24, клиент, client_id, протокол, 1–3 слота 24×24 с именем файла,
## «ожидается» с миганием, таймер, «Соединиться» и ×.
## Принимает drag&drop {kind:"file"}.

signal connect_pressed(id: String)
signal reject_pressed(id: String)
signal file_dropped(request_id: String, slot_index: int, payload: Dictionary)
signal detach_pressed(request_id: String, slot_index: int)

const CARD := Vector2(400, 64)
const SLOT_X := 33.0
const SLOT_STEP := 82.0
const SLOT_Y := 30.0

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

var _btn: Button90
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
	_btn = Button90.new()
	_btn.name = "ConnectButton"
	_btn.caption = "СОЕДИНИТЬСЯ"
	_btn.caption_size = Theme90.FS_MICRO
	_btn.position = Vector2(296, 3)
	_btn.size = Vector2(76, 18)
	add_child(_btn)
	_btn.pressed.connect(func() -> void: connect_pressed.emit(id))

	_reject = Button90.new()
	_reject.name = "RejectButton"
	_reject.icon = Button90.Icon.X
	_reject.position = Vector2(378, 4)
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
	_btn.disabled = protocol != "TCP"
	_btn.tooltip_text = "" if protocol == "TCP" else "Только для TCP-запросов"
	if is_attack and attack_kind == "phishing":
		tooltip_text = "ПОДОЗРИТЕЛЬНЫЙ ЗАПРОС · %s" % client_id
	else:
		tooltip_text = "%s · %s" % [client_name, client_id]
	custom_minimum_size = Vector2(CARD.x, 0)
	queue_redraw()


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
	return Rect2(SLOT_X + i * SLOT_STEP, SLOT_Y, 78, 24)


func _icon_rect(i: int) -> Rect2:
	return Rect2(SLOT_X + i * SLOT_STEP, SLOT_Y, 24, 24)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var face := Theme90.FACE_HI if hovered else Theme90.FACE
	Theme90.draw_bevel(self, r, false, 2.0, face)

	# аватар
	_draw_avatar(Rect2(5, 4, 24, 24))

	# клиент
	Theme90.text(self, f, Vector2(36, 2), Theme90.fit(f, client_name, 12, 146), 12, Theme90.INK, 146)
	Theme90.text(self, f, Vector2(36, 16), client_id, 10,
		Theme90.ACCENT if not avatar_muted else Theme90.SHADE, 120)

	# бейдж протокола; у фишинга — «???»
	var badge := Rect2(186, 5, 28, 13)
	Theme90.draw_bevel(self, badge, true, 1.0, Theme90.WHITE)
	if is_attack and attack_kind == "phishing":
		Theme90.text_vcenter(self, f, badge, "???", 10, Theme90.ERROR, -1, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		Theme90.text_vcenter(self, f, badge, protocol, 10,
			Theme90.NAVY if protocol == "TCP" else Theme90.WARN, -1, HORIZONTAL_ALIGNMENT_CENTER)

	# слоты
	for i in slot_count:
		_draw_slot(i, f)

	# таймер справа
	var tb := Rect2(296, 26, 98, 6)
	draw_rect(tb, Theme90.FACE_LO)
	draw_rect(Rect2(tb.position, Vector2(tb.size.x, 1)), Theme90.SHADE)
	draw_rect(Rect2(tb.position, Vector2(1, tb.size.y)), Theme90.SHADE)
	var col := Theme90.SUCCESS
	if ratio() < 0.2:
		col = Theme90.ERROR
	elif ratio() < 0.5:
		col = Theme90.WARN
	draw_rect(Rect2(tb.position.x + 1, tb.position.y + 1, floorf((tb.size.x - 2.0) * ratio()), tb.size.y - 2.0), col)
	Theme90.text(self, f, Vector2(296, 34), "осталось", 10, Theme90.DARK)
	var lw := f.get_string_size("осталось", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.num_line(self, Vector2(296 + lw + 3, 34), str(int(ceilf(time_left))), 8,
		Theme90.DARK, " с", 10)
	Theme90.num_right(self, 392, 34, str(int(progress * 100.0)), 8, Theme90.ACCENT, "%", 8)

	var pr := Rect2(296, 47, 98, 4)
	draw_rect(pr, Theme90.FACE_LO)
	if progress > 0.0:
		draw_rect(Rect2(pr.position.x, pr.position.y, floorf(pr.size.x * progress), pr.size.y), Theme90.ACCENT)

	if hovered and _drop_slot < 0:
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Theme90.ACCENT_LIGHT, false, 1.0)
	if _drop_slot >= 0:
		Theme90.draw_dashed_box(self, Rect2(2, 2, size.x - 4, size.y - 4), Theme90.NAVY, 4.0, 2.0)


func _draw_avatar(r: Rect2) -> void:
	var bg := Theme90.FACE_LO if avatar_muted else Theme90.NAVY
	draw_rect(r, bg)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), bg.lightened(0.35))
	draw_rect(r, Theme90.SHADE if avatar_muted else Theme90.NAVY_DEEP, false, 1.0)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x, r.position.y + 4), _monogram(), 16,
		Theme90.FACE if avatar_muted else Theme90.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# индикатор «онлайн»
	draw_rect(Rect2(r.position.x + 17, r.position.y + 17, 5, 5),
		Theme90.SHADE if avatar_muted else Theme90.SUCCESS)
	draw_rect(Rect2(r.position.x + 17, r.position.y + 17, 5, 1), Theme90.WHITE)


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
	var ir := _icon_rect(i)
	var data: Variant = slots[i] if i < slots.size() else null
	var drop := _drop_slot == i
	if data == null:
		Theme90.draw_dashed_box(self, ir, Theme90.SHADE, 2.0, 1.0)
		Theme90.text(self, f, Vector2(ir.position.x + 5, ir.position.y + 8), "+", 12, Theme90.SHADE)
		if _blink_on:
			Theme90.text(self, f, Vector2(ir.position.x + 28, ir.position.y + 7), "ожидается", 10, Theme90.WARN)
		if drop:
			draw_rect(ir.grow(1), Theme90.NAVY, false, 1.0)
		return
	var d: Dictionary = data
	var t := str(d.get("type", "text"))
	var col := FileCard.type_color(t)
	draw_rect(ir, Theme90.WHITE)
	draw_rect(ir, col, false, 1.0)
	Theme90.draw_doc_icon(self, ir, t, col)
	var nm := "%s.%s" % [str(d.get("name", "")), str(d.get("ext", ""))]
	Theme90.text(self, f, Vector2(ir.position.x + 28, ir.position.y + 7), Theme90.fit(f, nm, 10, 52),
		10, Theme90.INK, 52)
	# подсказка «отсоединить» на наведении
	if _hover_slot == i or drop:
		var xr := Rect2(ir.position.x + 14, ir.position.y + 2, 10, 10)
		draw_rect(xr, Theme90.ERROR)
		Theme90.draw_x(self, xr, Theme90.WHITE, 1.0)
	if drop:
		draw_rect(ir.grow(1), Theme90.NAVY, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hover_slot
		_hover_slot = _slot_at(event.position)
		if prev != _hover_slot:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var i := _slot_at(event.position)
			if event.double_click and i >= 0 and i < slots.size() and slots[i] != null:
				detach_pressed.emit(id, i)
				accept_event()
				return
			accept_event()


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
