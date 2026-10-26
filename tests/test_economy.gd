extends SceneTree
## Headless-тесты экономики v2: стартовые статы, лоты/капы, SLA, канал,
## таймеры, время передачи, выплата, выбор мини-игры, данные, прогрессия.
## Запуск: godot --headless --path . --script tests/test_economy.gd

const E := preload("res://scripts/core/economy.gd")
const D := preload("res://scripts/autoload/data.gd")
const G := preload("res://scripts/autoload/game.gd")
const EPS := 0.0001

var _checks: int = 0
var _fails: int = 0
var _case: String = ""


func _init() -> void:
	await process_frame
	_test_data()
	_test_start_stats()
	_test_levels_and_caps()
	_test_sla_rules()
	_test_channel_and_timers()
	_test_transfer_time()
	_test_payout()
	_test_udp_chance()
	_test_send_minigame()
	_test_attack_tier()
	_test_score()
	_test_progression()
	_test_meta_awards()
	_finish()


# --- данные ---------------------------------------------------------------

func _test_data() -> void:
	_set_case("data")
	var data = root.get_node_or_null("Data")
	if data == null:
		_fail("autoload Data недоступен")
		return
	_ok(not data.balance.is_empty(), "balance.json прочитан")
	_ok(data.types.has("text"), "тип text есть")
	var video: Dictionary = data.type_def("video")
	_eq(int(video.get("cells", 0)), 4, "video: 4 клетки")
	_approx(float(video.get("base_time_sec", 0.0)), 12.0, EPS, "video: base_time_sec 12")
	_approx(float(video.get("base_pay", 0.0)), 69.0, EPS, "video: base_pay 69")
	_approx(float(video.get("weight", 0.0)), 8.0, EPS, "video: weight 8")
	_approx(float(video.get("minigame_coeff", 0.0)), 8.0, EPS, "video: coeff 8")
	_approx(float(video.get("sla_loss", 0.0)), 16.0, EPS, "video: sla_loss 16")
	_eq(int(data.type_def("sound").get("cells", 0)), 2, "sound: 2 клетки")
	_eq(int(data.type_def("photo").get("cells", 0)), 3, "photo: 3 клетки")
	_eq(int(data.type_def("nope").get("cells", 0)), 1, "неизвестный тип → text (merge defaults)")

	var h1: Dictionary = data.hour_def(1)
	_eq(int(h1.get("files", 0)), 6, "H1: 6 файлов")
	_ok(not h1.has("request_cap"), "H1: request_cap удалён")
	_ok(not h1.has("recv_interval"), "H1: recv_interval удалён")
	_approx(float(h1.get("duration", 0.0)), 120.0, EPS, "H1: duration 120")
	_eq(int(h1.get("active_requests", 0)), 2, "H1: 2 активных запроса")
	_eq(int(h1.get("attacks", 0)), 0, "H1: 0 атак")
	_approx(float(h1.get("income_target", 0.0)), 100.0, EPS, "H1: цель дохода 100")
	_approx(float(h1.get("send_interval", 0.0)), 20.0, EPS, "H1: send_interval 20")
	var w1: Dictionary = h1.get("type_weights", {})
	_approx(float(w1.get("text", 0.0)), 0.70, EPS, "H1: text 70%")
	_approx(float(w1.get("sound", 0.0)), 0.30, EPS, "H1: sound 30%")
	_approx(float(w1.get("photo", 0.0)), 0.0, EPS, "H1: photo 0%")
	_approx(float(w1.get("video", 0.0)), 0.0, EPS, "H1: video 0%")
	var m1: Dictionary = h1.get("request_mix", {})
	_approx(float(m1.get("1", 0.0)), 0.76, EPS, "H1: 1 файл 76%")
	_approx(float(m1.get("2", 0.0)), 0.24, EPS, "H1: 2 файла 24%")
	_approx(float(m1.get("3", 0.0)), 0.0, EPS, "H1: 3 файла 0%")
	_approx(float(m1.get("4", 0.0)), 0.0, EPS, "H1: 4 файла 0%")
	_eq(int(data.hour_def(2).get("files", 0)), 6, "H2: 6 файлов")
	_eq(int(data.hour_def(9).get("files", 0)), 10, "H9: 10 файлов")
	_ok(not data.hour_def(9).has("request_cap"), "H9: request_cap удалён")
	_eq(int(data.hour_def(100).get("hour", 0)), 9, "hour > 9 → последняя строка")
	_eq(data.hours.size(), 9, "9 строк бюджета часов")
	var expected_files := [6, 6, 7, 8, 9, 9, 10, 10, 10]
	var expected_duration := [120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0, 360.0]
	var expected_send := [20.0, 24.0, 18.0, 24.0, 24.0, 24.0, 24.0, 24.0, 24.0]
	for i in range(9):
		var row: Dictionary = data.hour_def(i + 1)
		_eq(int(row.get("files", 0)), expected_files[i], "H%d: files" % (i + 1))
		_approx(float(row.get("duration", 0.0)), expected_duration[i], EPS,
			"H%d: duration" % (i + 1))
		_approx(float(row.get("send_interval", 0.0)), expected_send[i], EPS,
			"H%d: send_interval" % (i + 1))
		_ok(not row.has("request_cap"), "H%d: request_cap удалён" % (i + 1))
		_ok(not row.has("recv_interval"), "H%d: recv_interval удалён" % (i + 1))

	for row in data.hours:
		var weights: Dictionary = row.get("type_weights", {})
		var total := 0.0
		for key in ["text", "sound", "photo", "video"]:
			total += float(weights.get(key, 0.0))
		_approx(total, 1.0, EPS, "веса типов часа %d суммируются в 1.0" % int(row.get("hour", 0)))

	var lots: Array = data.lot_defs()
	_eq(lots.size(), 9, "ровно 9 лотов")
	var expected_ids := ["lot_slots", "lot_speed", "lot_sla", "lot_shield",
		"lot_money", "lot_folder", "lot_channel", "lot_timer", "lot_udp"]
	var expected_max := [4, 6, 4, 3, 8, 5, 6, 5, 4]
	var prices_sum := 0
	for i in range(expected_ids.size()):
		var lot: Dictionary = data.lot_def(str(expected_ids[i]))
		_ok(not lot.is_empty(), "лот %s есть" % str(expected_ids[i]))
		_eq(str(lot.get("id", "")), str(expected_ids[i]), "id лота %d" % i)
		_eq(int(lot.get("max_level", 0)), int(expected_max[i]), "max_level %s" % str(expected_ids[i]))
		_eq((lot.get("weight_by_hour", []) as Array).size(), 9, "weight_by_hour %s: 9 значений" % str(expected_ids[i]))
		var lot_prices: Array = lot.get("prices", [])
		_eq(lot_prices.size(), int(lot.get("max_level", 0)), "prices %s по числу уровней" % str(expected_ids[i]))
		for price in lot_prices:
			prices_sum += int(price)
	_eq(prices_sum, 8825, "сумма цен всех лотов = 8 825")
	_eq(str(data.lot_def("lot_speed").get("effect", "")), "transfer_speed", "lot_speed effect")
	_eq(str(data.lot_def("lot_channel").get("effect", "")), "channel_capacity", "lot_channel effect")
	var udp_lot: Dictionary = data.lot_def("lot_udp")
	_eq(str(udp_lot.get("effect", "")), "udp_success", "lot_udp effect")
	_approx(float(udp_lot.get("value", 0.0)), 0.10, EPS, "lot_udp value = 0.10")
	_eq(udp_lot.get("prices", []).size(), 4, "4 цены lot_udp")
	var udp_prices: Array = udp_lot.get("prices", [])
	_eq([int(udp_prices[0]), int(udp_prices[1]), int(udp_prices[2]), int(udp_prices[3])],
		[60, 120, 210, 350], "цены lot_udp")
	_ok(data.lot_def("lot_nope").is_empty(), "неизвестный лот → {}")
	_approx(float(data.constants.get("udp_success_base", 0.0)), 0.40, EPS,
		"constants.udp_success_base = 0.40")
	_approx(float(data.constants.get("udp_success_max", 0.0)), 0.80, EPS,
		"constants.udp_success_max = 0.80")
	_approx(float(data.constants.get("udp_fail_sla", 0.0)), -3.0, EPS,
		"constants.udp_fail_sla = -3")
	_approx(float(data.constants.get("udp_retry_cooldown_sec", 0.0)), 4.0, EPS,
		"constants.udp_retry_cooldown_sec = 4")

	var rules: Dictionary = data.shop_rules()
	_eq(int(rules.get("offers", 0)), 3, "shop_rules.offers = 3")
	_eq(int(rules.get("max_rerolls", 0)), 3, "shop_rules.max_rerolls = 3")
	_eq((rules.get("reroll_costs", []) as Array).size(), 3, "3 цены реролла")

	var dots: Dictionary = data.minigame_def("dots")
	_eq((dots.get("tiers", []) as Array).size(), 3, "dots: 3 ступени")
	for gid in ["dots", "sound", "text", "video", "photo", "maze", "junk", "ddos", "phishing", "ransomware"]:
		_ok(not data.minigame_def(gid).is_empty(), "мини-игра %s есть" % gid)
	_ok(not (data.minigames.get("games", {}) as Dictionary).has("wires"), "wires удалена")
	var sel: Dictionary = data.minigame_selection()
	_eq((sel.get("order", []) as Array).size(), 6, "send order: 6 игр")
	var sums: Array = sel.get("achievable_sums", [])
	_eq(sums.size(), 27, "27 достижимых сумм (1-4 файла)")
	_eq(int(sel.get("max_index", -1)), 26, "max_index = 26")
	_eq((sel.get("rank_games", []) as Array).size(), 27, "rank_games: 27 значений")
	_eq((sel.get("tier_max_rank", []) as Array).size(), 2, "tier_max_rank: 2 границы")
	var coeff: Dictionary = sel.get("coeff", {})
	_eq(int(coeff.get("video", 0)), 8, "coeff video = 8 в selection")
	_eq((data.attack_def("ddos").get("tiers", []) as Array).size(), 4, "ddos: 4 ступени")

	var grid_rules: Dictionary = data.grid_rules()
	_eq((grid_rules.get("folder_dims", []) as Array).size(), 6, "6 размеров сетки")
	_eq((grid_rules.get("shapes", {}) as Dictionary).size(), 26, "26 фигур (моно/домино/три/тетромино)")
	var s4: Dictionary = data.shape_def("S4")
	_eq((s4.get("cells", []) as Array).size(), 4, "S4: 4 клетки")
	_ok(data.shape_def("O1").size() > 0, "O1 есть")
	_ok(data.tr("ui.title") != "ui.title", "строки читаются")
	_ok(not str(data.folder_name()).is_empty(), "folder_name")


