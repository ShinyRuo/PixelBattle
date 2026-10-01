extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0


func _caster(level: int = 1) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"mei"))
	unit.level = level
	var one := (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	one.ultimate = null
	one.attack = 0.0
	one.mp_regen = 0.0
	one.move_speed = 0.0
	one.ninjutsu_crit_chance = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	wave.count = 2
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_actual_order_has_eight_half_second_pulses_and_one_payment() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var sim := _sim(one)
		var before: float = one.mp
		assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
		var raw: float = 15.0 * level + 0.25 * one.damage_attributes[&"agility"]
		var hit: float = (
			raw
			* _cfg.damage_multiplier(
				PBElement.relation(PBElement.Type.WATER, PBElement.Type.PHYSICAL)
			)
		)
		for tick: int in range(1, 88):
			sim.step()
			assert_almost_eq(
				sim.enemies()[0].max_hp - sim.enemies()[0].hp,
				hit * clampi((tick - 6) / 10, 0, 8),
				0.001
			)
		assert_eq(one.mp, before - (6.0 + 4.0 * level))
		assert_eq(one.skills[0].ready_at, 406)


func test_late_entry_and_departure_are_checked_again_each_pulse() -> void:
	var one := _caster()
	var sim := _sim(one)
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.distance = 0.9
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	for tick: int in 11:
		sim.step()
	assert_eq(enemy.hp, enemy.max_hp)
	enemy.distance = 0.5
	for tick: int in 10:
		sim.step()
	var once: float = enemy.hp
	assert_lt(once, enemy.max_hp)
	enemy.distance = 0.9
	for tick: int in 61:
		sim.step()
	assert_eq(enemy.hp, once)


func test_damage_and_debuff_areas_have_different_boundaries() -> void:
	var one := _caster(10)
	var sim := _sim(one)
	sim.enemies()[0].distance = 0.75
	sim.enemies()[1].distance = 0.757
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.ENEMY_DEFENCE, 6), -30.0)
	assert_eq(sim.enemies()[1].buffs.amount(PBBuffRules.ENEMY_DEFENCE, 6), 0.0)
	for tick: int in 82:
		sim.step()
	assert_eq(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.ENEMY_DEFENCE, 145), -30.0)
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.ENEMY_DEFENCE, 146), 0.0)


func test_death_and_movement_do_not_remove_existing_zone_and_next_wave_clears_it() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	one.alive = false
	one.pos = Vector2(0.9, 0.0)
	for tick: int in 80:
		sim.step()
	assert_lt(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	assert_false(sim.barrages()[0].active())
	var fresh := _sim(one)
	assert_true(fresh.barrages().is_empty())


func test_overlapping_carriers_refresh_once_and_keep_snapshot() -> void:
	var one := _caster(5)
	var sim := _sim(one)
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	var zone := sim.barrages()[0] as PBHazardZone
	assert_eq(zone.points.size(), 6)
	assert_eq(sim.enemies()[0].buffs.count(6), 1)
	one.skills[0].skill.zone_effects[0] = one.skills[0].skill.zone_effects[0].duplicate(true)
	one.skills[0].skill.zone_effects[0].mods[PBBuffRules.ENEMY_DEFENCE] = -999.0
	sim.step()
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.ENEMY_DEFENCE, 7), -15.0)
	assert_eq(_cfg.skills.by_id(&"boil_acid").zone_effects[0].mods[PBBuffRules.ENEMY_DEFENCE], -3.0)
