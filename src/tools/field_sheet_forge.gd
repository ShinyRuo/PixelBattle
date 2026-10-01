@tool
class_name PBFieldSheetForge
extends RefCounted
## 整图切帧。网格保留空尾帧；统一画布与缩放，不把逐帧扩散缩成同一大小。
## 浅底烟雾模式只提取暗部密度，不能还原被烘焙背景遮掉的原始色彩。

enum Background { ALPHA, DARK, KEY, SMOKE }

var cells: Array[Rect2i] = []
var error: String = ""
var columns: int = 3
var rows: int = 2
var count: int = 6
var output_size: int = 256
var gap: int = 12
var automatic: bool = false
var center_frames: bool = true
var square_canvas: bool = true
var background: Background = Background.ALPHA
var smoke_floor: float = 0.93


func slice(source: Image) -> Array[Image]:
	error = ""
	cells.clear()
	var out: Array[Image] = []
	if source == null or source.is_empty():
		error = "先选择一张序列帧整图"
		return out
	if columns < 1 or rows < 1 or count < 1 or count > 64 or output_size < 16:
		error = "列数、行数、帧数或输出尺寸无效"
		return out
	var work := _prepare(source)
	if automatic:
		cells = PBSheetCutter.cut(_mask(work), gap, 4, count)
	else:
		_grid(source.get_size())
	if cells.size() != count:
		error = "切出 %d 帧，需要 %d 帧；调整网格或空白间距" % [cells.size(), count]
		return out
	var pieces: Array[Image] = []
	var box := Vector2i.ONE
	for cell: Rect2i in cells:
		var piece := work.get_region(cell)
		var used := piece.get_used_rect()
		if center_frames and used.has_area():
			piece = piece.get_region(used)
		elif center_frames:
			piece = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		pieces.append(piece)
		box = box.max(piece.get_size())
	if square_canvas:
		box = Vector2i.ONE * maxi(box.x, box.y)
	for piece: Image in pieces:
		var canvas := Image.create_empty(box.x, box.y, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(
			piece, Rect2i(Vector2i.ZERO, piece.get_size()), (box - piece.get_size()) / 2
		)
		# 在预乘空间缩放，避免透明边缘染黑；最终恢复普通透明混合。
		_premultiply(canvas)
		var factor := float(output_size) / maxi(box.x, box.y)
		canvas.resize(
			maxi(roundi(box.x * factor), 1),
			maxi(roundi(box.y * factor), 1),
			Image.INTERPOLATE_LANCZOS
		)
		PBFxForge.unpremultiply(canvas)
		out.append(canvas)
	return out


func _grid(size: Vector2i) -> void:
	if count > columns * rows or size.x < columns or size.y < rows:
		return
	for i: int in count:
		var x := i % columns
		var y := i / columns
		var begin := Vector2i(x * size.x / columns, y * size.y / rows)
		var end := Vector2i((x + 1) * size.x / columns, (y + 1) * size.y / rows)
		cells.append(Rect2i(begin, end - begin))


func _prepare(source: Image) -> Image:
	var work := source.duplicate() as Image
	work.convert(Image.FORMAT_RGBA8)
	match background:
		Background.DARK:
			PBFxForge.dark_to_alpha(work, PBFxForge.DARK_FLOOR)
		Background.KEY:
			PBFxForge.soft_key(work, PBSheetCutter.guess_key(work))
			PBFxForge.unpremultiply(work)
		Background.SMOKE:
			_smoke(work)
	return work


func _smoke(work: Image) -> void:
	var bytes := work.get_data()
	for i: int in bytes.size() / 4:
		var at := i * 4
		var light := (float(bytes[at]) + bytes[at + 1] + bytes[at + 2]) / 765.0
		var density := clampf((smoke_floor - light) / maxf(smoke_floor - 0.08, 0.01), 0, 1)
		bytes[at] = 20
		bytes[at + 1] = 20
		bytes[at + 2] = 20
		bytes[at + 3] = roundi(density * bytes[at + 3])
	work.set_data(work.get_width(), work.get_height(), false, Image.FORMAT_RGBA8, bytes)


static func _premultiply(work: Image) -> void:
	var bytes := work.get_data()
	for i: int in bytes.size() / 4:
		var at := i * 4
		var alpha := float(bytes[at + 3]) / 255.0
		for channel: int in 3:
			bytes[at + channel] = roundi(bytes[at + channel] * alpha)
	work.set_data(work.get_width(), work.get_height(), false, Image.FORMAT_RGBA8, bytes)


## 切格用二值掩码，不能用人物工具的 50% alpha 门槛丢掉浅色特效。
static func _mask(work: Image) -> Image:
	var mask := work.duplicate() as Image
	var bytes := mask.get_data()
	for i: int in bytes.size() / 4:
		bytes[i * 4 + 3] = 255 if bytes[i * 4 + 3] >= 5 else 0
	mask.set_data(work.get_width(), work.get_height(), false, Image.FORMAT_RGBA8, bytes)
	return mask
