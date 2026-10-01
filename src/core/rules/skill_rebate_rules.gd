class_name PBSkillRebateRules
extends RefCounted
## 原版施放后的短延迟返蓝 / 冷却设置。只在真实落地时安排，一次消费，开波清零。


static func schedule(cast: PBSkillCast, tick: int) -> void:
	if cast.skill.rebate_delay_ticks <= 0:
		return
	cast.rebate_at = tick + cast.skill.rebate_delay_ticks
	cast.rebate_mana = (
		PBSkillCostRules.mana(cast.skill, cast.caster_level) * cast.skill.rebate_mana_scale
	)


static func advance(unit: PBAttacker, cast: PBSkillCast, tick: int) -> void:
	if cast == null or cast.rebate_at < 0 or tick < cast.rebate_at:
		return
	unit.restore_mana(cast.rebate_mana)
	cast.ready_at = tick + cast.skill.rebate_cooldown_ticks
	cast.rebate_at = -1
	cast.rebate_mana = 0.0


static func validate(skill: PBSkill) -> String:
	if (
		not is_finite(skill.rebate_mana_scale)
		or skill.rebate_mana_scale < 0.0
		or skill.rebate_mana_scale > 1.0
		or skill.rebate_delay_ticks < 0
		or skill.rebate_cooldown_ticks < 0
	):
		return "返蓝比例须为 0–1，返蓝延迟 / 冷却不能为负"
	if skill.rebate_delay_ticks == 0:
		return (
			"返蓝 / 冷却设置必须指定延迟"
			if skill.rebate_mana_scale > 0.0 or skill.rebate_cooldown_ticks > 0
			else ""
		)
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.hit_count != 1
		or skill.shot_cross_seconds > 0.0
		or skill.rebate_cooldown_ticks <= 0
		or skill.rebate_delay_ticks >= skill.cooldown_ticks
	):
		return "延迟返蓝只支持单段地面技能，需正重设冷却，且延迟短于基础冷却"
	return ""
