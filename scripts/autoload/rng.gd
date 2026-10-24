extends Node
## Rng — детерминированный генератор случайных чисел (autoload).
##
## TODO: единый сид на забег (реплеи/тесты), отдельные потоки для спавна и наград.
## Пока это заглушка: использует Godot RandomNumberGenerator без собственной логики.

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## TODO: зафиксировать сид на забег.
func set_seed(_new_seed: int) -> void:
	pass


## TODO: целое в диапазоне [from, to] из потока забега.
func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)
