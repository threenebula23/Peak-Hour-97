extends RefCounted
## Тесты экономики: канал, таймеры, мини-игры, выплата, итоговый счёт.

const E := preload("res://scripts/core/economy.gd")
const D := preload("res://scripts/autoload/data.gd")
const G := preload("res://scripts/autoload/game.gd")
const EPS := 0.0001


func run(t) -> void:
	_test_channel(t)
	_test_channel_time(t)
	_test_timers(t)
	_test_minigame(t)
	_test_payout(t)
	_test_score(t)
	_test_data(t)
	_test_game_defaults(t)


func _test_channel(t) -> void:
	t.set_case("channel")
	t.approx(E.channel_load(1, 2, [], {}), 26.0, EPS, "hour 1, 2 слота")
	t.approx(E.channel_factor(26.0, {}), 1.0, EPS, "26/80 → factor 1.0 (час 1 не нагружен)")
	t.approx(E.channel_load(1, 4, [22, 22], {}), 86.0, EPS, "hour 1, 4 слота, веса 22+22")
	t.approx(E.channel_factor(86.0, {}), 1.075, EPS, "час 1, полный канал → factor > 1")
	t.approx(E.channel_load(5, 4, [22, 22], {}), 102.0, EPS, "hour 5, 4 слота, веса 22+22")
	t.approx(E.channel_factor(102.0, {}), 1.275, EPS, "102/80 → factor 1.275")
	t.approx(E.channel_factor(E.channel_load(1, 0, [], {}), {}), 1.0, EPS, "час 1, пустой канал → factor 1.0")
	t.approx(E.channel_factor(E.channel_load(9, 0, [], {}), {}), 1.0, EPS, "час 9, пустой канал → factor 1.0")
	t.approx(E.channel_load(1, 0, [], {}), 10.0, EPS, "база канала")
	t.approx(E.channel_load(0, 0, [], {}), 10.0, EPS, "hour < 1 клампится")
	t.approx(E.channel_load(1, 0, [1.5, 2.5], {}), 14.0, EPS, "сумма весов")
	t.approx(E.channel_load(1, -3, [], {}), 10.0, EPS, "отрицательные слоты клампятся")
	t.approx(E.channel_load(1, 0, [-5, 3], {}), 13.0, EPS, "отрицательный вес клампится")
	t.approx(E.channel_capacity({}), 80.0, EPS, "capacity base")
	t.approx(E.channel_capacity({"channel": 2}), 130.0, EPS, "capacity +2 уровня")
	t.approx(E.channel_capacity({"shop_channel": 3}), 155.0, EPS, "capacity по id магазина")
	t.approx(E.channel_capacity({"channel": 4}), 180.0, EPS, "максимум 180 (80 + 4×25)")
	t.approx(E.channel_factor(180.0, {"channel": 2}), 180.0 / 130.0, EPS, "factor по upgrades")
	t.approx(E.channel_factor(10.0, {"channel": 4}), 1.0, EPS, "factor не ниже 1")
	t.approx(E.channel_factor(102.0, 80.0), 1.275, EPS, "factor по числу capacity")


func _test_channel_time(t) -> void:
	t.set_case("channel_time")
	var def := {"recv_time": 2.0, "send_time": 3.0}
	t.approx(E.recv_time(def, 1.02, {}), 2.04, EPS, "recv_time × factor")
	t.approx(E.send_time(def, 1.02, {}), 3.06, EPS, "send_time × factor")
	t.approx(E.recv_time(def, 1.0, {}), 2.0, EPS, "recv_time factor 1")
	t.approx(E.send_time({"recv_time": 2.0}, 1.0, {}), 0.0, EPS, "нет send_time → 0")


func _test_timers(t) -> void:
	t.set_case("timers")
	t.approx(E.packet_timer(1, {}), 20.0, EPS, "packet hour 1")
	t.approx(E.packet_timer(9, {}), 16.0, EPS, "packet hour 9")
	t.approx(E.packet_timer(40, {}), 12.0, EPS, "packet min clamp")
	t.approx(E.packet_timer(1, {"timer": 3}), 32.0, EPS, "packet +3 уровня")
	t.approx(E.packet_timer(1, {"timer": 250}), 999.0, EPS, "packet max clamp")
	t.approx(E.packet_timer(1, {"shop_timer": 1}), 24.0, EPS, "packet по id магазина")
	t.approx(E.request_timer(1, {}), 30.0, EPS, "request hour 1")
	t.approx(E.request_timer(9, {}), 26.0, EPS, "request hour 9")
	t.approx(E.request_timer(40, {}), 20.0, EPS, "request min clamp")
	t.approx(E.request_timer(1, {"timer": 2}), 38.0, EPS, "request +2 уровня")


func _test_minigame(t) -> void:
	t.set_case("minigame")
	t.approx(E.minigame_difficulty([]), 1.0, EPS, "пустой набор → 1.0")
	t.approx(E.minigame_difficulty(["text", "video"]), 2.5, EPS, "text+video = 2.5")
	t.approx(E.minigame_difficulty(["text", "text", "text"]), 1.0, EPS, "3 text = 1.0")
	t.approx(E.minigame_difficulty(["unknown"]), 1.0, EPS, "неизвестный тип = text")
	t.eq(E.minigame_type([]), "text", "пустой набор → text")
	t.eq(E.minigame_type(["text", "text", "text"]), "text", "3 text → text")
	t.eq(E.minigame_type(["text", "video"]), "photo", "avg 2.5 → photo")
	t.eq(E.minigame_type(["text", "sound"]), "sound", "avg 1.5 → sound")
	t.eq(E.minigame_type(["text", "photo"]), "sound", "avg 2.0 → sound")
	t.eq(E.minigame_type(["sound", "photo"]), "photo", "avg 2.5 → photo")
	t.eq(E.minigame_type(["photo", "video"]), "video", "avg 3.5 → video")
	t.eq(E.minigame_type(["video"]), "video", "video → video")
	t.eq(E.minigame_type(["sound"]), "sound", "sound → sound")
	t.eq(E.minigame_type(["photo"]), "photo", "photo → photo")


