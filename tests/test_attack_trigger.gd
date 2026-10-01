extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _caster(level: int = 10, bonded: bool = true) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"tsunade"))
	unit.level = level
	var units: Array[PBUnit] = [unit]
	if bonded:
		for id: StringName in [&"gaara", &"mei", &"raikage", &"onoki"]:
			units.append(PBUnit.new(_cfg.characters.by_id(id)))
	var patches := PBBondRules.active_skill_patches(units, [unit], _cfg.bonds)
	var one := (
		PBCombatRules
		. build_attackers(
			[unit],
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
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	one.pos = Vector2(0.4, 0.2)
	return one


func _enemy(at: Vector2, slot: int = 0) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at.x, 0)
	enemy.lane = at.y
	enemy.slot = slot
	return enemy


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	return rng


func _fire(one: PBAttacker, enemies: Array[PBEnemy], tick: int = 1) -> PBCombatOutcome:
	one.attack_casts[0].skill.attack_trigger_chance = 1.0
	var out := PBCombatOutcome.new()
	PBOnAttackRules.fire(one, enemies[0], enemies, _cfg, tick, _rng(), null, out)
	return out


func test_granted_only_by_full_bond_and_self_attack_bonus_tracks_all_ten_levels() -> void:
	assert_true(_caster(10, false).attack_casts.is_empty())
	for level: int in range(1, 11):
		var one := _caster(level)
		assert_eq(one.attack_casts.size(), 1)
		var skill := one.attack_casts[0].skill
		assert_eq(skill.attack_trigger_chance, 0.2)
		assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(skill.element, PBElement.Type.PHYSICAL)
		assert_eq(PBCritRules.attack_kind(one), PBDamageKind.Type.TAIJUTSU)
		var rate: float = 0.1 + 0.04 * (level - 1)
		assert_almost_eq(PBAllyAuraRules.bonus_rate(one, 0), rate, 0.000001)
		var stats := PBStats.new()
		PBLiveReadout.update(stats, one, _cfg, 0)
		assert_almost_eq(
			stats.atk, one.damage_attributes[&"attack"] + one.base_attack * rate, 0.000001
		)
		assert_eq(skill.damage, floorf(one.damage_attributes[&"strength"]) * 1.5)


func test_seven_circles_repeat_overlap_and_primary_control_is_applied_only_once() -> void:
	var one := _caster()
	var main := _enemy(Vector2(0.5, 0.2))
	var overlap := _enemy(Vector2(0.66, 0.2), 1)
	var behind := _enemy(Vector2(0.43, 0.2), 2)
	var outside := _enemy(Vector2(0.66, 0.301), 3)
	var enemies: Array[PBEnemy] = [main, overlap, behind, outside]
	var raw: float = one.attack_casts[0].skill.damage
	_fire(one, enemies)
	assert_almost_eq(main.hp, main.max_hp - raw * 2.0, 0.001)
	assert_almost_eq(overlap.hp, overlap.max_hp - raw * 5.0, 0.001)
	assert_eq(behind.hp, behind.max_hp)
	assert_eq(outside.hp, outside.max_hp)
	assert_eq(main.buffs.amount(PBBuffRules.STUN, 21), 1.0)
	assert_eq(main.buffs.amount(PBBuffRules.AIRBORNE, 21), 1.0)
	assert_eq(main.buffs.amount(PBBuffRules.STUN, 22), 0.0)
	assert_eq(overlap.buffs.amount(PBBuffRules.STUN, 1), 0.0)
	assert_eq(one.attack_casts[0].trigger_center, Vector2(0.5, 0.2))
	assert_eq(one.attack_casts[0].trigger_tick, 1)


func test_ninjutsu_crit_bonus_resistance_and_penetration_are_independent_of_armor() -> void:
	var one := _caster()
	one.ninjutsu_crit_chance = 1.0
	one.ninjutsu_bonus = 0.5
	one.ninjutsu_pen = 0.5
	one.crit_bonus = 99.0
	one.damage_bonus = 99.0
	var enemy := _enemy(Vector2(0.5, 0.2))
	enemy.armor = 99999.0
	enemy.ninjutsu_resist = 0.4
	var raw: float = one.attack_casts[0].skill.damage
	var expected: float = (
		raw * 1.5 * PBCritRules.multiplier_of(one, 1, PBDamageKind.Type.NINJUTSU) * 0.8
	)
	_fire(one, [enemy])
	assert_almost_eq(enemy.hp, enemy.max_hp - expected * 2.0, 0.001)


func test_begin_swing_triggers_once_and_finishing_attack_does_not_trigger_again() -> void:
	var one := _caster()
	one.attack_casts[0].skill.attack_trigger_chance = 1.0
	one.reach = 0.2
	one.windup_ticks = 3
	one.next_shot_at = 0
	var enemy := _enemy(Vector2(0.5, 0.2))
	var out := PBCombatOutcome.new()
	var rng := _rng()
	var mana: float = one.mp
	PBStrikeRules.deal([one], [enemy], [], 0, _cfg, 1, rng, null, out)
	assert_true(one.swinging)
	assert_eq(one.attack_casts[0].trigger_tick, 1)
	var after: float = enemy.hp
	var end: int = one.next_shot_at
	PBStrikeRules.deal([one], [enemy], [], 0, _cfg, end, rng, null, out)
	assert_false(one.swinging)
	assert_eq(one.attack_casts[0].trigger_tick, 1)
	assert_lt(enemy.hp, after)
	assert_eq(one.mp, mana)
	assert_eq(one.attack_casts[0].ready_at, 0)


func test_no_rng_and_zero_chance_do_not_trigger_or_consume_randomness() -> void:
	var one := _caster()
	var enemy := _enemy(Vector2(0.5, 0.2))
	var out := PBCombatOutcome.new()
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 1, null, null, out)
	assert_eq(enemy.hp, enemy.max_hp)
	var rng := _rng()
	var before: int = rng.state
	one.attack_casts[0].skill.attack_trigger_chance = 0.0
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 1, rng, null, out)
	assert_eq(rng.state, before)
	assert_eq(one.attack_casts[0].trigger_tick, -1)