# --- стартовые статы -------------------------------------------------------

func _test_start_stats() -> void:
	_set_case("start_stats")
	var game = G.new()
	game.start_new_run(1)
	_eq(int(game.money), 50, "старт: money = 50")
	_approx(float(game.sla), 60.0, EPS, "старт: SLA = 60")
	_approx(game.sla_cap(), 60.0, EPS, "старт: кап SLA = 60")
	_eq(game.hour, 1, "старт: hour = 1")
	_eq(game.connection_slots(), 1, "старт: 1 слот")
	_approx(game.channel_capacity(), 10.0, EPS, "старт: канал 10")
	_eq(game.buffer_limit(), 6, "старт: буфер 6")
	_approx(game.request_timer(), 30.0, EPS, "старт: таймер запроса 30")
	_approx(game.packet_timer(), 20.0, EPS, "старт: таймер пакета 20")
	_approx(game.money_mult(), 1.0, EPS, "старт: money_mult 1.0")
	_approx(game.speed_mult(), 1.0, EPS, "старт: speed_mult 1.0")
	_eq(game.shield_max(), 0, "старт: 0 зарядов щита")
	_eq(game.shield_charges, 0, "старт: заряды щита = 0")
	var dims: Vector2i = game.folder_dims()
	_eq(dims.x, 5, "старт: сетка 5 столбцов")
	_eq(dims.y, 4, "старт: сетка 4 строки")
	_eq(game.level("connection_slots"), 0, "level(connection_slots) = 0")
	_eq(game.level("slot_level"), 0, "level(slot_level) = 0")
	_ok(game.upgrades.is_empty(), "старт: upgrades пусты")
	_eq(game.shop_offers.size(), 0, "старт: офферов нет")
	_eq(game.shop_rerolls, 0, "старт: рероллов 0")
	game.free()


