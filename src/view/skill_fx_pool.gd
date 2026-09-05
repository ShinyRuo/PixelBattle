class_name PBSkillFxPool
extends Node2D
## 施法瞬间从施法者脚下扩散出去的一圈环（技能案 §4.5，M7-f）。
##
## ## 它补的是哪一格反馈
##
## 落点预示圈（[PBTelegraphPool]）说的是「**那儿**要挨打」，
## 命中白闪（[PBHitFeedback]）说的是「他刚挨了一下」——
## 中间缺的是「**这个人刚刚放了一个技能**」。
##
## 缺了它，一个锁定档的治疗在屏幕上**什么都不会发生**：没有落点圈
## （M7-c 那个 bug 修掉的正是「给它画一个场外的圈」），
## 目标身上只是血条悄悄涨了一截。玩家点下去看不到回音。
##
## ## 和 [PBTelegraphPool] 同构，但方向相反
##
## 那一个是**越接近落地越亮**（还有多久要挨打）；
## 这一个是**越扩散越淡**（刚才发生过什么）。前者是预告，后者是回音 ——
## 一个朝未来、一个朝过去，所以两者的透明度曲线必须反着走，
## 否则同屏两种圈会读成同一句话。
##
## ## 它不参与任何判定
##
## §4.5 那条：特效一律不进 sim。这一层连 [PBBattleSim] 都不认识 ——
## 它只收「谁、在哪、什么颜色」，由 [PBBattleView] 在下达那一刻喂进来。

## 同屏最多几个。出战席 10 人 + 尾兽，全都同一 tick 下达也就 11 个。
const CAPACITY: int = 12

## 一圈从冒出来到消失多少个渲染帧。**短** —— 它是一次「刚才」的回音，
## 拖长了会和落点预示圈在屏幕上同时存在，而那两句话不该叠在一起。
const LIFE_FRAMES: int = 18

## 起始与终止半径（像素）。从人脚下往外推。
const FROM_PX: float = 4.0
const TO_PX: float = 26.0

## 打人的那一档暖、给自己人的那一档青 —— 和 [PBAimLines] 的 B/D 两色同源，
## 「点谁」和「放出去之后」因此是同一套配色。
const HOSTILE := Color(0.98, 0.72, 0.32, 0.9)
const FRIENDLY := Color(0.42, 0.85, 0.90, 0.9)

const SEGMENTS: int = 24
const WIDTH: float = 1.0

## 三条平行的定长数组：圆心、还剩几帧、什么颜色。
##
## 和 [PBTelegraphPool] 同一条理由（§14 对热路径的要求）——
## 每帧造一批 Dictionary 就是每秒几百次分配。
var _at: PackedVector2Array = PackedVector2Array()
var _left: PackedInt32Array = PackedInt32Array()
var _warm: Array[bool] = []
var _live: int = 0

## 播报已经消化到第几条。**存下标不存 tick**：日志是环形的、会丢最老的
## 那几条，而下标只需要「从这儿往后是新的」这一个语义。
var _echoed: int = 0


func _ready() -> void:
	_at.resize(CAPACITY)
	_left.resize(CAPACITY)
	_warm.resize(CAPACITY)


## 有人在 [param at]（屏幕坐标）放了一个技能。[param friendly] 为真时用青色。
##
## **池子满了就丢掉这一个**，不扩池：扩池会在热路径上分配（§14），
## 而丢掉一个特效的代价只是「同一瞬间的第 13 个人没有回音」——
## 而那一瞬间屏幕上已经有 12 个圈了。
func flash(at: Vector2, friendly: bool) -> void:
	if _live >= CAPACITY:
		return
	_at[_live] = at
	_left[_live] = LIFE_FRAMES
	_warm[_live] = not friendly
	_live += 1
	queue_redraw()


## 走一个渲染帧。**每帧调一次**，和顿帧、倍速无关 ——
## 它是纯表现，不该跟着 tick 走（跟着走的话暂停时它会冻在半路上，
## 而玩家暂停正是为了看清刚才发生了什么）。
func step() -> void:
	if _live <= 0:
		return
	var kept: int = 0
	for i: int in _live:
		if _left[i] <= 1:
			continue
		_at[kept] = _at[i]
		_left[kept] = _left[i] - 1
		_warm[kept] = _warm[i]
		kept += 1
	_live = kept
	queue_redraw()


## 走一帧，并把播报里**新出现**的那几条施法变成圈。
## [param attackers] 直接来自 [method PBBattleSim.attackers]，**只读**。
##
## 消化到第几条由本类自己记（[member _echoed]）—— 那是这个池子的账，
## 放到调用方去存就多一处能对不上的地方。
##
## ## 触发读的是播报，不是「谁身上有一发在飞」
##
## 后者对不挑目标的那一档**结构上就看不见**：它没有施法延迟，
## 下达和落地在同一 tick，渲染层永远抓不到那个中间状态 ——
## 而那正是最需要回音的一档（它连落点预示圈都没有）。
##
## 播报记的恰恰是**下达**那一刻（M6-j 定的：玩家点下去就该看见回音），
## 所以它是这件事唯一说得准的来源。
func echo(book: PBBattleLog, attackers: Array[PBAttacker], field: Vector2) -> void:
	step()
	if book == null:
		return
	for i: int in range(mini(_echoed, book.entries.size()), book.entries.size()):
		var entry: Dictionary = book.entries[i]
		if int(entry.get("kind", -1)) != PBBattleLog.Kind.ULTIMATE:
			continue
		var slot: int = int(entry.get("source", -1))
		for who: PBAttacker in attackers:
			if who.slot == slot:
				flash(PBLayout.to_screen(who.pos, field), bool(entry.get("to_ally", false)))
				break
	_echoed = book.entries.size()


func clear() -> void:
	_live = 0
	_echoed = 0
	queue_redraw()


## 现在有几圈。测试拿它确认「放了才有、过一会儿就没」。
func shown() -> int:
	return _live


func _draw() -> void:
	for i: int in _live:
		# 0 = 刚放出来，1 = 就要消失。
		var age: float = 1.0 - float(_left[i]) / float(LIFE_FRAMES)
		var color: Color = HOSTILE if _warm[i] else FRIENDLY
		color.a *= 1.0 - age
		# 战场上的圆在屏幕上是椭圆（M6-a），见 [method PBLayout.ground_disc]。
		# 这一圈贴着地面，所以它和射程圈、落点圈必须是同一个形状 ——
		# 画成正圆的话它看起来是浮在半空的。
		draw_polyline(
			PBLayout.ground_disc(_at[i], lerpf(FROM_PX, TO_PX, age), SEGMENTS), color, WIDTH
		)
