extends Node
## Ambient — фоновый слой железа (autoload).
##
## Машина, а не существо: PSU/трансформатор гудит всегда, вентилятор
## реагирует только на устойчивую нагрузку, HDD издаёт дискретные seek.
## Никаких человеческих звуков и UI-панелей — только звук.
##
## Старт только по первому жесту (web autoplay): до него все плееры в −80 dB.
## Громкость масштабируется общим оффсетом от Audio.music_volume.
##
## Контекст (Main.controller.hour_director) только читается: если его нет —
## состояние idle без ошибок. Сигналы директора переподключаются, если он
## пересоздан.

const SILENCE_DB := -80.0

const PSU_PATH := "res://audio/music/hum.wav"
const FAN_PATH := "res://audio/amb/fan_loop.wav"
const ROOM_PATH := "res://audio/amb/room_loop.wav"
const SEEK_SHORT_PATH := "res://audio/amb/seek_short.wav"
const SEEK_SERIES_PATH := "res://audio/amb/seek_series.wav"

const PSU_IDLE_DB := -28.0
const PSU_LOAD_DB := -23.0
const PSU_SUSPEND_DB := -30.0
const FAN_IDLE_DB := -38.0
const FAN_LOAD_DB := -24.0
const ROOM_DB := -38.0
const SEEK_DB := -30.0
## Суммарная подложка (PSU + fan + room) не выше этого уровня.
const MAX_BACKING_DB := -18.0

const UNLOCK_FADE := 0.25
const SUSPEND_FADE := 0.3
const FAN_INERTIA := 3.0
const SEEK_COOLDOWN := 0.12
const SEEK_PROBABILITY := 0.5
const POLL_INTERVAL := 0.25


## Плавный «голос»: хранит текущую/целевую громкость и линейно едет к цели.
class Voice:
	var player: AudioStreamPlayer
	var current_db: float = -80.0
	var target_db: float = -80.0
	var _start_db: float = -80.0
	var _duration: float = 0.0
	var _elapsed: float = 0.0

	func _init(p: AudioStreamPlayer) -> void:
		player = p
		player.volume_db = current_db

	func set_target(db: float, duration: float, force: bool = false) -> void:
		db = maxf(db, -80.0)
		# Цель не изменилась — текущий ramp (в т.ч. fade-in) не перезапускаем.
		if not force and absf(db - target_db) < 0.05 and (_duration > 0.0 or absf(current_db - db) < 0.01):
			return
		_start_db = current_db
		target_db = db
		_duration = maxf(duration, 0.0)
		_elapsed = 0.0
		if _duration <= 0.0:
			current_db = target_db
			player.volume_db = current_db

	func snap_to(db: float) -> void:
		target_db = maxf(db, -80.0)
		current_db = target_db
		_duration = 0.0
		_elapsed = 0.0
		player.volume_db = current_db

	func tick(delta: float) -> void:
		if _duration <= 0.0:
			current_db = target_db
		else:
			_elapsed = minf(_elapsed + delta, _duration)
			var t := _elapsed / _duration
			current_db = lerpf(_start_db, target_db, t)
			if _elapsed >= _duration:
				_duration = 0.0
				current_db = target_db
		player.volume_db = current_db


var _psu_player: AudioStreamPlayer
var _fan_player: AudioStreamPlayer
var _room_player: AudioStreamPlayer
var _seek_short_players: Array[AudioStreamPlayer] = []
var _seek_series_player: AudioStreamPlayer

var _psu: Voice
var _fan: Voice
var _room: Voice

var _unlocked: bool = false
var _muted: bool = false
var _state: String = "idle"
var _load: float = 0.0
var _fan_load: float = 0.0
var _seek_cooldown: float = 0.0
var _seek_short_index: int = 0
var _poll_accum: float = 0.0

var _audio: Node = null
var _director: Node = null
var _director_id: int = 0

## Отладка/тесты: зафиксированное состояние поверх контекста.
var _forced: bool = false
var _forced_state: String = "idle"
var _forced_load: float = 0.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_audio = get_node_or_null("/root/Audio")
	_ensure_players()
	_resolve_context()
	# До первого жеста всё молчит.
	_apply_targets(0.0, true)


func _ensure_players() -> void:
	if _psu != null:
		return
	_build_players()


func _exit_tree() -> void:
	_unbind_director()
	# Останавливаем и отпускаем потоки, чтобы не оставлять playback на выходе.
	for player in _all_players():
		if player == null:
			continue
		player.stop()
		player.stream = null


