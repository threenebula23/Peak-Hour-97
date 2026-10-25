class_name RequestCard
extends Control
## Карточка запроса клиента 400×108 (v2).
##
## Показывает квадратные чипы прикреплённых файлов, счётчик
## «ПРИКРЕПЛЕНО X/Y», предсказанный выбор мини-игры (S → игра · T),
## переключатель TCP/UDP, явную кнопку ОТПРАВИТЬ, ОТКРЕПИТЬ и ОТКЛОНИТЬ.
## Атак/фишинга в карточке больше нет.

signal send_pressed(id: String)
signal protocol_toggle_requested(id: String)
signal reject_pressed(id: String)
signal file_dropped(request_id: String, slot_index: int, payload: Dictionary)
signal detach_pressed(request_id: String, slot_index: int)
## Legacy: соединение удалено. Сигнал оставлен, чтобы старые подписи не падали.
signal connect_pressed(id: String)

const CARD := Vector2(400, 108)
const ECONOMY := preload("res://scripts/core/economy.gd")
const SLOT_X := 8.0
const SLOT_STEP := 90.0
const SLOT_Y := 30.0
const SLOT_W := 86.0
const SLOT_H := 26.0
const PROTO_RECT := Rect2(178, 6, 44, 16)

const COEFF := {"text": 1, "sound": 2, "photo": 4, "video": 8}
const SEND_ORDER := ["dots", "sound", "wires", "text", "video", "photo", "maze"]
const GAME_NAMES := {
	"dots": "ОДНА ЛИНИЯ",
	"sound": "УРОВНИ",
	"wires": "ПРОВОДА",
	"text": "ЧУЖОЕ СЛОВО",
	"video": "РАСКАДРОВКА",
	"photo": "КАДР",
	"maze": "ЛАБИРИНТ",
}

var id := ""
var client_name := ""
var client_id := ""
var protocol := "TCP"
var slots: Array = []
var required_count := 0
var time_left := 30.0
var time_total := 30.0
var progress := 0.0
var queued := false
var sending := false
var minigame_active := false
## Готовность контейнера (HourDirector.is_request_ready): файлы собраны.
var send_ready := false
var send_sum := 0
var minigame_id := ""
var minigame_tier := 0

var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _send_btn: Button90
var _detach_btn: Button90
var _reject_btn: Button90
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

	_send_btn = _make_button("ОТПРАВИТЬ", Vector2(8, 86), Vector2(92, 18), true)
	_send_btn.pressed.connect(func() -> void:
		if can_send():
			send_pressed.emit(id))
	_detach_btn = _make_button("ОТКРЕПИТЬ", Vector2(104, 86), Vector2(86, 18), false)
	_detach_btn.pressed.connect(func() -> void:
		var index := _last_attached_index()
		if index >= 0:
			detach_pressed.emit(id, index))
	_reject_btn = _make_button("ОТКЛОНИТЬ", Vector2(194, 86), Vector2(90, 18), false)
	_reject_btn.danger = true
	_reject_btn.pressed.connect(func() -> void: reject_pressed.emit(id))
	set_process(true)


func _make_button(caption: String, pos: Vector2, sz: Vector2, accent: bool) -> Button90:
	var b := Button90.new()
	b.caption = caption
	b.caption_size = 10
	b.accent = accent
	b.position = pos
	b.size = sz
	add_child(b)
	return b


## Совместимые первые 8 аргументов v1 + v2-поля.
func setup(p_id: String, p_client: String, p_client_id: String, p_proto: String,
		p_slots: Array, p_left: float, p_total: float, p_progress: float = 0.0,
		p_required: int = 0, p_queued: bool = false, p_sending: bool = false,
		p_send_sum: int = 0, p_minigame_id: String = "", p_minigame_tier: int = 0,
		p_minigame_active: bool = false, p_ready: bool = false) -> void:
	id = p_id
	client_name = p_client
	client_id = p_client_id
	protocol = str(p_proto).to_upper()
	if protocol != "UDP":
		protocol = "TCP"
	slots = p_slots.duplicate(true) if p_slots is Array else []
	required_count = maxi(int(p_required), slots.size())
	if required_count <= 0 and not slots.is_empty():
		required_count = slots.size()
	time_left = p_left
	time_total = p_total
	progress = clampf(p_progress, 0.0, 1.0)
	queued = p_queued
	sending = p_sending
	minigame_active = p_minigame_active
	send_ready = p_ready
	send_sum = int(p_send_sum)
	minigame_id = str(p_minigame_id)
	minigame_tier = int(p_minigame_tier)
	tooltip_text = "%s · %s" % [client_name, client_id]
	custom_minimum_size = Vector2(CARD.x, 0)
	_update_buttons()
	queue_redraw()


