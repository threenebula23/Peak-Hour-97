extends MiniGame
## «Уровни» (sound). Вертикальные фейдеры, зелёные целевые зоны.
## T1–T3: 4/5/6 каналов, допуск 11/8/6%, на T2/T3 — синусоидальный дрейф.
## Таймера нет; качество фиксируется кнопкой «ЗАПИСАТЬ».

const TIERS := {
	1: {"count": 4, "tolerance": 0.11, "drift_amp": 0.0, "drift_hz": 0.0},
	2: {"count": 5, "tolerance": 0.08, "drift_amp": 0.02, "drift_hz": 0.15},
	3: {"count": 6, "tolerance": 0.06, "drift_amp": 0.03, "drift_hz": 0.25},
}
const LABELS := [
	["НЧ", "60"], ["НСЧ", "250"], ["СЧ", "1К"], ["ВСЧ", "4К"], ["ВЧ", "12К"],
	["УВЧ", "20К"],
]
const TRACK_TOP := 92.0
const TRACK_H := 154.0
const TRACK_W := 30.0

var state: Dictionary = {}
var _values: Array[float] = []
var _targets: Array[float] = []
var _phases: Array[float] = []
var _time: float = 0.0
var _dragging: int = -1
var _active: int = 0


func _own_game_id() -> String:
	return "sound"


func _setup() -> void:
	state = generate(tier, seed_value)
	_values.clear()
	_targets.clear()
	_phases.clear()
	for v in state.get("starts", []):
		_values.append(float(v))
	for v in state.get("targets", []):
		_targets.append(float(v))
	for p in state.get("phases", []):
		_phases.append(float(p))
	_time = 0.0
	_dragging = -1
	_active = 0


func _goal_text() -> String:
	return "СОВМЕСТИТЕ БЕГУНКИ С ЗЕЛЁНЫМИ ПОЛОСАМИ · ENTER — ЗАПИСАТЬ"


func _result_stats() -> String:
	var in_zone := 0
	for i in range(_values.size()):
		var tol := float(state.get("tolerance", 0.11))
		if absf(_values[i] - _current_target(i)) <= tol:
			in_zone += 1
	return "В ЗОНЕ %d/%d · ДОПУСК ±%d%%" % [in_zone, _values.size(),
		roundi(float(state.get("tolerance", 0.11)) * 100.0)]


# --- параметры/чистая логика ----------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIERS.get(clampi(p_tier, 1, 3), TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("sound", p_tier)
	if row.is_empty():
		return base
	if row.has("channels"):
		base["count"] = int(row["channels"])
	if row.has("count"):
		base["count"] = int(row["count"])
	if row.has("tolerance"):
		base["tolerance"] = float(row["tolerance"])
	if row.has("drift"):
		base["drift_amp"] = float(row["drift"])
	if row.has("drift_amp"):
		base["drift_amp"] = float(row["drift_amp"])
	if row.has("drift_hz"):
		base["drift_hz"] = float(row["drift_hz"])
	return base


