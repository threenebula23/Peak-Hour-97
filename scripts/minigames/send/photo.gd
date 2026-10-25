extends MiniGame
## «Кадр» (photo). Бюст клиента всегда движется случайно; игрок ведёт рамку
## и делает N снимков. FIX H4: движение считается по фиксированному
## логическому шагу (SIM_DT), внутри которого используется dt-вероятность
## смены цели 1-exp(-rate*dt), retarget_timer -= dt и current_dir = dir.
## Поэтому сид даёт одинаковую траекторию на 30 и 144 fps.

const SCAN := Rect2(30.0, 44.0, 580.0, 268.0)
const BUST := Vector2(36.0, 48.0)
const INSET := 4.0
const SIM_DT := 1.0 / 120.0
const TWITCH_RATE := 1.25
const TIERS := {
	1: {"speed": 90.0, "frame_w": 220.0, "frame_h": 150.0, "shots": 3,
		"switch_min": 0.8, "switch_max": 1.2, "turn_rate": 210.0},
	2: {"speed": 140.0, "frame_w": 180.0, "frame_h": 120.0, "shots": 4,
		"switch_min": 0.6, "switch_max": 1.0, "turn_rate": 260.0},
	3: {"speed": 200.0, "frame_w": 150.0, "frame_h": 100.0, "shots": 5,
		"switch_min": 0.5, "switch_max": 0.8, "turn_rate": 300.0},
	4: {"speed": 260.0, "frame_w": 120.0, "frame_h": 80.0, "shots": 6,
		"switch_min": 0.35, "switch_max": 0.65, "turn_rate": 340.0},
}

var state: Dictionary = {}
var params: Dictionary = {}
var _frame_pos: Vector2 = Vector2.ZERO
var _shots_taken: int = 0
var _captures: int = 0
var _acc: float = 0.0
var _flash: float = 0.0
var _last_capture_ok: bool = false


func _own_game_id() -> String:
	return "photo"


func _setup() -> void:
	params = tier_params(tier)
	state = _make_state(rng, params)
	_frame_pos = _clamp_frame(Vector2(SCAN.get_center().x, SCAN.position.y),
		params)
	_shots_taken = 0
	_captures = 0
	_acc = 0.0
	_flash = 0.0
	_last_capture_ok = false


# --- параметры/чистая математика ------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIERS.get(clampi(p_tier, 1, 4), TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("photo", p_tier)
	if row.is_empty():
		return base
	for key in ["speed", "frame_w", "frame_h", "switch_min", "switch_max",
			"turn_rate"]:
		if row.has(key):
			base[key] = float(row[key])
	for alias in [["retarget_min", "switch_min"], ["retarget_max", "switch_max"]]:
		if row.has(alias[0]):
			base[alias[1]] = float(row[alias[0]])
	if row.has("shots"):
		base["shots"] = int(row["shots"])
	return base


