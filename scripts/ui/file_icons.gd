class_name FileIcons
extends RefCounted
## Атлас иконок файлов: 8×8 ячеек по 16 px (128×128), итого 64 иконки.
##
## Индекс (`icon_id` 0..63) назначает бэкенд (FileItem.icon_id / Packet.icon_id)
## и он стабилен между сохранениями. Рисуем ТОЛЬКО по индексу: тип файла
## (text/sound/photo/video) остаётся фолбэком для старых сейвов с icon_id = -1.
##
## Пиксель-арт: nearest-фильтр на время вызова, пропорции клетки сохраняются
## (квадрат по меньшей стороне rect, по центру). Нет текстуры/индекса — `false`,
## вызывающий рисует свой фолбэк.

const COUNT := 64
const COLS := 8
const ROWS := 8
const PATH := "res://art/icons/file_icons.png"

static var _texture: Texture2D = null
static var _loaded := false


## Текстура листа (кэшируется). null — PNG не импортирован: иконки не рисуем.
static func texture() -> Texture2D:
	if not _loaded:
		_loaded = true
		if ResourceLoader.exists(PATH):
			_texture = load(PATH) as Texture2D
	return _texture


static func is_valid(icon_id: int) -> bool:
	return icon_id >= 0 and icon_id < COUNT


## Область ячейки в пикселях текстуры.
static func cell_region(icon_id: int) -> Rect2:
	var tex := texture()
	if tex == null or not is_valid(icon_id):
		return Rect2()
	var size := tex.get_size()
	var cell := Vector2(size.x / float(COLS), size.y / float(ROWS))
	var col := icon_id % COLS
	var row := int(icon_id / COLS)
	return Rect2(float(col) * cell.x, float(row) * cell.y, cell.x, cell.y)


## Нарисовать иконку `icon_id` в rect (квадрат по меньшей стороне, по центру).
## alpha — множитель прозрачности; белая модуляция сохраняет цвета листа.
## false — иконки нет / неверный id: caller рисует фолбэк по типу файла.
static func draw(ci: CanvasItem, rect: Rect2, icon_id: int, alpha: float = 1.0) -> bool:
	if ci == null or not is_valid(icon_id) or alpha <= 0.01:
		return false
	var tex := texture()
	if tex == null:
		return false
	var s := minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return false
	var side := roundf(s)
	var top_left := (rect.position + (rect.size - Vector2(side, side)) * 0.5).round()
	var target := Rect2(top_left, Vector2(side, side))
	var region := cell_region(icon_id)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return false
	var prev := ci.texture_filter
	if prev != CanvasItem.TEXTURE_FILTER_NEAREST:
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.draw_texture_rect_region(tex, target, region, Color(1, 1, 1, alpha))
	if prev != CanvasItem.TEXTURE_FILTER_NEAREST:
		ci.texture_filter = prev
	return true
