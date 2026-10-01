class_name PBAimLines
extends Node2D
## 「他要打谁」「我正在指谁」画出来（§02）。点选、点名、手动放技能在屏幕上本来一个反馈都没有 ——
## 暂停时更是如此，而暂停正是用来读局面的那一刻。
##
## | 线 | 从哪到哪 | 说的是 |
## |---|---|---|
## | A | 忍者 → 他这一刻的攻击目标 | 「他要打这个」 |
## | B | 选中的忍者 → 鼠标 | 「正在等你点一个敌人」 |
## | C | 选中的忍者 → 鼠标，鼠标处加一个范围圈 | 「正在等你点一个落点」 |
## | D | 选中的忍者 → 鼠标，可选目标脚下各一圈 | 「正在等你点一个队友」 |
## | E | 已下令的忍者脚下一圈 + 指向目标的线 | 「挑好了，等着放」 |
##
## **B / C / D 与 A 不同色**：A 是既成事实，后几条是还没落地的意图。C 的圈跟着鼠标（挑的是那块地落在哪），
## D 的圈在候选目标脚下（能不能点倒下的、能不能点自己，画出来就不用猜）。
##
## **施法者高亮不管哪一档都画**（地面技能没有候选目标可高亮），和候选环不同色。
## **画哪一条由技能自己说**（[member PBSkill.target]），不另摆一份「哪个模式画哪条线」的表。
## **A 平时只画选中那一条，暂停时画全场**：跑起来画全部是一屏乱线，暂停时要一眼看出谁在打同一个目标。

## A：他要打谁。绿 —— 和血条同一套「这是好事」的语义。
const LINE_TARGET := Color(0.443, 0.816, 0.549, 0.85)

## B：正在等你点敌人。红 —— 和敌人子弹同色系，说的是「这一下是攻击」。
const LINE_PICK := Color(0.898, 0.420, 0.420, 0.9)

## C：正在等你点忍术落点。橙 —— 和落点预示圈（[PBTelegraphPool]）同色系。
const LINE_CAST := Color(0.98, 0.72, 0.32, 0.9)

## D：正在等你点一个队友。青 —— 和红（打敌人）、橙（炸地面）都拉得开。
const LINE_ALLY := Color(0.42, 0.85, 0.90, 0.9)

## 施法者脚下那一圈：**就是他在放**。白偏暖，比候选环亮 ——
## 它说的是既成事实，而候选环说的是「你可以点这几个」。
const CASTER_EDGE := Color(1.0, 0.96, 0.86, 0.85)

## E：已下令但还没放出去的那几条。施法者脚下一圈黄 + 一条指向目标的虚线。
##
## 暂停下玩家会连着给好几个人下令，而指令卡只显示选中的那一个 —— 不画的话就是盲操作。
## 线色沿用 C / D（同一句话，从「正在挑」变成「挑好了」）；环用黄，和施法者高亮（[constant CASTER_EDGE]，白）拉开。
const ORDER_EDGE := Color(0.98, 0.85, 0.45, 0.85)

## 已下令那一圈的半径（像素）。比施法者高亮小一点，比候选环大一点。
const ORDER_PX: float = 8.5

## 候选目标脚下那一圈，和 D 线同色系、更淡。
const CANDIDATE_EDGE := Color(0.42, 0.85, 0.90, 0.45)

## 两种脚下环的半径（像素）。施法者那圈大一点，好在一堆候选里一眼认出来。
const CASTER_PX: float = 10.0
const CANDIDATE_PX: float = 7.0

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

## [constant PBFieldPicker.Aim.SKILL] 档下那一格技能点的是什么
## （[enum PBSkill.Target]）。**-1 = 不在技能档** —— 画哪条线读的就是它。
var _tier: int = -1

## 忍术范围圈的半径（像素）。0 表示不画。
var _cast_px: float = 0.0
var _cast_outline: PackedVector2Array = PackedVector2Array()

## 锁定档下可以点的那几个人的屏幕坐标（D 那一圈圈）。
var _candidates: PackedVector2Array = PackedVector2Array()

## E：已下令那几条的端点，**两个一对**（施法者、目标点）。
var _orders: PackedVector2Array = PackedVector2Array()

## 每一对是哪一档（[enum PBSkill.Target]），决定那条线什么颜色。
var _order_tiers: PackedInt32Array = PackedInt32Array()


