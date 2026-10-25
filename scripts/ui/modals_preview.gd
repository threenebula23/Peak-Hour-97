extends Control
## Дев-сцена: предпросмотр всех модальных окон на фейковом игровом экране.
##
##   godot --path . --script scripts/ui/dev_capture.gd -- \
##       --scene=res://scenes/ui/ModalsPreview.tscn --out=/tmp/modals.png --modal=shop
##
## --modal: shop | pause | settings | hour | run_win | run_lose | menu | confirm | grid
## Клавиши: 1–9 — окна, ← → — переключение, G — сетка.

const SHOP := preload("res://scripts/ui/shop_modal.gd")
const PAUSE := preload("res://scripts/ui/pause_modal.gd")
const SETTINGS := preload("res://scripts/ui/settings_modal.gd")
const HOUR := preload("res://scripts/ui/hour_result_modal.gd")
const RUN := preload("res://scripts/ui/run_result_modal.gd")
const MENU := preload("res://scripts/ui/main_menu.gd")
const CONFIRM := preload("res://scripts/ui/confirm_modal.gd")
const MASCOT_PREVIEW := preload("res://scripts/ui/tutorial_mascot_preview.gd")

const W := 1280.0
const H := 720.0
const TOOLBAR_H := 34.0
const GRID_SCALE := 0.285
const CELL := Vector2(1280.0 * GRID_SCALE, 720.0 * GRID_SCALE)
const GRID_X := 79.0
const GRID_Y := 50.0
const GRID_GAP_X := 14.0
const GRID_GAP_Y := 18.0

const TABS := ["МАГАЗИН", "ПАУЗА", "НАСТРОЙКИ", "ИТОГИ ЧАСА", "ПОБЕДА", "ПОРАЖЕНИЕ",
	"МЕНЮ", "ВОПРОС", "МАСКОТ", "СЕТКА"]
const ARG_NAMES := ["shop", "pause", "settings", "hour", "run_win", "run_lose", "menu",
	"confirm", "mascot", "grid"]

var _stage: Control
var _scrim: ColorRect
var _overlay: OverlayLayer
var _toolbar: Panel90
var _signal_label: Label

var _modals: Array[Control] = []
var _tab_buttons: Array[Button90] = []
var _active := 0
var _grid_mode := false

var _shop
var _pause
var _settings
var _hour
var _run_win
var _run_lose
var _menu
var _confirm
var _mascot_preview

var _money := 280
var _levels := {"shop_slot3": 1, "shop_buffer": 1, "shop_timer": 2}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	var start := _arg_start()
	_show_tab(start)


# --------------------------------------------------------------------------
# Сборка
# --------------------------------------------------------------------------

func _build() -> void:
	var desk := FakeDesk.new()
	desk.name = "FakeDesk"
	add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_scrim = ColorRect.new()
	_scrim.name = "GridScrim"
	_scrim.color = Color(0.086, 0.098, 0.129)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.visible = false
	add_child(_scrim)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_stage = Control.new()
	_stage.name = "Stage"
	add_child(_stage)
	_stage.position = Vector2.ZERO
	_stage.size = Vector2(W, H)

	_build_modals()

	_overlay = OverlayLayer.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 6
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.position = Vector2.ZERO
	_overlay.size = Vector2(W, H)

	_build_toolbar()


