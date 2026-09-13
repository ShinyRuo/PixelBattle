class_name PBTelegraphPool
extends Node2D
## 地面技能的落点预示圈（§02）。
##
## 这是施法延迟存在的理由：落点在下达时定死、伤害若干 tick 之后才落地，那段窗口让玩家能预判走位 ——
## 前提是**看得见落点**。
##
## 画成地面上的圆（屏幕上是椭圆，[method PBLayout.ground_disc]）：半径是真圆，画的形状必须和判定的形状一致。
## **越接近落地越亮**：恒定亮度读不出「还有多久」，而那正是预判要的信息。

## 同屏最多几个。出战席 10 人 + 尾兽，全都同时下达也就 11 个。
const CAPACITY: int = 12

## 填充要**很淡**，亮的是那圈边 —— 圆的面积很大，同样的透明度会盖住半个战场，读起来是「屏幕脏了」。
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
		# **每一格都要扫，不只大招那一格**：玩家手放的地面技能在飞的那几 tick 也要有预示圈。
		for i: int in PBSkillRules.cast_count(attacker):
			if _shown >= CAPACITY:
				break
			_add(PBSkillRules.cast_at(attacker, i), current_tick, field, scale)
	queue_redraw()


## 一发待落地的技能，够格就收进池子。**只有地面档有落点预示**：锁定档和不挑目标的
## 也是「一发在路上」，但没有落点，不拦的话会在场外画一个半径 0 的圈、白占一个池子槽位。
func _add(cast: PBSkillCast, current_tick: int, field: Vector2, scale: float) -> void:
	if cast == null or not cast.is_pending() or cast.lands_at <= current_tick:
		return
	if cast.skill.target != PBSkill.Target.GROUND:
		return
	# 还剩多少比例的等待时间。落地那一刻是 1，刚下达时接近 0。
	var total: int = maxi(cast.skill.delay_ticks, 1)
	_centers[_shown] = PBLayout.to_screen(cast.spot, field)
	_radii[_shown] = cast.skill.radius * scale
	_closeness[_shown] = clampf(
		1.0 - float(cast.lands_at - current_tick) / float(total), 0.0, 1.0
	)
	_shown += 1


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


## 直接画（`draw_circle` / `draw_arc`），只在 [method sync_pending] 变了之后 `queue_redraw`。
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
		# 这一处尤其不能画正圆：**它就是「这儿要挨打」那句话本身**，画错形状等于让玩家往安全的地方躲。
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
