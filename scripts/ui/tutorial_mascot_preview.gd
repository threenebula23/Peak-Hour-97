extends Control
## Дев-сцена: кот БАЙТ в трёх состояниях. Также вкладка «МАСКОТ»
## в ModalsPreview. Нужна для скриншотов и проверки API.

const MASCOT := preload("res://scripts/ui/tutorial_mascot.gd")

var _greeting: TutorialMascot
var _stepped: TutorialMascot
var _quiet: TutorialMascot
var _brief: TutorialMascot


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func _build() -> void:
	var w := 1280.0
	var h := 720.0
	if size.x > 0.0:
		w = size.x
	if size.y > 0.0:
		h = size.y

	_greeting = MASCOT.new()
	_greeting.name = "MascotGreeting"
	_greeting.bubble_width = 250.0
	add_child(_greeting)
	_greeting.position = Vector2(112, 292)
	_greeting.set_step(1)
	_greeting.set_progress(1, 9)
	_greeting.show_tutorial("ЧАС ПИК 0",
		"Привет! Я БАЙТ, кот-диспетчер. Помогу разобраться со сменой — без лишних слов.", -1)

	_stepped = MASCOT.new()
	_stepped.name = "MascotStep"
	_stepped.bubble_width = 250.0
	add_child(_stepped)
	_stepped.position = Vector2(690, 330)
	_stepped.set_step(10)
	_stepped.set_progress(10, 17)
	_stepped.show_tutorial("ПРАКТИКА",
		"Перетащите файл в слот запроса. Зелёная галочка — файл уже прикреплён.", -1)

	_quiet = MASCOT.new()
	_quiet.name = "MascotQuiet"
	add_child(_quiet)
	_quiet.position = Vector2(112, 516)
	_quiet.set_step(4)
	_quiet.show_message("", -1)

	_brief = MASCOT.new()
	_brief.name = "MascotBrief"
	_brief.bubble_width = 250.0
	add_child(_brief)
	_brief.position = Vector2(690, 516)
	_brief.set_step(17)
	_brief.set_progress(17, 17)
	_brief.show_tutorial("ГОТОВО", "Обучение завершено. Дальше — сами.", -1)


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size if size.x > 0.0 else Vector2(1280, 720))
	draw_texture_rect(Theme90.dither_texture(), full, true)
	draw_circle(Vector2(full.size.x * 0.9, full.size.y * 0.16), 220.0,
		Color(Theme90.ACCENT_LIGHT.r, Theme90.ACCENT_LIGHT.g, Theme90.ACCENT_LIGHT.b, 0.10))

	var card := Rect2(64, 52, full.size.x - 128, full.size.y - 104)
	draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER, 6, 1,
		Color(0, 0, 0, 0.10)), card)
	draw_rect(Rect2(card.position.x + 1, card.position.y + 1, 96, 3), Theme90.ACCENT)

	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(card.position.x + 44, card.position.y + 30),
		"МАСКОТ · БАЙТ (КОТ)", 16, Theme90.NAVY)
	Theme90.text(self, f, Vector2(card.position.x + 44, card.position.y + 53),
		"show_tutorial(title, text) · set_progress(n, total) · hide_message()",
		10, Theme90.SHADE)

	_caption(f, Vector2(112, 264), "ПРИВЕТСТВИЕ · ИНТРО-КАРТОЧКА")
	_caption(f, Vector2(690, 302), "ПРАКТИКА · ПРОГРЕСС 10 / 17")
	_caption(f, Vector2(112, 488), "КОТ БЕЗ ОБЛАЧКА · НОМЕР ШАГА НА БЕЙДЖЕ")
	_caption(f, Vector2(690, 488), "ФИНАЛ · ОБУЧЕНИЕ ЗАВЕРШЕНО")

	Theme90.text(self, f, Vector2(card.position.x + 44, card.end.y - 28),
		"Оранжевый кот в кепке и очках · art/mascot/tutor_cat.png",
		10, Theme90.SHADE)


func _caption(f: Font, pos: Vector2, text: String) -> void:
	Theme90.text(self, f, pos, text, 10, Theme90.ACCENT)
