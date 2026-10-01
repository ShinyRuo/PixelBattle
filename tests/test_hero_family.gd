extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _state() -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	for id: StringName in [&"naruto", &"kushina", &"minato"]:
		var unit := PBUnit.new(_cfg.characters.by_id(id))
		unit.level = 10
		state.add_unit(unit)
	return state


func _plan(state: PBRunState) -> PBWavePlan:
	var plan := PBWavePlan.new()
	plan.wave = PBWave.new()
	PBRunSim.lock_plan(state, plan, state.field_units(_cfg), false, _cfg)
	for one: PBAttacker in plan.attackers:
		one.prime(_cfg.tick_rate, _cfg)
		one.revive()
	return plan


func test_family_applies_each_members_own_effect_and_preserves_base_resources() -> void:
	var state := _state()
	var plan := _plan(state)
	var first := plan.attackers[0]
	var second := plan.attackers[1]
	var third := plan.attackers[2]
	assert_eq(first.damage_attributes[&"strength"], 408.0)
	assert_eq(first.skills[0].skill.heal_aura_max, 0.02)
	assert_eq(second.damage_attributes[&"intellect"], 300.0)
	assert_eq(second.skills[0].skill.heal_aura_hit_chance, 0.09)
	assert_eq(second.skills[0].skill.heal_aura_lost, 0.07)
	assert_eq(third.damage_attributes[&"agility"], 420.0)
	assert_eq(third.skills[1].skill.attack_repeat_count, 3)
	var character := plan.deployed[2].character
	var expected: float = (
		1.0
		/ (1.0 / character.attack_speed_base - 0.2)
		* (1.0 + 420.0 * character.attack_speed_per_agility)
		* 1.75
	)
	assert_almost_eq(third.attack_speed, expected, 0.000001)
	assert_eq(_cfg.skills.by_id(&"kurama_cloak").heal_aura_max, 0.01)
	assert_eq(_cfg.skills.by_id(&"flying_raijin_chain").attack_repeat_count, 2)
	assert_eq(_cfg.skills.by_id(&"battle_chakra").heal_aura_hit_chance, 0.0)


func test_dispatch_breaks_family_and_prepare_stats_match_actual() -> void:
	var state := _state()
	var team := state.field_units(_cfg)
	var before := PBPreparationReadout.of(team[2], state, _cfg, PBWave.new(), team)
	var plan := _plan(state)
	assert_eq(before.agility, plan.attackers[2].damage_attributes[&"agility"])
	assert_eq(before.attack_speed, float(_cfg.tick_rate) / plan.attackers[2].attack_interval())
	state.dispatch_manual.append(team[1].key())
	var fighting: Array[PBUnit] = [team[0], team[2]]
	var lost := PBPreparationReadout.of(team[2], state, _cfg, PBWave.new(), fighting)
	assert_eq(lost.agility, 350.0)
	var card := PBCommandCard.new()
	add_child_autofree(card)
	card.refresh(PBSelection.of_unit(team[2].key()), state, _cfg, PBWavePlan.new(), fighting)
	assert_eq(card.skill_definitions()[2].attack_repeat_count, 2)


func test_sage_version_does_not_replace_sr_member_and_duplicates_do_not_fill_family() -> void:
	var units: Array[PBUnit] = []
	for id: StringName in [&"naruto_sage", &"kushina", &"minato", &"minato"]:
		units.append(PBUnit.new(_cfg.characters.by_id(id)))
	var bond := _cfg.bonds.by_id(&"hero_family")
	assert_eq(PBBondRules.active_count(bond, units), 2)
	assert_true(PBBondRules.active_skill_patches(units, units, _cfg.bonds).is_empty())


func test_family_tooltip_explains_all_three_members_and_base_interval_seconds() -> void:
	var text := "\n".join(PBEffectWords.bond_effects(_cfg.bonds.by_id(&"hero_family"), _cfg))
	assert_string_contains(text, "当前三围（含装备） +20%")
	assert_string_contains(text, "基础攻击间隔减少 0.20 秒")
	assert_string_contains(text, "额外普攻次数 +1")
	assert_string_contains(text, "9%")
	assert_string_contains(text, "7%")
	assert_string_contains(text, "2%")
