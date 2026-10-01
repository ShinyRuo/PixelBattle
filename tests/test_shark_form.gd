extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _units(level: int = 10) -> Array[PBUnit]:
	var one := PBUnit.new(_cfg.characters.by_id(&"kisame"))
	one.level = level
	return [one, PBUnit.new(_cfg.characters.by_id(&"itachi"))]


func _team(units: Array[PBUnit], bonded: bool = true) -> Array[PBAttacker]:
	var passives: Dictionary = {}
	var patches: Dictionary = {}
	if bonded:
		passives = PBBondRules.active_passives(units, units, _cfg.bonds)
		patches = PBBondRules.active_skill_patches(units, units, _cfg.bonds)
	var team := PBCombatRules.build_attackers(
		units,
		PBElement.Type.PHYSICAL,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		passives,
		patches
	)
	for one: PBAttacker in team:
		one.prime(_cfg.tick_rate, _cfg)
		one.revive()
		one.pos = Vector2(0.4, 0.2)
	return team


func _enemy(at: Vector2, slot: int = 0) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at.x, 0, at.y)
	enemy.slot = slot
	return enemy


func test_all_ten_levels_gain_actual_stats_and_ranged_attacks_without_changing_roster() -> void:
	for level: int in range(1, 11):
		var units := _units(level)
		var baseline := units[0].stats(_cfg)
		var one := _team(units)[0]
		assert_eq(one.damage_attributes[&"strength"], baseline.strength + 6.0 * level)
		assert_eq(one.damage_attributes[&"agility"], baseline.agility + 6.0 * level)
		assert_eq(one.damage_attributes[&"intellect"], baseline.intellect + 6.0 * level)
		assert_eq(one.max_hp, baseline.hp + 6.0 * level * 80.0)
		assert_almost_eq(one.max_mp, baseline.mp + 6.0 * level * 0.7, 0.000001)
		assert_eq(one.reach, _cfg.units_to_field(500.0))
		assert_true(one.ranged_attack)
		assert_gt(one.shot_speed, 0.0)
		assert_eq(PBCritRules.attack_kind(one), PBDamageKind.Type.TAIJUTSU)
		assert_eq(one.skills[1].skill.enemy_aura_radius, 0.3)
		assert_true(PBFieldArt.supports_enemy_aura_area(one.skills[1].skill))
		assert_eq(PBPersistentFieldArt.art_key(one.skills[1].skill), &"shark_form")
		assert_eq(one.skills[1].skill.damage, 50.0 * level)
		assert_eq(units[0].stats(_cfg).strength, baseline.strength)
		assert_eq(units[0].character.reach_tier(), PBCharacter.Reach.MELEE)
		var bare := _team(units, false)[0]
		assert_false(bare.ranged_attack)
		assert_eq(bare.shot_speed, 0.0)
		assert_eq(bare.skills[1].skill.enemy_aura_radius, 0.0)
		assert_false(PBFieldArt.supports_enemy_aura_area(bare.skills[1].skill))


func test_aura_uses_current_position_and_lingers_after_departure_or_source_death() -> void:
	var team := _team(_units())
	var one: PBAttacker = team[0]
	var edge := _enemy(Vector2(0.7, 0.2))
	var far := _enemy(Vector2(0.7001, 0.2), 1)
	PBEnemyAuraRules.advance(team, [edge, far], _cfg, 1)
	assert_eq(edge.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 0.75)
	assert_eq(edge.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 1), 0.75)
	assert_eq(far.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)
	one.pos = Vector2(0.8, 0.2)
	PBEnemyAuraRules.advance(team, [edge, far], _cfg, 2)
	assert_eq(far.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 2), 0.75)
	one.alive = false
	PBEnemyAuraRules.advance(team, [edge, far], _cfg, 50)
	assert_eq(far.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 82), 0.75)
	assert_eq(far.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 83), 1.0)


