extends Node
## Rng — единый детерминированный поток случайных чисел забега (autoload).
##
## Состояние для save хранится строкой: int64 в JSON теряет точность,
## поэтому state_string()/restore_state() работают со строкой.

var _rng := RandomNumberGenerator.new()
var _run_seed: int = 0


func _ready() -> void:
	_rng.randomize()
	_run_seed = _rng.seed


## Зафиксировать сид забега. seed == 0 — случайный сид.
func start_run(seed: int) -> void:
	if seed == 0:
		_rng.randomize()
		_run_seed = _rng.seed
	else:
		_rng.seed = seed
		_run_seed = seed


## Совместимость со старым именем.
func set_seed(seed: int) -> void:
	start_run(seed)


func get_seed() -> int:
	return _run_seed


func seed_string() -> String:
	return str(_run_seed)


func state_string() -> String:
	return str(_rng.state)


func restore_state(state: String) -> bool:
	var raw := state.strip_edges()
	if raw.is_empty() or not raw.is_valid_int():
		return false
	_rng.state = int(raw)
	return true


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


## Индекс по весам. Пустой массив или нулевая сумма — -1.
func weighted_pick(weights: Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, float(weight))
	if total <= 0.0:
		return -1
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += maxf(0.0, float(weights[i]))
		if roll < acc:
			return i
	return weights.size() - 1
