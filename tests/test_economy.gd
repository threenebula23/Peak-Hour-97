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
	_test_progression(t)


func _test_channel(t) -> void:
	t.set_case("channel")
	# п.11: load = только активные передачи; слоты и фон не грузят канал.
	t.approx(E.channel_load(1, 2, [], {}), 0.0, EPS, "hour 1, 2 idle-слота → load 0")
	t.approx(E.channel_load(1, 4, [22, 22], {}), 44.0, EPS, "2 видео в передаче = 44 (слоты не влияют)")
	t.approx(E.channel_factor(44.0, {}), 1.0, EPS, "44/80 = 0.55 → factor не ниже 1.0")
	t.approx(E.channel_load(5, 4, [22, 22], {}), 44.0, EPS, "hour 5: только активные веса, без фона")
	t.approx(E.channel_load(9, 4, [22, 22, 22, 22], {}), 88.0, EPS, "4 видео в передаче = 88")
	t.approx(E.channel_factor(88.0, {}), 1.1, EPS, "88/80 → factor 1.1")
	t.approx(E.channel_factor(E.channel_load(1, 0, [], {}), {}), 1.0, EPS, "час 1, пустой канал → factor 1.0")
	t.approx(E.channel_factor(E.channel_load(9, 4, [], {}), {}), 1.0, EPS, "час 9, idle-слоты → factor 1.0")
	t.approx(E.channel_load(1, 0, [], {}), 0.0, EPS, "idle канал = 0")
	t.approx(E.channel_load(0, 0, [], {}), 0.0, EPS, "hour < 1 → idle 0")
	t.approx(E.channel_load(1, 0, [1.5, 2.5], {}), 4.0, EPS, "сумма весов активных передач")
	t.approx(E.channel_load(1, -3, [], {}), 0.0, EPS, "отрицательные слоты игнорируются")
	t.approx(E.channel_load(1, 0, [-5, 3], {}), 3.0, EPS, "отрицательный вес клампится")
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
	# п.10: grace h1 1.5, h2 1.35, h3 1.2, h4+ 1.0.
	t.approx(E.packet_timer(1, {}), 30.0, EPS, "packet hour 1 (20×1.5)")
	t.approx(E.packet_timer(2, {}), 26.325, EPS, "packet hour 2 (19.5×1.35)")
	t.approx(E.packet_timer(3, {}), 22.8, EPS, "packet hour 3 (19×1.2)")
	t.approx(E.packet_timer(4, {}), 18.5, EPS, "packet hour 4 (без grace)")
	t.approx(E.packet_timer(9, {}), 16.0, EPS, "packet hour 9")
	t.approx(E.packet_timer(40, {}), 12.0, EPS, "packet min clamp")
	t.approx(E.packet_timer(1, {"timer": 3}), 42.0, EPS, "packet +3 уровня (grace только на базу)")
	t.approx(E.packet_timer(1, {"timer": 250}), 999.0, EPS, "packet max clamp")
	t.approx(E.packet_timer(1, {"shop_timer": 1}), 34.0, EPS, "packet по id магазина")
	t.approx(E.request_timer(1, {}), 45.0, EPS, "request hour 1 (30×1.5)")
	t.approx(E.request_timer(2, {}), 39.825, EPS, "request hour 2 (29.5×1.35)")
	t.approx(E.request_timer(3, {}), 34.8, EPS, "request hour 3 (29×1.2)")
	t.approx(E.request_timer(4, {}), 28.5, EPS, "request hour 4 (без grace)")
	t.approx(E.request_timer(9, {}), 26.0, EPS, "request hour 9")
	t.approx(E.request_timer(40, {}), 20.0, EPS, "request min clamp")
	t.approx(E.request_timer(1, {"timer": 2}), 53.0, EPS, "request +2 уровня")
	t.approx(E.timer_grace(1), 1.5, EPS, "grace h1")
	t.approx(E.timer_grace(2), 1.35, EPS, "grace h2")
	t.approx(E.timer_grace(3), 1.2, EPS, "grace h3")
	t.approx(E.timer_grace(4), 1.0, EPS, "grace h4+")


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
	t.ok(data.unlocks.has("shop"), "progression.unlocks.shop прочитан")
	t.ok(data.meta_rewards.has("survive_hour_3"), "progression.meta_rewards прочитан")
	t.eq(int(data.unlocks.get("shop", {}).get("run_hour", 0)), 2, "shop открывается на часе 2")
	t.eq(int(data.unlocks.get("attack_ransomware", {}).get("run_hour", 0)), 4, "ransomware открывается на часе 4")
	t.ok(data.shop_item("shop_sla").size() > 0, "shop_sla есть в каталоге")
	t.eq(int(data.shop_item("shop_sla").get("value", 0)), 24, "shop_sla value = 24")
	t.eq(int(data.shop_item("shop_sla").get("max_level", 0)), 3, "shop_sla max_level = 3")
	var available = data.available_shop()
	t.ok(available is Array, "available_shop() — массив")
	t.ok(not str(data.folder_name()).is_empty(), "folder_name() не пуст")
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
	t.approx(float(game.sla), 128.0, 0.0001, "start_new_run: sla=128")
	t.eq(int(game.hour), 1, "start_new_run: hour=1")
	game.add_sla(1000.0)
	t.approx(float(game.sla), 200.0, 0.0001, "add_sla(1000) не поднимает SLA выше 200")
	game.free()


