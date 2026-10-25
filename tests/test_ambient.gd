extends SceneTree
## Headless-проверка фонового слоя Ambient (PSU / fan / room / seek).
##
## Запуск (из корня проекта):
##   godot --headless --path . --script tests/test_ambient.gd
## Код выхода 0 — все проверки прошли, 1 — есть провалы.
##
## Важно про автолоад: при запуске через --script скрипт компилируется ДО
## регистрации автолоадов, поэтому глобальные имена `Audio` / `Ambient` в нём
## недоступны (ошибка компиляции «Identifier not found»). Автолоад успевает
## создаться к отложенному вызову, поэтому берём узлы из /root.
##
## Уровни проверяются «сырыми»: Audio.set_music_volume(1.0) даёт нулевой
## оффсет, поэтому debug_state() должен совпадать с константами Ambient.

const AMB_FILES: Array[Dictionary] = [
	{"path": "res://audio/amb/fan_loop.wav", "length": 8.0},
	{"path": "res://audio/amb/room_loop.wav", "length": 15.0},
	{"path": "res://audio/amb/seek_short.wav", "length": 0.12},
	{"path": "res://audio/amb/seek_series.wav", "length": 0.4},
]

const AMB_BASENAMES: PackedStringArray = [
	"fan_loop.wav", "room_loop.wav", "seek_short.wav", "seek_series.wav",
]

const STATE_KEYS: PackedStringArray = [
	"psu_db", "fan_db", "fan_pitch", "room_db", "state", "unlocked", "muted",
]

const SFX_COUNT := 18
const MUSIC_COUNT := 1

var _checks: int = 0
var _fails: int = 0


func _init() -> void:
	_check_files_exist()
	# Автолоады добавляются в /root после _init главного цикла.
	call_deferred("_run")


## 1. Все 4 WAV Ambient лежат в audio/amb, а не в audio/sfx.
func _check_files_exist() -> void:
	for entry in AMB_FILES:
		var path: String = entry["path"]
		_check(FileAccess.file_exists(path), "файл %s существует" % path)

	var sfx_wavs := _wav_names("res://audio/sfx")
	var music_wavs := _wav_names("res://audio/music")
	print("FILE_COUNT sfx=%d music=%d amb=%d"
		% [sfx_wavs.size(), music_wavs.size(), AMB_FILES.size()])

	_check(sfx_wavs.size() == SFX_COUNT,
		"в audio/sfx ровно %d WAV (факт %d)" % [SFX_COUNT, sfx_wavs.size()])
	_check(music_wavs.size() == MUSIC_COUNT,
		"в audio/music ровно %d WAV (факт %d)" % [MUSIC_COUNT, music_wavs.size()])
	for base in AMB_BASENAMES:
		_check(not sfx_wavs.has(base),
			"ambient-файл %s не попал в audio/sfx" % base)


