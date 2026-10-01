extends GutTest


func test_five_original_cost_tables_cover_all_ten_levels() -> void:
	var cfg := PBGameData.config()
	var expected := {
		&"mirror_ward": [12, 20, 28, 36, 44, 52, 60, 68, 76, 84],
		&"sun_halo_dance": [12, 16, 20, 24, 28, 32, 36, 40, 44, 48],
		&"dust_release": [10, 18, 26, 34, 42, 50, 58, 66, 74, 82],
		&"inspire": [10, 13, 16, 19, 22, 25, 28, 31, 34, 37],
		&"deep_forest": [10, 13, 17, 20, 24, 27, 31, 34, 38, 41]
	}
	for id: StringName in expected:
		var skill := cfg.skills.by_id(id)
		for level: int in range(1, 11):
			var cost: float = expected[id][level - 1]
			assert_eq(PBSkillCostRules.mana(skill, level), cost)
			assert_string_contains(PBEffectWords.skill_body(skill, cfg, level), "耗蓝 %.0f" % cost)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"water_wall"), 10), 10.0)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"palm_healing"), 8), 25.0)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"reincarnation"), 10), 64.0)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"vampire_bugs"), 1), 10.0)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"vampire_bugs"), 10), 118.0)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"shadow_bind"), 10), 120.0)
	assert_eq(PBSkillCostRules.mana(cfg.skills.by_id(&"shadow_clones"), 10), 53.0)


func test_queue_gate_payment_and_landing_use_one_level_cost() -> void:
	var cfg := PBGameData.config()
	cfg.spawn_window = 0.0
	var card := PBUnit.new(cfg.characters.by_id(&"onoki"))
	card.level = 10
	var units: Array[PBUnit] = [card]
	var team := PBCombatRules.build_attackers(
		units, PBElement.Type.WIND, 1.0, PackedFloat64Array(), cfg
	)
	var one: PBAttacker = team[0]
	one.attack = 0.0
	one.mp_regen = 0.0
	one.move_speed = 0.0
	one.ultimate = null
	one.skills = [one.skills[0]]
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, cfg, team)
	one.mp = 81.0
	assert_false(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
	one.mp = 82.0
	assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
	assert_eq(one.mp, 82.0)
	sim.step()
	assert_eq(one.mp, 0.0)
	for tick: int in 15:
		sim.step()
	assert_eq(one.mp, 0.0)
	assert_eq(cfg.skills.by_id(&"dust_release").mp_cost, 10.0)


func test_queued_order_rechecks_current_mana_before_spending() -> void:
	var cfg := PBGameData.config()
	var one := PBAttacker.new()
	one.alive = true
	one.max_mp = 100.0
	one.mp = 48.0
	one.skills = [PBSkillCast.new(cfg.skills.by_id(&"sun_halo_dance").clone(), 10)]
	var orders := PBSkillOrders.new()
	orders.reset(1)
	assert_true(orders.place([one], 0, 1, PBSkillCast.NO_SPOT, -1, 0))
	one.mp = 47.0
	orders.flush([one], cfg, 0, null)
	assert_eq(one.mp, 47.0)
	assert_false(one.skills[0].is_pending())
	assert_eq(orders.count(), 0)


func test_clone_isolation_and_level_bounds() -> void:
	var skill := PBGameData.config().skills.by_id(&"mirror_ward")
	var copy := skill.clone()
	copy.mp_cost_levels[9] = 999.0
	assert_eq(PBSkillCostRules.mana(skill, 10), 84.0)
	assert_eq(PBSkillCostRules.mana(skill, -1), 12.0)
	assert_eq(PBSkillCostRules.mana(skill, 11), 84.0)


func test_cost_validation_rejects_invalid_values_and_mismatched_first_level() -> void:
	var skill := PBGameData.config().skills.by_id(&"mirror_ward").clone()
	for bad: float in [-1.0, INF, NAN]:
		skill.mp_cost_levels[9] = bad
		assert_ne(PBSkillLoader.check(skill), "")
	skill.mp_cost_levels = PackedFloat32Array([13.0])
	assert_ne(PBSkillLoader.check(skill), "")
	skill.mp_cost_levels = PackedFloat32Array()
	skill.mp_cost = -1.0
	assert_ne(PBSkillLoader.check(skill), "")


func test_passive_and_followup_cannot_hide_level_costs() -> void:
	var cfg := PBGameData.config()
	var aura := cfg.skills.by_id(&"light_rock").clone()
	aura.mp_cost_levels = PackedFloat32Array([0.0, 10.0])
	assert_ne(PBSkillLoader.check(aura), "")
	var child := cfg.skills.by_id(&"water_surge").clone()
	child.mp_cost_levels = PackedFloat32Array([0.0, 10.0])
	var table := PBSkillTable.new()
	table.add(child)
	assert_ne(PBSkillFollowupRules.check_link(cfg.skills.by_id(&"water_wall"), table), "")
