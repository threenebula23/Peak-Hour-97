class_name MainMenu
extends Control
## Главное меню PEAK HOUR 97: логотип, четыре пункта, версия и дисклеймер.
##
## Только UI. Наличие сохранения передаёт интеграция:
##   menu.set_has_save(SaveManager.has_save())

signal new_run
signal continue_run
signal settings
signal about

const W := 1280.0
const H := 720.0
const TITLE_H := 20.0

const WIN_RECT := Rect2(140, 50, 1000, 620)

var has_save := false

var _btn_continue: Button90
var _btn_new: Button90
var _btn_settings: Button90
var _btn_about: Button90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	queue_redraw()


func set_has_save(value: bool) -> void:
	has_save = value
	if _btn_continue != null:
		_btn_continue.disabled = not has_save
		_btn_continue.tooltip_text = "" if has_save else "Сохранение не найдено"
	queue_redraw()


func _build() -> void:
	_btn_continue = _make_button("Продолжить")
	_btn_continue.disabled = not has_save
	_btn_continue.pressed.connect(func() -> void: continue_run.emit())

	_btn_new = _make_button("Новый забег")
	_btn_new.accent = true
	_btn_new.pressed.connect(func() -> void: new_run.emit())

	_btn_settings = _make_button(_tr("btn.settings", "Настройки"))
	_btn_settings.pressed.connect(func() -> void: settings.emit())

	_btn_about = _make_button("Об игре")
	_btn_about.pressed.connect(func() -> void: about.emit())


func _tr(key: String, fallback: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("has_string") and data.has_string(key):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _make_button(caption: String) -> Button90:
	var b := Button90.new()
	b.caption = caption
	b.caption_size = Theme90.FS_BODY
	add_child(b)
	return b


func _window() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(W, H)
	return Rect2(WIN_RECT.position + ((s - Vector2(W, H)) * 0.5).round(), WIN_RECT.size)


func _layout() -> void:
	var w := _window()
	var x := w.position.x + 646.0
	var y := w.position.y + 96.0
	for b in [_btn_continue, _btn_new, _btn_settings, _btn_about]:
		if b != null:
			b.position = Vector2(x, y)
			b.size = Vector2(308, 24)
		y += 44.0


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, W, H)
	draw_texture_rect(Theme90.dither_texture(), full, true)
	draw_rect(Rect2(0, 0, full.size.x, 1), Theme90.SHADE)
	draw_rect(Rect2(0, 0, 1, full.size.y), Theme90.SHADE)
	draw_rect(Rect2(full.size.x - 1, 0, 1, full.size.y), Theme90.FACE_HI)
	draw_rect(Rect2(0, full.size.y - 1, full.size.x, 1), Theme90.FACE_HI)

	var w := _window()
	_draw_window(w)

	# подпись за пределами окна
	var f := Theme90.ui()
	Theme90.text(self, f, w.position + Vector2(4, w.size.y + 20),
		"ЧАС ПИК · НОЧНАЯ СМЕНА · ОПЕРАТОР УЗЛА 7", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, f, Vector2(w.position.x + 4, w.position.y + w.size.y + 20),
		"ЛИЦЕНЗИЯ НА ОДНО РАБОЧЕЕ МЕСТО", Theme90.FS_MICRO, Theme90.DARK,
		w.size.x - 8, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_window(w: Rect2) -> void:
	Theme90.draw_bevel(self, w, false, Theme90.BEVEL, Theme90.FACE)
	var inner := w.grow(-Theme90.BEVEL)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), Theme90.FACE_HI)
	draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), Theme90.FACE_HI)

	var tr := Rect2(w.position + Vector2(2, 2), Vector2(w.size.x - 4.0, TITLE_H))
	Theme90.draw_vgrad(self, tr, Theme90.NAVY, Theme90.NAVY_DEEP)
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, 1)), Color(0.0, 0.0, 0.372549))
	draw_rect(Rect2(tr.position.x, tr.end.y - 1, tr.size.x, 1), Theme90.DARK)
	draw_rect(Rect2(tr.position.x, tr.end.y - 2, tr.size.x, 1), Theme90.ACCENT)

	# дискета
	var ix := tr.position.x + 5.0
	var iy := tr.position.y + 3.0
	draw_rect(Rect2(ix, iy, 14, 14), Theme90.ACCENT_PALE)
	draw_rect(Rect2(ix, iy, 14, 14), Theme90.WHITE, false, 1.0)
	draw_rect(Rect2(ix + 3, iy + 1, 7, 5), Theme90.NAVY)
	draw_rect(Rect2(ix + 2, iy + 8, 10, 5), Theme90.ACCENT)
	draw_rect(Rect2(ix + 4, iy + 9, 6, 1), Theme90.ACCENT_PALE)

	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(tr.position.x + 24, tr.position.y, 300, TITLE_H),
		"ГЛАВНОЕ МЕНЮ", Theme90.FS_BODY, Theme90.WHITE)
	Theme90.text_vcenter(self, f, Rect2(tr.position.x, tr.position.y, tr.size.x - 94, TITLE_H),
		"УЗЕЛ 7 · СМЕНА 3 · 03:42", Theme90.FS_MICRO, Theme90.ACCENT_LIGHT,
		-1, HORIZONTAL_ALIGNMENT_RIGHT)

	# неактивные кнопки окна
	for i in 3:
		var br := Rect2(tr.end.x - 6.0 - 46.0 + i * 16.0, tr.position.y + 4.0, 14.0, 12.0)
		Theme90.draw_bevel(self, br, false, 1.0, Theme90.FACE)
		var glyph := Color(0.55, 0.55, 0.55)
		match i:
			0:
				draw_rect(Rect2(br.position.x + 3, br.position.y + br.size.y - 4, 8, 1), glyph)
			1:
				draw_rect(Rect2(br.position.x + 3, br.position.y + 2, 8, 8), glyph, false, 1.0)
				draw_rect(Rect2(br.position.x + 3, br.position.y + 2, 8, 2), glyph)
			_:
				draw_line(Vector2(br.position.x + 4, br.position.y + 3),
					Vector2(br.position.x + 9, br.position.y + 8), glyph, 1.0)
				draw_line(Vector2(br.position.x + 9, br.position.y + 3),
					Vector2(br.position.x + 4, br.position.y + 8), glyph, 1.0)

	_draw_hero(w)
	_draw_menu(w)
	_draw_footer(w)


