class_name PBAllyPool
extends Node2D
## 战场上的己方忍者。§02 第 8 点，M3.5-g。
##
## ## 在它之前，战场上只有敌人
##
## M0 到 M3 的战斗是「整队一个标量 DPS」，**「谁站在哪」根本没有答案**，
## 所以画面上画不出自己人是诚实的。M3-a 把标量拆成一组 [PBAttacker]、
## M3.5 又给了他们血量和跑动之后，那个答案有了 —— 但一直没有出口，
## 于是开打之后玩家看到的还是一条只有敌人在走的空道。
##
## 那不只是难看：**射程、站位、防挤、敌人还手这四件事全部不可见**，
## 而它们正是 M3-a 到 M3.5-c 做的全部内容。看不见的系统等于不存在。
##
## ## 己方和敌人必须一眼分得开
##
## 敌人是**多边形**（每系一个剪影，§02 的第二层视觉编码）。
## 己方因此一律画成**方块 + 头顶一条血条**：形状类别不同，
## 去色之后照样分得开，而属性色两边共用同一套（[constant
## PBEnemyPool.ELEMENT_COLORS]）—— 玩家在编队页认的那个颜色就是这个。
##
## 血条**只有己方有**。敌人的血量已经编码进颜色明暗（越暗越残），
## 而己方只有十来个、一个死了就少一份输出，那件事值得一个精确的读数。
##
## ## 尾兽不画
##
## 尾兽是一个 `dps = 0` 的攻击者（[constant PBBeastRules.BEAST_SLOT]），
## 它没有本体、不挨打、位置恒为 0。画出来会是一个贴在基地上永远满血的方块，
## 而玩家会以为那是个忍者。

## 己方方块的边长（像素）。比敌人的多边形（半径 5）略大一点 ——
## 十来个己方 vs 最多 48 个敌人，大一点才不会在潮水波里被淹掉。
const BODY: Vector2 = Vector2(11.0, 11.0)

## 血条尺寸与它离方块顶多远。
const BAR: Vector2 = Vector2(13.0, 2.0)
const BAR_LIFT: float = 9.0

## 阵亡之后画成什么样。**不藏起来** —— 藏了的话「他死了」和「他从来没上场」
## 在画面上是同一件事，而这一波剩下的时间里玩家正需要知道前排缺了一个。
const DEAD_COLOR := Color(0.22, 0.22, 0.26, 0.75)

const HP_GOOD := Color(0.44, 0.82, 0.55)
const HP_LOW := Color(0.90, 0.42, 0.42)
const BAR_BACK := Color(0.10, 0.11, 0.14, 0.85)

## 选中那个忍者的射程圈（§02 的战斗中操作，M4-e）。
##
## ## 为什么画在这里，而不是再开一个池子
##
## 它是**某一个己方单位**的属性，和血条一样跟着那个人走。
## 单开一个节点的话，「圈的位置」和「方块的位置」会各算一遍，
## 而差几个像素的表现是「射程圈好像没对准他」。
##
## 圈画在自己的 `_draw` 里 —— [CanvasItem] 先画自己再画子节点，
## 所以它自然落在方块和血条**底下**，不会盖住谁。
const RANGE_FILL := Color(0.55, 0.78, 0.95, 0.06)
const RANGE_EDGE := Color(0.62, 0.84, 0.98, 0.55)
const RANGE_SEGMENTS: int = 32

var _bodies: Array[ColorRect] = []
var _backs: Array[ColorRect] = []
var _fills: Array[ColorRect] = []

## 射程圈的屏幕圆心与半径。半径 0 = 不画。
var _range_at: Vector2 = Vector2.ZERO
var _range_px: float = 0.0


func _ready() -> void:
	# 按出战席上限一次建满，之后只改属性和 visible —— 和敌人池同一条规矩（§14）。
	var cfg := PBSimConfig.new()
	for _i: int in cfg.deploy_slots_max:
		_bodies.append(_add_rect(BODY, Color.WHITE))
	for _i: int in cfg.deploy_slots_max:
		_backs.append(_add_rect(BAR, BAR_BACK))
		_fills.append(_add_rect(BAR, HP_GOOD))


