@tool
class_name PBPortraitForge
extends RefCounted
## 把一张「N 列 × M 行」的头像表切成一人一张的卡面头像。
##
## **和 [PBActorForge] 是两条流水线**：战场形象要脚底坐底边、朝向统一、帧数对齐、缩放比跨段共用，
## 头像一条都不适用。共用的只有 ffmpeg 滤镜链的形状（抠洋红 → 预乘 → 面积平均缩放），
## 容差不同：那边吃带压缩噪点的视频帧（0.34），这边是干净的 PNG（0.20，同 [PBPixelate]）。
##
## **网格是量出来的，不是算出来的**：出图模型画的格线会飘（同一张表的五行高度能差四分之一），
## 按等分切的话会切进下一行的头发里。所以 [method grid] 去找**整条几乎全黑的行与列**（格线本身）。
##
## **按格子宽度缩**，不按包围盒：各格内容都顶满了自己的格子，按包围盒各缩各的等于没缩；
## 各列宽度几乎一样，模型把脸画在格子正中，「按宽缩」就等于「脸一样大」。高度不够的格子由 [member short] 报出来。

## 抠洋红的容差。**干净 PNG 用 0.20，不是 [PBActorForge] 那边的 0.34** ——
## 那个数是为带压缩噪点的视频帧调的。同 [PBPixelate] 顶上那条：
## 浅粉到洋红只差 0.41，容差往上调就开始啃粉发角色的头发。
const KEY_TOLERANCE: float = 0.20

## 贴图比它在屏幕上占的地方大几倍。和 [constant PBActorForge.HD_FACTOR] 同一个数同一个理由：
## 坐标系恒为 640×360，1080p 是它的 3 倍，所以 26×30 的格子在那儿占 78×90 个真实像素。
const SCALE_UP: int = 3

## 格线的判据：一整条上有超过这个比例的采样点是暗的。
const LINE_SHARE: float = 0.9

## 「暗」的阈值（0~255）。格线是纯黑，人物的深色描边也黑 ——
## 靠的不是这个阈值分得开，是「**整条**都黑」那个条件。
const DARK: int = 51

## 找格线时每条线上取几个采样点。**不逐像素扫全图**（4096² 走 [method Image.get_pixel] 要几分钟），
## 走 [method Image.get_data] 的字节下标再抽样，快三个量级。
const PROBES: int = 64

## 半透明像素归到哪一边。**只切掉抠背景剩下的那圈毛** ——
## 头像恒定是高清档（软边），照 [constant PBActorForge.ALPHA_CUT] 那个硬阈值
## 切的话，边缘会被切成锯齿，而屏幕上那张图只有 26 逻辑像素宽，锯齿很显眼。
const SOFT_CUT: float = 0.08

## 上一趟切图里，哪几格的高度不够铺满画布（底下留了空）。
##
## **必须说出来**：留空的那一截在卡面上是一块透明，而卡面底色是属性色 ——
## 看起来就像「这个人的胸口被属性色吃掉了一块」，而画布、坐标、缩放全都正确。
## 同 [member PBActorForge.clamped]。
var short: PackedStringArray = PackedStringArray()

## 上一趟量出来的网格，`{"cols": [Vector2i(起, 宽)…], "rows": […]}`。
var measured: Dictionary = {}


## 成品贴图多大。**从 [constant PBUnitTile.TILE_SIZE] 推，不写死** ——
## 卡面格子改一次尺寸而这里没跟上的话，头像会在格子里错位一圈，
## 而两个数看起来都很正常。
static func texture_size() -> Vector2i:
	var body: Vector2 = PBUnitTile.TILE_SIZE - Vector2(4.0, 4.0)
	return Vector2i(int(body.x), int(body.y)) * SCALE_UP


