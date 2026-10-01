extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(level: int = 10, bonded: bool = true, outer: bool = false) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"onoki"))
	unit.level = level
	var roster: Array[PBUnit] = [unit]
	if bonded:
		for id: StringName in [&"tsunade", &"gaara", &"mei", &"raikage"]:
			roster.append(PBUnit.new(_cfg.characters.by_id(id)))
	if outer:
		roster.append(PBUnit.new(_cfg.characters.by_id(&"kurotsuchi")))
	var patches := PBBondRules.active_skill_patches(roster, [unit], _cfg.bonds)
	var team := PBCombatRules.build_attackers(
		[unit], PBElement.Type.WIND, 1.0, PackedFloat64Array(), _cfg, null, 1, 0, {}, {}, patches
	)
	var one: PBAttacker = team[0]
	one.ultimate = null
	one.mp_regen = 0.0
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_real_bond_refunds_half_cost_only_after_landing_delay_at_every_level() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var sim := _sim(one)
		var cost: float = 2.0 + 8.0 * level
		var before: float = one.mp
		assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
		for tick: int in 19:
			sim.step()
		assert_almost_eq(one.mp, before - cost, 0.0001)
		assert_eq(one.skills[0].ready_at, 358)
		sim.step()
		assert_almost_eq(one.mp, before - cost * 0.5, 0.0001)
		assert_eq(one.skills[0].ready_at, 50)
		for tick: int in 29:
			sim.step()
		assert_false(sim.can_cast(one, 1))
		sim.step()
		assert_true(sim.can_cast(one, 1))
		assert_almost_eq(one.mp, before - cost * 0.5, 0.0001)


func test_unbonded_caster_keeps_normal_cost_and_cooldown() -> void:
	var one := _caster(10, false)
	var sim := _sim(one)
	var before: float = one.mp
	assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
	for tick: int in 45:
		sim.step()
	assert_eq(one.mp, before - 82.0)
	assert_eq(one.skills[0].ready_at, 358)
	assert_false(sim.can_cast(one, 1))


func test_two_bonds_combine_without_mutating_shared_skill() -> void:
	var one := _caster(10, true, true)
	var skill: PBSkill = one.skills[0].skill
	assert_almost_eq(skill.radius, 0.255, 0.000001)
	assert_eq(skill.outer_damage_scale, 0.6)
	assert_eq(skill.rebate_mana_scale, 0.5)
	assert_eq(skill.rebate_delay_ticks, 2)
	assert_eq(PBSkillRebateRules.validate(skill), "")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg, 10), "返还 41 蓝")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg, 10), "1.5 秒")
	assert_eq(_cfg.skills.by_id(&"dust_release").rebate_delay_ticks, 0)


func test_refund_is_capped_dead_caster_stays_dead_and_new_wave_clears_pending() -> void:
	var one := _caster()
	var cast: PBSkillCast = one.skills[0]
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	cast.land(12)
	one.mp = one.max_mp - 1.0
	PBSkillRebateRules.advance(one, cast, 14)
	assert_eq(one.mp, one.max_mp)
	cast.land(50)
	one.alive = false
	one.mp = 0.0
	PBSkillRebateRules.advance(one, cast, 52)
	assert_eq(one.mp, 0.0)
	assert_false(one.alive)
	cast.land(100)
	_sim(one)
	assert_eq(cast.rebate_at, -1)
	assert_eq(cast.rebate_mana, 0.0)


func test_empty_cast_still_refunds_once_and_second_cast_schedules_new_refund() -> void:
	var one := _caster()
	var sim := _sim(one)
	var before: float = one.mp
	assert_true(sim.cast_skill(one, Vector2(0.01, 0.0), 1))
	for tick: int in 50:
		sim.step()
	assert_eq(one.mp, before - 41.0)
	assert_true(sim.cast_skill(one, Vector2(0.01, 0.0), 1))
	for tick: int in 20:
		sim.step()
	assert_eq(one.mp, before - 82.0)
	assert_eq(one.skills[0].ready_at, 100)


func test_invalid_rebate_configuration_is_rejected() -> void:
	var skill := _caster().skills[0].skill
	for value: float in [-1.0, 1.1, INF, NAN]:
		var copy := skill.clone()
		copy.rebate_mana_scale = value
		assert_ne(PBSkillRebateRules.validate(copy), "")
	var copy := skill.clone()
	copy.rebate_delay_ticks = 0
	assert_ne(PBSkillRebateRules.validate(copy), "")
	copy = skill.clone()
	copy.target = PBSkill.Target.ENEMY
	assert_ne(PBSkillRebateRules.validate(copy), "")
