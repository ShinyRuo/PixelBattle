class_name PBSacrificeRules
extends RefCounted
## 献祭赠送三围：先截取整数三围的 99%，再按转化率取整；所有受益者使用同一份快照。
## 倒计时是死亡指令，不是伤害，因此不吃闪避、护盾或伤害免疫。赠送值留到本波结束。


static func can_target(skill: PBSkill, target: PBAttacker, caster: PBAttacker) -> bool:
	if not target.is_targetable():
		return false
	return (
		not skill.sacrifice_transfer
		or (target != caster and not target.summoned and target.attribute_profile != null)
	)


static func land(
	cast: PBSkillCast, caster: PBAttacker, team: Array[PBAttacker], cfg: PBSimConfig, tick: int
) -> void:
	if caster == null or not caster.alive or caster.sacrifice_at >= 0:
		return
	var selected: PackedInt32Array = PBSkillTargets.allies(cast, team, caster)
	if selected.is_empty() or not can_target(cast.skill, team[selected[0]], caster):
		return
	var additions: Dictionary = {}
	var rate: float = (0.1 + 0.03 * cast.caster_level) * cast.skill.transfer_scale
	for key: StringName in [PBStatRules.STRENGTH, PBStatRules.AGILITY, PBStatRules.INTELLECT]:
		var owned: float = floorf(float(caster.damage_attributes.get(key, 0.0)))
		additions[key] = floorf(floorf(owned * 0.99) * rate + 0.0000001)
	for index: int in selected:
		if can_target(cast.skill, team[index], caster):
			grant(team[index], cast.skill, additions, caster.slot, cfg, tick)
	caster.sacrifice_at = tick + maxi(roundi(5.0 * cfg.tick_rate), 1)


static func grant(
	target: PBAttacker,
	skill: PBSkill,
	additions: Dictionary,
	source: int,
	cfg: PBSimConfig,
	tick: int
) -> void:
	if skill.transfer_buff == null:
		return
	PBTemporaryAttributeRules.bind_to(target, cfg)
	target.buffs.add(skill.transfer_buff, additions.duplicate(), tick, 0, 0, source)


static func expire(
	team: Array[PBAttacker], tick: int, book: PBBattleLog, out: PBCombatOutcome
) -> void:
	for caster: PBAttacker in team:
		if caster.sacrifice_at < 0 or tick < caster.sacrifice_at:
			continue
		caster.sacrifice_at = -1
		if not caster.alive:
			continue
		caster.hp = 0.0
		caster.alive = false
		caster.swinging = false
		if caster.channel != null:
			caster.channel.active = false
		PBStrikeRules.record_death(caster, tick, book, out)


static func validate(skill: PBSkill) -> String:
	var buff_error := _validate_buff(skill)
	if buff_error != "":
		return buff_error
	if not is_finite(skill.transfer_scale) or skill.transfer_scale <= 0.0:
		return "三围转化倍率必须为有限正数"
	if not skill.sacrifice_transfer:
		return "" if skill.transfer_scale == 1.0 else "只有献祭转化技能能配置三围转化倍率"
	if (
		skill.target != PBSkill.Target.ALLY
		or skill.affects != PBSkill.Party.ALLIES
		or skill.shot_cross_seconds != 0.0
		or skill.radius != 0.0
		or skill.delay_ticks != 0
		or not skill.on_hit.is_empty()
	):
		return "献祭转化只支持即时锁定队友，不能混用命中效果或范围伤害"
	return ""


static func _validate_buff(skill: PBSkill) -> String:
	if not skill.sacrifice_transfer:
		return "赠予 BUFF 只能用于献祭技能" if skill.transfer_buff != null else ""
	var buff := skill.transfer_buff
	if buff == null or not buff.until_wave_end or not buff.per_source:
		return "献祭技能需要按来源保存的整波赠予 BUFF"
	if not buff.mods_growth.is_empty() or not buff.mods_levels.is_empty():
		return "赠予 BUFF 的三围量由施法快照计算，不能配置成长"
	for key: StringName in buff.mods:
		if key not in [PBBuffRules.STRENGTH, PBBuffRules.AGILITY, PBBuffRules.INTELLECT]:
			return "赠予 BUFF 只支持三围快照"
		if float(buff.mods[key]) != 0.0:
			return "赠予 BUFF 的初始三围必须为零"
	return PBBuffRules.validate(buff)
