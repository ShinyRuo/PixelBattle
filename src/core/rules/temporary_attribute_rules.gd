class_name PBTemporaryAttributeRules
extends RefCounted
## 百分比三围在施加时折成点数快照，刷新同名效果时扣除旧份，避免自己越叠越大。
## 生效 / 到期统一回到属性派生入口，血量保持比例，既不白送治疗也不因到期击杀。


static func prepare(
	unit: PBAttacker, buff: PBBuff, mods: Dictionary, cfg: PBSimConfig, tick: int
) -> Dictionary:
	bind_to(unit, cfg)
	if not mods.has(PBBuffRules.STRENGTH_BONUS) and not mods.has(PBBuffRules.ALL_STATS_BONUS):
		return mods
	refresh(unit, cfg, tick)
	var values := mods.duplicate()
	for key: StringName in [PBBuffRules.STRENGTH, PBBuffRules.AGILITY, PBBuffRules.INTELLECT]:
		var rate: float = float(mods.get(PBBuffRules.ALL_STATS_BONUS, 0.0))
		if key == PBBuffRules.STRENGTH:
			rate += float(mods.get(PBBuffRules.STRENGTH_BONUS, 0.0))
		if rate <= 0.0:
			continue
		var base: float = float(unit.damage_attributes.get(key, 0.0))
		for state: PBBuffState in unit.buffs.states():
			if state.is_live(tick) and state.buff.id == buff.id:
				base -= float(state.mods.get(key, 0.0))
		values[key] = float(values.get(key, 0.0)) + floorf(floorf(maxf(base, 0.0)) * rate)
	values.erase(PBBuffRules.STRENGTH_BONUS)
	values.erase(PBBuffRules.ALL_STATS_BONUS)
	return values


static func bind_to(unit: PBAttacker, cfg: PBSimConfig) -> void:
	if cfg != null:
		unit.buffs.on_changed = _on_changed.bind(weakref(unit), cfg)


static func _on_changed(tick: int, owner: WeakRef, cfg: PBSimConfig) -> void:
	var unit := owner.get_ref() as PBAttacker
	if unit != null:
		refresh(unit, cfg, tick)


static func refresh(unit: PBAttacker, cfg: PBSimConfig, tick: int) -> void:
	var reach_bonus := cfg.units_to_field(unit.buffs.amount(PBBuffRules.REACH_BONUS, tick))
	unit.reach += reach_bonus - unit.temporary_reach_bonus
	unit.temporary_reach_bonus = reach_bonus
	if unit.attribute_profile == null:
		return
	var additions: Dictionary = {}
	for key: StringName in [PBBuffRules.STRENGTH, PBBuffRules.AGILITY, PBBuffRules.INTELLECT]:
		var value: float = unit.buffs.amount(key, tick)
		if value != 0.0:
			additions[key] = value
	PBAttributeRules.set_temporary(unit, additions, cfg)


static func validate(buff: PBBuff) -> String:
	for key: StringName in [
		PBBuffRules.STRENGTH,
		PBBuffRules.AGILITY,
		PBBuffRules.INTELLECT,
		PBBuffRules.STRENGTH_BONUS,
		PBBuffRules.ALL_STATS_BONUS,
		PBBuffRules.REACH_BONUS
	]:
		if not buff.mods.has(key):
			continue
		if not buff.friendly or buff.kind != PBBuff.Kind.DURATION:
			return "临时三围只支持己方持续效果"
		var values: Array = [buff.mods[key], buff.mods_growth.get(key, 0.0)]
		values.append_array(Array(buff.mods_levels.get(key, PackedFloat32Array())))
		for value: float in values:
			if not is_finite(value) or value < 0.0:
				return "临时三围值与成长必须为有限非负数"
	return ""