## 量出这张表的网格。返回 `{"cols": [Vector2i(起点, 宽度)…], "rows": […]}`，
## 量不出来（比如没有格线）时返回 `{}`。
func grid(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {}
	var flat := image.duplicate() as Image
	flat.convert(Image.FORMAT_RGBA8)
	var data := flat.get_data()
	var w: int = flat.get_width()
	var h: int = flat.get_height()
	var cols := _spans(_lines(data, w, h, true), w)
	var rows := _spans(_lines(data, w, h, false), h)
	if cols.is_empty() or rows.is_empty():
		return {}
	measured = {"cols": cols, "rows": rows}
	return measured


## 切图。[param keys] 按**从左到右、从上到下**排，长度要等于格子数。
## 成品写到 `<out_dir>/<键>.png`。返回空串表示成功，否则是给人看的错误。
func cut(sheet_path: String, keys: PackedStringArray, out_dir: String) -> String:
	short = PackedStringArray()
	var image := Image.load_from_file(sheet_path)
	if image == null:
		return "读不到这张表：%s" % sheet_path
	var found := grid(image)
	if found.is_empty():
		return "量不出网格 —— 这张表上找不到格线（要黑色格线分隔）。"
	var cols: Array = found["cols"]
	var rows: Array = found["rows"]
	var cells: int = cols.size() * rows.size()
	if keys.size() != cells:
		return "量出来是 %d 列 × %d 行 = %d 格，而给了 %d 个键。" % [cols.size(), rows.size(), cells, keys.size()]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var exe := PBActorForge.ffmpeg_path()
	if exe == "":
		return "找不到 ffmpeg。装一个：winget install Gyan.FFmpeg（装完新开一个终端）"
	var at: int = 0
	for row: Vector2i in rows:
		for col: Vector2i in cols:
			var err := _one(exe, sheet_path, col, row, "%s/%s.png" % [out_dir, keys[at]])
			if err != "":
				return err
			at += 1
	return ""


## 给切好的头像全部打开 mipmap。**必须在 `--import` 之后再跑一趟** ——
## `.import` 是引擎导入时生成的，切完那一刻还不存在。
##
## ## 为什么高清档非要它
##
## 这张贴图在 1080p 下是 1:1，但在 720p 下是缩小采样的（0.67 倍）——
## 没有 mipmap 的表现是**卡面在窗口缩放时闪一层摩尔纹**，
## 而静止截图完全看不出来。同 [method PBActorForge._want_mipmaps]，
## 那边守的是「人一走动身上就闪」，是同一条。
func want_mipmaps(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".png.import"):
			continue
		var cfg := ConfigFile.new()
		var path: String = "%s/%s" % [dir_path, file_name]
		if cfg.load(path) != OK:
			continue
		if bool(cfg.get_value("params", "mipmaps/generate", false)):
			continue
		cfg.set_value("params", "mipmaps/generate", true)
		cfg.save(path)


## 一格。ffmpeg 负责裁 + 抠 + 缩，Godot 只在 78×90 这张小画布上收尾。
func _one(exe: String, sheet: String, col: Vector2i, row: Vector2i, to: String) -> String:
	var want := texture_size()
	var log: Array = []
	var code := OS.execute(
		exe,
		[
			"-v",
			"error",
			"-y",
			"-i",
			ProjectSettings.globalize_path(sheet),
			"-vf",
			_filter(col, row, want.x),
			"-frames:v",
			"1",
			ProjectSettings.globalize_path(to)
		],
		log,
		true
	)
	if code != 0:
		return "ffmpeg 切不动第 %s 格（%d）：%s" % [col, code, "\n".join(PackedStringArray(log))]
	var cell := Image.load_from_file(to)
	if cell == null:
		return "切出来这张读不回来：%s" % to
	_trim_fringe(cell)
	var canvas := Image.create_empty(want.x, want.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	var keep: int = mini(cell.get_height(), want.y)
	canvas.blit_rect(cell, Rect2i(0, 0, want.x, keep), Vector2i.ZERO)
	if cell.get_height() < want.y:
		short.append(to.get_file().get_basename())
	return "" if canvas.save_png(to) == OK else "存不下来：%s" % to


## 那条滤镜链。**四段缺一不可**，前三段的理由见 [constant PBActorForge.FILTER]；
## 第四段 `unpremultiply` 是把预乘除回去 —— 那边留在 GDScript 里做，
## 是因为它顺带要按档次切 alpha；这里只有一档，交给 ffmpeg 更省事。
func _filter(col: Vector2i, row: Vector2i, width: int) -> String:
	return (
		(
			"crop=%d:%d:%d:%d,colorkey=0xFF00FF:%.2f:0.0,format=rgba,"
			+ "premultiply=inplace=1,scale=%d:-1:flags=area,unpremultiply=inplace=1"
		)
		% [col.y, row.y, col.x, row.x, KEY_TOLERANCE, width]
	)


## 抠背景剩下的那一圈毛。**只切近乎透明的**，软边照原样留着 ——
## 软边正是高清档买的东西，切硬了等于把缩放换来的那点细节又扔掉。
func _trim_fringe(image: Image) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a < SOFT_CUT:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))


## 一整条上暗到什么程度。返回每一列（或每一行）的暗点占比。
func _lines(data: PackedByteArray, w: int, h: int, by_column: bool) -> Array[Vector2i]:
	var span: int = w if by_column else h
	var other: int = h if by_column else w
	var runs: Array[Vector2i] = []
	var start: int = -1
	for i: int in span:
		var dark: int = 0
		for p: int in PROBES:
			var j: int = int(float(other) * (float(p) + 0.5) / float(PROBES))
			var x: int = i if by_column else j
			var y: int = j if by_column else i
			var at: int = (y * w + x) * 4
			if data[at] < DARK and data[at + 1] < DARK and data[at + 2] < DARK:
				dark += 1
		if float(dark) / float(PROBES) > LINE_SHARE:
			if start < 0:
				start = i
		elif start >= 0:
			runs.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0:
		runs.append(Vector2i(start, span - 1))
	return runs


## 格线之间的空档 —— 也就是格子本身。**外框那两条线不算格子**，
## 所以只取相邻两条线中间那一段；一条线都没有时整条算一格。
func _spans(lines: Array[Vector2i], span: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cursor: int = 0
	for line: Vector2i in lines:
		if line.x > cursor:
			out.append(Vector2i(cursor, line.x - cursor))
		cursor = line.y + 1
	if cursor < span:
		out.append(Vector2i(cursor, span - cursor))
	return out
