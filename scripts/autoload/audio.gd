extends Node
## Audio — пул эффектов, музыка с кроссфейдом и low-SLA overlay (autoload).
##
## Пул из 8 AudioStreamPlayer для одноразовых SFX, два плеера A/B для
## музыки (menu/game/magazine/defeat) и отдельный loop-плеер для low_sla.
## Кастомных шин в проекте нет — работаем через Master и `volume_db`.
## AudioEffect намеренно не используются: в web-сборке (no threads) они
## недоступны.
##
## Приоритет музыки: defeat > shop (magazine) > scene (menu/game).
## Смена трека — кроссфейд, быстрые переключения не оставляют наложения:
## новый трек всегда стартует на «свободном» плеере, старый уходит в −80 dB
## и останавливается по завершении фейда.
##
## Web autoplay: до первого input музыка не стартует, целевой трек
## запоминается. В desktop/headless ограничение не действует.
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

## Все известные треки (без расширения) и их файлы.
## hum — legacy-фон, остальные — саундтреки.
const MUSIC_IDS: PackedStringArray = [
	"hum", "menu", "game", "magazine", "defeat", "low_sla",
]
const MUSIC_FILES := {
	"hum": "hum.wav",
	"menu": "menu.mp3",
	"game": "game.mp3",
	"magazine": "magazine.mp3",
	"defeat": "defeat.mp3",
	"low_sla": "low_sla.mp3",
}

## Зацикленные треки. defeat — one-shot.
const LOOP_MUSIC_IDS: PackedStringArray = [
	"hum", "menu", "game", "magazine", "low_sla",
]
const SCENE_IDS: PackedStringArray = ["menu", "game"]

const LOW_SLA_ID := "low_sla"
const SHOP_MUSIC_ID := "magazine"
const DEFEAT_MUSIC_ID := "defeat"

const SCENE_FADE := 0.9
const SHOP_FADE := 0.8
const DEFEAT_FADE := 0.6
const LOW_FADE := 0.8
const LEGACY_FADE := 0.8

## Overlay «низкий SLA»: тихо подмешивается поверх музыки, не останавливая её.
const LOW_SLA_DB := -14.0
const LOW_SLA_MAX_DB := -8.0

var music_volume: float = 0.8  ## линейно 0..1
var sfx_volume: float = 0.9    ## линейно 0..1
var muted: bool = false        ## использовать set_muted()

var _sfx_streams: Dictionary = {}       # id: String -> AudioStream
## Legacy-словарь одиночного фона (hum). Оставлен для совместимости с
## тестами/старым кодом, которые читают/чистят `_music_streams`.
var _music_streams: Dictionary = {}
var _music_bank: Dictionary = {}        # id: String -> AudioStream (все треки)

var _pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer    # плеер A; сохранённое имя для старого API
var _music_players: Array[AudioStreamPlayer] = []

## Состояние фейдов по индексам A(0)/B(1). Гейн в dB: 0 — полная громкость,
## SILENCE_DB — тишина. Итоговая громкость = _music_db + гейн.
var _music_gain: Array[float] = [SILENCE_DB, SILENCE_DB]
var _music_fade_from: Array[float] = [SILENCE_DB, SILENCE_DB]
var _music_fade_to: Array[float] = [SILENCE_DB, SILENCE_DB]
var _music_fade_elapsed: Array[float] = [0.0, 0.0]
var _music_fade_dur: Array[float] = [0.0, 0.0]
var _music_stop_after: Array[bool] = [false, false]
var _active_music: int = -1
var _last_music: int = 1

var _low_player: AudioStreamPlayer
var _low_stream: AudioStream = null
var _low_active: bool = false
var _low_ratio: float = 0.0
var _low_gain: float = SILENCE_DB
var _low_fade_from: float = SILENCE_DB
var _low_fade_to: float = SILENCE_DB
var _low_fade_elapsed: float = 0.0
var _low_fade_dur: float = 0.0

## Логическое состояние: какой трек должен звучать.
var _scene_id: String = ""
var _shop_open: bool = false
var _defeat_active: bool = false
var _manual_id: String = ""      # явный play_music(), пока не задана сцена
var _target_music: String = ""   # что уже играет/запрошено ("" — тишина)

