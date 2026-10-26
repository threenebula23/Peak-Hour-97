class_name StressOverlay
extends ColorRect
## «ЖАРА»: процедурный слой нагрева узла.
##
## Модель heat — чистая функция от снимка состояния часа (SLA, запросы,
## атаки, канал, буфер, очередь, прогресс часа) плюс короткие импульсы
## событий. Сглаживание — экспоненциальное через UiMotion.k(), без твинов
## в _process. Слой не читает экран (нет hint_screen_texture), поэтому
## модалки и тосты, добавленные выше, не тонируются.
##
## В headless материал не создаётся, слой скрыт. Обычно тикается из Main:
## set_inputs(snapshot); tick(delta, paused).

signal heat_changed(heat: float, level: int, temp_c: int)
signal level_changed(level: int)
signal kick(px: int)

const SHADER_PATH := "res://shaders/stress.gdshader"

## Границы уровней: 0→1, 1→2, 2→3. Вниз — на 0.04 раньше (гистерезис).
const LEVEL_T := [0.34, 0.58, 0.80]
const LEVEL_HYST := 0.04
const LEVEL_SWITCH := 0.4

const TEMP_BASE := 36.0
const TEMP_SPAN := 59.0

const TAU_GROW := 0.90
const TAU_DECAY := 2.80
const TAU_FAST := 0.35
const TAU_HOUR_END := 0.60
const TAU_IMPULSE := 3.5
const TAU_RELIEF := 1.2
const TAU_FLASH := 0.09

const UNIFORM_HZ := 20.0

var heat := 0.0
var level := 0
var temp_c := 36
## Разбивка последнего расчёта: p_* и сырые значения для подсказки.
var breakdown: Dictionary = {}

var _target := 0.0
var _inputs: Dictionary = {}
var _impulse := 0.0
var _relief := 0.0
var _fast_left := 0.0
var _flash := 0.0
var _end_hour := false
var _forced := false
var _reduced := false
var _level_timer := 0.0
var _uniform_accum := 0.0
var _mat: ShaderMaterial = null
var _headless := false
var _last_heat := -1.0
var _last_level := -1
var _last_temp := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	color = Color(1, 1, 1, 1)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_headless = DisplayServer.get_name() == "headless"
	_build()


func _build() -> void:
	if _headless:
		visible = false
		set_process(false)
		return
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_warning("StressOverlay: не удалось загрузить %s" % SHADER_PATH)
		visible = false
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material = _mat
	_apply_uniforms()
	visible = false
	# Тикается вручную из Main._process — собственный _process не нужен.
	set_process(false)


# --- публичный API ---------------------------------------------------------

func set_inputs(inputs: Dictionary) -> void:
	# Снимок уже новый на каждый кадр — shallow-ссылки достаточно, без deep copy.
	_inputs = inputs
	_end_hour = bool(_inputs.get("end_hour", _end_hour))
	_target = _evaluate(false)


func set_reduced(value: bool) -> void:
	_reduced = bool(value)
	if _reduced:
		_flash = 0.0
	_apply_uniforms()


func force_heat(value: float) -> void:
	_forced = true
	heat = clampf(value, 0.0, 1.0)
	_target = heat
	_fast_left = 0.0
	_end_hour = false
	_evaluate(true)
	var next_level := 0
	for i in LEVEL_T.size():
		if heat >= float(LEVEL_T[i]):
			next_level = i + 1
	if next_level != level:
		level = next_level
		level_changed.emit(level)
	temp_c = _temp_for(heat)
	_apply_uniforms()
	_refresh_visibility()
	_emit_heat()


func reset() -> void:
	_forced = false
	heat = 0.0
	_target = 0.0
	level = 0
	temp_c = 36
	_impulse = 0.0
	_relief = 0.0
	_fast_left = 0.0
	_flash = 0.0
	_end_hour = false
	_level_timer = 0.0
	_inputs.clear()
	breakdown.clear()
	_apply_uniforms()
	_refresh_visibility()
	if _last_level != 0:
		level_changed.emit(0)
	_emit_heat()


