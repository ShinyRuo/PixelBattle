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

## 补刀时，切点离这一格两端至少留出多少（占格宽的比例）。
##
## **不留的话第一刀会削掉一条腿**：贴着的两只之间那道谷是全局最小，
## 但一只野兽的**外侧轮廓**（尾巴尖、抬起来的前腿）投影同样很低，
## 而它离边缘很近。留出两成之后，剩下的最小值必定落在两只之间。
const SPLIT_MARGIN: float = 0.2

## 补刀时，谷底要浅到什么程度才认。**判据是「和这一格的平均高度比」**，
## 不是一个绝对值 —— 图有多大、生物有多高都在变，绝对值调不准。
##
## 两只贴着时那一列上只有尾巴和腿（实测远低于三成），
## 而**一整只野兽**的中间再瘦也瘦不到平均的三成 —— 那正是要挡住的：
## 切不开的时候宁可少切一格让人重出，也不能把一只从腰上劈开，
## 因为劈开之后每一格看起来仍然「像一帧」，只有数一数才发现不对。
const SPLIT_VALLEY: float = 0.3


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
##
## ## [param want]：知道该有几格的话，切不够就补刀（M9-h）
##
## 空白带这条判据要求**一整列一个前景像素都没有**。而模型画宽的生物时
## （犀牛、蛇这种横向很长的四足兽，一行还塞三只）经常让相邻两只**贴上甚至
## 交错** —— 那样的一列根本不存在，于是一整行并成一格。
## 面板上那个「至少空多少」滑块**在这一档救不了场**：它能做的只是让更窄的
## 缝也算缝，而这里的缝是 0。
##
## 所以 [param want] > 0 时多一层兜底：**取最宽的那一格，在它的列投影上
## 找最深的谷切一刀**，重复到够数。谷不为零，但它仍然是那一段的最小值。
##
## **它只在空白带切不够时才接管** —— 切得开的图一个像素都不会变。
## 补不满也照旧返回（调用方去数），见 [constant SPLIT_VALLEY]：
## 宁可少一格让人重出，也不能把一只从腰上劈开。
static func cut(
	image: Image, min_gap: int = DEFAULT_GAP, min_cell: int = DEFAULT_CELL, want: int = 0
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
	while want > out.size() and _split_widest(data, w, out, min_cell):
		pass
	return out


## 挑最宽的那一格切一刀，**从宽到窄依次试，切开一格就收手**。
## 切不动任何一格时返回 `false`，调用方据此收工。
##
## 切开的两半**各自重新收紧**（去掉内侧的空列）—— 不收紧的话那道谷里
## 剩下的空白会算进包围盒，而下游全靠 [method Image.get_used_rect] 量人。
static func _split_widest(
	data: PackedByteArray, w: int, cells: Array[Rect2i], min_cell: int
) -> bool:
	var order: Array[int] = []
	for i: int in cells.size():
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool: return cells[a].size.x > cells[b].size.x
	)
	for i: int in order:
		var cell: Rect2i = cells[i]
		if cell.size.x < min_cell * 2:
			continue
		var cols := _columns(data, w, cell)
		var at: int = _valley(cols, min_cell)
		if at < 0:
			continue
		var left := _slice(cols, cell, 0, at)
		var right := _slice(cols, cell, at, cell.size.x)
		if left.size.x < min_cell or right.size.x < min_cell:
			continue
		cells[i] = left
		cells.insert(i + 1, right)
		return true
	return false


## 这一格的列投影（下标 0 对齐格子的左沿）。
static func _columns(data: PackedByteArray, w: int, cell: Rect2i) -> PackedInt32Array:
	var cols := PackedInt32Array()
	cols.resize(cell.size.x)
	for y: int in range(cell.position.y, cell.end.y):
		var base: int = y * w * 4 + 3
		for x: int in cell.size.x:
			if data[base + (cell.position.x + x) * 4] >= 128:
				cols[x] += 1
	return cols


## 最深的那道谷在哪一列（格内下标），没有够浅的谷就返回 −1。
##
## **取谷底最宽的那一段的中点**，不是第一个最小值：两只贴着时那道谷常常
## 是好几列一样浅的一条，取第一列会把切点顶到左边那只的尾巴上。
static func _valley(cols: PackedInt32Array, min_cell: int) -> int:
	var span: int = cols.size()
	var margin: int = maxi(min_cell, int(round(float(span) * SPLIT_MARGIN)))
	if span - margin * 2 < 1:
		return -1
	var total: int = 0
	for count: int in cols:
		total += count
	var mean: float = float(total) / float(span)
	if mean <= 0.0:
		return -1
	var low: int = -1
	for x: int in range(margin, span - margin):
		if low < 0 or cols[x] < low:
			low = cols[x]
	if low < 0 or float(low) > mean * SPLIT_VALLEY:
		return -1
	var best_from: int = -1
	var best_len: int = 0
	var from: int = -1
	for x: int in range(margin, span - margin):
		if cols[x] != low:
			from = -1
			continue
		if from < 0:
			from = x
		if x - from + 1 > best_len:
			best_len = x - from + 1
			best_from = from
	return best_from + best_len / 2


## 取 [param cols] 上 `[from, to)` 那一段，**收紧到真有像素的地方**，
## 换成一个绝对矩形。[param cols] 的下标对齐 [param cell] 的左沿。
##
## 不收紧的话，那道谷里剩下的空白会算进包围盒，
## 而下游全靠 [method Image.get_used_rect] 量人。
static func _slice(cols: PackedInt32Array, cell: Rect2i, from: int, to: int) -> Rect2i:
	var lo: int = from
	while lo < to and cols[lo] <= FLOOR:
		lo += 1
	var hi: int = to
	while hi > lo and cols[hi - 1] <= FLOOR:
		hi -= 1
	return Rect2i(cell.position.x + lo, cell.position.y, hi - lo, cell.size.y)


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
