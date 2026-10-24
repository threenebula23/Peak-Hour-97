extends Node
## Audio — пул эффектов и фоновый гул (autoload).
##
## Пул из 8 AudioStreamPlayer для одноразовых SFX + отдельный проигрыватель
## для музыки/фона. Кастомных шин в проекте нет — работаем через Master
## и `volume_db`. AudioEffect намеренно не используются: в web-сборке
## (no threads) они недоступны.
##
## Настройки (громкости, mute) живут в полях, без UI.

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const POOL_SIZE := 8
const SILENCE_DB := -80.0
const PITCH_SPREAD := 0.03  ## ±3 % к тону, чтобы SFX не звучал монотонно

## Все известные эффекты (без расширения). Порядок соответствует audio/sfx/.
const SFX_IDS: PackedStringArray = [
	"click", "drag", "drop", "drop_error", "recv", "request_ready",
	"minigame_win", "minigame_fail", "modem", "connect_fail", "tick",
	"packet_loss", "attack", "attack_blocked", "money_up", "money_down",
	"hour_end", "run_end",
]

## Известный фон (без расширения). Порядок соответствует audio/music/.
const MUSIC_IDS: PackedStringArray = ["hum"]

var music_volume: float = 0.8  ## линейно 0..1
var sfx_volume: float = 0.9    ## линейно 0..1
var muted: bool = false        ## использовать set_muted()

var _sfx_streams: Dictionary = {}       # id: String -> AudioStream
var _music_streams: Dictionary = {}     # id: String -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _round_robin: int = 0
var _sfx_db: float = 0.0
var _music_db: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_pool.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Master"
	add_child(_music_player)
	_preload_all()
	_apply_volumes()


## Загрузка всех WAV в словари. Отсутствующий файл — предупреждение, не падение.
func _preload_all() -> void:
	for id in SFX_IDS:
		var path := SFX_DIR + String(id) + ".wav"
		var stream := _load_stream(path)
		if stream == null:
			push_warning("Audio: файл SFX не найден: " + path)
		else:
			_sfx_streams[id] = stream
	for id in MUSIC_IDS:
		var path := MUSIC_DIR + String(id) + ".wav"
		var stream := _load_stream(path)
		if stream == null:
			push_warning("Audio: файл музыки не найден: " + path)
		else:
			_music_streams[id] = stream
			_enable_loop(stream, path)


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## Зацикливание для фона (гул): loop на весь файл, шов уже совпадает.
func _enable_loop(stream: AudioStream, path: String) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	# Длина берётся из get_length(): одинаково корректна для PCM и для
	# сжатого импорта (по умолчанию Godot импортирует WAV в QOA).
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	if frames <= 0:
		push_warning("Audio: не удалось вычислить длину для loop: " + path)
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames


## Проиграть одноразовый эффект. `id` — имя файла без расширения;
## неизвестный id даёт push_warning и ни при каких условиях не падает.
func play_sfx(id: String) -> void:
	var key := id.trim_suffix(".wav")
	var stream := _sfx_streams.get(key) as AudioStream
	if stream == null:
		var path := SFX_DIR + key + ".wav"
		stream = _load_stream(path)
		if stream == null:
			push_warning("Audio: SFX не найден: " + path)
			return
		_sfx_streams[key] = stream
	var player := _next_player()
	player.stream = stream
	player.pitch_scale = 1.0 + _rng.randf_range(-PITCH_SPREAD, PITCH_SPREAD)
	player.volume_db = _sfx_db
	player.play()


## Проиграть фон (гул) с зацикливанием. Повторный вызов во время игры — no-op.
func play_music(id: String = "hum") -> void:
	var key := id.trim_suffix(".wav")
	var stream := _music_streams.get(key) as AudioStream
	if stream == null:
		var path := MUSIC_DIR + key + ".wav"
		stream = _load_stream(path)
		if stream == null:
			push_warning("Audio: музыка не найдена: " + path)
			return
		_music_streams[key] = stream
		_enable_loop(stream, path)
	if _music_player.playing and _music_player.stream == stream:
		return
	_music_player.stream = stream
	_music_player.volume_db = _music_db
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


## Громкость эффектов, линейно 0..1 (0.5 — вдвое тише).
func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()


## Громкость фона, линейно 0..1.
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()


## Общий mute: тишина без остановки проигрывания.
func set_muted(m: bool) -> void:
	muted = m
	_apply_volumes()


func _apply_volumes() -> void:
	_sfx_db = SILENCE_DB if muted else _to_db(sfx_volume)
	_music_db = SILENCE_DB if muted else _to_db(music_volume)
	for player in _pool:
		player.volume_db = _sfx_db
	_music_player.volume_db = _music_db


func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return SILENCE_DB
	return linear_to_db(linear)


## Свободный проигрыватель; если все заняты — просто следующий по кругу.
func _next_player() -> AudioStreamPlayer:
	for i in _pool.size():
		var idx := (_round_robin + i) % _pool.size()
		if not _pool[idx].playing:
			_round_robin = (idx + 1) % _pool.size()
			return _pool[idx]
	var player := _pool[_round_robin]
	_round_robin = (_round_robin + 1) % _pool.size()
	return player
