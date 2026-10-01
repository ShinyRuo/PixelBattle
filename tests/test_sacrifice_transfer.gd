extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _team(level: int = 10) -> Array[PBAttacker]:
	var cards: Array[PBUnit] = []
	for id: StringName in [&"chiyo", &"rock_lee", &"itachi"]:
		var card := PBUnit.new(_cfg.characters.by_id(id))
		card.level = level
		card.star_level = 2
		cards.append(card)
	var team := PBCombatRules.build_attackers(
		cards,
		PBElement.Type.FIRE,
		1.3,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		{},
		{},
		[{}, {PBStatRules.ATTACK: 200.0, PBStatRules.HP_BONUS: 0.3, PBStatRules.ATTACK_SPEED: 0.2}]
	)
	for i: int in team.size():
		team[i].pos = Vector2(0.2 + i * 0.02, 0.0)
		team[i].move_speed = 0.0
		team[i].revive()
		team[i].prime(_cfg.tick_rate, _cfg)
	return team


func _cast(caster: PBAttacker, bonded: bool = false) -> PBSkillCast:
	var cast := caster.skills[0]
	if bonded:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"puppet_masters":
				PBSkillPatchRules.apply(
					cast.skill, bond.member_skill_patches[&"chiyo"][cast.skill.id]
				)
	cast.origin = caster.pos
	cast.target_slot = 1
	return cast


func _sim(team: Array[PBAttacker]) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, team)
	sim.enemies()[0].damage_per_shot = 0.0
	sim.enemies()[0].speed = 0.0
	return sim


func test_ten_levels_round_each_attribute_twice_and_do_not_weaken_source() -> void:
	for level: int in range(1, 11):
		var team := _team(level)
		var source: Dictionary = team[0].damage_attributes.duplicate()
		var target: Dictionary = team[1].damage_attributes.duplicate()
		PBSkillRules.land_on_ally(_cast(team[0]), team, _cfg, 7, team[0])
		for key: StringName in [&"strength", &"agility", &"intellect"]:
			var given: float = floorf(floorf(floorf(source[key]) * 0.99) * (0.1 + 0.03 * level))
			assert_almost_eq(team[1].damage_attributes[key], target[key] + given, 0.001)
			assert_eq(team[0].damage_attributes[key], source[key])
		assert_eq(team[0].sacrifice_at, 107)
		assert_true(team[2].attribute_profile.temporary.is_empty())


func test_derived_stats_reuse_primary_star_equipment_rules_and_keep_health_ratios() -> void:
	var team := _team()
	var target := team[1]
	target.hp = target.max_hp * 0.3
	target.mp = target.max_mp * 0.6
	var before: PBStats = target.attribute_profile.current
	var attack_scale: float = target.attack / before.atk
	var old_skill: float = target.skills[0].skill.damage
	var old_raw: float = PBSkillDamage.raw(target.skills[0].skill, before, 10)
	PBSkillRules.land_on_ally(_cast(team[0]), team, _cfg, 0, team[0])
	var profile := target.attribute_profile
	var mods: Dictionary = profile.mods.duplicate()
	for key: StringName in profile.temporary:
		mods[key] = float(mods.get(key, 0.0)) + float(profile.temporary[key])
	var expected := PBStatRules.of(profile.character, profile.level, profile.star, _cfg, mods)
	assert_almost_eq(target.max_hp, expected.hp, 0.001)
	assert_almost_eq(target.hp / target.max_hp, 0.3, 0.0001)
	assert_almost_eq(target.mp / target.max_mp, 0.6, 0.0001)
	assert_almost_eq(target.attack, expected.atk * attack_scale, 0.001)
	assert_almost_eq(target.base_attack, expected.base_atk, 0.001)
	assert_almost_eq(target.defence, expected.def, 0.001)
	assert_almost_eq(target.attack_speed, expected.attack_speed, 0.001)
	assert_almost_eq(target.max_mp, expected.mp, 0.001)
	var new_raw: float = PBSkillDamage.raw(target.skills[0].skill, expected, 10)
	assert_almost_eq(target.skills[0].skill.damage, old_skill * new_raw / old_raw, 0.001)
	assert_almost_eq(target.strike_for(0), target.attack, 0.001)


func test_bond_gives_two_friends_identical_donation_and_only_one_sacrifice_timer() -> void:
	var team := _team()
	var cast := _cast(team[0], true)
	PBSkillRules.land_on_ally(cast, team, _cfg, 10, team[0])
	assert_eq(team[1].attribute_profile.temporary, team[2].attribute_profile.temporary)
	assert_false(team[1].attribute_profile.temporary.is_empty())
	var int_before: float = team[2].ninjutsu_attack
	assert_gt(int_before, 0.0)
	var source := PBHarmContext.from_caster(team[2], null, 11)
	assert_eq(source.attributes[&"intellect"], team[2].attribute_profile.current.intellect)
	assert_eq(team[0].sacrifice_at, 110)
	cast.ready_at = 0
	assert_false(PBSkillRules.can_cast(team[0], 1, 11))
	var old: Dictionary = team[1].attribute_profile.temporary.duplicate()
	PBSkillRules.land_on_ally(cast, team, _cfg, 11, team[0])
	assert_eq(team[1].attribute_profile.temporary, old)


