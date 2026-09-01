class_name PBFieldPicker
extends RefCounted
## 战场上「点到了谁」：战斗中的点选与点名（M4-e），准备阶段拖动摆位的命中判定。§02。
##
## **拖动本身 M5-4 起走引擎的拖放协议**（[PBDropArea]），不再自己监听鼠标 ——
## 一个项目里两套拖动迟早在「拖到别的面板上松手」这件事上分叉。
## 这里只剩下「屏幕上那个点是谁」。
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

## 正在等玩家点战场上的一个点，以及等他点来干什么。
##
## ## 为什么这两件事都要分两步
##
## 「按 A 再点地面」是 War3 那套，而且它让点错有一个可以后悔的中间态 ——
## 一步到位的话，手一抖就把主力指到一个残血杂兵身上，
## 或者把攒了 20 秒的忍术扔在空地上。
##
## ## 为什么是一个枚举，不是两个 bool
##
## 两个 bool 就有四种组合，其中「两个都开」是个说不清的状态 ——
## 那一下点击到底是指定目标还是下忍术？枚举里它不存在。
enum Aim {
	OFF,  ## 没在等
	TARGET,  ## 「攻击」：等他点一个敌人（M4-e）
	ULTIMATE,  ## 「忍术」：等他点一个落点（M5-9）
}

var aim_mode: Aim = Aim.OFF


## 正在等他点一个敌人。留着这个名字是因为它比 `aim_mode == Aim.TARGET` 好读，
## **而且只读** —— 状态只有 [member aim_mode] 一份。
var aiming: bool:
	get:
		return aim_mode == Aim.TARGET



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
## 点名只是一个**偏好**：那个敌人死了、走出射程了、还没进射程，
## 自动规则都会接管（见 [method PBBattleSim._first_reachable]）。
## 渲染层能碰 sim 的地方只有这一处，理由是它本来就是「玩家的指令」——
## 而指令就该是玩家能改的那种状态。
##
## **走 [method PBBattleSim.name_target]，不自己写那个字段**：点名要立刻
## 改变「他要打谁」（那根绿线），而重算那件事的规则在 sim 里，
## 且**暂停时 sim 的每 tick 那一遍不跑**。自己写一遍的话，
## 玩家在暂停下点完敌人画面一动不动，直到他取消暂停。
func aim(battle: PBBattleSim, live: PBAttacker, enemy: PBEnemy) -> void:
	if battle == null or live == null or enemy == null:
		return
	battle.name_target(live, enemy.slot)


## 交还给自动规则。
##
## **这是唯一一条能清掉点名的路。** 「目标死了就自动清」听起来更聪明，
## 但那样一个隔着射程点名的目标会在他走进来之前就被清掉，
## 而玩家看到的是「点了没用」。
func release(battle: PBBattleSim, live: PBAttacker) -> void:
	if battle != null and live != null:
		battle.name_target(live, -1)
	aim_mode = Aim.OFF


## 玩家按了「攻击」或「忍术」（M4-e / M5-9）。**再按一次退出**。
##
## 一步到位（按一下就打最近的）的话那两格没有意义 —— 那本来就是自动规则。
## 两者互斥是 [member aim_mode] 这个字段本身保证的，不靠调用方记得清另一个。
func toggle(want: Aim) -> void:
	aim_mode = Aim.OFF if aim_mode == want else want