func _all_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	if _psu_player != null:
		players.append(_psu_player)
	if _fan_player != null:
		players.append(_fan_player)
	if _room_player != null:
		players.append(_room_player)
	players.append_array(_seek_short_players)
	if _seek_series_player != null:
		players.append(_seek_series_player)
	return players


# --- жизненный цикл плееров -------------------------------------------------

func _build_players() -> void:
	_psu_player = _make_loop_player(PSU_PATH, "PSU")
	_fan_player = _make_loop_player(FAN_PATH, "Fan")
	_room_player = _make_loop_player(ROOM_PATH, "Room")
	_psu = Voice.new(_psu_player)
	_fan = Voice.new(_fan_player)
	_room = Voice.new(_room_player)

	var short_stream := _load_stream(SEEK_SHORT_PATH)
	for i in 2:
		var player := _make_oneshot_player("SeekShort%d" % i)
		player.stream = short_stream
		_seek_short_players.append(player)
	_seek_series_player = _make_oneshot_player("SeekSeries")
	_seek_series_player.stream = _load_stream(SEEK_SERIES_PATH)


func _make_loop_player(path: String, player_name: String) -> AudioStreamPlayer:
	var player := _make_oneshot_player(player_name)
	var stream := _load_stream(path)
	if stream == null:
		return player
	_enable_loop(stream, path)
	player.stream = stream
	return player


func _make_oneshot_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = &"Master"
	player.volume_db = SILENCE_DB
	add_child(player)
	return player


## Загрузка WAV. Отсутствующий файл — только warning, не падение.
func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Ambient: файл не найден: " + path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Ambient: не удалось загрузить: " + path)
	return stream


## Зацикливание для фонов (как в Audio._enable_loop, без вызова его приватных
## методов): loop на весь файл.
func _enable_loop(stream: AudioStream, path: String) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	if frames <= 0:
		push_warning("Ambient: не удалось вычислить длину для loop: " + path)
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames


# --- ввод: web autoplay -----------------------------------------------------

func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_unlock()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_unlock()


func _unlock() -> void:
	_unlocked = true
	_start_loops()
	_resolve_context()
	_apply_targets(UNLOCK_FADE)


## Петли стартуют только после первого жеста (web autoplay), в −80 dB.
func _start_loops() -> void:
	var loops: Array[AudioStreamPlayer] = [_psu_player, _fan_player, _room_player]
	for player in loops:
		if player != null and player.stream != null and not player.playing:
			player.play()


# --- процесс ----------------------------------------------------------------

func _process(delta: float) -> void:
	_seek_cooldown = maxf(0.0, _seek_cooldown - delta)
	_poll_accum += delta
	if _poll_accum >= POLL_INTERVAL:
		_poll_accum = 0.0
		_resolve_context()
	if _state != "suspend":
		var target := clampf(_load, 0.0, 1.0) if _state == "hour" else 0.0
		_fan_load += (target - _fan_load) * (1.0 - exp(-delta / FAN_INERTIA))
	_apply_targets()
	_tick_voices(delta)


func _tick_voices(delta: float) -> void:
	if _psu != null:
		_psu.tick(delta)
	if _fan != null:
		_fan.tick(delta)
	if _room != null:
		_room.tick(delta)


# --- контекст ---------------------------------------------------------------

func _refresh_audio() -> void:
	if not is_inside_tree():
		return
	if _audio == null or not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/Audio")


func _find_main() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene != null and is_instance_valid(scene) and scene.get("controller") != null:
		return scene
	var main := tree.root.get_node_or_null("Main")
	if main != null:
		return main
	return scene


func _find_director() -> Node:
	var main := _find_main()
	if main == null or not is_instance_valid(main):
		return null
	var controller = main.get("controller")
	if controller == null or not is_instance_valid(controller):
		return null
	var director = controller.get("hour_director")
	if director == null or not is_instance_valid(director):
		return null
	return director


func _resolve_context() -> void:
	_refresh_audio()
	_bind_director(_find_director())
	if _forced:
		_state = _forced_state
		_load = _forced_load
		return
	_state = _compute_state(_director)
	_load = _compute_load(_director) if _state == "hour" else 0.0


func _compute_state(director: Node) -> String:
	if director == null:
		return "idle"
	if bool(director.get("modal_open")) or bool(director.get("paused")):
		return "suspend"
	if bool(director.get("running")) and float(director.get("time_left")) > 0.0:
		return "hour"
	return "idle"


