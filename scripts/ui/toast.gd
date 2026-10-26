class_name ToastLayer
extends Control
## Очередь сообщений сверху по центру холста. Стопка растёт ВНИЗ от верхней
## кромки рабочей области: не перекрывает карточки ОТПРАВКИ и их кнопки
## ОТПРАВИТЬ/ОТКЛОНИТЬ. Светлые карточки с цветной точкой и мягкой тенью.
##
## Координаты — логические 1280×720 (canvas_items): тост шириной 400 стоит
## ровно по центру (440…840) и не заходит в правое окно ОТПРАВКА (856…1272).

const W := 400.0
const H := 30.0
const GAP := 4.0
## Первый тост: сразу под строкой меню, над заголовками ДИСК/ФАЙЛЫ.
const TOP := 44.0
## Точка входа: над кадром, карточка «въезжает» сверху вниз.
const ENTER_Y := -40.0
## Центр холста 1280 px.
const LEFT := (1280.0 - W) * 0.5
## Тайминги (Lane B): вход, перестановка, выход.
const ENTER_DUR := 0.20
const RELAYOUT_DUR := 0.16
const EXIT_DUR := 0.18
const LIFE_DUR := 3.0

var _items: Array[Control] = []
var _motion_on := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Внешний переключатель движения (Lane A / настройки).
func set_motion_enabled(on: bool) -> void:
	_motion_on = on


func _reduced() -> bool:
	return not _motion_on or UiMotion.reduced


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
	# Новый тост — последний в стопке, то есть самый нижний.
	item.position = Vector2(LEFT, ENTER_Y)
	item.modulate.a = 0.0
	add_child(item)
	_items.append(item)
	var target := _target_pos(_items.size() - 1)
	if _reduced():
		# Без движения: тост сразу на месте и полностью виден.
		item.position = target
		item.modulate.a = 1.0
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(item, "position", target, ENTER_DUR) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(item, "modulate:a", 1.0, ENTER_DUR)
		# Точка-статус «выпрыгивает» при появлении (draw-only).
		var dot := create_tween()
		dot.tween_property(item, "pop_scale", 1.0, 0.22).from(0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var life := create_tween()
	life.tween_interval(LIFE_DUR)
	life.tween_property(item, "modulate:a", 0.0, EXIT_DUR)
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


## Слот стопки: 44 / 78 / 112 — сверху вниз, свежий тост ниже старых.
func _slot_y(index: int) -> float:
	return TOP + float(index) * (H + GAP)


func _target_pos(index: int) -> Vector2:
	return Vector2(LEFT, _slot_y(index))


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
		if _reduced():
			item.position = _target_pos(i)
			continue
		var tw := create_tween()
		tw.tween_property(item, "position", _target_pos(i), RELAYOUT_DUR) \
			.set_trans(UiMotion.EASE_OUT_POS_TRANS).set_ease(UiMotion.EASE_OUT_POS_EASE)


class ToastItem:
	extends Control
	var txt := ""
	var kind := "info"
	## Pop точки-статуса и стрелки при входе (1.0 — покой).
	var pop_scale := 1.0

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
		# Цветная кромка и мягкая подложка по типу сообщения: тост заметнее,
		# но текст остаётся на бумаге (контраст не меняется).
		var ps := clampf(pop_scale, 0.0, 1.6)
		draw_rect(Rect2(1.0, 1.0, 3.0, maxf(0.0, size.y - 2.0)),
			Theme90.alpha_of(col, 0.55 + 0.35 * clampf(ps - 0.55, 0.0, 1.0)))
		draw_style_box(Theme90.box(Theme90.alpha_of(col, 0.045 * ps),
			Theme90.alpha_of(col, 0.26 * clampf(ps, 0.0, 1.0)), 3, 1),
			r.grow(-1.5))
		# цветная точка-статус вместо тяжёлой иконки; при входе чуть крупнее
		draw_circle(Vector2(15, size.y * 0.5), 4.0 * ps,
			Color(col.r, col.g, col.b, 0.18))
		draw_circle(Vector2(15, size.y * 0.5), 2.4 * ps, col)
		# Стрелка-«далее» справа появляется вместе с точкой.
		var ap := clampf((pop_scale - 0.55) / 0.45, 0.0, 1.0)
		if ap > 0.01:
			Theme90.draw_chevron(self, Vector2(size.x - 12, size.y * 0.5), 2,
				Color(col.r, col.g, col.b, 0.55 * ap), 3.0, 1.2)
		var f := Theme90.ui()
		Theme90.text_vcenter(self, f, Rect2(28, 0, size.x - 38, size.y),
			Theme90.fit(f, txt, 12, size.x - 44), 12, Theme90.INK)
