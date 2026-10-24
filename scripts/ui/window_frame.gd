class_name WindowFrame
extends Control
## Окно программы 90-х: серая фаска, синий титлбар 20 px,
## иконка, подпись справа и неактивные квадраты `_ □ ×`.

signal close_requested

const TITLE_H := 20.0

@export var title := "ОКНО":
	set(v):
		title = v
		queue_redraw()
@export var title_hint := "":
	set(v):
		title_hint = v
		queue_redraw()
@export var icon_kind := "generic":
	set(v):
		icon_kind = v
		queue_redraw()
@export var title_only := false:
	set(v):
		title_only = v
		queue_redraw()
@export var title_logo := false:
	set(v):
		title_logo = v
		queue_redraw()
@export var title_size := Theme90.FS_BODY
@export var close_enabled := false
@export var accent_line := false:
	set(v):
		accent_line = v
		queue_redraw()

var content: Control
var _btn_rects: Array[Rect2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 80.0), TITLE_H + 24.0)
	if content == null:
		content = Control.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_PASS
		content.clip_contents = true
		add_child(content)
	_layout()
	resized.connect(_layout)


func _layout() -> void:
	if content == null:
		return
	content.position = Vector2(2, TITLE_H + 2.0)
	content.size = Vector2(maxf(0.0, size.x - 4.0), maxf(0.0, size.y - TITLE_H - 4.0))
	content.custom_minimum_size = Vector2.ZERO


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.FACE)
	# внутренняя светлая линия для объёма
	var inner := r.grow(-Theme90.BEVEL)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), Theme90.FACE_HI)
	draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), Theme90.FACE_HI)
	if title_only:
		_draw_title()
		return
	_draw_title()
	# тень отделяет титлбар от тела окна
	draw_rect(Rect2(2, TITLE_H + 2.0, size.x - 4.0, 1), Theme90.FACE_HI)


func _draw_title() -> void:
	var tr := Rect2(2, 2, size.x - 4.0, TITLE_H)
	Theme90.draw_vgrad(self, tr, Theme90.NAVY, Theme90.NAVY_DEEP)
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, 1)), Color(0.0, 0.0, 0.372549))
	draw_rect(Rect2(tr.position.x, tr.end.y - 1, tr.size.x, 1), Theme90.DARK)
	if accent_line:
		draw_rect(Rect2(tr.position.x, tr.end.y - 2, tr.size.x, 1), Theme90.ACCENT)

	# иконка
	_draw_icon(Rect2(tr.position.x + 4.0, tr.position.y + 3.0, 14.0, 14.0))

	# подпись справа (доступное место до кнопок)
	_btn_rects.clear()
	var bx := tr.end.x - 6.0 - 46.0
	if not close_enabled:
		pass
	for i in 3:
		_btn_rects.append(Rect2(bx + i * 16.0, tr.position.y + 4.0, 14.0, 12.0))

	var f := Theme90.ui()
	var tx := tr.position.x + 22.0
	if not title.is_empty():
		var tf: Font = Theme90.logo() if title_logo else f
		var tsz := title_size
		var th := tf.get_height(tsz)
		Theme90.text(self, tf, Vector2(tx, tr.position.y + roundf((TITLE_H - th) * 0.5)),
			title, tsz, Theme90.WHITE)
		tx += tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x + 10.0

	if not title_hint.is_empty():
		var hint := title_hint
		var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Theme90.FS_MICRO).x
		var limit := bx - 10.0 - tx
		if hw > limit:
			hint = Theme90.fit(f, hint, Theme90.FS_MICRO, limit)
			hw = f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Theme90.FS_MICRO).x
		Theme90.text(self, f, Vector2(bx - 8.0 - hw, tr.position.y + 4.0), hint,
			Theme90.FS_MICRO, Theme90.ACCENT_LIGHT)

	# квадраты кнопок
	for i in 3:
		var br: Rect2 = _btn_rects[i]
		Theme90.draw_bevel(self, br, false, 1.0, Theme90.FACE)
		var glyph := Color(0.55, 0.55, 0.55) if not close_enabled else Theme90.INK
		match i:
			0:
				draw_rect(Rect2(br.position.x + 3, br.position.y + br.size.y - 4, 8, 1), glyph)
			1:
				draw_rect(Rect2(br.position.x + 3, br.position.y + 2, 8, 8), glyph, false, 1.0)
				draw_rect(Rect2(br.position.x + 3, br.position.y + 2, 8, 2), glyph)
			2:
				draw_line(Vector2(br.position.x + 4, br.position.y + 3), Vector2(br.position.x + 9, br.position.y + 8), glyph, 1.0)
				draw_line(Vector2(br.position.x + 9, br.position.y + 3), Vector2(br.position.x + 4, br.position.y + 8), glyph, 1.0)


