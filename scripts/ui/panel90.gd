class_name Panel90
extends Control
## Серая панель с фаской 2 px. Основа всех блоков интерфейса.
##
## KIND_GROUP рисует утопленную рамку с гравированным заголовком —
## это «заголовки групп» в стиле 90-х.

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
@export var title_size := Theme90.FS_BODY
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
			Theme90.draw_bevel(self, r, false, Theme90.BEVEL, face)
			if deep:
				var inner := r.grow(-Theme90.BEVEL)
				draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), Theme90.FACE_HI)
				draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), Theme90.FACE_HI)
		Kind.SUNKEN:
			Theme90.draw_bevel(self, r, true, Theme90.BEVEL, face)
		Kind.FLAT:
			draw_rect(r, face)
		Kind.GROUP:
			_draw_group(r)


func _draw_group(r: Rect2) -> void:
	Theme90.draw_bevel(self, r, true, Theme90.BEVEL, face)
	if title.is_empty():
		return
	var f := Theme90.ui()
	var inner := r.grow(-Theme90.BEVEL)
	var tx := inner.position.x + 7.0
	var ty := inner.position.y + 3.0
	if not title.is_empty():
		Theme90.text_engraved(self, f, Vector2(tx, ty), title, title_size)
	if not title_right.is_empty():
		var w := f.get_string_size(title_right, HORIZONTAL_ALIGNMENT_LEFT, -1, Theme90.FS_MICRO).x
		Theme90.text(self, f, Vector2(inner.end.x - w - 7.0, ty + 2.0), title_right,
			Theme90.FS_MICRO, Theme90.DARK)
	# гравированная линия под заголовком
	var ly := inner.position.y + 21.0
	draw_rect(Rect2(inner.position.x + 4, ly, inner.size.x - 8, 1), Theme90.SHADE)
	draw_rect(Rect2(inner.position.x + 4, ly + 1, inner.size.x - 8, 1), Theme90.LIGHT)
