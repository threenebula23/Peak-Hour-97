extends Node
## Game — верхнеуровневый контроллер сессии (autoload).
##
## TODO: состояния Prep -> Hour -> Results, переходы между сценами.
## Пока это заглушка: только точка расширения, игровой логики нет.

signal state_changed(from: StringName, to: StringName)

var state: StringName = &"boot"


func _ready() -> void:
	pass


## TODO: сброс прогресса к началу смены.
func reset_run() -> void:
	pass