func test_two_identical_carriers_refresh_one_effect_and_do_not_slow_allies_or_future_enemies(
) -> void:
	var units := _units()
	var second := PBUnit.new(_cfg.characters.by_id(&"kisame"))
	second.serial = 1
	units.append(second)
	var team := _team(units)
	var enemy := _enemy(Vector2(0.5, 0.2))
	var future := _enemy(Vector2(0.5, 0.2), 1)
	future.spawn_tick = 50
	PBEnemyAuraRules.advance(team, [enemy, future], _cfg, 1)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 0.75)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 1), 0.75)
	assert_eq(future.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)
	assert_eq(team[1].buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)


func test_real_battle_installs_aura_and_fires_a_projectile_at_the_new_range() -> void:
	var one := _team(_units())[0]
	one.ultimate = null
	one.move_speed = 0.0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	one.pos = Vector2(0.4, 0.2)
	one.windup_ticks = 0
	one.next_shot_at = 0
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.distance = 0.64
	enemy.lane = 0.2
	enemy.spawn_tick = 0
	enemy.speed = 0.0
	enemy.damage_per_shot = 0.0
	sim.step()
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, sim.current_tick()), 0.75)
	var flying: int = 0
	for shot: PBProjectile in sim.shots():
		if shot.alive:
			flying += 1
	assert_eq(flying, 1)
	assert_eq(enemy.hp, enemy.max_hp, "远程普攻先发弹道，不在起手直接扣血")
	for tick: int in 10:
		sim.step()
	assert_lt(enemy.hp, enemy.max_hp)


func test_preparation_stats_and_range_match_current_bond_and_remove_after_dispatch() -> void:
	var state := PBRunSim.new_state(_cfg)
	var units := _units()
	for unit: PBUnit in units:
		state.add_unit(unit)
	var preview := PBPreparationReadout.of(units[0], state, _cfg, PBWave.new(), units)
	assert_eq(preview.strength, 360.0)
	assert_eq(PBAttackRangeRules.preview(units[0], state, _cfg, units), _cfg.units_to_field(500.0))
	state.dispatch_manual.append(units[1].key())
	var fighting: Array[PBUnit] = [units[0]]
	var lost := PBPreparationReadout.of(units[0], state, _cfg, PBWave.new(), fighting)
	assert_eq(lost.strength, 300.0)
	assert_eq(
		PBAttackRangeRules.preview(units[0], state, _cfg, fighting), _cfg.units_to_field(125.0)
	)


func test_form_changes_training_branch_and_dispatch_restores_melee_training() -> void:
	var state := PBRunSim.new_state(_cfg)
	var units := _units()
	for unit: PBUnit in units:
		state.add_unit(unit)
	state.training = {
		PBTechRules.TRAIN_ATTACK: 2, PBTechRules.TRAIN_AIM: 3, PBTechRules.TRAIN_HP: 1
	}
	var ranged := PBCombatRules.unit_mods(units, state, _cfg, true)[0]
	assert_eq(ranged[PBStatRules.ATTACK], 90.0)
	assert_false(ranged.has(PBStatRules.HP_BONUS))
	var preview := PBPreparationReadout.of(units[0], state, _cfg, PBWave.new(), units)
	var plan := PBWavePlan.new()
	plan.wave = PBWave.new()
	PBRunSim.lock_plan(state, plan, units, false, _cfg)
	assert_eq(preview.atk, plan.attackers[0].damage_attributes[&"attack"])
	state.dispatch_manual.append(units[1].key())
	var melee := PBCombatRules.unit_mods([units[0]], state, _cfg, true)[0]
	assert_eq(melee[PBStatRules.ATTACK], 100.0)
	assert_eq(melee[PBStatRules.HP_BONUS], 0.03)


func test_aura_validation_rejects_missing_or_harmful_effects() -> void:
	var skill := _cfg.skills.by_id(&"shark_form").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	skill.enemy_aura_radius = -0.1
	assert_ne(PBEnemyAuraRules.validate(skill), "")
	skill.enemy_aura_radius = 0.3
	var effect: PBBuff = skill.enemy_aura_effects[0].duplicate(true)
	effect.mods[PBBuffRules.HARM] = 1.0
	skill.enemy_aura_effects = [effect]
	assert_ne(PBEnemyAuraRules.validate(skill), "")
