class_name PBFieldPicker
extends RefCounted
## 战场上「点到了谁」：战斗中的点选与点名（M4-e），准备阶段的拖动摆位（M4-f）。§02。
##
## ## 为什么从 [PBBattleView] 里搬出来
##
## 直接的触发是 gdlint 报那个文件破了 1000 行上限。那条上限
## 「超了不是错，是该拆了的信号」，这次它指对了地方 ——
## 和 [PBShopRules] 当初从 [PBStrategy] 里分出来是同一回事。
##
## 分出来的这一块有一个说得清的边界：**它只回答「屏幕上那个点对应哪个单位」，
## 以及「点名这件事的状态」**。画面怎么装配、面板什么时候刷新，
## 那是 [PBBattleView] 的事。
##
## ## 命中判定为什么在这里做，不给每个单位挂一个输入区
##
## 敌人是 `Polygon2D`、己方是 `ColorRect`，两种节点的输入行为完全不同，
## 而且同屏有 48 + 10 个。给每一个都挂上输入区等于让引擎每帧做五十几次
## 命中测试，而这里一次点击只做一遍。

## 玩家按了「攻击」、正在等他点一个敌人。
##
## ## 为什么指定目标要分两步
##
## 「按 A 再点地面」是 War3 那套，而且它让点错有一个可以后悔的中间态 ——
## 一步到位的话，手一抖就把主力指到一个残血杂兵身上。
var aiming: bool = false

## 正在被拖着摆位置的那个忍者的 id（准备阶段，M4-f）。空 = 没在拖。
##
## 存 id 不存下标：拖到一半时名单可能重排（羁绊策略每帧重挑一次），
## 而下标一变手上拖的就换了个人 —— 那不报错，只表现为「拖着拖着换人了」。
var dragging: StringName = &""


## [param spot] 附近站着的是名单里的第几个。没点中返回 -1。
##
## 位置走 [method PBFormationRules.spots_of] —— 和画在屏幕上的那一份
## 是同一次计算，各算各的话「点得到哪」和「看见哪」会差开。
static func unit_at(
	units: Array[PBUnit], formation: Dictionary, cfg: PBSimConfig, spot: Vector2, pick: float
) -> int:
	var spots := PBFormationRules.spots_of(units, formation, cfg)
	for i: int in units.size():
		if spots[i].distance_to(spot) <= pick:
			return i
	return -1


## [param unit_id] 是名单里的第几个。不在名单里返回 -1。
static func index_of(units: Array[PBUnit], unit_id: StringName) -> int:
	for i: int in units.size():
		if units[i].key() == unit_id:
			return i
	return -1


## 把正在拖的那个人摆到 [param at]。没在拖就什么都不做。
##
## **每一帧都写进状态**，不是松手才写 —— 松手才写的话拖动过程中方块
## 不会跟着走，玩家会以为没拖起来。
##
## 走 [method PBFormationRules.place]，不自己往 [member PBRunState.formation]
## 里塞 Vector2：那条路会漏掉界限夹取，而一个摆在战场之外的忍者不报错，
## 他只是画在屏幕外面然后一发都打不着。
func drag_to(state: PBRunState, cfg: PBSimConfig, at: Vector2) -> void:
	var unit := state.roster.get(dragging, null) as PBUnit
	if unit == null:
		dragging = &""
		return
	PBFormationRules.place(state, unit, at, cfg)


## 选中那个忍者这一波在场上的样子。没上场（或者压根没选人）就返回 null。
##
## 靠 [member PBAttacker.slot] 对回 [member PBWavePlan.deployed] 的下标 ——
## 那是建攻击者时定下的对应关系（[method PBCombatRules.build_attackers]），
## 全项目只有这一处需要反查。
func attacker_of(
	battle: PBBattleSim, deployed: Array[PBUnit], unit_id: StringName
) -> PBAttacker:
	if battle == null or unit_id == &"":
		return null
	for attacker: PBAttacker in battle.attackers():
		if attacker.slot < 0 or attacker.slot >= deployed.size():
			continue
		if deployed[attacker.slot].key() == unit_id:
			return attacker
	return null


## [param spot]（战场坐标）[param pick] 之内最近的己方单位。没有就返回 null。
##
## 尾兽那一个排除在外（`slot < 0`）：它没有本体、位置恒为 0，
## 点得中的话玩家会以为基地上站着一个忍者。
func ally_at(battle: PBBattleSim, spot: Vector2, pick: float) -> PBAttacker:
	var best: PBAttacker = null
	var best_gap: float = pick
	for attacker: PBAttacker in battle.attackers():
		if attacker.slot < 0 or attacker.max_hp <= 0.0:
			continue
		var gap: float = attacker.pos.distance_to(spot)
		if gap <= best_gap:
			best = attacker
			best_gap = gap
	return best


## [param spot] 附近最近的**已出场且活着**的敌人。没有就返回 null。
func enemy_at(battle: PBBattleSim, spot: Vector2, pick: float) -> PBEnemy:
	var best: PBEnemy = null
	var best_gap: float = pick
	for enemy: PBEnemy in battle.enemies():
		if not enemy.is_active(battle.current_tick()):
			continue
		var gap: float = enemy.pos().distance_to(spot)
		if gap <= best_gap:
			best = enemy
			best_gap = gap
	return best


## 让 [param live] 改打 [param enemy]。任一为 null 就什么都不做。
##
## **写的是 [member PBAttacker.forced_target] 这一个字段**，而它只是一个偏好：
## 那个敌人死了、走出射程了、还没进射程，自动规则都会接管
## （见 [method PBBattleSim._first_reachable]）。渲染层能碰 sim 的地方
## 只有这一处，理由是它本来就是「玩家的指令」——
## 而指令就该是玩家能改的那种状态。
func aim(live: PBAttacker, enemy: PBEnemy) -> void:
	if live == null or enemy == null:
		return
	live.forced_target = enemy.slot


## 交还给自动规则。
##
## **这是唯一一条能清掉点名的路。** 「目标死了就自动清」听起来更聪明，
## 但那样一个隔着射程点名的目标会在他走进来之前就被清掉，
## 而玩家看到的是「点了没用」。
func release(live: PBAttacker) -> void:
	if live != null:
		live.forced_target = -1
	aiming = false
