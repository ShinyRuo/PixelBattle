extends GutTest
## 固定区域持续伤害、属性快照、分级时长与防御交互。

const IDS: Array[StringName] = [&"wood_descent"]
const DURATIONS: Array[float] = [1.5, 1.5, 2.0, 2.0, 2.0, 2.5, 2.5, 3.0, 3.0, 3.5]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0


func _caster(id: StringName, level: int = 1, mods: Dictionary = {}) -> PBAttacker:
	for character: PBCharacter in _cfg.characters.all():
		if not character.skill_ids.has(id):
			continue
		var unit := PBUnit.new(character)
		unit.level = level
		return (
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
				{},
				[mods]
			)[0]
		)
	fail_test("技能必须能找到施法者")
	return PBAttacker.new()


func _cast(one: PBAttacker, id: StringName) -> PBSkillCast:
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == id:
			return cast
	return null


func _enemy(at: float = 0.3) -> PBEnemy:
	var wave := PBWave.new()
	wave.element = PBElement.Type.PHYSICAL
	wave.hp_each = 1000000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at, 0)
	return enemy


func _land(one: PBAttacker, id: StringName, enemies: Array[PBEnemy], tick: int = 0) -> PBHazardZone:
	var cast := _cast(one, id)
	cast.spot = enemies[0].pos()
	var zone := PBHazardZone.new()
	zone.begin(one, cast, tick)
	zone.advance(enemies, 0, _cfg, tick, null, null)
	return zone


func _raw(one: PBAttacker, id: StringName, level: int) -> float:
	match id:
		&"wood_descent":
			return 17.5 * level + 0.2 * floorf(float(one.damage_attributes[&"strength"]))
		&"boil_acid":
			return 30.0 * level + 0.5 * float(one.damage_attributes[&"agility"])
	return 50.0 * level


func test_fixed_area_has_no_initial_damage_and_twelve_half_second_hits() -> void:
	for level: int in [1, 5, 10]:
		var one := _caster(&"wood_descent", level)
		var enemy := _enemy()
		var zone := _land(one, &"wood_descent", [enemy], 7)
		var expected := (
			_raw(one, &"wood_descent", level)
			* _cfg.damage_multiplier(PBElement.relation(zone.cast.skill.element, enemy.element))
		)
		for tick: int in range(7, 139):
			zone.advance([enemy], 0, _cfg, tick, null, null)
			assert_almost_eq(enemy.max_hp - enemy.hp, expected * mini((tick - 7) / 10, 12), 0.001)
		assert_eq(zone.fired, 12)
		assert_false(zone.active())


func test_area_control_rechecks_entry_exit_and_expires() -> void:
	var one := _caster(&"wood_descent", 6)
	var inside := _enemy()
	var outside := _enemy(0.9)
	var zone := _land(one, &"wood_descent", [inside, outside])
	assert_almost_eq(inside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 0), 0.7, 0.0001)
	assert_eq(outside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 0), 1.0)
	inside.distance = 0.9
	outside.distance = 0.3
	zone.advance([inside, outside], 0, _cfg, 3, null, null)
	assert_eq(inside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 3), 1.0)
	assert_almost_eq(outside.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 3), 0.7, 0.0001)
	zone.advance([inside, outside], 0, _cfg, 119, null, null)
	zone.advance([inside, outside], 0, _cfg, 120, null, null)
	assert_eq(outside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 121), 1.0)


func test_sand_duration_follows_each_original_level_bracket() -> void:
	var skill: PBSkill = _cfg.skills.by_id(&"sand_burial")
	var buff: PBBuff = skill.on_start_area[0]
	for index: int in DURATIONS.size():
		assert_eq(buff.seconds_at(index + 1), DURATIONS[index])
	assert_eq(buff.seconds_at(99), 3.5, "等级超出数据范围不能越界")
	assert_eq(buff.duration_ticks(_cfg, 1), 30)
	assert_eq(buff.duration_ticks(_cfg, 10), 70)


func test_equipment_snapshot_survives_attribute_change_and_source_death() -> void:
	var plain := _caster(&"wood_descent")
	var boosted := _caster(&"wood_descent", 1, {PBStatRules.STRENGTH: 100.0})
	var first := _enemy()
	var second := _enemy()
	var a := _land(plain, &"wood_descent", [first])
	var b := _land(boosted, &"wood_descent", [second])
	boosted.damage_attributes[&"strength"] = 999999.0
	boosted.skills[0].skill.damage = 999999.0
	boosted.alive = false
	a.advance([first], 0, _cfg, 10, null, null)
	b.advance([second], 0, _cfg, 10, null, null)
	var expected := (
		20.0 * _cfg.damage_multiplier(PBElement.relation(a.cast.skill.element, first.element))
	)
	assert_almost_eq(first.hp - second.hp, expected, 0.001)
	assert_true(b.active())


