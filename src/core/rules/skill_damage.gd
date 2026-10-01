class_name PBSkillDamage
extends RefCounted
## 技能的属性公式；不处理攻速、克制、暴击和防御。固定基数按技能等级成长。
## 特殊技能可以明确指定属性，伤害类型仍由施法者攻击属性决定。

const STATS: Array[StringName] = [&"", &"attack", &"intellect", &"agility", &"strength", &"max_hp"]


static func stat_of(skill: PBSkill) -> StringName:
	if skill.damage_stat != &"":
		return skill.damage_stat
	return &"intellect" if skill.kind == PBDamageKind.Type.NINJUTSU else &"attack"


static func raw(skill: PBSkill, stats: PBStats, level: int) -> float:
	var values: Dictionary = {
		&"attack": stats.atk,
		&"intellect": stats.intellect,
		&"agility": stats.agility,
		&"strength": stats.strength,
		&"max_hp": stats.hp,
	}
	var fixed: float = skill.damage_base + skill.damage_growth * float(maxi(level - 1, 0))
	var attribute: float = float(values[stat_of(skill)])
	if skill.damage_stat_floor:
		attribute = floorf(attribute)
	return maxf(fixed + attribute * skill.power_mult + stats.hp * skill.damage_hp, 0.0)


static func validate(skill: PBSkill) -> String:
	if (
		skill.blink_to_target
		and (skill.target != PBSkill.Target.ENEMY or skill.shot_cross_seconds > 0.0)
	):
		return "目标闪烁只支持非弹道锁定敌人技能"
	if (
		not skill.on_target.is_empty()
		and (
			skill.target != PBSkill.Target.ENEMY
			or skill.radius <= 0.0
			or skill.shot_cross_seconds > 0.0
		)
	):
		return "主目标效果只支持非弹道的锁定敌人范围技能"
	if (
		skill.death_move_ticks < 0
		or (skill.death_move_ticks > 0 and skill.target != PBSkill.Target.GROUND)
	):
		return "阵亡移动时长不能为负，且仅支持地面技能"
	if not STATS.has(skill.damage_stat):
		return "不认识的伤害基数：%s" % skill.damage_stat
	for value: float in [skill.power_mult, skill.damage_base, skill.damage_growth, skill.damage_hp]:
		if not is_finite(value) or value < 0.0:
			return "伤害系数和基数必须为非负有限数"
	var start_error: String = _validate_start(skill)
	return _validate_area(skill) if start_error.is_empty() else start_error


static func _validate_start(skill: PBSkill) -> String:
	if skill.on_start_target.is_empty():
		return _validate_echo(skill)
	if (
		skill.target != PBSkill.Target.ENEMY
		or skill.delay_ticks <= 0
		or skill.shot_cross_seconds > 0.0
	):
		return "主目标起手效果需要有延迟的非弹道锁定技能"
	for buff: PBBuff in skill.on_start_target:
		if buff == null or buff.friendly or buff.kind != PBBuff.Kind.DURATION:
			return "主目标起手效果只支持敌方持续状态"
	return _validate_echo(skill)


static func _validate_echo(skill: PBSkill) -> String:
	if skill.echo_delay_ticks < 0 or not is_finite(skill.echo_radius_scale):
		return "延后伤害参数必须有限，延迟不能为负"
	if skill.echo_delay_ticks == 0:
		return "没有延后伤害时不能配置范围倍率" if skill.echo_radius_scale != 1.0 else ""
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.hit_count != 1
		or skill.line_length != 0.0
		or skill.radius <= 0.0
		or skill.echo_radius_scale <= 0.0
		or skill.echo_delay_ticks <= skill.delay_ticks
	):
		return "延后伤害须晚于首击，只支持有正半径的单段地面圆形敌方技能"
	return ""


## 原始公式先做中心衰减和封顶，再沿用本次攻击已经算好的倍率；不再掷暴击。
static func area_damage(cast: PBSkillCast, enemy: PBEnemy, rolled: float) -> float:
	var skill := cast.skill
	if (
		skill.full_damage_radius > 0.0
		and enemy.pos().distance_to(cast.spot) > skill.full_damage_radius + 0.0000001
	):
		rolled *= skill.outer_damage_scale
	if skill.target_hp == 0.0 and skill.center_scale == 1.0 and skill.damage_cap == 0.0:
		return rolled
	var fixed: float = skill.damage_base + skill.damage_growth * float(cast.caster_level - 1)
	var edge: float = clampf(enemy.pos().distance_to(cast.spot) / skill.radius, 0.0, 1.0)
	var raw: float = (fixed + enemy.max_hp * skill.target_hp) * lerpf(skill.center_scale, 1.0, edge)
	if skill.damage_cap > 0.0:
		raw = minf(raw, skill.damage_cap)
	return rolled * raw / fixed


static func _validate_area(skill: PBSkill) -> String:
	var ring_error := _validate_ring(skill)
	if not ring_error.is_empty():
		return ring_error
	for value: float in [skill.target_hp, skill.center_scale, skill.damage_cap]:
		if not is_finite(value) or value < 0.0:
			return "范围伤害参数必须为非负有限数"
	if skill.target_hp == 0.0 and skill.center_scale == 1.0 and skill.damage_cap == 0.0:
		return ""
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.affects != PBSkill.Party.ENEMIES
		or not is_finite(skill.radius)
		or skill.radius <= 0.0
		or skill.center_scale < 1.0
		or skill.damage_base <= 0.0
		or skill.power_mult != 0.0
		or skill.damage_hp != 0.0
	):
		return "目标生命与中心衰减仅支持有正半径、正固定基数的地面敌方技能"
	return ""


static func _validate_ring(skill: PBSkill) -> String:
	for value: float in [skill.full_damage_radius, skill.outer_damage_scale]:
		if not is_finite(value) or value < 0.0:
			return "内外圈伤害参数必须为有限非负数"
	if skill.full_damage_radius == 0.0:
		return "外圈伤害倍率需要正内圈半径" if skill.outer_damage_scale != 1.0 else ""
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.affects != PBSkill.Party.ENEMIES
		or not is_finite(skill.radius)
		or skill.radius < skill.full_damage_radius
		or skill.line_length != 0.0
		or skill.pulse_radius_step != 0.0
		or skill.outer_damage_scale > 1.0
	):
		return "内外圈仅支持圆形地面敌方技能，内圈不能大于外圈，外圈伤害不能超过全额"
	return ""
