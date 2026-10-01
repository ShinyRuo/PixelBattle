class_name PBMindRules
extends RefCounted
## 主目标按单位等级决定眩晕或临时转化；追加目标只有独立计时的眩晕。
## 转化状态属于效果槽，覆盖、清除、到期或引导中断时立即恢复敌对。


static func apply(enemy: PBEnemy, shot: PBProjectile, cfg: PBSimConfig, tick: int) -> void:
	var buff: PBBuff = shot.skill.on_hit[0]
	var values: Dictionary = PBBuffRules.resolve(buff, shot.level)
	var duration: int = buff.duration_ticks(cfg, shot.level)
	if shot.primary_target and shot.level > enemy.level:
		values = {PBBuffRules.DOMINATED: 1.0}
	elif not shot.primary_target:
		duration = maxi(roundi(duration * shot.skill.extra_control_scale), 1)
	enemy.buffs.add(buff, values, tick, duration, 0, shot.source)
	if shot.primary_target:
		if shot.channel != null:
			shot.channel.attach(enemy, buff.id, tick, true)
		for state: PBBuffState in enemy.buffs.states():
			if state.buff == buff and state.applied_at == tick:
				enemy.control_ref = weakref(state) if values.has(PBBuffRules.DOMINATED) else null
				break
		enemy.swinging = false


static func any_controlled(enemies: Array[PBEnemy], tick: int) -> bool:
	for enemy: PBEnemy in enemies:
		if enemy.is_active(tick) and enemy.controlled(tick):
			return true
	return false


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.extra_control_scale) or skill.extra_control_scale < 1.0:
		return "追加控制时长倍率必须是大于等于 1 的有限数"
	if not skill.mind_control:
		return "" if skill.extra_control_scale == 1.0 else "追加控制倍率需要心灵控制技能"
	if (
		skill.channel_control
		or skill.target != PBSkill.Target.ENEMY
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.shot_cross_seconds <= 0.0
		or skill.radius != 0.0
		or skill.on_hit.size() != 1
		or skill.power_mult != 0.0
		or skill.damage_base != 0.0
		or skill.damage_growth != 0.0
		or skill.damage_hp != 0.0
		or skill.target_hp != 0.0
		or skill.first_cast_attack != 0.0
	):
		return "心灵控制需要锁定敌方弹道与一份独立持续控制效果"
	var buff: PBBuff = skill.on_hit[0]
	if buff.kind != PBBuff.Kind.DURATION or not buff.mods.has(PBBuffRules.STUN):
		return "心灵控制的默认效果必须是持续眩晕"
	return ""
