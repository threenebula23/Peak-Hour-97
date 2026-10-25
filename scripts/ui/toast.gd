class_name ToastLayer
extends Control
## Очередь сообщений внизу справа. Живут над статус-баром, не перекрывая его.
## Светлые карточки с цветной точкой и мягкой тенью.

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
			# Гасим life-tween до освобождения узла: иначе его callback через
			# 3.45 с сработает на уже удалённом объекте (null capture).
			_stop_life(old)
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
		if not is_instance_valid(item):
			# Тост уже удалён извне — не трогаем освобождённый узел.
			_relayout()
			return
		_items.erase(item)
		item.queue_free()
		_relayout())
	item.set_meta("life_tween", life)
	# Любое внешнее удаление тоста тоже не должно оставлять висящий tween.
	item.tree_exiting.connect(func() -> void:
		_stop_life(item))


func _stop_life(item: Control) -> void:
	if item == null or not is_instance_valid(item) or not item.has_meta("life_tween"):
		return
	var tw = item.get_meta("life_tween")
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()


func _slot_y(index: int) -> float:
	return BOTTOM - H - (index) * (H + GAP)


func _target_pos(index: int) -> Vector2:
	return Vector2(1272.0 - W, _slot_y(index))


func _relayout() -> void:
	# Индексное удаление: erase()/has() на освобождённом объекте внутри
	# типизированного массива дают ошибку, remove_at() — нет.
	for i in range(_items.size() - 1, -1, -1):
		if not is_instance_valid(_items[i]):
			_items.remove_at(i)
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
				return Theme90.ACCENT

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var col := _kind_color()
		Theme90.draw_bevel(self, r, false, 1.0, Theme90.PAPER_HI)
		# цветная точка-статус вместо тяжёлой иконки
		draw_circle(Vector2(15, size.y * 0.5), 4.0, Color(col.r, col.g, col.b, 0.18))
		draw_circle(Vector2(15, size.y * 0.5), 2.4, col)
		var f := Theme90.ui()
		Theme90.text_vcenter(self, f, Rect2(28, 0, size.x - 38, size.y),
			Theme90.fit(f, txt, 12, size.x - 44), 12, Theme90.INK)
