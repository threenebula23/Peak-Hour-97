class_name DdosGame
extends MiniGame
## Атака «Щит» (ddos). Конечная волна красных пакетов падает сверху.
## Щит следует за мышью по X (кнопку держать не нужно) и двигается стрелками.
##
## Движение только dt-based: p.y += speed * delta, без покадрового damping.
## Раунд заканчивается сам, когда каждый пакет волны отбит или пробил низ.
## Качество: q = blocked / total_packets (все пакеты волны входят в total).

const GAME_ID := "ddos"
const TITLE_RU := "ЩИТ"

## Поле заканчивается на y=294, чтобы подсказка (y=298..311) не легла на доску.
const FIELD := Rect2(18.0, 58.0, 604.0, 236.0)
const PACKET_W := 18.0
const PACKET_H := 20.0
const SHIELD_H := 16.0
const SHIELD_Y := 270.0
const FIELD_PAD := 10.0
const SHIELD_PAD := 8.0
const MIN_SPACING := 12.0

const TIERS := {
	1: {"packets": 8, "speed": 110.0, "shield_width": 260.0, "interval": 0.55, "threshold": 0.60},
	2: {"packets": 10, "speed": 140.0, "shield_width": 220.0, "interval": 0.45, "threshold": 0.65},
	3: {"packets": 12, "speed": 170.0, "shield_width": 180.0, "interval": 0.35, "threshold": 0.70},
	4: {"packets": 14, "speed": 200.0, "shield_width": 150.0, "interval": 0.28, "threshold": 0.75},
}

var _wave: Dictionary = {}
var _packets: Array = []
var _events: Array = []
var _spawned: int = 0
var _blocked: int = 0
var _breached: int = 0
var _elapsed: float = 0.0
var _shield_center: float = 320.0
var _flash: float = 0.0
var _round_done: bool = false


func _own_game_id() -> String:
	return GAME_ID


func title() -> String:
	return TITLE_RU


func quality() -> float:
	if _finished:
		return quality_value
	return ddos_quality(_blocked, int(_wave.get("total", 0)))


func _setup() -> void:
	_wave = generate_wave(tier, seed_value)
	_packets.clear()
	_events.clear()
	_spawned = 0
	_blocked = 0
	_breached = 0
	_elapsed = 0.0
	_shield_center = float(_wave.get("start_shield_x", 320.0))
	_flash = 0.0
	_round_done = false


# --- параметры -------------------------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var base: Dictionary = (TIERS.get(t, TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier(GAME_ID, t)
	if row.is_empty():
		return base
	for key in ["packets"]:
		if row.has(key):
			base[key] = int(row[key])
	for key in ["speed", "shield_width", "interval", "threshold"]:
		if row.has(key):
			base[key] = float(row[key])
	return base


# --- генерация -------------------------------------------------------------

