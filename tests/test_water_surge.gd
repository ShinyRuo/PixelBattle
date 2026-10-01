extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(bonded: bool = true, level: int = 1) -> PBAttacker:
	var card := PBUnit.new(_cfg.characters.by_id(&"tobirama"))
	card.level = level
	var roster: Array[PBUnit] = [card]
	if bonded:
		roster.append(PBUnit.new(_cfg.characters.by_id(&"hashirama")))
	var patches := PBBondRules.active_skill_patches(roster, [card], _cfg.bonds)
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[card],
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
	one.ultimate = null
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"water_wall":
			one.skills = [cast]
			break
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	one.ninjutsu_crit_chance = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 3
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	one.pos = Vector2(0.5, 0.0)
	var distances := [0.51, 0.8825, 0.8827]
	for i: int in sim.enemies().size():
		var enemy: PBEnemy = sim.enemies()[i]
		enemy.distance = distances[i]
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_wall_grants_five_hundred_defence_for_three_or_four_point_five_seconds() -> void:
	for bonded: bool in [false, true]:
		var one := _caster(bonded)
		var sim := _sim(one)
		var mp_before: float = one.mp
		assert_true(sim.cast_skill_now(one, 1))
		PBCastTestClock.release(sim, one)
		var until: int = 96 if bonded else 66
		assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, until), 500.0)
		assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, until + 1), 0.0)
		assert_eq(one.buffs.amount(PBBuffRules.DAMAGE_TAKEN, 1), 1.0)
		assert_almost_eq(one.mp, mp_before - 10.0, 0.000001)
		assert_eq(one.skills[0].ready_at, 346)
		assert_eq(sim.barrages().size(), 5 if bonded else 0)
	assert_eq(_cfg.skills.by_id(&"water_wall").on_self[0].duration_seconds, 3.0)


func test_defence_mitigates_taijutsu_but_does_not_grant_ninjutsu_reduction() -> void:
	var one := _caster()
	one.revive()
	PBSkillRules.apply_on_self(one, one.skills[0], _cfg, 0)
	for kind: PBDamageKind.Type in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
		var amounts: Array[float] = []
		for tick: int in [1, 100]:
			one.hp = one.max_hp
			PBStrikeRules.hurt_ally(
				one,
				null,
				100.0,
				PBElement.Type.PHYSICAL,
				_cfg,
				tick,
				null,
				null,
				PBCombatOutcome.new(),
				PBEnemyHitContext.new([], false, kind)
			)
			amounts.append(one.max_hp - one.hp)
		if kind == PBDamageKind.Type.TAIJUTSU:
			assert_lt(amounts[0], amounts[1])
		else:
			assert_almost_eq(amounts[0], amounts[1], 0.000001)


func test_five_waves_launch_in_sequence_and_each_enemy_is_hit_once_per_wave() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill_now(one, 1)
	for tick: int in range(1, 46):
		sim.step()
		if tick == 9:
			assert_eq(sim.enemies()[0].hp, 100000.0)
		if tick == 10:
			assert_eq(sim.enemies()[0].hp, 99860.0)
		if tick == 18:
			assert_eq(sim.enemies()[0].hp, 99300.0)
	assert_eq(sim.enemies()[0].hp, 99300.0)
	assert_eq(sim.enemies()[1].hp, 99300.0)
	assert_eq(sim.enemies()[2].hp, 100000.0)
	for i: int in 5:
		var wave: PBTravelWave = sim.barrages()[i]
		assert_eq(wave.launch_at, 8 + 2 * i)
		assert_eq(wave.fired, 14)
		assert_eq(wave.struck.size(), 2)
		assert_false(wave.active())
		assert_almost_eq(wave.visual_radius(), 0.134, 0.000001)
		assert_almost_eq(wave.visual_spot().x, 0.7485, 0.000001)


