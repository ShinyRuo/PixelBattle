extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _caster(level: int = 10, bonded: bool = false) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"raikage"))
	unit.level = level
	var units: Array[PBUnit] = [unit]
	if bonded:
		for id: StringName in [&"gaara", &"mei", &"tsunade", &"onoki"]:
			units.append(PBUnit.new(_cfg.characters.by_id(id)))
	var passives := PBBondRules.active_passives(units, [unit], _cfg.bonds)
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
			passives,
			{},
			[{PBStatRules.STRENGTH: 7.0}]
		)[0]
	)
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	return one


func _enemy(ranged: bool = true) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.8, 0)
	enemy.shot_speed = 0.1 if ranged else 0.0
	return enemy


func _hit(one: PBAttacker, enemy: PBEnemy, tick: int, damage: float = 0.0) -> void:
	PBStrikeRules.hurt_ally(
		one, enemy, damage, PBElement.Type.PHYSICAL, _cfg, tick, null, null, PBCombatOutcome.new()
	)


func test_all_levels_have_actual_strength_and_hp_with_original_integer_snapshot() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var strength: float = one.damage_attributes[&"strength"]
		var hp: float = one.max_hp
		var mana: float = one.max_mp
		var attack: float = one.damage_attributes[&"attack"]
		one.hp = hp * 0.4
		_hit(one, _enemy(), 1)
		var extra: float = floorf(strength * 0.3)
		assert_eq(one.damage_attributes[&"strength"], strength + extra)
		assert_eq(one.max_hp, hp + extra * 80.0)
		assert_almost_eq(one.hp / one.max_hp, 0.4, 0.000001)
		assert_eq(one.max_mp, mana)
		assert_eq(one.damage_attributes[&"attack"], attack + extra * 3.5)
		assert_eq(one.buffs.amount(PBBuffRules.DAMAGE_SCALE, 1), 1.0)
		assert_eq(one.struck_ready_at, 201)
		PBTemporaryAttributeRules.refresh(one, _cfg, 101)
		assert_eq(one.max_hp, hp + extra * 80.0)
		PBTemporaryAttributeRules.refresh(one, _cfg, 102)
		assert_almost_eq(one.max_hp, hp, 0.000001)
		assert_eq(one.damage_attributes[&"strength"], strength)
		assert_almost_eq(one.hp / one.max_hp, 0.4, 0.000001)


func test_five_kage_changes_bonus_to_half_and_adds_five_second_dodge() -> void:
	var one := _caster(10, true)
	var strength: float = one.damage_attributes[&"strength"]
	_hit(one, _enemy(), 1)
	assert_eq(one.damage_attributes[&"strength"], strength + floorf(strength * 0.5))
	assert_eq(one.buffs.amount(PBBuffRules.DODGE, 101), 0.5)
	assert_eq(one.buffs.amount(PBBuffRules.DODGE, 102), 0.0)
	assert_eq(one.buffs.amount(PBBuffRules.DAMAGE_TAKEN, 21), 0.0)
	assert_eq(one.buffs.amount(PBBuffRules.DAMAGE_TAKEN, 22), 1.0)
	assert_eq(one.struck_ready_at, 201)
	assert_eq(
		_cfg.characters.by_id(&"raikage").struck_buffs[0].mods[PBBuffRules.STRENGTH_BONUS], 0.3
	)


func test_reapply_refreshes_without_multiplying_its_own_strength() -> void:
	var one := _caster()
	var original: float = one.damage_attributes[&"strength"]
	var buff: PBBuff = one.struck_buffs[0]
	PBSkillRules.apply_one(one, buff, PBBuffRules.resolve(buff, 10), _cfg, 1)
	var once: float = one.damage_attributes[&"strength"]
	PBSkillRules.apply_one(one, buff, PBBuffRules.resolve(buff, 10), _cfg, 50)
	assert_eq(one.damage_attributes[&"strength"], once)
	PBTemporaryAttributeRules.refresh(one, _cfg, 150)
	assert_eq(one.damage_attributes[&"strength"], once)
	PBTemporaryAttributeRules.refresh(one, _cfg, 151)
	assert_eq(one.damage_attributes[&"strength"], original)


func test_expiry_removes_only_temporary_gain_and_keeps_later_attribute_gifts() -> void:
	var one := _caster()
	var original: float = one.damage_attributes[&"strength"]
	_hit(one, _enemy(), 1)
	PBAttributeRules.grant(one, {PBStatRules.STRENGTH: 20.0}, _cfg)
	assert_eq(one.damage_attributes[&"strength"], original + floorf(original * 0.3) + 20.0)
	PBTemporaryAttributeRules.refresh(one, _cfg, 102)
	assert_eq(one.damage_attributes[&"strength"], original + 20.0)
	PBAttributeRules.reset(one, _cfg)
	assert_eq(one.damage_attributes[&"strength"], original)


func test_close_attack_does_not_trigger_and_cooldown_prevents_refresh() -> void:
	var one := _caster()
	var original: float = one.damage_attributes[&"strength"]
	var start: Vector2 = one.pos
	_hit(one, _enemy(false), 1)
	assert_eq(one.damage_attributes[&"strength"], original)
	assert_eq(one.pos, start)
	_hit(one, _enemy(), 2)
	assert_ne(one.pos, start)
	var boosted: float = one.damage_attributes[&"strength"]
	_hit(one, _enemy(), 50)
	assert_eq(one.damage_attributes[&"strength"], boosted)
	PBTemporaryAttributeRules.refresh(one, _cfg, 103)
	assert_eq(one.damage_attributes[&"strength"], original, "冷却期间受击不能续五秒")


func test_real_simulation_expires_buff_and_reused_attacker_starts_at_baseline() -> void:
	var one := _caster()
	one.move_speed = 0.0
	var base: float = one.max_hp
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.spawn_tick = 0
	enemy.distance = 0.8
	enemy.speed = 0.0
	enemy.damage_per_shot = 0.0
	enemy.shot_speed = 0.1
	_hit(one, enemy, 1)
	assert_gt(one.max_hp, base)
	for tick: int in 102:
		sim.step()
	assert_almost_eq(one.max_hp, base, 0.000001)
	_hit(one, enemy, 202)
	assert_gt(one.max_hp, base)
	var next := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	assert_almost_eq(one.max_hp, base, 0.000001)
	assert_true(one.attribute_profile.temporary.is_empty())
	assert_eq(next.current_tick(), 0)


func test_opening_total_bonus_does_not_multiply_runtime_attribute_gifts() -> void:
	var character := _cfg.characters.by_id(&"gaara")
	var mods: Dictionary = {PBStatRules.ALL_STATS_TOTAL_BONUS: 0.2}
	var base := PBStatRules.of(character, 10, 1, _cfg, mods)
	var added := PBStatRules.of(character, 10, 1, _cfg, mods, {PBStatRules.STRENGTH: 13.0})
	assert_eq(added.strength - base.strength, 13.0)


func test_strength_configuration_rejects_enemy_or_instant_effects() -> void:
	var buff := PBBuff.new()
	buff.id = &"strength_check"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 5.0
	buff.mods = {PBBuffRules.STRENGTH_BONUS: 0.3}
	assert_eq(PBBuffRules.validate(buff), "")
	buff.friendly = false
	assert_ne(PBBuffRules.validate(buff), "")
	buff.friendly = true
	buff.kind = PBBuff.Kind.INSTANT
	assert_ne(PBBuffRules.validate(buff), "")
