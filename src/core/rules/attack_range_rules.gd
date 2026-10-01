class_name PBAttackRangeRules
extends RefCounted
## 形态射程覆盖不改名册，准备射程圈与实战使用同一原版码数换算。
## 保留开战坐标；变远程不会把已经摆好的单位搬到后排。


static func apply(unit: PBAttacker, cfg: PBSimConfig) -> void:
	if unit.ranged_range <= 0.0:
		return
	unit.ranged_attack = true
	unit.reach = cfg.units_to_field(unit.ranged_range)
	unit.shot_speed = cfg.field_length / maxf(cfg.projectile_cross_seconds * cfg.tick_rate, 1.0)


static func preview(
	unit: PBUnit, state: PBRunState, cfg: PBSimConfig, deployed: Array[PBUnit]
) -> float:
	if not deployed.has(unit):
		return cfg.reach_of(unit.character)
	var passives := PBBondRules.active_passives(state.bonded_units(cfg, true), deployed, cfg.bonds)
	var mods := PBCombatRules.unit_mods(deployed, state, cfg, true)
	var own: Dictionary = passives.get(unit.character.id, {})
	var amount: float = maxf(
		float(unit.character.passives.get(PBPassiveRules.RANGED_RANGE, 0.0)),
		float(own.get(PBPassiveRules.RANGED_RANGE, 0.0))
	)
	amount = maxf(amount, float(mods[deployed.find(unit)].get(PBPassiveRules.RANGED_RANGE, 0.0)))
	return cfg.units_to_field(amount) if amount > 0.0 else cfg.reach_of(unit.character)
