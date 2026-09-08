@tool
class_name PBSheetCutter
extends RefCounted
## 把一张图集按**空白带**切成一格一格。M8-f。
##
## ## 为什么不按「平均切成 2×3」
##
## 实测四张真图集：`attack` 那张最左一格贴着画面左边，`dead` 那张上下两排
## 中间空了将近三分之一 —— **模型不会给你等分网格**。平均切的话格子边界
## 会从人物身上穿过去，而切歪了带进半个邻居之后包围盒就错，
## **画布、坐标、锚点全部看起来完全正确**（[PBActorForge] 全靠
## [method Image.get_used_rect] 量人）。
##
## 所以这里按实际的空白带切：逐行、逐列数前景像素，连续的非空区间就是一带。
## 先分行带，再在每个行带里分列 —— 出来的顺序天然就是**从左到右、
## 从上到下**，和提示词里要求的播放顺序一致。
##
## ## 为什么先抠背景再投影
##
## [method cut] 只看 alpha，一个字节一次比较。不先抠的话每个像素都要和洋红
## 比一次颜色距离，2048×2048 那张要多花好几秒 —— 而这一步在编辑器里是
## 同步跑的，卡住的是整个编辑器。
##
## 拆成两个函数还有一处实惠：[method cut] 对**任何**已经有透明背景的图都能用，
## 不绑死在洋红这一种底色上。

## 背景色。和 [constant PBPixelate.KEY_COLOR] 是同一个洋红 ——
## 两处分叉的话，「降采样面板抠得掉、切图工具抠不掉」这种事就会发生。
const KEY_COLOR := Color(1.0, 0.0, 1.0)

## 抠色容差。**跟 [constant PBPixelate.DEFAULT_TOL] 走 0.20，不跟
## [constant PBActorForge.FILTER] 那边的 0.34。**
##
## 那边吃的是带压缩噪点的视频帧，所以要放宽；这边是干净的 PNG。
## 而 0.34 会开始啃**浅粉**（浅粉到洋红只差 0.41）—— 粉发、粉衣服的角色
## 一调高就缺一块，而缺的那块看起来只是「这里怎么透明了」。
const DEFAULT_TOL: float = 0.20

## 判「这一行/列空不空」的地板。**不是 0** —— AI 出的图边缘常留几个孤立像素，
## 按 0 算的话它们会把本来分开的两格连成一格。
const FLOOR: int = 2

## 两格之间至少空多少像素才算断开。太小会把一个人切成两半（比如
## 出拳那帧分离的特效），太大会把相邻两格并成一格 —— 所以它是面板上
## 一个能调的滑块，切完翻一遍就知道调对没有。
const DEFAULT_GAP: int = 24

## 一格至少多大才算数，用来丢掉噪点。
const DEFAULT_CELL: int = 24


## 猜这张图的背景色。**不假设它是纯洋红。**
##
## ## 为什么要猜（M8-f 实测）
##
## 一张真图集（GPT Image 出的 2048×2048）：背景在 `#df2eda` 附近抖动，
## 离纯洋红 **0.263**，四角跨度 0.228~0.416 —— 它**根本不是 `#FF00FF`**，
## 而且不是平涂，带着噪点。
##
## 拿纯洋红加 0.20 的容差去抠，**一个像素都抠不掉**：投影因此全满、
## 整张图被当成一格，而屏幕上只是「切图按钮好像没反应」。
##
## 把容差放大到 0.42 能盖住，但那已经开始啃**浅粉**（浅粉到洋红只差 0.41），
## 粉发的角色会缺一块。所以正确的做法是**把中心挪到实际的背景色上**，
## 容差照旧 —— 以 `#df2eda` 为心，四角最远的那个也只有 0.16。
##
## ## 怎么猜
##
## 背景占了大半张图，所以它是**众数**。但要先**量化到每通道 32 级**再统计：
## 不量化的话噪点会把票分散掉，实测第一名只占 4.5%，
## 而那个数字本身就说明「最常见的那个颜色」在有噪点时不可靠。
static func guess_key(image: Image, step: int = 4) -> Color:
	if image == null:
		return KEY_COLOR
	var w: int = image.get_width()
	var h: int = image.get_height()
	if w <= 0 or h <= 0:
		return KEY_COLOR
	var work := image
	if work.get_format() != Image.FORMAT_RGBA8:
		work = image.duplicate() as Image
		work.convert(Image.FORMAT_RGBA8)
	var data := work.get_data()
	var counts: Dictionary = {}
	var best: int = -1
	var top: int = 0
	var stride: int = maxi(step, 1)
	for y: int in range(0, h, stride):
		var base: int = y * w * 4
		for x: int in range(0, w, stride):
			var at: int = base + x * 4
			# 已经透明的不投票 —— 那种图（比如重切一张切过的）背景本来就没了。
			if data[at + 3] < 128:
				continue
			var bucket: int = (
				((data[at] >> 3) << 10) | ((data[at + 1] >> 3) << 5) | (data[at + 2] >> 3)
			)
			var votes: int = int(counts.get(bucket, 0)) + 1
			counts[bucket] = votes
			if votes > top:
				top = votes
				best = bucket
	if best < 0:
		return KEY_COLOR
	# 桶心：移回去再加半个桶宽。桶宽 8，所以最多偏 4/255 ≈ 0.016，
	# 相比 0.20 的容差可以忽略。
	return Color8(((best >> 10) & 31) * 8 + 4, ((best >> 5) & 31) * 8 + 4, (best & 31) * 8 + 4)


