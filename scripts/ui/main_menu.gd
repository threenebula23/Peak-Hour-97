class_name MainMenu
extends Control
## Главное меню: одна центрированная карточка — логотип, слоган и пять кнопок.
## Служебные подписи, шаги смены и стартовая сводка убраны из отрисовки.
##
## Фон — медленно падающие иконки файлов (FileIcons), зацикленные и приглушённые;
## они живут под карточкой и не перекрывают текст/кнопки.
##
## Только UI. Наличие сохранения передаёт интеграция:
##   menu.set_has_save(SaveManager.has_save())

signal new_run
signal continue_run
signal tutorial_requested
signal settings
signal about

const W := 1280.0
const H := 720.0

## Preload вместо глобального имени: работает и без прогретого class cache.
const VHS_OVERLAY := preload("res://scripts/ui/vhs_overlay.gd")

## Карточка меню: 560×520 по центру экрана.
const CARD := Vector2(560.0, 520.0)
const BTN_W := 300.0
const BTN_H := 38.0
const BTN_STEP := 50.0

## Стартовая сводка v2: 9 часов, 50 $, SLA 60, 1 слот.
## Оставлена как API для тестов/интеграции, но в меню не рисуется.
const START_STATS_TEXT := "9 часов · $50 на старте · 60 SLA · 1 слот"

# --- анимация входа --------------------------------------------------------
const INTRO_DUR := 0.42
const INTRO_RISE := 14.0

# --- фон: падающие иконки --------------------------------------------------
const PARTICLE_MIN := 18
const PARTICLE_MAX := 22
const PARTICLE_HZ := 30.0
const PARTICLE_SIZE_MIN := 16.0
const PARTICLE_SIZE_MAX := 28.0
const PARTICLE_MARGIN := 48.0

var has_save := false
## Тонкий VHS-слой поверх меню. Игра и модалки не фильтруются.
var vhs = null

var _btn_continue: Button90
var _btn_new: Button90
var _btn_tutorial: Button90
var _btn_settings: Button90
var _btn_about: Button90

## Порядок кнопок: раскладка, отрисовка hover-маркера, обход в _process.
var _order: Array[Button90] = []
## Плавность hover-маркера per-button (0..1).
var _marker_amts := {}

var _intro_t := 1.0
var _intro_dy := 0.0

## Частицы фона: словари с x/y/speed/size/icon/alpha/spin/rot/phase/wobble/freq/drift.
var _particles: Array[Dictionary] = []
var _particle_accum := 0.0
var _particle_t := 0.0

static var _card_style: StyleBoxFlat = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_build_vhs()
	_init_particles()
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_play_intro()
	_layout()
	_sync_process()
	queue_redraw()


func set_has_save(value: bool, hint: String = "") -> void:
	has_save = value
	if _btn_continue != null:
		_btn_continue.disabled = not has_save
		if has_save:
			_btn_continue.tooltip_text = ""
		elif hint.is_empty():
			_btn_continue.tooltip_text = "Сохранение не найдено"
		else:
			_btn_continue.tooltip_text = hint
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

	_btn_tutorial = _make_button(_tr("btn.tutorial", "Обучение"))
	_btn_tutorial.pressed.connect(func() -> void: tutorial_requested.emit())

	_btn_settings = _make_button(_tr("btn.settings", "Настройки"))
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


## Строка стартовой сводки (API для тестов; в меню не рисуется).
func start_stats_text() -> String:
	return START_STATS_TEXT


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
	_order.append(b)
	_marker_amts[b] = 0.0
	return b


# --- раскладка -------------------------------------------------------------

func _window() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(W, H)
	var origin := ((s - CARD) * 0.5).round()
	origin.y += _intro_dy
	return Rect2(origin, CARD)


## Панель действий: 300×250 по центру карточки. Кнопки центрируются по ней.
func _panel_rect(w: Rect2) -> Rect2:
	return Rect2(w.position.x + (w.size.x - BTN_W) * 0.5,
		w.position.y + 230.0, BTN_W, BTN_STEP * 4.0 + BTN_H + 12.0)


