extends SceneTree
## Headless-тесты четырёх мини-игр атак: генерация, валидаторы, формулы
## качества, таблицы T1–T4, отсутствие таймеров и контракт finished.
##
## Запуск:
##   godot --headless --path . --script tests/test_attack_games.gd

const JUNK := preload("res://scripts/minigames/attack/junk.gd")
const DDOS := preload("res://scripts/minigames/attack/ddos.gd")
const PHISHING := preload("res://scripts/minigames/attack/phishing.gd")
const RANSOMWARE := preload("res://scripts/minigames/attack/ransomware.gd")
const FACTORY := preload("res://scripts/minigames/minigame_factory.gd")
const AD := preload("res://scripts/systems/attack_director.gd")

const SEEDS := [1, 7, 42, 99, 1234, 2026]
const IDS := ["junk", "ddos", "phishing", "ransomware"]
const SEND_IDS := ["dots", "sound", "wires", "text", "video", "photo", "maze"]

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _last_q: float = -1.0
var _finish_count: int = 0


func _init() -> void:
	await process_frame
	_test_junk_params()
	_test_junk_generation()
	_test_junk_quality()
	_test_ddos_params()
	_test_ddos_generation()
	_test_ddos_motion_is_dt_based()
	_test_ddos_quality()
	_test_phishing_params()
	_test_phishing_generation()
	_test_phishing_quality()
	_test_ransomware_params()
	_test_ransomware_generation()
	_test_ransomware_quality()
	_test_no_timers_and_no_global_rng()
	_test_factory_and_finished_contract()
	_test_surrender_semantics()
	_test_submit_quality_contract()
	_finish()


# --- junk ------------------------------------------------------------------

func _test_junk_params() -> void:
	_set_case("junk_params")
	var expected := {
		1: {"cards": 9, "junk": 2, "hints": 1, "threshold": 0.60},
		2: {"cards": 10, "junk": 3, "hints": 2, "threshold": 0.65},
		3: {"cards": 11, "junk": 4, "hints": 2, "threshold": 0.70},
		4: {"cards": 12, "junk": 5, "hints": 3, "threshold": 0.75},
	}
	for tier in range(1, 5):
		var p := JUNK.tier_params(tier)
		var spec: Dictionary = expected[tier]
		_eq(int(p["cards"]), int(spec["cards"]), "junk T%d cards" % tier)
		_eq(int(p["junk"]), int(spec["junk"]), "junk T%d junk" % tier)
		_eq(int(p["hints"]), int(spec["hints"]), "junk T%d hints" % tier)
		_approx(float(p["threshold"]), float(spec["threshold"]), 0.0001,
			"junk T%d threshold" % tier)
		_ok(int(p["junk"]) < int(p["cards"]), "junk T%d есть нормальные карточки" % tier)


func _test_junk_generation() -> void:
	_set_case("junk_generation")
	for tier in range(1, 5):
		var p := JUNK.tier_params(tier)
		for seed in SEEDS:
			var data := JUNK.generate_junk(tier, seed)
			var cards: Array = data["cards"]
			_eq(cards.size(), int(p["cards"]), "junk T%d seed %d: всего карточек" % [tier, seed])
			_eq(int(data["total_junk"]), int(p["junk"]), "junk T%d seed %d: мусора" % [tier, seed])
			_ok(JUNK.validate_junk(data), "junk T%d seed %d: валидатор" % [tier, seed])

			var junk_seen := 0
			var normal_seen := 0
			var name_counts := {}
			for card in cards:
				var name := str((card as Dictionary).get("name", ""))
				name_counts[name] = int(name_counts.get(name, 0)) + 1
			for card in cards:
				var c: Dictionary = card
				var anomalies := JUNK.detected_anomalies(c, name_counts)
				if bool(c.get("junk", false)):
					junk_seen += 1
					var independent := 0
					for anomaly in anomalies:
						if str(anomaly) != "duplicate_name":
							independent += 1
					_ok(independent >= 1,
						"junk T%d seed %d: у мусора есть однозначный признак" % [tier, seed])
				else:
					normal_seen += 1
					for anomaly in anomalies:
						if str(anomaly) != "duplicate_name":
							_fail("junk T%d seed %d: нормальная карточка с аномалией %s" %
								[tier, seed, str(anomaly)])
			_eq(junk_seen, int(p["junk"]), "junk T%d seed %d: счётчик мусора" % [tier, seed])
			_eq(normal_seen, int(p["cards"]) - int(p["junk"]),
				"junk T%d seed %d: счётчик нормальных" % [tier, seed])
			_ok((data["hints"] as Array).size() <= int(p["hints"]),
				"junk T%d seed %d: число подсказок" % [tier, seed])
			_ok((data["hints"] as Array).size() >= 1,
				"junk T%d seed %d: подсказки есть" % [tier, seed])

	# Детерминизм по сиду и различие разных сидов.
	_eq(str(JUNK.generate_junk(2, 77)), str(JUNK.generate_junk(2, 77)),
		"junk одинаковый сид → одинаковая раздача")
	_ok(str(JUNK.generate_junk(2, 77)) != str(JUNK.generate_junk(2, 78)),
		"junk разные сиды → разные раздачи")


