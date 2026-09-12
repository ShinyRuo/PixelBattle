class_name PBSummonRules
extends RefCounted
## 召唤物怎么来、怎么散（M12-c3）。全部 static，无状态，零引擎依赖。
##
## 和 [PBTargetRules]（敌人该打谁）、[PBMoveRules]（我方该往哪儿走）、
## [PBStrikeRules]（他这一 tick 打出去了什么）、[PBShotRules]（飞行中那一发到了没有）
## 对称：**这一层答的是「场上现在站着几个不是卡的人」。**
##
## ## 召唤物是真单位，不是一段增伤
##
## 玩家定的。原版那句「影分身承受 600% 的伤害」就是在说它们站在场上、
## 敌人会打它们、它们会替本体挡刀。降格成「本体增伤 N 秒」零结构代价，
## 但那正是 §09 明令禁止的「**只是更大的百分比**」。
##
## ## 位子是开波预留的，不在跑动中往数组里塞人
##
## **定长是这个 sim 里一堆东西的隐含前提**：[PBSkillOrders] 开波按人数铺一次、
## 渲染池按人数建节点、[PBCrowdRules] 两两遍历。中途变长会让它们各自失配，
## **而失配基本都不报错**。预留是本项目已经用熟的形状（同 [PBProjectile] 池、
## [PBEnemy] 池：定长 + `alive` 标志）。
##
## **没有召唤技能的队伍一个位子也不留**，所以全部既有配平数字一位不动 ——
## 同 M3.5-f 装备那条「空着 = 一字不差」。
##
## ## `slot` 从此不保证对应一张卡
##
## 在这之前 [member PBAttacker.slot] 同时是两件事：数组下标、出战席第几张卡。
## 召唤物只满足前一件。三处拿它反查卡的地方因此都要认这条
## （[PBFormationRules]、`battle_view` 的点选、[PBAllyPool] —— 最后一处
## 早就带着守卫了）。**尾兽先示范过同一件事**：它是一个 `slot = -1` 的
## [PBAttacker]，只是它连数组都不在。

## 召唤物散场时血条上还剩什么都不算数 —— 它不是「死了」，是「到点了」。
## 见 [method dismiss]。
const GONE: int = -1


## 这支队伍最多要留几个召唤物的位子。
##
## **按每个人的技能逐个数，不拍一个上限。** 拍上限的话，一支带两个召唤师的
## 队伍会在第二个人放技能时凭空少几个位子，**而它不报错** ——
## 表现是「有时候只召出来一半」。
static func reserve(deployed: Array[PBUnit], cfg: PBSimConfig) -> int:
	var total: int = 0
	for unit: PBUnit in deployed:
		for id: StringName in unit.character.skill_ids:
			var skill: PBSkill = _skill_of(id, cfg)
			if skill != null:
				total += maxi(skill.summon_count, 0)
	return total


## 把一个预留位子恢复成「空着」。开波和散场都走它。
##
## **不走 [method PBAttacker.revive]**：那个函数的意思是「他满血站好了」，
## 而一个还没被召出来的位子这一波可能一次都不会站人。
static func dismiss(one: PBAttacker) -> void:
	one.alive = false
	one.hp = 0.0
	one.expires_at = GONE
	one.buffs.clear()


## 放一发召唤技能：从预留位子里取 [member PBSkill.summon_count] 个站到本体身边。
## 返回真的召出来几个（位子不够就少召，**不报错也不排队**）。
##
## **位子不够只可能是数漏了**（[method reserve] 按技能逐个数过），
## 所以这里静默少召是安全的兜底，不是设计。
static func raise_from(
	attackers: Array[PBAttacker], caster: PBAttacker, skill: PBSkill, tick: int, cfg: PBSimConfig
) -> int:
	if skill.summon_count <= 0 or caster == null:
		return 0
	var life: int = int(round(skill.summon_seconds * float(cfg.tick_rate)))
	var made: int = 0
	for one: PBAttacker in attackers:
		if made >= skill.summon_count:
			break
		if not one.summoned or one.expires_at != GONE:
			continue
		_stand_up(one, caster, skill, tick + maxi(life, 1), cfg)
		made += 1
	return made


## 到点的召唤物散场。返回散了几个。
##
## **一 tick 扫一遍，而不是每个召唤物自己记一个闹钟** —— 同
## [PBBuffBag] 那条「过期是查询时比 tick」的反面：那一层漏跑一次不改变任何结果，
## 而这一层漏跑一次会让一个召唤物多站一会儿，那是能看出来的。
static func expire(attackers: Array[PBAttacker], tick: int) -> int:
	var gone: int = 0
	for one: PBAttacker in attackers:
		if not one.summoned or one.expires_at == GONE:
			continue
		if one.alive and tick < one.expires_at:
			continue
		dismiss(one)
		gone += 1
	return gone


## 站起来：照着本体缩一份属性。
##
## **射程、护甲属性、走位全抄本体**（原版：「乌鸦射程与自身一样」），
## 只有输出和血按比例缩。另外配一套的话，召唤物会在「够不够得着」这件事上
## 和本体分叉，而那表现为「召出来的东西站着不动」。
static func _stand_up(
	one: PBAttacker, caster: PBAttacker, skill: PBSkill, until: int, cfg: PBSimConfig
) -> void:
	one.dps = caster.dps * maxf(skill.summon_power, 0.0)
	one.max_hp = caster.max_hp * maxf(skill.summon_hp_share, 0.0)
	one.defence = caster.defence
	one.def_element = caster.def_element
	one.reach = caster.reach
	one.attack_speed = caster.attack_speed
	one.shot_speed = caster.shot_speed
	one.move_speed = caster.move_speed
	one.pos = caster.pos
	one.home = caster.pos
	one.expires_at = until
	one.prime(cfg.tick_rate, cfg)
	one.alive = true
	one.hp = one.max_hp
	one.next_shot_at = until - int(round(skill.summon_seconds * float(cfg.tick_rate)))


## 按 id 从配置里的技能表找一份技能。表没装进来（批量扫描那一路）就是 null。
static func _skill_of(id: StringName, cfg: PBSimConfig) -> PBSkill:
	if cfg.skills == null:
		return null
	return cfg.skills.by_id(id)
