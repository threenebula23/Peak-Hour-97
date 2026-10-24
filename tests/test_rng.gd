extends RefCounted
## Тесты Rng: детерминизм по сиду, сохранение/восстановление state.

const R := preload("res://scripts/autoload/rng.gd")


func run(t) -> void:
	_test_same_seed(t)
	_test_state(t)
	_test_pick(t)
	_test_edges(t)


func _test_same_seed(t) -> void:
	t.set_case("same_seed")
	var a = R.new()
	var b = R.new()
	a.start_run(12345)
	b.start_run(12345)
	for i in range(25):
		t.approx(a.randf(), b.randf(), 0.0, "randf #%d" % i)
	for i in range(10):
		t.eq(a.randi_range(1, 6), b.randi_range(1, 6), "randi #%d" % i)

	var c = R.new()
	var d = R.new()
	c.start_run(1)
	d.start_run(2)
	var different := false
	for i in range(10):
		if not is_equal_approx(c.randf(), d.randf()):
			different = true
	t.ok(different, "разные сиды дают разные последовательности")

	t.eq(c.seed_string(), "1", "seed_string")
	t.eq(int(c.get_seed()), 1, "get_seed")
	a.free()
	b.free()
	c.free()
	d.free()


func _test_state(t) -> void:
	t.set_case("state")
	var a = R.new()
	a.start_run(777)
	for i in range(7):
		a.randf()
	var state: String = a.state_string()
	t.ok(not state.is_empty(), "state_string не пуст")
	t.ok(state.is_valid_int(), "state — целое в строке: %s" % state)

	var b = R.new()
	b.start_run(1)
	t.ok(b.restore_state(state), "restore_state")
	for i in range(25):
		t.approx(a.randf(), b.randf(), 0.0, "продолжение #%d" % i)

	t.ok(not b.restore_state("не число"), "restore_state мусора — false")
	t.ok(not b.restore_state(""), "restore_state пустой строки — false")
	a.free()
	b.free()


func _test_pick(t) -> void:
	t.set_case("pick")
	var rng = R.new()
	rng.start_run(5)
	t.eq(rng.pick([42]), 42, "pick одного")
	t.eq(rng.pick([]), null, "pick пустого — null")
	t.eq(rng.weighted_pick([1, 0, 0]), 0, "weighted с одним весом")
	t.eq(rng.weighted_pick([]), -1, "weighted пустого — -1")
	t.eq(rng.weighted_pick([0, 0]), -1, "weighted нулевых весов — -1")

	var seen := {}
	for i in range(60):
		var idx: int = rng.weighted_pick([1, 2, 3])
		t.ok(idx >= 0 and idx < 3, "weighted индекс в диапазоне")
		seen[idx] = true
	t.eq(seen.size(), 3, "weighted задел все три индекса")
	rng.free()


func _test_edges(t) -> void:
	t.set_case("edges")
	var rng = R.new()
	rng.start_run(99)
	t.eq(rng.randi_range(5, 5), 5, "randi_range с равными границами")
	t.approx(rng.randf_range(2.0, 2.0), 2.0, 0.0, "randf_range с равными границами")
	var value: float = rng.randf()
	t.ok(value >= 0.0 and value < 1.0, "randf в [0,1)")
	var zero_seed = R.new()
	zero_seed.start_run(0)
	t.ok(not zero_seed.seed_string().is_empty(), "seed 0 → случайный сид")
	t.ok(zero_seed.restore_state(zero_seed.state_string()), "state seed 0 восстанавливается")
	rng.free()
	zero_seed.free()
