class_name PBEnemyAuraRules
extends RefCounted
## 忍者携带的敌方减益光环跟随本体；每 tick 刷新，离开 / 来源死亡只保留已有残留。
## 同名效果复用效果袋刷新规则，不因两个相同载体而重复叠加。


static func advance(
	team: Array[PBAttacker], enemies: Array[PBEnemy], cfg: PBSimConfig, tick: int
) -> void:
	for source: PBAttacker in team:
		if not source.is_targetable():
			continue
		for cast: PBSkillCast in source.skills:
			var skill := cast.skill
			if skill.enemy_aura_radius <= 0.0:
				continue
			for enemy: PBEnemy in enemies:
				if not enemy.has_spawned(tick):
					break
				if not enemy.is_hostile(tick):
					continue
				if source.pos.distance_to(enemy.pos()) > skill.enemy_aura_radius + 0.0000001:
					continue
				PBSkillRules.apply_all_enemy(
					enemy, skill.enemy_aura_effects, cast.caster_level, cfg, tick
				)


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.enemy_aura_radius) or skill.enemy_aura_radius < 0.0:
		return "敌方减益光环范围必须是有限非负数"
	if skill.enemy_aura_radius == 0.0:
		return "光环效果需要正范围" if not skill.enemy_aura_effects.is_empty() else ""
	if skill.enemy_aura_effects.is_empty() or skill.attack_trigger_chance <= 0.0:
		return "敌方光环必须附着于攻击被动，且有减益效果"
	for buff: PBBuff in skill.enemy_aura_effects:
		if (
			buff == null
			or buff.friendly
			or buff.kind != PBBuff.Kind.DURATION
			or buff.mods.has(PBBuffRules.HARM)
		):
			return "敌方光环只支持无直接伤害的持续减益"
	return ""