func _layout() -> void:
	var w := _window()
	var panel := _panel_rect(w)
	var px := panel.position.x
	var py := panel.position.y
	for b in _order:
		if b != null:
			b.position = Vector2(px, py)
			b.size = Vector2(BTN_W, BTN_H)
		py += BTN_STEP


# --- анимация входа / процесс ---------------------------------------------

func _play_intro() -> void:
	_intro_t = 1.0
	_intro_dy = 0.0
	if _animating():
		_intro_t = 0.0
		_intro_dy = INTRO_RISE
	_layout()


func _snap_intro() -> void:
	_intro_t = 1.0
	_intro_dy = 0.0
	_layout()


func _animating() -> bool:
	return visible and not UiMotion.reduced \
		and DisplayServer.get_name() != "headless"


func _on_visibility_changed() -> void:
	if visible:
		_play_intro()
	_sync_process()
	queue_redraw()


func _sync_process() -> void:
	var on := _animating()
	if not on:
		_snap_intro()
		queue_redraw()
	set_process(on)


func _process(delta: float) -> void:
	if not _animating():
		# «Снизить эффекты» включили посреди входа: вернуть финальную раскладку.
		_snap_intro()
		_particle_accum = 0.0
		set_process(false)
		queue_redraw()
		return

	var changed := false

	# Вход: мягкий подъём карточки с кнопками.
	if _intro_t < 1.0:
		_intro_t = minf(1.0, _intro_t + delta / INTRO_DUR)
		var e := 1.0 - pow(1.0 - _intro_t, 3.0)
		_intro_dy = INTRO_RISE * (1.0 - e)
		_layout()
		changed = true

	# Hover-маркер у кнопок: плавно появляется/гаснет.
	for b in _order:
		var target := _hover_target(b)
		var cur := float(_marker_amts.get(b, 0.0))
		if not is_equal_approx(cur, target):
			cur = move_toward(cur, target, delta / (0.12 if target > cur else 0.18))
			_marker_amts[b] = cur
			changed = true

	# Иконки падают медленно — перерисовка 30 Гц, а не каждый кадр.
	_particle_accum += delta
	if _particle_accum >= 1.0 / PARTICLE_HZ:
		_step_particles(_particle_accum)
		_particle_accum = 0.0
		changed = true

	if changed:
		queue_redraw()


# --- фон: падающие иконки файлов ------------------------------------------

func _init_particles() -> void:
	_particles.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1997
	var count := rng.randi_range(PARTICLE_MIN, PARTICLE_MAX)
	for i in count:
		var size := float(rng.randi_range(int(PARTICLE_SIZE_MIN), int(PARTICLE_SIZE_MAX)))
		_particles.append({
			"x": rng.randf_range(-32.0, W + 32.0),
			"y": rng.randf_range(-PARTICLE_MARGIN, H),
			"size": size,
			"icon": rng.randi_range(0, FileIcons.COUNT - 1),
			"speed": rng.randf_range(7.0, 16.0),
			"alpha": 0.25 + 0.35 * pow(rng.randf(), 1.6),
			"spin": rng.randf_range(-0.45, 0.45),
			"rot": rng.randf_range(0.0, TAU),
			"phase": rng.randf_range(0.0, TAU),
			"wobble": rng.randf_range(3.0, 9.0),
			"freq": rng.randf_range(0.10, 0.32),
			"drift": rng.randf_range(-4.0, 4.0),
		})


func _step_particles(dt: float) -> void:
	_particle_t += dt
	var x_span := W + PARTICLE_MARGIN * 2.0
	var y_span := H + PARTICLE_MARGIN * 2.0
	for p in _particles:
		p["y"] = fposmod(float(p["y"]) + float(p["speed"]) * dt
			+ PARTICLE_MARGIN, y_span) - PARTICLE_MARGIN
		p["x"] = fposmod(float(p["x"]) + float(p["drift"]) * dt
			+ PARTICLE_MARGIN, x_span) - PARTICLE_MARGIN
		p["rot"] = fposmod(float(p["rot"]) + float(p["spin"]) * dt, TAU)


