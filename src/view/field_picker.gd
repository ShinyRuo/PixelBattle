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
## 同屏有 48 + 10 个单位。给每一个都挂上输入区等于让引擎每帧做五十几次
## 命中测试，而这里一次点击只做一遍。
##
## M6-b 之后两边都是 [AnimatedSprite2D]（[Node2D]，压根不参与 GUI 命中），
## 所以「给单位挂输入区」这条路要先给每个人盖一层 [Control] ——
## 而那正是 M5-10 花了三个里程碑才挖出来的那个坑。

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
## ## 为什么 M7-e 之后只有一个 `SKILL`，不是每一档一个值
##
## 接下来那一下点击是什么意思（点地面 / 点队友 / 点敌人），
## **由那个技能自己的 [member PBSkill.target] 决定** —— 一把尺子。
## 加成 `SKILL_ALLY` / `SKILL_GROUND` / `SKILL_ENEMY` 三个值的话就有两份真相
## （枚举值和技能表），而它们可以分叉：改了技能表却忘了改按下按钮那一行，
## 表现是「点了队友却在地上炸了一发」，不报错。
##
## 这和上面那句「两个 bool 有四种组合」是同一条道理。
enum Aim {
	OFF,  ## 没在等
	TARGET,  ## 「攻击」：等他点一个敌人（M4-e）
	SKILL,  ## 「忍术」或某个技能：等他点什么由 [member aim_skill] 那一格自己说（M7-e）
}

var aim_mode: Aim = Aim.OFF

## [constant Aim.SKILL] 档下，正在放的是第几格技能
## （[method PBSkillRules.cast_at] 的下标：0 = 大招）。**-1 = 没在放。**
##
## 和 [member aim_mode] 是**一对**，不是两份真相：`OFF` 时它恒为 -1
## （[method toggle] 保证），所以「在等点击」这件事只有一个答案。
var aim_skill: int = -1


## 正在等他点一个敌人。留着这个名字是因为它比 `aim_mode == Aim.TARGET` 好读，
## **而且只读** —— 状态只有 [member aim_mode] 一份。
var aiming: bool:
	get:
		return aim_mode == Aim.TARGET



## [param spot] 附近站着的是名单里的第几个。没点中返回 -1。
##
## 位置走 [method PBFormationRules.spots_of] —— 和画在屏幕上的那一份
## 是同一次计算，各算各的话「点得到哪」和「看见哪」会差开。
## [param pick] 是**屏幕像素**，量距离也在屏幕上量（M6-a）——
## 战场坐标里量的话，y 被压过（[constant PBLayout.Y_SCALE]）的那三成
## 会变成「纵向要点得更准」，见 [method PBLayout.screen_gap]。
static func unit_at(
	units: Array[PBUnit],
	formation: Dictionary,
	cfg: PBSimConfig,
	spot: Vector2,
	field: Vector2,
	pick: float
) -> int:
	var spots := PBFormationRules.spots_of(units, formation, cfg)
	for i: int in units.size():
		if PBLayout.screen_gap(spots[i], spot, field) <= pick:
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
func ally_at(battle: PBBattleSim, spot: Vector2, field: Vector2, pick: float) -> PBAttacker:
	var best: PBAttacker = null
	var best_gap: float = pick
	for attacker: PBAttacker in battle.attackers():
		if attacker.slot < 0 or attacker.max_hp <= 0.0:
			continue
		var gap: float = PBLayout.screen_gap(attacker.pos, spot, field)
		if gap <= best_gap:
			best = attacker
			best_gap = gap
	return best


## [param spot] 附近最近的**已出场且活着**的敌人。没有就返回 null。
func enemy_at(battle: PBBattleSim, spot: Vector2, field: Vector2, pick: float) -> PBEnemy:
	var best: PBEnemy = null
	var best_gap: float = pick
	for enemy: PBEnemy in battle.enemies():
		if not enemy.is_active(battle.current_tick()):
			continue
		var gap: float = PBLayout.screen_gap(enemy.pos(), spot, field)
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
	stop()


## 不再等任何点击。取消的三条路（右键 / `Esc` / 再点一次那一格）都走这里 ——
## **两个字段必须一起清**，各清各的话会留下「`OFF` 但还记着第 1 格」这种
## 说不清的状态，而下一次进入 [constant Aim.SKILL] 时它会悄悄生效。
func stop() -> void:
	aim_mode = Aim.OFF
	aim_skill = -1


## 玩家按了「攻击」或某一格技能（M4-e / M5-9 / M7-e）。**再按一次退出**。
##
## 一步到位（按一下就打最近的）的话那几格没有意义 —— 那本来就是自动规则。
## 几种模式互斥是 [member aim_mode] 这个字段本身保证的，不靠调用方记得清另一个。
##
## [param skill] 只在 [constant Aim.SKILL] 档有意义。**同一格再按一次才退出** ——
## 「忍术」按下去之后再按「技能 1」该是**换成技能 1**，不是退出，
## 否则玩家要按两下才换得了格子。
func toggle(want: Aim, skill: int = -1) -> void:
	if aim_mode == want and (want != Aim.SKILL or aim_skill == skill):
		stop()
		return
	aim_mode = want
	aim_skill = skill if want == Aim.SKILL else -1
