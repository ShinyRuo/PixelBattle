class_name PBTelegraphPool
extends Node2D
## 大招的落点预示。§02 / M3-b 的施法延迟，M3.5-h；M4-a 从竖带改回圆。
##
## ## 这是施法延迟存在的理由
##
## M3-b 给大招加了 `delay_ticks`：落点在下达时定死，伤害在若干 tick 之后
## 才落地（[PBSkill] 顶部）。那段窗口的**全部意义**是让玩家能预判走位 ——
## 而预判的前提是他**看得见落点**。在这之前那个窗口只存在于数据里，
## 玩家能观测到的只有「伤害有时候延迟一下才出现」。
##
## ## 为什么先画成带子、现在又改回圆
##
## M3.5-h 画的是一条**竖带**，理由写得很硬：
## [member PBSkill.radius] 那时只作用在推进轴上，纵向散布是渲染层
## 为了不让 48 个敌人挤成一条线才编的，一点都不算数 ——
## 画成圆会让玩家去躲一个根本不存在的纵向判定，那比不画更糟。
##
## **M4-a 把纵向搬进了 sim**（[member PBEnemy.lane]），那条理由随之反转：
## 半径现在是真圆，带子才是谎话。它会让玩家以为整条道都会挨到，
## 于是根本不去躲 —— 而躲得开。
##
## 圆是**真圆**，不是椭圆：两轴共用同一个像素比例
## （[method PBLayout.px_per_unit]）。不共用的话画出来的形状
## 和判定的形状不是一回事，而那正是这一整块要兑现的东西。
##
## ## 越接近落地越亮
##
## 一个恒定亮度的圈读不出「还有多久」，而那正是预判要的那一格信息。

## 同屏最多几个。出战席 10 人 + 尾兽，全都同时下达也就 11 个。
const CAPACITY: int = 12

## 填充要**很淡**，亮的是那圈边。
##
## 带子那一版填充可以浓一点：它只有 2×radius 宽，压着战场一小条。
## 圆的面积是那条带子的好几倍（半径 0.12 换算过来是 134 像素直径），
## 同样的透明度画出来是一大块盖住半个战场的色块 —— 玩家看到的不是
## 「这儿要挨打」，而是「屏幕脏了」。
const FILL := Color(0.98, 0.72, 0.32, 0.05)
const EDGE := Color(0.98, 0.85, 0.45, 0.75)

## 越接近落地，填充和边各自还能再浓多少。
const FILL_RAMP: float = 0.10
const EDGE_RAMP: float = 0.6

## 圈的边线宽度（像素）。
const EDGE_WIDTH: float = 1.0

## 圆画成多少段。24 段在 `640×360` 下已经看不出是多边形，
## 而段数直接乘上 12 个圈进每帧的顶点数。
const SEGMENTS: int = 24

## 两个落点差多少像素之内算同一个（见 [method _draw]）。
const MERGE_PX: float = 3.0

## 屏幕坐标下的圆心、半径、以及「还有多久落地」（0 = 刚下达，1 = 就要落地）。
##
## 用三条平行的定长数组而不是一个 Dictionary 数组：这一份每渲染帧重填一次，
## 每帧造 12 个 Dictionary 就是每秒 720 次分配（§14 对热路径的要求）。
var _centers: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _closeness: PackedFloat32Array = PackedFloat32Array()
var _shown: int = 0


func _ready() -> void:
	_centers.resize(CAPACITY)
	_radii.resize(CAPACITY)
	_closeness.resize(CAPACITY)


## 把待落地的大招画出来。[param attackers] 直接来自
## [method PBBattleSim.attackers]，**只读**。
## [param field] 是 `Vector2(field_length, field_height)`。
func sync_pending(attackers: Array[PBAttacker], current_tick: int, field: Vector2) -> void:
	var scale: float = PBLayout.px_per_unit(field)
	_shown = 0
	for attacker: PBAttacker in attackers:
		if _shown >= CAPACITY:
			break
		var cast: PBSkillCast = attacker.ultimate
		# 没有落点 = 现在没有待落地的大招（[constant PBSkillCast.NO_SPOT]）。
		if cast == null or not cast.is_pending() or cast.lands_at <= current_tick:
			continue
		# 还剩多少比例的等待时间。落地那一刻是 1，刚下达时接近 0。
		var total: int = maxi(cast.skill.delay_ticks, 1)
		_centers[_shown] = PBLayout.to_screen(cast.spot, field)
		_radii[_shown] = cast.skill.radius * scale
		_closeness[_shown] = clampf(
			1.0 - float(cast.lands_at - current_tick) / float(total), 0.0, 1.0
		)
		_shown += 1
	queue_redraw()


func clear() -> void:
	_shown = 0
	queue_redraw()


## 现在画着几个圈。测试拿它确认「在空中时画、落地就收」。
func shown() -> int:
	return _shown


## 第 [param index] 个圈的屏幕圆心。
func center_of(index: int) -> Vector2:
	return _centers[index] if index >= 0 and index < _shown else Vector2.ZERO


## 第 [param index] 个圈的屏幕半径（像素）。
func radius_of(index: int) -> float:
	return _radii[index] if index >= 0 and index < _shown else 0.0


## 直接画，不再养一池 `ColorRect`。
##
## 带子那一版是两条竖边加一块填充，三个矩形拼得出来；圆拼不出来。
## `draw_circle` / `draw_arc` 每帧重画，而这个节点本来就只在
## [method sync_pending] 变了之后 `queue_redraw`。
func _draw() -> void:
	for i: int in _shown:
		# **重合的圈只画一次。**
		#
		# 全队的大招都瞄同一处最密的敌群（[method PBAimRules.pick_spot]），
		# 所以十来个落点几乎精确重叠。各画各的话透明度会叠加 ——
		# 0.05 叠十二层就是一块不透明的色块，玩家看到的不是「这儿要挨打」
		# 而是「屏幕脏了」。**淡到什么程度都救不了**，因为脏的是层数不是浓度。
		#
		# 去重放在画的这一步，不放在 [method sync_pending]：
		# `shown()` 报的是**待落地的大招有几发**，那是它的含义，不该被画法改掉。
		if _merged_into_earlier(i):
			continue
		var near: float = _closeness[i]
		# 战场上的圆在屏幕上是椭圆（M6-a），见 [method PBLayout.ground_disc]。
		# 这一处尤其不能自己画正圆：**它就是「这儿要挨打」那句话本身**，
		# 画错形状等于让玩家往一个安全的地方躲。
		var ring := PBLayout.ground_disc(_centers[i], _radii[i], SEGMENTS)
		draw_colored_polygon(ring, Color(FILL.r, FILL.g, FILL.b, FILL.a + near * FILL_RAMP))
		draw_polyline(
			ring, Color(EDGE.r, EDGE.g, EDGE.b, 0.35 + near * EDGE_RAMP), EDGE_WIDTH
		)


## 前面有没有一个圈和第 [param index] 个几乎重合。
##
## 比圆心也比半径：同一个落点上一个大圈套一个小圈是两条真信息
## （罩得住的范围不一样），不该被并掉。
func _merged_into_earlier(index: int) -> bool:
	for j: int in index:
		if (
			_centers[j].distance_to(_centers[index]) <= MERGE_PX
			and absf(_radii[j] - _radii[index]) <= MERGE_PX
		):
			return true
	return false