## strength: для sla_drop — абсолютное падение SLA, для остальных — масштаб.
func notify(kind: String, strength: float = 1.0) -> void:
	var scale := clampf(strength, 0.0, 4.0)
	match kind:
		"attack_start":
			_impulse += 0.20 * maxf(scale, 0.0)
			_fast_left = maxf(_fast_left, 1.0)
			_flash = maxf(_flash, 0.35)
			kick.emit(1)
		"attack_fail":
			_impulse += 0.24 * maxf(scale, 0.0)
			_fast_left = 1.2
			_flash = 1.0
			kick.emit(2)
		"expired":
			_impulse += 0.20 * maxf(scale, 0.0)
			_fast_left = 1.2
			_flash = 1.0
			kick.emit(1)
		"packet_lost":
			_impulse += 0.12 * maxf(scale, 0.0)
			_fast_left = 1.0
			_flash = maxf(_flash, 0.6)
			kick.emit(1)
		"sla_drop":
			var drop := maxf(strength, 0.0)
			_impulse += clampf(0.06 * drop / 5.0, 0.05, 0.22)
			_fast_left = 1.1
			_flash = maxf(_flash, 0.7)
			kick.emit(2)
		"relief":
			_relief += 0.10 * maxf(scale, 0.0)
		"hour_end":
			_end_hour = true
		"spawn_frozen":
			_impulse += 0.05 * maxf(scale, 0.0)
		_:
			pass
	_impulse = minf(_impulse, 0.60)
	_relief = minf(_relief, 0.30)
	_flash = clampf(_flash, 0.0, 1.0)


func tick(delta: float, paused: bool) -> void:
	if _headless:
		return
	var dt := clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return
	if not paused:
		if _fast_left > 0.0:
			_fast_left = maxf(0.0, _fast_left - dt)
		_impulse -= _impulse * UiMotion.k(dt, TAU_IMPULSE)
		_relief -= _relief * UiMotion.k(dt, TAU_RELIEF)
		_target = _evaluate(false)
		if _end_hour:
			# Конец часа: остывание быстрым tau 0.60 независимо от SLA/очередей.
			_target = 0.0
		if not _forced:
			var tau := TAU_GROW
			if _target < heat:
				tau = TAU_DECAY
				if _fast_left > 0.0:
					tau = TAU_FAST
				elif _end_hour:
					tau = TAU_HOUR_END
			heat += (_target - heat) * UiMotion.k(dt, tau)
			heat = UiMotion.clamp01(heat)
		else:
			_target = heat
		_level_timer = maxf(0.0, _level_timer - dt)
		_update_level()
	_flash = maxf(0.0, _flash - _flash * UiMotion.k(dt, TAU_FLASH))
	temp_c = _temp_for(heat)
	_uniform_accum += dt
	if _uniform_accum >= 1.0 / UNIFORM_HZ:
		_uniform_accum = 0.0
		_apply_uniforms()
		# Разбивка для тултипа — 20 Гц, а не каждый кадр (30 ключей).
		_evaluate(true)
		_emit_heat()
	_refresh_visibility()


# --- модель ----------------------------------------------------------------