func test_real_order_dies_at_five_seconds_ignoring_damage_defences_once() -> void:
	var team := _team()
	var sim := _sim(team)
	var caster := team[0]
	var guard := PBBuff.new()
	guard.id = &"sacrifice_guard"
	caster.buffs.add(guard, {PBBuffRules.SHIELD: 999999.0, PBBuffRules.UNDYING: 1.0}, 0, 500, 0)
	caster.revives = 1
	caster.dodge = 1.0
	assert_true(sim.cast_skill_on(caster, team[1], 1))
	PBCastTestClock.release(sim, caster)
	var end: int = caster.sacrifice_at
	assert_eq(end, 106)
	while sim.current_tick() < end - 1:
		sim.step()
	assert_true(caster.alive)
	sim.step()
	assert_false(caster.alive)
	assert_eq(caster.hp, 0.0)
	assert_eq(sim.result().allies_lost, 1)
	for i: int in 3:
		sim.step()
	assert_eq(sim.result().allies_lost, 1)


func test_source_early_death_does_not_double_count_or_revoke_donation() -> void:
	var team := _team()
	PBSkillRules.land_on_ally(_cast(team[0]), team, _cfg, 0, team[0])
	var old: Dictionary = team[1].damage_attributes.duplicate()
	var out := PBCombatOutcome.new()
	PBStrikeRules.wound_ally(team[0], team[0].hp + 1.0, _cfg, 1, null, null, out)
	PBSacrificeRules.expire(team, 100, null, out)
	assert_eq(out.allies_lost, 1)
	assert_eq(team[1].damage_attributes, old)
	assert_eq(team[0].sacrifice_at, -1)


func test_new_wave_and_cloned_sim_clear_donations_without_touching_original_card() -> void:
	var team := _team()
	var baseline: Dictionary = team[1].damage_attributes.duplicate()
	var base_damage: float = team[1].skills[0].skill.damage
	PBSkillRules.land_on_ally(_cast(team[0]), team, _cfg, 0, team[0])
	var copied := team[1].clone()
	assert_ne(copied.attribute_profile, team[1].attribute_profile)
	_sim([copied])
	assert_eq(copied.damage_attributes, baseline)
	assert_false(team[1].attribute_profile.temporary.is_empty())
	_sim(team)
	assert_eq(team[1].damage_attributes, baseline)
	assert_almost_eq(team[1].skills[0].skill.damage, base_damage, 0.001)
	assert_eq(team[0].sacrifice_at, -1)
	assert_true(team[1].attribute_profile.temporary.is_empty())


func test_self_summon_and_dead_targets_are_refused_and_invalid_primary_costs_no_life() -> void:
	var team := _team()
	var sim := _sim(team)
	assert_false(sim.cast_skill_on(team[0], team[0], 1))
	team[1].summoned = true
	assert_false(sim.cast_skill_on(team[0], team[1], 1))
	team[1].summoned = false
	assert_true(sim.cast_skill_on(team[0], team[1], 1))
	team[1].alive = false
	sim.step()
	assert_eq(team[0].sacrifice_at, -1)
	assert_true(team[2].attribute_profile.temporary.is_empty())


func test_loader_and_tooltip_require_real_transfer_shape() -> void:
	var skill := _cfg.skills.by_id(&"reincarnation").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	var words := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_true(words.contains("40%"))
	assert_true(words.contains("5 秒后死亡"))
	assert_false(words.contains("增伤"))
	skill.shot_cross_seconds = 0.2
	assert_ne(PBSkillLoader.check(skill), "")


func test_sacrifice_runs_death_cast_through_normal_battle_path() -> void:
	var team := _team()
	var skill := PBSkill.new()
	skill.target = PBSkill.Target.GROUND
	skill.affects = PBSkill.Party.ALLIES
	skill.radius = 1.0
	var heal := PBBuff.new()
	heal.id = &"transfer_death_heal"
	heal.mods = {PBBuffRules.HEAL: 100.0}
	skill.on_hit = [heal]
	team[0].death_casts = [PBSkillCast.new(skill)]
	var sim := _sim(team)
	team[0].sacrifice_at = 1
	team[1].hp -= 200.0
	var before: float = team[1].hp
	sim.step()
	assert_eq(team[1].hp, before + 100.0)
	assert_eq(sim.result().allies_lost, 1)
	assert_false(team[0].death_pending)
	sim.step()
	assert_eq(team[1].hp, before + 100.0)


func test_transfer_link_has_six_frames_and_ends_before_persistent_gift() -> void:
	var team := _team()
	PBSacrificeRules.land(_cast(team[0]), team[0], team, _cfg, 0)
	assert_gt(team[0].sacrifice_at, 0)
	var found := false
	for state: PBBuffState in team[1].buffs.states():
		if state.buff == null or state.buff.id != &"reincarnation_gift":
			continue
		found = true
		assert_eq(state.source_slot, team[0].slot)
		assert_true(state.is_live(team[0].sacrifice_at + 1))
	assert_true(found)
	var skin := PBFieldArt.read("links", &"reincarnation_gift")
	assert_not_null(skin)
	assert_eq(skin.frames.size(), 6)
	assert_eq(skin.link_width, 56.0)
	for frame: Texture2D in skin.frames:
		assert_eq(frame.get_size(), Vector2(256, 256))
	var choices := PBFieldArtBindings.new().choices()
	assert_true(choices.any(func(row: Dictionary) -> bool:
		return row.kind == "links" and row.id == "reincarnation_gift"))
