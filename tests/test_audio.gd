extends SceneTree
## Headless-проверка звукового слоя PEAK HOUR.
##
## Запуск (из корня проекта):
##   godot --headless --path . --script tests/test_audio.gd
## Код выхода 0 — все проверки прошли, 1 — есть провалы.
##
## Важно про автолоад: при запуске через --script скрипт компилируется ДО
## регистрации автолоадов, поэтому глобальное имя `Audio` в нём недоступно
## (ошибка компиляции «Identifier not found»). Автолоад успевает создаться к
## отложенному вызову, поэтому берём его узел из /root под тем же именем.

const SFX_IDS: PackedStringArray = [
	"click", "drag", "drop", "drop_error", "recv", "request_ready",
	"minigame_win", "minigame_fail", "modem", "connect_fail", "tick",
	"packet_loss", "attack", "attack_blocked", "money_up", "money_down",
	"hour_end", "run_end",
]
const MUSIC_IDS: PackedStringArray = ["hum"]

var _checks: int = 0
var _fails: int = 0


func _init() -> void:
	_check_files()
	# Автолоады добавляются в /root после _init главного цикла.
	call_deferred("_check_audio_api")


## 1. Все 19 WAV существуют на диске проекта.
func _check_files() -> void:
	for id in SFX_IDS:
		_check(FileAccess.file_exists("res://audio/sfx/%s.wav" % id),
			"файл res://audio/sfx/%s.wav" % id)
	for id in MUSIC_IDS:
		_check(FileAccess.file_exists("res://audio/music/%s.wav" % id),
			"файл res://audio/music/%s.wav" % id)
	print("FILE_COUNT sfx=%d music=%d всего=%d (ожидается 18+1=19)"
		% [SFX_IDS.size(), MUSIC_IDS.size(), SFX_IDS.size() + MUSIC_IDS.size()])


## 2. API автолоада: play_sfx / громкости / музыка — без падений.
func _check_audio_api() -> void:
	# Держимся за главный цикл: так тест не уронит чужой раннер, если его
	# однажды загрузят как модуль, а в обычном режиме всё работает как прежде.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var Audio := tree.root.get_node_or_null("Audio")
	_check(Audio != null, "автолоад Audio создан в /root")
	if Audio == null:
		_finish()
		return

	# прелоад: словари заполнены
	_check(Audio._sfx_streams.size() == SFX_IDS.size(),
		"предзагружено SFX: %d" % Audio._sfx_streams.size())
	_check(Audio._music_streams.size() == MUSIC_IDS.size(),
		"предзагружено музыки: %d" % Audio._music_streams.size())

	# формат потока: 22050 Гц моно
	var click: AudioStream = Audio._sfx_streams.get("click")
	_check(click is AudioStreamWAV and (click as AudioStreamWAV).mix_rate == 22050,
		"click.wav импортирован как AudioStreamWAV 22050 Гц")

	# главная проверка: play_sfx не падает
	Audio.play_sfx("click")
	_check(true, "Audio.play_sfx(\"click\") — без исключений")

	# неизвестный id — предупреждение, но не падение
	Audio.play_sfx("no_such_id")
	_check(true, "Audio.play_sfx(\"no_such_id\") — push_warning, не падает")

	# громкость
	Audio.set_sfx_volume(0.5)
	_check(is_equal_approx(Audio.sfx_volume, 0.5), "set_sfx_volume(0.5) записал поле")
	_check(is_equal_approx(Audio._sfx_db, -6.0206),
		"set_sfx_volume(0.5) -> volume_db ≈ -6.02 (факт %.4f)" % Audio._sfx_db)
	Audio.set_music_volume(0.4)
	_check(is_equal_approx(Audio.music_volume, 0.4), "set_music_volume(0.4) записал поле")
	Audio.set_sfx_volume(9.9)
	_check(Audio.sfx_volume == 1.0, "set_sfx_volume(9.9) зажат до 1.0")
	Audio.set_sfx_volume(-1.0)
	_check(Audio.sfx_volume == 0.0, "set_sfx_volume(-1.0) зажат до 0.0")

	# mute (сначала возвращаем ненулевую громкость, иначе 0.0 — это тоже тишина)
	Audio.set_sfx_volume(0.9)
	Audio.set_muted(true)
	_check(Audio.muted and Audio._sfx_db <= -80.0, "set_muted(true) глушит пул")
	Audio.set_muted(false)
	_check(not Audio.muted and Audio._sfx_db > -80.0, "set_muted(false) возвращает звук")

	# весь набор эффектов подряд — пул из 8 выдерживает
	for id in SFX_IDS:
		Audio.play_sfx(id)
	_check(true, "все %d SFX проиграны подряд без падений" % SFX_IDS.size())

	# музыка
	Audio.play_music("hum")
	var music_playing: bool = Audio.get("_music_player").playing
	_check(music_playing, "play_music(\"hum\") запускает фон")
	var wav := Audio.get("_music_player").stream as AudioStreamWAV
	_check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and wav.loop_begin == 0 and wav.loop_end == 66150,
		"гул зациклен: loop_mode=FORWARD, loop_end=66150 (3.0 с @22050)")
	Audio.play_music("hum")  # повторный вызов — no-op
	_check(Audio.get("_music_player").playing, "повторный play_music не сбрасывает фон")
	Audio.stop_music()
	_check(not Audio.get("_music_player").playing, "stop_music останавливает фон")

	Audio.set_sfx_volume(0.9)
	Audio.set_music_volume(0.8)

	# Хвост для headless: dummy-аудиодрайвер не успевает освободить
	# playback'ы, если выйти сразу после play() — тогда при выходе сыплются
	# «ObjectDB instances were leaked». Останавливаем пул и даём кадрам
	# доработать перед quit().
	for player in Audio._pool:
		player.stop()
	Audio.stop_music()
	await create_timer(0.3).timeout
	_finish()


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