func test_ten_levels_use_fixed_level_damage_and_water_ninjutsu() -> void:
	for level: int in range(1, 11):
		var one := _caster(true, level)
		var sim := _sim(one)
		var child: PBSkill = one.skills[0].skill.followup
		assert_eq(child.damage, float(140 * level))
		assert_eq(child.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(child.element, PBElement.Type.WATER)
		for enemy: PBEnemy in sim.enemies():
			enemy.armor = 1000.0
			enemy.ninjutsu_resist = 0.25
		sim.cast_skill_now(one, 1)
		for tick: int in 45:
			sim.step()
		assert_almost_eq(100000.0 - sim.enemies()[0].hp, 140.0 * level * 5.0 * 0.75, 0.001)


func _directions(seed_value: int) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var one := _caster()
	var cast := PBSkillCast.new(one.skills[0].skill.followup)
	cast.spot = Vector2.ZERO
	var out: Array[Vector2] = []
	for i: int in 5:
		var wave := PBTravelWave.new()
		wave.begin(one, cast, 0)
		wave.advance([], 0, _cfg, 0, rng, null)
		out.append(wave.direction)
	return out


func test_fan_uses_seeded_discrete_angles_without_global_randomness() -> void:
	var first := _directions(20260916)
	assert_eq(first, _directions(20260916))
	assert_ne(first, _directions(20260917))
	for direction: Vector2 in first:
		var degrees: float = rad_to_deg(direction.angle())
		assert_between(degrees, -70.001, 70.001)
		assert_almost_eq(degrees / 14.0, roundf(degrees / 14.0), 0.000001)
		assert_almost_eq(direction.length(), 1.0, 0.000001)


func test_origin_and_damage_survive_caster_movement_and_death() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill_now(one, 1)
	PBCastTestClock.release(sim, one)
	one.pos = Vector2(0.9, 0.0)
	one.alive = false
	one.aim_at = -1
	for tick: int in range(7, 46):
		for wave: PBSkillBarrage in sim.barrages():
			wave.advance(sim.enemies(), 0, _cfg, tick, null, null)
	assert_eq(sim.enemies()[0].hp, 99300.0)
	for wave: PBSkillBarrage in sim.barrages():
		assert_eq(wave.center, Vector2(0.5, 0.0))
		assert_eq(wave.cast.skill.damage, 140.0)


func test_late_spawn_is_hit_but_dead_units_are_skipped_and_pool_resets_history() -> void:
	var one := _caster()
	var sim := _sim(one)
	var late: PBEnemy = sim.enemies()[1]
	late.distance = 0.55
	late.spawn_tick = 14
	sim.enemies()[2].alive = false
	sim.cast_skill_now(one, 1)
	for tick: int in 45:
		sim.step()
	assert_eq(late.hp, 99300.0)
	one.skills[0].ready_at = 0
	sim.cast_skill_now(one, 1)
	PBCastTestClock.release(sim, one)
	assert_eq(sim.barrages().size(), 5)
	for wave: PBTravelWave in sim.barrages():
		assert_true(wave.struck.is_empty())
		assert_eq(wave.fired, 0)
		assert_eq(wave.direction, Vector2.RIGHT)


func test_wave_validation_rejects_ignored_and_nonfinite_configuration() -> void:
	var skill := _cfg.skills.by_id(&"water_surge").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	for key: String in ["travel_step", "fan_spread_degrees"]:
		for value: float in [-1.0, INF, NAN]:
			var copy := skill.clone()
			copy.set(key, value)
			assert_ne(PBTravelWave.validate_wave(copy), "")
	for key: String in ["wave_count", "wave_interval_ticks", "fan_steps", "hit_count"]:
		var copy := skill.clone()
		copy.set(key, 0)
		assert_ne(PBTravelWave.validate_wave(copy), "")
	var copy := skill.clone()
	copy.travel_step = 0.0
	assert_ne(PBTravelWave.validate_wave(copy), "")
	copy = skill.clone()
	copy.line_length = 1.0
	assert_ne(PBTravelWave.validate_wave(copy), "")


func test_tooltip_and_nonlinear_duration_patch_keep_source_resources_immutable() -> void:
	var one := _caster()
	var words := PBEffectWords.skill_body(one.skills[0].skill, _cfg)
	assert_string_contains(words, "4.5 秒")
	assert_string_contains(words, "500")
	assert_string_contains(words, "5 道")
	assert_string_contains(words, "只命中一次")
	var copy := _cfg.skills.by_id(&"water_wall").clone()
	copy.on_self[0] = copy.on_self[0].duplicate(true)
	copy.on_self[0].duration_levels = PackedFloat32Array([1.0, 2.0, 3.0])
	var original: PBBuff = copy.on_self[0]
	PBSkillPatchRules.apply(copy, {PBSkillPatchRules.SELF_DURATION_SCALE: 1.5})
	assert_eq(copy.on_self[0].seconds_at(3), 4.5)
	assert_eq(original.seconds_at(3), 3.0)
	assert_eq(_cfg.skills.by_id(&"water_wall").on_self[0].seconds_at(), 3.0)
