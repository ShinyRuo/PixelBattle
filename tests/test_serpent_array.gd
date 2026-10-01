extends GutTest

var _cfg: PBSimConfig
var _unit: PBAttacker
var _sim: PBBattleSim


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_cfg.spawn_window = 0
	_cfg.unit_min_gap = 0
	var card := PBUnit.new(_cfg.characters.by_id(&"orochimaru"))
	card.level = 2
	var owned: Array[PBUnit] = [card, PBUnit.new(_cfg.characters.by_id(&"kabuto"))]
	var patches := PBBondRules.active_skill_patches(owned, [card], _cfg.bonds)
	_unit = (
		PBCombatRules
		. build_attackers(
			[card],
			PBElement.Type.PHYSICAL,
			1,
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
	_unit.attack = 0
	_unit.dps = 0
	_unit.move_speed = 0
	_unit.mp_regen = 0
	var wave := PBWave.new()
	wave.count = 3
	wave.hp_each = 10000
	wave.element = PBElement.Type.PHYSICAL
	_sim = PBBattleSim.new(wave, 0, 0, _cfg, [_unit])
	for enemy: PBEnemy in _sim.enemies():
		enemy.distance = 0.5
		enemy.lane = 0.3
		enemy.speed = 0
		enemy.damage_per_shot = 0


func _until(tick: int) -> void:
	while _sim.current_tick() < tick:
		_sim.step()


func test_ground_followup_starts_control_then_delayed_damage_with_distinct_ranges() -> void:
	var enemies := _sim.enemies()
	enemies[1].distance = 0.701
	enemies[2].distance = 0.703
	assert_true(_sim.cast_skill(_unit, Vector2(0.5, 0.3), 1))
	_until(6)
	assert_eq(enemies[0].buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 6), 0.5)
	assert_eq(enemies[1].buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 6), 1.0)
	assert_eq(enemies[2].hp, 10000.0)
	var before := enemies[1].hp
	_until(65)
	assert_eq(enemies[1].hp, before)
	_until(66)
	var child := _unit.skills[0].skill.followup
	var main := child.damage
	var ratio := _cfg.damage_multiplier(PBElement.relation(child.element, PBElement.Type.PHYSICAL))
	assert_almost_eq(enemies[1].hp, (before - main) * (1.0 - 0.08 * ratio), 0.001)
	assert_eq(enemies[1].buffs.amount(PBBuffRules.SILENCE, 66), 0.0)
	assert_eq(enemies[0].buffs.amount(PBBuffRules.SILENCE, 66), 1.0)
	assert_eq(enemies[2].hp, 10000.0)
	assert_eq(_sim.barrages()[0].fired, 1)
	assert_eq(_unit.skills[0].ready_at, 286)


func test_hero_excludes_remaining_hp_damage_and_source_death_keeps_followup() -> void:
	var enemies := _sim.enemies()
	enemies[0].is_hero = true
	enemies[1].is_hero = false
	_sim.cast_skill(_unit, Vector2(0.5, 0.3), 1)
	_until(6)
	var before := enemies[0].hp
	assert_eq(before, enemies[1].hp)
	_unit.alive = false
	_unit.skills[0].skill.followup.damage = 99999
	_until(66)
	var first := _sim.barrages()[0].cast.skill.damage
	assert_almost_eq(enemies[0].hp, before - first, 0.001)
	assert_lt(enemies[1].hp, enemies[0].hp)
	assert_eq(_sim.barrages()[0].fired, 1)


func test_silence_levels_and_unbonded_base_have_no_followup() -> void:
	var child := _cfg.skills.by_id(&"serpent_array")
	assert_eq(child.control_radius, 0.2)
	assert_eq(child.radius, 0.2025)
	for level: int in range(1, 11):
		assert_almost_eq(child.on_hit[0].seconds_at(level), 0.5 + 0.3 * level, 0.00001)
	assert_false(_cfg.skills.by_id(&"great_breakthrough").followup_enabled)
	assert_true(_unit.skills[0].skill.followup_enabled)
	assert_eq(child.mp_cost, 0.0)
	assert_eq(child.cooldown_ticks, 0)


func test_new_wave_drops_pending_array() -> void:
	_sim.cast_skill(_unit, Vector2(0.5, 0.3), 1)
	_until(6)
	assert_true(_sim.barrages()[0].active())
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000
	var next := PBBattleSim.new(wave, 0, 0, _cfg, [_unit])
	assert_true(next.barrages().is_empty())
	assert_eq(_unit.skills[0].ready_at, 0)
