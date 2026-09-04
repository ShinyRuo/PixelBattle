@tool
class_name PBPixelate
extends RefCounted
## 高清立绘 → 真·低分辨率像素图的那条降采样流水线。M6-p。
##
## ## 它解决的是什么
##
## AI 出的立绘是「看起来像素风的插画」：边缘带半透明、格子宽窄不一、
## 脸画得很清楚。这条流水线把它**真的**降到几十像素高，再用最近邻放大回去 ——
## 于是每一格都是一个实心方块，脸上只剩几个像素点。
##
## 产出直接当视频模型的**首帧图**用（见 `Docs/AI出图_战场形象.md` §2.5）。
##
## ## 为什么只有一份实现
##
## 命令行（[PBPixelateCli]）和编辑器插件（[PBPixelatePanel]）都只是它的调用方。
## 各写一份的话「命令行出的图和插件出的图差一个色阶」迟早发生，而它**不报错** ——
## 表现是同一个角色的四段视频首帧不是同一张图，而角色一致性全押在那张图上。
## 这和 [PBActorForge] 是同一条规矩。
##
## ## 四段里有三段是「不写就不报错」的
##
## 1. **抠洋红要连预乘一起做**（[method prepare]）。抠完之后透明像素的 RGB
##    仍然是洋红，缩放一平均就往人物边缘渗粉，**而 alpha 看起来完全正常**。
## 2. **alpha 要二值化**（[method _finish]）。降采样会产出一圈半透明边缘，
##    直接盖回洋红上就又是一圈粉边；砍成「要么在要么不在」，边缘才是硬的，
##    后面 [PBActorForge] 那一趟的抠色也才干净。
## 3. **放大只能最近邻**。双线性会把刚做出来的方块又糊回去，
##    而那时图看起来「还行」，只是白做了。
##
## 第四段（[method _quantize] 压调色板）不是防错的，是效果：
## 渐变和高光被并成一块，「插画感」掉得比降分辨率还快。
##
## ## 逐像素循环只发生在一处
##
## 原图 1024×1024 是一百万像素，GDScript 逐像素扫一遍要一秒上下 ——
## 所以**抠色那一趟只跑一次**（[method prepare]），几个档位的预览共用它的结果；
## 缩放和放大走 [Image] 的 C++ 接口；其余逐像素的活全发生在
## 那张几十像素见方的小图上。

## 背景色。和 [constant PBActorForge.FILTER] 里抠的是同一个洋红。
const KEY_COLOR := Color(1.0, 0.0, 1.0)

## 预览摊开哪几档（小图高度）。**从「只剩色块」到「基本没压住」**，
## 一眼比出来才知道该要哪一档 —— 光看一个数字选不出来。
const LEVELS: PackedInt32Array = [48, 64, 80, 96, 128, 160]

const DEFAULT_HEIGHT: int = 96
const DEFAULT_COLORS: int = 24

## 抠背景的容差。**粉发的角色不要往上调**：浅粉到洋红的距离只有 0.41，
## 调到 [PBActorForge] 那边用的 0.34 就开始啃头发，而它不报错。
## 那边面对的是视频帧（带压缩噪点）所以必须松，这边是干净的 PNG。
const DEFAULT_TOL: float = 0.20

## 二值化的门槛（0~255）。低于它的边缘像素整个丢掉。
const ALPHA_CUT: int = 128

## 小图高度。实际倍数是**取整**的，见 [method factor]。
var height: int = DEFAULT_HEIGHT

## 调色板压到几种颜色，0 = 不压。
var colors: int = DEFAULT_COLORS

var tol: float = DEFAULT_TOL

## 背景不是洋红时关掉它（那时边缘不抠，直接按 RGB 缩）。
var keyed: bool = true


