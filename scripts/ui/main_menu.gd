class_name MainMenu
extends Control
## Главное меню: больше воздуха, бумага, один акцентный блок действий.
## Логотип, слоган, четыре кнопки и короткое «как идёт смена» — без
## служебных подписей, модемов и мелких блоков.
##
## Только UI. Наличие сохранения передаёт интеграция:
##   menu.set_has_save(SaveManager.has_save())

signal new_run
signal continue_run
signal settings
signal about

const W := 1280.0
const H := 720.0

## Preload вместо глобального имени: работает и без прогретого class cache.
const VHS_OVERLAY := preload("res://scripts/ui/vhs_overlay.gd")

const WIN_RECT := Rect2(120, 80, 1040, 560)

var has_save := false
## Тонкий VHS-слой поверх меню. Игра и модалки не фильтруются.
var vhs = null

var _btn_continue: Button90
var _btn_new: Button90
var _btn_settings: Button90
var _btn_about: Button90

static var _card_style: StyleBoxFlat = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_build_vhs()
	resized.connect(_layout)
	_layout()
	queue_redraw()


func set_has_save(value: bool) -> void:
	has_save = value
	if _btn_continue != null:
		_btn_continue.disabled = not has_save
		_btn_continue.tooltip_text = "" if has_save else "Сохранение не найдено"
	queue_redraw()


## Включить/выключить VHS-эффект меню (кодом или из настроек).
func set_vhs_enabled(value: bool) -> void:
	if vhs != null:
		vhs.set_enabled(value)
		queue_redraw()


func is_vhs_enabled() -> bool:
	return vhs != null and vhs.enabled


func _build() -> void:
	_btn_continue = _make_button("Продолжить")
	_btn_continue.disabled = not has_save
	_btn_continue.pressed.connect(func() -> void: continue_run.emit())

	_btn_new = _make_button("Новый забег")
	_btn_new.accent = true
	_btn_new.pressed.connect(func() -> void: new_run.emit())

	_btn_settings = _make_button(_tr("btn.settings", "Настройки"))
	# визуально «активная» кнопка: логику подключит main.gd
	_btn_settings.active = true
	_btn_settings.pressed.connect(func() -> void: settings.emit())

	_btn_about = _make_button("Об игре")
	_btn_about.pressed.connect(func() -> void: about.emit())


## VHS-слой — полноэкранный ColorRect поверх меню. Он фильтрует карточку,
## текст и кнопки, но остаётся внутри MainMenu; модалки — отдельные соседи
## в modal_root, они рисуются поверх и не фильтруются.
func _build_vhs() -> void:
	vhs = VHS_OVERLAY.new()
	vhs.name = "VhsOverlay"
	add_child(vhs)
	vhs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	b.caption_size = 14
	add_child(b)
	return b


func _window() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(W, H)
	return Rect2(WIN_RECT.position + ((s - Vector2(W, H)) * 0.5).round(), WIN_RECT.size)


func _layout() -> void:
	var w := _window()
	var px := w.position.x + 660.0
	var py := w.position.y + 112.0
	var buttons: Array[Button90] = [_btn_continue, _btn_new, _btn_settings, _btn_about]
	for b in buttons:
		if b != null:
			b.position = Vector2(px, py)
			b.size = Vector2(300, 38)
		py += 52.0


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, W, H)
	# 1. Бумага.
	draw_texture_rect(Theme90.dither_texture(), full, true)
	# очень мягкие пастельные пятна — цвет в фоне, не в интерфейсе
	draw_circle(Vector2(full.size.x * 0.93, full.size.y * 0.10), 250.0,
		Color(Theme90.ACCENT_LIGHT.r, Theme90.ACCENT_LIGHT.g, Theme90.ACCENT_LIGHT.b, 0.10))
	draw_circle(Vector2(full.size.x * 0.06, full.size.y * 0.96), 300.0,
		Color(0.96, 0.80, 0.72, 0.09))
	# 2. Карточка, панель, декоративные фигуры и текст. VHS — отдельный
	#    full-rect слой-ребёнок, он фильтрует весь кадр меню в native-res.
	var w := _window()
	_draw_card(w)
	_draw_actions_surface(w)
	_draw_hero_shapes(w)
	_draw_hero_text(w)
	_draw_actions_text(w)


func _panel_rect(w: Rect2) -> Rect2:
	return Rect2(w.position.x + 636.0, w.position.y + 44.0, 348, w.size.y - 88.0)


func _draw_card(w: Rect2) -> void:
	if _card_style == null:
		_card_style = Theme90.box(Theme90.WHITE, Theme90.BORDER, 6, 1,
			Color(0, 0, 0, 0.13))
		_card_style.shadow_size = 10
		_card_style.shadow_offset = Vector2(0, 5)
	draw_style_box(_card_style, w)
	# тонкая цветная полоска в верхнем левом углу
	draw_rect(Rect2(w.position.x + 1, w.position.y + 1, 112, 3), Theme90.ACCENT)