## 把三条线摆好。每渲染帧调一次。
##
## [param live] 是选中的那个忍者，可以是 null（没选中人时只有 A 线）。
## [param everyone] 为真时 A 线画全场，否则只画 [param live] 那一条 ——
## 判据是「暂停了没有」，理由见类顶部。
func sync(
	battle: PBBattleSim,
	field: Vector2,
	live: PBAttacker,
	picker: PBFieldPicker,
	cursor: Vector2,
	everyone: bool
) -> void:
	# **收整个 [PBFieldPicker]，不收拆开的两个字段**：
	# `aim_mode` 和 `aim_skill` 是一对（见那里），拆开传就有一处能对不上。
	var mode: int = picker.aim_mode
	var links := PackedVector2Array()
	if everyone:
		for attacker: PBAttacker in battle.attackers():
			_link(links, attacker, battle, field)
	elif live != null:
		_link(links, live, battle, field)
	var from := Vector2.ZERO
	var tier: int = -1
	var cast_px: float = 0.0
	var picks := PackedVector2Array()
	var outline := PackedVector2Array()
	if live != null and mode != PBFieldPicker.Aim.OFF:
		from = PBLayout.to_screen(live.pos, field)
		var cast := PBSkillRules.cast_at(live, picker.aim_skill)
		if mode == PBFieldPicker.Aim.SKILL and cast != null:
			tier = cast.skill.target
			if tier == PBSkill.Target.GROUND:
				# 半径读技能自己的，不读配置：羁绊功能档会放大它
				# （[constant PBBondFunctionRules.PULL_RADIUS_SCALE]），而圈画小了
				# 等于告诉玩家一件错的事。
				cast_px = cast.skill.radius * PBLayout.px_per_unit(field)
				if cast.skill.line_length > 0.0:
					for point: Vector2 in PBSkillArea.outline(
						cast.skill, live.pos, PBLayout.to_field(cursor, field)
					):
						outline.append(PBLayout.to_screen(point, field))
			elif tier == PBSkill.Target.ALLY:
				_gather_allies(picks, battle, field)
			elif tier == PBSkill.Target.ENEMY:
				_gather_enemies(picks, battle, field)
	var orders := PackedVector2Array()
	var tiers := PackedInt32Array()
	_gather_orders(orders, tiers, battle, field)
	if _cast_outline != outline:
		_cast_outline = outline
		queue_redraw()
	_apply(links, from, cursor, mode, tier, cast_px, picks, orders, tiers)


## 已下令但还没放出去的那几条，每条收一对端点加一个档位。
## **读 [method PBBattleSim.orders]**：攒着的那条还没进 [PBSkillCast]，放出去之后换成落点预示圈接手。
## 终点：地面档是落点，锁定档是那个队友现在站的地方，不挑目标的没有终点（只画那个圈）。
static func _gather_orders(
	out: PackedVector2Array, tiers: PackedInt32Array, battle: PBBattleSim, field: Vector2
) -> void:
	var queue := battle.orders()
	if queue.count() == 0:
		return
	var attackers := battle.attackers()
	for at: int in attackers.size():
		var index: int = queue.index_of(at)
		if index < 0:
			continue
		var cast := PBSkillRules.cast_at(attackers[at], index)
		if cast == null:
			continue
		var from := PBLayout.to_screen(attackers[at].pos, field)
		var to := from
		if cast.skill.target == PBSkill.Target.GROUND:
			to = PBLayout.to_screen(queue.spot_of(at), field)
		elif cast.skill.target == PBSkill.Target.ALLY:
			var slot: int = queue.target_of(at)
			if slot >= 0 and slot < attackers.size():
				to = PBLayout.to_screen(attackers[slot].pos, field)
		out.append(from)
		out.append(to)
		tiers.append(cast.skill.target)


## 锁定档下点得中的那几个人。**判据是 [method PBAttacker.is_targetable]**，和落地时那道门读同一份 ——
## 否则会画出「看着能点、点了空放」的候选。尾兽排除在外（`slot < 0`，没有本体）。
static func _gather_allies(out: PackedVector2Array, battle: PBBattleSim, field: Vector2) -> void:
	for attacker: PBAttacker in battle.attackers():
		if attacker.slot >= 0 and attacker.is_targetable():
			out.append(PBLayout.to_screen(attacker.pos, field))


