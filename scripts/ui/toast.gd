class_name ToastLayer
extends Control
## Очередь сообщений внизу справа. Живут над статус-баром, не перекрывая его.

const W := 400.0
const H := 30.0
const GAP := 4.0
const BOTTOM := 650.0

var _items: Array[Control] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func toast(text: String, kind: String = "info") -> void:
	if _items.size() >= 3:
		var old: Control = _items.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var item := ToastItem.new(text, kind)
	item.size = Vector2(W, H)
	item.position = Vector2(1276.0, _slot_y(_items.size()))
	add_child(item)
	_items.append(item)
	var target := _target_pos(_items.size() - 1)
	var tw := create_tween()
	tw.tween_property(item, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var life := create_tween()
	life.tween_interval(3.0)
	life.tween_property(item, "modulate:a", 0.0, 0.45)
	life.tween_callback(func() -> void:
		_items.erase(item)
		item.queue_free()
		_relayout())


func _slot_y(index: int) -> float:
	return BOTTOM - H - (index) * (H + GAP)


func _target_pos(index: int) -> Vector2:
	return Vector2(1272.0 - W, _slot_y(index))


func _relayout() -> void:
	for i in _items.size():
		var item := _items[i]
		if not is_instance_valid(item):
			continue
		var tw := create_tween()
		tw.tween_property(item, "position", _target_pos(i), 0.18)


class ToastItem:
	extends Control
	var txt := ""
	var kind := "info"

	func _init(p_text: String, p_kind: String) -> void:
		txt = p_text
		kind = p_kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _kind_color() -> Color:
		match kind:
			"success":
				return Theme90.SUCCESS
			"warn":
				return Theme90.WARN
			"error":
				return Theme90.ERROR
			_:
				return Theme90.NAVY

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		Theme90.draw_bevel(self, r, false, 2.0, Theme90.FACE)
		var col := _kind_color()
		draw_rect(Rect2(2, 2, 3, size.y - 4), col)
		# иконка
		var ic := Rect2(10, 9, 12, 12)
		draw_rect(ic, col)
		match kind:
			"success":
				draw_line(ic.position + Vector2(3, 6), ic.position + Vector2(5, 9), Theme90.WHITE, 1.0)
				draw_line(ic.position + Vector2(5, 9), ic.position + Vector2(9, 3), Theme90.WHITE, 1.0)
			"warn", "error":
				draw_rect(Rect2(ic.get_center().x, ic.position.y + 2, 1, 5), Theme90.WHITE)
				draw_rect(Rect2(ic.get_center().x, ic.position.y + 8, 1, 2), Theme90.WHITE)
			_:
				draw_rect(Rect2(ic.get_center().x, ic.position.y + 3, 1, 6), Theme90.WHITE)
				draw_rect(Rect2(ic.get_center().x, ic.position.y + 10, 1, 1), Theme90.WHITE)
		var f := Theme90.ui()
		Theme90.text_vcenter(self, f, Rect2(28, 0, size.x - 34, size.y),
			Theme90.fit(f, txt, 12, size.x - 36), 12, Theme90.INK)