## 把池子同步到这一波的攻击者上。每渲染帧调一次。
##
## [param units] 是与攻击者同序的上场名单（[member PBWavePlan.deployed]），
## 只用来取属性色 —— [PBAttacker] 身上没有「攻元素」，那一份克制倍率
## 在建攻击者时就乘进 `dps` 了（§14 铁律 4：element 挂在伤害事件上）。
##
## **位置直接读 [member PBAttacker.pos]**（M4-a）。在那之前 y 是这里
## 按显示序号现编的 —— sim 是一维的，纵向没有答案可读。
func sync_allies(attackers: Array[PBAttacker], units: Array[PBUnit], field: Vector2) -> void:
	var shown: int = 0
	for attacker: PBAttacker in attackers:
		if shown >= _bodies.size():
			break
		# 尾兽那一个不画，见类顶部。
		if attacker.slot < 0 or attacker.max_hp <= 0.0:
			continue
		var at := PBEnemyPool.to_screen(attacker.pos, field)
		var unit: PBUnit = units[attacker.slot] if attacker.slot < units.size() else null
		_place(shown, at, attacker, unit)
		shown += 1
	for i: int in range(shown, _bodies.size()):
		_bodies[i].visible = false
		_backs[i].visible = false
		_fills[i].visible = false


## 准备阶段把上场名单画在他们的开战位置上（§02，M4-f）。
##
## ## 为什么准备阶段也要画
##
## 在它之前准备阶段的战场是**空的**，上场名单只在屏幕上方那一排头像里 ——
## 于是「谁站前排」这件事只能从射程档反推。摆位要成为一个操作，
## 第一步是让玩家看见现在摆成什么样。
##
## 不画血条：还没开打，那条永远是满的，而一条恒满的血条只是噪声。
func sync_placed(units: Array[PBUnit], spots: Array[Vector2], field: Vector2) -> void:
	for i: int in _bodies.size():
		var shown: bool = i < units.size() and i < spots.size()
		_bodies[i].visible = shown
		_backs[i].visible = false
		_fills[i].visible = false
		if not shown:
			continue
		_bodies[i].position = PBEnemyPool.to_screen(spots[i], field) - BODY * 0.5
		_bodies[i].color = PBEnemyPool.ELEMENT_COLORS.get(units[i].element, Color.WHITE)


## 一个都不画（本局结束之后没有战场）。
func clear() -> void:
	for i: int in _bodies.size():
		_bodies[i].visible = false
		_backs[i].visible = false
		_fills[i].visible = false
	show_range(Vector2.ZERO, 0.0)


## 把射程圈画在 [param at]（屏幕坐标），半径 [param radius_px] 像素。
## 半径给 0 就是收起来。
func show_range(at: Vector2, radius_px: float) -> void:
	if _range_at == at and is_equal_approx(_range_px, radius_px):
		return
	_range_at = at
	_range_px = radius_px
	queue_redraw()


func _draw() -> void:
	if _range_px <= 0.0:
		return
	draw_circle(_range_at, _range_px, RANGE_FILL)
	draw_arc(_range_at, _range_px, 0.0, TAU, RANGE_SEGMENTS, RANGE_EDGE, 1.0)


func _place(index: int, at: Vector2, attacker: PBAttacker, unit: PBUnit) -> void:
	var body: ColorRect = _bodies[index]
	body.visible = true
	body.position = at - BODY * 0.5
	var ratio: float = clampf(attacker.hp / attacker.max_hp, 0.0, 1.0)
	if not attacker.alive:
		body.color = DEAD_COLOR
	elif unit == null:
		body.color = Color.WHITE
	else:
		body.color = PBEnemyPool.ELEMENT_COLORS.get(unit.element, Color.WHITE)

	# 死了不画血条 —— 一条空血条和一条读不出来的血条长得一样，
	# 而方块已经变灰了，那一格信息不需要说两遍。
	_backs[index].visible = attacker.alive
	_fills[index].visible = attacker.alive
	if not attacker.alive:
		return
	var bar_at := at - Vector2(BAR.x * 0.5, BAR_LIFT)
	_backs[index].position = bar_at
	_fills[index].position = bar_at
	_fills[index].size = Vector2(BAR.x * ratio, BAR.y)
	_fills[index].color = HP_LOW if ratio < 0.35 else HP_GOOD


func _add_rect(of_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = of_size
	rect.color = color
	rect.visible = false
	add_child(rect)
	return rect
