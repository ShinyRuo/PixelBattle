class_name PBAimLines
extends Node2D
## 「他要打谁」「我正在指谁」这两件事画出来（§02，M5-11）。三条虚线。
##
## ## 为什么非画不可
##
## M4-e 给了战斗中点选与点名，M5-9 又加了手动忍术。**这两条指令在屏幕上
## 一个反馈都没有** —— 按了「攻击」之后玩家看不出自己进没进指定状态，
## 点完一个敌人也看不出那个忍者到底改打他了没有。
## 唯一的线索是指令卡上那格按钮换了个字，而它在屏幕的另一头。
##
## 暂停时更是如此：§02 特意允许暂停下操作，而暂停画面上
## **一切都不动**，「谁在打谁」于是完全不可读。
##
## ## 三条线各是一句话
##
## | 线 | 从哪到哪 | 说的是 |
## |---|---|---|
## | A | 忍者 → 他这一刻的攻击目标 | 「他要打这个」 |
## | B | 选中的忍者 → 鼠标 | 「正在等你点一个敌人」 |
## | C | 选中的忍者 → 鼠标，鼠标处加一个范围圈 | 「正在等你点忍术落点」 |
##
## **B / C 与 A 不同色**：A 是既成事实，B / C 是一个还没落地的意图。
## 同色的话玩家分不清「已经改好了」和「还没点」——
## 而那正是两步操作唯一需要表达的东西。
##
## C 那个圈画在**鼠标**上而不是忍者身上：忍术打的是一块地，
## 玩家要挑的是那块地落在哪，圈跟着手走他才看得出自己会罩住几个。
##
## ## A 画一条还是画全部，看暂停没暂停（M5-12）
##
## 跑起来的时候画全部就是一屏乱线 —— 十条线每帧都在扫，谁也读不出信息。
## 但**暂停正是用来读局面的那一刻**（§02 允许暂停下操作），
## 那时「哪几个人在打同一个目标、谁在空放」一眼就得看出来，
## 而只画选中那一条的话，玩家得挨个点过去。

## A：他要打谁。绿 —— 和血条同一套「这是好事」的语义。
const LINE_TARGET := Color(0.443, 0.816, 0.549, 0.85)

## B：正在等你点敌人。红 —— 和敌人子弹同色系，说的是「这一下是攻击」。
const LINE_PICK := Color(0.898, 0.420, 0.420, 0.9)

## C：正在等你点忍术落点。橙 —— 和落点预示圈（[PBTelegraphPool]）同色系。
const LINE_CAST := Color(0.98, 0.72, 0.32, 0.9)

## 忍术范围圈的填充与描边。填充要很淡，理由同 [PBTelegraphPool]：
## 半径换算过来上百像素，浓一点就是一块盖住半个战场的色块。
const CAST_FILL := Color(0.98, 0.72, 0.32, 0.06)
const CAST_EDGE := Color(0.98, 0.72, 0.32, 0.55)

## 虚线的一段有多长（像素）。4 是在 640×360 上还看得出是虚线的下限 ——
## 再短就糊成实线，再长就断得像两条线。
const DASH: float = 4.0

const WIDTH: float = 1.0

## 圆画多少段。和 [PBTelegraphPool] 同一个数，好让两个圈看起来是一套。
const SEGMENTS: int = 48

## 全部 A 线的端点，**两个一对**（起点、终点）。空数组表示一条都不画。
##
## 存成一个扁平数组而不是「一个忍者一条线」的结构：这一层只管画，
## 一条线是谁的、为什么画，答案全在 [member PBAttacker.aim_at] 里，
## 在这儿再存一份身份只会多一处对不上的地方。
var _links: PackedVector2Array = PackedVector2Array()

## B / C 的起点（选中那个忍者）。[constant Vector2.ZERO] 表示没有 B / C。
var _from: Vector2 = Vector2.ZERO

## B / C 的终点（鼠标）。
var _cursor: Vector2 = Vector2.ZERO

## 现在在等什么（[enum PBFieldPicker.Aim]）。
var _mode: int = PBFieldPicker.Aim.OFF

## 忍术范围圈的半径（像素）。0 表示不画。
var _cast_px: float = 0.0