func _draw_hero(w: Rect2) -> void:
	var f := Theme90.ui()
	# значок издания
	var chip := Rect2(w.position + Vector2(40, 44), Vector2(268, 16))
	Theme90.draw_bevel(self, chip, true, 1.0, Theme90.FACE)
	Theme90.text_vcenter(self, f, chip, "СПРАВОЧНИК ОПЕРАТОРА · ИЗДАНИЕ 1997",
		Theme90.FS_MICRO, Theme90.DARK, -1, HORIZONTAL_ALIGNMENT_CENTER)

	# логотип
	Theme90.text(self, Theme90.logo(), w.position + Vector2(40, 84), "PEAK HOUR 97",
		40, Theme90.NAVY)
	draw_rect(Rect2(w.position + Vector2(40, 134), Vector2(196, 6)), Theme90.NAVY)
	draw_rect(Rect2(w.position + Vector2(242, 134), Vector2(6, 6)), Theme90.ERROR)

	# подзаголовок
	var sub := _tr("ui.subtitle", "Час пик. Одна смена. Ни одного свободного места.")
	var lines := Theme90.wrap(f, sub, 16, 520, 2)
	var sy := w.position.y + 154.0
	for line in lines:
		Theme90.text(self, f, Vector2(w.position.x + 40, sy), line, 16, Theme90.DARK)
		sy += 20.0

	# «как идёт смена»
	var panel := Rect2(w.position + Vector2(40, 214), Vector2(540, 210))
	Theme90.draw_bevel(self, panel, true, Theme90.BEVEL, Theme90.FACE)
	var pt := panel.position
	Theme90.text(self, f, pt + Vector2(10, 7), "КАК ИДЁТ СМЕНА", Theme90.FS_MICRO, Theme90.NAVY)
	draw_rect(Rect2(pt.x + 8, pt.y + 23, panel.size.x - 16, 1), Theme90.SHADE)
	draw_rect(Rect2(pt.x + 8, pt.y + 24, panel.size.x - 16, 1), Theme90.LIGHT)

	var rows := [
		"Принимайте пакеты и раскладывайте файлы по папкам",
		"Собирайте запросы клиентов и отправляйте их в канал",
		"Держите SLA и отражайте атаки на узел",
	]
	var ry := pt.y + 40.0
	for i in rows.size():
		var box := Rect2(pt.x + 14, ry, 26, 26)
		Theme90.draw_bevel(self, box, true, 1.0, Theme90.FACE)
		_draw_step_icon(i, box)
		Theme90.text(self, f, Vector2(pt.x + 52, ry + 6),
			Theme90.fit(f, rows[i], Theme90.FS_BODY, 470), Theme90.FS_BODY, Theme90.INK)
		if i < rows.size() - 1:
			draw_rect(Rect2(pt.x + 14, ry + 34, panel.size.x - 28, 1), Theme90.FACE_HI)
		ry += 50.0

	# стартовая сводка
	var strip := Rect2(w.position + Vector2(40, 442), Vector2(540, 26))
	Theme90.draw_bevel(self, strip, false, 1.0, Theme90.FACE_HI)
	Theme90.text_vcenter(self, f, strip, "9 ЧАСОВ · 150 $ НА СТАРТЕ · 200 SLA · 4 ТИПА ФАЙЛОВ",
		Theme90.FS_MICRO, Theme90.DARK, -1, HORIZONTAL_ALIGNMENT_CENTER)

	# строка «модема» — просто антураж
	var modem := Rect2(w.position + Vector2(40, 488), Vector2(540, 44))
	Theme90.draw_bevel(self, modem, true, 2.0, Theme90.FACE)
	var led_colors := [Theme90.SUCCESS, Theme90.WARN, Theme90.SHADE]
	for i in 3:
		var led := Rect2(modem.position + Vector2(12 + i * 13, 18), Vector2(9, 9))
		Theme90.draw_bevel(self, led, true, 1.0, Theme90.DARK)
		draw_rect(led.grow(-2), led_colors[i])
	Theme90.text(self, f, modem.position + Vector2(62, 10), "МОДЕМ 28.8K", Theme90.FS_MICRO,
		Theme90.INK)
	Theme90.text(self, f, modem.position + Vector2(62, 24), "ЛИНИЯ СВОБОДНА · ДИСК C: 412 МБ",
		Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, f, modem.position + Vector2(modem.size.x - 120, 10), "ГОТОВ",
		Theme90.FS_MICRO, Theme90.SUCCESS, 112, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_lamp(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	var bulb := Theme90.WARN
	# лампа: широкий низ, узкий верх, патрон
	draw_rect(Rect2(x + 12, y + 10, 20, 4), bulb)
	draw_rect(Rect2(x + 8, y + 14, 28, 12), bulb)
	draw_rect(Rect2(x + 12, y + 26, 20, 4), bulb)
	draw_rect(Rect2(x + 10, y + 14, 4, 12), bulb)
	draw_rect(Rect2(x + 30, y + 14, 4, 12), bulb)
	draw_rect(Rect2(x + 10, y + 10, 4, 4), bulb)
	draw_rect(Rect2(x + 30, y + 10, 4, 4), bulb)
	draw_rect(Rect2(x + 12, y + 16, 5, 8), Theme90.WHITE)
	draw_rect(Rect2(x + 13, y + 30, 18, 4), Theme90.SHADE)
	draw_rect(Rect2(x + 15, y + 34, 14, 3), Theme90.DARK)
	draw_rect(Rect2(x + 17, y + 37, 10, 2), Theme90.DARK)
	# лучи
	for i in 3:
		draw_rect(Rect2(x + 7 + i * 4, y + 2 - i, 2, 3), bulb)
		draw_rect(Rect2(x + 35 - i * 4, y + 2 - i, 2, 3), bulb)
	draw_rect(Rect2(x + 3, y + 18, 3, 2), bulb)
	draw_rect(Rect2(x + 38, y + 18, 3, 2), bulb)


func _draw_step_icon(index: int, box: Rect2) -> void:
	var x := box.position.x + 5.0
	var y := box.position.y + 5.0
	var c := Theme90.NAVY
	match index:
		0:
			draw_rect(Rect2(x, y + 6, 16, 10), Theme90.WHITE)
			draw_rect(Rect2(x, y + 6, 16, 10), c, false, 1.0)
			Theme90.draw_arrow(self, Rect2(x + 4, y, 8, 8), 1, c)
		1:
			Theme90.draw_packet_icon(self, Vector2(x + 1, y + 3), c)
			draw_rect(Rect2(x + 12, y + 8, 3, 5), Theme90.WARN)
		_:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 8, y), Vector2(x + 16, y + 4), Vector2(x + 15, y + 11),
				Vector2(x + 8, y + 16), Vector2(x + 1, y + 11), Vector2(x, y + 4)]), c)
			draw_rect(Rect2(x + 7, y + 4, 2, 6), Theme90.WHITE)
			draw_rect(Rect2(x + 7, y + 12, 2, 2), Theme90.WHITE)