func _test_progression(t) -> void:
	t.set_case("progression")
	# run_tests.gd запускается из _init до _ready автолоадов — форсируем Data.
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var data = (loop as SceneTree).root.get_node_or_null("Data")
		if data != null and data.get("unlocks") is Dictionary and (data.unlocks as Dictionary).is_empty():
			data.load_all()
	var game = G.new()
	game.start_new_run(5)
	# run_hour-гейты.
	t.ok(not game.feature_unlocked("shop"), "час 1: магазин закрыт")
	t.ok(game.feature_unlocked("minigame_text"), "час 1: text открыт")
	t.ok(not game.feature_unlocked("minigame_sound"), "час 1: sound закрыт")
	t.ok(not game.feature_unlocked("minigame_photo"), "час 1: photo закрыт")
	t.ok(not game.feature_unlocked("attack_junk"), "час 1: junk закрыт")
	game.hour = 2
	t.ok(game.feature_unlocked("shop"), "час 2: магазин открыт")
	t.ok(game.feature_unlocked("minigame_sound"), "час 2: sound открыт")
	t.ok(game.feature_unlocked("attack_ddos"), "час 2: ddos открыт")
	t.ok(not game.feature_unlocked("attack_phishing"), "час 2: phishing закрыт")
	game.hour = 4
	t.ok(game.feature_unlocked("minigame_video"), "час 4: video открыт")
	t.ok(game.feature_unlocked("attack_ransomware"), "час 4: ransomware открыт")
	t.ok(game.feature_unlocked("нет_такой_фичи"), "неизвестная фича считается открытой")
	# Мета-гейты.
	t.ok(not game.feature_unlocked("search"), "search закрыт до мета-награды")
	t.ok(not game.feature_unlocked("shield"), "shield закрыт до мета-награды")
	t.eq(game.award_meta_for_run(2).size(), 0, "2 часа: мета-наград нет")
	var at3 := game.award_meta_for_run(3)
	t.ok(at3.has("survive_hour_3"), "3 часа: survive_hour_3 выдан")
	t.ok(game.feature_unlocked("search"), "после 3 часов search открыт")
	t.ok(not game.feature_unlocked("shield"), "shield ещё закрыт")
	t.eq(game.award_meta_for_run(3).size(), 0, "повторно награда не выдаётся")
	var at5 := game.award_meta_for_run(5)
	t.ok(at5.has("survive_hour_5"), "5 часов: survive_hour_5 выдан")
	t.ok(game.feature_unlocked("shield"), "после 5 часов shield открыт")
	var at9 := game.award_meta_for_run(9)
	t.ok(at9.has("complete_run"), "9 часов: complete_run выдан")
	t.ok(game.feature_unlocked("minigame_advanced"), "после 9 часов advanced открыт")
	# Мета переживает reset_run и сохраняется/загружается.
	game.reset_run()
	t.ok(game.feature_unlocked("search"), "reset_run не стирает мету")
	game.start_new_run(6)
	t.ok(game.feature_unlocked("shield"), "start_new_run не стирает мету")
	game.free()