func _wav_names(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	for name in DirAccess.get_files_at(dir_path):
		if name.ends_with(".wav"):
			result.append(name)
	result.sort()
	return result


## 2. Загрузка потоков и API автолоада.
func _run() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var Audio := tree.root.get_node_or_null("Audio")
	var Ambient := tree.root.get_node_or_null("Ambient")

	_check(Audio != null, "автолоад Audio создан в /root")
	_check(Ambient != null, "автолоад Ambient создан в /root")
	if Audio == null or Ambient == null:
		_finish()
		return

	# --- потоки: 22050 Гц, моно, ненулевая длина -----------------------------
	for entry in AMB_FILES:
		var path: String = entry["path"]
		var expected_len: float = entry["length"]
		var stream := load(path) as AudioStreamWAV
		_check(stream != null, "%s читается как AudioStreamWAV" % path)
		if stream == null:
			continue
		_check(stream.mix_rate == 22050,
			"%s: 22050 Гц (факт %d)" % [path, stream.mix_rate])
		_check(not stream.stereo, "%s: моно" % path)
		# Импортёр использует QOA (compress/mode=2), поэтому 16-bit PCM
		# допустим не строго: важно, что поток валиден и длина совпадает.
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS
				or stream.format == AudioStreamWAV.FORMAT_QOA,
			"%s: PCM16 или QOA (факт format=%d)" % [path, stream.format])
		_check(absf(stream.get_length() - expected_len) <= 0.02,
			"%s: длина ≈ %.2f с (факт %.3f)" % [path, expected_len, stream.get_length()])

	# Ambient сам предзагрузил свои плееры.
	var fan_player = Ambient.get("_fan_player")
	var room_player = Ambient.get("_room_player")
	var psu_player = Ambient.get("_psu_player")
	_check(fan_player != null and fan_player.stream != null,
		"Ambient загрузил поток вентилятора")
	_check(room_player != null and room_player.stream != null,
		"Ambient загрузил поток комнаты")
	_check(psu_player != null and psu_player.stream != null,
		"Ambient загрузил поток PSU (hum.wav)")

	# --- debug_state: ключи ---------------------------------------------------
	var st: Dictionary = Ambient.debug_state()
	for key in STATE_KEYS:
		_check(st.has(key), "debug_state() содержит ключ %s" % key)

	# --- idle: точные уровни при нулевом оффсете -----------------------------
	Audio.set_music_volume(1.0)
	_check(is_equal_approx(Audio.music_volume, 1.0),
		"set_music_volume(1.0) записал поле")

	Ambient.debug_apply(0.0, "idle")
	st = Ambient.debug_state()
	_check_approx(st, "psu_db", -28.0, 0.05, "idle: PSU −28 dB")
	_check_approx(st, "fan_db", -38.0, 0.05, "idle: fan −38 dB")
	_check_approx(st, "room_db", -38.0, 0.05, "idle: room −38 dB")
	_check_approx(st, "fan_pitch", 0.96, 0.05, "idle: pitch 0.96")
	_check(str(st.get("state")) == "idle", "idle: state == idle")
	_check(bool(st.get("unlocked")) == true, "idle: debug_apply разблокировал звук")

	# --- hour, load = 1 -------------------------------------------------------
	Ambient.debug_apply(1.0, "hour")
	st = Ambient.debug_state()
	_check(str(st.get("state")) == "hour", "hour: state == hour")
	_check_approx(st, "psu_db", -23.0, 0.05, "hour load=1: PSU −23 dB")
	_check_approx(st, "fan_db", -24.0, 0.05, "hour load=1: fan −24 dB")
	_check_approx(st, "room_db", -38.0, 0.05, "hour load=1: room −38 dB")
	_check_approx(st, "fan_pitch", 1.10, 0.02, "hour load=1: pitch 1.10")

	# --- hour, load = 0.5: монотонность --------------------------------------
	Ambient.debug_apply(0.5, "hour")
	st = Ambient.debug_state()
	var fan_half := float(st.get("fan_db"))
	_check(fan_half > -38.0 and fan_half < -24.0,
		"hour load=0.5: fan_db %.2f между idle −38 и load=1 −24" % fan_half)
	_check_approx(st, "psu_db", -25.5, 0.05, "hour load=0.5: PSU −25.5 dB")
	var pitch_half := float(st.get("fan_pitch"))
	_check(pitch_half > 0.96 and pitch_half < 1.10,
		"hour load=0.5: pitch %.3f между 0.96 и 1.10" % pitch_half)

	# --- suspend --------------------------------------------------------------
	Ambient.debug_apply(0.5, "suspend")
	st = Ambient.debug_state()
	_check(str(st.get("state")) == "suspend", "suspend: state == suspend")
	_check_approx(st, "psu_db", -30.0, 0.05, "suspend: PSU −30 dB")
	_check_approx(st, "fan_db", -80.0, 0.01, "suspend: fan −80 dB")
	_check_approx(st, "room_db", -80.0, 0.01, "suspend: room −80 dB")

	# --- mute ----------------------------------------------------------------
	Audio.set_muted(true)
	Ambient.debug_apply(0.0, "idle")
	st = Ambient.debug_state()
	_check(bool(st.get("muted")) == true, "mute: debug_state().muted == true")
	_check_approx(st, "psu_db", -80.0, 0.01, "mute: PSU −80 dB")
	_check_approx(st, "fan_db", -80.0, 0.01, "mute: fan −80 dB")
	_check_approx(st, "room_db", -80.0, 0.01, "mute: room −80 dB")

	# --- снятие mute: восстановление -----------------------------------------
	Audio.set_muted(false)
	Ambient.debug_apply(0.0, "idle")
	st = Ambient.debug_state()
	_check(bool(st.get("muted")) == false, "unmute: debug_state().muted == false")
	_check_approx(st, "psu_db", -28.0, 0.05, "unmute: PSU восстановлен −28 dB")
	_check_approx(st, "fan_db", -38.0, 0.05, "unmute: fan восстановлен −38 dB")
	_check_approx(st, "room_db", -38.0, 0.05, "unmute: room восстановлен −38 dB")

	# --- повторные вызовы: без падений и утечек состояния --------------------
	var states: PackedStringArray = ["idle", "hour", "suspend"]
	for i in 60:
		var state: String = states[i % states.size()]
		var load_value: float = float(i % 11) / 10.0
		Ambient.debug_apply(load_value, state)
	_check(true, "60 повторных debug_apply(...) — без исключений")
	st = Ambient.debug_state()
	_check(str(st.get("state")) == "suspend",
		"последний debug_apply(9/10, suspend) оставил state == suspend")

	Ambient.debug_apply(0.0, "idle")
	st = Ambient.debug_state()
	_check(str(st.get("state")) == "idle", "финальный debug_apply вернул idle")

	# --- вернуть пользовательские настройки ----------------------------------
	Audio.set_music_volume(0.8)
	Audio.set_muted(false)
	_check(is_equal_approx(Audio.music_volume, 0.8), "восстановлено music_volume = 0.8")
	_check(Audio.muted == false, "восстановлено muted = false")

	# Даём кадрам доработать, чтобы headless-драйвер не ругался на выходе.
	await create_timer(0.15).timeout
	_finish()


func _check_approx(state: Dictionary, key: String, expected: float, tol: float, what: String) -> void:
	var actual := float(state.get(key, -999.0))
	_check(absf(actual - expected) <= tol,
		"%s (факт %.3f)" % [what, actual])


func _finish() -> void:
	print("RESULT checks=%d fails=%d" % [_checks, _fails])
	var main := Engine.get_main_loop()
	if main == null or main == self:
		quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)
