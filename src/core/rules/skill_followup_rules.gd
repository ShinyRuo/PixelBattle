class_name PBSkillFollowupRules
extends RefCounted
## 附加招式与主技能共享一次耗蓝 / 冷却，但保留自己的伤害、时序和命中效果。
## 表里只存外键；战斗实例在建队时解析并复制。不允许链式引用，避免循环及重复触发。


static func validate(skill: PBSkill) -> String:
	if skill.followup_enabled and skill.followup_id == &"":
		return "附加招式已启用但没有指定技能"
	if skill.followup_id == &"":
		return ""
	if (
		skill.followup_id == skill.id
		or skill.shot_cross_seconds != 0.0
		or skill.hit_count != 1
		or skill.target not in [PBSkill.Target.ENEMY, PBSkill.Target.NONE, PBSkill.Target.GROUND]
	):
		return "附加招式只支持非弹道单段锁定 / 自身 / 地面技能，不能引用自身"
	return ""


static func check_link(skill: PBSkill, table: PBSkillTable) -> String:
	if skill.followup_id == &"":
		return ""
	var child := table.by_id(skill.followup_id)
	if child == null:
		return "附加招式不存在：%s" % skill.followup_id
	if (
		child.followup_id != &""
		or child.target != PBSkill.Target.GROUND
		or child.affects != PBSkill.Party.ENEMIES
		or child.mp_cost != 0.0
		or not child.mp_cost_levels.is_empty()
		or child.cooldown_ticks != 0
	):
		return "附加招式须为无独立冷却 / 耗蓝的地面敌方技能，不能继续附加招式"
	return ""


static func prepare(
	original: PBSkillCast, caster: PBAttacker, enemies: Array[PBEnemy], tick: int
) -> PBSkillCast:
	if not original.skill.followup_enabled or original.skill.followup == null:
		return null
	var center: Vector2 = (
		original.spot if original.skill.target == PBSkill.Target.GROUND else caster.pos
	)
	if original.skill.target == PBSkill.Target.ENEMY:
		var found: bool = false
		for enemy: PBEnemy in enemies:
			if enemy.slot == original.target_slot and enemy.is_hostile(tick):
				center = enemy.pos()
				found = true
				break
		if not found:
			return null
	var out := PBSkillCast.new(original.skill.followup.clone(), original.caster_level)
	out.spot = center
	out.origin = caster.pos
	return out