static func generate(p_tier: int, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return _make_state(rng, tier_params(p_tier))


static func _make_state(p_rng: RandomNumberGenerator, p: Dictionary) -> Dictionary:
	var speed := float(p.get("speed", 90.0)) * p_rng.randf_range(0.9, 1.1)
	var pos := _random_point(p_rng)
	var target := _random_point(p_rng)
	var dir := Vector2.RIGHT.rotated(p_rng.randf_range(0.0, TAU))
	var timer := p_rng.randf_range(float(p.get("switch_min", 0.8)),
		float(p.get("switch_max", 1.2)))
	return {
		"pos": pos,
		"target": target,
		"current_dir": dir,
		"retarget_timer": timer,
		"speed": speed,
		"params": p,
	}


static func _random_point(p_rng: RandomNumberGenerator) -> Vector2:
	var half := BUST * 0.5
	return Vector2(
		p_rng.randf_range(SCAN.position.x + half.x + 2.0,
			SCAN.end.x - half.x - 2.0),
		p_rng.randf_range(SCAN.position.y + half.y + 2.0,
			SCAN.end.y - half.y - 2.0))


static func _clamp_bust(pos: Vector2) -> Vector2:
	var half := BUST * 0.5
	return Vector2(
		clampf(pos.x, SCAN.position.x + half.x, SCAN.end.x - half.x),
		clampf(pos.y, SCAN.position.y + half.y, SCAN.end.y - half.y))


## H4: один логический шаг. dt здесь всегда SIM_DT, поэтому вероятность
## смены цели масштабируется временем, а не кадром.
static func step_motion(p_state: Dictionary, p_rng: RandomNumberGenerator,
		dt: float) -> void:
	if dt <= 0.0:
		return
	var p: Dictionary = p_state.get("params", {})
	var pos: Vector2 = p_state.get("pos", SCAN.get_center())
	var target: Vector2 = p_state.get("target", SCAN.get_center())
	var current_dir: Vector2 = p_state.get("current_dir", Vector2.RIGHT)
	var speed := float(p_state.get("speed", float(p.get("speed", 90.0))))
	var turn_rate := deg_to_rad(float(p.get("turn_rate", 240.0)))

	var to_target := target - pos
	var desired := current_dir
	if to_target.length_squared() > 0.001:
		desired = to_target.normalized()
	var max_turn := turn_rate * dt
	var angle := current_dir.angle_to(desired)
	current_dir = current_dir.rotated(clampf(angle, -max_turn, max_turn))
	# H4: явно фиксируем текущее направление и двигаемся по нему.
	var dir := current_dir
	pos += dir * speed * dt
	pos = _clamp_bust(pos)

	# Редкая резкая смена цели, вероятность зависит от dt.
	if p_rng.randf() < 1.0 - exp(-TWITCH_RATE * dt):
		target = _random_point(p_rng)
		p_state["retarget_timer"] = p_rng.randf_range(
			float(p.get("switch_min", 0.8)), float(p.get("switch_max", 1.2)))

	var timer := float(p_state.get("retarget_timer", 1.0)) - dt
	if timer <= 0.0 or pos.distance_to(target) < 24.0:
		target = _random_point(p_rng)
		timer = p_rng.randf_range(float(p.get("switch_min", 0.8)),
			float(p.get("switch_max", 1.2)))
	p_state["pos"] = pos
	p_state["target"] = target
	p_state["current_dir"] = current_dir
	p_state["retarget_timer"] = timer


## Детерминированная симуляция на фиксированном шаге. fps влияет только на
## группировку вызовов, не на последовательность шагов/позиций.
static func simulate(seed: int, p_tier: int, duration: float, fps: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var p := tier_params(p_tier)
	var s := _make_state(rng, p)
	var total_steps := int(floor(maxf(0.0, duration) / SIM_DT))
	var positions: Array[Vector2] = []
	var frame_dt := 1.0 / float(maxi(1, fps))
	var acc := 0.0
	var steps := 0
	var guard := 0
	while steps < total_steps and guard < total_steps * 4 + 16:
		guard += 1
		acc += frame_dt
		while acc >= SIM_DT and steps < total_steps:
			step_motion(s, rng, SIM_DT)
			positions.append(s["pos"])
			steps += 1
			acc -= SIM_DT
	return {
		"positions": positions,
		"final": s["pos"],
		"steps": steps,
	}


static func capture_success(bust_pos: Vector2, frame_pos: Vector2,
		frame_size: Vector2) -> bool:
	var b := Rect2(bust_pos - BUST * 0.5, BUST)
	var f := Rect2(frame_pos, frame_size)
	return b.position.x >= f.position.x and b.position.y >= f.position.y \
		and b.end.x <= f.end.x and b.end.y <= f.end.y


static func quality_for(captures: int, shots: int) -> float:
	if shots <= 0:
		return 0.0
	return clampf(float(maxi(0, captures)) / float(shots), 0.0, 1.0)


static func _clamp_frame(mouse: Vector2, p: Dictionary) -> Vector2:
	var fw := float(p.get("frame_w", 220.0))
	var fh := float(p.get("frame_h", 150.0))
	var x := clampf(mouse.x - fw * 0.5,
		SCAN.position.x + INSET, SCAN.end.x - INSET - fw)
	var y := clampf(mouse.y - fh * 0.5,
		SCAN.position.y + INSET, SCAN.end.y - INSET - fh)
	return Vector2(x, y)


func _frame_size() -> Vector2:
	return Vector2(float(params.get("frame_w", 220.0)),
		float(params.get("frame_h", 150.0)))


func _frame_rect() -> Rect2:
	return Rect2(_frame_pos, _frame_size())


# --- игра ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not running or _finished:
		return
	var mouse := _frame_pos + _frame_size() * 0.5
	if is_inside_tree():
		mouse = get_local_mouse_position()
	if SCAN.grow(2.0).has_point(mouse):
		_frame_pos = _clamp_frame(mouse, params)
	_acc += minf(maxf(delta, 0.0), 0.1)
	var guard := 0
	while _acc >= SIM_DT and guard < 32:
		guard += 1
		step_motion(state, rng, SIM_DT)
		_acc -= SIM_DT
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _capture() -> void:
	if _finished:
		return
	var shots := int(params.get("shots", 3))
	if _shots_taken >= shots:
		return
	_shots_taken += 1
	var ok := capture_success(state["pos"], _frame_pos, _frame_size())
	_last_capture_ok = ok
	if ok:
		_captures += 1
	_flash = 0.22
	_play_sfx(&"minigame_win" if ok else &"minigame_fail")
	if _shots_taken >= shots:
		_finish(quality_for(_captures, shots))
	queue_redraw()


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if local.y >= FOOTER_Y or not SCAN.grow(6.0).has_point(local):
		return false
	_frame_pos = _clamp_frame(local, params)
	_capture()
	return true


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if local.y >= FOOTER_Y:
		return
	_frame_pos = _clamp_frame(local, params)
	queue_redraw()


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if keycode == KEY_SPACE or keycode == KEY_ENTER:
		_capture()
		return true
	var step := 6.0
	var center := _frame_pos + _frame_size() * 0.5
	if keycode == KEY_LEFT:
		center.x -= step
	elif keycode == KEY_RIGHT:
		center.x += step
	elif keycode == KEY_UP:
		center.y -= step
	elif keycode == KEY_DOWN:
		center.y += step
	else:
		return false
	_frame_pos = _clamp_frame(center, params)
	queue_redraw()
	return true


# --- отрисовка -------------------------------------------------------------

func _draw_game() -> void:
	var font := Theme90.ui()
	var shots := int(params.get("shots", 3))
	var inside := capture_success(state["pos"], _frame_pos, _frame_size())
	_draw_label("СКАН КЛИЕНТА · КАДР %d / %d" % [_shots_taken, shots],
		Vector2(24.0, 34.0), 10, Theme90.NAVY, 280.0)
	_draw_label("УДАЧНЫХ %d · ОСТАЛОСЬ %d" % [_captures, shots - _shots_taken],
		Vector2(320.0, 34.0), 10, Theme90.SHADE, 280.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	draw_style_box(Theme90.box(Theme90.DARK, Color(0, 0, 0, 0), 4, 1), SCAN)
	# Мягкий фон скана: окно/стол, на игру не влияет.
	draw_rect(Rect2(SCAN.position + Vector2(18, 16), Vector2(178, 118)),
		Color(0.86, 0.84, 0.76, 0.12))
	draw_line(SCAN.position + Vector2(18, 134), SCAN.position + Vector2(196, 134),
		Color(1, 1, 1, 0.16), 2.0)
	draw_rect(Rect2(SCAN.end - Vector2(170, 102), Vector2(120, 72)),
		Color(0.65, 0.58, 0.45, 0.12))

	var bust_pos: Vector2 = state["pos"]
	_draw_bust(bust_pos)
	var frame := _frame_rect()
	var fcol := Theme90.SUCCESS if inside else Theme90.ACCENT_LIGHT
	Theme90.draw_dashed_box(self, frame, fcol, 5.0, 2.0)
	# Уголки рамки.
	var corner := 12.0
	for p in [frame.position, Vector2(frame.end.x, frame.position.y),
			Vector2(frame.position.x, frame.end.y), frame.end]:
		draw_circle(p, 2.2, fcol)
	draw_line(frame.position + Vector2(0, corner),
		frame.position + Vector2(0, 0), fcol, 2.0)
	draw_line(frame.position + Vector2(0, 0),
		frame.position + Vector2(corner, 0), fcol, 2.0)
	draw_line(Vector2(frame.end.x, frame.position.y),
		Vector2(frame.end.x, frame.position.y + corner), fcol, 2.0)
	draw_line(Vector2(frame.end.x - corner, frame.position.y),
		Vector2(frame.end.x, frame.position.y), fcol, 2.0)

	if _flash > 0.0:
		var a := _flash / 0.22
		draw_rect(SCAN, Color(1, 1, 1, 0.22 * a))
		var text := "В РАМКЕ" if _last_capture_ok else "МИМО"
		_draw_label(text, Vector2(SCAN.get_center().x - 60.0, SCAN.position.y + 12.0),
			16, Theme90.SUCCESS if _last_capture_ok else Theme90.ERROR, 120.0,
			HORIZONTAL_ALIGNMENT_CENTER)

	_draw_label("ВЕДИТЕ РАМКУ МЫШЬЮ · ЛКМ / ПРОБЕЛ — СНИМОК",
		Vector2(24.0, 344.0), 10, Theme90.SHADE, 430.0)
	_draw_label("рамка %d×%d" % [roundi(_frame_size().x), roundi(_frame_size().y)],
		Vector2(466.0, 344.0), 10, Theme90.SHADE, 156.0,
		HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_bust(pos: Vector2) -> void:
	var b := Rect2(pos - BUST * 0.5, BUST)
	draw_circle(Vector2(pos.x, b.end.y - 4.0), 12.0, Color(0, 0, 0, 0.16))
	# Плечи.
	draw_colored_polygon(PackedVector2Array([
		Vector2(pos.x - 15.0, b.end.y - 2.0),
		Vector2(pos.x - 9.0, b.position.y + 26.0),
		Vector2(pos.x + 9.0, b.position.y + 26.0),
		Vector2(pos.x + 15.0, b.end.y - 2.0)]), Theme90.NAVY)
	# Голова.
	draw_circle(Vector2(pos.x, b.position.y + 14.0), 9.0, Theme90.NAVY)
	# Шея.
	draw_rect(Rect2(Vector2(pos.x - 3.0, b.position.y + 22.0), Vector2(6, 8)),
		Theme90.NAVY_DEEP)
	# Лицо/блик — чтобы бюст читался.
	draw_circle(Vector2(pos.x + 3.0, b.position.y + 12.0), 1.5, Theme90.PAPER_HI)
