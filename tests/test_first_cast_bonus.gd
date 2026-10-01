extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.march_seconds = 1000000.0


func _caster(enabled: bool = true) -> PBAttacker:
	var patches: Dictionary = {}
	if enabled:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"power_of_youth":
				patches = bond.member_skill_patches
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[PBUnit.new(_cfg.characters.by_id(&"might_guy"))],
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
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"leaf_gale":
			one.skills = [cast]
			break
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	one.ultimate = null
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.max_hp = 0.0
	one.max_mp = 1000.0
	one.mp_regen = 0.0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var enemy := sim.enemies()[0]
	enemy.distance = 0.5
	enemy.speed = 0.0
	enemy.armor = 0.0
	return sim


func _fire(sim: PBBattleSim, one: PBAttacker, _spot: Vector2) -> void:
	PBCastTestClock.recover(sim, one)
	one.skills[0].ready_at = sim.current_tick()
	assert_true(sim.cast_skill_at(one, sim.enemies()[0], 1))
	for tick: int in 14:
		sim.step()


func test_real_bond_adds_four_times_total_attack_only_to_owner() -> void:
	var one := _caster()
	var skill := one.skills[0].skill
	assert_almost_eq(skill.first_cast_damage, float(one.damage_attributes[&"attack"]) * 4.0, 0.001)
	assert_eq(skill.kind, PBDamageKind.Type.TAIJUTSU)
	assert_eq(skill.element, PBElement.Type.PHYSICAL)
	assert_eq(_caster(false).skills[0].skill.first_cast_damage, 0.0)
	assert_eq(_cfg.skills.by_id(&"leaf_gale").first_cast_attack, 0.0)


func test_first_cast_damage_and_cooldown_reset_do_not_repeat_bonus() -> void:
	var one := _caster()
	var sim := _sim(one)
	var enemy := sim.enemies()[0]
	var skill := one.skills[0].skill
	_fire(sim, one, enemy.pos())
	assert_almost_eq(enemy.max_hp - enemy.hp, skill.damage + skill.first_cast_damage, 0.001)
	assert_true(one.skills[0].first_cast_spent)
	var hp: float = enemy.hp
	enemy.buffs.clear()
	_fire(sim, one, enemy.pos())
	assert_almost_eq(hp - enemy.hp, skill.damage, 0.001)


func test_empty_first_cast_consumes_bonus_and_next_wave_restores_it() -> void:
	var one := _caster()
	var sim := _sim(one)
	var enemy := sim.enemies()[0]
	one.skills[0].cast_on(-1, sim.current_tick())
	sim.step()
	assert_eq(enemy.hp, enemy.max_hp)
	assert_true(one.skills[0].first_cast_spent)
	_fire(sim, one, enemy.pos())
	assert_almost_eq(enemy.max_hp - enemy.hp, one.skills[0].skill.damage, 0.001)
	var next := _sim(one)
	assert_false(one.skills[0].first_cast_spent)
	_fire(next, one, next.enemies()[0].pos())
	assert_almost_eq(
		next.enemies()[0].max_hp - next.enemies()[0].hp,
		one.skills[0].skill.damage + one.skills[0].skill.first_cast_damage,
		0.001
	)


func test_taijutsu_bonus_applies_once_without_ninjutsu_bonus() -> void:
	var one := _caster()
	one.taijutsu_bonus = 0.5
	one.ninjutsu_bonus = 99.0
	var sim := _sim(one)
	var skill := one.skills[0].skill
	var enemy := sim.enemies()[0]
	enemy.ninjutsu_resist = 1.0
	_fire(sim, one, enemy.pos())
	assert_almost_eq(enemy.max_hp - enemy.hp, (skill.damage + skill.first_cast_damage) * 1.5, 0.001)


func test_clone_and_tooltip_keep_definition_without_consumed_state() -> void:
	var one := _caster()
	one.skills[0].take_first_bonus()
	var copy := one.clone()
	assert_false(copy.skills[0].first_cast_spent)
	assert_eq(copy.skills[0].skill.first_cast_damage, one.skills[0].skill.first_cast_damage)
	assert_string_contains(PBEffectWords.skill_body(copy.skills[0].skill, _cfg), "首次施放")