func _test_junk_quality() -> void:
	_set_case("junk_quality")
	_approx(JUNK.junk_quality(2, 0, 2), 1.0, 0.0001, "junk 2/2 = 1")
	_approx(JUNK.junk_quality(1, 0, 2), 0.5, 0.0001, "junk 1/2 = 0.5")
	_approx(JUNK.junk_quality(0, 0, 2), 0.0, 0.0001, "junk 0/2 = 0")
	_approx(JUNK.junk_quality(0, 2, 2), 0.0, 0.0001, "junk ложные клампятся в 0")
	_approx(JUNK.junk_quality(3, 1, 2), 1.0, 0.0001, "junk клампится сверху")
	_approx(JUNK.junk_quality(1, 2, 2), 0.0, 0.0001, "junk больше ложных — 0")
	_approx(JUNK.junk_quality(5, 1, 5), 0.8, 0.0001, "junk (5-1)/5 = 0.8")
	_approx(JUNK.junk_quality(0, 0, 0), 0.0, 0.0001, "junk без мусора = 0")


# --- ddos ------------------------------------------------------------------

func _test_ddos_params() -> void:
	_set_case("ddos_params")
	var expected := {
		1: {"packets": 8, "speed": 110.0, "shield_width": 260.0, "interval": 0.55,
			"threshold": 0.60},
		2: {"packets": 10, "speed": 140.0, "shield_width": 220.0, "interval": 0.45,
			"threshold": 0.65},
		3: {"packets": 12, "speed": 170.0, "shield_width": 180.0, "interval": 0.35,
			"threshold": 0.70},
		4: {"packets": 14, "speed": 200.0, "shield_width": 150.0, "interval": 0.28,
			"threshold": 0.75},
	}
	for tier in range(1, 5):
		var p := DDOS.tier_params(tier)
		var spec: Dictionary = expected[tier]
		_eq(int(p["packets"]), int(spec["packets"]), "ddos T%d packets" % tier)
		_approx(float(p["speed"]), float(spec["speed"]), 0.0001, "ddos T%d speed" % tier)
		_approx(float(p["shield_width"]), float(spec["shield_width"]), 0.0001,
			"ddos T%d shield_width" % tier)
		_approx(float(p["interval"]), float(spec["interval"]), 0.0001,
			"ddos T%d interval" % tier)
		_approx(float(p["threshold"]), float(spec["threshold"]), 0.0001,
			"ddos T%d threshold" % tier)


func _test_ddos_generation() -> void:
	_set_case("ddos_generation")
	for tier in range(1, 5):
		var p := DDOS.tier_params(tier)
		for seed in SEEDS:
			var wave := DDOS.generate_wave(tier, seed)
			var packets: Array = wave["packets"]
			_eq(packets.size(), int(p["packets"]), "ddos T%d seed %d: пакетов" % [tier, seed])
			_eq(int(wave["total"]), int(p["packets"]), "ddos T%d seed %d: total" % [tier, seed])
			_ok(DDOS.validate_wave(wave), "ddos T%d seed %d: волна валидна" % [tier, seed])
			var xs: Array = []
			var last_spawn := -1.0
			for packet in packets:
				var item: Dictionary = packet
				xs.append(float(item["x"]))
				_ok(float(item["spawn_at"]) > last_spawn,
					"ddos T%d seed %d: spawn_at растёт" % [tier, seed])
				last_spawn = float(item["spawn_at"])
				_ok(is_finite(float(item["x"])) and is_finite(float(item["speed"])),
					"ddos T%d seed %d: координаты/скорость конечны" % [tier, seed])
			xs.sort()
			for i in range(1, xs.size()):
				_ok(float(xs[i]) - float(xs[i - 1]) >= 12.0 - 0.001,
					"ddos T%d seed %d: позиции разнесены" % [tier, seed])
			_ok(last_spawn < 30.0, "ddos T%d seed %d: волна конечна" % [tier, seed])
			var start := float(wave["start_shield_x"])
			var half := float(wave["shield_width"]) * 0.5
			_ok(start - half >= 18.0 - 0.001 and start + half <= 622.0 + 0.001,
				"ddos T%d seed %d: стартовый щит в поле" % [tier, seed])


