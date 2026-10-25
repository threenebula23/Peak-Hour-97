class_name Panel90
extends Control
## Светлая панель с 1 px контуром и мягкой тенью. Основа всех блоков UI.
##
## KIND_GROUP — панель с тонкой полосой заголовка: бирюзовая точка,
## спокойный заголовок 10 px и волосяной разделитель. Без гравировки.

enum Kind { RAISED, SUNKEN, FLAT, GROUP }

@export var kind: Kind = Kind.RAISED:
	set(v):
		kind = v
		queue_redraw()
@export var face: Color = Theme90.FACE:
	set(v):
		face = v
		queue_redraw()
@export var title := "":
	set(v):
		title = v
		queue_redraw()
@export var title_right := "":
	set(v):
		title_right = v
		queue_redraw()
@export var title_size := Theme90.FS_MICRO
@export var deep := false:
	set(v):
		deep = v
		queue_redraw()


func _ready() -> void:
	if mouse_filter == Control.MOUSE_FILTER_STOP:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		Kind.RAISED:
			draw_style_box(Theme90.box(face, Theme90.BORDER, 4, 1, Theme90.SHADOW), r)
		Kind.SUNKEN:
			draw_style_box(Theme90.well_box(face), r)
		Kind.FLAT:
			draw_rect(r, face)
		Kind.GROUP:
			_draw_group(r)


func _draw_group(r: Rect2) -> void:
	draw_style_box(Theme90.box(face, Theme90.BORDER, 4, 1, Theme90.SHADOW), r)
	var f := Theme90.ui()
	var inner := r.grow(-1.0)
	var head_y := inner.position.y + 5.0
	if not title.is_empty():
		draw_circle(Vector2(inner.position.x + 12.0, head_y + 5.5), 2.5, Theme90.ACCENT)
		Theme90.text(self, f, Vector2(inner.position.x + 20.0, head_y), title,
			title_size, Theme90.NAVY, inner.size.x - 40.0)
	if not title_right.is_empty():
		var tw := f.get_string_size(title_right, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Theme90.FS_MICRO).x
		Theme90.text(self, f, Vector2(inner.end.x - tw - 10.0, head_y + 0.5),
			title_right, Theme90.FS_MICRO, Theme90.SHADE)
	if not title.is_empty() or not title_right.is_empty():
		var ly := inner.position.y + 21.0
		draw_rect(Rect2(inner.position.x + 8.0, ly, maxf(0.0, inner.size.x - 16.0), 1.0),
			Theme90.HAIRLINE)
