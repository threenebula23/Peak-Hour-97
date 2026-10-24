class_name PacketCard
extends Control
## Карточка входящего пакета 400×44.
## Иконка, имя+ext, бейдж TCP/UDP, таймер (зелёный/жёлтый/красный + мигание <5 %),
## секунды, кнопка «Соединиться» (только TCP) и прогресс загрузки.
## Перетаскивается как {"kind": "packet", "id": ...}.

signal connect_pressed(id: String)

const CARD := Vector2(400, 44)

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

var _btn: Button90
var _blink := 0.0
var _blink_on := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)

	_btn = Button90.new()
	_btn.name = "ConnectButton"
	_btn.caption = "СОЕДИНИТЬСЯ"
	_btn.caption_size = Theme90.FS_MICRO
	_btn.position = Vector2(300, 2)
	_btn.size = Vector2(76, 18)
	add_child(_btn)
	_btn.pressed.connect(func() -> void: connect_pressed.emit(id))
	set_process(true)


func setup(p_id: String, p_name: String, p_ext: String, p_type: String, p_proto: String,
		p_left: float, p_total: float, p_progress: float = 0.0, p_size_kb: int = 0,
		p_is_attack: bool = false, p_attack_kind: String = "", p_attack_id: String = "") -> void:
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
	_update_button()
	if is_attack:
		tooltip_text = "УГРОЗА: %s\nПеретащите в ЩИТ (карантин)" % _display_name()
	else:
		tooltip_text = "%s\n%d КБ · %s" % [_display_name(), size_kb, protocol]
	queue_redraw()


func _update_button() -> void:
	if _btn == null:
		return
	_btn.caption = "СОЕДИНИТЬСЯ"
	_btn.visible = not is_attack
	_btn.disabled = is_attack or protocol != "TCP"
	_btn.tooltip_text = "" if protocol == "TCP" else "Только для TCP-пакетов"


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
	if hovered:
		Theme90.draw_bevel(self, r, false, 2.0, Theme90.FACE_HI)
	else:
		Theme90.draw_bevel(self, r, false, 2.0, Theme90.FACE)
	if hovered:
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Theme90.ACCENT_LIGHT, false, 1.0)

	if is_attack:
		_draw_attack_icon(Rect2(6, 12, 20, 20))
	else:
		var tc := FileCard.type_color(type)
		Theme90.draw_doc_icon(self, Rect2(6, 12, 20, 20), type, tc)
	Theme90.text(self, f, Vector2(32, 2), _display_name(), 12,
		Theme90.ERROR if is_attack else Theme90.INK, 186)

	# бейдж протокола / тип угрозы
	var badge := Rect2(222, 4, 28, 13)
	Theme90.draw_bevel(self, badge, true, 1.0, Theme90.WHITE)
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
	var tr := Rect2(32, 19, 160, 7)
	draw_rect(tr, Theme90.FACE_LO)
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, 1)), Theme90.SHADE)
	draw_rect(Rect2(tr.position, Vector2(1, tr.size.y)), Theme90.SHADE)
	var fill_w := floorf((tr.size.x - 2.0) * ratio())
	var col := timer_color()
	if not _blink_on:
		col = Theme90.ERROR.lerp(Theme90.FACE, 0.45)
	draw_rect(Rect2(tr.position.x + 1, tr.position.y + 1, fill_w, tr.size.y - 2.0), col)
	if fill_w > 2.0:
		draw_rect(Rect2(tr.position.x + 1, tr.position.y + 1, fill_w, 1), col.lightened(0.35))

	# секунды + размер
	var w := Theme90.num_line(self, Vector2(197, 17), str(int(ceilf(time_left))), 8, timer_color(), " с", 10)
	Theme90.text(self, f, Vector2(197 + w + 3, 19), "·", 10, Theme90.DARK)
	Theme90.num_line(self, Vector2(197 + w + 8, 17), str(size_kb), 8, Theme90.DARK, " КБ", 10)

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
	var pr := Rect2(300, 25, 76, 6)
	draw_rect(pr, Theme90.FACE_LO)
	draw_rect(Rect2(pr.position, Vector2(pr.size.x, 1)), Theme90.SHADE)
	draw_rect(Rect2(pr.position, Vector2(1, pr.size.y)), Theme90.SHADE)
	if progress > 0.0:
		draw_rect(Rect2(pr.position.x + 1, pr.position.y + 1, floorf((pr.size.x - 2.0) * progress), pr.size.y - 2.0), Theme90.ACCENT)
	Theme90.num_line(self, Vector2(380, 21), str(int(progress * 100.0)), 8, Theme90.DARK, "%", 8)


func _draw_attack_icon(r: Rect2) -> void:
	var f := Theme90.ui()
	match attack_kind:
		"junk":
			# серая иконка «?» — мусорный пакет без типа
			draw_rect(r, Theme90.FACE_LO)
			draw_rect(r, Theme90.SHADE, false, 1.0)
			Theme90.text(self, f, Vector2(r.position.x, r.position.y + 2), "?", 14,
				Theme90.FACE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		"ddos":
			draw_rect(r, Theme90.NAVY_DEEP)
			draw_rect(r, Theme90.ERROR, false, 1.0)
			for i in 3:
				draw_rect(Rect2(r.position.x + 3, r.position.y + 3 + i * 5, r.size.x - 6, 2), Theme90.ERROR)
		"ransomware":
			draw_rect(r, Theme90.NAVY_DEEP)
			draw_rect(Rect2(r.position.x + 3, r.position.y + 3, 14, 14), Theme90.ERROR, false, 1.0)
			# красный квадрат 4×4 по центру
			draw_rect(Rect2(r.position.x + 8, r.position.y + 8, 4, 4), Theme90.ERROR)
		_:
			draw_rect(r, Theme90.FACE_LO)
			draw_rect(r, Theme90.ERROR, false, 1.0)
			Theme90.text(self, f, Vector2(r.position.x, r.position.y + 2), "!", 14,
				Theme90.ERROR, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _get_drag_data(_at_position: Vector2) -> Variant:
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