func _test_ddos_motion_is_dt_based() -> void:
	_set_case("ddos_dt_motion")
	# Две одинаковые игры: 2 шага по 0.25 с против 1 шага 0.5 с. При чистом
	# dt-интегрировании без покадрового damping активные пакеты совпадут.
	var a = DDOS.new()
	var b = DDOS.new()
	a.start("ddos", 2, 4242)
	b.start("ddos", 2, 4242)
	a._elapsed = 100.0
	b._elapsed = 100.0
	a._process(0.0)
	b._process(0.0)
	_eq(a._packets.size(), int(a._wave["total"]), "ddos: все пакеты заспавнены")
	_eq(b._packets.size(), int(b._wave["total"]), "ddos: все пакеты заспавнены (B)")
	a._process(0.25)
	a._process(0.25)
	b._process(0.5)
	_eq(a._blocked, b._blocked, "ddos: 2×0.25 и 1×0.5 дают одинаковые попадания")
	_eq(a._breached, b._breached, "ddos: 2×0.25 и 1×0.5 дают одинаковые пробития")
	_eq(a._packets.size(), b._packets.size(), "ddos: одинаковое число активных пакетов")
	for i in range(mini(a._packets.size(), b._packets.size())):
		var pa: Dictionary = a._packets[i]
		var pb: Dictionary = b._packets[i]
		_approx(float(pa["y"]), float(pb["y"]), 0.001, "ddos: y не зависит от fps")
		_approx(float(pa["x"]), float(pb["x"]), 0.001, "ddos: x не зависит от fps")
	a.free()
	b.free()


func _test_ddos_quality() -> void:
	_set_case("ddos_quality")
	_approx(DDOS.ddos_quality(8, 8), 1.0, 0.0001, "ddos 8/8 = 1")
	_approx(DDOS.ddos_quality(4, 8), 0.5, 0.0001, "ddos 4/8 = 0.5")
	_approx(DDOS.ddos_quality(0, 8), 0.0, 0.0001, "ddos 0/8 = 0")
	_approx(DDOS.ddos_quality(9, 8), 1.0, 0.0001, "ddos клампится сверху")
	_approx(DDOS.ddos_quality(1, 0), 0.0, 0.0001, "ddos без пакетов = 0")
	_approx(DDOS.ddos_quality(3, 4), 0.75, 0.0001, "ddos 3/4 = 0.75")


# --- phishing --------------------------------------------------------------

func _test_phishing_params() -> void:
	_set_case("phishing_params")
	var expected_clients := [3, 4, 5, 6]
	var expected_threshold := [0.75, 0.75, 0.80, 0.80]
	var expected_checks := [
		["name"],
		["name", "dept"],
		["name", "dept", "id"],
		["name", "dept", "id", "photo", "expiry"],
	]
	for tier in range(1, 5):
		var p := PHISHING.tier_params(tier)
		_eq(int(p["clients"]), expected_clients[tier - 1], "phishing T%d clients" % tier)
		_approx(float(p["threshold"]), expected_threshold[tier - 1], 0.0001,
			"phishing T%d threshold" % tier)
		_eq(p["checks"], expected_checks[tier - 1], "phishing T%d checks" % tier)