func test_attribute_transfer_refreshes_trigger_damage_and_wave_reset_clears_visual_state() -> void:
	var one := _caster()
	var raw: float = one.attack_casts[0].skill.damage
	PBAttributeRules.grant(one, {PBStatRules.STRENGTH: 20.0}, _cfg)
	assert_almost_eq(one.attack_casts[0].skill.damage, raw + 30.0, 0.000001)
	_fire(one, [_enemy(Vector2(0.5, 0.2))])
	var copy := one.clone()
	assert_eq(copy.attack_casts[0].trigger_tick, -1)
	copy.attack_casts[0].skill.damage = 1.0
	assert_ne(one.attack_casts[0].skill.damage, 1.0)
	one.revive()
	assert_eq(one.attack_casts[0].trigger_tick, -1)


func test_lethal_overlap_counts_each_enemy_once_and_does_not_control_corpses() -> void:
	var one := _caster()
	var main := _enemy(Vector2(0.5, 0.2))
	var other := _enemy(Vector2(0.66, 0.2), 1)
	main.hp = 1.0
	other.hp = 1.0
	var out := _fire(one, [main, other])
	assert_eq(out.kills, 2)
	assert_eq(main.buffs.amount(PBBuffRules.STUN, 1), 0.0)


func test_real_bond_tooltip_explains_overlap_control_and_damage_kind() -> void:
	var bond := _cfg.bonds.by_id(&"five_kage")
	var text := "\n".join(PBEffectWords.bond_effects(bond, _cfg))
	assert_string_contains(text, "20%")
	assert_string_contains(text, "共 7 圈")
	assert_string_contains(text, "忍术伤害（物理属性）")
	assert_string_contains(text, "仅主目标")
	assert_string_contains(text, "基础攻击 +10%")


func test_proc_roll_is_independent_and_failed_proc_does_not_roll_skill_crit() -> void:
	var one := _caster()
	var enemy := _enemy(Vector2(0.5, 0.2))
	var rng := _rng()
	var expected := _rng()
	var roll: float = expected.randf()
	one.attack_casts[0].skill.attack_trigger_chance = maxf(roll * 0.5, 0.0000001)
	one.ninjutsu_crit_chance = 1.0
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 1, rng, null, PBCombatOutcome.new())
	assert_eq(rng.state, expected.state)
	assert_eq(enemy.hp, enemy.max_hp)
	one.attack_casts[0].skill.attack_trigger_chance = 1.0
	expected.randf()
	expected.randf()
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 2, rng, null, PBCombatOutcome.new())
	assert_eq(rng.state, expected.state, "触发骰一次、整组技能暴击骰一次，不按七圈重复掷骰")


func test_zero_windup_uses_same_single_trigger_and_air_has_no_proc() -> void:
	var one := _caster()
	one.attack_casts[0].skill.attack_trigger_chance = 1.0
	one.windup_ticks = 0
	one.next_shot_at = 0
	one.reach = 0.2
	var rng := _rng()
	var before: int = rng.state
	PBStrikeRules.deal([one], [], [], 0, _cfg, 1, rng, null, PBCombatOutcome.new())
	assert_eq(rng.state, before)
	assert_eq(one.attack_casts[0].trigger_tick, -1)
	var enemy := _enemy(Vector2(0.5, 0.2))
	PBStrikeRules.deal([one], [enemy], [], 0, _cfg, 2, rng, null, PBCombatOutcome.new())
	assert_eq(one.attack_casts[0].trigger_tick, 2)
	assert_false(one.swinging)
	assert_gt(one.next_shot_at, 2)


func test_frontward_chain_rotates_with_attack_direction_and_does_not_hit_unspawned() -> void:
	var one := _caster()
	one.pos = Vector2(0.5, 0.1)
	var main := _enemy(Vector2(0.5, 0.2))
	var ahead := _enemy(Vector2(0.5, 0.36), 1)
	var future := _enemy(Vector2(0.5, 0.36), 2)
	future.spawn_tick = 100
	_fire(one, [main, ahead, future])
	assert_eq(one.attack_casts[0].trigger_direction, Vector2.DOWN)
	assert_lt(ahead.hp, ahead.max_hp)
	assert_eq(future.hp, future.max_hp)


func test_trigger_validator_rejects_ignored_or_invalid_configuration() -> void:
	var source := _cfg.skills.by_id(&"monstrous_strength")
	assert_eq(PBSkillLoader.check(source), "")
	for values: Dictionary in [
		{&"attack_trigger_chance": 1.1},
		{&"attack_chain_count": 33},
		{&"attack_chain_step": NAN},
		{&"cooldown_ticks": 1},
		{&"mp_cost": 1.0},
		{&"line_length": 1.0},
		{&"attack_chain_count": 0},
		{&"self_attack_bonus": -0.1}
	]:
		var copy := source.clone()
		for key: StringName in values:
			copy.set(key, values[key])
		assert_ne(PBOnAttackRules.validate(copy), "", str(values))