func _test_levels_and_caps() -> void:
	_set_case("levels/caps")
	var game = G.new()
	game.start_new_run(2)

	game.set_lot_level("lot_slots", 4)
	_eq(game.level("lot_slots"), 4, "lot_slots = 4")
	_eq(game.level("slot_level"), 4, "агрегат slot_level = 4")
	_eq(int(game.upgrades.get("lot_slots", -1)), 4, "upgrades[lot_slots] = 4")
	_eq(game.connection_slots(), 5, "4 уровня → 5 слотов")

	game.set_lot_level("lot_speed", 6)
	_eq(game.level("speed_level"), 6, "speed_level = 6")
	_approx(game.speed_mult(), 0.531441, 0.0005, "pow(0.90, 6) ≈ 0.531")
	_approx(E.speed_mult(6), pow(0.90, 6.0), EPS, "speed_mult = pow(0.90, 6) без ^")

	game.set_lot_level("lot_sla", 4)
	_approx(game.sla_cap(), 220.0, EPS, "4 уровня ИБП → кап 220")
	_approx(game.sla, 220.0, EPS, "ИБП сразу добавляет +40 за уровень (60 → 220)")
	game.add_sla(1000.0)
	_approx(game.sla, 220.0, EPS, "add_sla не выше динамического капа 220")

	game.set_lot_level("lot_money", 8)
	_approx(game.money_mult(), 1.4, EPS, "8 уровней контракта → ×1.4")
	_approx(E.money_mult({"money_level": 4}), 1.2, EPS, "Economy.money_mult(level 4) = 1.2")

	game.set_lot_level("lot_folder", 5)
	var dims: Vector2i = game.folder_dims()
	_eq(dims.x, 9, "folder level 5: 9 столбцов")
	_eq(dims.y, 6, "folder level 5: 6 строк")
	game.set_lot_level("lot_folder", 1)
	dims = game.folder_dims()
	_eq(dims.x, 6, "folder level 1: 6×4 → 6 столбцов")
	_eq(dims.y, 4, "folder level 1: 6×4 → 4 строки")

	game.set_lot_level("lot_channel", 6)
	_approx(game.channel_capacity(), 46.0, EPS, "6 уровней канала → 46")
	_eq(game.buffer_limit(), 12, "6 уровней канала → буфер 12")

	game.set_lot_level("lot_timer", 5)
	_approx(game.request_timer(), 65.0, EPS, "5 уровней таймера → 65")
	game.set_lot_level("lot_timer", 99)
	_eq(game.level("lot_timer"), 5, "уровень клампится max_level")

	game.set_lot_level("lot_shield", 3)
	_eq(game.shield_max(), 3, "3 уровня заземления → 3 заряда")
	_eq(game.shield_charges, 3, "покупка сразу заряжает щит")

	# Сетка уровней 0..5 из таблицы.
	var expected := [[5, 4], [6, 4], [7, 5], [8, 5], [8, 6], [9, 6]]
	for lvl in range(6):
		game.set_lot_level("lot_folder", lvl)
		var d: Vector2i = game.folder_dims()
		_eq(d.x, int(expected[lvl][0]), "folder dims[%d].x" % lvl)
		_eq(d.y, int(expected[lvl][1]), "folder dims[%d].y" % lvl)
	game.free()