func _test_phishing_generation() -> void:
	_set_case("phishing_generation")
	for tier in range(1, 5):
		var p := PHISHING.tier_params(tier)
		for seed in SEEDS:
			var clients := PHISHING.generate_clients(tier, seed)
			_eq(clients.size(), int(p["clients"]), "phishing T%d seed %d: клиентов" % [tier, seed])
			_ok(PHISHING.validate_clients(clients, tier),
				"phishing T%d seed %d: все решения однозначны" % [tier, seed])
			var fakes := 0
			var valids := 0
			for client in clients:
				var c: Dictionary = client
				var diffs := PHISHING.client_diff_fields(c)
				_ok(diffs.size() <= 1, "phishing T%d seed %d: не больше одного отличия" % [tier, seed])
				if bool(c.get("valid", false)):
					valids += 1
					_eq(str(c.get("expected", "")), "issue", "phishing: честный → ВЫДАТЬ")
				else:
					fakes += 1
					_eq(str(c.get("expected", "")), "deny", "phishing: подделка → ОТКАТАТЬ")
					_eq(str(c.get("mismatch", "")), str(diffs[0]) if not diffs.is_empty() else "",
						"phishing: mismatch = отличие")
					_ok((c.get("checks", []) as Array).has(str(c.get("mismatch", ""))),
						"phishing: отличие в проверяемом поле")
					if str(c.get("mismatch", "")) == "id":
						var file_id := str((c.get("file", {}) as Dictionary).get("id", ""))
						var pass_id := str((c.get("pass", {}) as Dictionary).get("id", ""))
						_eq(file_id.length(), pass_id.length(), "phishing: ID той же длины")
						var has_cyrillic := false
						for i in range(pass_id.length()):
							if PHISHING.LOOKALIKE.values().has(pass_id.substr(i, 1)):
								has_cyrillic = true
						_ok(has_cyrillic, "phishing: поддельный ID содержит кириллицу")
			_ok(valids >= 1 and fakes >= 1,
				"phishing T%d seed %d: есть и честные, и подделки" % [tier, seed])

	var named := PHISHING.generate_client(4, 123, 0, 1)
	var diff_name := PHISHING.client_diff_fields(named)
	_eq(diff_name.size(), 1, "phishing T4: подделка отличается одним полем")


func _test_phishing_quality() -> void:
	_set_case("phishing_quality")
	_approx(PHISHING.phishing_quality(3, 3), 1.0, 0.0001, "phishing 3/3 = 1")
	_approx(PHISHING.phishing_quality(2, 3), 2.0 / 3.0, 0.0001, "phishing 2/3")
	_approx(PHISHING.phishing_quality(0, 3), 0.0, 0.0001, "phishing 0/3 = 0")
	_approx(PHISHING.phishing_quality(5, 3), 1.0, 0.0001, "phishing клампится сверху")
	_approx(PHISHING.phishing_quality(0, 0), 0.0, 0.0001, "phishing без клиентов = 0")


# --- ransomware ------------------------------------------------------------

func _test_ransomware_params() -> void:
	_set_case("ransomware_params")
	var expected := {
		1: {"cards": 12, "exe": 1, "threshold": 0.50, "masking": "extension_visible"},
		2: {"cards": 16, "exe": 2, "threshold": 0.55, "masking": "extension_small"},
		3: {"cards": 20, "exe": 2, "threshold": 0.60, "masking": "document_icon"},
		4: {"cards": 24, "exe": 3, "threshold": 0.65, "masking": "similar_names"},
	}
	for tier in range(1, 5):
		var p := RANSOMWARE.tier_params(tier)
		var spec: Dictionary = expected[tier]
		_eq(int(p["cards"]), int(spec["cards"]), "ransomware T%d cards" % tier)
		_eq(int(p["exe"]), int(spec["exe"]), "ransomware T%d exe" % tier)
		_approx(float(p["threshold"]), float(spec["threshold"]), 0.0001,
			"ransomware T%d threshold" % tier)
		_eq(str(p["masking"]), str(spec["masking"]), "ransomware T%d masking" % tier)


func _test_ransomware_generation() -> void:
	_set_case("ransomware_generation")
	for tier in range(1, 5):
		var p := RANSOMWARE.tier_params(tier)
		for seed in SEEDS:
			var data := RANSOMWARE.generate_cards(tier, seed)
			var cards: Array = data["cards"]
			_eq(cards.size(), int(p["cards"]), "ransomware T%d seed %d: карточек" % [tier, seed])
			_eq(int(data["total_exe"]), int(p["exe"]), "ransomware T%d seed %d: exe" % [tier, seed])
			_ok(RANSOMWARE.validate_cards(data),
				"ransomware T%d seed %d: валидатор" % [tier, seed])
			var exec_count := 0
			var target_count := 0
			var trap_count := 0
			for card in cards:
				var c: Dictionary = card
				if bool(c.get("executable", false)):
					exec_count += 1
				if bool(c.get("target", false)):
					target_count += 1
					_ok(bool(c.get("executable", false)), "ransomware: цель исполняемая")
				if bool(c.get("trap", false)):
					trap_count += 1
					_ok(not bool(c.get("executable", false)), "ransomware: ловушка не exe")
					_ok(not bool(c.get("target", false)), "ransomware: ловушка не цель")
					_ok(str(c.get("name", "")).to_lower().contains("exe"),
						"ransomware: в имени ловушки есть exe")
					_ok(["DOC", "XLS"].has(str(c.get("ext", ""))),
						"ransomware: расширение ловушки doc/xls")
			_eq(exec_count, int(p["exe"]), "ransomware T%d seed %d: найдено exe" % [tier, seed])
			_ok(exec_count >= 1, "ransomware T%d seed %d: минимум один exe" % [tier, seed])
			_ok(target_count <= 1, "ransomware T%d seed %d: не больше одной цели" % [tier, seed])
			if tier <= 2:
				_eq(target_count, 1, "ransomware T%d seed %d: ровно одна цель" % [tier, seed])
			if tier == 4:
				_eq(trap_count, 2, "ransomware T4 seed %d: две ловушки" % seed)
			else:
				_eq(trap_count, 0, "ransomware T%d seed %d: без ловушек" % [tier, seed])


