class_name PBOnAttackWords
extends RefCounted
## 攻击触发技能的说明共用于技能卡与授予它的羁绊卡。


static func body(skill: PBSkill, cfg: PBSimConfig, level: int) -> String:
	var chance: String = (
		"普攻起手时 %.0f%% 概率触发" % (skill.attack_trigger_chance * 100.0)
		if skill.attack_trigger_chance > 0.0
		else "由羁绊解锁的攻击起手被动"
	)
	var own: String = ""
	if skill.self_attack_bonus > 0.0 or skill.self_attack_bonus_growth > 0.0:
		own = (
			"\n当前等级：自身基础攻击 +%.0f%%"
			% (
				(skill.self_attack_bonus + skill.self_attack_bonus_growth * maxi(level - 1, 0))
				* 100.0
			)
		)
	return "%s\n%s%s\n不耗蓝，无需施放" % [chance, details(skill, cfg), own]


static func details(skill: PBSkill, cfg: PBSimConfig) -> String:
	if skill.attack_repeat_count > 0:
		return (
			("立即对当前目标额外普攻 %d 次，每次使用当前攻击力\n" + "沿用普攻伤害类型、属性克制、暴击和命中效果；目标倒下即停止")
			% skill.attack_repeat_count
		)
	var words := PackedStringArray()
	if skill.target == PBSkill.Target.ENEMY:
		words.append("额外伤害仅作用于当前攻击目标，不是普攻暴击")
	else:
		words.append(
			(
				"从攻击目标向前，每 %.3f 距离一个圆，共 %d 圈，各圈半径 %.2f；相交处可重复受伤"
				% [skill.attack_chain_step, skill.attack_chain_count, skill.radius]
			)
		)
	var stat: String = (
		{&"strength": "力量", &"agility": "敏捷", &"intellect": "智力", &"attack": "攻击力"}
		. get(PBSkillDamage.stat_of(skill), "属性")
	)
	var formula: String = "%s ×%.2f" % [stat, skill.power_mult]
	if skill.damage_stat_floor:
		formula = "整数" + formula
	if skill.damage_base > 0.0 or skill.damage_growth > 0.0:
		formula = "%.0f + %.0f×（等级−1）" % [skill.damage_base, skill.damage_growth]
		if skill.power_mult > 0.0:
			formula += " + %s ×%.2f" % [stat, skill.power_mult]
	words.append(
		(
			"%s%s %s伤害（%s属性）"
			% [
				"每圈 " if skill.attack_chain_count > 0 else "",
				formula,
				"体术" if skill.kind == PBDamageKind.Type.TAIJUTSU else "忍术",
				(
					"物理"
					if skill.element == PBElement.Type.PHYSICAL
					else PBUnitTile.ELEMENT_NAMES.get(skill.element, "?")
				)
			]
		)
	)
	for buff: PBBuff in skill.on_primary:
		words.append(
			(
				"仅主目标：%s（%.1f 秒）"
				% [PBLocale.text(buff.name_key), float(buff.duration_ticks(cfg)) / cfg.tick_rate]
			)
		)
	if skill.self_attack_bonus > 0.0 or skill.self_attack_bonus_growth > 0.0:
		words.append(
			(
				"自身基础攻击 +%.0f%%，每级再 +%.0f%%；不放大装备直接攻击"
				% [skill.self_attack_bonus * 100.0, skill.self_attack_bonus_growth * 100.0]
			)
		)
	if skill.enemy_aura_radius > 0.0:
		words.append("携带减益光环，范围 %.2f；随自身移动，倒下后停止刷新" % skill.enemy_aura_radius)
		for buff: PBBuff in skill.enemy_aura_effects:
			words.append(PBEffectWords.buff_line(buff, 1))
	return "\n".join(words)