## 点敌人那一档下点得中的那几个。**判据是 [method PBEnemy.is_active]**，和 [method PBFieldPicker.enemy_at] 读同一份。
static func _gather_enemies(out: PackedVector2Array, battle: PBBattleSim, field: Vector2) -> void:
	for enemy: PBEnemy in battle.enemies():
		if enemy.is_active(battle.current_tick()):
			out.append(PBLayout.to_screen(enemy.pos(), field))


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
	links: PackedVector2Array,
	from: Vector2,
	cursor: Vector2,
	mode: int,
	tier: int,
	cast_px: float,
	picks: PackedVector2Array,
	orders: PackedVector2Array,
	tiers: PackedInt32Array
) -> void:
	if (
		_links == links
		and _from == from
		and _cursor == cursor
		and _mode == mode
		and _tier == tier
		and is_equal_approx(_cast_px, cast_px)
		and _candidates == picks
		and _orders == orders
		and _order_tiers == tiers
	):
		return
	_links = links
	_from = from
	_cursor = cursor
	_mode = mode
	_tier = tier
	_cast_px = cast_px
	_candidates = picks
	_orders = orders
	_order_tiers = tiers
	queue_redraw()


## 一条都不画（准备阶段、本局结束）。
func clear() -> void:
	_cast_outline = PackedVector2Array()
	_apply(
		PackedVector2Array(),
		Vector2.ZERO,
		Vector2.ZERO,
		PBFieldPicker.Aim.OFF,
		-1,
		0.0,
		PackedVector2Array(),
		PackedVector2Array(),
		PackedInt32Array()
	)


func _draw() -> void:
	for i: int in range(0, _links.size() - 1, 2):
		draw_dashed_line(_links[i], _links[i + 1], LINE_TARGET, WIDTH, DASH)
	# E 先画：它是背景里的一层「还欠着几条」，B / C / D 那条正在挑的要压在上面。
	for i: int in _order_tiers.size():
		var at := _orders[i * 2]
		var to := _orders[i * 2 + 1]
		draw_polyline(PBLayout.ground_disc(at, ORDER_PX, SEGMENTS), ORDER_EDGE, WIDTH)
		if at != to:
			var hue := LINE_ALLY if _order_tiers[i] == PBSkill.Target.ALLY else LINE_CAST
			draw_dashed_line(at, to, hue, WIDTH, DASH)
	if _from == Vector2.ZERO:
		return
	# **施法者高亮先画，而且哪一档都画**（决策 1）：地面技能没有候选目标，
	# 但「是谁在放」那个问题它一样有。见类顶部。
	draw_polyline(PBLayout.ground_disc(_from, CASTER_PX, SEGMENTS), CASTER_EDGE, WIDTH)
	if _mode == PBFieldPicker.Aim.TARGET:
		draw_dashed_line(_from, _cursor, LINE_PICK, WIDTH, DASH)
		return
	if _mode != PBFieldPicker.Aim.SKILL:
		return
	if _tier == PBSkill.Target.ALLY or _tier == PBSkill.Target.ENEMY:
		# **点敌人那一档用橙线，不是「攻击」那条红线**：红说「改打谁」（偏好），橙说「这一发落在谁身上」。
		var hue := LINE_ALLY if _tier == PBSkill.Target.ALLY else LINE_CAST
		var edge := CANDIDATE_EDGE if _tier == PBSkill.Target.ALLY else CAST_EDGE
		draw_dashed_line(_from, _cursor, hue, WIDTH, DASH)
		for at: Vector2 in _candidates:
			draw_polyline(PBLayout.ground_disc(at, CANDIDATE_PX, SEGMENTS), edge, WIDTH)
		return
	if _tier != PBSkill.Target.GROUND:
		return
	draw_dashed_line(_from, _cursor, LINE_CAST, WIDTH, DASH)
	if _cast_px > 0.0:
		# 地面上的圆画成椭圆，见 [method PBLayout.ground_disc]。
		var ring := PBLayout.ground_disc(_cursor, _cast_px, SEGMENTS)
		if not _cast_outline.is_empty():
			ring = _cast_outline
		draw_colored_polygon(ring, CAST_FILL)
		draw_polyline(ring, CAST_EDGE, WIDTH)
