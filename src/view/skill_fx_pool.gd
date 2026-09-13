class_name PBSkillFxPool
extends Node2D
## 施法瞬间从施法者脚下扩散出去的一圈环。
##
## 补的是「**这个人刚刚放了一个技能**」这格反馈：锁定档的治疗没有落点圈，没有它的话屏幕上什么都不会发生。
## 和 [PBTelegraphPool] 方向相反：那一个越接近落地越亮（预告），这一个越扩散越淡（回音），否则两种圈读成同一句话。
## **不参与任何判定**，连 [PBBattleSim] 都不认识 —— 只收「谁、在哪、什么颜色」。

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

## 播报已经消化到**第几条**（[member PBBattleLog.total]，只增不减）。不能存 `entries` 的长度，理由见那个字段。
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


## 走一帧，并把播报里**新出现**的施法变成圈。[param attackers] 来自 [method PBBattleSim.attackers]，**只读**。
## 游标由本类自己记（[member _echoed]）。
##
## **触发读播报，不读「谁身上有一发在飞」**：不挑目标的那一档下达和落地在同一 tick，渲染层结构上抓不到中间状态，
## 而那正是最需要回音的一档。播报记的是下达那一刻，所以它是唯一说得准的来源。
func echo(book: PBBattleLog, attackers: Array[PBAttacker], field: Vector2) -> void:
	step()
	if book == null:
		return
	for i: int in range(book.fresh_from(_echoed), book.entries.size()):
		var entry: Dictionary = book.entries[i]
		if int(entry.get("kind", -1)) != PBBattleLog.Kind.ULTIMATE:
			continue
		var slot: int = int(entry.get("source", -1))
		for who: PBAttacker in attackers:
			if who.slot == slot:
				flash(PBLayout.to_screen(who.pos, field), bool(entry.get("to_ally", false)))
				break
	_echoed = book.total


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
		# 贴着地面的圈画成椭圆（[method PBLayout.ground_disc]），和射程圈、落点圈同一个形状；画成正圆会像浮在半空。
		draw_polyline(
			PBLayout.ground_disc(_at[i], lerpf(FROM_PX, TO_PX, age), SEGMENTS), color, WIDTH
		)
