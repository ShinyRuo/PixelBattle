class_name PBSkillCostRules
extends RefCounted
## 蓝量门槛、实际扣除和说明卡共用同一份等级查表。


static func mana(skill: PBSkill, level: int = 1) -> float:
	if skill.mp_cost_levels.is_empty():
		return skill.mp_cost
	return skill.mp_cost_levels[clampi(level - 1, 0, skill.mp_cost_levels.size() - 1)]


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.mp_cost) or skill.mp_cost < 0.0:
		return "耗蓝必须是有限非负数"
	for cost: float in skill.mp_cost_levels:
		if not is_finite(cost) or cost < 0.0:
			return "各级耗蓝必须是有限非负数"
	if not skill.mp_cost_levels.is_empty() and skill.mp_cost_levels[0] != skill.mp_cost:
		return "耗蓝表首项必须等于基础耗蓝"
	return ""