func _test_sla_rules() -> void:
	_set_case("sla_rules")
	var game = G.new()
	game.start_new_run(3)
	game.sla = 30.0
	var after: float = game.regen_sla_for_hour()
	_approx(after, 45.0, EPS, "regen_sla_for_hour: 30 + 15 = 45")
	_approx(float(game.sla), 45.0, EPS, "SLA обновлён после регена")
	game.sla = 55.0
	game.add_sla(100.0)
	_approx(float(game.sla), 60.0, EPS, "add_sla клампится текущим капом 60")
	game.set_lot_level("lot_sla", 1)
	game.sla = 90.0
	game.hour = 2
	game.regen_sla_for_hour()
	_approx(float(game.sla), 100.0, EPS, "реген не превышает кап 100")
	game.regen_sla_for_hour()
	_approx(float(game.sla), 100.0, EPS, "повторный реген в том же часу — no-op")

	# SLA 0 во время часа = поражение забега.
	var reasons: Array = []
	game.run_ended.connect(func(reason): reasons.append(str(reason)))
	game.phase = &"hour"
	game.add_sla(-999.0)
	_approx(float(game.sla), 0.0, EPS, "SLA падает до 0")
	_eq(str(game.phase), "results", "SLA 0 → фаза results")
	_eq(reasons.size(), 1, "run_ended эмитится один раз")
	if reasons.size() == 1:
		_eq(str(reasons[0]), "sla", "причина поражения sla")
	game.free()


func _test_channel_and_timers() -> void:
	_set_case("channel/timers")
	_approx(E.channel_capacity({}), 10.0, EPS, "capacity base 10")
	_approx(E.channel_capacity({"channel_level": 1}), 16.0, EPS, "capacity +1 = 16")
	_approx(E.channel_capacity({"channel": 6}), 46.0, EPS, "capacity +6 = 46")
	_approx(E.channel_capacity({"lot_channel": 3}), 28.0, EPS, "capacity по id лота")
	_approx(E.channel_factor(0.0, {}), 1.0, EPS, "пустой канал → factor 1")
	_approx(E.channel_factor(46.0, {"channel_level": 6}), 1.0, EPS, "load = capacity → factor 1")
	_approx(E.channel_factor(92.0, {"channel_level": 6}), 2.0, EPS, "load ×2 → factor 2")
	_approx(E.channel_factor(100.0, 10.0), 10.0, EPS, "factor по числу capacity")
	_approx(E.channel_load(1, 5, [8, 8], {}), 16.0, EPS, "2 видео в передаче = 16")
	_approx(E.channel_load(1, 0, [1, 2, 4, 8], {}), 15.0, EPS, "сумма весов 1/2/4/8")
	_approx(E.channel_load(1, 5, [-5, 3], {}), 3.0, EPS, "отрицательный вес клампится")
	_eq(E.buffer_limit({}), 6, "буфер base 6")
	_eq(E.buffer_limit({"channel_level": 6}), 12, "буфер 6 → 12")
	_eq(E.buffer_limit({"channel_level": 99}), 12, "буфер cap 12")

	_approx(E.packet_timer(1, {}), 20.0, EPS, "packet timer H1 = 20")
	_approx(E.packet_timer(9, {"timer_level": 5}), 20.0, EPS, "packet timer не меняется")
	_approx(E.request_timer(1, {}), 30.0, EPS, "request timer base 30")
	_approx(E.request_timer(5, {"timer_level": 1}), 37.0, EPS, "request timer +1 = 37")
	_approx(E.request_timer(9, {"timer_level": 5}), 65.0, EPS, "request timer max 65")
	_approx(E.request_timer(9, {"timer_level": 99}), 65.0, EPS, "request timer cap 65")
	_approx(E.request_timer(1, {"lot_timer": 2}), 44.0, EPS, "request timer по id лота")


