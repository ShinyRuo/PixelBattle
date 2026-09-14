@tool
class_name PBFxForge
extends RefCounted
## 特效图集（子弹、命中、范围爆发、光环）→ 一段帧 PNG 的流水线。规格见 `Docs/素材规格_特效.md`。
##
## 和 [PBActorForge] 是两条流水线：特效没有脚底、不需要跨段共用缩放比，只要「切开、摆齐、缩到位」。
## 切格走同一个 [PBSheetCutter]（按空白带切，不按等分网格）。
##
## ## 两种背景
##
## - [constant Mode.DARK]：**纯黑底**，发光类（火、雷、查克拉、光环）。黑底上的颜色本身就是预乘过的
##   （颜色 × 亮度），所以摆齐和缩放都在黑底上做，最后一步才把亮度折成透明度（[method dark_to_alpha]）——
##   先抠再缩的话，半透明光晕会在缩放时被透明像素染暗。
## - [constant Mode.KEY]：**洋红底**，实体类（苦无、手里剑）。**软抠 + 去色溢**（[method soft_key]）：
##   边缘那一圈是「物体色和洋红混出来的」，按二值抠的话它们全留下来、alpha 拉满，缩小之后就是一圈紫边。
##   抠完存成预乘的，缩完再除回来（[method unpremultiply]）。
##
## ## 一段里每一帧同一个画布、同一个缩放比
##
## 画布取这一段里最大那一格的尺寸，每一格按锚点摆进去再一起缩 —— 各缩各的话，
## 一个扩散的爆炸会在每一帧里一样大。

enum Mode { DARK, KEY }
enum Anchor { CENTER, BOTTOM }

## 黑底模式下亮度低于它的像素算背景（出图模型的「纯黑」常带一点噪点）。
const DARK_FLOOR: float = 0.05

## 洋红底软抠的两道门槛，单位是「这个像素有背景色的几成洋红」（见 [method soft_key]）。
## 低于 [constant KEY_SOLID] 算实心物体，高于 [constant KEY_CLEAR] 算纯背景，中间按比例半透明。
## 背景那一头留得宽：出图模型的洋红底不纯、JPG 还会在边上糊出色块，
## 门槛贴着 1.0 的话背景里到处是几乎透明的脏点，切格的包围盒会被撑大。
const KEY_SOLID: float = 0.12
const KEY_CLEAR: float = 0.80

## 算出来的 alpha 低于它就当全透明，理由同 [constant KEY_CLEAR]。
const KEY_DUST: float = 0.06

## 上一次 [method slice] 量到的东西：`cells`（每一格在原图上的矩形）、`canvas`（缩放前的画布尺寸）。
var measured: Dictionary = {}


## 读一张图集，切成一段帧写进 [param out_dir]（`<anim>_<序号>.png`）。**返回错误信息，空串 = 成功。**
##
## [param size] 是成品画布长边的像素数（0 = 不缩放）。[param want] > 0 时切出的格数必须正好是它。
## 这一段原来多出来的旧帧会被删掉，否则加载时一直数到断号为止会把它们也算进去。
func cut(
	sheet_path: String,
	out_dir: String,
	anim: String,
	mode: Mode = Mode.DARK,
	anchor: Anchor = Anchor.CENTER,
	size: int = 0,
	want: int = 0
) -> String:
	var sheet := Image.load_from_file(sheet_path)
	if sheet == null or sheet.is_empty():
		return "读不到图：%s" % sheet_path
	var frames := slice(sheet, mode, anchor, size, want)
	if frames.is_empty():
		return "一格都没切出来：%s（背景模式选对了吗？格与格之间留空了吗？）" % sheet_path
	if want > 0 and frames.size() != want:
		return "切出 %d 格，要的是 %d 格：%s" % [frames.size(), want, sheet_path]
	return write(frames, out_dir, anim)


## 把切好的一段写进 [param out_dir]（`<anim>_<序号>.png`），并删掉这一段多出来的旧帧。
## **返回错误信息，空串 = 成功。** 命令行和编辑器面板都走这一份。
static func write(frames: Array[Image], out_dir: String, anim: String) -> String:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return "建不了目录：%s" % out_dir
	for i: int in frames.size():
		var path: String = "%s/%s_%d.png" % [out_dir, anim, i]
		if frames[i].save_png(path) != OK:
			return "写不进去：%s" % path
	_drop_extra(out_dir, anim, frames.size())
	return ""


