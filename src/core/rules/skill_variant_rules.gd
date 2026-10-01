class_name PBSkillVariantRules
extends RefCounted
## 羁绊替换整套技能机制，保留按钮身份与本体耗蓝 / 冷却。准备与实战共用此入口。
## 变体不能继续引用变体；基础资源与变体资源都不被修改。


static func prepare(
	original: PBSkill, patch: Dictionary, cfg: PBSimConfig, level: int = 1
) -> PBSkill:
	var chosen: PBSkill = original
	if float(patch.get(PBSkillPatchRules.VARIANT_ENABLE, 0.0)) > 0.0:
		chosen = cfg.skills.by_id(original.variant_id)
		if chosen == null:
			chosen = original
	var copy := chosen.clone()
	copy.id = original.id
	copy.variant_art_id = chosen.id if chosen != original else &""
	copy.name_key = (
		chosen.name_key if chosen != original and original.variant_first else original.name_key
	)
	copy.mp_cost = original.mp_cost
	copy.mp_cost_levels = original.mp_cost_levels.duplicate()
	copy.cooldown_ticks = original.cooldown_ticks
	copy.hit_count = copy.hits_at(level)
	copy.hit_count_levels = PackedInt32Array()
	PBSkillPatchRules.apply(copy, patch, cfg.tick_rate)
	if chosen != original and original.variant_first:
		var normal := original.clone()
		normal.variant_id = &""
		normal.variant_first = false
		normal.hit_count = normal.hits_at(level)
		normal.hit_count_levels = PackedInt32Array()
		PBSkillPatchRules.apply(normal, patch, cfg.tick_rate)
		normal.variant_enabled = false
		copy.recast = normal
	return copy


static func check_link(skill: PBSkill, table: PBSkillTable) -> String:
	if skill.variant_id == &"":
		return "首次变体必须指定变体技能" if skill.variant_first else ""
	var other := table.by_id(skill.variant_id)
	if other == null or other == skill:
		return "技能变体不存在或引用自身"
	if (
		other.variant_id != &""
		or other.target != skill.target
		or other.affects != skill.affects
		or other.mp_cost != 0.0
		or not other.mp_cost_levels.is_empty()
		or other.cooldown_ticks != 0
		or (skill.variant_first and (skill.target != PBSkill.Target.GROUND or skill.hit_count < 2))
	):
		return "变体须保持指令目标类型，不可链式引用或有独立耗蓝 / 冷却"
	return ""
