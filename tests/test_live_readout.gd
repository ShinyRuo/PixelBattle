extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _unit(id: StringName, level: int = 1) -> PBUnit:
	var unit := PBUnit.new(_cfg.characters.by_id(id))
	unit.level = level
	return unit


func _team(units: Array[PBUnit]) -> Array[PBAttacker]:
	var patches := PBBondRules.active_skill_patches(units, units, _cfg.bonds)
	var team := PBCombatRules.build_attackers(
		units, PBElement.Type.WIND, 1.5, PackedFloat64Array(), _cfg, null, 1, 0, {}, {}, patches
	)
	for one: PBAttacker in team:
		one.prime(_cfg.tick_rate, _cfg)
		one.revive()
	PBAllyAuraRules.install(team)
	PBMotionAuraRules.install(team)
	return team


func test_attack_readout_uses_raw_attribute_and_current_base_attack_bonus() -> void:
	var team := _team([_unit(&"temari"), _unit(&"onoki")])
	team[0].pos = Vector2.ZERO
	team[1].pos = Vector2(0.2, 0.0)
	var stats := PBStats.new()
	assert_true(PBLiveReadout.update(stats, team[1], _cfg, 1))
	var raw: float = team[1].damage_attributes[&"attack"]
	assert_almost_eq(stats.atk, raw + team[1].base_attack * 0.13, 0.000001)
	assert_ne(stats.atk, team[1].attack)
	team[1].buffs.add(PBBuff.new(), {PBBuffRules.BASE_ATTACK_BONUS: 0.2}, 0, 10, 0)
	PBLiveReadout.update(stats, team[1], _cfg, 1)
	assert_almost_eq(stats.atk, raw + team[1].base_attack * 0.33, 0.000001)
	team[1].pos.x = 0.4
	PBLiveReadout.update(stats, team[1], _cfg, 11)
	assert_eq(stats.atk, raw)
	assert_eq(team[1].damage_attributes[&"attack"], raw)


func test_motion_aura_changes_displayed_cadence_and_returns_after_departure() -> void:
	var team := _team([_unit(&"kurotsuchi", 10), _unit(&"onoki")])
	team[0].pos = Vector2.ZERO
	team[1].pos = Vector2(0.2, 0.0)
	var stats := PBStats.new()
	PBLiveReadout.update(stats, team[1], _cfg, 0)
	var fast: float = stats.attack_speed
	assert_eq(fast, float(_cfg.tick_rate) / team[1].attack_interval())
	team[0].alive = false
	PBLiveReadout.update(stats, team[1], _cfg, 1)
	assert_lt(stats.attack_speed, fast)
	team[1].alive = false
	PBLiveReadout.update(stats, team[1], _cfg, 2)
	assert_eq(stats.attack_speed, 0.0)


func test_transferred_stats_and_temporary_defence_are_displayed_without_mutation() -> void:
	var team := _team([_unit(&"tobirama")])
	var one: PBAttacker = team[0]
	var stats := PBStats.new()
	PBLiveReadout.update(stats, one, _cfg, 0)
	var old_strength: float = stats.strength
	PBAttributeRules.grant(
		one,
		{PBStatRules.STRENGTH: 100.0, PBStatRules.AGILITY: 50.0, PBStatRules.INTELLECT: 20.0},
		_cfg
	)
	var current: PBStats = one.attribute_profile.current
	one.buffs.add(PBBuff.new(), {PBBuffRules.DEFENCE: 500.0}, 0, 60, 0)
	PBLiveReadout.update(stats, one, _cfg, 1)
	assert_eq(stats.strength, old_strength + 100.0)
	assert_eq(stats.hp, one.max_hp)
	assert_eq(stats.mp, one.max_mp)
	assert_eq(stats.def, one.defence + 500.0)
	assert_eq(current.def, one.defence)
	PBLiveReadout.update(stats, one, _cfg, 61)
	assert_eq(stats.def, one.defence)
	PBAttributeRules.reset(one, _cfg)
	PBLiveReadout.update(stats, one, _cfg, 62)
	assert_eq(stats.strength, old_strength)


func test_unchanged_values_do_not_request_text_layout_but_expiry_does() -> void:
	var one := _team([_unit(&"onoki")])[0]
	var stats := PBStats.new()
	assert_true(PBLiveReadout.update(stats, one, _cfg, 0))
	assert_false(PBLiveReadout.update(stats, one, _cfg, 1))
	one.hp -= 10.0
	assert_false(PBLiveReadout.update(stats, one, _cfg, 2))
	one.buffs.add(PBBuff.new(), {PBBuffRules.DEFENCE: 3.0}, 2, 5, 0)
	assert_true(PBLiveReadout.update(stats, one, _cfg, 3))
	assert_false(PBLiveReadout.update(stats, one, _cfg, 5))
	assert_true(PBLiveReadout.update(stats, one, _cfg, 8))


func test_actual_panel_updates_live_defence_and_clears_it_on_selection_change() -> void:
	var state := PBRunState.new()
	var card := _unit(&"tobirama", 10)
	var other := _unit(&"onoki")
	state.add_unit(card)
	state.add_unit(other)
	var info := PBUnitInfo.new()
	add_child_autofree(info)
	var wave := PBWave.new()
	info.refresh(PBSelection.of_unit(card.key()), state, _cfg, wave, [card, other])
	var one := _team([card])[0]
	one.buffs.add(PBBuff.new(), {PBBuffRules.DEFENCE: 500.0}, 0, 90, 0)
	info.show_live(one, 1)
	var expected: String = "防 %.0f" % (one.defence + 500.0)
	assert_string_contains(info._body.text, expected)
	assert_string_contains(info._body.text, "千手兄弟")
	await wait_frames(2)
	assert_lte(info._body.get_line_count(), 5)
	info.refresh(PBSelection.of_unit(other.key()), state, _cfg, wave, [card, other])
	assert_false(info._body.text.contains(expected))
	info.refresh(PBSelection.of_kind(PBSelection.Kind.NONE), state, _cfg, wave, [card, other])
	var team_text: String = info._body.text
	info.show_live(one, 2)
	assert_eq(info._body.text, team_text)
