class_name PBSummonRules
extends RefCounted
## 召唤物怎么来、怎么散。全部 static，无状态，零引擎依赖。
##
## ## 召唤物是真单位（玩家定的）
##
## 原版「影分身承受 600% 的伤害」说明它站在场上、会挨打、替本体挡刀。
## 降格成「本体增伤 N 秒」正是 §09 禁止的「只是更大的百分比」。
##
## ## 位子开波预留，跑动中不往数组里塞人
##
## 定长是 sim 里一堆东西的隐含前提：[PBSkillOrders] 按人数铺一次、渲染池按人数建节点、
## [PBCrowdRules] 两两遍历。中途变长会让它们各自失配，而失配基本不报错。
## **没有召唤技能的队伍一个位子也不留**，配平数字一位不动。
##
## ## `slot` 不保证对应一张卡
##
## [member PBAttacker.slot] 对召唤物只是数组下标。拿它反查卡的地方
## （[PBFormationRules]、`battle_view` 的点选、[PBAllyPool]）都要带守卫 ——
## 尾兽（`slot = -1`）是同一个形状。

## 召唤物散场时血条上还剩什么都不算数 —— 它不是「死了」，是「到点了」。
## 见 [method dismiss]。
const GONE: int = -1


## 这支队伍最多要留几个召唤物的位子。
##
## **按每个人的技能逐个数，不拍一个上限。** 拍上限的话，一支带两个召唤师的
## 队伍会在第二个人放技能时凭空少几个位子，**而它不报错** ——
## 表现是「有时候只召出来一半」。
static func reserve(deployed: Array[PBUnit], cfg: PBSimConfig, patches: Dictionary = {}) -> int:
	var total: int = 0
	for unit: PBUnit in deployed:
		for id: StringName in unit.character.skill_ids:
			var skill: PBSkill = _skill_of(id, cfg)
			if skill != null:
				skill = skill.clone()
				PBSkillPatchRules.apply(skill, patches.get(unit.character.id, {}).get(id, {}))
				total += maxi(skill.summon_count, 0)
				total += maxi(skill.phantom_count, 0) * skill.hit_count
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
	one.forced_target = -1
	one.focus_named_target = false
	one.aim_at = -1
	one.swinging = false
	one.phantom = false
	one.appearance_slot = -1


## 放一发召唤技能：从预留位子里取 [member PBSkill.summon_count] 个站到本体身边。
## 返回真的召出来几个（位子不够就少召，**不报错也不排队**）。
##
## **位子不够只可能是数漏了**（[method reserve] 按技能逐个数过），
## 所以这里静默少召是安全的兜底，不是设计。
##
## [param count] 大于等于 0 时只召这么多个（受击时召一个分身那一路），属性照这份技能。
static func raise_from(
	attackers: Array[PBAttacker],
	caster: PBAttacker,
	skill: PBSkill,
	tick: int,
	cfg: PBSimConfig,
	count: int = -1,
	level: int = 1,
	target_slot: int = -1
) -> int:
	if skill.summon_count <= 0 or caster == null:
		return 0
	var want: int = skill.summon_count if count < 0 else count
	var life: int = int(round(skill.summon_seconds * float(cfg.tick_rate)))
	var made: int = 0
	for one: PBAttacker in attackers:
		if made >= want:
			break
		if not one.summoned or one.expires_at != GONE:
			continue
		_stand_up(one, caster, skill, tick + maxi(life, 1), cfg, level)
		one.focus_named_target = skill.summon_focus
		one.forced_target = target_slot if skill.summon_focus else -1
		one.next_shot_at = tick
		made += 1
	return made


## 到点的召唤物散场。返回散了几个。**每 tick 扫一遍**。
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
	one: PBAttacker, caster: PBAttacker, skill: PBSkill, until: int, cfg: PBSimConfig, level: int
) -> void:
	one.summon_skill_id = skill.id
	one.summon_serial += 1
	one.phantom = false
	one.appearance_slot = -1
	one.crit_chance = 0.0
	one.crit_bonus = 0.0
	# 一发多重要跟着缩：战斗读的是 `attack`，只缩 dps 的话召唤物一点伤害都打不出来。
	one.attack = caster.attack * skill.summon_power_at(level)
	one.base_attack = caster.base_attack * skill.summon_power_at(level)
	one.damage_attributes = caster.damage_attributes.duplicate()
	one.damage_attributes[&"attack"] = (
		float(caster.damage_attributes.get(&"attack", 0.0)) * skill.summon_power_at(level)
	)
	one.ranged_attack = caster.ranged_attack
	one.dps = caster.dps * skill.summon_power_at(level)
	one.max_hp = caster.max_hp * maxf(skill.summon_hp_share, 0.0)
	# 吸血跟着**这一发技能**走，不抄本体：位子会被别的召唤技能复用，抄本体或者不重设都会串。
	one.lifesteal = maxf(skill.summon_lifesteal, 0.0)
	one.defence = caster.defence
	one.def_element = caster.def_element
	one.attack_element = caster.attack_element
	one.ninjutsu_resist = caster.ninjutsu_resist
	one.reach = caster.reach
	one.attack_speed = caster.attack_speed
	one.shot_speed = caster.shot_speed
	one.move_speed = caster.move_speed
	one.leash = caster.leash
	one.swinging = false
	one.aim_at = -1
	one.pos = caster.pos
	one.home = caster.pos
	one.expires_at = until
	one.prime(cfg.tick_rate, cfg)
	one.alive = true
	one.hp = one.max_hp


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.summon_power_growth) or skill.summon_power_growth < 0.0:
		return "召唤攻击成长必须有限且非负"
	if skill.summon_power_growth > 0.0 or skill.summon_focus:
		if skill.summon_count <= 0:
			return "召唤成长与追击必须配置召唤数量"
	if skill.summon_focus and skill.target != PBSkill.Target.ENEMY:
		return "召唤追击必须锁定敌方目标"
	return ""


## 按 id 从配置里的技能表找一份技能。表没装进来（批量扫描那一路）就是 null。
static func _skill_of(id: StringName, cfg: PBSimConfig) -> PBSkill:
	if cfg.skills == null:
		return null
	return cfg.skills.by_id(id)