func _test_transfer_time() -> void:
	_set_case("transfer_time")
	_approx(E.recv_transfer_time({"base_time_sec": 3}, 1.0, 0), 3.0, EPS, "text 3 с")
	_approx(E.recv_transfer_time({"base_time_sec": 5}, 1.0, 0), 5.0, EPS, "sound 5 с")
	_approx(E.recv_transfer_time({"base_time_sec": 8}, 1.0, 0), 8.0, EPS, "photo 8 с")
	_approx(E.recv_transfer_time({"base_time_sec": 12}, 1.0, 0), 12.0, EPS, "video 12 с")
	_approx(E.recv_transfer_time({"base_time_sec": 12}, 1.0, 1), 12.0 * 0.90, EPS, "speed 1 → ×0.90")
	_approx(E.recv_transfer_time({"base_time_sec": 12}, 2.0, 0), 24.0, EPS, "channel factor 2")
	_approx(E.recv_transfer_time({"base_time_sec": 8}, 1.0, 2), 8.0 * pow(0.90, 2.0), EPS, "speed 2")
	_approx(E.send_transfer_time({"base_time_sec": 12}, 1.0, 0, "tcp"), 12.0, EPS, "TCP ×1.0")
	_approx(E.send_transfer_time({"base_time_sec": 12}, 1.0, 0, "udp"), 9.6, EPS, "UDP ×0.8")
	_approx(E.send_transfer_time({"base_time_sec": 12}, 1.0, 0, &"UDP"), 9.6, EPS, "UDP StringName")
	_approx(E.recv_time({"base_time_sec": 8}, 1.0, {"speed_level": 2}), 8.0 * pow(0.90, 2.0), EPS, "legacy recv_time + speed")
	_approx(E.send_time({"base_time_sec": 12}, 1.0, {"speed_level": 1}), 12.0 * 0.90, EPS, "legacy send_time")
	_approx(E.recv_time({"recv_time": 2.0}, 1.0, {}), 2.0, EPS, "legacy поле recv_time")


func _test_payout() -> void:
	_set_case("payout")
	# 100 × 0.8 × 1.0 × 1.15 × 1.15 × 1.1 = 116.38 → 116
	_eq(E.payout(100.0, 2, 15.0, 30.0, 1.0, "tcp", 5, {}), 116, "полный TCP-пример (multi 1.15)")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 0.5, "udp", 0, {}), 64, "quality 0.5, udp ×0.85")
	_eq(E.payout(100.0, 3, 30.0, 30.0, 1.0, "udp", 0, {}), 111, "multi n=3 (1.30) × udp 0.85")
	_eq(E.payout(100.0, 1, 0.0, 30.0, 1.0, "udp", 0, {}), 51, "speed минимум 0.6")
	_eq(E.payout(100.0, 1, 60.0, 30.0, 1.0, "udp", 0, {}), 85, "time ratio клампится 1")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "TCP", 10, {}), 138, "TCP + streak 10")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, &"udp", 10, {}), 102, "streak +20% × udp 0.85")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "udp", 50, {}), 102, "streak cap 10")
	_eq(E.payout(100.0, 0, 30.0, 30.0, 1.0, "udp", 0, {}), 0, "n=0 → 0")
	_eq(E.payout(0.0, 1, 30.0, 30.0, 1.0, "udp", 0, {}), 0, "base 0 → 0")
	_eq(E.payout(100.0, 1, 30.0, 0.0, 1.0, "udp", 0, {}), 85, "timer_total 0 → полная скорость")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 2.0, "udp", 0, {}), 85, "quality клампится 1")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "udp", 0, {"money_level": 4}), 102, "money_mult +4 = ×1.2")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "udp", 0, {"money_level": 8}), 119, "money_mult +8 = ×1.4")
	_eq(E.payout(100.0, 1, 30.0, 30.0, 1.0, "udp", 0, {"lot_money": 2}), 94, "money_mult по id лота")

	# Float-точность: 1/3 и 2/3 не должны стать int/int.
	# 100 × (0.6 + 0.4/3) × 0.5 × 0.85 = 31.167 → 31.
	_eq(E.payout(100.0, 1, 1.0, 3.0, 0.0, "udp", 0, {}), 31, "time ratio 1/3 — float")
	# 100 × (0.6 + 0.8/3) × 0.5 × 0.85 = 36.833 → 37.
	_eq(E.payout(100.0, 1, 2.0, 3.0, 0.0, "udp", 0, {}), 37, "time ratio 2/3 — float")


