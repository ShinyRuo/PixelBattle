extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _caster(element: PBElement.Type = PBElement.Type.PHYSICAL) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"minato"))
	unit.level = 10
	var one := PBCombatRules.build_attackers([unit], element, 1.0, PackedFloat64Array(), _cfg)[0]
	one.ultimate = null
	one.move_speed = 0.0
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	one.pos = Vector2(0.4, 0.2)
	return one


func _enemy(slot: int = 0) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	var one := PBEnemy.new()
	one.spawn(wave, 0.0, 0.45, 0, 0.2)
	one.slot = slot
	return one


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 187
	return rng


func test_passive_is_two_extra_attacks_without_crit_or_mana_placeholder() -> void:
	var one := _caster()
	var skill: PBSkill = one.skills[1].skill
	assert_eq(skill.id, &"flying_raijin_chain")
	assert_eq(skill.attack_trigger_chance, 0.17)
	assert_eq(skill.attack_repeat_count, 2)
	assert_eq(one.crit_chance, 0.0)
	assert_eq(one.crit_bonus, 0.0)
	assert_false(PBSkillRules.can_cast(one, 2, 1))
	skill.attack_trigger_chance = 1.0
	var enemy := _enemy()
	var other := _enemy(1)
	var book := PBBattleLog.new()
	var mana: float = one.mp
	var expected: float = PBCritRules.strike(one, 1)[PBCritRules.DAMAGE] * 2.0
	PBOnAttackRules.fire(one, enemy, [enemy, other], _cfg, 1, _rng(), book, PBCombatOutcome.new())
	assert_almost_eq(enemy.hp, enemy.max_hp - expected, 0.001)
	assert_eq(other.hp, other.max_hp)
	assert_eq(book.entries.size(), 2)
	assert_eq(one.mp, mana)
	assert_eq(one.skills[1].ready_at, 0)


func test_repeats_use_taijutsu_crit_armor_and_water_element() -> void:
	var neutral := _caster()
	var one := _caster(PBElement.Type.FIRE)
	var relation: float = _cfg.damage_multiplier(
		PBElement.relation(PBElement.Type.WATER, PBElement.Type.FIRE)
	)
	assert_almost_eq(one.strike_for(1), neutral.strike_for(1) * relation, 0.000001)
	one.skills[1].skill.attack_trigger_chance = 1.0
	one.crit_chance = 1.0
	one.taijutsu_bonus = 0.5
	one.armor_pen = 0.5
	one.ninjutsu_bonus = 99.0
	one.ninjutsu_crit_chance = 1.0
	one.ninjutsu_crit_bonus = 99.0
	var enemy := _enemy()
	enemy.armor = 40.0
	enemy.ninjutsu_resist = 1.0
	var raw: float = one.strike_for(1) * 1.5 * PBCritRules.multiplier_of(one, 1)
	var expected: float = (
		PBStrikeRules.mitigated(one, enemy, raw, PBDamageKind.Type.TAIJUTSU, _cfg, 1) * 2.0
	)
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 1, _rng(), null, PBCombatOutcome.new())
	assert_almost_eq(enemy.hp, enemy.max_hp - expected, 0.001)
	assert_eq(PBCritRules.attack_kind(one), PBDamageKind.Type.TAIJUTSU)


func test_trigger_happens_once_at_windup_then_regular_attack_follows() -> void:
	var one := _caster()
	one.skills[1].skill.attack_trigger_chance = 1.0
	one.windup_ticks = 3
	one.next_shot_at = 0
	var enemy := _enemy()
	var book := PBBattleLog.new()
	var out := PBCombatOutcome.new()
	var rng := _rng()
	PBStrikeRules.deal([one], [enemy], [], 0, _cfg, 1, rng, book, out)
	assert_eq(book.entries.size(), 2)
	assert_true(one.swinging)
	PBStrikeRules.deal([one], [enemy], [], 0, _cfg, one.next_shot_at, rng, book, out)
	assert_eq(book.entries.size(), 3)
	assert_eq(one.skills[1].trigger_tick, 1)
	assert_false(one.swinging)


func test_repeats_apply_normal_hit_effects_but_do_not_recurse_or_hit_another_target() -> void:
	var one := _caster()
	one.skills[1].skill.attack_trigger_chance = 1.0
	var effect := PBBuff.new()
	effect.id = &"repeat_mark"
	effect.kind = PBBuff.Kind.DURATION
	effect.duration_seconds = 2.0
	effect.mods = {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}
	one.attack_buffs = [effect]
	var enemy := _enemy()
	var other := _enemy(1)
	var book := PBBattleLog.new()
	PBOnAttackRules.fire(one, enemy, [enemy, other], _cfg, 1, _rng(), book, PBCombatOutcome.new())
	assert_eq(book.entries.size(), 2)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 0.5)
	assert_eq(other.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)
	enemy.hp = 1.0
	book.clear()
	var out := PBCombatOutcome.new()
	PBOnAttackRules.fire(one, enemy, [enemy, other], _cfg, 2, _rng(), book, out)
	assert_eq(book.entries.size(), 1)
	assert_eq(out.kills, 1)
	assert_eq(other.hp, other.max_hp)


func test_current_attribute_changes_refresh_repeat_damage_and_wave_reset_clears_trigger() -> void:
	var one := _caster()
	one.skills[1].skill.attack_trigger_chance = 1.0
	var before: float = one.strike_for(1)
	PBAttributeRules.grant(one, {PBStatRules.AGILITY: 20.0}, _cfg)
	assert_gt(one.strike_for(1), before)
	var enemy := _enemy()
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 1, _rng(), null, PBCombatOutcome.new())
	assert_almost_eq(enemy.hp, enemy.max_hp - one.strike_for(1) * 2.0, 0.001)
	var copy := one.clone()
	copy.skills[1].skill.attack_repeat_count = 3
	assert_eq(one.skills[1].skill.attack_repeat_count, 2)
	one.revive()
	assert_eq(one.skills[1].trigger_tick, -1)


func test_invalid_repeat_configurations_are_rejected_and_tooltip_explains_normal_attacks() -> void:
	var original := _cfg.skills.by_id(&"flying_raijin_chain")
	assert_eq(PBSkillLoader.check(original), "")
	for patch: Dictionary in [
		{&"attack_repeat_count": -1},
		{&"attack_repeat_count": 9},
		{&"attack_trigger_chance": 0.0},
		{&"power_mult": 1.0},
		{&"radius": 0.1},
		{&"target": PBSkill.Target.GROUND},
		{&"mp_cost": 1.0}
	]:
		var skill := original.clone()
		for key: StringName in patch:
			skill.set(key, patch[key])
		assert_ne(PBSkillLoader.check(skill), "", str(patch))
	var text := PBOnAttackWords.body(original, _cfg, 10)
	assert_string_contains(text, "17%")
	assert_string_contains(text, "额外普攻 2 次")
	assert_string_contains(text, "不耗蓝")