func _draw_particles() -> void:
	if _particles.is_empty() or FileIcons.texture() == null:
		return
	for p in _particles:
		var y := float(p["y"])
		if y < -PARTICLE_MARGIN or y > H + PARTICLE_MARGIN:
			continue
		var x := float(p["x"]) \
			+ sin(_particle_t * TAU * float(p["freq"]) + float(p["phase"])) * float(p["wobble"])
		var s := float(p["size"])
		draw_set_transform(Vector2(x, y), float(p["rot"]), Vector2.ONE)
		FileIcons.draw(self, Rect2(-s * 0.5, -s * 0.5, s, s), int(p["icon"]),
			float(p["alpha"]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, W, H)
	# 1. Бумага и два очень мягких пастельных пятна.
	draw_texture_rect(Theme90.dither_texture(), full, true)
	draw_circle(Vector2(full.size.x * 0.93, full.size.y * 0.10), 250.0,
		Color(Theme90.ACCENT_LIGHT.r, Theme90.ACCENT_LIGHT.g,
			Theme90.ACCENT_LIGHT.b, 0.10))
	draw_circle(Vector2(full.size.x * 0.06, full.size.y * 0.96), 300.0,
		Color(0.96, 0.80, 0.72, 0.09))
	# 2. Иконки падают под карточкой; карточка непрозрачна, поэтому текст
	#    и кнопки всегда читаемы.
	_draw_particles()
	# 3. Центрированная карточка, логотип, слоган и hover-маркеры кнопок.
	var w := _window()
	_draw_card(w)
	_draw_hero_shapes(w)
	_draw_hero_text(w)
	_draw_hover_marks()


func _draw_card(w: Rect2) -> void:
	if _card_style == null:
		_card_style = Theme90.box(Theme90.WHITE, Theme90.BORDER, 6, 1,
			Color(0, 0, 0, 0.13))
		_card_style.shadow_size = 10
		_card_style.shadow_offset = Vector2(0, 5)
	draw_style_box(_card_style, w)


func _draw_hero_shapes(w: Rect2) -> void:
	# Тонкая акцентная линейка по центру под названием.
	var cx := w.get_center().x
	var y := w.position.y + 130.0
	draw_rect(Rect2(cx - 36, y, 58, 3), Theme90.ACCENT)
	draw_rect(Rect2(cx + 26, y, 8, 3), Theme90.ERROR)


func _draw_hero_text(w: Rect2) -> void:
	var f := Theme90.ui()
	var cx := w.get_center().x

	var kicker := "ДИСПЕТЧЕР ФАЙЛОВОГО ОБМЕНА · 1997"
	var kw := f.get_string_size(kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(cx - kw * 0.5, w.position.y + 40.0),
		kicker, 10, Theme90.ACCENT)

	var title := "PEAK HOUR 97"
	var tf := Theme90.display()
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	Theme90.text(self, tf, Vector2(cx - tw * 0.5, w.position.y + 58.0),
		title, 46, Theme90.NAVY)

	var sub := _tr("ui.subtitle", "Час пик. Одна смена. Ни одного свободного места.")
	var lines := Theme90.wrap(f, sub, 15, 420.0, 2)
	var sy := w.position.y + 150.0
	for line in lines:
		var lw := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		Theme90.text(self, f, Vector2(cx - lw * 0.5, sy), line, 15, Theme90.DARK)
		sy += 21.0


## Меню-специфичный hover: короткая акцентная риска слева от кнопки.
## Сами кнопки уже умеют плавные hover/фокус/рябь из Button90.
func _draw_hover_marks() -> void:
	for b in _order:
		if b == null:
			continue
		var amt := _hover_target(b) if not _animating() \
			else float(_marker_amts.get(b, 0.0))
		if amt <= 0.01:
			continue
		var h := 16.0
		var r := Rect2(b.position.x - 15.0,
			b.position.y + roundf((b.size.y - h) * 0.5), 3.0, h)
		draw_rect(r, Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b,
			0.75 * amt))


func _hover_target(b: Button90) -> float:
	if b == null or b.disabled:
		return 0.0
	return 1.0 if b.is_hovered() or b.has_focus() else 0.0
