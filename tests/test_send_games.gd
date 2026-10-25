extends SceneTree
## Headless-юнит-тесты чистых функций семи игр отправки.
## Запуск: godot --headless --path . --script tests/test_send_games.gd

const DOTS := preload("res://scripts/minigames/send/dots.gd")
const SOUND := preload("res://scripts/minigames/send/sound.gd")
const WIRES := preload("res://scripts/minigames/send/wires.gd")
const TEXT := preload("res://scripts/minigames/send/text.gd")
const VIDEO := preload("res://scripts/minigames/send/video.gd")
const PHOTO := preload("res://scripts/minigames/send/photo.gd")
const MAZE := preload("res://scripts/minigames/send/maze.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""


func _init() -> void:
	await process_frame
	_test_dots()
	_test_sound()
	_test_wires()
	_test_text()
	_test_video()
	_test_photo()
	_test_maze()
	_finish()


# --- dots ------------------------------------------------------------------

func _test_dots() -> void:
	_set_case("dots")
	var expected := {
		1: {"cols": 3, "rows": 3, "obstacles": 0},
		2: {"cols": 4, "rows": 3, "obstacles": 2},
		3: {"cols": 4, "rows": 4, "obstacles": 4},
		4: {"cols": 5, "rows": 4, "obstacles": 6},
	}
	for tier in range(1, 5):
		var spec: Dictionary = expected[tier]
		var p := DOTS.tier_params(tier)
		_eq(int(p["cols"]), int(spec["cols"]), "T%d cols" % tier)
		_eq(int(p["rows"]), int(spec["rows"]), "T%d rows" % tier)
		_eq(int(p["obstacles"]), int(spec["obstacles"]), "T%d obstacles" % tier)
		for seed in [1, 7, 42, 99, 1234, 2026]:
			var b := DOTS.generate_tier(tier, seed)
			var cols := int(b["cols"])
			var rows := int(b["rows"])
			var obstacles := int(spec["obstacles"])
			_eq(int(b["blocked"].size()), obstacles, "T%d seed %d: число препятствий" % [tier, seed])
			_eq(int(b["free_count"]), cols * rows - obstacles,
				"T%d seed %d: свободных клеток" % [tier, seed])
			_eq(int(b["path"].size()), cols * rows - obstacles,
				"T%d seed %d: длина пути = свободные клетки" % [tier, seed])
			_ok(DOTS.validate_board(b), "T%d seed %d: доска решаема/валидна" % [tier, seed])
			_eq(int(b["start"]), int(b["path"][0]), "T%d seed %d: старт = начало пути" % [tier, seed])
			_eq(int(b["finish"]), int(b["path"][b["path"].size() - 1]),
				"T%d seed %d: финиш = конец пути" % [tier, seed])
			var blocked: Array = b["blocked"]
			var free: Array = b["free"]
			var path: Array = b["path"]
			var seen := {}
			for i in range(path.size()):
				var id := int(path[i])
				_ok(not blocked.has(id), "T%d seed %d: путь не по препятствию" % [tier, seed])
				_ok(free.has(id), "T%d seed %d: путь по свободной клетке" % [tier, seed])
				_ok(not seen.has(id), "T%d seed %d: клетка не повторяется" % [tier, seed])
				seen[id] = true
				if i > 0:
					var prev := int(path[i - 1])
					var dx := absi(id % cols - prev % cols)
					var dy := absi(id / cols - prev / cols)
					_eq(dx + dy, 1, "T%d seed %d: соседние клетки пути" % [tier, seed])
			# Свободные + препятствия покрывают всю сетку без пересечений.
			var union := {}
			for id in free:
				union[int(id)] = true
			for id in blocked:
				union[int(id)] = true
			_eq(union.size(), cols * rows, "T%d seed %d: покрытие сетки" % [tier, seed])

	_approx(DOTS.quality_for(0, 0, 2), 1.0, 0.0001, "dots q без ошибок = 1")
	_approx(DOTS.quality_for(2, 0, 2), 0.92, 0.0001, "dots 2 отката T2 = 0.92")
	_approx(DOTS.quality_for(0, 3, 1), 0.7, 0.0001, "dots 3 ошибки = 0.7")
	_approx(DOTS.quality_for(50, 50, 4), 0.0, 0.0001, "dots q без нижнего порога 0.3")


# --- sound -----------------------------------------------------------------

func _test_sound() -> void:
	_set_case("sound")
	var expected_counts := [3, 4, 5, 6]
	var expected_tol := [0.16, 0.11, 0.08, 0.06]
	for tier in range(1, 5):
		for seed in [1, 7, 42, 99, 1234]:
			var data := SOUND.generate(tier, seed)
			var count := int(data["count"])
			_eq(count, expected_counts[tier - 1], "sound T%d count" % tier)
			_approx(float(data["tolerance"]), expected_tol[tier - 1], 0.0001,
				"sound T%d tol" % tier)
			_eq((data["targets"] as Array).size(), count, "sound targets size")
			_eq((data["starts"] as Array).size(), count, "sound starts size")
			var targets: Array = data["targets"]
			var starts: Array = data["starts"]
			var tol := float(data["tolerance"])
			for i in range(count):
				_ok(float(targets[i]) >= tol - 0.001 and float(targets[i]) <= 1.0 - tol + 0.001,
					"sound T%d цель внутри дорожки" % tier)
				_ok(absf(float(starts[i]) - float(targets[i])) > tol,
					"sound T%d старт вне допуска" % tier)
			for i in range(count):
				for j in range(i + 1, count):
					_ok(absf(float(targets[i]) - float(targets[j])) >= 2.0 * tol - 0.001,
						"sound T%d цели не сливаются" % tier)
		var drift := SOUND.generate(tier, 5)
		if tier <= 2:
			_approx(float(drift["drift_amp"]), 0.0, 0.0001, "sound T%d без дрейфа" % tier)
		elif tier == 3:
			_approx(float(drift["drift_amp"]), 0.02, 0.0001, "sound T3 дрейф 2%")
			_approx(float(drift["drift_hz"]), 0.15, 0.0001, "sound T3 дрейф 0.15 Гц")
		else:
			_approx(float(drift["drift_amp"]), 0.03, 0.0001, "sound T4 дрейф 3%")
			_approx(float(drift["drift_hz"]), 0.25, 0.0001, "sound T4 дрейф 0.25 Гц")

	_approx(SOUND.channel_quality(0.5, 0.5, 0.16), 1.0, 0.0001, "sound центр = 1")
	_approx(SOUND.channel_quality(0.66, 0.5, 0.16), 0.5, 0.0001, "sound край = 0.5")
	_approx(SOUND.channel_quality(0.34, 0.5, 0.16), 0.5, 0.0001, "sound край снизу = 0.5")
	_approx(SOUND.channel_quality(0.82, 0.5, 0.16), 0.0, 0.0001, "sound 2*tol = 0")
	_approx(SOUND.quality_from([0.5, 0.34], [0.5, 0.5], 0.16), 0.75, 0.0001,
		"sound среднее 0.75")
	_approx(SOUND.target_at(0.5, 0.0, 0.0, 0.0, 3.0), 0.5, 0.0001,
		"sound без дрейфа цель статична")
	_ok(SOUND.target_at(0.5, 0.03, 0.25, 0.0, 1.0) != 0.5,
		"sound с дрейфом цель смещается")


# --- wires -----------------------------------------------------------------

func _test_wires() -> void:
	_set_case("wires")
	var expected := {
		1: {"wires": 3, "sockets": 3},
		2: {"wires": 4, "sockets": 4},
		3: {"wires": 5, "sockets": 6},
		4: {"wires": 6, "sockets": 6},
	}
	for tier in range(1, 5):
		var geo := WIRES.geometry(tier)
		_approx(float(geo["box"]), 34.0, 0.0001, "wires T%d box 34" % tier)
		_approx(float(geo["pitch"]), 40.0, 0.0001, "wires T%d pitch 40" % tier)
		_ok(float(geo["gap"]) >= 300.0 - 0.001, "wires T%d зазор >= 300" % tier)
		_eq((geo["left_rects"] as Array).size(), int(expected[tier]["wires"]),
			"wires T%d число левых портов" % tier)
		_eq((geo["right_rects"] as Array).size(), int(expected[tier]["sockets"]),
			"wires T%d число правых портов" % tier)
		var left_rack: Rect2 = geo["left_rack"]
		var right_rack: Rect2 = geo["right_rack"]
		_ok(left_rack.end.y <= 320.0, "wires T%d левая стойка <= 320" % tier)
		_ok(right_rack.end.y <= 320.0, "wires T%d правая стойка <= 320" % tier)
		for side in ["left_rects", "right_rects"]:
			var rects: Array = geo[side]
			var rack := left_rack if side == "left_rects" else right_rack
			for i in range(rects.size()):
				var a: Rect2 = rects[i]
				_ok(a.position.x >= rack.position.x and a.position.y >= rack.position.y
					and a.end.x <= rack.end.x + 0.001 and a.end.y <= rack.end.y + 0.001,
					"wires T%d порт внутри стойки" % tier)
				for j in range(i + 1, rects.size()):
					_ok(not a.intersects(rects[j]), "wires T%d порты не пересекаются" % tier)
		var lanes: Array = geo["lanes"]
		for i in range(1, lanes.size()):
			_ok(absf(float(lanes[i]) - float(lanes[i - 1])) >= 8.0 - 0.001,
				"wires T%d полосы >= 8 px" % tier)
		for seed in [1, 7, 42, 99, 1234, 2026]:
			var data := WIRES.generate(tier, seed)
			_eq((data["wires"] as Array).size(), int(expected[tier]["wires"]),
				"wires T%d wires" % tier)
			_eq((data["sockets"] as Array).size(), int(expected[tier]["sockets"]),
				"wires T%d sockets" % tier)
			_ok(WIRES.validate_pairs(data), "wires T%d seed %d пары уникальны/матчатся" % [tier, seed])
			var sockets: Array = data["sockets"]
			var empty_count := 0
			for socket in sockets:
				if bool(socket.get("empty", false)):
					empty_count += 1
			if tier == 3:
				_eq(empty_count, 1, "wires T3 одно пустое гнездо")
			else:
				_eq(empty_count, 0, "wires T%d без пустых" % tier)
			if tier >= 4:
				var color_counts := {}
				var shape_counts := {}
				for wire in data["wires"]:
					var c := str(wire["color"])
					var s := str(wire["shape"])
					color_counts[c] = int(color_counts.get(c, 0)) + 1
					shape_counts[s] = int(shape_counts.get(s, 0)) + 1
				var shared_colors := 0
				var shared_shapes := 0
				for k in color_counts.keys():
					if int(color_counts[k]) >= 2:
						shared_colors += 1
				for k in shape_counts.keys():
					if int(shape_counts[k]) >= 2:
						shared_shapes += 1
				_ok(shared_colors >= 2, "wires T4 два общих цвета")
				_ok(shared_shapes >= 2, "wires T4 две общие формы")

	_approx(WIRES.quality_for(3, 0, 3), 1.0, 0.0001, "wires все подключены = 1")
	_approx(WIRES.quality_for(2, 1, 4), 0.4375, 0.0001, "wires 2/4 и 1 ошибка = 0.4375")
	_approx(WIRES.quality_for(0, 20, 6), 0.0, 0.0001, "wires q клампится в 0")


# --- text ------------------------------------------------------------------

func _test_text() -> void:
	_set_case("text")
	var expected := {
		1: {"words": 11, "aliens": 1, "lines": 2},
		2: {"words": 15, "aliens": 2, "lines": 2},
		3: {"words": 19, "aliens": 3, "lines": 3},
		4: {"words": 24, "aliens": 4, "lines": 3},
	}
	for tier in range(1, 5):
		for seed in [1, 7, 42, 99, 1234, 2026]:
			var data := TEXT.generate(tier, seed)
			_eq((data["words"] as Array).size(), int(expected[tier]["words"]),
				"text T%d число слов" % tier)
			_eq(int(data["aliens"]), int(expected[tier]["aliens"]), "text T%d чужих" % tier)
			_eq((data["rows"] as Array).size(), int(expected[tier]["lines"]),
				"text T%d строк" % tier)
			var row_sum := 0
			for r in data["rows"]:
				row_sum += int(r)
			_eq(row_sum, int(expected[tier]["words"]), "text T%d сумма по строкам" % tier)
			_ok(TEXT.validate_generation(data, tier),
				"text T%d seed %d: уникальность и однозначность" % [tier, seed])
			var texts := {}
			var all_rows_used := {}
			for word in data["words"]:
				texts[str(word["text"]).to_lower()] = true
				all_rows_used[int(word["row"])] = true
			_eq(texts.size(), int(expected[tier]["words"]), "text T%d нет дублей" % tier)
			_eq(all_rows_used.size(), int(expected[tier]["lines"]),
				"text T%d все строки заполнены" % tier)

	_approx(TEXT.quality_for(1, 0, 1), 1.0, 0.0001, "text 1 найден = 1")
	_approx(TEXT.quality_for(1, 1, 1), 0.0, 0.0001, "text ложное = 0")
	_approx(TEXT.quality_for(2, 1, 4), 0.25, 0.0001, "text 2-1 из 4 = 0.25")
	_approx(TEXT.quality_for(0, 5, 1), 0.0, 0.0001, "text q не уходит ниже 0")


# --- video -----------------------------------------------------------------

func _test_video() -> void:
	_set_case("video")
	var expected := {
		1: {"cards": 3, "slots": 3},
		2: {"cards": 4, "slots": 4},
		3: {"cards": 5, "slots": 4},
		4: {"cards": 6, "slots": 5},
	}
	var seen_timecodes := {}
	for tier in range(1, 5):
		for seed in [1, 7, 42, 99, 1234, 2026]:
			var data := VIDEO.generate(tier, seed)
			_eq((data["cards"] as Array).size(), int(expected[tier]["cards"]),
				"video T%d карточек" % tier)
			_eq(int(data["slots"]), int(expected[tier]["slots"]), "video T%d слотов" % tier)
			var decoys := 0
			var mirrored := 0
			var real_slots := {}
			for card in data["cards"]:
				if bool(card.get("decoy", false)):
					decoys += 1
					_eq(int(card.get("correct_slot", 0)), -1, "video брак без правильного слота")
				else:
					real_slots[int(card.get("correct_slot", -1))] = true
				if bool(card.get("mirrored", false)):
					mirrored += 1
			for i in range(int(expected[tier]["slots"])):
				_ok(real_slots.has(i), "video T%d слот %d имеет реальный кадр" % [tier, i])
			_eq(real_slots.size(), int(expected[tier]["slots"]), "video T%d уникальные верные слоты" % tier)
			if tier <= 2:
				_eq(decoys, 0, "video T%d без брака" % tier)
				_eq(mirrored, 0, "video T%d без зеркала" % tier)
			else:
				_eq(decoys, 1, "video T%d ровно 1 брак" % tier)
				var info := VIDEO.decoy_info(data)
				_eq(int(info["duplicate_count"]), 2, "video T%d таймкод брака дублируется ровно дважды" % tier)
				_ok(int(info["duplicate_real"]) >= 0, "video T%d брак дублирует реальный кадр" % tier)
				var real_shape := ""
				for card in data["cards"]:
					if int(card.get("id", -1)) == int(info["duplicate_real"]):
						real_shape = str(card.get("shape", ""))
				_ok(real_shape != str(info["decoy_shape"]), "video T%d силуэт брака отличается" % tier)
			if tier == 4:
				_eq(mirrored, 1, "video T4 ровно 1 зеркальный кадр")
			else:
				_eq(mirrored, 0, "video T%d без зеркала" % tier)
			var tc_key := "|".join(data.get("slot_timecodes", []))
			seen_timecodes["%d:%d:%s" % [tier, seed, tc_key]] = true

	# Таймкоды зависят от раздачи, а не жёстко от индекса.
	_ok(seen_timecodes.size() >= 8, "video таймкоды меняются от сида")
	_approx(VIDEO.quality_from(4, 4, 0, 0), 1.0, 0.0001, "video всё верно = 1")
	_approx(VIDEO.quality_from(4, 3, 1, 0), 0.625, 0.0001, "video 3 верно, 1 ошибка = 0.625")
	_approx(VIDEO.quality_from(4, 3, 0, 1), 0.5, 0.0001, "video брак в слоте = 0.5")
	_approx(VIDEO.quality_from(4, 0, 4, 4), 0.0, 0.0001, "video q не ниже 0")


# --- photo -----------------------------------------------------------------

func _test_photo() -> void:
	_set_case("photo")
	var speeds := [90.0, 140.0, 200.0, 260.0]
	var frame_w := [220.0, 180.0, 150.0, 120.0]
	var frame_h := [150.0, 120.0, 100.0, 80.0]
	var shots := [3, 4, 5, 6]
	for tier in range(1, 5):
		var p := PHOTO.tier_params(tier)
		_approx(float(p["speed"]), speeds[tier - 1], 0.0001, "photo T%d speed" % tier)
		_approx(float(p["frame_w"]), frame_w[tier - 1], 0.0001, "photo T%d frame_w" % tier)
		_approx(float(p["frame_h"]), frame_h[tier - 1], 0.0001, "photo T%d frame_h" % tier)
		_eq(int(p["shots"]), shots[tier - 1], "photo T%d shots" % tier)
		for seed in [1, 7, 42, 99, 1234]:
			var a := PHOTO.simulate(seed, tier, 1.0, 30)
			var b := PHOTO.simulate(seed, tier, 1.0, 144)
			_ok(int(a["steps"]) > 0, "photo T%d шаги есть" % tier)
			_eq(int(a["steps"]), int(b["steps"]), "photo T%d 30/144 fps: одинаковое число шагов" % tier)
			var pa: Array = a["positions"]
			var pb: Array = b["positions"]
			_eq(pa.size(), pb.size(), "photo T%d 30/144 fps: одинаковое число позиций" % tier)
			var max_diff := 0.0
			for i in range(mini(pa.size(), pb.size())):
				max_diff = maxf(max_diff, (pa[i] as Vector2).distance_to(pb[i] as Vector2))
			_ok(max_diff <= 0.0001, "photo T%d 30/144 fps: траектории совпадают (%.6f)" % [tier, max_diff])
		var first := PHOTO.simulate(1, tier, 0.8, 60)
		var second := PHOTO.simulate(2, tier, 0.8, 60)
		_ok((first["final"] as Vector2).distance_to(second["final"] as Vector2) > 1.0,
			"photo T%d разные сиды → разные траектории" % tier)
		_ok(frame_w[tier - 1] <= 220.0 and frame_h[tier - 1] <= 150.0,
			"photo T%d рамка не тривиальная" % tier)

	_ok(PHOTO.capture_success(Vector2(150, 150), Vector2(100, 100), Vector2(220, 150)),
		"photo бюст целиком в рамке → успех")
	_ok(not PHOTO.capture_success(Vector2(100, 150), Vector2(100, 100), Vector2(220, 150)),
		"photo бюст частично вне рамки → провал")
	_approx(PHOTO.quality_for(2, 4), 0.5, 0.0001, "photo 2 из 4 = 0.5")
	_approx(PHOTO.quality_for(4, 4), 1.0, 0.0001, "photo 4 из 4 = 1")
	_approx(PHOTO.quality_for(0, 3), 0.0, 0.0001, "photo 0 из 3 = 0")
	_ok(float(PHOTO.tier_params(3)["frame_w"]) < float(PHOTO.tier_params(1)["frame_w"]),
		"photo T3 рамка меньше T1")


# --- maze ------------------------------------------------------------------

func _test_maze() -> void:
	_set_case("maze")
	var expected := {
		1: {"cols": 9, "rows": 4, "field_w": 360.0, "field_h": 160.0, "corridor": 28.0, "speed": 420.0},
		2: {"cols": 11, "rows": 4, "field_w": 440.0, "field_h": 160.0, "corridor": 24.0, "speed": 470.0},
		3: {"cols": 13, "rows": 4, "field_w": 494.0, "field_h": 152.0, "corridor": 20.0, "speed": 520.0},
		4: {"cols": 15, "rows": 5, "field_w": 520.0, "field_h": 180.0, "corridor": 18.0, "speed": 560.0},
	}
	for tier in range(1, 5):
		var p := MAZE.tier_params(tier)
		var spec: Dictionary = expected[tier]
		for key in ["cols", "rows"]:
			_eq(int(p[key]), int(spec[key]), "maze T%d %s" % [tier, key])
		for key in ["field_w", "field_h", "corridor", "speed"]:
			_approx(float(p[key]), float(spec[key]), 0.0001, "maze T%d %s" % [tier, key])
		for seed in [1, 7, 42, 99, 1234, 2026]:
			var data := MAZE.generate_tier(tier, seed)
			var cols := int(data["cols"])
			var rows := int(data["rows"])
			var ent := int(data["ent_row"])
			var ex := int(data["exit_row"])
			_ok(bool(data["solvable"]), "maze T%d seed %d решаем" % [tier, seed])
			var bfs_path := MAZE.bfs(data["cells"], cols, rows, ent * cols, ex * cols + (cols - 1))
			_ok(bfs_path.size() >= 2, "maze T%d seed %d BFS-путь есть" % [tier, seed])
			_eq(int(bfs_path[0]), ent * cols, "maze T%d BFS старт" % tier)
			_eq(int(bfs_path[bfs_path.size() - 1]), ex * cols + cols - 1, "maze T%d BFS финиш" % tier)
			for i in range(1, bfs_path.size()):
				var a := int(bfs_path[i - 1])
				var b := int(bfs_path[i])
				var ax := a % cols
				var ay := a / cols
				var bx := b % cols
				var by := b / cols
				_eq(absi(ax - bx) + absi(ay - by), 1, "maze T%d BFS шаг по соседям" % tier)
				var nbrs := MAZE.neighbors_open(data["cells"], ax, ay, cols, rows)
				_ok(nbrs.has(Vector2i(bx, by)), "maze T%d BFS идёт через открытую стену" % tier)
			# Стенки: внутренние рёбра совпадают с cells.
			var edges := MAZE.wall_edges(data["cells"], cols, rows, ent, ex)
			for by in range(rows):
				for bx in range(1, cols):
					var closed := bool(edges["v:%d:%d" % [bx, by]])
					_eq(closed, bool(data["cells"][by][bx - 1]["e"]),
						"maze T%d вертикальная стена %d:%d" % [tier, bx, by])
			for by in range(1, rows):
				for bx in range(cols):
					var closed := bool(edges["h:%d:%d" % [bx, by]])
					_eq(closed, bool(data["cells"][by - 1][bx]["s"]),
						"maze T%d горизонтальная стена %d:%d" % [tier, bx, by])
			var field := Rect2(40.0, 80.0, float(spec["field_w"]), float(spec["field_h"]))
			var walls := MAZE.build_walls(data["cells"], cols, rows, ent, ex, field,
				float(spec["corridor"]))
			var closed_edges := 0
			for k in edges.keys():
				if bool(edges[k]):
					closed_edges += 1
			_eq(walls.size(), closed_edges, "maze T%d число стенок = рёбрам" % tier)
			for wall in walls:
				_ok((wall as Rect2).size.x > 0.0 and (wall as Rect2).size.y > 0.0,
					"maze T%d стенка имеет размер" % tier)

	_approx(MAZE.quality_for(0, 0), 1.0, 0.0001, "maze без ошибок = 1")
	_approx(MAZE.quality_for(5, 2), 0.76, 0.0001, "maze 5 столкновений/2 тупика = 0.76")
	_approx(MAZE.quality_for(20, 30), 0.0, 0.0001, "maze q без нижнего порога 0.4")
	# Скольжение: стена не пропускает пакет насквозь.
	var field_test := Rect2(0.0, 0.0, 100.0, 100.0)
	var walls_test := [Rect2(45.0, 0.0, 10.0, 100.0)]
	var moved := MAZE.move_packet(Vector2(20, 50), Vector2(90, 50), 100.0, 1.0,
		walls_test, field_test, 4.5)
	_ok(bool(moved["blocked"]), "maze движение в стену помечено")
	_ok((moved["pos"] as Vector2).x < 45.0, "maze пакет не прошёл сквозь стену")


# --- assert-хелперы --------------------------------------------------------

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
	print("test_send_games: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_send_games" if _fails == 0 else "FAIL test_send_games")
	quit(0 if _fails == 0 else 1)