## 把一张图集切成一段帧（不碰磁盘）。**不改动 [param sheet]。**
func slice(sheet: Image, mode: Mode, anchor: Anchor, size: int = 0, want: int = 0) -> Array[Image]:
	var out: Array[Image] = []
	measured = {}
	if sheet == null or sheet.is_empty():
		return out
	var work := sheet.duplicate() as Image
	work.convert(Image.FORMAT_RGBA8)
	var mask: Image = work
	if mode == Mode.KEY:
		soft_key(work, PBSheetCutter.guess_key(work))
	else:
		mask = dark_mask(work, DARK_FLOOR)
	var cells := _tighten(
		mask, PBSheetCutter.cut(mask, PBSheetCutter.DEFAULT_GAP, PBSheetCutter.DEFAULT_CELL, want)
	)
	if cells.is_empty():
		return out
	var box := Vector2i.ZERO
	for cell: Rect2i in cells:
		box = Vector2i(maxi(box.x, cell.size.x), maxi(box.y, cell.size.y))
	box = Vector2i(box.x + box.x % 2, box.y + box.y % 2)
	measured = {"cells": cells, "canvas": box}
	for cell: Rect2i in cells:
		var canvas := Image.create_empty(box.x, box.y, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0.0, 0.0, 0.0, 1.0 if mode == Mode.DARK else 0.0))
		var at := Vector2i((box.x - cell.size.x) / 2, (box.y - cell.size.y) / 2)
		if anchor == Anchor.BOTTOM:
			at.y = box.y - cell.size.y
		canvas.blit_rect(work, cell, at)
		_scale_to(canvas, size)
		if mode == Mode.DARK:
			dark_to_alpha(canvas, DARK_FLOOR)
		else:
			unpremultiply(canvas)
		out.append(canvas)
	return out


## 每一格收紧到它的内容上。**必须有这一步**：[method PBSheetCutter.cut] 先分行带再分列，
## 同一行里每一格的高度都是整条带的高度 —— 不收紧的话小的那一帧会带着一截空白摆进画布，居中和贴底都偏。
static func _tighten(mask: Image, cells: Array[Rect2i]) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for cell: Rect2i in cells:
		var used := mask.get_region(cell).get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			out.append(Rect2i(cell.position + used.position, used.size))
	return out


## 洋红底软抠，**原地改**，结果是**预乘**过的（RGB 已乘 alpha）。
##
## 把每个像素看成 `物体色 × a + 背景色 × (1 − a)`。洋红的特征是「红蓝都高、绿低」，
## 于是「洋红成分」取 `min(r, b) − g`，和背景色自己的那个值一比就是背景占几成，`a = 1 − 那个比例`。
## a 定下来之后把背景色从像素里**减回去**（`(像素 − 背景 × (1 − a)) / a`），边缘的紫色就还原成物体本来的颜色。
##
## 两道收尾，都是实测那张苦无图上看出来的：
##
## - **a 不许小到「减完是负数」**：减背景时红蓝先减穿、被夹成 0，绿却留着 —— 边上会冒出一粒粒绿点。
##   所以 a 至少取到红、蓝都不减穿的那个值。
## - **去色溢**：减完还剩的「红蓝都比绿高」那一截是洋红的残留，从红蓝里一起扣掉。不扣的话暗色物体会描一圈紫边。
##   半透明的边上反过来也管：绿不许比红蓝都高（JPG 会把边糊出一圈暗绿）。
##
## **假设物体本身不带洋红或粉色**（提示词里写着）：紫色、粉色的物体会被当成半透明的背景抠薄、再被扣成灰色。
static func soft_key(image: Image, key: Color) -> void:
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var key_amount: float = maxf(minf(key.r, key.b) - key.g, 0.05)
	for i: int in data.size() / 4:
		var at: int = i * 4
		var r: float = float(data[at]) / 255.0
		var g: float = float(data[at + 1]) / 255.0
		var b: float = float(data[at + 2]) / 255.0
		var share: float = maxf(minf(r, b) - g, 0.0) / key_amount
		var a: float = clampf(1.0 - (share - KEY_SOLID) / (KEY_CLEAR - KEY_SOLID), 0.0, 1.0)
		if a < KEY_DUST:
			data[at] = 0
			data[at + 1] = 0
			data[at + 2] = 0
			data[at + 3] = 0
			continue
		# 背景最多占 `min(r / 背景r, b / 背景b)` 那么多，再多红蓝就减穿了。
		var room: float = minf(r / maxf(key.r, 0.05), b / maxf(key.b, 0.05))
		a = maxf(a, 1.0 - minf(room, 1.0))
		# 预乘之后的颜色 = 物体色 × a = 像素 − 背景 × (1 − a)。
		var rest: float = 1.0 - a
		var pr: float = clampf(r - key.r * rest, 0.0, a)
		var pg: float = clampf(g - key.g * rest, 0.0, a)
		var pb: float = clampf(b - key.b * rest, 0.0, a)
		var spill: float = minf(pr, pb) - pg
		if spill > 0.0:
			pr -= spill
			pb -= spill
		# 半透明的边上绿也不许冒尖：JPG 的色块把洋红糊成了一圈暗绿。只管边，实心的绿色物体不受影响。
		if a < 1.0:
			pg = minf(pg, maxf(pr, pb))
		data[at] = roundi(pr * 255.0)
		data[at + 1] = roundi(pg * 255.0)
		data[at + 2] = roundi(pb * 255.0)
		data[at + 3] = roundi(a * 255.0)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