func _test_udp_chance() -> void:
	_set_case("udp_chance")
	# База 40%, +10% за уровень «UDP-повторителя», кап 80%.
	_approx(E.udp_success_chance({}), 0.40, EPS, "Economy: база 40%")
	for lvl in range(5):
		_approx(E.udp_success_chance({"lot_udp": lvl}), 0.40 + 0.10 * float(lvl),
			EPS, "Economy: lot_udp=%d" % lvl)
	_approx(E.udp_success_chance({"udp_level": 3}), 0.70, EPS,
		"Economy: агрегат udp_level")
	_approx(E.udp_success_chance({"lot_udp": 9}), 0.80, EPS,
		"Economy: кап 80% при 9 уровнях")
	_approx(E.udp_success_chance({"udp": 7}), 0.80, EPS,
		"Economy: ключ udp тоже читается")
	_approx(E.udp_success_chance({}, 0.5, 0.2, 0.9), 0.5, EPS,
		"Economy: кастомная база без уровней")
	_approx(E.udp_success_chance({"lot_udp": 1}, 0.5, 0.2, 0.9), 0.7, EPS,
		"Economy: кастомный шаг")
	_approx(E.udp_success_chance({"lot_udp": 1}, 0.9, 0.2, 0.8), 0.9, EPS,
		"Economy: кап не ниже базы")
	_eq(E.UDP_SUCCESS_BASE, 0.40, "константа UDP_SUCCESS_BASE")
	_eq(E.UDP_SUCCESS_STEP, 0.10, "константа UDP_SUCCESS_STEP")
	_eq(E.UDP_SUCCESS_MAX, 0.80, "константа UDP_SUCCESS_MAX")

	# Game зеркалит Economy и обновляется покупкой лота.
	var game = G.new()
	game.start_new_run(9)
	_approx(game.udp_success_chance(), 0.40, EPS, "Game: старт 40%")
	game.set_lot_level("lot_udp", 2)
	_approx(game.udp_success_chance(), 0.60, EPS, "Game: lot_udp=2 → 60%")
	_approx(float(game.udp_success_chance()),
		E.udp_success_chance(game.upgrades), EPS, "Game и Economy совпадают")
	game.set_lot_level("lot_udp", 9)
	_approx(game.udp_success_chance(), 0.80, EPS, "Game: уровень клампится и кап 80%")
	_eq(int(game.upgrades.get("udp_level", -1)), 4, "агрегат udp_level = 4")
	game.free()


