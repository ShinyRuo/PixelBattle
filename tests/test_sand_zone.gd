extends GutTest

const COUNTS: Array[int] = [3, 3, 4, 4, 4, 5, 5, 6, 6, 7]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0


func _caster(level: int = 1) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"gaara"))
	unit.level = level
	var one := (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	one.ninjutsu_crit_chance = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 1000000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_all_levels_start_control_immediately_and_have_exact_delayed_pulses() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var sim := _sim(one)
		var before: float = one.mp
		assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
		PBCastTestClock.release(sim, one)
		var enemy: PBEnemy = sim.enemies()[0]
		assert_eq(enemy.hp, enemy.max_hp)
		assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 6), 0.0)
		assert_eq(enemy.buffs.amount(PBBuffRules.DISARM, 6), 1.0)
		assert_eq(enemy.buffs.amount(PBBuffRules.STUN, 6), 0.0, "缠绕不能变成眩晕")
		assert_eq(one.skills[0].skill.hit_count, COUNTS[level - 1])
		var each: float = (
			50.0
			* level
			* _cfg.damage_multiplier(
				PBElement.relation(PBElement.Type.WIND, PBElement.Type.PHYSICAL)
			)
		)
		for tick: int in range(7, 89):
			sim.step()
			assert_almost_eq(
				enemy.max_hp - enemy.hp, each * mini((tick - 6) / 10, COUNTS[level - 1]), 0.001
			)
		assert_eq(one.mp, before - (6.0 + 4.0 * level))
		assert_eq(one.skills[0].ready_at, 366)
		assert_eq(enemy.buffs.amount(PBBuffRules.DISARM, 89), 0.0)


func test_late_entry_gets_damage_without_retroactive_root_and_leaving_stops_damage() -> void:
	var one := _caster(10)
	var sim := _sim(one)
	var late: PBEnemy = sim.enemies()[1]
	late.distance = 0.8
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	late.distance = 0.5
	for tick: int in 10:
		sim.step()
	assert_lt(late.hp, late.max_hp)
	assert_eq(late.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 16), 1.0)
	assert_true(late.ready_to_fire(16))
	var leaving: PBEnemy = sim.enemies()[0]
	var before: float = leaving.hp
	leaving.distance = 0.8
	for tick: int in 60:
		sim.step()
	assert_eq(leaving.hp, before)
	assert_eq(leaving.buffs.amount(PBBuffRules.DISARM, 76), 1.0)
	assert_eq(leaving.buffs.amount(PBBuffRules.DISARM, 77), 0.0)


func test_original_288_range_and_caster_death_preserve_fixed_ground_damage() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.enemies()[0].distance = 0.6439
	sim.enemies()[1].distance = 0.6441
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	one.alive = false
	one.pos = Vector2(0.9, 0.0)
	for tick: int in 30:
		sim.step()
	assert_lt(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	assert_eq(sim.enemies()[1].hp, sim.enemies()[1].max_hp)
	assert_false(sim.barrages()[0].active())


func test_repeated_casts_keep_separate_centers_and_next_wave_clears_them() -> void:
	var one := _caster(10)
	var sim := _sim(one)
	sim.enemies()[1].distance = 0.8
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	PBCastTestClock.recover(sim, one)
	one.skills[0].ready_at = 0
	sim.cast_skill(one, Vector2(0.8, 0.0), 1)
	PBCastTestClock.release(sim, one)
	assert_eq(sim.barrages().size(), 2)
	assert_eq(sim.barrages()[0].center, Vector2(0.5, 0.0))
	assert_eq(sim.barrages()[1].center, Vector2(0.8, 0.0))
	for tick: int in 10:
		sim.step()
	assert_lt(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	assert_lt(sim.enemies()[1].hp, sim.enemies()[1].max_hp)
	assert_true(_sim(one).barrages().is_empty())
