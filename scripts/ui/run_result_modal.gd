class_name RunResultModal
extends Control
## Модальное окно «ЗАБЕГ ОКОНЧЕН»: победа или поражение, счёт и сводка.
##
##   run_result.open({
##       "won": true, "reason": "Смена отработана. Все 9 часов.",
##       "score": 14820, "best": 15100, "hours": 9, "hours_total": 9,
##       "money": 2380, "sla": 96, "sla_max": 200,
##   })

signal new_run
signal to_menu
signal closed

const W := 620.0
const H := 336.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

var _data: Dictionary = {}
var _btn_new: Button90
var _btn_menu: Button90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_btn_new = Button90.new()
	_btn_new.caption = "Новый забег"
	_btn_new.accent = true
	add_child(_btn_new)
	_btn_new.pressed.connect(_on_new)

	_btn_menu = Button90.new()
	_btn_menu.caption = _tr("btn.to_menu", "В меню")
	add_child(_btn_menu)
	_btn_menu.pressed.connect(_on_menu)

	resized.connect(_layout)
	_layout()
	visible = false


func open(data: Dictionary = {}) -> void:
	_data = data.duplicate(true)
	visible = true
	_layout()
	queue_redraw()
	if _btn_new != null:
		_btn_new.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_new() -> void:
	if not visible:
		return
	visible = false
	new_run.emit()


func _on_menu() -> void:
	if not visible:
		return
	visible = false
	to_menu.emit()


func _tr(key: String, fallback: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("has_string") and data.has_string(key):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _value(key: String, fallback: int) -> int:
	return int(_data.get(key, fallback))


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	if _btn_new != null:
		_btn_new.position = r.position + Vector2(346, 286)
		_btn_new.size = Vector2(148, 24)
	if _btn_menu != null:
		_btn_menu.position = r.position + Vector2(502, 286)
		_btn_menu.size = Vector2(104, 24)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, 1280, 720)
	draw_rect(full, DIM)
	var r := _window_rect()
	var won := bool(_data.get("won", true))
	_draw_frame(r, won)

	var f := Theme90.ui()
	var band := Rect2(r.position + Vector2(14, 28), Vector2(r.size.x - 28, 72))
	var band_color := Theme90.NAVY if won else Color(0.36, 0.07, 0.07)
	Theme90.draw_bevel(self, band, false, 2.0, band_color)
	draw_rect(Rect2(band.position + Vector2(2, 2), Vector2(band.size.x - 4, 1)),
		Color(1, 1, 1, 0.28))

	Theme90.text(self, Theme90.logo(), band.position + Vector2(16, 9),
		"ПОБЕДА" if won else "ПОРАЖЕНИЕ", 24,
		Theme90.WHITE if won else Color(1.0, 0.80, 0.80))
	var reason := str(_data.get("reason", ""))
	if reason.is_empty():
		if won:
			reason = _tr("results.run.won", "Смена отработана. Победа!")
		else:
			reason = _tr("results.run.lost", "Смена сорвалась. Поражение.")
	Theme90.text(self, f, band.position + Vector2(16, 50),
		Theme90.fit(f, reason, Theme90.FS_MICRO, band.size.x - 120), Theme90.FS_MICRO,
		Color(0.86, 0.90, 1.0) if won else Color(1.0, 0.86, 0.86))

	if won:
		_draw_cup(Rect2(band.position.x + band.size.x - 54, band.position.y + 20, 34, 34))
	else:
		_draw_broken(Rect2(band.position.x + band.size.x - 54, band.position.y + 20, 34, 34))

	# счёт
	var score_box := Rect2(r.position + Vector2(14, 108), Vector2(r.size.x - 28, 68))
	Theme90.draw_bevel(self, score_box, true, 2.0, Theme90.FACE)
	Theme90.text(self, f, score_box.position + Vector2(14, 4), "СЧЁТ", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, Theme90.logo(), score_box.position + Vector2(14, 20),
		_fmt(_value("score", 0)), 28, Theme90.INK)

	Theme90.text_vcenter(self, f, Rect2(score_box.position.x, score_box.position.y + 6,
		score_box.size.x - 14, 12), "ЛУЧШИЙ", Theme90.FS_MICRO, Theme90.DARK,
		-1, HORIZONTAL_ALIGNMENT_RIGHT)
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(score_box.position.x,
		score_box.position.y + 22, score_box.size.x - 14, 18), _fmt(_value("best", 0)),
		14, Theme90.DARK, -1, HORIZONTAL_ALIGNMENT_RIGHT)

	# три ячейки сводки
	var total := maxi(1, _value("hours_total", 9))
	_draw_cell(Rect2(r.position + Vector2(14, 184), Vector2(188, 68)), "ЧАСЫ",
		"%d / %d" % [_value("hours", 0), total])
	_draw_cell(Rect2(r.position + Vector2(216, 184), Vector2(188, 68)), "ДЕНЬГИ",
		_fmt(_value("money", 0)) + " $")
	_draw_cell(Rect2(r.position + Vector2(418, 184), Vector2(188, 68)), "SLA",
		"%d / %d" % [_value("sla", 0), maxi(1, _value("sla_max", 200))])

	Theme90.text(self, f, Vector2(r.position.x + 16, r.position.y + 262),
		"ВЫБЕРИТЕ, ЧТО ДЕЛАТЬ ДАЛЬШЕ · ESC — ЗАКРЫТЬ", Theme90.FS_MICRO, Theme90.DARK)


