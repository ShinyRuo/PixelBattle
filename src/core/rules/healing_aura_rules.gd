class_name PBHealingAuraRules
extends RefCounted
## 常驻治疗按当前站位查询，同名光环取最高治疗量；半径 0 仅自身。
## 无残留状态，离圈 / 来源倒下立即失效。原生光环残留尚待验证，不借用付费治疗 BUFF。
## 受攻击回复在敌人起手时发生，不等命中，不由技能伤害或额外普攻反复触发。


static func enabled(skill: PBSkill) -> bool:
	return skill.heal_aura_flat > 0.0 or skill.heal_aura_max > 0.0


static func advance(team: Array[PBAttacker], cfg: PBSimConfig, tick: int) -> void:
	var sources: Array[PBAttacker] = []
	for source: PBAttacker in team:
		if not source.is_targetable():
			continue
		for cast: PBSkillCast in source.skills:
			if enabled(cast.skill):
				sources.append(source)
				break
	if sources.is_empty():
		return
	for unit: PBAttacker in team:
		if not unit.is_targetable():
			continue
		var heals := {}
		for source: PBAttacker in sources:
			for cast: PBSkillCast in source.skills:
				var skill := cast.skill
				if not covers(source, unit, skill) or tick % skill.heal_aura_period_ticks != 0:
					continue
				var amount: float = (
					skill.heal_aura_flat
					+ skill.heal_aura_growth * maxi(cast.caster_level - 1, 0)
					+ unit.max_hp * skill.heal_aura_max
				)
				amount *= float(skill.heal_aura_period_ticks) / cfg.tick_rate * skill.heal_scale
				heals[skill.id] = maxf(float(heals.get(skill.id, 0.0)), amount)
		for amount: float in heals.values():
			unit.heal(amount)


static func covers(source: PBAttacker, unit: PBAttacker, skill: PBSkill) -> bool:
	return (
		enabled(skill)
		and source.is_targetable()
		and unit.is_targetable()
		and (
			source == unit
			or (skill.radius > 0.0 and source.pos.distance_to(unit.pos) <= skill.radius + 0.0000001)
		)
	)


static func on_attacked(
	unit: PBAttacker, team: Array[PBAttacker], rng: RandomNumberGenerator
) -> void:
	if rng == null or not unit.is_targetable():
		return
	var chance: float = 0.0
	var lost: float = 0.0
	for source: PBAttacker in team:
		for cast: PBSkillCast in source.skills:
			var skill := cast.skill
			if not covers(source, unit, skill):
				continue
			if skill.heal_aura_hit_chance * skill.heal_aura_lost > chance * lost:
				chance = skill.heal_aura_hit_chance
				lost = skill.heal_aura_lost
	if chance > 0.0 and rng.randf() < chance:
		unit.heal(maxf(unit.max_hp - unit.hp, 0.0) * lost)


static func validate(skill: PBSkill) -> String:
	for value: float in [
		skill.heal_aura_flat,
		skill.heal_aura_growth,
		skill.heal_aura_max,
		skill.heal_aura_hit_chance,
		skill.heal_aura_lost
	]:
		if not is_finite(value) or value < 0.0:
			return "治疗光环参数必须为有限非负数"
	if not enabled(skill):
		return (
			"治疗光环附加参数需要基础回复量"
			if (
				skill.heal_aura_growth > 0.0
				or skill.heal_aura_hit_chance > 0.0
				or skill.heal_aura_lost > 0.0
			)
			else ""
		)
	if (
		skill.heal_aura_period_ticks < 1
		or skill.heal_aura_hit_chance > 1.0
		or skill.heal_aura_lost > 1.0
		or skill.heal_aura_max > 1.0
		or (skill.heal_aura_hit_chance == 0.0) != (skill.heal_aura_lost == 0.0)
	):
		return "治疗周期至少一帧，比例不超过 1，攻击触发概率与已损恢复比例须成对配置"
	if (
		skill.target != PBSkill.Target.NONE
		or skill.affects != PBSkill.Party.ALLIES
		or skill.mp_cost != 0.0
		or not skill.mp_cost_levels.is_empty()
		or skill.cooldown_ticks != 0
		or skill.power_mult != 0.0
		or skill.damage_base != 0.0
		or skill.damage_growth != 0.0
		or skill.damage_hp != 0.0
		or skill.summon_count != 0
		or not skill.on_hit.is_empty()
		or not skill.on_self.is_empty()
	):
		return "常驻治疗只能配置无耗蓝冷却、无伤害、无命中效果的友方被动"
	return ""