func _build_modals() -> void:
	_shop = SHOP.new()
	_shop.name = "ShopModal"
	_add_modal(_shop)

	_pause = PAUSE.new()
	_pause.name = "PauseModal"
	_add_modal(_pause)

	_settings = SETTINGS.new()
	_settings.name = "SettingsModal"
	_add_modal(_settings)

	_hour = HOUR.new()
	_hour.name = "HourResultModal"
	_add_modal(_hour)

	_run_win = RUN.new()
	_run_win.name = "RunResultVictory"
	_add_modal(_run_win)

	_run_lose = RUN.new()
	_run_lose.name = "RunResultDefeat"
	_add_modal(_run_lose)

	_menu = MENU.new()
	_menu.name = "MainMenu"
	_add_modal(_menu)

	_confirm = CONFIRM.new()
	_confirm.name = "ConfirmModal"
	_add_modal(_confirm)

	_mascot_preview = MASCOT_PREVIEW.new()
	_mascot_preview.name = "MascotPreview"
	_add_modal(_mascot_preview)

	# фейковые данные
	_shop.open(_money, _levels)
	_pause.open()
	_settings.open({"sfx": 70, "music": 55, "calm_bg": true, "fullscreen": false})
	_hour.open({
		"hour": 3, "hours_total": 9, "earned": 1240, "done": 8, "failed": 2,
		"reflected": 3, "missed": 1, "sla_delta": -12, "sla": 168, "sla_max": 200,
	})
	_run_win.open({
		"won": true, "reason": "Смена отработана. Все 9 часов закрыты.",
		"score": 14820, "best": 15100, "hours": 9, "hours_total": 9,
		"money": 2380, "sla": 96, "sla_max": 200,
	})
	_run_lose.open({
		"won": false, "reason": "SLA упал до нуля на шестом часе.",
		"score": 6310, "best": 15100, "hours": 5, "hours_total": 9,
		"money": 940, "sla": 0, "sla_max": 200,
	})
	_menu.set_has_save(false)
	_confirm.ask("Выйти в главное меню?", "Прогресс текущей смены не сохранится.",
		"Да", "Нет", true)

	# сигналы
	_shop.buy_requested.connect(_on_shop_buy)
	_shop.closed.connect(func() -> void: _status("МАГАЗИН ЗАКРЫТ"))
	_pause.resumed.connect(func() -> void: _status("ПАУЗА · ПРОДОЛЖИТЬ"))
	_pause.settings_requested.connect(func() -> void: _status("ПАУЗА · НАСТРОЙКИ"))
	_pause.menu_requested.connect(func() -> void: _status("ПАУЗА · В ГЛАВНОЕ МЕНЮ"))
	_pause.closed.connect(func() -> void: _status("ПАУЗА ЗАКРЫТА"))
	_settings.settings_changed.connect(_on_settings_changed)
	_settings.closed.connect(func() -> void: _status("НАСТРОЙКИ ЗАКРЫТЫ"))
	_hour.next_pressed.connect(func() -> void:
		_status("ИТОГИ ЧАСА · ДАЛЕЕ")
		_hour.open({
			"hour": 4, "hours_total": 9, "earned": 1580, "done": 11, "failed": 1,
			"reflected": 4, "missed": 0, "sla_delta": 9, "sla": 177, "sla_max": 200,
		}))
	_run_win.new_run.connect(func() -> void: _status("ЗАБЕГ · НОВЫЙ ЗАБЕГ"))
	_run_win.to_menu.connect(func() -> void: _status("ЗАБЕГ · В МЕНЮ"))
	_run_lose.new_run.connect(func() -> void: _status("ЗАБЕГ · НОВЫЙ ЗАБЕГ"))
	_run_lose.to_menu.connect(func() -> void: _status("ЗАБЕГ · В МЕНЮ"))
	_menu.new_run.connect(func() -> void: _status("МЕНЮ · НОВЫЙ ЗАБЕГ"))
	_menu.continue_run.connect(func() -> void: _status("МЕНЮ · ПРОДОЛЖИТЬ"))
	_menu.settings.connect(func() -> void: _status("МЕНЮ · НАСТРОЙКИ"))
	_menu.about.connect(func() -> void: _status("МЕНЮ · ОБ ИГРЕ"))
	_confirm.answered.connect(func(yes: bool) -> void:
		_status("ОТВЕТ: " + ("ДА" if yes else "НЕТ")))


func _add_modal(m: Control) -> void:
	_stage.add_child(m)
	# фиксированный размер: в сетке масштабируем сами
	m.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	m.size = Vector2(W, H)
	m.position = Vector2.ZERO
	_modals.append(m)


