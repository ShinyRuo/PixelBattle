class_name PBAttributeRules
extends RefCounted
## 战斗内三围变动统一入口。保留当前血蓝比例和已有攻防倍率，不重置出手 / 技能冷却。
## 下一波回基线；已经飞出去的伤害快照不回写，后续技能与属性效果读取新属性。


static func grant(target: PBAttacker, additions: Dictionary, cfg: PBSimConfig) -> bool:
	var profile: PBAttributeProfile = target.attribute_profile
	if profile == null or not target.is_targetable():
		return false
	for key: StringName in [PBStatRules.STRENGTH, PBStatRules.AGILITY, PBStatRules.INTELLECT]:
		profile.received[key] = (
			float(profile.received.get(key, 0.0)) + float(additions.get(key, 0.0))
		)
	_refresh(target, profile.stats(cfg), cfg)
	return true


static func reset(target: PBAttacker, cfg: PBSimConfig) -> void:
	target.sacrifice_at = -1
	var profile: PBAttributeProfile = target.attribute_profile
	if profile == null or (profile.received.is_empty() and profile.temporary.is_empty()):
		return
	profile.received.clear()
	profile.temporary.clear()
	_refresh(target, profile.stats(cfg), cfg)


static func set_temporary(target: PBAttacker, additions: Dictionary, cfg: PBSimConfig) -> void:
	var profile := target.attribute_profile
	if profile == null or profile.temporary == additions:
		return
	profile.temporary = additions
	_refresh(target, profile.stats(cfg), cfg)


static func _refresh(target: PBAttacker, values: PBStats, cfg: PBSimConfig) -> void:
	var profile: PBAttributeProfile = target.attribute_profile
	var before: PBStats = profile.current
	target.attack *= _ratio(values.atk, before.atk)
	target.dps *= _ratio(values.dps(), before.dps())
	target.base_attack += values.base_atk - before.base_atk
	target.ninjutsu_attack *= _ratio(values.intellect, before.intellect)
	target.defence += values.def - before.def
	target.attack_speed *= _ratio(values.attack_speed, before.attack_speed)
	var hp_ratio: float = _ratio(values.hp, before.hp)
	var mp_ratio: float = _ratio(values.mp, before.mp)
	target.max_hp *= hp_ratio
	target.hp *= hp_ratio
	target.max_mp *= mp_ratio
	target.mp *= mp_ratio
	target.mp_regen *= mp_ratio
	target.damage_attributes = {
		&"strength": values.strength,
		&"agility": values.agility,
		&"intellect": values.intellect,
		&"attack": values.atk,
		&"max_hp": target.max_hp,
	}
	for i: int in PBSkillRules.cast_count(target):
		var cast := PBSkillRules.cast_at(target, i)
		if cast != null:
			_refresh_skill(cast.opening_skill(), profile, before, values, cfg)
	for cast: PBSkillCast in target.death_casts:
		_refresh_skill(cast.skill, profile, before, values, cfg)
	for cast: PBSkillCast in target.attack_casts:
		_refresh_skill(cast.skill, profile, before, values, cfg)
	profile.current = values
	target.prime(cfg.tick_rate, cfg)


static func _refresh_skill(
	skill: PBSkill, profile: PBAttributeProfile, before: PBStats, values: PBStats, cfg: PBSimConfig
) -> void:
	var old_raw: float = PBSkillDamage.raw(skill, before, profile.level)
	var new_raw: float = PBSkillDamage.raw(skill, values, profile.level)
	if old_raw > 0.0:
		skill.damage *= new_raw / old_raw
	else:
		skill.damage = (
			new_raw
			* profile.team_mult
			* cfg.damage_multiplier(PBElement.relation(skill.element, profile.wave_element))
		)
	skill.first_cast_damage *= _ratio(values.atk, before.atk)
	if skill.followup != null:
		_refresh_skill(skill.followup, profile, before, values, cfg)
	if skill.recast != null:
		_refresh_skill(skill.recast, profile, before, values, cfg)


static func _ratio(after: float, before: float) -> float:
	return after / before if before > 0.0 else 1.0
