class_name PBAllyAuraRules
extends RefCounted
## 远程基础攻击光环按出手时位置查询。同类取最高，不叠加；离开或载体失效立即消失。
## 基础攻击含主属性与星级派生，不含直接攻击词条。弱引用不延长战斗单位生命周期。


static func install(team: Array[PBAttacker]) -> void:
	var sources: Array[WeakRef] = []
	for unit: PBAttacker in team:
		for cast: PBSkillCast in unit.skills:
			if cast.skill.ranged_attack_aura > 0.0:
				sources.append(weakref(unit))
				break
	for unit: PBAttacker in team:
		unit.aura_sources = sources


static func rate(unit: PBAttacker) -> float:
	if not unit.is_targetable() or not unit.ranged_attack:
		return 0.0
	var amount: float = 0.0
	for source: WeakRef in unit.aura_sources:
		var owner: PBAttacker = source.get_ref()
		if owner == null or not owner.is_targetable():
			continue
		for cast: PBSkillCast in owner.skills:
			# Vector2 分量为单精度，半径字段为双精度；边界保留浮点舍入余量。
			if unit.pos.distance_to(owner.pos) <= cast.skill.radius + 0.0000001:
				amount = maxf(amount, cast.skill.ranged_attack_aura)
	return amount


static func skill_damage(unit: PBAttacker, skill: PBSkill, bonus: float, tick: int = 0) -> float:
	var extra: float = unit.base_attack * bonus_rate(unit, tick)
	var total: float = float(unit.damage_attributes.get(&"attack", 0.0))
	var first: float = bonus * extra / total if total > 0.0 else 0.0
	return skill.damage + bonus + extra * skill.attack_formula_scale + first


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.ranged_attack_aura) or skill.ranged_attack_aura < 0.0:
		return "远程基础攻击光环必须是有限非负数"
	if skill.ranged_attack_aura == 0.0:
		return ""
	if (
		skill.target != PBSkill.Target.NONE
		or skill.affects != PBSkill.Party.ALLIES
		or not is_finite(skill.radius)
		or skill.radius <= 0.0
		or skill.mp_cost != 0.0
		or not skill.mp_cost_levels.is_empty()
		or skill.power_mult != 0.0
		or skill.damage_base != 0.0
		or skill.damage_growth != 0.0
		or not skill.on_hit.is_empty()
		or not skill.on_self.is_empty()
	):
		return "远程攻击光环需要无耗蓝、无伤害、无命中效果的友方自身范围技能"
	return ""


static func normal_bonus(unit: PBAttacker, tick: int = 0) -> float:
	var total: float = float(unit.damage_attributes.get(&"attack", 0.0))
	if total <= 0.0:
		return 0.0
	# 取当前单发攻击中的基础攻击占比，保留克制 / 队伍倍率及探测缩放。
	return unit.damage_per_shot() * unit.base_attack / total * bonus_rate(unit, tick)


static func bonus_rate(unit: PBAttacker, tick: int) -> float:
	return (
		rate(unit)
		+ PBOnAttackRules.self_bonus(unit)
		+ unit.buffs.amount(PBBuffRules.BASE_ATTACK_BONUS, tick)
	)