## 把接近 [param key] 的像素抠成全透明，其余的 alpha 拉满。**原地改。**
##
## ## 为什么顺手把 alpha 拉满（而不是只清背景）
##
## 下游 [method PBActorForge.compose] 假设源帧是**预乘**过的（ffmpeg 那条链
## 里 `premultiply` 干的活），而预乘对 alpha=255 的像素没有任何影响、
## 对 alpha=0 的像素要求 RGB 也是 0 —— 这里两样都做到了，
## 所以切出来的帧和 ffmpeg 出的帧在 `compose` 眼里是同一种东西。
##
## 半透明一律归到两边去（像素画不许有半透明边缘，规格第 8 节）。
static func key_out(image: Image, key: Color = KEY_COLOR, tol: float = DEFAULT_TOL) -> void:
	if image == null:
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var limit: float = tol * tol
	var count: int = data.size() / 4
	for i: int in count:
		var at: int = i * 4
		var dr: float = float(data[at]) / 255.0 - key.r
		var dg: float = float(data[at + 1]) / 255.0 - key.g
		var db: float = float(data[at + 2]) / 255.0 - key.b
		if dr * dr + dg * dg + db * db <= limit:
			data[at] = 0
			data[at + 1] = 0
			data[at + 2] = 0
			data[at + 3] = 0
		else:
			data[at + 3] = 255
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


## 切成一格一格，**按从左到右、从上到下**排好。图里一格都没有就返回空数组。
##
## [param image] 必须**已经抠过背景**（[method key_out]）—— 这里只看 alpha。
static func cut(
	image: Image, min_gap: int = DEFAULT_GAP, min_cell: int = DEFAULT_CELL
) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if image == null:
		return out
	var w: int = image.get_width()
	var h: int = image.get_height()
	if w <= 0 or h <= 0:
		return out
	var data := image.get_data()
	var rows := PackedInt32Array()
	rows.resize(h)
	for y: int in h:
		rows[y] = _count_row(data, w, y)
	# **先分行带、再在带内分列。** 反过来（先分列）会把上下两排里
	# 横向位置相近的两格并成一列，于是六格切出三格 —— 而每一格里
	# 上下叠着两个人，`get_used_rect` 量出来的「人」有两个头。
	for band: Vector2i in _bands(rows, min_gap, min_cell):
		var cols := PackedInt32Array()
		cols.resize(w)
		for y: int in range(band.x, band.y):
			_add_row(data, w, y, cols)
		for col: Vector2i in _bands(cols, min_gap, min_cell):
			out.append(Rect2i(col.x, band.x, col.y - col.x, band.y - band.x))
	return out


static func _count_row(data: PackedByteArray, w: int, y: int) -> int:
	var count: int = 0
	var base: int = y * w * 4 + 3
	for x: int in w:
		if data[base + x * 4] >= 128:
			count += 1
	return count


static func _add_row(data: PackedByteArray, w: int, y: int, cols: PackedInt32Array) -> void:
	var base: int = y * w * 4 + 3
	for x: int in w:
		if data[base + x * 4] >= 128:
			cols[x] += 1


## 把一条投影切成若干 `[起, 止)` 区间。
##
## 判据是「**离上一个非空位置隔了多远**」，不是「连续空了几格」——
## 两种写法在收尾那一段行为不同：后者会把末尾那条带的结尾算到图的边缘上，
## 于是最后一格比别的格宽出一大截空白。
static func _bands(counts: PackedInt32Array, min_gap: int, min_cell: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start: int = -1
	var last: int = -1
	for i: int in counts.size():
		if counts[i] <= FLOOR:
			continue
		if start < 0:
			start = i
		elif i - last > min_gap:
			if last - start + 1 >= min_cell:
				out.append(Vector2i(start, last + 1))
			start = i
		last = i
	if start >= 0 and last - start + 1 >= min_cell:
		out.append(Vector2i(start, last + 1))
	return out