var _unlocked: bool = false
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

	_music_player = _make_music_player("MusicA")
	_music_players.append(_music_player)
	_music_players.append(_make_music_player("MusicB"))

	_low_player = AudioStreamPlayer.new()
	_low_player.name = "LowSla"
	_low_player.bus = &"Master"
	_low_player.volume_db = SILENCE_DB
	add_child(_low_player)

	_preload_all()
	# Web: старт только после первого жеста. Desktop/headless не блокируем.
	_unlocked = not OS.has_feature("web")
	_apply_volumes()


func _make_music_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = &"Master"
	player.volume_db = SILENCE_DB
	add_child(player)
	return player


## Загрузка всех SFX и музыкальных треков. Отсутствующий файл — warning,
## не падение.
func _preload_all() -> void:
	for id in SFX_IDS:
		var path := SFX_DIR + String(id) + ".wav"
		var stream := _load_stream(path)
		if stream == null:
			push_warning("Audio: файл SFX не найден: " + path)
		else:
			_sfx_streams[id] = stream
	for id in MUSIC_IDS:
		var key := String(id)
		var stream := _load_music_stream(key)
		if stream == null:
			push_warning("Audio: файл музыки не найден: " + _music_path(key))
		else:
			_music_bank[key] = stream
			# Legacy-словарь держим ровно с одним элементом (hum).
			if key == "hum":
				_music_streams[key] = stream
	_low_stream = _music_bank.get(LOW_SLA_ID) as AudioStream


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _music_path(id: String) -> String:
	if MUSIC_FILES.has(id):
		return MUSIC_DIR + String(MUSIC_FILES[id])
	# Неизвестный id: пробуем mp3, затем wav (совместимость со старым кодом).
	var mp3_path := MUSIC_DIR + id + ".mp3"
	if ResourceLoader.exists(mp3_path):
		return mp3_path
	return MUSIC_DIR + id + ".wav"


## Загрузка трека с настройкой loop. defeat — one-shot.
func _load_music_stream(id: String) -> AudioStream:
	var path := _music_path(id)
	var stream := _load_stream(path)
	if stream == null:
		return null
	_configure_loop(stream, id)
	return stream


func _get_music_stream(id: String) -> AudioStream:
	var stream := _music_bank.get(id) as AudioStream
	if stream != null:
		return stream
	stream = _load_music_stream(id)
	if stream == null:
		push_warning("Audio: музыка не найдена: " + _music_path(id))
		return null
	_music_bank[id] = stream
	return stream


## MP3: loop=true, loop_offset=0. WAV: loop на весь файл. defeat: loop выкл.
func _configure_loop(stream: AudioStream, id: String) -> void:
	var should_loop := LOOP_MUSIC_IDS.has(id)
	var mp3 := stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = should_loop
		if should_loop:
			mp3.loop_offset = 0.0
		return
	var wav := stream as AudioStreamWAV
	if wav == null:
		return
	if not should_loop:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		return
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	# Длина берётся из get_length(): одинаково корректна для PCM и для
	# сжатого импорта (по умолчанию Godot импортирует WAV в QOA).
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	if frames <= 0:
		push_warning("Audio: не удалось вычислить длину для loop: " + _music_path(id))
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames


# --- SFX --------------------------------------------------------------------

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


# --- музыка: публичный API --------------------------------------------------

## Явный запуск трека (backward-compatible: по умолчанию hum).
## Кроссфейд; повтор того же трека — no-op.
func play_music(id: String = "hum", fade: float = LEGACY_FADE) -> void:
	var key := _normalize_music_id(id)
	if key == LOW_SLA_ID:
		set_low_sla(true)
		return
	if key == DEFEAT_MUSIC_ID:
		play_defeat()
		return
	_manual_id = key
	_request_music(key, fade)


## Смена игровой сцены: menu/game. Кроссфейд 0.9 c, повтор — no-op.
func set_scene(id: String) -> void:
	var key := _normalize_music_id(id)
	if not SCENE_IDS.has(key):
		push_warning("Audio: неизвестная сцена для музыки: " + id)
		return
	# Новая сцена (в т.ч. menu после defeat) снимает defeat-состояние и
	# закрывает магазинный overlay: смена сцены — более крупный переход.
	_defeat_active = false
	_shop_open = false
	_manual_id = ""
	_scene_id = key
	if key == "menu":
		# В меню low-SLA overlay не нужен.
		_disable_low(LOW_FADE)
	_request_music(_resolve_target(), SCENE_FADE)