## 从磁盘读一张图。**走 [method Image.load_from_file] 不走 `load()`** ——
## 输入图在 `res://` 外面（`aires\` 是原始素材，不进导入库），
## 而 `load()` 只认导入过的资源。
static func read(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


## 缩多少倍。**必须是整数** —— 非整数倍会把像素栅格压成宽窄不一的格子，
## 而它不报错，只表现为「看着有点脏」。
func factor(source_height: int) -> int:
	return maxi(1, int(round(float(source_height) / float(maxi(1, height)))))


## 抠洋红 + 预乘。**这一趟是整条链上唯一的百万像素循环**，
## 所以它单独摆出来：几个档位的预览共用同一份结果。
func prepare(source: Image) -> Image:
	var out := Image.new()
	out.copy_from(source)
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	if not keyed:
		return out
	var data := out.get_data()
	var cut := tol * tol * 3.0
	var i: int = 0
	while i < data.size():
		var dr := float(data[i]) / 255.0 - KEY_COLOR.r
		var dg := float(data[i + 1]) / 255.0 - KEY_COLOR.g
		var db := float(data[i + 2]) / 255.0 - KEY_COLOR.b
		if dr * dr + dg * dg + db * db <= cut:
			data[i] = 0
			data[i + 1] = 0
			data[i + 2] = 0
			data[i + 3] = 0
		i += 4
	return Image.create_from_data(
		out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, data
	)


## 出小图。`prepared` 是 [method prepare] 的结果，可以反复用。
func shrink(prepared: Image, to_factor: int) -> Image:
	var n := maxi(1, to_factor)
	var small := Image.new()
	small.copy_from(prepared)
	small.resize(
		maxi(1, prepared.get_width() / n),
		maxi(1, prepared.get_height() / n),
		Image.INTERPOLATE_LANCZOS
	)
	_finish(small)
	if colors > 0:
		_quantize(small, colors)
	return small


## 最近邻放大回去。**只能最近邻**，理由见类头第 3 条。
func enlarge(small: Image, by_factor: int) -> Image:
	var n := maxi(1, by_factor)
	var big := Image.new()
	big.copy_from(small)
	big.resize(small.get_width() * n, small.get_height() * n, Image.INTERPOLATE_NEAREST)
	return big


## 一次走完。命令行那条路用这个。
func run(source: Image) -> Dictionary:
	var n := factor(source.get_height())
	var small := shrink(prepare(source), n)
	return {"small": small, "big": enlarge(small, n), "factor": n}


## 解预乘 → alpha 二值化 → 盖回洋红底。三件事共用一趟循环 ——
## 这时候图已经只有几十像素见方了。
func _finish(image: Image) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c := image.get_pixel(x, y)
			if not keyed:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
				continue
			if c.a * 255.0 < float(ALPHA_CUT):
				image.set_pixel(x, y, KEY_COLOR)
				continue
			# 预乘的逆运算：缩放稀释过的颜色除回来
			var k := 1.0 / c.a
			image.set_pixel(x, y, Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0)))


## 中位切分（median cut）压调色板。在小图上跑，几千个像素。
##
## **背景那个洋红一定会占到一个色位**（它是面积最大的一块），
## 所以压完之后 [PBActorForge] 那一趟仍然抠得到它。
func _quantize(image: Image, want: int) -> void:
	var counts: Dictionary = {}
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c := image.get_pixel(x, y)
			var key := (int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)
			counts[key] = int(counts.get(key, 0)) + 1
	if counts.size() <= want:
		return

	var boxes: Array = [counts.keys()]
	while boxes.size() < want:
		var pick := _widest(boxes)
		if pick < 0:
			break
		boxes.append_array(_split(boxes[pick]))
		boxes.remove_at(pick)

	var palette: Array[Color] = []
	for box: Array in boxes:
		palette.append(_average(box, counts))
	var mapped: Dictionary = {}
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c := image.get_pixel(x, y)
			var key := (int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)
			if not mapped.has(key):
				mapped[key] = _nearest(c, palette)
			image.set_pixel(x, y, mapped[key])


## 挑一个还能切的箱子：色域最宽的那个。全是单色就返回 -1。
func _widest(boxes: Array) -> int:
	var best: int = -1
	var best_span: int = 0
	for i: int in boxes.size():
		var box: Array = boxes[i]
		if box.size() < 2:
			continue
		var span: int = 0
		for channel: int in 3:
			var lo: int = 255
			var hi: int = 0
			for key: int in box:
				var v := (key >> (16 - channel * 8)) & 0xFF
				lo = mini(lo, v)
				hi = maxi(hi, v)
			span = maxi(span, hi - lo)
		if span > best_span:
			best_span = span
			best = i
	return best


## 按最宽的那个通道从中位切成两半。
func _split(box: Array) -> Array:
	var widest: int = 0
	var widest_span: int = -1
	for channel: int in 3:
		var lo: int = 255
		var hi: int = 0
		for key: int in box:
			var v := (key >> (16 - channel * 8)) & 0xFF
			lo = mini(lo, v)
			hi = maxi(hi, v)
		if hi - lo > widest_span:
			widest_span = hi - lo
			widest = channel
	var shift := 16 - widest * 8
	var sorted: Array = box.duplicate()
	sorted.sort_custom(
		func(a: int, b: int) -> bool: return ((a >> shift) & 0xFF) < ((b >> shift) & 0xFF)
	)
	var half := sorted.size() / 2
	return [sorted.slice(0, half), sorted.slice(half)]


## 箱子里那些颜色的**加权**平均（按出现次数）—— 不加权的话
## 一个只有三个像素的高光会把整块的颜色拉走。
func _average(box: Array, counts: Dictionary) -> Color:
	var total: int = 0
	var sums := Vector3i.ZERO
	for key: int in box:
		var n: int = counts[key]
		total += n
		sums += Vector3i((key >> 16) & 0xFF, (key >> 8) & 0xFF, key & 0xFF) * n
	if total == 0:
		return Color.BLACK
	return Color(
		float(sums.x) / float(total) / 255.0,
		float(sums.y) / float(total) / 255.0,
		float(sums.z) / float(total) / 255.0
	)


func _nearest(c: Color, palette: Array[Color]) -> Color:
	var best := palette[0]
	var best_d := INF
	for p: Color in palette:
		var d := (
			(p.r - c.r) * (p.r - c.r) + (p.g - c.g) * (p.g - c.g) + (p.b - c.b) * (p.b - c.b)
		)
		if d < best_d:
			best_d = d
			best = p
	return best
