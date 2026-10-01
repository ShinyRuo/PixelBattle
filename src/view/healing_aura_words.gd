class_name PBHealingAuraWords
extends RefCounted


static func body(skill: PBSkill, cfg: PBSimConfig, level: int) -> String:
	var scope: String = (
		"仅自身"
		if skill.radius <= 0.0
		else ("周围友军（含自身），范围 %.0f 码" % (skill.radius * cfg.war3_units_per_field))
	)
	var lines := PackedStringArray(["常驻治疗　" + scope])
	var flat: float = skill.heal_aura_flat + skill.heal_aura_growth * maxi(level - 1, 0)
	if flat > 0.0:
		lines.append("每秒恢复 %.0f 点生命" % (flat * skill.heal_scale))
	if skill.heal_aura_max > 0.0:
		lines.append("每秒恢复最大生命的 %.1f%%" % (skill.heal_aura_max * skill.heal_scale * 100.0))
	lines.append("每 %.2f 秒结算一次" % (float(skill.heal_aura_period_ticks) / cfg.tick_rate))
	if skill.heal_aura_hit_chance > 0.0:
		lines.append(
			(
				"受到普攻起手时 %.0f%% 概率恢复 %.0f%% 已损生命，先回复再承受该次攻击"
				% [skill.heal_aura_hit_chance * 100.0, skill.heal_aura_lost * 100.0]
			)
		)
	lines.append("同名光环取最高；离圈或载体倒下即失效\n不耗蓝，无需施放")
	return "\n".join(lines)
