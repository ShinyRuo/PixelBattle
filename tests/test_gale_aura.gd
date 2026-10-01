extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _owner(bonded: bool = false, level: int = 1, flat: float = 0.0) -> PBAttacker:
	var owner := PBUnit.new(_cfg.characters.by_id(&"temari"))
	owner.level = level
	var roster: Array[PBUnit] = [owner]
	if bonded:
		roster.append(PBUnit.new(_cfg.characters.by_id(&"shikamaru")))
	var patches := PBBondRules.active_skill_patches(roster, [owner], _cfg.bonds)
	var unit: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[owner],
			PBElement.Type.FIRE,
			1.0,
			PackedFloat64Array(),
			_cfg,
			null,
			1,
			0,
			{},
			{},
			patches,
			[{PBStatRules.ATTACK: flat}]
		)[0]
	)
	unit.ultimate = null
	unit.pos = Vector2.ZERO
	unit.move_speed = 0.0
	unit.prime(20, _cfg)
	PBAllyAuraRules.install([unit])
	return unit


func _target() -> PBAttacker:
	var unit := PBAttacker.new()
	unit.max_hp = 1000.0
	unit.hp = unit.max_hp
	unit.ranged_attack = true
	unit.base_attack = 100.0
	unit.attack = 450.0
	unit.damage_attributes = {&"attack": 300.0, &"intellect": 50.0}
	unit.attack_speed = 1.0
	unit.prime(20)
	return unit


func test_real_bond_sets_aura_to_26_percent_without_character_level_growth() -> void:
	for level: int in range(1, 11):
		var base := _owner(false, level)
		var boosted := _owner(true, level)
		assert_almost_eq(PBAllyAuraRules.rate(base), 0.13, 0.00001)
		assert_almost_eq(PBAllyAuraRules.rate(boosted), 0.26, 0.00001)
		assert_false(PBSkillRules.can_cast(boosted, 1, 0))
		assert_almost_eq(boosted.strike_for(0), boosted.attack * 1.26, 0.001)
	assert_eq(_cfg.skills.by_id(&"gale_dance").ranged_attack_aura, 0.13)
	assert_true(_cfg.skills.by_id(&"gale_dance").on_hit.is_empty())


func test_dynamic_range_ranged_filter_source_death_and_strongest_only() -> void:
	var low := _owner()
	var high := _owner(true)
	var unit := _target()
	PBAllyAuraRules.install([low, high, unit])
	unit.pos = Vector2(0.3, 0.0)
	assert_almost_eq(unit.strike_for(0), 450.0 + 150.0 * 0.26, 0.001)
	high.alive = false
	assert_almost_eq(PBAllyAuraRules.rate(unit), 0.13, 0.00001)
	unit.pos.x = 0.3001
	assert_eq(PBAllyAuraRules.rate(unit), 0.0)
	unit.pos = Vector2.ZERO
	unit.ranged_attack = false
	assert_eq(PBAllyAuraRules.rate(unit), 0.0)
	unit.ranged_attack = true
	low.alive = false
	assert_eq(PBAllyAuraRules.rate(unit), 0.0)
	high.alive = true
	assert_almost_eq(PBAllyAuraRules.rate(unit), 0.26, 0.00001)
	assert_eq(unit.buffs.count(0), 0, "光环不占短期效果槽位")


func test_direct_attack_equipment_is_not_amplified_and_element_scaling_is_retained() -> void:
	var naked := _owner()
	var equipped := _owner(false, 1, 500.0)
	assert_eq(naked.base_attack, equipped.base_attack)
	var multiplier: float = _cfg.damage_multiplier(
		PBElement.relation(PBElement.Type.WIND, PBElement.Type.FIRE)
	)
	assert_almost_eq(equipped.attack - naked.attack, 500.0 * multiplier, 0.001)
	assert_almost_eq(equipped.strike_for(0) - naked.strike_for(0), 500.0 * multiplier, 0.001)
	var unit := PBUnit.new(_cfg.characters.by_id(&"temari"))
	var stats := unit.stats(_cfg, {PBStatRules.AGILITY: 10.0, PBStatRules.ATTACK: 500.0})
	assert_almost_eq(stats.atk - stats.base_atk, 500.0, 0.001)
	assert_gt(stats.base_atk, unit.stats(_cfg).base_atk, "主属性派生攻击计入基础攻击")


