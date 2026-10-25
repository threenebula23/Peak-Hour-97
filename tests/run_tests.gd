extends SceneTree
## Headless-раннер тестов ядра.
##
## Запуск:
##   godot --headless --path . --script tests/run_tests.gd
##
## Часть модулей v2 — самостоятельные SceneTree-скрипты (`_init` + `quit`).
## Их нельзя вызывать через `run(t)` в этом же процессе: они сами управляют
## SceneTree и завершением. Поэтому такие модули запускаются дочерним
## процессом Godot через OS.execute, а здесь остаются только RefCounted-
## модули с `run(t)`. Это убирает ложные FAIL и сохраняет единый exit code.

const MODULES := [
	["rng", "res://tests/test_rng.gd"],
]

## Standalone SceneTree-скрипты: [имя, путь]. Каждый — отдельный процесс.
const STANDALONE := [
	["economy", "res://tests/test_economy.gd"],
	["registry", "res://tests/test_registry.gd"],
	["save", "res://tests/test_save.gd"],
]

var _checks: int = 0
var _fails: int = 0
var _module: String = ""
var _case: String = ""
var _module_fails: int = 0


func _init() -> void:
	# Ждём _ready автолоадов (Data/Game/Rng), иначе прогрессия читается пустой.
	await process_frame
	print("PEAK HOUR — headless tests")
	var failed_modules: Array[String] = []

	for entry in MODULES:
		_module = str(entry[0])
		_case = ""
		_module_fails = 0
		if not ResourceLoader.exists(str(entry[1])):
			print("\n--- %s --- SKIP (нет файла)" % _module)
			continue
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

	for entry in STANDALONE:
		var name := str(entry[0])
		var path := str(entry[1])
		if not ResourceLoader.exists(path):
			print("\n--- %s (standalone) --- SKIP (нет файла)" % name)
			continue
		if not _run_standalone(name, path):
			failed_modules.append(name)

	print("")
	print("Проверок в этом процессе: %d, провалов: %d" % [_checks, _fails])
	print("Standalone-модулей: %d" % STANDALONE.size())
	if _fails == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL: модули %s" % ", ".join(failed_modules))
		quit(1)


## Запустить самостоятельный SceneTree-тест дочерним Godot.
## Возвращает true, если процесс завершился с кодом 0.
func _run_standalone(name: String, path: String) -> bool:
	print("\n--- %s (standalone) ---" % name)
	var godot := OS.get_executable_path()
	if godot.is_empty():
		print("FAIL %s: не удалось определить путь к Godot" % name)
		return false
	var project_dir := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--headless",
		"--path", project_dir,
		"--script", path,
	])
	var output: Array = []
	var code := OS.execute(godot, args, output, true)
	for line in output:
		print(str(line).trim_suffix("\n").trim_suffix("\r"))
	if code == 0:
		print("PASS %s" % name)
		return true
	print("FAIL %s (exit %d)" % [name, code])
	return false


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
