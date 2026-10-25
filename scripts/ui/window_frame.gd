class_name WindowFrame
extends Control
## Светлое окно: бумажное тело, тонкий 1 px контур, скругление 4.
## Заголовок — светлая полоса с тёмным текстом, цветной иконкой и волосяной
## линией снизу. Никаких синих титлбаров и объёмных квадратов.

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
@export var close_enabled := false:
	set(v):
		close_enabled = v
		queue_redraw()
@export var accent_line := false:
	set(v):
		accent_line = v
		queue_redraw()

var content: Control
var _close_rect := Rect2()


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
	content.position = Vector2(2.0, TITLE_H + 2.0)
	content.size = Vector2(maxf(0.0, size.x - 4.0), maxf(0.0, size.y - TITLE_H - 4.0))
	content.custom_minimum_size = Vector2.ZERO


func _icon_color() -> Color:
	match icon_kind:
		"outbox":
			return Theme90.WARN
		"files":
			return Theme90.ACCENT
		"tree":
			return Theme90.SUCCESS
		_:
			return Theme90.NAVY


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# тело окна: белая бумага + тонкий контур + мягкая тень
	draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER, 4, 1, Theme90.SHADOW), r)
	_draw_title()
	if title_only:
		return
	if accent_line:
		draw_rect(Rect2(1.0, TITLE_H + 1.0, size.x - 2.0, 1.0),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.24))


func _draw_title() -> void:
	var tr := Rect2(1.0, 1.0, maxf(0.0, size.x - 2.0), TITLE_H)
	draw_style_box(Theme90.top_box(Theme90.PAPER_HI, 4), tr)
	draw_rect(Rect2(tr.position.x + 1.0, tr.end.y, tr.size.x - 2.0, 1.0), Theme90.HAIRLINE)

	var icon_color := _icon_color()
	_draw_icon(Rect2(tr.position.x + 7.0, tr.position.y + 3.0, 14.0, 14.0), icon_color)

	# закрытие — одна аккуратная точка-крестик, только если разрешено
	_close_rect = Rect2()
	if close_enabled:
		_close_rect = Rect2(tr.end.x - 22.0, tr.position.y + 3.0, 14.0, 14.0)
		draw_circle(_close_rect.get_center(), 6.0, Color(Theme90.ERROR.r, Theme90.ERROR.g,
			Theme90.ERROR.b, 0.14))
		Theme90.draw_x(self, _close_rect, Theme90.ERROR, 1.2)

	var f := Theme90.ui()
	var tx := tr.position.x + 26.0
	var right_limit := tr.end.x - (24.0 if close_enabled else 8.0)
	if not title.is_empty():
		var tf: Font = Theme90.logo() if title_logo else f
		var tsz := 10 if title_logo else title_size
		var th := tf.get_height(tsz)
		Theme90.text(self, tf, Vector2(tx, tr.position.y + roundf((TITLE_H - th) * 0.5)),
			title, tsz, Theme90.NAVY_DEEP)
		tx += tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x + 12.0

	if not title_hint.is_empty():
		var hint := title_hint
		var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Theme90.FS_MICRO).x
		var limit := right_limit - 8.0 - tx
		if hw > limit:
			hint = Theme90.fit(f, hint, Theme90.FS_MICRO, limit)
			hw = f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1,
				Theme90.FS_MICRO).x
		if limit > 8.0:
			Theme90.text(self, f, Vector2(right_limit - hw, tr.position.y + 5.0), hint,
				Theme90.FS_MICRO, Theme90.SHADE)


func _draw_icon(r: Rect2, color: Color) -> void:
	var c := roundf(r.position.x)
	var y := roundf(r.position.y)
	match icon_kind:
		"inbox":
			draw_style_box(Theme90.box(Color(color.r, color.g, color.b, 0.12), Color(0, 0, 0, 0), 3, 0),
				r)
			Theme90.draw_packet_icon(self, Vector2(c + 1, y + 3), color)
		"outbox":
			draw_style_box(Theme90.box(Color(color.r, color.g, color.b, 0.12), Color(0, 0, 0, 0), 3, 0),
				r)
			Theme90.draw_packet_icon(self, Vector2(c + 1, y + 3), color)
			draw_line(Vector2(c + 1, y + 1), Vector2(c + 13, y + 1), color, 1.0)
		"files":
			draw_style_box(Theme90.box(Color(color.r, color.g, color.b, 0.12), Color(0, 0, 0, 0), 3, 0),
				r)
			draw_style_box(Theme90.box(Theme90.WHITE, Color(color.r, color.g, color.b, 0.55), 1, 1),
				Rect2(c + 2, y + 2, 9, 11))
			draw_style_box(Theme90.box(Theme90.WHITE, Color(color.r, color.g, color.b, 0.55), 1, 1),
				Rect2(c + 4, y + 4, 9, 11))
			for i in 3:
				draw_rect(Rect2(c + 6, y + 7 + i * 2.2, 5, 0.8), color)
		"tree":
			Theme90.draw_folder_icon(self, Vector2(c + 1, y + 2), color, true)
		"app":
			# дискета: светлая карточка с цветной наклейкой
			draw_style_box(Theme90.box(Theme90.PAPER_HI, Color(color.r, color.g, color.b, 0.5), 2, 1),
				Rect2(c + 1, y + 1, 12, 12))
			draw_rect(Rect2(c + 4, y + 2, 6, 4), color)
			draw_rect(Rect2(c + 3, y + 8, 8, 3), Color(color.r, color.g, color.b, 0.6))
			draw_rect(Rect2(c + 5, y + 9, 4, 1), Theme90.PAPER_HI)
		_:
			draw_circle(r.get_center(), 3.0, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if close_enabled and _close_rect.has_point(event.position):
			close_requested.emit()
			accept_event()


func set_title(t: String, hint: String = "") -> void:
	title = t
	title_hint = hint
	queue_redraw()