func _build_toolbar() -> void:
	_toolbar = Panel90.new()
	_toolbar.name = "Toolbar"
	_toolbar.kind = Panel90.Kind.FLAT
	_toolbar.z_index = 10
	add_child(_toolbar)
	_toolbar.position = Vector2.ZERO
	_toolbar.size = Vector2(W, TOOLBAR_H)

	var sep := ColorRect.new()
	sep.color = Theme90.SHADE
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.position = Vector2(0, TOOLBAR_H - 1)
	sep.size = Vector2(W, 1)
	_toolbar.add_child(sep)

	var caption := Label.new()
	caption.text = "ПРЕДПРОСМОТР"
	caption.add_theme_font_override("font", Theme90.ui(700))
	caption.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
	caption.add_theme_color_override("font_color", Theme90.DARK)
	caption.position = Vector2(8, 11)
	caption.size = Vector2(80, 12)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toolbar.add_child(caption)

	var f := Theme90.ui()
	var sep_x := 92.0
	var vline := ColorRect.new()
	vline.color = Theme90.SHADE
	vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vline.position = Vector2(sep_x, 5)
	vline.size = Vector2(1, 24)
	_toolbar.add_child(vline)

	var x := 100.0
	for i in TABS.size():
		var b := Button90.new()
		b.flat_style = true
		b.caption = TABS[i]
		b.caption_size = Theme90.FS_MICRO
		b.size = Vector2(f.get_string_size(TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
			Theme90.FS_MICRO).x + 18.0, 24)
		b.position = Vector2(x, 5)
		b.tooltip_text = "Клавиша %d" % (i + 1)
		b.pressed.connect(_show_tab.bind(i))
		_toolbar.add_child(b)
		_tab_buttons.append(b)
		x += b.size.x + 4.0

	_signal_label = Label.new()
	_signal_label.text = "СИГНАЛ: —"
	_signal_label.add_theme_font_override("font", Theme90.ui(700))
	_signal_label.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
	_signal_label.add_theme_color_override("font_color", Theme90.NAVY)
	_signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_signal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_signal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signal_label.position = Vector2(770, 5)
	_signal_label.size = Vector2(330, 24)
	_toolbar.add_child(_signal_label)

	var hint := Label.new()
	hint.text = "1–9 · ← → · G"
	hint.add_theme_font_override("font", Theme90.ui(700))
	hint.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
	hint.add_theme_color_override("font_color", Theme90.DARK)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.position = Vector2(1110, 5)
	hint.size = Vector2(160, 24)
	_toolbar.add_child(hint)


# --------------------------------------------------------------------------
# Переключение
# --------------------------------------------------------------------------

func _arg_start() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--modal="):
			var key := a.substr(8)
			var idx := ARG_NAMES.find(key)
			if idx >= 0:
				return idx
	return 0


func _show_tab(index: int) -> void:
	_active = clampi(index, 0, TABS.size() - 1)
	_grid_mode = _active == TABS.size() - 1
	_scrim.visible = _grid_mode
	for i in _tab_buttons.size():
		_tab_buttons[i].active = i == _active
		_tab_buttons[i].queue_redraw()

	if _grid_mode:
		_overlay.cells.clear()
		for i in _modals.size():
			var m := _modals[i]
			if m == _mascot_preview:
				m.visible = false
				continue
			var cell := _grid_cell(i)
			m.visible = true
			m.scale = Vector2(GRID_SCALE, GRID_SCALE)
			m.position = cell
			_overlay.cells.append({"rect": Rect2(cell, CELL), "title": _cell_title(i)})
	else:
		_overlay.cells.clear()
		for i in _modals.size():
			var m := _modals[i]
			m.scale = Vector2.ONE
			m.position = Vector2.ZERO
			m.size = Vector2(W, H)
			m.visible = i == _active
	_overlay.queue_redraw()
	_status("—")


func _grid_cell(i: int) -> Vector2:
	var col := i % 3
	var row := i / 3
	return Vector2(GRID_X + col * (CELL.x + GRID_GAP_X),
		GRID_Y + row * (CELL.y + GRID_GAP_Y))


func _cell_title(i: int) -> String:
	var titles := ["МАГАЗИН", "ПАУЗА", "НАСТРОЙКИ", "ИТОГИ ЧАСА", "ЗАБЕГ: ПОБЕДА",
		"ЗАБЕГ: ПОРАЖЕНИЕ", "ГЛАВНОЕ МЕНЮ", "ПОДТВЕРЖДЕНИЕ", "МАСКОТ"]
	if i < titles.size():
		return titles[i]
	return TABS[i]


func _status(text: String) -> void:
	if _signal_label != null:
		var value := "СИГНАЛ: " + text
		_signal_label.text = Theme90.fit(Theme90.ui(700), value, Theme90.FS_MICRO, 320)


