extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster() -> PBAttacker:
	var card := PBUnit.new(_cfg.characters.by_id(&"shisui"))
	var caster: PBAttacker = (
		PBCombatRules
		. build_attackers([card], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	caster.revive()
	caster.pos = Vector2.ZERO
	caster.move_speed = 0.0
	caster.dps = 0.0
	caster.attack = 0.0
	caster.crit_chance = 0.0
	caster.ninjutsu_crit_chance = 0.0
	caster.ultimate = null
	caster.skills = [caster.skills[1]]
	caster.mp_regen = 0.0
	return caster


func _enemy(slot: int, distance: float) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, distance, 0)
	enemy.slot = slot
	return enemy


func _sequence(caster: PBAttacker) -> PBExpandingStrike:
	caster.skills[0].skill.damage = 100.0
	var sequence := PBExpandingStrike.new()
	sequence.begin(caster, caster.skills[0], 0)
	return sequence


func test_nine_steps_match_script_radius_timing_and_damage_without_repeating() -> void:
	var caster := _caster()
	var sequence := _sequence(caster)
	var enemies: Array[PBEnemy] = []
	for i: int in 9:
		enemies.append(_enemy(i, (433.0 + 133.0 * i) / 2000.0))
	var book := PBBattleLog.new()
	assert_eq(sequence.advance(enemies, 0, _cfg, 1, null, book), 0)
	assert_eq(sequence.fired, 0)
	for tick: int in range(2, 21):
		sequence.advance(enemies, 0, _cfg, tick, null, book)
	assert_eq(sequence.struck.size(), 9)
	assert_false(sequence.active())
	assert_almost_eq(sequence.radius_at(1), 0.2165, 0.000001)
	assert_almost_eq(sequence.radius_at(9), 0.7485, 0.000001)
	for i: int in 9:
		assert_almost_eq(100000.0 - enemies[i].hp, 100.0 * (1.11 + 0.11 * i), 0.001)
	assert_eq(caster.skills[0].skill.radius, 0.7485)


func test_empty_steps_are_spent_and_ninth_step_hits_exact_boundary_only() -> void:
	var sequence := _sequence(_caster())
	var enemies: Array[PBEnemy] = [_enemy(0, 0.7485), _enemy(1, 0.749)]
	for tick: int in range(1, 20):
		sequence.advance(enemies, 0, _cfg, tick, null, null)
	assert_eq(sequence.struck, PackedInt32Array([0]))
	assert_almost_eq(enemies[0].hp, 99801.0, 0.001)
	assert_eq(enemies[1].hp, 100000.0)


func test_nearest_then_slot_order_skips_dead_unspawned_and_converted() -> void:
	var sequence := _sequence(_caster())
	var enemies: Array[PBEnemy] = [
		_enemy(4, 0.2), _enemy(3, 0.1), _enemy(2, 0.1), _enemy(1, 0.05), _enemy(0, 0.01)
	]
	enemies[3].alive = false
	enemies[4].spawn_tick = 40
	sequence.advance(enemies, 0, _cfg, 2, null, null)
	sequence.advance(enemies, 0, _cfg, 4, null, null)
	assert_eq(sequence.struck, PackedInt32Array([2, 3]))
	var buff := PBBuff.new()
	buff.id = &"probe_domination"
	enemies[0].buffs.add(buff, {PBBuffRules.DOMINATED: 1.0}, 0, 100, 0)
	for state: PBBuffState in enemies[0].buffs.states():
		if state.buff == buff:
			enemies[0].control_ref = weakref(state)
	sequence.advance(enemies, 0, _cfg, 6, null, null)
	assert_eq(sequence.struck.size(), 2)


func test_cast_center_and_emitted_wave_survive_movement_and_source_death() -> void:
	var caster := _caster()
	var sequence := _sequence(caster)
	var enemies: Array[PBEnemy] = [_enemy(0, 0.2), _enemy(1, 0.3)]
	caster.pos = Vector2(2.0, 0.0)
	caster.alive = false
	sequence.advance(enemies, 0, _cfg, 2, null, null)
	sequence.advance(enemies, 0, _cfg, 4, null, null)
	sequence.advance(enemies, 0, _cfg, 6, null, null)
	assert_eq(sequence.struck, PackedInt32Array([0, 1]))
	assert_eq(sequence.visual_spot(), Vector2.ZERO)
	assert_almost_eq(sequence.visual_radius(), 0.3495, 0.000001)


func test_real_cast_pays_once_and_physical_element_still_uses_ninjutsu_rules() -> void:
	var caster := _caster()
	var skill := caster.skills[0].skill
	assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
	assert_eq(skill.element, PBElement.Type.PHYSICAL)
	var wave := PBWave.new()
	wave.count = 10
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [caster])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.15 + enemy.slot * 0.01
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
		enemy.armor = 10000.0
		enemy.ninjutsu_resist = 0.25
	var mana: float = caster.mp
	assert_true(sim.cast_skill_now(caster, 1))
	for tick: int in 25:
		sim.step()
	assert_eq(caster.mp, mana - skill.mp_cost)
	assert_eq(caster.skills[0].ready_at, 306)
	assert_eq(sim.barrages().size(), 1)
	for i: int in 9:
		var expected: float = skill.damage * (1.11 + i * 0.11) * 0.75
		assert_almost_eq(100000.0 - sim.enemies()[i].hp, expected, 0.001)
	assert_eq(sim.enemies()[9].hp, 100000.0)


func test_new_sequence_has_independent_hit_list_and_validation_rejects_ignored_fields() -> void:
	var caster := _caster()
	var one := _sequence(caster)
	var two := _sequence(caster)
	var enemies: Array[PBEnemy] = [_enemy(0, 0.1)]
	one.advance(enemies, 0, _cfg, 2, null, null)
	two.advance(enemies, 0, _cfg, 2, null, null)
	assert_almost_eq(enemies[0].hp, 99778.0, 0.001)
	one.begin(caster, caster.skills[0], 5)
	assert_true(one.struck.is_empty())
	assert_eq(two.struck.size(), 1)
	var skill := _cfg.skills.by_id(&"sun_halo_dance").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	assert_true(PBEffectWords.skill_body(skill, _cfg).contains("199%"))
	skill.pulse_radius_step = INF
	assert_ne(PBSkillLoader.check(skill), "")
	skill.pulse_radius_step = 0.0665
	skill.hit_count = 1
	skill.hit_interval_ticks = 0
	assert_ne(PBSkillLoader.check(skill), "")