func _test_payout(t) -> void:
	t.set_case("payout")
	# base 100, n=2, 15/30, quality 1, tcp, streak 5:
	# 100 × 0.8 × 1.0 × 1.1 × 1.15 × 1.1 = 111.32 → 111
	t.eq(E.payout(100.0, 2, 15.0, 30.0, 1.0, "tcp", 5, {}), 111, "полный TCP-пример")
	t.eq(E.payout(100.0, 1, 30.0, 30.0, 0.5, "udp", 0, {}), 75, "quality 0.5, udp")
	t.eq(E.payout(100.0, 3, 30.0, 30.0, 1.0, "udp", 0, {}), 120, "multi n=3")
	t.eq(E.payout(100.0, 1, 0.0, 30.0, 1.0, "udp", 0, {}), 60, "speed минимум 0.6")
	t.eq(E.payout(100.0, 1, 60.0, 30.0, 1.0, "udp", 0, {}), 100, "time ratio клампится 1")
	t.eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "TCP", 10, {}), 138, "TCP + streak 10")
	t.eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, &"udp", 10, {}), 120, "streak +20%")
	t.eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "udp", 50, {}), 120, "streak cap 10")
	t.eq(E.payout(100.0, 0, 30.0, 30.0, 1.0, "udp", 0, {}), 0, "n=0 → 0")
	t.eq(E.payout(0.0, 1, 30.0, 30.0, 1.0, "udp", 0, {}), 0, "base 0 → 0")
	t.eq(E.payout(100.0, 1, 30.0, 0.0, 1.0, "udp", 0, {}), 100, "timer_total 0 → полная скорость")
	t.eq(E.payout(100.0, 1, 30.0, 30.0, 2.0, "udp", 0, {}), 100, "quality клампится 1")


func _test_score(t) -> void:
	t.set_case("score")
	t.eq(E.score(9, 12000, 250.0), 23500, "9 часов, 12000, SLA 250")
	t.eq(E.score(0, 0, 0.0), 0, "нулевой забег")
	t.eq(E.score(1, 500, 200.0), 3500, "1 час, 500, SLA 200")
	t.eq(E.score(-3, -100, -50.0), 0, "отрицательные значения клампятся")


func _test_data(t) -> void:
	t.set_case("data")
	var data = D.new()
	data.load_all()
	t.ok(not data.balance.is_empty(), "balance.json прочитан")
	t.ok(data.types.has("text"), "тип text есть")
	t.ok(data.types.size() >= 4, "минимум 4 типа файлов")
	var text_def = data.type_def("text")
	t.ok(text_def is Dictionary and not text_def.is_empty(), "type_def(text)")
	t.ok(not str(text_def.get("ext", "")).is_empty(), "у text есть ext")
	t.eq(str(data.type_def("nope").get("name_ru", "")), str(text_def.get("name_ru", "")), "неизвестный тип → text")

	t.ok(not data.difficulty.is_empty(), "таблица сложности не пуста")
	var first = data.difficulty_for(1)
	t.eq(int(first.get("hour", 0)), 1, "difficulty_for(1)")
	var last_row = data.difficulty[data.difficulty.size() - 1]
	var beyond = data.difficulty_for(999)
	t.eq(int(beyond.get("hour", 0)), int(last_row.get("hour", 0)), "hour > max → последняя строка")

	t.ok(not data.shop.is_empty(), "магазин не пуст")
	var first_item = data.shop[0]
	var item_id := str(first_item.get("id", ""))
	var found = data.shop_item(item_id)
	t.eq(str(found.get("id", "")), item_id, "shop_item по id")
	t.eq(data.shop_item("нет_такого_товара").size(), 0, "неизвестный товар → {}")

	t.ok(not data.names.is_empty(), "names_ru.json прочитан")
	t.ok(not data.strings.is_empty(), "strings_ru.json прочитан")
	t.ok(data.tr("ui.title") != "ui.title", "вложенный ключ ui.title")
	t.ok(data.has_string("ui.title"), "has_string для вложенного ключа")
	t.ok(not data.has_string("точно.нет.ключа"), "has_string для отсутствующего ключа")
	t.eq(data.tr("точно.нет.ключа"), "точно.нет.ключа", "нет ключа → сам ключ")
	data.free()


func _test_game_defaults(t) -> void:
	t.set_case("game_defaults")
	var game = G.new()
	game.start_new_run()
	t.eq(int(game.money), 150, "start_new_run: money=150")
	t.approx(float(game.sla), 200.0, 0.0001, "start_new_run: sla=200")
	t.eq(int(game.hour), 1, "start_new_run: hour=1")
	game.add_sla(1000.0)
	t.approx(float(game.sla), 200.0, 0.0001, "add_sla(1000) не поднимает SLA выше 200")
	game.free()