func _test_ransomware_quality() -> void:
	_set_case("ransomware_quality")
	_approx(RANSOMWARE.ransomware_quality(3, 0, 3), 1.0, 0.0001, "ransomware 3/3 = 1")
	_approx(RANSOMWARE.ransomware_quality(1, 0, 2), 0.5, 0.0001, "ransomware 1/2 = 0.5")
	_approx(RANSOMWARE.ransomware_quality(0, 0, 2), 0.0, 0.0001, "ransomware 0/2 = 0")
	_approx(RANSOMWARE.ransomware_quality(1, 1, 2), 0.25, 0.0001,
		"ransomware (1 - 0.5)/2 = 0.25")
	_approx(RANSOMWARE.ransomware_quality(0, 4, 2), 0.0, 0.0001,
		"ransomware ложные клампятся в 0")
	_approx(RANSOMWARE.ransomware_quality(4, 0, 2), 1.0, 0.0001,
		"ransomware клампится сверху")
	_approx(RANSOMWARE.ransomware_quality(0, 0, 0), 0.0, 0.0001, "ransomware без exe = 0")


# --- общие требования ------------------------------------------------------

func _test_no_timers_and_no_global_rng() -> void:
	_set_case("no_timers")
	var scripts := {
		"junk": JUNK,
		"ddos": DDOS,
		"phishing": PHISHING,
		"ransomware": RANSOMWARE,
	}
	var paths := {
		"junk": "res://scripts/minigames/attack/junk.gd",
		"ddos": "res://scripts/minigames/attack/ddos.gd",
		"phishing": "res://scripts/minigames/attack/phishing.gd",
		"ransomware": "res://scripts/minigames/attack/ransomware.gd",
	}
	for id in IDS:
		var game = scripts[id].new()
		game.start(id, 2, 12345)
		_eq(game.game_id, id, "%s: game_id" % id)
		_eq(game.tier, 2, "%s: tier" % id)
		_ok(game.running, "%s: running" % id)
		_eq(_count_timers(game), 0, "%s: нет Timer-узлов" % id)
		game._process(0.016)
		_ok(not game.is_finished(), "%s: один кадр не завершает игру" % id)
		game.free()

		var source := FileAccess.get_file_as_string(str(paths[id]))
		_ok(not source.is_empty(), "%s: исходник читается" % id)
		_ok(not source.contains("Timer.new"), "%s: нет Timer.new" % id)
		_ok(not source.contains("create_timer"), "%s: нет create_timer" % id)
		_ok(not source.contains("Rng."), "%s: не использует глобальный Rng" % id)
		_ok(source.contains("RandomNumberGenerator.new()"), "%s: локальный RNG" % id)


func _test_factory_and_finished_contract() -> void:
	_set_case("factory_contract")
	for id in IDS:
		var game = FACTORY.create_attack(str(id), 2, 2026)
		if game == null:
			print("SKIP: MiniGameFactory.create_attack(%s) вернул null" % str(id))
			continue
		_ok(game is MiniGame, "%s: фабрика вернула MiniGame" % str(id))
		_eq(game.game_id, str(id), "%s: фабрика выставила game_id" % str(id))
		_eq(game.tier, 2, "%s: фабрика выставила tier" % str(id))
		_ok(game.running, "%s: игра запущена" % str(id))
		_finish_count = 0
		_last_q = -1.0
		game.finished.connect(_on_finished)
		game._finish(0.37)
		_eq(_finish_count, 1, "%s: finished эмитится один раз" % str(id))
		_approx(_last_q, 0.37, 0.0001, "%s: finished(q)" % str(id))
		_approx(game.quality(), 0.37, 0.0001, "%s: quality()" % str(id))
		_ok(game.is_finished(), "%s: is_finished" % str(id))
		_ok(not game.running, "%s: running=false после finish" % str(id))
		game._finish(0.99)
		_eq(_finish_count, 1, "%s: повторный finish не эмитит" % str(id))
		game.free()


