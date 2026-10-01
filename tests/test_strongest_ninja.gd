extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0
	_cfg.unit_min_gap = 0
	_cfg.aim_policy = PBAimRules.Policy.NONE


func _caster(id: StringName, bonded: bool = true, level: int = 1) -> PBAttacker:
	var card := PBUnit.new(_cfg.characters.by_id(id))
	card.level = level
	var owned: Array[PBUnit] = [card]
	if bonded:
		owned.append(
			PBUnit.new(_cfg.characters.by_id(&"hashirama" if id == &"madara" else &"madara"))
		)
	var patches := PBBondRules.active_skill_patches(owned, [card], _cfg.bonds)
	var unit := (
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
	unit.prime(_cfg.tick_rate, _cfg)
	unit.revive()
	unit.attack = 0
	unit.dps = 0
	unit.move_speed = 0
	unit.mp_regen = 0
	return unit


func _sim(unit: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0, 0, _cfg, [unit])
	var enemy := sim.enemies()[0]
	enemy.distance = 0.5
	enemy.lane = 0.3
	enemy.speed = 0
	enemy.damage_per_shot = 0
	return sim


func test_complete_form_snapshots_three_stats_range_and_level_duration() -> void:
	for level: int in range(1, 11):
		var unit := _caster(&"madara", true, level)
		var before := unit.damage_attributes.duplicate()
		var hp := unit.max_hp
		var mp := unit.max_mp
		var reach := unit.reach
		unit.hp *= 0.5
		unit.mp *= 0.4
		var cast := unit.skills[0]
		PBSkillRules.apply_on_self(unit, cast, _cfg, 1)
		for stat: StringName in [&"strength", &"agility", &"intellect"]:
			assert_eq(
				unit.damage_attributes[stat], before[stat] + floorf(floorf(before[stat]) * 0.2)
			)
		assert_gt(unit.max_hp, hp)
		assert_gt(unit.max_mp, mp)
		assert_almost_eq(unit.hp / unit.max_hp, 0.5, 0.000001)
		assert_almost_eq(unit.mp / unit.max_mp, 0.4, 0.000001)
		assert_almost_eq(unit.reach, _cfg.units_to_field(400), 0.000001)
		assert_false(unit.ranged_attack)
		assert_eq(unit.shot_speed, 0.0)
		var seconds: float = [2, 2, 3, 3, 3, 4, 4, 5, 5, 6][level - 1] * 1.35
		var end := 1 + roundi(seconds * _cfg.tick_rate)
		assert_almost_eq(cast.skill.on_self[0].seconds_at(level), seconds, 0.00001)
		PBTemporaryAttributeRules.refresh(unit, _cfg, end + 1)
		assert_almost_eq(unit.reach, reach, 0.000001)
		assert_almost_eq(unit.max_hp, hp, 0.000001)
		for stat: StringName in [&"strength", &"agility", &"intellect"]:
			assert_eq(unit.damage_attributes[stat], before[stat])


func test_refresh_remove_and_eviction_revoke_only_this_buff() -> void:
	var unit := _caster(&"madara")
	var before := unit.damage_attributes.duplicate()
	var reach := unit.reach
	var cast := unit.skills[0]
	PBSkillRules.apply_on_self(unit, cast, _cfg, 1)
	var once := unit.damage_attributes.duplicate()
	PBSkillRules.apply_on_self(unit, cast, _cfg, 2)
	assert_eq(unit.damage_attributes, once)
	PBAttributeRules.grant(unit, {PBStatRules.INTELLECT: 13.0}, _cfg)
	unit.buffs.remove(&"madara_perfect", 3)
	assert_eq(unit.damage_attributes[&"intellect"], before[&"intellect"] + 13)
	assert_almost_eq(unit.reach, reach, 0.000001)
	PBSkillRules.apply_on_self(unit, cast, _cfg, 4)
	for i: int in 32:
		var buff := PBBuff.new()
		buff.id = StringName("filler_%d" % i)
		buff.kind = PBBuff.Kind.DURATION
		unit.buffs.add(buff, {PBBuffRules.DEFENCE: 1.0}, 5, 1000, 0)
	assert_almost_eq(unit.reach, reach, 0.000001)
	assert_eq(unit.damage_attributes[&"strength"], before[&"strength"])
	assert_eq(unit.damage_attributes[&"intellect"], before[&"intellect"] + 13)


func test_without_bond_never_gets_full_form_and_wave_clears_it() -> void:
	var normal := _caster(&"madara", false)
	var reach := normal.reach
	PBSkillRules.apply_on_self(normal, normal.skills[0], _cfg, 1)
	assert_almost_eq(normal.reach, reach, 0.000001)
	assert_eq(normal.temporary_reach_bonus, 0.0)
	var bonded := _caster(&"madara")
	PBSkillRules.apply_on_self(bonded, bonded.skills[0], _cfg, 1)
	assert_almost_eq(bonded.clone().reach, reach, 0.000001)
	_sim(bonded)
	assert_almost_eq(bonded.reach, reach, 0.000001)
	assert_true(bonded.attribute_profile.temporary.is_empty())


func test_first_cast_fifteen_hits_has_correct_total_timing_and_reverts() -> void:
	var unit := _caster(&"hashirama", true, 5)
	var sim := _sim(unit)
	var enemy := sim.enemies()[0]
	assert_eq(unit.skills[0].skill.variant_art_id, &"true_hands")
	assert_true(sim.cast_skill(unit, enemy.pos(), 1))
	var total := 200 * 5 + 2.5 * floorf(unit.damage_attributes[&"strength"])
	total *= _cfg.damage_multiplier(PBElement.relation(PBElement.Type.SAGE, enemy.element))
	for tick: int in range(1, 87):
		sim.step()
		var hits := 0 if tick < 30 else mini(1 + (tick - 30) / 4, 15)
		assert_almost_eq(enemy.max_hp - enemy.hp, total * hits / 15, 0.001)
	assert_eq(sim.barrages()[0].fired, 15)
	assert_eq(sim.barrages()[0].last_at, 86)
	assert_eq(unit.skills[0].skill.hit_count, 12)
	assert_eq(unit.skills[0].skill.variant_art_id, &"")
	assert_eq(sim.barrages()[0].cast.skill.variant_art_id, &"true_hands")
	var next := _sim(unit)
	assert_true(next.barrages().is_empty())
	assert_eq(unit.skills[0].skill.hit_count, 15)


func test_control_refreshes_before_damage_and_catches_later_entrants() -> void:
	var unit := _caster(&"hashirama")
	var sim := _sim(unit)
	var enemy := sim.enemies()[0]
	var barrage := PBSkillBarrage.new()
	unit.skills[0].spot = enemy.pos()
	barrage.begin(unit, unit.skills[0], 0)
	enemy.distance = 0.9
	barrage.advance([enemy], 0, _cfg, 0, null, null)
	assert_true(enemy.ready_to_fire(0))
	enemy.distance = 0.5
	barrage.advance([enemy], 0, _cfg, 20, null, null)
	assert_false(enemy.ready_to_fire(20))
	assert_eq(enemy.hp, enemy.max_hp)
	unit.alive = false
	for tick: int in range(21, 81):
		barrage.advance([enemy], 0, _cfg, tick, null, null)
	assert_eq(barrage.fired, 15)
	assert_false(enemy.ready_to_fire(80))
	assert_true(enemy.ready_to_fire(81))


func test_variant_art_and_new_buffs_are_authorable_without_textures() -> void:
	var choices := PBFieldArtBindings.new().choices()
	for id: String in ["wood_descent", "true_hands"]:
		assert_true(
			choices.any(func(row: Dictionary) -> bool: return row.id == id and row.kind == "pulses")
		)
	var unit := _caster(&"hashirama")
	assert_eq(PBPersistentFieldArt.art_key(unit.skills[0].skill), &"true_hands")
	assert_eq(PBPersistentFieldArt.art_key(unit.skills[0].skill.recast), &"wood_descent")
	assert_eq(PBSkillLoader.check(_cfg.skills.by_id(&"susanoo_perfect")), "")
	assert_eq(PBSkillLoader.check(_cfg.skills.by_id(&"true_hands")), "")