## Открыт магазин/журнал: поверх сцены играет magazine, приоритет ниже defeat.
func set_shop_open(open: bool) -> void:
	if _shop_open == open:
		return
	_shop_open = open
	_request_music(_resolve_target(), SHOP_FADE)


## Проигрыш: кроссфейд в one-shot defeat; после конца — тишина до set_scene().
func play_defeat() -> void:
	_defeat_active = true
	_disable_low(LOW_FADE)
	# Повторный вызов во время звучания — no-op, после конца — можно заново.
	if _target_music == DEFEAT_MUSIC_ID and _active_music >= 0 \
			and _music_players[_active_music].playing:
		return
	_request_music(DEFEAT_MUSIC_ID, DEFEAT_FADE, true)


## Остановить музыку (и overlay). fade=0 — сразу (старое поведение).
func stop_music(fade: float = 0.0) -> void:
	_scene_id = ""
	_shop_open = false
	_defeat_active = false
	_manual_id = ""
	_target_music = ""
	_stop_all_music(fade)
	_disable_low(fade)


## Low-SLA overlay: плавно подмешивается поверх музыки, не останавливая её.
## ratio 0..1 усиливает сигнал (SLA просел сильнее). Повторное применение
## той же цели не перезапускает фейд.
func set_low_sla(active: bool, ratio: float = 0.0) -> void:
	_low_ratio = clampf(ratio, 0.0, 1.0)
	var target_db := _low_target_db(active)
	var same := active == _low_active and absf(target_db - _low_fade_to) < 0.05
	if same and (_low_fade_dur > 0.0 or _low_player.playing or not active or not _unlocked):
		return
	_low_active = active
	_set_low_target(active, LOW_FADE)


## Выключить overlay (defeat/меню) и дать ему уйти в тишину.
func _disable_low(fade: float) -> void:
	_low_active = false
	_set_low_target(false, fade)


func _low_target_db(active: bool) -> float:
	if not active:
		return SILENCE_DB
	return lerpf(LOW_SLA_DB, LOW_SLA_MAX_DB, _low_ratio)


# --- музыка: внутренняя логика ---------------------------------------------

func _normalize_music_id(id: String) -> String:
	var key := id.strip_edges()
	key = key.trim_suffix(".mp3")
	key = key.trim_suffix(".wav")
	return key


func _resolve_target() -> String:
	if _defeat_active:
		return DEFEAT_MUSIC_ID
	if _shop_open:
		return SHOP_MUSIC_ID
	if _scene_id != "":
		return _scene_id
	return _manual_id


## Запрос трека с учётом web-autoplay и «повтор — no-op».
## force нужен только явному play_defeat() после завершения one-shot.
func _request_music(id: String, fade: float, force: bool = false) -> void:
	if not _unlocked:
		# Запоминаем pending: стартуем после первого input.
		_target_music = id
		return
	if not force and id == _target_music and id != "":
		return
	_start_music(id, fade)


func _start_music(id: String, fade: float) -> void:
	if id == "":
		_stop_all_music(fade)
		return
	var stream := _get_music_stream(id)
	if stream == null:
		return

	var idx := 0
	if _active_music >= 0:
		idx = 1 - _active_music
		# Старый активный трек уходит в тишину и затем останавливается.
		_begin_fade_out(_active_music, fade)
	else:
		idx = 1 - _last_music
		# Хвост предыдущего stop_music не должен накладываться на новый трек.
		for i in _music_players.size():
			if i != idx and _music_players[i].playing:
				_begin_fade_out(i, minf(fade, 0.2))

	var player := _music_players[idx]
	player.stop()
	player.stream = stream
	player.pitch_scale = 1.0
	_music_gain[idx] = SILENCE_DB
	_music_fade_from[idx] = SILENCE_DB
	_music_fade_to[idx] = 0.0
	_music_fade_elapsed[idx] = 0.0
	_music_fade_dur[idx] = maxf(fade, 0.0)
	_music_stop_after[idx] = false
	if fade <= 0.0:
		_music_gain[idx] = 0.0
	player.play()

	_active_music = idx
	_last_music = idx
	_target_music = id
	_apply_volumes()


func _stop_all_music(fade: float) -> void:
	_active_music = -1
	for i in _music_players.size():
		if _music_players[i].playing or _music_gain[i] > SILENCE_DB + 0.01:
			_begin_fade_out(i, fade)
	_apply_volumes()