func _compute_load(director: Node) -> float:
	if director == null:
		return 0.0
	var buffer_fill := 0.0
	if director.has_method("buffer_used") and director.has_method("_buffer_limit"):
		var limit := maxf(1.0, float(director.call("_buffer_limit")))
		buffer_fill = clampf(float(director.call("buffer_used")) / limit, 0.0, 1.0)
	var queue_fill := 0.0
	if director.has_method("_normal_request_count") and director.has_method("_max_requests"):
		var max_requests := maxf(1.0, float(director.call("_max_requests")))
		queue_fill = clampf(float(director.call("_normal_request_count")) / max_requests, 0.0, 1.0)
	var attacks := 0
	var attack_director = director.get("attack_director")
	if attack_director != null and is_instance_valid(attack_director):
		var active = attack_director.get("active_attacks")
		if active is Dictionary:
			attacks = (active as Dictionary).size()
	var lateness := 0.0
	if director.has_method("_hour_seconds"):
		var hour_seconds := maxf(1.0, float(director.call("_hour_seconds")))
		lateness = clampf(1.0 - float(director.get("time_left")) / hour_seconds, 0.0, 1.0)
	return clampf(
		0.40 * buffer_fill
		+ 0.25 * queue_fill
		+ 0.20 * float(mini(attacks, 2)) / 2.0
		+ 0.15 * lateness,
		0.0, 1.0
	)


# --- подписки на seek -------------------------------------------------------

func _bind_director(director: Node) -> void:
	var new_id := director.get_instance_id() if director != null else 0
	if new_id == _director_id:
		return
	_unbind_director()
	if director == null:
		return
	_director = director
	_director_id = new_id
	if director.has_signal("packet_added"):
		director.connect(&"packet_added", _on_packet_added)
	if director.has_signal("request_added"):
		director.connect(&"request_added", _on_request_added)
	if director.has_signal("hour_finished"):
		director.connect(&"hour_finished", _on_hour_finished)


func _unbind_director() -> void:
	if _director != null and is_instance_valid(_director):
		if _director.is_connected(&"packet_added", _on_packet_added):
			_director.disconnect(&"packet_added", _on_packet_added)
		if _director.is_connected(&"request_added", _on_request_added):
			_director.disconnect(&"request_added", _on_request_added)
		if _director.is_connected(&"hour_finished", _on_hour_finished):
			_director.disconnect(&"hour_finished", _on_hour_finished)
	_director = null
	_director_id = 0


func _on_packet_added(_id: String) -> void:
	_try_seek_short()


func _on_request_added(_id: String) -> void:
	_try_seek_short()


func _on_hour_finished(_report: Dictionary) -> void:
	if not _can_seek():
		return
	var player := _seek_series_player
	if player == null or player.stream == null:
		return
	player.volume_db = _with_offset_db(SEEK_DB, _volume_offset())
	player.pitch_scale = 1.0
	player.play()


func _try_seek_short() -> void:
	if not _can_seek() or _seek_cooldown > 0.0:
		return
	if _rng.randf() >= SEEK_PROBABILITY:
		return
	if _seek_short_players.is_empty():
		return
	var player := _seek_short_players[_seek_short_index]
	_seek_short_index = (_seek_short_index + 1) % _seek_short_players.size()
	if player.stream == null:
		return
	player.volume_db = _with_offset_db(SEEK_DB, _volume_offset())
	player.pitch_scale = _rng.randf_range(0.95, 1.05)
	player.play()
	_seek_cooldown = SEEK_COOLDOWN


func _can_seek() -> bool:
	if not _unlocked or _muted:
		return false
	var current := _state
	# Свежая проверка паузы/модалки: сигнал может прийти между опросами.
	if not _forced and _director != null and is_instance_valid(_director):
		current = _compute_state(_director)
	return current != "suspend"


func _stop_oneshots() -> void:
	for player in _seek_short_players:
		if player.playing:
			player.stop()
	if _seek_series_player != null and _seek_series_player.playing:
		_seek_series_player.stop()


# --- громкости --------------------------------------------------------------

func _read_muted() -> bool:
	if _audio == null or not is_instance_valid(_audio):
		return false
	var raw = _audio.get("muted")
	return bool(raw) if typeof(raw) == TYPE_BOOL else false


## Общий оффсет от пользовательской громкости музыки (0..1 → ≤0 dB).
func _volume_offset() -> float:
	if _audio == null or not is_instance_valid(_audio):
		return 0.0
	var raw = _audio.get("music_volume")
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return 0.0
	var value := clampf(float(raw), 0.0, 1.0)
	if value <= 0.001:
		return SILENCE_DB
	return linear_to_db(value)


