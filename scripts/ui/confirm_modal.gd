class_name ConfirmModal
extends Control
## Модальное окно подтверждения: вопрос и «Да» / «Нет».
##
##   confirm.ask("Выйти в главное меню?", "Прогресс смены не сохранится.", "Да", "Нет", true)
##   confirm.answered.connect(_on_answered)
##
## Сигнал answered(bool) приходит один раз — после него окно скрывается.

signal answered(value: bool)

const W := 460.0
const H := 148.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

var _question := "Продолжить?"
var _detail := ""
var _danger := false
var _yes_text := "Да"
var _no_text := "Нет"
var _btn_yes: Button90
var _btn_no: Button90
var _btn_x: Button90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	visible = false


func ask(question: String, detail: String = "", yes_text: String = "Да",
		no_text: String = "Нет", danger: bool = false) -> void:
	_question = question
	_detail = detail
	_danger = danger
	_yes_text = yes_text
	_no_text = no_text
	if _btn_yes != null:
		_btn_yes.caption = yes_text
		_btn_yes.accent = not danger
		_btn_yes.danger = danger
	if _btn_no != null:
		_btn_no.caption = no_text
	visible = true
	queue_redraw()
	if _btn_no != null:
		_btn_no.grab_focus()


func _build() -> void:
	_btn_yes = Button90.new()
	_btn_yes.caption = _yes_text
	add_child(_btn_yes)
	_btn_yes.pressed.connect(_answer.bind(true))

	_btn_no = Button90.new()
	_btn_no.caption = _no_text
	add_child(_btn_no)
	_btn_no.pressed.connect(_answer.bind(false))

	_btn_x = Button90.new()
	_btn_x.icon = Button90.Icon.X
	_btn_x.tooltip_text = "Нет"
	_btn_x.pressed.connect(_answer.bind(false))
	add_child(_btn_x)


func _answer(value: bool) -> void:
	if not visible:
		return
	visible = false
	answered.emit(value)


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	if _btn_yes != null:
		_btn_yes.position = r.position + Vector2(236, 102)
		_btn_yes.size = Vector2(100, 24)
	if _btn_no != null:
		_btn_no.position = r.position + Vector2(348, 102)
		_btn_no.size = Vector2(100, 24)
	if _btn_x != null:
		_btn_x.position = r.position + Vector2(W - 22, 4)
		_btn_x.size = Vector2(16, 16)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_answer(false)
		get_viewport().set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, 1280, 720)
	draw_rect(full, DIM)
	_draw_frame(_window_rect())


func _draw_frame(r: Rect2) -> void:
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.WHITE)
	Theme90.modal_header(self, r, "ПОДТВЕРЖДЕНИЕ", "ТРЕБУЕТСЯ ОТВЕТ")

	# знак вопроса в утопленной плашке
	var well := Rect2(r.position + Vector2(18, 28), Vector2(34, 34))
	Theme90.draw_sunken(self, well)
	Theme90.text_vcenter(self, Theme90.logo(), well, "?",
		18, Theme90.ERROR if _danger else Theme90.NAVY)

	# вопрос и пояснение
	var f := Theme90.ui()
	var lines := Theme90.wrap(f, _question, 14, 378, 2)
	var y := r.position.y + 30
	for line in lines:
		Theme90.text(self, f, Vector2(r.position.x + 62, y), line, 14, Theme90.INK)
		y += 18.0
	if not _detail.is_empty():
		Theme90.text(self, f, Vector2(r.position.x + 62, r.position.y + 58),
			Theme90.fit(f, _detail, Theme90.FS_MICRO, 378), Theme90.FS_MICRO,
			Theme90.ERROR if _danger else Theme90.DARK)

	# разделитель над кнопками
	var ly := r.position.y + 88
	draw_rect(Rect2(r.position.x + 10, ly, r.size.x - 20, 1), Theme90.SHADE)
	draw_rect(Rect2(r.position.x + 10, ly + 1, r.size.x - 20, 1), Theme90.FACE_HI)

