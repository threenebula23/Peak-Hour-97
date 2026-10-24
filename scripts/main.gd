extends Control
## Точка входа PEAK HOUR 97.
##
## Сейчас здесь только каркас: серый фон #C0C0C0 и заголовок по центру.
## TODO: переход в Prep -> Hour -> Results через автолоад Game.

@onready var title: Label = $Title


func _ready() -> void:
	title.text = "PEAK HOUR 97"