## 把三条线摆好。每渲染帧调一次。
##
## [param live] 是选中的那个忍者，可以是 null（没选中人时只有 A 线）。
## [param everyone] 为真时 A 线画全场，否则只画 [param live] 那一条 ——
## 判据是「暂停了没有」，理由见类顶部。
func sync(
	battle: PBBattleSim,
	field: Vector2,
	live: PBAttacker,
	mode: int,
	cursor: Vector2,
	everyone: bool
) -> void:
	var links := PackedVector2Array()
	if everyone:
		for attacker: PBAttacker in battle.attackers():
			_link(links, attacker, battle, field)
	elif live != null:
		_link(links, live, battle, field)
	var from := Vector2.ZERO
	var cast_px: float = 0.0
	if live != null and mode != PBFieldPicker.Aim.OFF:
		from = PBLayout.to_screen(live.pos, field)
		if mode == PBFieldPicker.Aim.ULTIMATE and live.ultimate != null:
			# 半径读大招自己的，不读配置：羁绊功能档会放大它
			# （[member PBSimConfig.bond_pull_radius_scale]），而圈画小了
			# 等于告诉玩家一件错的事。
			cast_px = live.ultimate.radius * PBLayout.px_per_unit(field)
	_apply(links, from, cursor, mode, cast_px)


## 一个忍者的 A 线，有目标才收进 [param out]（两个点一对）。
##
## ## 终点从 [member PBAttacker.aim_at] 读，不在这儿重算
##
## 点名、射程、出场时刻、死活四个条件里漏抄一个，画出来的线就指着
## 一个他其实没在打的敌人，**而且不报错**。
##
## 那个下标仍然要**再验一次死活**：sim 是每 tick 算的，而画面每渲染帧都画，
## 两者之间隔着倍速与暂停。画一根指着尸体的线比不画更糟 ——
## 玩家会以为这个忍者卡住了。
static func _link(
	out: PackedVector2Array, attacker: PBAttacker, battle: PBBattleSim, field: Vector2
) -> void:
	if not attacker.is_targetable() or attacker.aim_at < 0:
		return
	if attacker.aim_at >= battle.enemies().size():
		return
	var enemy: PBEnemy = battle.enemies()[attacker.aim_at]
	if not enemy.is_active(battle.current_tick()):
		return
	out.append(PBLayout.to_screen(attacker.pos, field))
	out.append(PBLayout.to_screen(enemy.pos(), field))


## 存下这一帧的五个量，变了才重画。
##
## **暂停时这道门是全部的意义**：画面一动不动，五个量一个都没变，
## 于是十几条线一帧都不用重绘。
func _apply(
	links: PackedVector2Array, from: Vector2, cursor: Vector2, mode: int, cast_px: float
) -> void:
	if (
		_links == links
		and _from == from
		and _cursor == cursor
		and _mode == mode
		and is_equal_approx(_cast_px, cast_px)
	):
		return
	_links = links
	_from = from
	_cursor = cursor
	_mode = mode
	_cast_px = cast_px
	queue_redraw()


## 一条都不画（准备阶段、本局结束）。
func clear() -> void:
	_apply(PackedVector2Array(), Vector2.ZERO, Vector2.ZERO, PBFieldPicker.Aim.OFF, 0.0)


func _draw() -> void:
	for i: int in range(0, _links.size() - 1, 2):
		draw_dashed_line(_links[i], _links[i + 1], LINE_TARGET, WIDTH, DASH)
	if _from == Vector2.ZERO:
		return
	if _mode == PBFieldPicker.Aim.TARGET:
		draw_dashed_line(_from, _cursor, LINE_PICK, WIDTH, DASH)
	elif _mode == PBFieldPicker.Aim.ULTIMATE:
		draw_dashed_line(_from, _cursor, LINE_CAST, WIDTH, DASH)
		if _cast_px > 0.0:
			# 战场上的圆在屏幕上是椭圆（M6-a），见 [method PBLayout.ground_disc]。
			var ring := PBLayout.ground_disc(_cursor, _cast_px, SEGMENTS)
			draw_colored_polygon(ring, CAST_FILL)
			draw_polyline(ring, CAST_EDGE, WIDTH)