func _test_send_minigame() -> void:
	_set_case("send_minigame")
	var m: Dictionary = E.send_minigame_for([])
	_eq(int(m.get("sum", -1)), 0, "S=0")
	_eq(str(m.get("id", "")), "dots", "S=0 → dots")
	_eq(int(m.get("tier", 0)), 1, "S=0 → T1")
	m = E.send_minigame_for(["text"])
	_eq(int(m.get("sum", 0)), 1, "S=1")
	_eq(str(m.get("id", "")), "text", "S=1 → text")
	_eq(int(m.get("tier", 0)), 1, "S=1 → T1")
	_eq(int(m.get("index", -1)), 0, "S=1 → rank 0")
	m = E.send_minigame_for(["sound"])
	_eq(int(m.get("sum", 0)), 2, "S=2")
	_eq(str(m.get("id", "")), "sound", "S=2 → sound")
	_eq(int(m.get("tier", 0)), 1, "S=2 → T1")
	m = E.send_minigame_for(["TEXT", "Sound"])
	_eq(int(m.get("sum", 0)), 3, "S=3 (types lowercase)")
	_eq(str(m.get("id", "")), "dots", "S=3 → dots")
	_eq(int(m.get("tier", 0)), 1, "S=3 → T1")
	m = E.send_minigame_for(["photo"])
	_eq(int(m.get("sum", 0)), 4, "S=4")
	_eq(str(m.get("id", "")), "photo", "S=4 → photo")
	_eq(int(m.get("tier", 0)), 1, "S=4 → T1")
	m = E.send_minigame_for(["video"])
	_eq(int(m.get("sum", 0)), 8, "S=8")
	_eq(str(m.get("id", "")), "video", "S=8 → video")
	_eq(int(m.get("tier", 0)), 1, "S=8 → T1 (rank 7)")
	_eq(int(m.get("index", -1)), 7, "S=8 → rank 7")
	m = E.send_minigame_for(["video", "text"])
	_eq(int(m.get("sum", 0)), 9, "S=9")
	_eq(int(m.get("tier", 0)), 2, "S=9 → T2")
	_eq(str(m.get("id", "")), "dots", "S=9 → dots (rank 8)")
	m = E.send_minigame_for(["video", "video", "video"])
	_eq(int(m.get("sum", 0)), 24, "S=24")
	_eq(int(m.get("tier", 0)), 3, "S=24 → T3")
	_eq(str(m.get("id", "")), "dots", "S=24 → dots (rank 22)")
	_eq(int(m.get("index", -1)), 22, "S=24 → rank 22")
	m = E.send_minigame_for(["video", "video", "video", "video"])
	_eq(int(m.get("sum", 0)), 32, "S=32")
	_eq(int(m.get("tier", 0)), 3, "S=32 → T3")
	_eq(int(m.get("index", -1)), 26, "S=32 → rank 26")
	# ACHIEVABLE_SUMS: ровно 27 значений для 1–4 файлов.
	_eq(E.achievable_sums().size(), 27, "27 достижимых сумм")
	var alias: Dictionary = E.selection_for_sum(8)
	_eq(str(alias.get("id", "")), "video", "selection_for_sum(8) → video")
	_eq(int(alias.get("tier", 0)), 1, "selection_for_sum(8) → T1")
	_eq(int(alias.get("index", -1)), 7, "selection_for_sum(8) → rank 7")

	# Все 6 игр и все 3 ступени достижимы при 1–4 файлах.
	var pool := ["text", "sound", "photo", "video"]
	var ids: Dictionary = {}
	var tiers: Dictionary = {}
	for a in range(pool.size()):
		for b in range(pool.size()):
			for c in range(pool.size()):
				for d in range(pool.size()):
					for combo in [[pool[a]], [pool[a], pool[b]],
							[pool[a], pool[b], pool[c]],
							[pool[a], pool[b], pool[c], pool[d]]]:
						var r: Dictionary = E.send_minigame_for(combo)
						var id := str(r.get("id", ""))
						ids[id] = true
						tiers[int(r.get("tier", 0))] = true
						_ok(E.SEND_ORDER.has(id), "id %s из SEND_ORDER" % id)
	_eq(ids.size(), 6, "достижимы все 6 игр отправки")
	for t in [1, 2, 3]:
		_ok(tiers.has(t), "достижима ступень T%d" % t)
	_ok(not ids.has("junk"), "атакующие игры не выбираются для отправки")
	_ok(not ids.has("wires"), "wires больше не выбирается")


func _test_attack_tier() -> void:
	_set_case("attack_tier")
	_eq(E.attack_tier(1), 1, "H1 → T1")
	_eq(E.attack_tier(2), 1, "H2 → T1")
	_eq(E.attack_tier(3), 1, "H3 → T1")
	_eq(E.attack_tier(4), 2, "H4 → T2")
	_eq(E.attack_tier(5), 2, "H5 → T2")
	_eq(E.attack_tier(6), 3, "H6 → T3")
	_eq(E.attack_tier(7), 3, "H7 → T3")
	_eq(E.attack_tier(8), 4, "H8 → T4")
	_eq(E.attack_tier(9), 4, "H9 → T4")


func _test_score() -> void:
	_set_case("score")
	_eq(E.score(9, 8000, 200.0), 19000, "9 часов, 8000, SLA 200")
	_eq(E.score(0, 0, 0.0), 0, "нулевой забег")
	_eq(E.score(1, 500, 200.0), 3500, "1 час, 500, SLA 200")
	_eq(E.score(-3, -100, -50.0), 0, "отрицательные значения клампятся")


# --- прогрессия ------------------------------------------------------------

