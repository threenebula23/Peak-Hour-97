extends SceneTree
## Headless-раннер тестов ядра.
##
## Запуск:
##   godot --headless --path . --script tests/run_tests.gd

const MODULES := [
	["registry", "res://tests/test_registry.gd"],
	["economy", "res://tests/test_economy.gd"],
	["save", "res://tests/test_save.gd"],
	["rng", "res://tests/test_rng.gd"],
]

var _checks: int = 0
var _fails: int = 0
var _module: String = ""
var _case: String = ""
var _module_fails: int = 0


func _init() -> void:
	print("PEAK HOUR — headless tests")
	var failed_modules: Array[String] = []
	for entry in MODULES:
		_module = str(entry[0])
		_case = ""
		_module_fails = 0
		print("\n--- %s ---" % _module)
		var script = load(str(entry[1]))
		if script == null:
			fail("не удалось загрузить %s" % str(entry[1]))
			failed_modules.append(_module)
			continue
		var instance = script.new()
		if not instance.has_method("run"):
			fail("в модуле нет run(t)")
			failed_modules.append(_module)
			continue
		instance.run(self)
		if _module_fails == 0:
			print("PASS %s" % _module)
		else:
			print("FAIL %s (%d)" % [_module, _module_fails])
			failed_modules.append(_module)

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL: модули %s" % ", ".join(failed_modules))
		quit(1)


# --- assert-хелперы --------------------------------------------------------

func set_case(name: String) -> void:
	_case = name


func ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	fail(message + " — ожидалось true")
	return false


func eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	fail("%s — получено %s, ожидалось %s" % [message, _fmt(actual), _fmt(expected)])
	return false


func ne(actual, unexpected, message: String) -> bool:
	_checks += 1
	if actual != unexpected:
		return true
	fail("%s — получено %s, не ожидалось %s" % [message, _fmt(actual), _fmt(unexpected)])
	return false


func approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return true
	fail("%s — получено %.6f, ожидалось %.6f (eps %.6f)" % [message, actual, expected, eps])
	return false


func fail(message: String) -> void:
	_fails += 1
	_module_fails += 1
	print("FAIL [%s/%s] %s" % [_module, _case, message])


func _fmt(value) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % str(value)
	return str(value)