func _draw_hero_shapes(w: Rect2) -> void:
	var x := w.position.x + 56.0
	# акцентная линейка под логотипом
	draw_rect(Rect2(x, w.position.y + 116, 72, 3), Theme90.ACCENT)
	draw_rect(Rect2(x + 76, w.position.y + 116, 6, 3), Theme90.ERROR)

	# шаги смены: круги, волосяные разделители
	var ry := w.position.y + 258.0
	for i in 3:
		draw_circle(Vector2(x + 12, ry + 12), 12.0, Theme90.ACCENT_PALE)
		if i < 2:
			draw_rect(Rect2(x + 34, ry + 35, 478, 1), Theme90.HAIRLINE)
		ry += 48.0

	# стартовая сводка — одна спокойная полоса
	var strip := Rect2(x, w.position.y + 412, 512, 28)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 4, 1), strip)
	draw_circle(Vector2(strip.position.x + 14, strip.get_center().y), 3.0, Theme90.SUCCESS)


func _draw_hero_text(w: Rect2) -> void:
	var f := Theme90.ui()
	var x := w.position.x + 56.0

	Theme90.text(self, f, Vector2(x, w.position.y + 42),
		"ДИСПЕТЧЕР ФАЙЛОВОГО ОБМЕНА · 1997", 10, Theme90.ACCENT)
	Theme90.text(self, Theme90.logo(), Vector2(x - 2, w.position.y + 62),
		"PEAK HOUR 97", 32, Theme90.NAVY)

	var sub := _tr("ui.subtitle", "Час пик. Одна смена. Ни одного свободного места.")
	var lines := Theme90.wrap(f, sub, 16, 520, 2)
	var sy := w.position.y + 132.0
	for line in lines:
		Theme90.text(self, f, Vector2(x, sy), line, 16, Theme90.DARK)
		sy += 21.0

	# короткий блок «как идёт смена»
	var ty := w.position.y + 232.0
	Theme90.text(self, f, Vector2(x, ty), "КАК ИДЁТ СМЕНА", 10, Theme90.SHADE)
	var rows := [
		"Принимайте пакеты и раскладывайте файлы по папкам",
		"Собирайте запросы клиентов и отправляйте в канал",
		"Держите SLA и отражайте атаки на узел",
	]
	var ry := w.position.y + 258.0
	for i in rows.size():
		var circ := Vector2(x + 12, ry + 12)
		var num := str(i + 1)
		var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		Theme90.text(self, f, Vector2(circ.x - nw * 0.5, circ.y - 9), num, 12, Theme90.NAVY)
		Theme90.text(self, f, Vector2(x + 34, ry + 3),
			Theme90.fit(f, rows[i], 15, 478), 15, Theme90.INK)
		ry += 48.0

	var strip := Rect2(x, w.position.y + 412, 512, 28)
	Theme90.text_vcenter(self, f, Rect2(strip.position.x + 26, strip.position.y,
		strip.size.x - 36, strip.size.y),
		"9 часов · $150 на старте · 128 SLA · 4 типа файлов", 11, Theme90.DARK)

	# нижняя строка — только один тихий кредит
	Theme90.text(self, f, Vector2(x, w.position.y + w.size.y - 28),
		"© 1997 «ВЕКТОР-СОФТ» · СБОРКА 12.10.1997", 10, Theme90.SHADE)


func _draw_actions_surface(w: Rect2) -> void:
	var panel := _panel_rect(w)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 5, 1), panel)
	# едва заметный водяной знак в нижней части панели
	Theme90.text(self, Theme90.logo(), Vector2(panel.get_center().x - 44,
		panel.end.y - 126), "97", 44, Color(Theme90.NAVY.r, Theme90.NAVY.g,
		Theme90.NAVY.b, 0.055))

	# вертикальная тонкая линия раздела колонок
	draw_rect(Rect2(w.position.x + 612.0, w.position.y + 44.0, 1,
		w.size.y - 88.0), Theme90.HAIRLINE)


func _draw_actions_text(w: Rect2) -> void:
	var panel := _panel_rect(w)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(panel.position.x + 24, panel.position.y + 22),
		"НОЧНАЯ СМЕНА · УЗЕЛ 7", 10, Theme90.ACCENT)

	var save_text := "СОХРАНЕНИЕ НАЙДЕНО" if has_save else "СОХРАНЕНИЯ ПОКА НЕТ"
	Theme90.text(self, f, Vector2(panel.position.x + 24, panel.position.y + 300),
		save_text, 10, Theme90.SUCCESS if has_save else Theme90.SHADE)

	# подсказка-слоган внизу панели
	var tip := "Начните смену — и держите канал."
	var tw := f.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	Theme90.text(self, f, Vector2(panel.get_center().x - tw * 0.5,
		panel.end.y - 34), tip, 11, Theme90.SHADE)


func _draw_step_icon(index: int, box: Rect2) -> void:
	var x := box.position.x + 5.0
	var y := box.position.y + 5.0
	match index:
		0:
			draw_style_box(Theme90.box(Theme90.WHITE, Theme90.ACCENT_LIGHT, 2, 1),
				Rect2(x, y + 6, 16, 10))
			Theme90.draw_arrow(self, Rect2(x + 4, y, 8, 8), 1, Theme90.ACCENT)
		1:
			Theme90.draw_packet_icon(self, Vector2(x + 1, y + 3), Theme90.ACCENT)
			draw_rect(Rect2(x + 12, y + 8, 3, 5), Theme90.WARN)
		_:
			draw_circle(Vector2(x + 8, y + 8), 8.0, Theme90.SUCCESS)
			draw_rect(Rect2(x + 7, y + 4, 2, 6), Theme90.WHITE)
			draw_rect(Rect2(x + 7, y + 12, 2, 2), Theme90.WHITE)