func _test_progression() -> void:
	_set_case("progression")
	var game = G.new()
	game.start_new_run(5)
	_ok(not game.feature_unlocked("shop"), "час 1: магазин закрыт")
	_ok(game.feature_unlocked("minigame_text"), "час 1: text открыт")
	_ok(not game.feature_unlocked("minigame_sound"), "час 1: sound закрыт")
	_ok(not game.feature_unlocked("attack_junk"), "час 1: junk закрыт")
	game.hour = 2
	_ok(game.feature_unlocked("shop"), "час 2: магазин открыт")
	_ok(game.feature_unlocked("minigame_sound"), "час 2: sound открыт")
	_ok(game.feature_unlocked("attack_ddos"), "час 2: ddos открыт")
	_ok(not game.feature_unlocked("attack_phishing"), "час 2: phishing закрыт")
	game.hour = 4
	_ok(game.feature_unlocked("minigame_video"), "час 4: video открыт")
	_ok(game.feature_unlocked("attack_ransomware"), "час 4: ransomware открыт")
	_ok(game.feature_unlocked("нет_такой_фичи"), "неизвестная фича считается открытой")
	_ok(not game.feature_unlocked("search"), "search закрыт до мета-награды")
	_ok(not game.feature_unlocked("shield"), "shield закрыт до мета-награды")
	_eq(game.award_meta_for_run(2).size(), 0, "2 часа: мета-наград нет")
	var at3 := game.award_meta_for_run(3)
	_ok(at3.has("survive_hour_3"), "3 часа: survive_hour_3 выдан")
	_ok(game.feature_unlocked("search"), "после 3 часов search открыт")
	_ok(not game.feature_unlocked("shield"), "shield ещё закрыт")
	_eq(game.award_meta_for_run(3).size(), 0, "повторно награда не выдаётся")
	var at5 := game.award_meta_for_run(5)
	_ok(at5.has("survive_hour_5"), "5 часов: survive_hour_5 выдан")
	_ok(game.feature_unlocked("shield"), "после 5 часов shield открыт")
	var at9 := game.award_meta_for_run(9)
	_ok(at9.has("complete_run"), "9 часов: complete_run выдан")
	game.reset_run()
	_ok(game.feature_unlocked("search"), "reset_run не стирает мету")
	game.start_new_run(6)
	_ok(game.feature_unlocked("shield"), "start_new_run не стирает мету")
	game.free()


func _test_meta_awards() -> void:
	_set_case("meta_awards")
	var game = G.new()
	var toasts: Array = []
	game.toast.connect(func(text): toasts.append(str(text)))
	game.start_new_run(11)
	toasts.clear()

	game.end_hour()
	_eq(int(game.stats.get("hours_done", 0)), 1, "1 час отработан")
	_ok(not game.feature_unlocked("search"), "после 1 часа search закрыт")
	_ok(not _has_unlock_toast(toasts), "1 час: тоста об открытии нет")

	game.end_hour()
	_eq(int(game.stats.get("hours_done", 0)), 2, "2 часа отработано")
	_ok(not game.feature_unlocked("search"), "после 2 часов search закрыт")

	game.end_hour()
	_eq(int(game.stats.get("hours_done", 0)), 3, "3 часа отработано")
	_ok(str(game.phase) != "results", "забег не завершён после 3 часов")
	_ok(game.feature_unlocked("search"), "после 3 часов search открыт")
	_ok(_has_unlock_toast(toasts), "3 часа: тост «Открыто: …» есть")
	_ok(game.run_meta_awards.has("survive_hour_3"), "run_meta_awards: survive_hour_3")
	_eq(game.run_meta_awards.size(), 1, "run_meta_awards без дублей")

	game.end_hour()
	_ok(not game.feature_unlocked("shield"), "после 4 часов shield ещё закрыт")

	game.end_hour()
	_eq(int(game.stats.get("hours_done", 0)), 5, "5 часов отработано")
	_ok(game.feature_unlocked("shield"), "после 5 часов shield открыт")
	_eq(game.run_meta_awards.size(), 2, "run_meta_awards: 2 награды")

	for i in range(4):
		game.end_hour()
	_eq(int(game.stats.get("hours_done", 0)), 9, "9 часов отработано")
	_eq(str(game.phase), "results", "9-й час завершает забег")
	_ok(game.meta_unlocks.has("complete_run"), "complete_run выдан на 9-м часе")
	_eq(game.run_meta_awards.size(), 3, "run_meta_awards: все 3 награды")

	var size_before: int = game.meta_unlocks.size()
	var again: Array = game.award_meta_for_run(9)
	_eq(again.size(), 0, "повторный award_meta_for_run(9) ничего не выдаёт")
	_eq(game.meta_unlocks.size(), size_before, "meta_unlocks не растёт при повторе")

	game.reset_run()
	_ok(game.run_meta_awards.is_empty(), "reset_run очищает run_meta_awards")
	_ok(game.feature_unlocked("search"), "reset_run: search остаётся открыт")
	game.start_new_run(12)
	_eq(int(game.stats.get("hours_done", 0)), 0, "новый забег: часы сброшены")
	_ok(game.feature_unlocked("shield"), "start_new_run: shield остаётся открыт")
	game.free()


func _has_unlock_toast(toasts: Array) -> bool:
	for text in toasts:
		if str(text).contains("Открыто"):
			return true
	return false


# --- assert-хелперы --------------------------------------------------------

func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message)
	return false


func _eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_fail("%s — получено %s, ожидалось %s" % [message, str(actual), str(expected)])
	return false


func _approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(actual - expected) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	print("test_economy: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_economy" if _fails == 0 else "FAIL test_economy")
	quit(0 if _fails == 0 else 1)
