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
			if bond.id == &"masterminds":
				patches = bond.member_skill_patches
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[PBUnit.new(_cfg.characters.by_id(&"kabuto"))],
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
		if cast.skill.id == &"white_rage":
			one.skills = [cast]
			break
	one.ultimate = null
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 3
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	sim.enemies()[1].lane = 0.3
	sim.enemies()[2].lane = 0.36
	return sim


func test_second_hit_is_three_seconds_from_cast_wider_and_without_silence() -> void:
	var one := _caster()
	var sim := _sim(one)
	var center: PBEnemy = sim.enemies()[0]
	var outer: PBEnemy = sim.enemies()[1]
	var far: PBEnemy = sim.enemies()[2]
	var mp_before: float = one.mp
	assert_true(sim.cast_skill(one, center.pos(), 1))
	for i: int in 16:
		sim.step()
	assert_lt(center.hp, center.max_hp)
	assert_eq(outer.hp, outer.max_hp)
	assert_eq(center.buffs.amount(PBBuffRules.SILENCE, 16), 1.0)
	var hurt: float = center.max_hp - center.hp
	var ready: int = one.skills[0].ready_at
	for i: int in 49:
		sim.step()
	assert_eq(outer.hp, outer.max_hp)
	sim.step()
	assert_almost_eq(center.max_hp - center.hp, hurt * 2.0, 0.0001)
	assert_almost_eq(outer.max_hp - outer.hp, hurt, 0.0001)
	assert_eq(far.hp, far.max_hp)
	assert_eq(center.buffs.amount(PBBuffRules.SILENCE, 66), 0.0)
	assert_eq(outer.buffs.amount(PBBuffRules.SILENCE, 66), 0.0)
	assert_almost_eq(one.mp, mp_before - one.skills[0].skill.mp_cost, 0.0001)
	assert_eq(one.skills[0].ready_at, ready)


func test_unbonded_skill_has_no_extra_hit() -> void:
	var one := _caster(false)
	var sim := _sim(one)
	sim.cast_skill(one, sim.enemies()[0].pos(), 1)
	for i: int in 61:
		sim.step()
	assert_eq(sim.enemies()[1].hp, sim.enemies()[1].max_hp)
	assert_true(sim.barrages().is_empty())


func test_echo_stays_at_original_point_after_caster_moves_or_dies() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill(one, sim.enemies()[0].pos(), 1)
	for i: int in 16:
		sim.step()
	one.pos = Vector2(0.9, 0.4)
	one.alive = false
	for i: int in 50:
		sim.step()
	assert_lt(sim.enemies()[1].hp, sim.enemies()[1].max_hp)
	assert_eq(sim.barrages()[0].cast.spot, Vector2(0.5, 0.0))


func test_cooldown_reset_keeps_two_echoes_independent_and_next_wave_clears_them() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill(one, sim.enemies()[0].pos(), 1)
	for i: int in 16:
		sim.step()
	one.skills[0].ready_at = 10
	sim.cast_skill(one, Vector2(0.9, 0.0), 1)
	for i: int in 16:
		sim.step()
	assert_eq(sim.barrages().size(), 2)
	assert_ne(sim.barrages()[0].center, sim.barrages()[1].center)
	assert_ne(sim.barrages()[0].next_at, sim.barrages()[1].next_at)
	var new_sim := _sim(one)
	assert_true(new_sim.barrages().is_empty())
	assert_eq(_cfg.skills.by_id(&"white_rage").echo_delay_ticks, 0)


func test_echo_validation_and_description() -> void:
	var skill := _caster().skills[0].skill
	assert_eq(PBSkillDamage.validate(skill), "")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg), "施放 3.0 秒后")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg), "不附带控制")
	skill.echo_delay_ticks = skill.delay_ticks
	assert_ne(PBSkillDamage.validate(skill), "")