func _with_offset_db(db: float, offset: float) -> float:
	if db <= SILENCE_DB + 0.01:
		return SILENCE_DB
	return maxf(SILENCE_DB, db + offset)


## Страховка: суммарная подложка не выше MAX_BACKING_DB. При штатных уровнях
## (PSU −23, fan −24, room −38) суммарная мощность ≈ −20 dB, лимит не срабатывает.
func _limit_backing(psu_db: float, fan_db: float, room_db: float) -> Array:
	var power := pow(10.0, psu_db / 10.0) + pow(10.0, fan_db / 10.0) + pow(10.0, room_db / 10.0)
	var limit := pow(10.0, MAX_BACKING_DB / 10.0)
	if power <= limit:
		return [psu_db, fan_db, room_db]
	var shift := linear_to_db(sqrt(limit / power))
	return [
		maxf(SILENCE_DB, psu_db + shift),
		maxf(SILENCE_DB, fan_db + shift),
		maxf(SILENCE_DB, room_db + shift),
	]


func _apply_targets(override_dur: float = -1.0, snap: bool = false) -> void:
	if _psu == null:
		return
	_muted = _read_muted()
	var psu_db := PSU_IDLE_DB
	var fan_db := FAN_IDLE_DB
	var room_db := ROOM_DB
	var psu_dur := 0.25
	var fan_dur := 0.25
	var room_dur := 0.25
	match _state:
		"hour":
			psu_db = lerpf(PSU_IDLE_DB, PSU_LOAD_DB, clampf(_load, 0.0, 1.0))
			fan_db = lerpf(FAN_IDLE_DB, FAN_LOAD_DB, clampf(_fan_load, 0.0, 1.0))
		"suspend":
			psu_db = PSU_SUSPEND_DB
			fan_db = SILENCE_DB
			room_db = SILENCE_DB
			psu_dur = SUSPEND_FADE
			fan_dur = SUSPEND_FADE
			room_dur = SUSPEND_FADE
	if not _unlocked or _muted:
		psu_db = SILENCE_DB
		fan_db = SILENCE_DB
		room_db = SILENCE_DB
		if _muted and _unlocked:
			# Mute — быстро, но без щелчка; снятие идёт обычным ramp.
			psu_dur = 0.15
			fan_dur = 0.15
			room_dur = 0.15
		_stop_oneshots()
	var offset := _volume_offset()
	var levels := _limit_backing(
		_with_offset_db(psu_db, offset),
		_with_offset_db(fan_db, offset),
		_with_offset_db(room_db, offset)
	)
	if snap:
		_psu.snap_to(float(levels[0]))
		_fan.snap_to(float(levels[1]))
		_room.snap_to(float(levels[2]))
	else:
		var durations := [psu_dur, fan_dur, room_dur]
		if override_dur >= 0.0:
			durations = [override_dur, override_dur, override_dur]
		_psu.set_target(float(levels[0]), float(durations[0]))
		_fan.set_target(float(levels[1]), float(durations[1]))
		_room.set_target(float(levels[2]), float(durations[2]))
	_fan_player.pitch_scale = lerpf(0.96, 1.10, clampf(_fan_load, 0.0, 1.0))
	_psu_player.pitch_scale = 1.0
	_room_player.pitch_scale = 1.0


# --- отладка/тесты ----------------------------------------------------------

## Принудительно применить состояние (idle/hour/suspend) и нагрузку 0..1.
## Зафиксированные значения держатся до следующего вызова; для тестов.
func debug_apply(load: float, state: String) -> void:
	_forced = true
	_forced_load = clampf(load, 0.0, 1.0)
	_forced_state = state if state in ["idle", "hour", "suspend"] else "idle"
	_unlocked = true
	_state = _forced_state
	_load = _forced_load
	_fan_load = _load if _state == "hour" else 0.0
	_refresh_audio()
	_ensure_players()
	_apply_targets(0.0, true)


func debug_state() -> Dictionary:
	return {
		"psu_db": _psu.current_db if _psu != null else SILENCE_DB,
		"fan_db": _fan.current_db if _fan != null else SILENCE_DB,
		"fan_pitch": _fan_player.pitch_scale if _fan_player != null else 1.0,
		"room_db": _room.current_db if _room != null else SILENCE_DB,
		"state": _state,
		"unlocked": _unlocked,
		"muted": _muted,
	}
