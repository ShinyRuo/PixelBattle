class_name PBSkillImpact
extends RefCounted
## 主弹道命中位置决定附加控制范围；不连锁、不重挂主目标，也不扩散伤害。


static func validate(skill: PBSkill) -> String:
	var channel_error := PBSkillChannel.validate(skill)
	if channel_error != "":
		return channel_error
	var radius: float = skill.impact_hold_radius
	var seconds: float = skill.impact_hold_seconds
	if not is_finite(radius) or not is_finite(seconds) or radius < 0.0 or seconds < 0.0:
		return "弹道附加禁锢的半径和时间必须是有限非负数"
	if radius == 0.0 and seconds == 0.0:
		return ""
	if radius == 0.0 or seconds == 0.0:
		return "弹道附加禁锢必须同时配置半径和时间"
	if skill.target != PBSkill.Target.ENEMY or skill.shot_cross_seconds <= 0.0:
		return "弹道附加禁锢只支持锁定敌人的技能弹道"
	return ""


static func hold_neighbors(
	primary: PBEnemy,
	skill: PBSkill,
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	channel: PBSkillChannel = null
) -> void:
	if skill.impact_hold_radius <= 0.0 or skill.impact_hold_seconds <= 0.0:
		return
	var buff := PBBuff.new()
	buff.id = StringName("%s_impact_hold" % skill.id)
	buff.kind = PBBuff.Kind.DURATION
	buff.friendly = false
	buff.duration_seconds = skill.impact_hold_seconds
	buff.mods = {PBBuffRules.STUN: 1.0, PBBuffRules.ENEMY_SPEED_SCALE: 0.0}
	for enemy: PBEnemy in enemies:
		if enemy == primary or not enemy.is_hostile(tick):
			continue
		if enemy.pos().distance_to(primary.pos()) <= skill.impact_hold_radius:
			PBSkillRules.apply_all_enemy(enemy, [buff], 1, cfg, tick)
			if channel != null:
				channel.attach(enemy, buff.id, tick)