func _evaluate(collect_breakdown: bool = false) -> float:
	var sla_cap := maxf(0.001, _num("sla_cap", 60.0))
	var sla := _num("sla", sla_cap)
	var r_sla := UiMotion.clamp01(sla / sla_cap)

	var req_limit := maxf(1.0, _num("req_limit", 1.0))
	var req_active := maxf(0.0, _num("req_active", 0.0))
	var attacks := maxf(0.0, _num("attacks", 0.0))
	var attack_tier := maxf(0.0, _num("attack_tier", 0.0))
	var channel_ratio := UiMotion.clamp01(_num("channel_ratio", 0.0))
	var buffer_ratio := UiMotion.clamp01(_num("buffer_ratio", 0.0))
	var urgent := maxf(0.0, _num("urgent", 0.0))
	var sending := maxf(0.0, _num("sending", 0.0))
	var queued := maxf(0.0, _num("queued", 0.0))
	var slots_max := maxf(1.0, _num("slots_max", 1.0))
	var hour_progress := UiMotion.clamp01(_num("hour_progress", 0.0))

	var p_sla := pow(1.0 - r_sla, 1.6)
	var p_req := UiMotion.clamp01((req_active / req_limit - 0.5) / 0.5)
	var p_atk := UiMotion.clamp01(attacks / 2.0) \
		* (0.75 + 0.25 * UiMotion.clamp01(attack_tier / 4.0))
	var p_ch := UiMotion.clamp01((channel_ratio - 0.60) / 0.60)
	var p_buf := UiMotion.clamp01((buffer_ratio - 0.60) / 0.40)
	var p_urg := UiMotion.clamp01(urgent / req_limit)
	var p_send := UiMotion.clamp01(sending / slots_max)
	var p_q := UiMotion.clamp01(queued / slots_max)
	var p_hour := pow(hour_progress, 1.6)

	var base := 1.0 \
		- (1.0 - p_sla) \
		* (1.0 - 0.55 * p_req) \
		* (1.0 - 0.45 * p_atk) \
		* (1.0 - 0.30 * p_ch) \
		* (1.0 - 0.18 * p_buf) \
		* (1.0 - 0.12 * p_urg) \
		* (1.0 - 0.12 * p_send) \
		* (1.0 - 0.10 * p_q)

	var target := UiMotion.clamp01(base + 0.06 * p_hour
		+ 0.20 * _impulse - 0.10 * _relief)
	if r_sla < 0.40:
		target = maxf(target, 0.60 + 0.22 * (0.40 - r_sla) / 0.20)
	if r_sla < 0.20:
		target = maxf(target, 0.82 + 0.16 * (0.20 - r_sla) / 0.20)
	target = UiMotion.clamp01(target)

	if collect_breakdown:
		breakdown = {
			"sla": sla,
			"sla_cap": sla_cap,
			"sla_ratio": r_sla,
			"req_active": int(roundf(req_active)),
			"req_limit": int(roundf(req_limit)),
			"attacks": int(roundf(attacks)),
			"attack_tier": int(roundf(attack_tier)),
			"channel": _num("channel", 0.0),
			"channel_capacity": _num("channel_capacity", 10.0),
			"channel_ratio": channel_ratio,
			"buffer_used": int(roundf(_num("buffer_used", 0.0))),
			"buffer_max": int(roundf(_num("buffer_max", 0.0))),
			"buffer_ratio": buffer_ratio,
			"urgent": int(roundf(urgent)),
			"sending": int(roundf(sending)),
			"queued": int(roundf(queued)),
			"slots_max": int(roundf(slots_max)),
			"hour_progress": hour_progress,
			"p_sla": p_sla,
			"p_req": p_req,
			"p_atk": p_atk,
			"p_ch": p_ch,
			"p_buf": p_buf,
			"p_urg": p_urg,
			"p_send": p_send,
			"p_q": p_q,
			"p_hour": p_hour,
			"base": base,
			"target": target,
		}
	return target


func _num(key: String, fallback: float) -> float:
	var raw = _inputs.get(key, fallback)
	if raw == null:
		return fallback
	return float(raw)


func _temp_for(value: float) -> int:
	return clampi(int(roundf(TEMP_BASE + TEMP_SPAN * value)), 36, 95)


func _update_level() -> void:
	if _level_timer > 0.0:
		return
	var next := level
	if level < LEVEL_T.size() and heat >= float(LEVEL_T[level]):
		next = level + 1
	elif level > 0 and heat <= float(LEVEL_T[level - 1]) - LEVEL_HYST:
		next = level - 1
	if next != level:
		level = clampi(next, 0, LEVEL_T.size())
		_level_timer = LEVEL_SWITCH
		level_changed.emit(level)
		_emit_heat()


# --- шейдер и сигналы ------------------------------------------------------

func _apply_uniforms() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("heat", heat)
	_mat.set_shader_parameter("level", float(level))
	_mat.set_shader_parameter("flash", _flash)
	_mat.set_shader_parameter("reduced", 1.0 if _reduced else 0.0)
	_mat.set_shader_parameter("tint_warm", Theme90.HEAT_WARM)
	_mat.set_shader_parameter("tint_hot", Theme90.HEAT_HOT)
	_mat.set_shader_parameter("tint_crit", Theme90.HEAT_CRIT)


func _refresh_visibility() -> void:
	if _mat == null:
		visible = false
		return
	visible = heat >= 0.05 or _flash > 0.001


func _emit_heat() -> void:
	if absf(heat - _last_heat) < 0.0005 \
			and level == _last_level and temp_c == _last_temp:
		return
	_last_heat = heat
	_last_level = level
	_last_temp = temp_c
	heat_changed.emit(heat, level, temp_c)
