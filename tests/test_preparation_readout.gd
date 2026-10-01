extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _state(ids: Array[StringName]) -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	state.tech_pop = 2
	for id: StringName in ids:
		var unit := PBUnit.new(_cfg.characters.by_id(id))
		unit.level = 10
		state.add_unit(unit)
	return state


func _actual(state: PBRunState, team: Array[PBUnit], wave: PBWave) -> Array[PBAttacker]:
	var plan := PBWavePlan.new()
	plan.wave = wave
	PBRunSim.lock_plan(state, plan, team, false, _cfg)
	for one: PBAttacker in plan.attackers:
		one.prime(_cfg.tick_rate, _cfg)
		one.revive()
	PBAllyAuraRules.install(plan.attackers)
	PBMotionAuraRules.install(plan.attackers)
	return plan.attackers


func test_five_kage_preparation_matches_actual_derived_stats() -> void:
	var state := _state([&"gaara", &"mei", &"tsunade", &"raikage", &"onoki"])
	var team := state.field_units(_cfg)
	var wave := PBWave.new()
	var preview := PBPreparationReadout.of(team[0], state, _cfg, wave, team)
	var actual := _actual(state, team, wave)[0]
	assert_eq(preview.strength, 240.0)
	assert_eq(preview.agility, 240.0)
	assert_eq(preview.intellect, 372.0)
	assert_eq(preview.hp, actual.max_hp)
	assert_eq(preview.mp, actual.max_mp)
	assert_eq(preview.atk, actual.damage_attributes[&"attack"])
	assert_eq(team[0].stats(_cfg).strength, 200.0)


func test_training_and_equipment_preview_matches_battle_without_spending_parts() -> void:
	var state := _state([&"raikage"])
	var team := state.field_units(_cfg)
	state.training[PBTechRules.TRAIN_ATTACK] = 3
	state.training[PBTechRules.TRAIN_HP] = 2
	var item := _cfg.equipment.item(&"thunder_fang")
	for part: StringName in item.recipe:
		PBEquipRules.add_part(state.equip_parts, part)
	PBEquipRules.pin(state.equipped, team[0].key(), item.id, _cfg)
	var parts := state.equip_parts.duplicate(true)
	var pins := state.equipped.duplicate(true)
	var wave := PBWave.new()
	var preview := PBPreparationReadout.of(team[0], state, _cfg, wave, team)
	var actual := _actual(state, team, wave)[0]
	assert_eq(preview.hp, actual.max_hp)
	assert_eq(preview.atk, actual.damage_attributes[&"attack"])
	assert_gt(preview.hp, team[0].stats(_cfg).hp)
	assert_eq(state.equip_parts, parts)
	assert_eq(state.equipped, pins)


func test_motion_aura_preview_respects_formation_distance() -> void:
	var state := _state([&"kurotsuchi", &"onoki"])
	var team := state.field_units(_cfg)
	var wave := PBWave.new()
	state.formation[team[0].key()] = Vector2(0.1, 0.1)
	state.formation[team[1].key()] = Vector2(0.2, 0.1)
	var near := PBPreparationReadout.of(team[1], state, _cfg, wave, team)
	var actual := _actual(state, team, wave)[1]
	assert_eq(near.attack_speed, float(_cfg.tick_rate) / actual.attack_interval())
	state.formation[team[1].key()] = Vector2(0.5, 0.4)
	var far := PBPreparationReadout.of(team[1], state, _cfg, wave, team)
	assert_lt(far.attack_speed, near.attack_speed)


func test_bench_preview_does_not_inherit_field_only_bond() -> void:
	var state := _state([&"gaara", &"mei", &"tsunade", &"raikage", &"onoki"])
	var team := state.field_units(_cfg)
	var unit: PBUnit = team.pop_front()
	var preview := PBPreparationReadout.of(unit, state, _cfg, PBWave.new(), team)
	assert_eq(preview.strength, unit.stats(_cfg).strength)
	assert_eq(preview.intellect, unit.stats(_cfg).intellect)


func test_bench_preview_does_not_borrow_equipment_reserved_for_a_fighter() -> void:
	var state := _state([&"raikage", &"kisame"])
	var team := state.field_units(_cfg)
	var bench: PBUnit = team.pop_back()
	var item := _cfg.equipment.item(&"thunder_fang")
	for part: StringName in item.recipe:
		PBEquipRules.add_part(state.equip_parts, part)
	PBEquipRules.pin(state.equipped, team[0].key(), item.id, _cfg)
	state.training[PBTechRules.TRAIN_ATTACK] = 3
	var preview := PBPreparationReadout.of(bench, state, _cfg, PBWave.new(), team)
	assert_eq(preview.atk, bench.stats(_cfg).atk)
	assert_eq(preview.hp, bench.stats(_cfg).hp)
