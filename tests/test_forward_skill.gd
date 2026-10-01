extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(enabled: bool = true) -> PBAttacker:
	var patches: Dictionary = {}
	if enabled:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"my_cage":
				patches = bond.member_skill_patches
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[PBUnit.new(_cfg.characters.by_id(&"jugo"))],
			PBElement.Type.PHYSICAL,
			1.0,
			PackedFloat64Array(),
			_cfg,
			null,
			1,
			0,
			{},
			{},
			patches
		)[0]
	)
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"piston_fist":
			one.skills = [cast]
			break
	one.pos = Vector2(0.2, 0.0)
	one.ultimate = null
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 4
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for i: int in sim.enemies().size():
		var enemy := sim.enemies()[i]
		enemy.distance = 0.2 + 0.15 * i
		enemy.speed = 0.0
		enemy.armor = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_real_bond_adds_three_forward_pulses_with_independent_hit_checks() -> void:
	var one := _caster()
	var sim := _sim(one)
	var mana: float = one.mp
	assert_true(sim.cast_skill_now(one, 1))
	PBCastTestClock.release(sim, one)
	var sequence := sim.barrages()[0]
	assert_eq(sequence.fired, 1)
	assert_eq(sequence.cast.spot, Vector2(0.2, 0.0))
	assert_lt(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	assert_eq(sim.enemies()[3].hp, sim.enemies()[3].max_hp)
	for pulse: int in range(1, 4):
		for i: int in 5:
			sim.step()
		assert_eq(sequence.fired, pulse + 1)
		assert_almost_eq(sequence.cast.spot.x, 0.2 + 0.15 * pulse, 0.0001)
	assert_lt(sim.enemies()[3].hp, sim.enemies()[3].max_hp)
	assert_eq(sim.enemies()[3].buffs.amount(PBBuffRules.AIRBORNE, 21), 1.0)
	assert_false(sequence.active())
	assert_eq(one.mp, mana - one.skills[0].skill.mp_cost)
	assert_eq(sim._slow_until, -1)


func test_power_boost_applies_to_each_pulse_without_mutating_shared_skill() -> void:
	var base := _caster(false).skills[0].skill
	var boosted := _caster().skills[0].skill
	assert_almost_eq(boosted.damage, base.damage * 1.5, 0.0001)
	assert_eq(boosted.hit_count, 4)
	assert_eq(boosted.hit_interval_ticks, 5)
	assert_eq(boosted.kind, PBDamageKind.Type.TAIJUTSU)
	assert_eq(boosted.element, PBElement.Type.PHYSICAL)
	assert_eq(_cfg.skills.by_id(&"piston_fist").hit_count, 1)
	assert_eq(_cfg.skills.by_id(&"piston_fist").hit_step, 0.0)


func test_propagation_keeps_original_direction_after_caster_moves_and_dies() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill_now(one, 1)
	PBCastTestClock.release(sim, one)
	one.pos = Vector2(0.95, 0.5)
	one.alive = false
	for i: int in 15:
		sim.step()
	assert_eq(sim.barrages()[0].fired, 4)
	assert_lt(sim.enemies()[3].hp, sim.enemies()[3].max_hp)
	assert_almost_eq(sim.barrages()[0].cast.spot.x, 0.65, 0.0001)
	assert_eq(sim.barrages()[0].cast.spot.y, 0.0)


func test_unbonded_skill_does_not_propagate() -> void:
	var one := _caster(false)
	var sim := _sim(one)
	sim.cast_skill_now(one, 1)
	for i: int in 16:
		sim.step()
	assert_true(sim.barrages().is_empty())
	assert_eq(sim.enemies()[3].hp, sim.enemies()[3].max_hp)


func test_forward_skill_validation_and_description() -> void:
	var skill := _caster().skills[0].skill
	assert_eq(PBSkillRules.validate(skill), "")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg), "向前蔓延 3 次")
	skill.hit_step = -0.1
	assert_ne(PBSkillRules.validate(skill), "")
	skill.hit_step = 0.15
	skill.target = PBSkill.Target.GROUND
	assert_ne(PBSkillRules.validate(skill), "")
	skill.target = PBSkill.Target.NONE
	skill.hit_count = 1
	assert_ne(PBSkillRules.validate(skill), "")