func _draw_icon(r: Rect2) -> void:
	var c := Theme90.ACCENT_LIGHT
	match icon_kind:
		"inbox":
			draw_rect(Rect2(r.position.x, r.position.y + 8, 14, 6), Theme90.WHITE)
			draw_rect(Rect2(r.position.x, r.position.y + 8, 14, 6), c, false, 1.0)
			draw_rect(Rect2(r.position.x + 4, r.position.y, 2, 6), Theme90.WHITE)
			draw_rect(Rect2(r.position.x + 5, r.position.y, 6, 1), Theme90.WHITE)
			Theme90.draw_arrow(self, Rect2(r.position.x + 3, r.position.y + 1, 8, 6), 1, Theme90.WHITE)
		"outbox":
			draw_rect(Rect2(r.position.x, r.position.y + 8, 14, 6), Theme90.WHITE)
			draw_rect(Rect2(r.position.x, r.position.y + 8, 14, 6), c, false, 1.0)
			Theme90.draw_arrow(self, Rect2(r.position.x + 3, r.position.y + 1, 8, 6), 0, Theme90.WHITE)
		"files":
			draw_rect(Rect2(r.position.x + 3, r.position.y + 1, 9, 11), Theme90.WHITE)
			draw_rect(Rect2(r.position.x + 3, r.position.y + 1, 9, 11), c, false, 1.0)
			draw_rect(Rect2(r.position.x + 1, r.position.y + 4, 9, 10), Theme90.WHITE)
			draw_rect(Rect2(r.position.x + 1, r.position.y + 4, 9, 10), c, false, 1.0)
			for i in 3:
				draw_rect(Rect2(r.position.x + 3, r.position.y + 7 + i * 2, 5, 1), c)
		"tree":
			for i in 3:
				draw_rect(Rect2(r.position.x + 1 + i * 3, r.position.y + 1 + i * 4, 7, 3), Theme90.WHITE)
				draw_rect(Rect2(r.position.x + 1 + i * 3, r.position.y + 1 + i * 4, 7, 3), c, false, 1.0)
		"app":
			# дискета
			draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 12, 12), Theme90.ACCENT_PALE)
			draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 12, 12), Theme90.WHITE, false, 1.0)
			draw_rect(Rect2(r.position.x + 4, r.position.y + 2, 6, 4), Theme90.NAVY)
			draw_rect(Rect2(r.position.x + 3, r.position.y + 8, 8, 4), Theme90.ACCENT)
			draw_rect(Rect2(r.position.x + 5, r.position.y + 9, 4, 1), Theme90.ACCENT_PALE)
		_:
			draw_rect(Rect2(r.position.x + 2, r.position.y + 2, 10, 10), Theme90.ACCENT_PALE)
			draw_rect(Rect2(r.position.x + 2, r.position.y + 2, 10, 10), Theme90.WHITE, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _btn_rects.size():
			if _btn_rects[i].has_point(event.position):
				if i == 2 and close_enabled:
					close_requested.emit()
				accept_event()
				return


func set_title(t: String, hint: String = "") -> void:
	title = t
	title_hint = hint
	queue_redraw()