static func generate(p_tier: int, seed: int) -> Dictionary:
	var p := tier_params(p_tier)
	var count := clampi(int(p.get("count", 3)), 2, 6)
	var tol := clampf(float(p.get("tolerance", 0.16)), 0.02, 0.30)
	var amp := maxf(0.0, float(p.get("drift_amp", 0.0)))
	var hz := maxf(0.0, float(p.get("drift_hz", 0.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var targets: Array[float] = []
	var min_gap := tol * 2.0
	var lo := tol
	var hi := 1.0 - tol
	var attempts := 0
	while targets.size() < count and attempts < 600:
		attempts += 1
		var candidate := rng.randf_range(lo, hi)
		var ok := true
		for t in targets:
			if absf(candidate - float(t)) < min_gap - 0.0001:
				ok = false
				break
		if ok:
			targets.append(candidate)
	# Резерв: равномерная сетка, если rejection не сошёлся.
	if targets.size() < count:
		targets.clear()
		var span := maxf(0.0, hi - lo)
		var step := span / float(maxi(1, count - 1))
		for i in range(count):
			targets.append(clampf(lo + step * float(i), 0.02, 0.98))
	targets.sort()

	var starts: Array[float] = []
	var phases: Array[float] = []
	for i in range(count):
		var target := float(targets[i])
		var sign := -1.0 if rng.randf() < 0.5 else 1.0
		var offset := rng.randf_range(tol * 1.10, tol * 2.8)
		var start := clampf(target + sign * offset, 0.02, 0.98)
		if absf(start - target) <= tol * 1.02:
			start = clampf(target - sign * offset, 0.02, 0.98)
		if absf(start - target) <= tol:
			start = clampf(target + tol * 2.0, 0.02, 0.98)
		if absf(start - target) <= tol:
			start = clampf(target - tol * 2.0, 0.02, 0.98)
		if absf(start - target) <= tol:
			start = 0.02 if target >= 0.5 else 0.98
		starts.append(start)
		phases.append(rng.randf_range(0.0, TAU))
	return {
		"tier": clampi(p_tier, 1, 3),
		"count": count,
		"tolerance": tol,
		"drift_amp": amp,
		"drift_hz": hz,
		"targets": targets,
		"starts": starts,
		"phases": phases,
	}


static func target_at(target: float, amp: float, hz: float, phase: float,
		time: float) -> float:
	if amp <= 0.0 or hz <= 0.0:
		return target
	return clampf(target + amp * sin(TAU * hz * time + phase), 0.0, 1.0)


static func channel_quality(value: float, target: float, tol: float) -> float:
	if tol <= 0.0:
		return 1.0 if is_equal_approx(value, target) else 0.0
	return clampf(1.0 - absf(value - target) / (2.0 * tol), 0.0, 1.0)


static func quality_from(values: Array, targets: Array, tol: float,
		amp: float = 0.0, hz: float = 0.0, phases: Array = [], time: float = 0.0) -> float:
	var n := mini(values.size(), targets.size())
	if n <= 0:
		return 0.0
	var total := 0.0
	for i in range(n):
		var target := float(targets[i])
		if amp > 0.0 and hz > 0.0:
			var phase := float(phases[i]) if i < phases.size() else 0.0
			target = target_at(target, amp, hz, phase, time)
		total += channel_quality(float(values[i]), target, tol)
	return clampf(total / float(n), 0.0, 1.0)


func _current_target(i: int) -> float:
	if i < 0 or i >= _targets.size():
		return 0.5
	return target_at(_targets[i], float(state.get("drift_amp", 0.0)),
		float(state.get("drift_hz", 0.0)), _phases[i] if i < _phases.size() else 0.0,
		_time)


func _quality_now() -> float:
	var targets: Array = []
	for i in range(_targets.size()):
		targets.append(_current_target(i))
	return quality_from(_values, targets, float(state.get("tolerance", 0.16)))


func _process(delta: float) -> void:
	if not running:
		return
	if float(state.get("drift_amp", 0.0)) > 0.0:
		_time += maxf(0.0, delta)
		queue_redraw()


# --- геометрия -------------------------------------------------------------

func _track_rect(i: int) -> Rect2:
	var count := _values.size()
	var spacing := minf(104.0, 480.0 / float(maxi(1, count)))
	var center_x := 320.0
	var x := center_x + (float(i) - float(count - 1) * 0.5) * spacing - TRACK_W * 0.5
	return Rect2(x, TRACK_TOP, TRACK_W, TRACK_H)


func _value_to_y(rect: Rect2, value: float) -> float:
	var pad := 7.0
	return rect.position.y + pad + (1.0 - clampf(value, 0.0, 1.0)) * (rect.size.y - pad * 2.0)


func _y_to_value(rect: Rect2, y: float) -> float:
	var pad := 7.0
	var inner := rect.size.y - pad * 2.0
	return clampf(1.0 - (y - rect.position.y - pad) / inner, 0.0, 1.0)


func _fader_at(local: Vector2) -> int:
	for i in range(_values.size()):
		var rect := _track_rect(i)
		if local.x >= rect.position.x - 24.0 and local.x <= rect.end.x + 24.0 \
				and local.y >= rect.position.y - 20.0 and local.y <= rect.end.y + 18.0:
			return i
	return -1


# --- ввод ------------------------------------------------------------------

func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if ACTION_RECT.has_point(local):
		_finish(_quality_now())
		return true
	var idx := _fader_at(local)
	if idx < 0:
		return false
	_dragging = idx
	_active = idx
	_values[idx] = _y_to_value(_track_rect(idx), local.y)
	_play_sfx(&"tick")
	queue_redraw()
	return true


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if _dragging < 0:
		return
	_values[_dragging] = _y_to_value(_track_rect(_dragging), local.y)
	queue_redraw()


func _on_pointer_released(_local: Vector2, _event: InputEvent) -> void:
	_dragging = -1


func _on_key_pressed(keycode: int, event: InputEvent) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_finish(_quality_now())
		return true
	if keycode == KEY_LEFT or keycode == KEY_A:
		_active = posmod(_active - 1, _values.size())
		queue_redraw()
		return true
	if keycode == KEY_RIGHT or keycode == KEY_D:
		_active = (_active + 1) % _values.size()
		queue_redraw()
		return true
	if keycode in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]:
		var key_event := event as InputEventKey
		var step := 0.005 if key_event != null and key_event.shift_pressed else 0.02
		var sign := 1.0 if keycode in [KEY_UP, KEY_W] else -1.0
		_values[_active] = clampf(_values[_active] + sign * step, 0.0, 1.0)
		queue_redraw()
		return true
	return false


# --- отрисовка -------------------------------------------------------------

func _draw_game() -> void:
	var tol := float(state.get("tolerance", 0.16))
	var in_zone := 0
	for i in range(_values.size()):
		if absf(_values[i] - _current_target(i)) <= tol:
			in_zone += 1
	_draw_label("МИКШЕР · КАНАЛ 97", Vector2(24.0, 46.0), 10, Theme90.ACCENT, 240.0)
	_draw_label("В ЗОНЕ %d / %d · ДОПУСК ±%d%%" % [in_zone, _values.size(),
		roundi(tol * 100.0)], Vector2(280.0, 46.0), 10,
		Theme90.SUCCESS if in_zone == _values.size() else Theme90.DARK, 320.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	var panel := Rect2(18.0, 58.0, 604.0, 250.0)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 4, 1), panel)

	# Общая шкала 100/50/0.
	var first := _track_rect(0)
	for v in [1.0, 0.5, 0.0]:
		var y := _value_to_y(first, v)
		Theme90.text(self, Theme90.ui(), Vector2(first.position.x - 44.0, y - 6.0),
			"%d" % roundi(v * 100.0), 10, Theme90.DARK, 34.0,
			HORIZONTAL_ALIGNMENT_RIGHT)

	for i in range(_values.size()):
		var rect := _track_rect(i)
		var target := _current_target(i)
		var active := i == _active
		draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 3, 1), rect)
		var y_top := _value_to_y(rect, minf(1.0, target + tol))
		var y_bottom := _value_to_y(rect, maxf(0.0, target - tol))
		draw_rect(Rect2(rect.position.x + 2.0, y_top, rect.size.x - 4.0,
			maxf(2.0, y_bottom - y_top)), Color(Theme90.SUCCESS.r, Theme90.SUCCESS.g,
			Theme90.SUCCESS.b, 0.30))
		draw_line(Vector2(rect.position.x - 4.0, _value_to_y(rect, target)),
			Vector2(rect.end.x + 4.0, _value_to_y(rect, target)), Theme90.SUCCESS, 2.0)
		var y := _value_to_y(rect, _values[i])
		draw_rect(Rect2(rect.position.x + 4.0, y, rect.size.x - 8.0,
			rect.end.y - y - 7.0), Color(Theme90.ACCENT.r, Theme90.ACCENT.g,
			Theme90.ACCENT.b, 0.24))
		draw_style_box(Theme90.box(Theme90.WHITE, Theme90.ACCENT, 3, 1,
			Theme90.SHADOW), Rect2(rect.position.x - 7.0, y - 6.0, rect.size.x + 14.0, 12.0))
		if active:
			Theme90.draw_dashed_box(self, rect.grow(3.0), Theme90.ACCENT, 3.0, 1.0)
		var label: Array = LABELS[i % LABELS.size()]
		Theme90.text(self, Theme90.ui(), Vector2(rect.position.x - 10.0,
			rect.end.y + 8.0), str(label[0]), 12, Theme90.DARK, rect.size.x + 20.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		Theme90.text(self, Theme90.ui(), Vector2(rect.position.x - 10.0,
			rect.end.y + 23.0), "%s · %d%%" % [str(label[1]), roundi(_values[i] * 100.0)],
			10, Theme90.DARK, rect.size.x + 20.0, HORIZONTAL_ALIGNMENT_CENTER)

	_draw_action_button(ACTION_RECT, "ЗАПИСАТЬ", true, true)
