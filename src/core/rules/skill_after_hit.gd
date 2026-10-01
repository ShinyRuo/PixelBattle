class_name PBSkillAfterHit
extends RefCounted
## 先完成主伤害（含护盾 / 易伤），再按剩余生命计算第二笔。沿用本段的增伤与暴击结果。


static func land(
	cast: PBSkillCast,
	enemy: PBEnemy,
	rolled: float,
	caster: PBAttacker,
	cfg: PBSimConfig,
	tick: int,
	book: PBBattleLog,
	crit: bool
) -> bool:
	var skill := cast.skill
	if skill.target_current_hp <= 0.0 or not enemy.alive:
		return false
	if skill.target_nonhero_only and enemy.is_hero:
		return false
	var fixed: float = skill.damage_base + skill.damage_growth * (cast.caster_level - 1)
	var raw: float = enemy.hp * skill.target_current_hp * rolled / fixed
	var dealt := PBStrikeRules.mitigated(caster, enemy, raw, skill.kind, cfg, tick)
	if book != null:
		book.hit(tick, -1 if caster == null else caster.slot, enemy.slot, dealt, false, crit)
	return enemy.take_damage(dealt, tick, null, false, skill.element)


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.target_current_hp) or skill.target_current_hp < 0.0:
		return "后续当前生命附伤必须为有限非负比例"
	if skill.target_current_hp == 0.0:
		return "非英雄限制需要当前生命附伤" if skill.target_nonhero_only else ""
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.damage_base <= 0.0
		or skill.power_mult != 0.0
		or skill.damage_hp != 0.0
		or skill.target_hp != 0.0
		or skill.center_scale != 1.0
		or skill.damage_cap != 0.0
	):
		return "后续当前生命附伤仅支持正固定基数的地面敌方伤害，不混合其他生命公式"
	return ""