func _update_buttons() -> void:
	if _send_btn != null:
		_send_btn.disabled = not can_send()
		_send_btn.tooltip_text = "Отправить контейнер" if can_send() \
			else _send_disabled_reason()
	if _detach_btn != null:
		_detach_btn.disabled = attached_count() <= 0 or sending or minigame_active or queued
	if _reject_btn != null:
		_reject_btn.disabled = sending


func ratio() -> float:
	if time_total <= 0.0:
		return 0.0
	return clampf(time_left / time_total, 0.0, 1.0)


func attached_count() -> int:
	var n := 0
	for slot in slots:
		if slot is Dictionary and bool(slot.get("attached", false)):
			n += 1
	return n


func can_send() -> bool:
	if required_count <= 0:
		return false
	if sending or queued or minigame_active:
		return false
	return attached_count() >= required_count and send_ready


func send_disabled() -> bool:
	return _send_btn != null and _send_btn.disabled


func _send_disabled_reason() -> String:
	if sending:
		return "Отправка уже идёт"
	if queued:
		return "Ожидание свободного слота"
	if minigame_active:
		return "Сначала завершите мини-игру"
	if attached_count() < required_count:
		return "Прикрепите файлы: %d из %d" % [attached_count(), required_count]
	return "Отправка недоступна"


## Предсказание мини-игры: сумма коэффициентов → игра и ступень (§6).
## Пока мини-игра не запущена, игра/ступень считаются тем же плотным
## маппингом B4 (Economy.send_minigame_for), что и при реальной отправке.
func prediction() -> Dictionary:
	var types: Array = []
	var computed_sum := 0
	for slot in slots:
		if slot is Dictionary and bool(slot.get("attached", false)):
			var t := str(slot.get("type", "text"))
			types.append(t)
			computed_sum += int(COEFF.get(t, 1))
	var sum := send_sum if send_sum > 0 else computed_sum
	var pick: Dictionary = ECONOMY.send_minigame_for(types)
	var game := str(pick.get("id", "dots"))
	var tier := clampi(int(pick.get("tier", 1)), 1, 4)
	var index := int(pick.get("index", 0))
	if not minigame_id.is_empty():
		# Мини-игра уже активна: показываем выбор директора, не пересчитываем.
		game = minigame_id
		if minigame_tier > 0:
			tier = clampi(minigame_tier, 1, 4)
	return {
		"sum": sum,
		"index": index,
		"id": game,
		"name": _game_name(game),
		"tier": tier,
	}


func minigame_text() -> String:
	var p := prediction()
	if int(p.get("sum", 0)) <= 0:
		return "МИНИ-ИГРА: —"
	return "МИНИ-ИГРА: %s · T%d" % [str(p.get("name", "")), int(p.get("tier", 1))]


func difficulty_text() -> String:
	return "СЛОЖНОСТЬ: %d" % int(prediction().get("sum", 0))


func _game_name(game_id: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("minigame_def"):
		var def: Dictionary = data.call("minigame_def", game_id)
		var name_ru := str(def.get("name_ru", ""))
		if not name_ru.is_empty():
			return name_ru.to_upper()
	return str(GAME_NAMES.get(game_id, game_id.to_upper()))


func _process(delta: float) -> void:
	_blink += delta
	var on := int(_blink * 2.0) % 2 == 0
	if on != _blink_on:
		_blink_on = on
		queue_redraw()


func _slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_X + i * SLOT_STEP, SLOT_Y, SLOT_W, SLOT_H)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var bg := Theme90.WHITE if hovered else Theme90.PAPER_HI
	var border := Theme90.ACCENT_LIGHT if hovered else Theme90.BORDER
	draw_style_box(Theme90.box(bg, border, 4, 1,
		Color(0, 0, 0, 0.11) if hovered else Theme90.SHADOW), r)

	_draw_avatar(Rect2(8, 6, 20, 20))

	Theme90.text(self, f, Vector2(32, 4), Theme90.fit(f, client_name, 12, 140), 12,
		Theme90.INK, 140)
	Theme90.text(self, f, Vector2(32, 17), Theme90.fit(f, client_id, 9, 140), 9,
		Theme90.SHADE, 140)

	_draw_protocol_chip(f)
	_draw_timer(f)

	for i in maxi(required_count, 1):
		_draw_slot(i, f)

	_draw_counter(f)
	_draw_prediction(f)

	if hovered and _drop_slot < 0:
		draw_style_box(Theme90.box(Color(0, 0, 0, 0), Theme90.ACCENT_LIGHT, 4, 1),
			r.grow(-1.0))
	if _drop_slot >= 0:
		Theme90.draw_dashed_box(self, Rect2(2, 2, size.x - 4, size.y - 4),
			Theme90.ACCENT, 4.0, 1.2)