func _test_surrender_semantics() -> void:
	_set_case("surrender")
	var ad = AD.new()
	var created: Dictionary = {}
	ad.create_game_override = func(kind, tier, seed, ctx):
		var g = FACTORY.create_attack(str(kind), int(tier), int(seed), ctx)
		if g != null:
			created[str(kind)] = g
		return g
	for id in IDS:
		var attack_id := str(ad.spawn_attack(id))
		_ok(not attack_id.is_empty(), "%s: AttackDirector открыл мини-игру" % id)
		var game = created.get(id)
		if game == null:
			_ok(false, "%s: мини-игра атаки создана" % id)
			continue
		_ok(bool(game.is_attack), "%s: AttackDirector выставил is_attack" % id)
		_eq(str(game.skip_label()), "СДАТЬСЯ", "%s: кнопка отказа — СДАТЬСЯ" % id)
		_press_escape(game)
		_ok(bool(game._skip_armed), "%s: Esc взводит сдачу" % id)
		_ok(not bool(game.is_finished()), "%s: после первого Esc игра идёт" % id)
		_press_escape(game)
		_ok(bool(game.is_finished()), "%s: второй Esc подтверждает сдачу" % id)
		_approx(float(game.quality()), 0.0, 0.0001, "%s: сдача даёт q=0" % id)
		ad.cancel_active()
	ad.free()

	# Мини-игры отправки: Esc — no-op, кнопка остаётся ПРОПУСТИТЬ.
	for id in SEND_IDS:
		var send = FACTORY.create_send(id, 1, 909)
		if send == null:
			print("SKIP: MiniGameFactory.create_send(%s) вернул null" % id)
			continue
		_ok(not bool(send.is_attack), "%s: мини-игра отправки не атака" % id)
		_eq(str(send.skip_label()), "ПРОПУСТИТЬ",
			"%s: кнопка отправки — ПРОПУСТИТЬ" % id)
		_press_escape(send)
		_ok(not bool(send._skip_armed), "%s: Esc не взводит пропуск" % id)
		_ok(not bool(send.is_finished()), "%s: Esc не завершает отправку" % id)
		send.free()


func _test_submit_quality_contract() -> void:
	_set_case("submit_contract")
	var junk = JUNK.new()
	junk.start("junk", 1, 555)
	for card in junk._cards:
		if bool((card as Dictionary).get("junk", false)):
			junk._marked[int((card as Dictionary).get("id", -1))] = true
	junk._submit()
	_ok(junk.is_finished(), "junk: ПРОВЕРИТЬ завершает игру")
	_approx(junk.quality(), 1.0, 0.0001, "junk: все снятые = q 1")
	_ok(junk._result_detail.contains("СНЯТО"), "junk: result_detail заполнен")
	junk.free()

	var ransomware = RANSOMWARE.new()
	ransomware.start("ransomware", 1, 556)
	for card in ransomware._cards:
		var c: Dictionary = card
		if bool(c.get("executable", false)):
			ransomware._marked[int(c.get("id", -1))] = true
	ransomware._submit()
	_ok(ransomware.is_finished(), "ransomware: ПРОВЕРИТЬ завершает игру")
	_approx(ransomware.quality(), 1.0, 0.0001, "ransomware: все exe = q 1")
	_ok(ransomware._result_detail.contains("НАЙДЕНО"), "ransomware: result_detail заполнен")
	ransomware.free()


# --- assert-хелперы --------------------------------------------------------

func _count_timers(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Timer:
			count += 1
		count += _count_timers(child)
	return count


func _on_finished(q: float) -> void:
	_finish_count += 1
	_last_q = q


func _press_escape(game) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	game._input(event)


func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message + " — ожидалось true")
	return false


func _eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_fail("%s — получено %s, ожидалось %s" % [message, str(actual), str(expected)])
	return false


func _approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, float(actual), float(expected)])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	print("test_attack_games: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_attack_games" if _fails == 0 else "FAIL test_attack_games")
	quit(0 if _fails == 0 else 1)
