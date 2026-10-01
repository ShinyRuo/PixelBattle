extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _team(ids: Array[StringName], level: int = 10) -> Array[PBAttacker]:
	var units: Array[PBUnit] = []
	for id: StringName in ids:
		var unit := PBUnit.new(_cfg.characters.by_id(id))
		unit.level = level
		units.append(unit)
	var team := PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg
	)
	for one: PBAttacker in team:
		one.ultimate = null
		one.move_speed = 0.0
		one.prime(_cfg.tick_rate, _cfg)
		one.revive()
		one.pos = Vector2(0.4, 0.2)
		one.hp = one.max_hp * 0.5
	return team


func test_self_recovery_is_permanent_half_second_percent_and_does_not_heal_teammates() -> void:
	var team := _team([&"naruto", &"minato"])
	var one := team[0]
	var before: float = one.hp
	var other: float = team[1].hp
	for tick: int in range(1, 10):
		PBHealingAuraRules.advance(team, _cfg, tick)
	assert_eq(one.hp, before)
	PBHealingAuraRules.advance(team, _cfg, 10)
	assert_almost_eq(one.hp, before + one.max_hp * 0.005, 0.000001)
	for tick: int in range(11, 41):
		PBHealingAuraRules.advance(team, _cfg, tick)
	assert_almost_eq(one.hp, before + one.max_hp * 0.02, 0.000001)
	assert_eq(team[1].hp, other)
	assert_false(PBSkillRules.can_cast(one, 1, 1000))
	assert_eq(one.skills[0].skill.mp_cost, 0.0)


func test_all_levels_of_area_recovery_use_450_code_boundary_and_current_position() -> void:
	for level: int in range(1, 11):
		var team := _team([&"kushina", &"minato"], level)
		var source := team[0]
		var target := team[1]
		target.pos = Vector2(0.625, 0.2)
		var own: float = source.hp
		var before: float = target.hp
		for tick: int in range(1, 21):
			PBHealingAuraRules.advance(team, _cfg, tick)
		assert_almost_eq(target.hp, before + 35.0 * level, 0.00001)
		assert_almost_eq(source.hp, own + 35.0 * level, 0.00001)
		target.pos = Vector2(0.6251, 0.2)
		before = target.hp
		PBHealingAuraRules.advance(team, _cfg, 21)
		assert_eq(target.hp, before)
		source.pos = Vector2(0.5, 0.2)
		PBHealingAuraRules.advance(team, _cfg, 22)
		assert_gt(target.hp, before)
		assert_false(PBSkillRules.can_cast(source, 1, 1000))


func test_same_aura_uses_strongest_and_dead_source_immediately_stops() -> void:
	var team := _team([&"kushina", &"kushina", &"minato"])
	team[0].skills[0].caster_level = 1
	var target := team[2]
	var before: float = target.hp
	PBHealingAuraRules.advance(team, _cfg, 1)
	assert_almost_eq(target.hp, before + 350.0 / 20.0, 0.000001)
	team[1].alive = false
	before = target.hp
	PBHealingAuraRules.advance(team, _cfg, 2)
	assert_almost_eq(target.hp, before + 35.0 / 20.0, 0.000001)
	team[0].alive = false
	before = target.hp
	PBHealingAuraRules.advance(team, _cfg, 3)
	assert_eq(target.hp, before)


func test_self_recovery_and_external_aura_stack_and_use_updated_max_health() -> void:
	var team := _team([&"naruto", &"kushina"])
	var one := team[0]
	PBAttributeRules.grant(one, {PBStatRules.STRENGTH: 10.0}, _cfg)
	var before: float = one.hp
	PBHealingAuraRules.advance(team, _cfg, 10)
	assert_almost_eq(one.hp, before + one.max_hp * 0.005 + 17.5, 0.000001)
	one.hp = one.max_hp - 1.0
	PBHealingAuraRules.advance(team, _cfg, 20)
	assert_eq(one.hp, one.max_hp)
	one.alive = false
	one.hp = 0.0
	PBHealingAuraRules.advance(team, _cfg, 30)
	assert_eq(one.hp, 0.0)


func test_healing_strength_applies_once_and_silence_does_not_disable_passive() -> void:
	var team := _team([&"kushina", &"minato"])
	team[0].skills[0].skill.heal_scale = 1.5
	var silence := PBBuff.new()
	silence.id = &"healing_silence"
	silence.kind = PBBuff.Kind.DURATION
	team[0].buffs.add(silence, {PBBuffRules.SILENCE: 1.0}, 0, 100, 0)
	var before: float = team[1].hp
	PBHealingAuraRules.advance(team, _cfg, 1)
	assert_almost_eq(team[1].hp, before + 17.5 * 1.5, 0.000001)


func test_invalid_healing_aura_configs_and_real_tooltip() -> void:
	var original := _cfg.skills.by_id(&"battle_chakra")
	assert_eq(PBSkillLoader.check(original), "")
	for patch: Dictionary in [
		{&"heal_aura_flat": -1.0},
		{&"heal_aura_period_ticks": 0},
		{&"heal_aura_max": 1.1},
		{&"heal_aura_hit_chance": 0.1},
		{&"mp_cost": 1.0},
		{&"target": PBSkill.Target.ENEMY}
	]:
		var skill := original.clone()
		for key: StringName in patch:
			skill.set(key, patch[key])
		assert_ne(PBSkillLoader.check(skill), "", str(patch))
	var text := PBEffectWords.skill_body(original, _cfg, 10)
	assert_string_contains(text, "450 码")
	assert_string_contains(text, "350 点")
	assert_string_contains(text, "不耗蓝")
	var ring := PBAuraRing.new()
	add_child_autofree(ring)
	ring.sync_preview(Vector2(0.4, 0.2), [original], Vector2(1.0, 0.3))
	assert_almost_eq(ring.radius_px, 0.225 * PBLayout.px_per_unit(Vector2(1.0, 0.3)), 0.0001)
