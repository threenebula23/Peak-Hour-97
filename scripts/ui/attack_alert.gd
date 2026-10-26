class_name AttackAlert
extends Control
## Короткое полноэкранное предупреждение перед мини-игрой атаки:
## затемнение, панель «ИДЁТ АТАКА» + название, пульс и лёгкая тряска.
## Живёт 1.1 с и эмитит finished; в reduced/headless — без движения.

signal finished

const DURATION := 1.1
const PANEL_SIZE := Vector2(560, 168)

var _title := "ИДЁТ АТАКА"
var _subtitle := ""
var _duration := DURATION
var _t := 0.0
var _done := false
var _reduced := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reduced = UiMotion.reduced or DisplayServer.get_name() == "headless"
	set_process(false)


func play(title: String, subtitle: String, duration: float = DURATION) -> void:
	_title = title
	_subtitle = subtitle
	_duration = maxf(0.15, duration)
	_t = 0.0
	_done = false
	_reduced = UiMotion.reduced or DisplayServer.get_name() == "headless"
	visible = true
	set_process(true)
	queue_redraw()


## Досрочно завершить (смена фазы/отмена атаки) без ожидания таймера.
func finish_now() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	visible = false
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	queue_redraw()
	if _t >= _duration:
		finish_now()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, Color(0.20, 0.05, 0.04, 0.48))
	draw_rect(full, Color(0.70, 0.16, 0.12, 0.10))

	var pulse := 0.0
	var shake := Vector2.ZERO
	if not _reduced:
		pulse = 0.5 + 0.5 * sin(TAU * _t / 0.42)
		shake = Vector2(sin(_t * 46.0) * 2.0, cos(_t * 37.0) * 1.0).round()

	var panel := Rect2(((size - PANEL_SIZE) * 0.5).round() + shake, PANEL_SIZE)
	# Красное свечение-пульс вокруг панели.
	if not _reduced:
		draw_rect(panel.grow(4.0 + 5.0 * pulse),
			Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b,
				0.08 + 0.16 * pulse), false, 2.0)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.ERROR, 4, 2,
		Theme90.SHADOW), panel)
	draw_rect(Rect2(panel.position.x + 1, panel.position.y + 1,
		panel.size.x - 2, 4), Theme90.ERROR)
	# Тонкая внутренняя линия, чтобы панель не сливалась с затемнением.
	draw_rect(Rect2(panel.position.x + 14, panel.position.y + 54,
		panel.size.x - 28, 1), Theme90.HAIRLINE)

	var title_col := Theme90.ERROR.darkened(0.18)
	Theme90.text_vcenter(self, Theme90.display(),
		Rect2(panel.position.x, panel.position.y + 20, panel.size.x, 34),
		_title, 30, title_col, -1, HORIZONTAL_ALIGNMENT_CENTER)
	Theme90.text_vcenter(self, Theme90.ui(),
		Rect2(panel.position.x, panel.position.y + 62, panel.size.x, 26),
		_subtitle, 18, Theme90.NAVY_DEEP, -1, HORIZONTAL_ALIGNMENT_CENTER)

	var hint_col := Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b,
		0.68 + (0.32 * pulse if not _reduced else 0.0))
	Theme90.text_vcenter(self, Theme90.ui(),
		Rect2(panel.position.x, panel.position.y + 100, panel.size.x, 18),
		"ПРИГОТОВЬТЕСЬ", 10, hint_col, -1, HORIZONTAL_ALIGNMENT_CENTER)
	# Маленькие красные штрихи-«маячки» по краям панели.
	var blink := 1.0 if _reduced else (0.45 + 0.55 * pulse)
	for i in 2:
		var x := panel.position.x + 18.0 + i * (panel.size.x - 40.0)
		draw_rect(Rect2(x, panel.end.y - 18, 8, 2),
			Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, blink))