func _on_shop_buy(id: String) -> void:
	var price: int = _shop.item_price(id)
	var level := int(_levels.get(id, 0))
	var max_level: int = _shop.item_max_level(id)
	if level >= max_level:
		_status("МАКСИМУМ: " + _shop.item_name(id))
		return
	if _money < price:
		_status("НЕ ХВАТАЕТ %d $: %s" % [price - _money, _shop.item_name(id)])
		return
	_money -= price
	_levels[id] = level + 1
	_shop.refresh(_money, _levels)
	_status("КУПЛЕНО: %s · −%d $" % [_shop.item_name(id), price])


func _on_settings_changed(values: Dictionary) -> void:
	_status("ЗВУК %d · МУЗЫКА %d · ФОН %s · ЭКРАН %s" % [
		int(values.get("sfx", 0)), int(values.get("music", 0)),
		"ВКЛ" if bool(values.get("calm_bg", false)) else "ВЫКЛ",
		"ВКЛ" if bool(values.get("fullscreen", false)) else "ВЫКЛ"])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_show_tab(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		KEY_G:
			_show_tab(TABS.size() - 1)
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			_show_tab((_active - 1 + TABS.size()) % TABS.size())
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_show_tab((_active + 1) % TABS.size())
			get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Служебные слои
# --------------------------------------------------------------------------

class OverlayLayer:
	extends Control

	var cells: Array = []

	func _draw() -> void:
		for cell in cells:
			var r: Rect2 = cell["rect"]
			draw_rect(r.grow(1), Color(0.55, 0.58, 0.66), false, 1.0)
			draw_rect(r, Color(0.20, 0.22, 0.28), false, 1.0)
			draw_rect(Rect2(r.position.x, r.position.y - 14, 5, 5), Theme90.ACCENT_LIGHT)
			Theme90.text(self, Theme90.ui(), Vector2(r.position.x + 10, r.position.y - 14),
				str(cell["title"]), Theme90.FS_MICRO, Color(0.86, 0.89, 0.95))


## Условный «игровой экран» под модалками — чтобы видеть затемнение.
class FakeDesk:
	extends Control

	func _draw() -> void:
		draw_texture_rect(Theme90.dither_texture(), Rect2(Vector2.ZERO, size), true)
		var f := Theme90.ui()
		var lf := Theme90.logo()

		# титлбар приложения — светлая полоса
		draw_rect(Rect2(0, 0, size.x, 24), Theme90.PAPER_HI)
		draw_rect(Rect2(0, 23, size.x, 1), Theme90.HAIRLINE)
		Theme90.text(self, lf, Vector2(10, 7), "PEAK HOUR 97", 9, Theme90.NAVY)
		Theme90.text(self, f, Vector2(size.x - 74, 7), "03:42", Theme90.FS_MICRO,
			Theme90.SHADE)

		# строка меню
		draw_rect(Rect2(0, 24, size.x, 20), Theme90.PAPER)
		draw_rect(Rect2(0, 43, size.x, 1), Theme90.HAIRLINE)
		Theme90.text(self, f, Vector2(10, 27), "ФАЙЛ   ПРАВКА   ВИД   СПРАВКА",
			Theme90.FS_MICRO, Theme90.DARK)
		Theme90.text(self, f, Vector2(1070, 27), "МАГАЗИН", Theme90.FS_MICRO, Theme90.DARK)
		Theme90.text(self, f, Vector2(1140, 27), "НАЧАТЬ ЧАС", Theme90.FS_MICRO, Theme90.NAVY)

		# рабочая область
		draw_style_box(Theme90.box(Theme90.PAPER, Theme90.BORDER_SOFT, 4, 1), Rect2(8, 48, 840, 548))
		_draw_window(Rect2(16, 72, 240, 516), "ДИСКИ")
		_draw_window(Rect2(264, 72, 576, 516), "ФАЙЛЫ · ПРИЁМ")
		_draw_window(Rect2(856, 48, 416, 264), "ПРИЁМ")
		_draw_window(Rect2(856, 320, 416, 276), "ОТПРАВКА")

		# дерево
		Theme90.draw_folder_icon(self, Vector2(30, 108), Theme90.WARN, true)
		Theme90.text(self, f, Vector2(50, 104), "C:  ЛОКАЛЬНЫЙ", Theme90.FS_MICRO, Theme90.INK)
		for i in 5:
			Theme90.draw_folder_icon(self, Vector2(42, 132 + i * 20), Theme90.WARN, false)
			Theme90.text(self, f, Vector2(62, 130 + i * 20),
				["ПРИЁМ", "ОТПРАВКА", "АРХИВ", "ПРОЕКТЫ", "СКАНЫ"][i],
				Theme90.FS_MICRO, Theme90.DARK)

		# сетка файлов
		for i in 18:
			var col := i % 6
			var row := i / 6
			var r := Rect2(292 + col * 88, 112 + row * 72, 76, 60)
			draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER_SOFT, 3, 1), r)
			Theme90.draw_doc_icon(self, Rect2(r.position + Vector2(26, 6), Vector2(24, 24)),
				["text", "sound", "photo", "video"][i % 4],
				[Theme90.ACCENT, Theme90.WARN, Theme90.SUCCESS, Theme90.ERROR][i % 4])
			Theme90.text(self, f, Vector2(r.position.x + 7, r.position.y + 38),
				Theme90.fit(f, ["отчёт_смены", "реклама", "скан_пасп", "кадр_4", "договор",
					"прайс"][i % 6] + ".xls", Theme90.FS_MICRO, 62),
				Theme90.FS_MICRO, Theme90.DARK)

		# карточки приёма и запросов
		for i in 4:
			var y := 80.0 + i * 52.0
			var card := Rect2(866, y, 396, 44)
			draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER_SOFT, 3, 1), card)
			Theme90.draw_packet_icon(self, card.position + Vector2(10, 14), Theme90.ACCENT)
			Theme90.text(self, f, card.position + Vector2(32, 9), "пакет_%02d.wav" % (i + 1),
				Theme90.FS_MICRO, Theme90.INK)
			Theme90.text(self, f, card.position + Vector2(32, 24), "1,8 МБ · 00:12",
				Theme90.FS_MICRO, Theme90.SHADE)

		for i in 3:
			var y := 328.0 + i * 64.0
			var card := Rect2(866, y, 396, 56)
			draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), card)
			Theme90.text(self, f, card.position + Vector2(10, 7), "ООО «ВЕКТОР»",
				Theme90.FS_MICRO, Theme90.INK)
			Theme90.text(self, f, card.position + Vector2(10, 22), "Требуется 2 файла",
				Theme90.FS_MICRO, Theme90.SHADE)
			for j in 2:
				draw_style_box(Theme90.well_box(Theme90.WHITE),
					Rect2(card.position + Vector2(270 + j * 58, 12), Vector2(50, 32)))

		# слоты
		draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 4, 1), Rect2(8, 604, 1264, 52))
		Theme90.text(self, f, Vector2(20, 620), "TCP", Theme90.FS_MICRO, Theme90.NAVY)
		for i in 4:
			draw_style_box(Theme90.well_box(Theme90.WHITE), Rect2(58 + i * 240, 610, 236, 40))
			Theme90.text(self, f, Vector2(70 + i * 240, 622), "СЛОТ %d" % (i + 1),
				Theme90.FS_MICRO, Theme90.SHADE)

		# статус-бар
		draw_rect(Rect2(0, 660, size.x, 60), Theme90.PAPER_HI)
		draw_rect(Rect2(0, 660, size.x, 1), Theme90.HAIRLINE)
		Theme90.text(self, f, Vector2(18, 672), "УЗЕЛ 7 НА СВЯЗИ · БУФЕР 3/4 · КАНАЛ 45%",
			Theme90.FS_MICRO, Theme90.SHADE)
		Theme90.text(self, f, Vector2(18, 693), "СМЕНА 3 · 03:42 / 08:00",
			Theme90.FS_MICRO, Theme90.SHADE)
		Theme90.text(self, lf, Vector2(1010, 680), "$ 1240", 12, Theme90.SUCCESS)

	func _draw_window(r: Rect2, title: String) -> void:
		draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER, 3, 1, Theme90.SHADOW), r)
		var tr := Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, 18)
		draw_style_box(Theme90.top_box(Theme90.PAPER_HI, 3), tr)
		draw_rect(Rect2(tr.position.x, tr.end.y, tr.size.x, 1), Theme90.HAIRLINE)
		Theme90.text_vcenter(self, Theme90.ui(), Rect2(tr.position.x + 8, tr.position.y,
			tr.size.x - 16, 18), title, Theme90.FS_MICRO, Theme90.NAVY)
