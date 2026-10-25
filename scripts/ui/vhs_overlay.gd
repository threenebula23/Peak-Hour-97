class_name VhsOverlay
extends RefCounted
## Процедурный VHS-слой главного меню. НЕ создаёт Node/Control и не читает
## screen texture.
##
## Меню рисует его прямо в MainMenu._draw() в два прохода:
##   бумага → VHS фона → карточка/панель/фигуры → VHS по ним → текст.
## Поэтому слой не перекрывает меню, не перехватывает мышь и не может
## затереть кадр фоном подготовки. Кнопки — дети MainMenu, они поверх.
##
## Состояние и параметры здесь; рисование вызывает меню:
##   vhs.draw_layer(self, full_rect)
##   vhs.advance(delta) + queue_redraw() при анимации
##
## В HEADLESS текстуры не создаются и draw_layer() ничего не рисует.

## Скан-линии: шаг 2 логических px (при 1920×1080 — 3 физ. px), 1 px затемнения.
const SCANLINE_STEP := 2.0
const SCANLINE_STRENGTH := 0.07
const GRAIN_SIZE := 128
const VIGNETTE_W := 320
const VIGNETTE_H := 180

const DARK := Color(0.035, 0.045, 0.05)
const LIGHT := Color(0.99, 0.99, 0.96)

## Включён ли эффект. Отключается кодом: menu.set_vhs_enabled(false).
var enabled := true
## Общая сила слоя, 0.0..0.55.
var intensity := 0.42
## Внутреннее время анимации (полоса и зерно).
var time := 0.0

var _grain: ImageTexture = null
var _vignette: ImageTexture = null
var _band: ImageTexture = null
var _ready_ok := false


func _init() -> void:
	# В headless не тратим время на генерацию текстур и анимацию.
	_ready_ok = DisplayServer.get_name() != "headless"
	if not _ready_ok:
		return
	_build_grain()
	_build_vignette()
	_build_band()


func set_enabled(value: bool) -> void:
	enabled = value


func is_available() -> bool:
	return _ready_ok


## Продвинуть время анимации. Вызывается меню из _process.
func advance(delta: float) -> void:
	if enabled and _ready_ok:
		time += delta


## Нарисовать VHS в rect. Canvas — обычно сам MainMenu.
##
## over_content=false — проход по бумажному фону: скан-линии, зерно,
## виньетка и полоса. over_content=true — мягкий проход по карточке и панели
## ДО отрисовки текста: чуть слабее, без виньетки, но с той же полосой.
func draw_layer(canvas: CanvasItem, rect: Rect2, over_content: bool = false) -> void:
	if not enabled or not _ready_ok:
		return
	var k := 0.72 if over_content else 1.0

	# 1. Скан-линии: 1 px затемнения каждые 2 px.
	var scan := Color(DARK.r, DARK.g, DARK.b, SCANLINE_STRENGTH * intensity * k)
	var y := rect.position.y
	while y < rect.end.y:
		canvas.draw_rect(Rect2(rect.position.x, y, rect.size.x, 1.0), scan)
		y += SCANLINE_STEP

	# 2. Зерно: тайл 128×128, обновляется 2 раза в секунду.
	var step := int(floor(time * 2.0))
	var off := Vector2(float((step * 37) % GRAIN_SIZE), float((step * 53) % GRAIN_SIZE))
	canvas.draw_texture_rect(_grain,
		Rect2(rect.position - off, rect.size + off), true,
		Color(1, 1, 1, intensity * k))

	# 3. Виньетка — только у краёв кадра, не на карточке.
	if not over_content:
		canvas.draw_texture_rect(_vignette, rect, false, Color(1, 1, 1, intensity))

	# 4. Редкая полоса прокрутки: медленно идёт сверху вниз с лёгким дрожанием.
	#    Позиция считается по логической высоте кадра (720), поэтому полоса
	#    совпадает на бумаге и на карточке; rect только обрезает её.
	var band_h := 96.0
	var span := 720.0 + band_h * 2.0
	var band_top := fposmod(time * 0.055, 1.0) * span - band_h
	var top := maxf(band_top, rect.position.y)
	var bottom := minf(band_top + band_h, rect.end.y)
	if bottom > top:
		var v0 := (top - band_top) / band_h
		var v1 := (bottom - band_top) / band_h
		var src := Rect2(0.0, v0 * _band.get_height(), _band.get_width(),
			(v1 - v0) * _band.get_height())
		var jitter := sin(time * 0.7) * 4.0
		canvas.draw_texture_rect_region(_band,
			Rect2(rect.position.x + jitter, top, rect.size.x, bottom - top),
			src, Color(1, 1, 1, intensity * k))


func _build_grain() -> void:
	var img := Image.create(GRAIN_SIZE, GRAIN_SIZE, false, Image.FORMAT_RGBA8)
	for yy in GRAIN_SIZE:
		for xx in GRAIN_SIZE:
			var n := float((xx * 73 + yy * 151 + 31) % 97) / 97.0
			var c := DARK if n < 0.5 else LIGHT
			var a := absf(n - 0.5) * 2.0 * 0.05
			img.set_pixel(xx, yy, Color(c.r, c.g, c.b, a))
	_grain = ImageTexture.create_from_image(img)


func _build_vignette() -> void:
	var img := Image.create(VIGNETTE_W, VIGNETTE_H, false, Image.FORMAT_RGBA8)
	for yy in VIGNETTE_H:
		for xx in VIGNETTE_W:
			var q := Vector2(float(xx) / VIGNETTE_W - 0.5,
				float(yy) / VIGNETTE_H - 0.5)
			q.x *= 16.0 / 9.0
			var v := smoothstep(0.34, 0.94, q.length())
			img.set_pixel(xx, yy, Color(DARK.r, DARK.g, DARK.b, v * 0.13))
	_vignette = ImageTexture.create_from_image(img)


func _build_band() -> void:
	const BW := 128
	const BH := 32
	var img := Image.create(BW, BH, false, Image.FORMAT_RGBA8)
	for yy in BH:
		var cy := absf(float(yy) / (BH - 1) - 0.5) * 2.0
		var band_a := (1.0 - cy * cy) * 0.12
		for xx in BW:
			# слабые вертикальные штрихи — при дрожании полоса «плывёт»
			var streak := 0.85 + 0.15 * float((xx * 29) % 17) / 17.0
			if yy == 0:
				# светлая ведущая кромка — «трекинг» кассеты
				img.set_pixel(xx, yy, Color(LIGHT.r, LIGHT.g, LIGHT.b,
					0.45 * streak))
			elif yy == BH - 1:
				img.set_pixel(xx, yy, Color(LIGHT.r, LIGHT.g, LIGHT.b,
					0.28 * streak))
			else:
				img.set_pixel(xx, yy, Color(DARK.r, DARK.g, DARK.b,
					band_a * streak))
	_band = ImageTexture.create_from_image(img)
