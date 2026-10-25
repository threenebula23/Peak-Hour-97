extends SceneTree
## Headless-регресс на краш тостов (ToastLayer).
##
## Баг: 4-й тост вытеснял старейший через queue_free(), но его life-tween
## оставался жить и через 3.45 с вызывал callback с освобождённым узлом:
##   «Lambda capture at index 0 was freed» + «Cannot call queue_free on null».
##
## Проверяет:
##   • при вытеснении life-tween убивается, а не остаётся висеть;
##   • вытесненный тост удаляется, в очереди остаются только живые;
##   • _relayout вычищает невалидные записи из _items;
##   • после полного жизненного цикла 5–6 тостов нет висящих узлов/ошибок.
##
## Запуск:
##   godot --headless --path . --script tests/test_toast.gd

var _checks := 0
var _fails := 0


func _init() -> void:
	await process_frame
	var layer: ToastLayer = ToastLayer.new()
	root.add_child(layer)
	await process_frame

	# 3 тоста — очередь полна, life-tween у каждого создан.
	for i in 3:
		layer.toast("ТОСТ %d" % i)
		await process_frame
	_eq(layer._items.size(), 3, "в очереди 3 тоста")
	for item in layer._items:
		_ok(item.get_meta("life_tween", null) is Tween, "у тоста сохранён life-tween")

	var first = layer._items[0]
	var first_life = first.get_meta("life_tween", null)
	_ok(first_life is Tween and (first_life as Tween).is_valid(),
		"life-tween первого тоста активен до вытеснения")

	# 4-й тост вытесняет первый: его tween обязан быть убит в том же кадре.
	layer.toast("ТОСТ 3")
	_ok(first.is_queued_for_deletion(), "вытесненный тост поставлен на удаление")
	_ok(first_life is Tween and not (first_life as Tween).is_valid(),
		"life-tween вытесненного тоста убит (не сработает на freed-узле)")
	_eq(layer._items.size(), 3, "после вытеснения в очереди 3 живых тоста")
	_ok(not layer._items.has(first), "вытесненный тост убран из _items")

	# Внешне удалённый/невалидный элемент не должен застревать в _items.
	layer._items.resize(layer._items.size() + 1)  # null-элемент
	_ok(layer._items.has(null), "в _items добавлен невалидный элемент (null)")
	layer._relayout()
	_ok(not layer._items.has(null), "_relayout вычищает невалидные элементы")

	# Догоняем до 6 тостов и прокручиваем весь жизненный цикл (> 3.45 с).
	layer.toast("ТОСТ 4")
	await process_frame
	layer.toast("ТОСТ 5")
	await process_frame
	_eq(layer._items.size(), 3, "очередь ограничена тремя тостами")

	await create_timer(4.2).timeout
	_eq(layer._items.size(), 0, "_items пуст после истечения всех тостов")
	_eq(layer.get_child_count(), 0, "все узлы тостов освобождены")

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_fails += 1
	print("FAIL: %s" % message)


func _eq(actual, expected, message: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_fails += 1
	print("FAIL: %s — получено %s, ожидалось %s" % [message, actual, expected])
