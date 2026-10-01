extends GutTest

const SECONDS := [2, 2, 3, 3, 3, 4, 4, 4, 4, 5]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _caster(level: int = 1) -> PBAttacker:
	for character: PBCharacter in _cfg.characters.all():
		if character.skill_ids.has(&"almighty_push"):
			var unit := PBUnit.new(character)
			unit.level = level
			var one: PBAttacker = (
				PBCombatRules
				. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
			)
			one.max_hp = 10000.0
			one.hp = one.max_hp
			one.alive = true
			return one
	fail_test("缺少施法者")
	return PBAttacker.new()


func _cast(one: PBAttacker) -> PBSkillCast:
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"almighty_push":
			return cast
	return null


func _enemy() -> PBEnemy:
	var enemy := PBEnemy.new()
	enemy.alive = true
	enemy.max_hp = 10000.0
	enemy.hp = enemy.max_hp
	enemy.start_x = 1.0
	enemy.distance = 0.55
	return enemy


func _hit(one: PBAttacker, enemy: PBEnemy, tick: int = 1) -> PBCombatOutcome:
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(one, enemy, 100.0, PBElement.Type.PHYSICAL, _cfg, tick, null, null, out)
	return out


func test_all_levels_have_original_window_and_share_without_direct_damage() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var cast := _cast(one)
		PBSkillRules.apply_on_self(one, cast, _cfg, 7)
		var end: int = 7 + SECONDS[level - 1] * _cfg.tick_rate
		assert_almost_eq(
			one.buffs.amount(PBBuffRules.REFLECT, end), (10 + 3 * level) / 100.0, 0.00001
		)
		assert_eq(one.buffs.amount(PBBuffRules.REFLECT, end + 1), 0.0)
		assert_eq(cast.skill.power_mult, 0.0)
		assert_eq(cast.skill.damage, 0.0)
		assert_string_contains(PBEffectWords.skill_body(cast.skill, _cfg, level), "无直接伤害")
	assert_string_contains(PBEffectWords.skill_body(_cast(_caster()).skill, _cfg), "13%")


func test_local_knockback_does_not_damage_or_hit_outside_radius() -> void:
	var one := _caster()
	one.pos = Vector2(0.5, 0.0)
	var inside := _enemy()
	var outside := _enemy()
	outside.distance = 0.8
	PBSkillRules.land_on_field(_cast(one), [inside, outside], 0, _cfg, 1, one, 0.0)
	assert_almost_eq(inside.distance, 0.65, 0.00001)
	assert_eq(outside.distance, 0.8)
	assert_eq(inside.hp, inside.max_hp)
	assert_eq(outside.hp, outside.max_hp)


func test_reflection_uses_mitigated_hit_for_melee_and_ranged() -> void:
	for ranged: bool in [false, true]:
		var one := _caster()
		var enemy := _enemy()
		enemy.shot_speed = 0.05 if ranged else 0.0
		PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
		_hit(one, enemy)
		assert_almost_eq(enemy.max_hp - enemy.hp, (one.max_hp - one.hp) * 0.13, 0.00001)


func test_expired_window_does_not_reflect_a_later_hit() -> void:
	var one := _caster()
	var enemy := _enemy()
	PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
	_hit(one, enemy, 41)
	assert_eq(enemy.hp, enemy.max_hp)
	assert_lt(one.hp, one.max_hp)


func test_ninjutsu_uses_resistance_before_reflection_without_second_defence_pass() -> void:
	var one := _caster()
	one.defence = 10000.0
	one.ninjutsu_resist = 0.4
	var enemy := _enemy()
	enemy.armor = 10000.0
	enemy.ninjutsu_resist = 0.99
	PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
	PBStrikeRules.hurt_ally(
		one,
		enemy,
		100.0,
		PBElement.Type.PHYSICAL,
		_cfg,
		1,
		null,
		null,
		PBCombatOutcome.new(),
		PBEnemyHitContext.new([], false, PBDamageKind.Type.NINJUTSU)
	)
	assert_almost_eq(one.max_hp - one.hp, 60.0, 0.00001)
	assert_almost_eq(enemy.max_hp - enemy.hp, 60.0 * 0.13, 0.00001)


func test_shielded_hit_still_reflects_and_receiver_shield_absorbs_once() -> void:
	var one := _caster()
	one.defence = 0.0
	var enemy := _enemy()
	PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
	var shield := PBBuff.new()
	shield.id = &"test_shield"
	shield.kind = PBBuff.Kind.DURATION
	one.buffs.add(shield, {PBBuffRules.SHIELD: 1000.0}, 0, 40, 0)
	enemy.buffs.add(shield, {PBBuffRules.SHIELD: 5.0}, 0, 40, 0)
	_hit(one, enemy)
	assert_eq(one.hp, one.max_hp)
	assert_almost_eq(enemy.max_hp - enemy.hp, 8.0, 0.00001)


func test_recast_refreshes_instead_of_stacking() -> void:
	var one := _caster()
	PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
	PBSkillRules.apply_on_self(one, _cast(one), _cfg, 30)
	assert_almost_eq(one.buffs.amount(PBBuffRules.REFLECT, 70), 0.13, 0.00001)
	assert_eq(one.buffs.amount(PBBuffRules.REFLECT, 71), 0.0)


func test_permanent_and_melee_only_reflection_add_to_window() -> void:
	for ranged: bool in [false, true]:
		var one := _caster()
		one.reflect = 0.2
		one.melee_reflect = 0.1
		var enemy := _enemy()
		enemy.shot_speed = 0.05 if ranged else 0.0
		PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
		_hit(one, enemy)
		var share: float = 0.33 if ranged else 0.43
		assert_almost_eq(enemy.max_hp - enemy.hp, (one.max_hp - one.hp) * share, 0.00001)


func test_reflection_kill_is_counted_once_and_missing_source_is_safe() -> void:
	var one := _caster()
	PBSkillRules.apply_on_self(one, _cast(one), _cfg, 0)
	var enemy := _enemy()
	enemy.hp = 0.001
	assert_eq(_hit(one, enemy).kills, 1)
	assert_eq(_hit(one, enemy).kills, 0)
	assert_eq(_hit(one, null).kills, 0)


func test_reflection_definition_rejects_unsupported_target_and_negative_share() -> void:
	var buff := PBBuff.new()
	buff.kind = PBBuff.Kind.DURATION
	buff.mods = {PBBuffRules.REFLECT: 0.13}
	buff.friendly = false
	assert_ne(PBBuffFormula.validate(buff), "")
	buff.friendly = true
	assert_eq(PBBuffFormula.validate(buff), "")
	buff.mods[PBBuffRules.REFLECT] = -0.1
	assert_ne(PBBuffFormula.validate(buff), "")