func _draw_menu(w: Rect2) -> void:
	var f := Theme90.ui()
	var well := Rect2(w.position + Vector2(628, 30), Vector2(344, 482))
	Theme90.draw_bevel(self, well, true, Theme90.BEVEL, Theme90.FACE)
	var wp := well.position

	Theme90.text(self, f, wp + Vector2(16, 8), "МЕНЮ", Theme90.FS_BODY, Theme90.NAVY)
	draw_rect(Rect2(wp.x + 8, wp.y + 25, well.size.x - 16, 1), Theme90.SHADE)
	draw_rect(Rect2(wp.x + 8, wp.y + 26, well.size.x - 16, 1), Theme90.LIGHT)

	# состояние сохранения
	var save_text := "СОХРАНЕНИЕ: ЕСТЬ · ЧАС 3" if has_save else "СОХРАНЕНИЕ НЕ НАЙДЕНО"
	Theme90.text(self, f, wp + Vector2(18, 38), save_text, Theme90.FS_MICRO,
		Theme90.SUCCESS if has_save else Theme90.DARK)

	# советы
	var tip := Rect2(wp + Vector2(18, 278), Vector2(well.size.x - 36, 152))
	Theme90.draw_bevel(self, tip, true, 1.0, Theme90.FACE)
	Theme90.text(self, f, tip.position + Vector2(8, 6), "СОВЕТ ДНЯ", Theme90.FS_MICRO,
		Theme90.NAVY)
	draw_rect(Rect2(tip.position.x + 6, tip.position.y + 22, tip.size.x - 12, 1), Theme90.SHADE)
	var tip_lines := Theme90.wrap(f,
		"Улучшения окупаются к часу 8–9. Берите слоты и буфер заранее: к вечеру канал уже не резиновый.",
		Theme90.FS_BODY, 196, 6)
	var ty := tip.position.y + 32.0
	for line in tip_lines:
		Theme90.text(self, f, Vector2(tip.position.x + 8, ty), line, Theme90.FS_BODY, Theme90.DARK)
		ty += 16.0
	_draw_lamp(Rect2(tip.position + Vector2(232, 44), Vector2(44, 56)))

	# версия
	var vy := wp.y + 456.0
	Theme90.text(self, f, Vector2(wp.x + 18, vy), "ВЕРСИЯ 0.1.0", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, f, Vector2(wp.x + 18, vy + 14), "СБОРКА 12.10.1997", Theme90.FS_MICRO,
		Theme90.DARK)
	Theme90.text(self, f, Vector2(wp.x + 18, vy + 28), "© 1997 «ВЕКТОР-СОФТ»", Theme90.FS_MICRO,
		Theme90.SHADE)


func _draw_footer(w: Rect2) -> void:
	var f := Theme90.ui()
	var y := w.position.y + 550.0
	draw_rect(Rect2(w.position.x + 12, y, w.size.x - 24, 1), Theme90.SHADE)
	draw_rect(Rect2(w.position.x + 12, y + 1, w.size.x - 24, 1), Theme90.FACE_HI)

	Theme90.text(self, f, Vector2(w.position.x + 16, y + 10),
		"PEAK HOUR 97 · ДИСПЕТЧЕР ФАЙЛОВОГО ОБМЕНА", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, f, Vector2(w.position.x + 16, y + 10),
		"СОБРАНО НА GODOT · 1280×720", Theme90.FS_MICRO, Theme90.DARK,
		w.size.x - 32, HORIZONTAL_ALIGNMENT_RIGHT)
	Theme90.text(self, f, Vector2(w.position.x + 16, y + 28),
		"Все совпадения случайны. Узел 7 и фирма «Вектор» вымышлены.",
		Theme90.FS_MICRO, Theme90.SHADE)