func _draw_frame(r: Rect2, won: bool) -> void:
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.FACE)
	var inner := r.grow(-Theme90.BEVEL)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), Theme90.FACE_HI)
	draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), Theme90.FACE_HI)

	var tr := Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4.0, TITLE_H))
	Theme90.draw_vgrad(self, tr, Theme90.NAVY, Theme90.NAVY_DEEP)
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, 1)), Color(0.0, 0.0, 0.372549))
	draw_rect(Rect2(tr.position.x, tr.end.y - 1, tr.size.x, 1), Theme90.DARK)
	draw_rect(Rect2(tr.position.x, tr.end.y - 2, tr.size.x, 1),
		Theme90.ACCENT if won else Theme90.ERROR)

	# флажок
	var fx := tr.position.x + 5.0
	var fy := tr.position.y + 4.0
	draw_rect(Rect2(fx, fy, 1, 12), Theme90.WHITE)
	draw_rect(Rect2(fx + 1, fy, 8, 6), Theme90.ACCENT_LIGHT)
	draw_rect(Rect2(fx + 1, fy, 8, 1), Theme90.WHITE)

	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(tr.position.x + 22, tr.position.y, 240, TITLE_H),
		"ЗАБЕГ ОКОНЧЕН", Theme90.FS_BODY, Theme90.WHITE)
	Theme90.text_vcenter(self, f, Rect2(tr.position.x, tr.position.y, tr.size.x - 34, TITLE_H),
		"PEAK HOUR 97", Theme90.FS_MICRO, Theme90.ACCENT_LIGHT,
		-1, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_cell(r: Rect2, label: String, value: String) -> void:
	Theme90.draw_bevel(self, r, true, 2.0, Theme90.FACE)
	var f := Theme90.ui()
	Theme90.text(self, f, r.position + Vector2(10, 9), label, Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, Theme90.logo(), r.position + Vector2(10, 28), value, 16, Theme90.INK)


func _draw_cup(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	var gold := Theme90.WARN
	draw_rect(Rect2(x + 6, y + 2, 16, 10), gold)
	draw_rect(Rect2(x + 6, y + 2, 16, 2), gold.lightened(0.35))
	draw_rect(Rect2(x + 2, y + 4, 4, 2), gold)
	draw_rect(Rect2(x + 2, y + 4, 1, 5), gold)
	draw_rect(Rect2(x + 22, y + 4, 4, 2), gold)
	draw_rect(Rect2(x + 25, y + 4, 1, 5), gold)
	draw_rect(Rect2(x + 2, y + 9, 5, 1), gold)
	draw_rect(Rect2(x + 22, y + 9, 5, 1), gold)
	draw_rect(Rect2(x + 12, y + 12, 4, 8), gold)
	draw_rect(Rect2(x + 8, y + 20, 12, 3), gold)
	draw_rect(Rect2(x + 7, y + 23, 14, 2), gold.darkened(0.25))
	draw_rect(Rect2(x + 9, y + 4, 2, 6), Theme90.WHITE)


func _draw_broken(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	var red := Color(0.85, 0.18, 0.18)
	# треснувшая плашка счёта
	draw_rect(Rect2(x + 4, y + 4, 24, 26), red)
	draw_rect(Rect2(x + 4, y + 4, 24, 2), red.lightened(0.35))
	draw_rect(Rect2(x + 4, y + 4, 2, 26), red.lightened(0.2))
	draw_line(Vector2(x + 9, y + 2), Vector2(x + 14, y + 12), Theme90.WHITE, 1.0)
	draw_line(Vector2(x + 14, y + 12), Vector2(x + 10, y + 18), Theme90.WHITE, 1.0)
	draw_line(Vector2(x + 10, y + 18), Vector2(x + 16, y + 30), Theme90.WHITE, 1.0)
	draw_line(Vector2(x + 10, y + 18), Vector2(x + 4, y + 22), Theme90.WHITE, 1.0)
	draw_line(Vector2(x + 14, y + 12), Vector2(x + 20, y + 7), Theme90.WHITE, 1.0)


func _fmt(value: int) -> String:
	var neg := value < 0
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if neg else "") + out