## 黑底图 → 透明图：透明度 = 三个通道里最亮的那个，颜色除回来。低于 [param dim] 的算背景。
##
## 这样出来的图用**加法混合**叠上去和原来的黑底图几乎相同（差一级取整），用普通混合在暗背景上也看得过去。
static func dark_to_alpha(image: Image, dim: float = DARK_FLOOR) -> void:
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var cut_at: int = int(dim * 255.0)
	for i: int in data.size() / 4:
		var at: int = i * 4
		var peak: int = maxi(data[at], maxi(data[at + 1], data[at + 2]))
		if peak < cut_at or peak == 0:
			data[at] = 0
			data[at + 1] = 0
			data[at + 2] = 0
			data[at + 3] = 0
			continue
		data[at] = mini(data[at] * 255 / peak, 255)
		data[at + 1] = mini(data[at + 1] * 255 / peak, 255)
		data[at + 2] = mini(data[at + 2] * 255 / peak, 255)
		data[at + 3] = peak
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


## 黑底图的「哪里有东西」：亮度不低于 [param dim] 的像素不透明，其余全透明。只拿来切格。
##
## 门槛取得低，暗淡的光晕也算进格子里 —— 否则切出来的矩形会把光晕的外圈裁掉。
static func dark_mask(image: Image, dim: float = DARK_FLOOR) -> Image:
	var mask := image.duplicate() as Image
	mask.convert(Image.FORMAT_RGBA8)
	var data := mask.get_data()
	var cut_at: int = int(dim * 255.0)
	for i: int in data.size() / 4:
		var at: int = i * 4
		var peak: int = maxi(data[at], maxi(data[at + 1], data[at + 2]))
		data[at + 3] = 255 if peak >= cut_at and peak > 0 else 0
	mask.set_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8, data)
	return mask


## 预乘图 → 普通图：颜色除以透明度。全透明的像素颜色归零。
static func unpremultiply(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	for i: int in data.size() / 4:
		var at: int = i * 4
		var alpha: int = data[at + 3]
		if alpha == 0:
			data[at] = 0
			data[at + 1] = 0
			data[at + 2] = 0
			continue
		data[at] = mini(data[at] * 255 / alpha, 255)
		data[at + 1] = mini(data[at + 1] * 255 / alpha, 255)
		data[at + 2] = mini(data[at + 2] * 255 / alpha, 255)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


## 等比缩到长边正好 [param size]，两边凑成偶数（锚点落在中点上不偏半格）。0 = 不缩。
static func _scale_to(image: Image, size: int) -> void:
	if size <= 0:
		return
	var w: int = image.get_width()
	var h: int = image.get_height()
	var ratio: float = float(size) / float(maxi(w, h))
	var to_w: int = maxi(int(round(float(w) * ratio)), 2)
	var to_h: int = maxi(int(round(float(h) * ratio)), 2)
	image.resize(to_w + to_w % 2, to_h + to_h % 2, Image.INTERPOLATE_CUBIC)


## 删掉这一段第 [param keep] 帧起的旧帧（连 `.import` 一起）。
static func _drop_extra(out_dir: String, anim: String, keep: int) -> void:
	var i: int = keep
	while true:
		var path: String = "%s/%s_%d.png" % [out_dir, anim, i]
		if not FileAccess.file_exists(path):
			return
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".import"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".import"))
		i += 1
