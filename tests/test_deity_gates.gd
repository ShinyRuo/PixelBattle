extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(bonded: bool = true, level: int = 1) -> PBAttacker:
	var card := PBUnit.new(_cfg.characters.by_id(&"hashirama"))
	card.level = level
	var roster: Array[PBUnit] = [card]
	if bonded:
		roster.append(PBUnit.new(_cfg.characters.by_id(&"tobirama")))
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
		if cast.skill.id == &"deep_forest":
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
	wave.count = 5
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var distances := [0.5, 0.6325, 0.695, 0.7575, 0.7577]
	for i: int in sim.enemies().size():
		var enemy: PBEnemy = sim.enemies()[i]
		enemy.distance = distances[i]
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_real_bond_strikes_at_script_times_and_expands_without_reapplying_roots() -> void:
	var one := _caster()
	var sim := _sim(one)
	var enemies := sim.enemies()
	var mp_before: float = one.mp
	assert_true(sim.cast_skill_at(one, enemies[0], 1))
	for tick: int in range(1, 52):
		sim.step()
		if tick in [9, 29, 49]:
			var expected_count: int = [9, 29, 49].find(tick)
			assert_almost_eq(
				100000.0 - enemies[0].hp,
				one.skills[0].skill.followup.damage * expected_count,
				0.001
			)
	var damage: float = one.skills[0].skill.followup.damage
	assert_almost_eq(100000.0 - enemies[0].hp, damage * 3.0, 0.001)
	assert_almost_eq(100000.0 - enemies[1].hp, damage * 3.0, 0.001)
	assert_almost_eq(100000.0 - enemies[2].hp, damage * 2.0, 0.001)
	assert_almost_eq(100000.0 - enemies[3].hp, damage, 0.001)
	assert_eq(enemies[4].hp, 100000.0)
	assert_eq(enemies[0].buffs.amount(PBBuffRules.DISARM, 51), 0.0)
	assert_eq(enemies[1].buffs.amount(PBBuffRules.DISARM, 5), 0.0)
	assert_eq(enemies[3].buffs.amount(PBBuffRules.STUN, 60), 1.0)
	assert_eq(enemies[3].buffs.amount(PBBuffRules.STUN, 61), 0.0)
	assert_almost_eq(one.mp, mp_before - 10.0, 0.0001)
	assert_eq(one.skills[0].ready_at, 286)
	assert_eq(sim.barrages().size(), 1)
	assert_false(sim.barrages()[0].active())


func test_unbonded_roots_stop_movement_and_attack_but_allow_active_ninjutsu() -> void:
	var one := _caster(false)
	var sim := _sim(one)
	one.pos = Vector2(0.45, 0.0)
	var enemy: PBEnemy = sim.enemies()[0]
	sim.cast_skill_at(one, enemy, 1)
	PBCastTestClock.release(sim, one)
	assert_true(sim.barrages().is_empty())
	assert_eq(enemy.hp, enemy.max_hp)
	assert_false(enemy.ready_to_fire(2))
	assert_eq(enemy.buffs.amount(PBBuffRules.STUN, 2), 0.0)
	enemy.speed = 0.1
	enemy.march_to(Vector2.ZERO, 1.0, 2)
	assert_eq(enemy.distance, 0.5)
	var ability := PBEnemyAbility.new()
	ability.id = &"probe_spell"
	ability.damage_base = 100.0
	ability.intellect_scale = 0.0
	ability.reach = 1.0
	enemy.abilities = [ability]
	enemy.ability_ready_at = PackedInt32Array([0])
	var before: float = one.hp
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 2, null, null, PBCombatOutcome.new())
	assert_lt(one.hp, before)
	assert_eq(enemy.ability_ready_at[0], 102)


