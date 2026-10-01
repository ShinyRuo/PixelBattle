class_name PBRescueRules
extends RefCounted
## 救援在实际扣血后判定；每波每名本体仅一次，不救活尸体、不治疗召唤物。
## 光环只负责触发，已授予的周期恢复不因来源死亡或离圈撤回。


static func on_hurt(
	target: PBAttacker,
	source: PBEnemy,
	dealt: float,
	team: Array[PBAttacker],
	cfg: PBSimConfig,
	tick: int
) -> void:
	if (
		not target.is_targetable()
		or target.summoned
		or target.rescue_used
		or target.attribute_profile == null
		or target.max_hp < 400
		or source == null
		or source.max_hp < 400
		or dealt <= 5
		or target.hp > target.max_hp * 0.5
	):
		return
	for owner: PBAttacker in team:
		if not owner.is_targetable() or owner.summoned:
			continue
		for cast: PBSkillCast in owner.skills:
			var skill := cast.skill
			if skill.rescue_radius <= 0 or owner.pos.distance_to(target.pos) > skill.rescue_radius:
				continue
			target.rescue_used = true
			var level := target.attribute_profile.level
			for buff: PBBuff in skill.on_rescue:
				var mods := PBBuffRules.scale_heal(
					PBBuffRules.resolve(buff, level), skill.heal_scale
				)
				PBSkillRules.apply_one(target, buff, mods, cfg, tick, level)
			return


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.rescue_radius) or skill.rescue_radius < 0:
		return "救援半径必须有限且非负"
	if skill.rescue_radius > 0 and skill.on_rescue.is_empty():
		return "救援光环必须配置恢复效果"
	for buff: PBBuff in skill.on_rescue:
		if buff == null or not buff.friendly or buff.kind != PBBuff.Kind.PERIODIC:
			return "救援只允许友方周期恢复"
		if buff.mods.keys() != [PBBuffRules.HEAL]:
			return "救援效果只配置治疗量"
	return ""
