class_name PBMotionAuraRules
extends RefCounted
## 攻速 / 移速光环实时查询位置，同类取最高；普通形态半径 0 只作用自身。
## 不回写基础属性，避免移出范围、属性转移或召唤位复用时残留加成。


static func enabled(skill: PBSkill) -> bool:
	return skill.attack_speed_aura > 0.0 or skill.move_speed_aura > 0.0


static func install(team: Array[PBAttacker]) -> void:
	var sources: Array[WeakRef] = []
	for unit: PBAttacker in team:
		for cast: PBSkillCast in unit.skills:
			if enabled(cast.skill):
				sources.append(weakref(unit))
				break
	for unit: PBAttacker in team:
		unit.motion_sources = sources


static func bonus(unit: PBAttacker, movement: bool = false) -> float:
	if not unit.alive or unit.max_hp <= 0.0:
		return 0.0
	var amount: float = 0.0
	for source: WeakRef in unit.motion_sources:
		var owner: PBAttacker = source.get_ref()
		if owner == null or not owner.is_targetable():
			continue
		for cast: PBSkillCast in owner.skills:
			var skill: PBSkill = cast.skill
			if not enabled(skill):
				continue
			if (
				owner != unit
				and (
					skill.radius <= 0.0
					or owner.pos.distance_to(unit.pos) > skill.radius + 0.0000001
				)
			):
				continue
			var value: float = (
				skill.move_speed_aura
				if movement
				else (
					skill.attack_speed_aura
					+ skill.attack_speed_aura_growth * float(maxi(cast.caster_level - 1, 0))
				)
			)
			amount = maxf(amount, value)
	return amount


static func attack_scale(unit: PBAttacker) -> float:
	var existing: float = 0.0
	if unit.attribute_profile != null:
		existing = PBStatRules.amount(unit.attribute_profile.mods, PBStatRules.ATTACK_SPEED)
	return 1.0 + bonus(unit) / maxf(1.0 + existing, 0.01)


static func move_step(unit: PBAttacker) -> float:
	return unit.move_speed * (1.0 + bonus(unit, true) / maxf(1.0 + unit.move_speed_bonus, 0.01))


static func windup_ticks(unit: PBAttacker) -> int:
	if unit.motion_sources.is_empty():
		return unit.windup_ticks
	return mini(
		roundi(float(unit.windup_ticks) / attack_scale(unit)), maxi(unit.attack_interval() - 1, 0)
	)


static func validate(skill: PBSkill) -> String:
	for value: float in [
		skill.attack_speed_aura, skill.attack_speed_aura_growth, skill.move_speed_aura
	]:
		if not is_finite(value) or value < 0.0:
			return "攻速 / 移速光环必须为有限非负数"
	if not enabled(skill):
		return "光环成长需要正基础攻速加成" if skill.attack_speed_aura_growth > 0.0 else ""
	if (
		skill.target != PBSkill.Target.NONE
		or skill.affects != PBSkill.Party.ALLIES
		or not is_finite(skill.radius)
		or skill.radius < 0.0
		or skill.mp_cost != 0.0
		or not skill.mp_cost_levels.is_empty()
		or skill.power_mult != 0.0
		or skill.damage_base != 0.0
		or skill.damage_growth != 0.0
		or skill.damage_hp != 0.0
		or skill.summon_count != 0
		or not skill.on_hit.is_empty()
		or not skill.on_self.is_empty()
	):
		return "速度光环只支持无伤害、无耗蓝、无命中效果的友方被动技能"
	return ""
