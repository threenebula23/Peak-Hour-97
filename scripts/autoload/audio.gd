extends Node
## Audio — шина звука и музыка (autoload).
##
## TODO: пулы AudioStreamPlayer, кроссфейд музыки, приглушение при потере фокуса.
## Пока это заглушка: никаких потоков не создаёт.

var music_volume: float = 0.8
var sfx_volume: float = 0.9


## TODO: проиграть одноразовый SFX из res://audio/sfx.
func play_sfx(_sfx_name: StringName) -> void:
	pass