func test_secondary_uses_strength_and_sage_ninjutsu_at_all_ten_levels() -> void:
	for level: int in range(1, 11):
		var one := _caster(true, level)
		var child: PBSkill = one.skills[0].skill.followup
		assert_eq(child.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(child.element, PBElement.Type.SAGE)
		var element_scale: float = _cfg.damage_multiplier(
			PBElement.relation(PBElement.Type.SAGE, PBElement.Type.PHYSICAL)
		)
		assert_eq(child.damage, float(one.damage_attributes[&"strength"]) * element_scale)
		var sim := _sim(one)
		var enemy: PBEnemy = sim.enemies()[0]
		enemy.armor = 1000.0
		enemy.ninjutsu_resist = 0.25
		sim.cast_skill_at(one, enemy, 1)
		for tick: int in 10:
			sim.step()
		assert_almost_eq(100000.0 - enemy.hp, child.damage * 0.75, 0.001)


func test_emitted_gates_keep_center_and_damage_after_target_or_source_changes() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill_at(one, sim.enemies()[0], 1)
	PBCastTestClock.release(sim, one)
	var sequence: PBSkillBarrage = sim.barrages()[0]
	var damage: float = sequence.cast.skill.damage
	PBAttributeRules.grant(one, {PBStatRules.STRENGTH: 100.0}, _cfg)
	assert_gt(one.skills[0].skill.followup.damage, damage)
	assert_eq(sequence.cast.skill.damage, damage)
	one.pos = Vector2(0.8, 0.2)
	one.alive = false
	sim.enemies()[0].alive = false
	for tick: int in [10, 30, 50]:
		sequence.advance(sim.enemies(), 0, _cfg, tick, null, null)
	assert_eq(sequence.center, Vector2(0.5, 0.0))
	assert_almost_eq(100000.0 - sim.enemies()[1].hp, damage * 3.0, 0.001)
	assert_false(sequence.active())


func test_invalid_primary_does_not_start_followup_and_copies_are_isolated() -> void:
	var one := _caster()
	var sim := _sim(one)
	one.skills[0].target_slot = 1000
	assert_null(PBSkillFollowupRules.prepare(one.skills[0], one, sim.enemies(), 1))
	var copy := one.clone()
	copy.skills[0].skill.followup.damage = 9999.0
	assert_ne(one.skills[0].skill.followup.damage, 9999.0)
	assert_eq(_cfg.skills.by_id(&"deity_gates").damage, 0.0)
	assert_null(_cfg.skills.by_id(&"deep_forest").followup)
	assert_false(_cfg.skills.by_id(&"deep_forest").followup_enabled)
	assert_false(_cfg.characters.by_id(&"hashirama").skill_ids.has(&"deity_gates"))


func test_links_reject_missing_recursive_or_active_cost_secondary() -> void:
	var main := _cfg.skills.by_id(&"deep_forest").clone()
	var child := _cfg.skills.by_id(&"deity_gates").clone()
	var table := PBSkillTable.new()
	table.add(main)
	assert_ne(PBSkillFollowupRules.check_link(main, table), "")
	table.add(child)
	assert_eq(PBSkillFollowupRules.check_link(main, table), "")
	child.mp_cost = 1.0
	assert_ne(PBSkillFollowupRules.check_link(main, table), "")
	child.mp_cost = 0.0
	child.followup_id = main.id
	assert_ne(PBSkillFollowupRules.check_link(main, table), "")
	main.followup_id = main.id
	assert_ne(PBSkillFollowupRules.validate(main), "")
	main.followup_id = &""
	main.followup_enabled = true
	assert_ne(PBSkillFollowupRules.validate(main), "")


func test_pool_reuse_resets_growing_radius_and_tooltip_shows_real_followup() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill_at(one, sim.enemies()[0], 1)
	for tick: int in 51:
		sim.step()
	var sequence: PBSkillBarrage = sim.barrages()[0]
	assert_almost_eq(sequence.visual_radius(), 0.2575, 0.000001)
	one.skills[0].ready_at = 0
	sim.cast_skill_at(one, sim.enemies()[0], 1)
	PBCastTestClock.release(sim, one)
	assert_eq(sim.barrages().size(), 1)
	assert_eq(sequence.fired, 0)
	assert_almost_eq(sequence.visual_radius(), 0.1325, 0.000001)
	var words: String = PBEffectWords.skill_body(one.skills[0].skill, _cfg)
	assert_string_contains(words, "明神门")
	assert_string_contains(words, "0.2 秒")
	assert_string_contains(words, "3 段")
	assert_string_contains(words, "0.2575")