static func generate_wave(p_tier: int, seed: int) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var p := tier_params(t)
	var total := clampi(int(p.get("packets", 8)), 4, 24)
	var base_speed := maxf(40.0, float(p.get("speed", 110.0)))
	var shield_width := clampf(float(p.get("shield_width", 260.0)), 80.0, FIELD.size.x)
	var interval := maxf(0.10, float(p.get("interval", 0.55)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var left := FIELD.position.x + FIELD_PAD
	var right := FIELD.end.x - FIELD_PAD - PACKET_W
	var band := (right - left) / float(total)
	var bands: Array = []
	for i in range(total):
		bands.append(i)
	_shuffle(bands, rng)

	var packets: Array = []
	var spawn_at := 0.35
	for i in range(total):
		var band_index := int(bands[i])
		var band_left := left + band * float(band_index)
		var inner := maxf(1.0, band - 12.0 - PACKET_W)
		var x := band_left + 6.0 + rng.randf() * inner
		x = clampf(x, left, right)
		var speed := base_speed * rng.randf_range(0.90, 1.10)
		if i > 0:
			spawn_at += interval * rng.randf_range(0.85, 1.15)
		packets.append({
			"id": i,
			"x": x,
			"speed": speed,
			"spawn_at": spawn_at,
		})

	var min_center := FIELD.position.x + shield_width * 0.5 + SHIELD_PAD
	var max_center := FIELD.end.x - shield_width * 0.5 - SHIELD_PAD
	var start_shield := rng.randf_range(min_center, max_center)

	return {
		"tier": t,
		"packets": packets,
		"total": total,
		"speed": base_speed,
		"shield_width": shield_width,
		"interval": interval,
		"threshold": float(p.get("threshold", 0.6)),
		"start_shield_x": start_shield,
		"field": FIELD,
		"shield_y": SHIELD_Y,
		"packet_w": PACKET_W,
		"packet_h": PACKET_H,
	}


static func validate_wave(data: Dictionary) -> bool:
	var packets: Array = data.get("packets", [])
	var total := int(data.get("total", 0))
	if total <= 0 or packets.size() != total:
		return false
	var shield_width := float(data.get("shield_width", 0.0))
	if shield_width <= 0.0 or shield_width > FIELD.size.x:
		return false
	var base_speed := float(data.get("speed", 0.0))
	var last_spawn := -1.0
	var xs: Array = []
	for packet in packets:
		var p: Dictionary = packet
		var x := float(p.get("x", -1000.0))
		var speed := float(p.get("speed", -1.0))
		var spawn_at := float(p.get("spawn_at", -1.0))
		if is_nan(x) or is_inf(x) or is_nan(speed) or is_inf(speed):
			return false
		if is_nan(spawn_at) or is_inf(spawn_at) or spawn_at < 0.0 or spawn_at > 30.0:
			return false
		if x < FIELD.position.x + FIELD_PAD - 0.5 or x > FIELD.end.x - FIELD_PAD - PACKET_W + 0.5:
			return false
		if speed < base_speed * 0.89 or speed > base_speed * 1.11:
			return false
		if spawn_at <= last_spawn:
			return false
		last_spawn = spawn_at
		xs.append(x)
		# Щит такой ширины может физически перекрыть пакет.
		var center := x + PACKET_W * 0.5
		var min_center := FIELD.position.x + shield_width * 0.5 + SHIELD_PAD
		var max_center := FIELD.end.x - shield_width * 0.5 - SHIELD_PAD
		var reachable := clampf(center, min_center, max_center)
		if absf(reachable - center) > shield_width * 0.5 - PACKET_W * 0.5 + 0.5:
			return false

	xs.sort()
	for i in range(1, xs.size()):
		if float(xs[i]) - float(xs[i - 1]) < MIN_SPACING - 0.01:
			return false
	return true


static func ddos_quality(blocked: int, total_packets: int) -> float:
	if total_packets <= 0:
		return 0.0
	return clampf(float(blocked) / float(total_packets), 0.0, 1.0)


# --- игра ------------------------------------------------------------------

func _shield_rect() -> Rect2:
	var shield_width := float(_wave.get("shield_width", 260.0))
	var min_center := FIELD.position.x + shield_width * 0.5 + SHIELD_PAD
	var max_center := FIELD.end.x - shield_width * 0.5 - SHIELD_PAD
	_shield_center = clampf(_shield_center, min_center, max_center)
	return Rect2(_shield_center - shield_width * 0.5, SHIELD_Y, shield_width, SHIELD_H)


func _spawn_packet(packet: Dictionary) -> void:
	_packets.append({
		"id": int(packet.get("id", 0)),
		"x": float(packet.get("x", 0.0)),
		"y": FIELD.position.y - PACKET_H,
		"speed": float(packet.get("speed", 100.0)),
		"resolved": false,
	})


func _add_event(pos: Vector2, text: String, color: Color) -> void:
	_events.append({"pos": pos, "text": text, "color": color, "ttl": 0.7})


func _process(delta: float) -> void:
	if _finished or _round_done:
		return
	_elapsed += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)

	var wave_packets: Array = _wave.get("packets", [])
	while _spawned < wave_packets.size() \
			and _elapsed >= float((wave_packets[_spawned] as Dictionary).get("spawn_at", 0.0)):
		_spawn_packet(wave_packets[_spawned])
		_spawned += 1

	var shield := _shield_rect()
	var active: Array = []
	for entry in _packets:
		var p: Dictionary = entry
		var prev_bottom := float(p["y"]) + PACKET_H
		p["y"] = float(p["y"]) + float(p["speed"]) * delta
		var bottom := float(p["y"]) + PACKET_H
		var px := float(p["x"])

		if not bool(p["resolved"]) and prev_bottom < SHIELD_Y and bottom >= SHIELD_Y:
			if px + PACKET_W >= shield.position.x and px <= shield.end.x:
				p["resolved"] = true
				_blocked += 1
				_add_event(Vector2(px + PACKET_W * 0.5, SHIELD_Y - 10.0), "ОТБИТО",
					Theme90.SUCCESS)
				_play_sfx(&"stamp")

		if not bool(p["resolved"]) and bottom >= FIELD.end.y:
			p["resolved"] = true
			_breached += 1
			_flash = 0.22
			_add_event(Vector2(px + PACKET_W * 0.5, FIELD.end.y - 12.0), "ПРОБОЙ",
				Theme90.ERROR)
			_play_sfx(&"bad")

		if not bool(p["resolved"]):
			active.append(p)
	_packets = active

	for event in _events:
		(event as Dictionary)["ttl"] = float((event as Dictionary)["ttl"]) - delta
		(event as Dictionary)["pos"] = (event as Dictionary)["pos"] + Vector2(0.0, -14.0 * delta)
	_events = _events.filter(func(e): return float(e["ttl"]) > 0.0)

	if _spawned >= wave_packets.size() and _packets.is_empty():
		_round_done = true
		var total := int(_wave.get("total", wave_packets.size()))
		var q := ddos_quality(_blocked, total)
		_result_detail = _with_context("ОТБИТО %d ИЗ %d · ПРОБОЙ %d" % [
			_blocked, total, _breached])
		_finish(q)
	queue_redraw()


func _with_context(text: String) -> String:
	var parts: Array = []
	var reward := str(context.get("reward_text", ""))
	var penalty := str(context.get("penalty_text", ""))
	if not reward.is_empty():
		parts.append(reward)
	if not penalty.is_empty():
		parts.append(penalty)
	parts.append(text)
	return " · ".join(parts)


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if _finished or _round_done:
		return
	_shield_center = local.x
	_queue_shield_redraw()


func _on_pointer_pressed(local: Vector2, event: InputEvent) -> bool:
	if _finished or _round_done:
		return false
	_on_pointer_moved(local, event)
	return true


func _on_key_pressed(keycode: int, event: InputEvent) -> bool:
	if _finished or _round_done:
		return false
	var step := 8.0 if event is InputEventKey and (event as InputEventKey).shift_pressed else 26.0
	match keycode:
		KEY_LEFT, KEY_A:
			_shield_center -= step
			_queue_shield_redraw()
			return true
		KEY_RIGHT, KEY_D:
			_shield_center += step
			_queue_shield_redraw()
			return true
	return false


func _queue_shield_redraw() -> void:
	_shield_rect()
	queue_redraw()


# --- отрисовка -------------------------------------------------------------

func _draw_game() -> void:
	var total := int(_wave.get("total", 0))
	draw_rect(FIELD, Color(0.075, 0.110, 0.120, 1.0))
	draw_rect(FIELD, Color(1, 1, 1, 0.10), false, 1.0)

	var grid := Color(1, 1, 1, 0.055)
	var gx := FIELD.position.x + 28.0
	while gx < FIELD.end.x:
		draw_line(Vector2(gx, FIELD.position.y), Vector2(gx, FIELD.end.y), grid, 1.0)
		gx += 32.0
	var gy := FIELD.position.y + 26.0
	while gy < FIELD.end.y:
		draw_line(Vector2(FIELD.position.x, gy), Vector2(FIELD.end.x, gy), grid, 1.0)
		gy += 26.0

	_draw_label("ОТБИТО %d / %d" % [_blocked, total], Vector2(24.0, 44.0), 12,
		Theme90.INK, 220.0)
	_draw_label("ПРОБОЙ %d" % _breached, Vector2(420.0, 44.0), 12,
		Theme90.ERROR if _breached > 0 else Theme90.SHADE, 200.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	if _flash > 0.0:
		draw_rect(FIELD, Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b,
			0.10 + 0.18 * (_flash / 0.22)))

	for entry in _packets:
		var p: Dictionary = entry
		var rect := Rect2(float(p["x"]), float(p["y"]), PACKET_W, PACKET_H)
		draw_style_box(Theme90.box(Theme90.ERROR, Theme90.ERROR.darkened(0.25), 2, 1,
			Theme90.SHADOW), rect)
		Theme90.text_vcenter(self, Theme90.ui(), rect, "!", 12, Theme90.WHITE,
			-1, HORIZONTAL_ALIGNMENT_CENTER)
		draw_line(Vector2(rect.position.x + 4.0, rect.position.y + 4.0),
			Vector2(rect.end.x - 4.0, rect.end.y - 4.0), Color(1, 1, 1, 0.32), 1.0)

	var shield := _shield_rect()
	draw_style_box(Theme90.box(Theme90.ACCENT, Theme90.NAVY_DEEP, 3, 1, Theme90.SHADOW), shield)
	Theme90.draw_hatch(self, shield.grow(-2.0), Color(1, 1, 1, 0.14), 7.0)
	Theme90.text_vcenter(self, Theme90.ui(), shield, "ЩИТ", 10, Theme90.WHITE,
		-1, HORIZONTAL_ALIGNMENT_CENTER)

	for event in _events:
		var e: Dictionary = event
		var alpha := clampf(float(e["ttl"]) / 0.55, 0.0, 1.0)
		var pos: Vector2 = e["pos"]
		var col: Color = e["color"]
		Theme90.text(self, Theme90.ui(), pos - Vector2(24.0, 0.0), str(e["text"]), 10,
			Color(col.r, col.g, col.b, alpha), 48.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_footer_hint() -> void:
	# Подсказка живёт в свободной полосе между полем (y=294) и футером (y=320).
	_draw_label("ЩИТ СЛЕДУЕТ ЗА МЫШЬЮ ПО X · СТРЕЛКИ ← → ТОЖЕ", Vector2(18.0, 298.0),
		10, Theme90.SHADE, 604.0)


# --- служебное -------------------------------------------------------------

static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