func _begin_fade_out(idx: int, duration: float) -> void:
	_music_fade_from[idx] = _music_gain[idx]
	_music_fade_to[idx] = SILENCE_DB
	_music_fade_elapsed[idx] = 0.0
	_music_fade_dur[idx] = maxf(duration, 0.0)
	_music_stop_after[idx] = true
	if duration <= 0.0:
		_music_gain[idx] = SILENCE_DB
		_music_players[idx].stop()


# --- low SLA overlay --------------------------------------------------------

func _set_low_target(active: bool, fade: float) -> void:
	var target_db := _low_target_db(active)

	if not active:
		_low_fade_from = _low_gain
		_low_fade_to = SILENCE_DB
		_low_fade_elapsed = 0.0
		_low_fade_dur = maxf(fade, 0.0)
		if fade <= 0.0:
			_low_gain = SILENCE_DB
			_low_player.stop()
		_apply_volumes()
		return

	if not _unlocked:
		# Запомнили намерение; запустим после первого input.
		_low_fade_to = target_db
		return
	if _low_stream == null:
		_low_stream = _get_music_stream(LOW_SLA_ID)
	if _low_stream == null:
		return
	if not _low_player.playing:
		_low_player.stop()
		_low_player.stream = _low_stream
		_low_player.pitch_scale = 1.0
		_low_gain = SILENCE_DB
		_low_player.play()

	_low_fade_from = _low_gain
	_low_fade_to = target_db
	_low_fade_elapsed = 0.0
	_low_fade_dur = maxf(fade, 0.0)
	if fade <= 0.0:
		_low_gain = target_db
	_apply_volumes()


# --- web autoplay -----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_unlock()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_unlock()


func _unlock() -> void:
	_unlocked = true
	# Overlay и музыка стартуют только сейчас, с фейда.
	if _low_active:
		_set_low_target(true, LOW_FADE)
	if _target_music != "":
		var pending := _target_music
		_target_music = ""
		_start_music(pending, SCENE_FADE)


# --- процесс: фейды ---------------------------------------------------------

func _process(delta: float) -> void:
	if not _unlocked:
		return
	_tick_music_fades(delta)
	_tick_low_fade(delta)


func _tick_music_fades(delta: float) -> void:
	var changed := false
	for i in _music_players.size():
		if _music_fade_dur[i] <= 0.0:
			continue
		changed = true
		_music_fade_elapsed[i] = minf(_music_fade_elapsed[i] + delta, _music_fade_dur[i])
		var t := _music_fade_elapsed[i] / _music_fade_dur[i]
		_music_gain[i] = lerpf(_music_fade_from[i], _music_fade_to[i], t)
		if _music_fade_elapsed[i] >= _music_fade_dur[i]:
			_music_gain[i] = _music_fade_to[i]
			_music_fade_dur[i] = 0.0
			if _music_stop_after[i] and i != _active_music:
				_music_stop_after[i] = false
				_music_players[i].stop()
	if changed:
		_apply_volumes()


func _tick_low_fade(delta: float) -> void:
	if _low_fade_dur > 0.0:
		_low_fade_elapsed = minf(_low_fade_elapsed + delta, _low_fade_dur)
		var t := _low_fade_elapsed / _low_fade_dur
		_low_gain = lerpf(_low_fade_from, _low_fade_to, t)
		if _low_fade_elapsed >= _low_fade_dur:
			_low_gain = _low_fade_to
			_low_fade_dur = 0.0
			if not _low_active and _low_gain <= SILENCE_DB + 0.01:
				_low_player.stop()
		_apply_volumes()


# --- громкости --------------------------------------------------------------

## Громкость эффектов, линейно 0..1 (0.5 — вдвое тише).
func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()


## Громкость музыки, линейно 0..1. Применяется ко всем музыкальным плеерам.
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
	for i in _music_players.size():
		_music_players[i].volume_db = _combine_db(_music_db, _music_gain[i])
	if _low_player != null:
		_low_player.volume_db = _combine_db(_music_db, _low_gain)


## Суммарная громкость: базовая (пользователь/mute) + гейн фейда.
func _combine_db(base_db: float, gain_db: float) -> float:
	if base_db <= SILENCE_DB + 0.01 or gain_db <= SILENCE_DB + 0.01:
		return SILENCE_DB
	return clampf(base_db + gain_db, SILENCE_DB, 0.0)


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
