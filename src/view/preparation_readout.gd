class_name PBPreparationReadout
extends RefCounted
## 准备属性使用真实建队与派生公式，不再只显示裸装名册数值。不推进模拟、不消费随机流。
## 只在面板刷新时构建；战斗逐帧读数仍由 PBLiveReadout 负责。


static func of(
	unit: PBUnit, state: PBRunState, cfg: PBSimConfig, wave: PBWave, deployed: Array[PBUnit]
) -> PBStats:
	if not deployed.has(unit):
		return unit.stats(cfg)
	var team: Array[PBUnit] = deployed
	var counted := state.bonded_units(cfg, true)
	var functions := PBBondRules.active_functions(counted, team, cfg.bonds)
	var passives := PBBondRules.active_passives(counted, team, cfg.bonds)
	var patches := PBBondRules.active_skill_patches(counted, team, cfg.bonds)
	var attackers := PBCombatRules.build_attackers(
		team,
		wave.element,
		1.0,
		PBCombatRules.unit_multipliers(team, state, cfg),
		cfg,
		PBBeastRules.beast_of(state, cfg),
		state.beast_level,
		0,
		functions,
		passives,
		patches,
		PBCombatRules.unit_mods(team, state, cfg, true)
	)
	PBFormationRules.apply(attackers, team, state.formation, cfg)
	for one: PBAttacker in attackers:
		if not one.summoned:
			one.prime(cfg.tick_rate, cfg)
			one.revive()
	PBAllyAuraRules.install(attackers)
	PBMotionAuraRules.install(attackers)
	var stats := unit.stats(cfg)
	PBLiveReadout.update(stats, attackers[team.find(unit)], cfg, 0)
	return stats
