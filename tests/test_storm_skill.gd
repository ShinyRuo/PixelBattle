extends GutTest

var _cfg: PBSimConfig
var _unit: PBAttacker
var _cast: PBSkillCast


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_cfg.unit_min_gap = 0
	_cfg.spawn_window = 0
	var card := PBUnit.new(_cfg.characters.by_id(&"kakuzu"))
	_unit = (
		PBCombatRules.build_attackers([card], PBElement.Type.FIRE, 1, PackedFloat64Array(), _cfg)[0]
	)
	_cast = _unit.skills[0]
	_unit.move_speed = 0
	_unit.attack = 0
	_unit.dps = 0
	_unit.max_mp = 100
	_unit.mp_regen = 0
	_unit.home = Vector2(0.45, 0.3)
	_unit.pos = _unit.home


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 937
	return rng


func _sim() -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000
	var sim := PBBattleSim.new(wave, 0, 0, _cfg, [_unit], _rng())
	sim.enemies()[0].distance = 0.6
	sim.enemies()[0].lane = 0.3
	sim.enemies()[0].speed = 0
	sim.enemies()[0].damage_per_shot = 0
	return sim


func test_real_no_target_cast_waits_for_release_then_twenty_rounds() -> void:
	var sim := _sim()
	assert_eq(_cast.skill.id, &"false_darkness")
	assert_eq(_cast.skill.target, PBSkill.Target.NONE)
	assert_eq(_cast.skill.delay_ticks, 0)
	assert_true(_cast.skill.damage_stat_floor)
	assert_true(sim.cast_skill_now(_unit, 1))
	for tick: int in range(1, 87):
		sim.step()
		if tick < 6:
			assert_true(sim.barrages().is_empty())
		else:
			assert_eq(sim.barrages()[0].fired, mini((tick - 6) / 4, 20) * 3)
	assert_eq(sim.barrages()[0].last_at, 86)
	assert_false(sim.barrages()[0].active())
	assert_eq(_cast.ready_at, 406)
	assert_eq(_unit.mp, 90.0)


func test_each_round_follows_current_position_and_survives_source_death() -> void:
	var a := PBSkillBarrage.new()
	var b := PBSkillBarrage.new()
	var other := _unit.clone()
	a.begin(_unit, _cast, 0)
	b.begin(other, _cast, 0)
	var rng_a := _rng()
	var rng_b := _rng()
	for tick: int in range(4, 81, 4):
		_unit.pos += Vector2(0.01, 0.002)
		_unit.alive = false
		a.advance([], 0, _cfg, tick, rng_a, null)
		b.advance([], 0, _cfg, tick, rng_b, null)
		for i: int in 3:
			assert_lt((a.landings[i] - b.landings[i] - (_unit.pos - other.pos)).length(), 0.00001)
	assert_eq(a.fired, 60)
	assert_eq(rng_a.state, rng_b.state, "相同种子与施法序列应可重放")


func test_overlapping_three_landings_damage_same_enemy_three_times() -> void:
	var sim := _sim()
	var enemy := sim.enemies()[0]
	_cast.skill.damage = 10
	_cast.skill.hit_radius = 1
	var barrage := PBSkillBarrage.new()
	barrage.begin(_unit, _cast, 0)
	barrage.advance([enemy], 0, _cfg, 4, _rng(), null)
	assert_almost_eq(enemy.hp, enemy.max_hp - 30, 0.001)
	assert_eq(barrage.fired, 3)


func test_new_wave_clears_old_storm_and_reuse_clears_visual_landings() -> void:
	var sim := _sim()
	assert_true(sim.cast_skill_now(_unit, 1))
	for tick: int in 10:
		sim.step()
	var barrage := sim.barrages()[0]
	assert_eq(barrage.landings.size(), 3)
	var next := _sim()
	assert_true(next.barrages().is_empty())
	assert_eq(_cast.ready_at, 0)
	barrage.begin(_unit, _cast, 20)
	assert_true(barrage.landings.is_empty())
	assert_eq(barrage.last_at, -1)
	assert_eq(barrage.next_at, 24)


func test_invalid_scatter_combinations_are_rejected() -> void:
	var skill := _cast.skill.clone()
	assert_eq(PBSkillRules.validate(skill), "")
	skill.volley_size = 7
	assert_ne(PBSkillRules.validate(skill), "")
	skill.volley_size = 3
	skill.target = PBSkill.Target.GROUND
	assert_ne(PBSkillRules.validate(skill), "")
	skill.target = PBSkill.Target.NONE
	skill.scatter_steps = 0
	assert_ne(PBSkillRules.validate(skill), "")