func test_acid_debuff_changes_taijutsu_but_not_its_own_ninjutsu_damage() -> void:
	var one := _caster(&"boil_acid", 5)
	var enemy := _enemy()
	enemy.armor = 100.0
	var cast := _cast(one, &"boil_acid")
	cast.spot = enemy.pos()
	var zone := PBHazardZone.new()
	zone.begin(one, cast, 0)
	zone.advance([enemy], 0, _cfg, 0, null, null)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 80), -15.0)
	var raw: float = _raw(one, &"boil_acid", 5) * 0.5
	var expected: float = (
		raw
		* _cfg.damage_multiplier(
			PBElement.relation(_cast(one, &"boil_acid").skill.element, enemy.element)
		)
	)
	zone.advance([enemy], 0, _cfg, 10, null, null)
	assert_almost_eq(enemy.max_hp - enemy.hp, expected, 0.001)
	assert_almost_eq(
		PBStrikeRules.mitigated(null, enemy, 100.0, PBDamageKind.Type.TAIJUTSU, _cfg, 20),
		100.0 * (1.0 - PBStatRules.damage_reduction(85.0, _cfg)),
		0.001
	)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 91), 0.0)


func test_repeated_casts_keep_independent_damage_and_shared_control_definition() -> void:
	var one := _caster(&"wood_descent", 3)
	var enemy := _enemy()
	var shared := _cfg.skills.by_id(&"wood_descent").zone_effects[0]
	var first := _land(one, &"wood_descent", [enemy])
	var second := _land(one, &"wood_descent", [enemy], 5)
	first.advance([enemy], 0, _cfg, 10, null, null)
	second.advance([enemy], 0, _cfg, 10, null, null)
	var once := enemy.max_hp - enemy.hp
	second.advance([enemy], 0, _cfg, 15, null, null)
	assert_almost_eq(enemy.max_hp - enemy.hp, once * 2, 0.001)
	assert_false(shared.mods.has(PBBuffRules.HARM))
	assert_almost_eq(shared.mods[PBBuffRules.ENEMY_SPEED_SCALE], 0.7, 0.0001)


func test_real_area_damage_uses_bonus_resistance_shield_and_counts_kill_once() -> void:
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_cfg.unit_min_gap = 0
	var one := _caster(&"wood_descent", 1)
	one.attack = 0
	one.dps = 0
	one.move_speed = 0
	one.ninjutsu_bonus = 1
	one.ninjutsu_pen = 0.5
	one.ninjutsu_crit_chance = 0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 10000
	wave.resist_each = 0.4
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0, 0, _cfg, [one])
	var enemy := sim.enemies()[0]
	enemy.distance = 0.3
	enemy.speed = 0
	enemy.damage_per_shot = 0
	var guard := PBBuff.new()
	guard.id = &"area_guard"
	guard.kind = PBBuff.Kind.DURATION
	enemy.buffs.add(guard, {PBBuffRules.SHIELD: 20.0}, 0, 100, 0)
	assert_true(sim.cast_skill(one, enemy.pos(), 1))
	for tick: int in 16:
		sim.step()
	var jump := (
		_raw(one, &"wood_descent", 1)
		* 2
		* 0.8
		* _cfg.damage_multiplier(PBElement.relation(one.skills[0].skill.element, enemy.element))
	)
	assert_almost_eq(enemy.hp, 10020.0 - jump, 0.001)
	assert_eq(enemy.buffs.shield_left(16), 0.0)
	enemy.hp = 1
	for tick: int in 20:
		sim.step()
	assert_false(enemy.alive)
	assert_eq(sim.result().kills, 1)


func test_zero_initial_damage_does_not_roll_a_spurious_critical() -> void:
	var one := _caster(&"sand_burial")
	one.ninjutsu_crit_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var before: int = rng.state
	var roll := PBCritRules.hit(one, 0.0, PBDamageKind.Type.NINJUTSU, 0, rng)
	assert_false(roll[PBCritRules.CRIT])
	assert_eq(rng.state, before)


func test_level_duration_reaches_ally_skills_and_triggered_effects() -> void:
	var buff := PBBuff.new()
	buff.id = &"level_duration"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 1.0
	buff.duration_levels = PackedFloat32Array([1.0, 3.0])
	buff.mods = {PBBuffRules.DEFENCE: 10.0}
	var one := _caster(&"wood_descent", 2)
	var skill := PBSkill.new()
	skill.on_self = [buff]
	PBSkillRules.apply_on_self(one, PBSkillCast.new(skill, 2), _cfg, 0)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 60), 10.0)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 61), 0.0)
	one.buffs.clear()
	one.open_low_hp = 1.0
	one.low_hp_buffs = [buff]
	PBStrikeRules.open_wave(one, _cfg)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 60), 10.0)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 61), 0.0)
	one.buffs.clear()
	one.struck_buffs = [buff]
	one.revive()
	PBStrikeRules.hurt_ally(
		one, _enemy(), 1.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, PBCombatOutcome.new()
	)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 60), 10.0)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 61), 0.0)


func test_invalid_attribute_formula_and_duration_data_are_rejected() -> void:
	var buff := PBBuff.new()
	buff.id = &"invalid_formula"
	buff.kind = PBBuff.Kind.PERIODIC
	buff.duration_seconds = 1.0
	buff.period_seconds = 0.5
	buff.mods = {PBBuffRules.HARM: 1.0}
	buff.harm_stat = &"typo"
	assert_ne(PBBuffRules.validate(buff), "")
	buff.harm_stat = &"strength"
	buff.harm_mult = -1.0
	assert_ne(PBBuffRules.validate(buff), "")
	buff.harm_mult = 0.4
	buff.duration_levels = PackedFloat32Array([0.0])
	assert_ne(PBBuffRules.validate(buff), "")
	buff.duration_levels = PackedFloat32Array([1.5, 2.0])
	assert_eq(PBBuffRules.validate(buff), "")