func test_intellect_attacks_and_spells_stay_independent_but_attack_formulas_receive_bonus() -> void:
	var owner := _owner()
	var unit := _target()
	PBAllyAuraRules.install([owner, unit])
	unit.attack_ninjutsu = 1.0
	unit.ninjutsu_attack = 70.0
	assert_eq(unit.strike_for(0), 70.0)
	var skill := PBSkill.new()
	skill.damage = 200.0
	assert_eq(PBAllyAuraRules.skill_damage(unit, skill, 0.0), 200.0)
	skill.attack_formula_scale = 2.0
	assert_almost_eq(PBAllyAuraRules.skill_damage(unit, skill, 0.0), 226.0, 0.001)
	var source := PBHarmContext.from_caster(unit, skill)
	assert_almost_eq(float(source.attributes[&"attack"]), 313.0, 0.001)
	assert_eq(float(source.attributes[&"intellect"]), 50.0)


func test_real_sim_passive_requires_no_order_or_mana_and_changes_projectile_damage() -> void:
	var losses: Array[float] = []
	for enabled: bool in [false, true]:
		var owner := _owner()
		if not enabled:
			owner.skills.clear()
		owner.attack_speed = 1.0
		owner.shot_speed = 1.0
		owner.reach = 2.0
		owner.crit_chance = 0.0
		owner.mp_regen = 0.0
		var wave := PBWave.new()
		wave.count = 1
		wave.hp_each = 100000.0
		var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [owner])
		sim.enemies()[0].distance = 0.5
		sim.enemies()[0].speed = 0.0
		sim.enemies()[0].damage_per_shot = 0.0
		var mana: float = owner.mp
		if enabled:
			assert_false(sim.cast_skill_now(owner, 1))
		for i: int in 40:
			sim.step()
		assert_eq(owner.mp, mana)
		losses.append(sim.enemies()[0].max_hp - sim.enemies()[0].hp)
	assert_gt(losses[0], 0.0)
	assert_almost_eq(losses[1], losses[0] * 1.13, 0.001)


func test_clone_and_new_team_do_not_retain_sources_from_previous_simulation() -> void:
	var owner := _owner()
	var unit := _target()
	PBAllyAuraRules.install([owner, unit])
	var copy := unit.clone()
	assert_eq(copy.base_attack, unit.base_attack)
	assert_true(copy.ranged_attack)
	assert_eq(PBAllyAuraRules.rate(copy), 0.0)
	PBAllyAuraRules.install([unit])
	assert_eq(PBAllyAuraRules.rate(unit), 0.0)


func test_validation_and_tooltip_distinguish_passive_from_timed_damage_buff() -> void:
	var skill := _cfg.skills.by_id(&"gale_dance").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	var words := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_true(words.contains("被动光环"))
	assert_true(words.contains("13%"))
	assert_false(words.contains("冷却"))
	skill.ranged_attack_aura = NAN
	assert_ne(PBSkillLoader.check(skill), "")
	skill.ranged_attack_aura = 0.26
	skill.mp_cost = 10.0
	assert_ne(PBSkillLoader.check(skill), "")


func test_summoned_ranged_unit_receives_current_aura_without_baking_it_into_inheritance() -> void:
	var owner := _owner()
	var spare := PBAttacker.new()
	spare.summoned = true
	PBSummonRules.dismiss(spare)
	var team: Array[PBAttacker] = [owner, spare]
	PBAllyAuraRules.install(team)
	var skill := PBSkill.new()
	skill.summon_count = 1
	skill.summon_power = 0.5
	skill.summon_hp_share = 0.5
	skill.summon_seconds = 5.0
	assert_eq(PBSummonRules.raise_from(team, owner, skill, 0, _cfg), 1)
	assert_almost_eq(spare.strike_for(0), owner.strike_for(0) * 0.5, 0.001)
	owner.alive = false
	assert_almost_eq(spare.strike_for(1), spare.attack, 0.001)


func test_attack_probe_scaling_also_scales_the_aura_contribution() -> void:
	var owner := _owner()
	var before: float = owner.strike_for(0)
	owner.attack *= 0.1
	owner.prime(20)
	assert_almost_eq(owner.strike_for(0), before * 0.1, 0.001)
