class_name PBIconArt
extends RefCounted
## 左侧形象：基地使用五代火影石像与火影大楼图，尾兽仍由代码画像素图。
##
## **画在小画布上再整数倍放大**（[constant SCALE]）：非整数比拉过的像素栅格宽窄不一。
## **一次建好之后只查表**：每张图几百次 `set_pixel`，面板每次点击都会重画。

## 大本营那张的画布边长（像素）。比尾兽大一圈：**它是这一局的命**，
## 玩家的目光第一时间该落在它上面。
const BASE_PX: int = 32

## 尾兽那张的画布边长。
const BEAST_PX: int = 28

## 显示时放大几倍。**只能是整数**，见类顶部。
const SCALE: int = 2

## 石头、暗石、门洞。三档灰足够画出体积，再多一档在 32 见方上看不出来。
const STONE := Color(0.60, 0.64, 0.72, 1.0)
const STONE_DARK := Color(0.38, 0.41, 0.50, 1.0)
const GATE := Color(0.13, 0.14, 0.19, 1.0)

## 描边。和 [constant PBWhiteModel.OUTLINE] 同一个色 ——
## 两处的图会并排出现在同一屏上，描边不一样会显得是两套素材。
const OUTLINE := Color(0.06, 0.06, 0.09, 1.0)

## 九只尾兽各自的颜色，**按尾数取**（一尾在第 0 位）。
##
## 九个色相互不相邻：沙黄 / 蓝 / 水青 / 赤红 / 近白 / 紫 / 碧绿 / 靛蓝 / 橙红。
## 挑色的依据是**能不能在 56 像素见方里一眼分开**，不是好不好看 ——
## 这一格上九只轮换，两只撞色就等于这张图什么都没说。
##
## **一个名字都不写**（§14 铁律 5，`test_beast_data.gd` 逐文件扫）：
## 序号来自 [method PBBeastTable.all] 的顺序，界面只认序号。
const BEAST_COLORS: Array[Color] = [
	Color(0.85, 0.76, 0.50, 1.0),
	Color(0.36, 0.66, 0.86, 1.0),
	Color(0.42, 0.78, 0.76, 1.0),
	Color(0.86, 0.38, 0.30, 1.0),
	Color(0.90, 0.88, 0.84, 1.0),
	Color(0.68, 0.48, 0.82, 1.0),
	Color(0.52, 0.80, 0.46, 1.0),
	Color(0.42, 0.48, 0.80, 1.0),
	Color(0.94, 0.55, 0.24, 1.0),
]

## 还没选尾兽时那张图的颜色。**不是「不画」** —— 空位也得是一张图，
## 否则那一格看起来像没加载出来。
const EMPTY := Color(0.34, 0.37, 0.45, 1.0)

static var _cache: Dictionary = {}


## 大本营透明图；动态旗帜与飞鸟由 [PBBaseMotion] 叠加。
static func base() -> Texture2D:
	return preload("res://assets/base/hokage_hall_5_heads.png")


## 第 [param tails] 尾那只。**0 表示还没选**，画的是一个带问号的剪影。
static func beast(tails: int) -> Texture2D:
	return _cached("beast%d" % tails, func() -> Image: return _draw_beast(tails))


## 显示尺寸（像素）。面板按它摆位，**不要在那边写死数字** ——
## 画布一改，两处就会差几个像素，而那表现为「图有点没对齐」。
static func base_size() -> float:
	return float(BASE_PX * SCALE)


static func beast_size() -> float:
	return float(BEAST_PX * SCALE)


static func _cached(key: String, make: Callable) -> Texture2D:
	if not _cache.has(key):
		var image: Image = make.call()
		_outline(image)
		image.resize(
			image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST
		)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## 一只尾兽：一团身子 + 两只耳朵 + 一排尾巴。
##
## **尾数就是图里那几条尾巴**，颜色按 [constant BEAST_COLORS] 取 ——
## 九只在同一块面板上轮换，光靠颜色分不清（五尾和九尾都偏亮），
## 光靠形状也分不清（都是一团），两样一起才认得出。
static func _draw_beast(tails: int, px: int = BEAST_PX) -> Image:
	var image := _blank(px)
	var tint: Color = EMPTY
	if tails >= 1 and tails <= BEAST_COLORS.size():
		tint = BEAST_COLORS[tails - 1]
	# 尾巴先画：它们在身子后面，后画会盖住轮廓。
	var root := Vector2(14.0, 17.0)
	for i: int in tails:
		# 扇形铺开，**从上方那半圈取角度** —— 往下扫会插进台基里，
		# 而那看起来不像尾巴，像影子漏了一块。
		var span: float = 0.0 if tails <= 1 else float(i) / float(tails - 1) - 0.5
		_ray(image, root, deg_to_rad(-90.0 + span * 150.0), 12.0, tint.darkened(0.25))
	_disc(image, Vector2(14.0, 18.0), 7.0, tint)  # 身子
	for x: int in [8, 17]:  # 两只耳朵
		_rect(image, x, 9, 3, 4, tint)
		_rect(image, x + 1, 8, 2, 1, tint)
	_rect(image, 11, 20, 6, 3, tint.darkened(0.3))  # 口鼻
	for x: int in [11, 16]:  # 眼睛
		_rect(image, x, 16, 2, 2, GATE)
	if tails <= 0:
		_question(image)
	return image


## 空位那张图上的问号，**画在身子上**（形状先对上「这一格将来是尾兽」）。笔画 2 像素宽，1 像素在灰底上看不见。
static func _question(image: Image) -> void:
	for spot: Vector2i in [
		Vector2i(11, 12),
		Vector2i(13, 12),
		Vector2i(15, 13),
		Vector2i(15, 15),
		Vector2i(13, 16),
		Vector2i(13, 18),
	]:
		_rect(image, spot.x, spot.y, 2, 2, PBSkin.TITLE)


static func _blank(side: int) -> Image:
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	return image


static func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for row: int in height:
		for column: int in width:
			_put(image, x + column, y + row, color)


static func _disc(image: Image, at: Vector2, radius: float, color: Color) -> void:
	var span: int = int(ceilf(radius))
	for row: int in range(-span, span + 1):
		for column: int in range(-span, span + 1):
			if Vector2(float(column), float(row)).length() <= radius:
				_put(image, int(at.x) + column, int(at.y) + row, color)


## 从 [param from] 朝 [param angle] 画一条 [param length] 长的线。
## 步长取 0.5 像素：取 1 的话斜线会断成一串点。
static func _ray(image: Image, from: Vector2, angle: float, length: float, color: Color) -> void:
	var step := Vector2(cos(angle), sin(angle))
	var walked: float = 0.0
	while walked <= length:
		var at: Vector2 = from + step * walked
		_put(image, int(round(at.x)), int(round(at.y)), color)
		walked += 0.5


static func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, color)


## 沿剪影外沿描一圈深色。**先收集再写** —— 边描边写的话，
## 刚描上的那一圈会被当成实体，一趟扫下来描出三四层
## （和 [method PBWhiteModel._outline] 是同一个坑）。
static func _outline(image: Image) -> void:
	var edge: Array[Vector2i] = []
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				continue
			if _touches_body(image, x, y):
				edge.append(Vector2i(x, y))
	for at: Vector2i in edge:
		image.set_pixel(at.x, at.y, OUTLINE)


static func _touches_body(image: Image, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at := Vector2i(x + step.x, y + step.y)
		if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
			continue
		if image.get_pixel(at.x, at.y).a > 0.0:
			return true
	return false