func _draw_protocol_chip(f: Font) -> void:
	var pcol := Theme90.NAVY if protocol == "TCP" else Theme90.WARN
	draw_style_box(Theme90.box(Color(pcol.r, pcol.g, pcol.b, 0.13),
		Color(pcol.r, pcol.g, pcol.b, 0.45), 3, 1), PROTO_RECT)
	Theme90.text_vcenter(self, f, PROTO_RECT, protocol, 10, pcol, -1,
		HORIZONTAL_ALIGNMENT_CENTER)
	Theme90.draw_chevron(self, Vector2(PROTO_RECT.end.x - 5, PROTO_RECT.get_center().y),
		2, pcol, 2.0, 1.0)


func _draw_timer(f: Font) -> void:
	var label := "ОСТАЛОСЬ"
	var value := "%d с" % int(ceilf(time_left))
	var col := _time_color()
	if sending:
		label = "ОТПРАВКА"
		value = "%d%%" % int(roundf(progress * 100.0))
		col = Theme90.ACCENT
	elif queued:
		label = "СЛОТ"
		value = "ОЖИДАНИЕ"
		col = Theme90.WARN
	elif minigame_active:
		label = "СОСТОЯНИЕ"
		value = "МИНИ-ИГРА"
		col = Theme90.ACCENT
	Theme90.text(self, f, Vector2(232, 4), label, 9, Theme90.SHADE)
	var vw := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(392 - vw, 3), value, 10, col)
	var fill := progress if sending else ratio()
	Theme90.draw_meter(self, Rect2(232, 19, 152, 4), fill,
		Theme90.ACCENT if sending else col)


func _draw_counter(f: Font) -> void:
	Theme90.text(self, f, Vector2(280, 31), "ПРИКРЕПЛЕНО", 8, Theme90.SHADE, 114)
	var have := attached_count()
	var cap := maxi(required_count, 0)
	var col := Theme90.SUCCESS if have >= cap and cap > 0 else Theme90.DARK
	Theme90.num_line(self, Vector2(280, 42), "%d/%d" % [have, cap], 12, col)


func _draw_prediction(f: Font) -> void:
	var p := prediction()
	Theme90.text(self, f, Vector2(8, 62), minigame_text(), 10, Theme90.NAVY, 224)
	Theme90.text(self, f, Vector2(236, 62), difficulty_text(), 10, Theme90.DARK, 156)
	if queued:
		Theme90.text(self, f, Vector2(236, 73), "ОЖИДАНИЕ СЛОТА", 9, Theme90.WARN, 156)
	elif sending:
		Theme90.text(self, f, Vector2(236, 73), "ПЕРЕДАЧА ИДЁТ", 9, Theme90.ACCENT, 156)
	elif minigame_active:
		Theme90.text(self, f, Vector2(236, 73), "ИДЁТ МИНИ-ИГРА", 9, Theme90.ACCENT, 156)
	elif _blink_on and attached_count() < required_count:
		Theme90.text(self, f, Vector2(236, 73), "НУЖНО ФАЙЛОВ: %d" % maxi(0,
			required_count - attached_count()), 9, Theme90.WARN, 156)


func _time_color() -> Color:
	if queued:
		return Theme90.WARN
	if ratio() < 0.2:
		return Theme90.ERROR
	if ratio() < 0.5:
		return Theme90.WARN
	return Theme90.SUCCESS


