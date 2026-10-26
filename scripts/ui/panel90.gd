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
## Цветная полоса панели: точка и линия группы, кромка утопленной шапки,
## верхняя лента полосы слотов. Текст остаётся тёмным ради контраста.
@export var accent_color: Color = Theme90.ACCENT:
	set(v):
		accent_color = v
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
	# Полоса слотов — единственный RAISED-блок в игре: даём ей собственный
	# фиолетовый акцент, не трогая main.gd (он задаёт только kind/name).
	if kind == Kind.RAISED and accent_color == Theme90.ACCENT:
		accent_color = Theme90.PURPLE
	if mouse_filter == Control.MOUSE_FILTER_STOP:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		Kind.RAISED:
			_draw_raised(r)
		Kind.SUNKEN:
			draw_style_box(Theme90.well_box(Theme90.paper_tint(accent_color, 0.035)), r)
			draw_rect(Rect2(r.position.x, r.position.y + 2.0, 2.0,
				maxf(0.0, r.size.y - 4.0)), Theme90.alpha_of(accent_color, 0.34))
		Kind.FLAT:
			draw_rect(r, face)
			draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0),
				Theme90.alpha_of(accent_color, 0.16))
		Kind.GROUP:
			_draw_group(r)


## Полоса слотов: бумажная карточка + цветная лента сверху и кромка слева.
func _draw_raised(r: Rect2) -> void:
	draw_style_box(Theme90.box(face, Theme90.BORDER, 4, 1, Theme90.SHADOW), r)
	draw_rect(Rect2(r.position.x + 1.0, r.position.y, maxf(0.0, r.size.x - 2.0), 2.0),
		Theme90.alpha_of(accent_color, 0.72))
	draw_rect(Rect2(r.position.x, r.position.y + 2.0, 2.0, maxf(0.0, r.size.y - 2.0)),
		Theme90.alpha_of(accent_color, 0.34))


func _draw_group(r: Rect2) -> void:
	draw_style_box(Theme90.box(face, Theme90.BORDER, 4, 1, Theme90.SHADOW), r)
	var f := Theme90.ui()
	var inner := r.grow(-1.0)
	var head_y := inner.position.y + 5.0
	# Цветная верхняя лента группы + вертикальный маркер: группы читаются
	# как разные блоки, но фон остаётся бумажным.
	draw_rect(Rect2(inner.position.x + 4.0, inner.position.y, maxf(0.0, inner.size.x - 8.0), 2.0),
		Theme90.alpha_of(accent_color, 0.55))
	draw_rect(Rect2(inner.position.x + 2.0, inner.position.y + 3.0, 2.0,
		maxf(0.0, inner.size.y - 6.0)), Theme90.alpha_of(accent_color, 0.28))
	if not title.is_empty():
		draw_circle(Vector2(inner.position.x + 12.0, head_y + 5.5), 2.5, accent_color)
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
			Theme90.alpha_of(accent_color, 0.22))