func _draw_avatar(r: Rect2) -> void:
	var bg := Theme90.ACCENT
	draw_style_box(Theme90.box(bg, Color(0, 0, 0, 0), 5, 0), r)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x, r.position.y + 3), _monogram(), 12,
		Theme90.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	draw_circle(Vector2(r.end.x - 3, r.end.y - 3), 2.5, Theme90.PAPER_HI)
	draw_circle(Vector2(r.end.x - 3, r.end.y - 3), 1.6, Theme90.SUCCESS)


func _monogram() -> String:
	var parts := client_name.replace("«", " ").replace("»", " ").split(" ", false)
	if parts.is_empty():
		return "?"
	var last := str(parts[parts.size() - 1])
	if last.length() == 0:
		return "?"
	return last.substr(0, 1).to_upper()


func _draw_slot(i: int, f: Font) -> void:
	var cell := _slot_rect(i)
	var data: Variant = slots[i] if i < slots.size() else null
	var drop := _drop_slot == i
	if data == null:
		Theme90.draw_dashed_box(self, cell, Color(Theme90.SHADE.r, Theme90.SHADE.g,
			Theme90.SHADE.b, 0.55), 2.5, 1.0)
		Theme90.text(self, f, Vector2(cell.position.x + 5, cell.position.y + 5), "+",
			12, Theme90.SHADE)
		if _blink_on:
			Theme90.text(self, f, Vector2(cell.position.x + 16, cell.position.y + 7),
				"ожидается", 9, Theme90.WARN, SLOT_W - 18.0)
		if drop:
			Theme90.draw_dashed_box(self, cell.grow(1), Theme90.ACCENT, 2.5, 1.4)
		return
	var d: Dictionary = data
	var t := str(d.get("type", "text"))
	var col := FileCard.type_color(t)
	draw_style_box(Theme90.box(Theme90.WHITE, Color(col.r, col.g, col.b, 0.55), 3, 1),
		cell)
	# квадратный чип: только иконка типа + имя + тип, без фигуры
	FileShape.draw_type_icon(self, Rect2(cell.position + Vector2(4, 6), Vector2(12, 12)),
		t, col)
	var nm := "%s.%s" % [str(d.get("name", "")), str(d.get("ext", ""))]
	Theme90.text(self, f, Vector2(cell.position.x + 20, cell.position.y + 3),
		Theme90.fit(f, nm, 9, SLOT_W - 24.0), 9, Theme90.INK, SLOT_W - 24.0)
	Theme90.text(self, f, Vector2(cell.position.x + 20, cell.position.y + 14),
		FileCard.type_title(t), 8, Theme90.SHADE, SLOT_W - 24.0)
	if bool(d.get("attached", false)):
		Theme90.draw_check_badge(self, Vector2(cell.end.x - 7, cell.position.y + 7), 4.5)
	if _hover_slot == i or drop:
		var xr := Rect2(cell.end.x - 12, cell.position.y + 14, 10, 10)
		draw_circle(xr.get_center(), 5.0, Color(Theme90.ERROR.r, Theme90.ERROR.g,
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
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if PROTO_RECT.has_point(event.position):
			protocol_toggle_requested.emit(id)
			accept_event()
			return
		var i := _slot_at(event.position)
		if i >= 0:
			if event.double_click and i < slots.size() and slots[i] != null \
					and bool((slots[i] as Dictionary).get("attached", false)):
				detach_pressed.emit(id, i)
			accept_event()
			return
		accept_event()


func _slot_at(pos: Vector2) -> int:
	for i in maxi(required_count, 1):
		if _slot_rect(i).has_point(pos):
			return i
	return -1


func _last_attached_index() -> int:
	for i in range(slots.size() - 1, -1, -1):
		var slot = slots[i]
		if slot is Dictionary and bool(slot.get("attached", false)):
			return i
	return -1


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if str(data.get("kind", "")) != "file":
		return false
	# Файл со стола сортировки в запрос прикреплять нельзя (§4.7).
	if str(data.get("from", "")) == "table":
		return false
	var i := _slot_at(at_position)
	if i < 0:
		i = _first_empty()
	_drop_slot = i
	var dc := _drag_controller()
	if dc != null:
		dc.set_mode("square")
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
	for i in maxi(required_count, 1):
		if i >= slots.size() or slots[i] == null:
			return i
	return maxi(0, required_count - 1)


func _drag_controller() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("drag_controller")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_slot = -1
		queue_redraw()
