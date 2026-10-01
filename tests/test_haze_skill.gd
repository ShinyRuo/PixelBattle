extends GutTest

const TIMES: Array[int] = [1, 1, 2, 2, 2, 3, 3, 3, 3, 4]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _enemy() -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var one := PBEnemy.new()
	one.spawn(wave, 0.01, 0.5, 0)
	return one


func _haze(one: PBEnemy, level: int = 1, tick: int = 0) -> void:
	PBSkillRules.apply_all_enemy(one, _cfg.skills.by_id(&"haze_illusion").on_hit, level, _cfg, tick)


func test_every_level_disarms_both_normal_attack_kinds_and_expires_without_sweep() -> void:
	for level: int in range(1, 11):
		for kind: PBDamageKind.Type in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
			var enemy := _enemy()
			enemy.damage_kind = kind
			_haze(enemy, level, 5)
			var end: int = 5 + 20 * TIMES[level - 1]
			assert_false(enemy.ready_to_fire(end))
			assert_true(enemy.ready_to_fire(end + 1))
			assert_eq(enemy.buffs.amount(PBBuffRules.STUN, end), 0.0)
			assert_eq(enemy.buffs.amount(PBBuffRules.SILENCE, end), 0.0)
			enemy.advance(1.0, end)
			assert_almost_eq(enemy.distance, 0.4975, 0.00001)
			enemy.advance(1.0, end + 1)
			assert_almost_eq(enemy.distance, 0.4875, 0.00001)


func test_disarm_does_not_silence_active_enemy_abilities() -> void:
	var enemy := _enemy()
	_haze(enemy)
	var ability := PBEnemyAbility.new()
	ability.id = &"probe_active"
	ability.damage_base = 100.0
	ability.intellect_scale = 0.0
	enemy.abilities = [ability]
	enemy.ability_ready_at = PackedInt32Array([0])
	var ally := PBAttacker.new()
	ally.max_hp = 1000.0
	ally.hp = 1000.0
	ally.pos = enemy.pos()
	PBEnemyAbilityRules.advance(enemy, [ally], _cfg, 1, null, null, PBCombatOutcome.new())
	assert_lt(ally.hp, 1000.0)
	assert_eq(enemy.ability_ready_at[0], 1 + ability.cooldown_ticks)
	assert_false(enemy.ready_to_fire(1))


func test_skill_event_element_controls_vulnerability_independently_of_damage_kind() -> void:
	for kind: PBDamageKind.Type in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
		for element: PBElement.Type in PBElement.Type.values():
			var enemy := _enemy()
			_haze(enemy)
			var skill := PBSkill.new()
			skill.kind = kind
			skill.element = element
			skill.radius = 0.1
			var cast := PBSkillCast.new(skill)
			cast.spot = enemy.pos()
			var caster := PBAttacker.new()
			caster.attack_element = PBElement.Type.FIRE
			PBSkillRules.land(cast, [enemy], 0, _cfg, 1, caster, 100.0)
			var expected: float = 250.0 if element == PBElement.Type.SAGE else 200.0
			assert_almost_eq(enemy.max_hp - enemy.hp, expected, 0.001)


func test_normal_attack_single_skill_and_projectile_share_element_vulnerability() -> void:
	for path: int in 3:
		var enemy := _enemy()
		_haze(enemy)
		var caster := PBAttacker.new()
		caster.attack_element = PBElement.Type.SAGE
		var skill := PBSkill.new()
		skill.element = PBElement.Type.SAGE
		skill.target = PBSkill.Target.ENEMY
		var cast := PBSkillCast.new(skill)
		cast.target_slot = 0
		match path:
			0:
				PBStrikeRules.land(
					caster, enemy, 100.0, false, [enemy], _cfg, 1, null, PBCombatOutcome.new()
				)
			1:
				PBSkillRules.land_on_enemy(cast, [enemy], _cfg, 1, caster, 100.0)
			2:
				caster.attack_element = PBElement.Type.FIRE
				var shot := PBProjectile.new()
				shot.launch(Vector2.ZERO, 0, 100.0, 1.0, false, skill.element, 0, skill)
				PBSkillRules.hit_by_shot(enemy, shot, caster, _cfg, 1, null)
		assert_almost_eq(enemy.max_hp - enemy.hp, 250.0, 0.001)


func test_mixed_periodic_elements_are_scaled_before_combining_and_before_shields() -> void:
	var enemy := _enemy()
	_haze(enemy, 10)
	var expected: float = 0.0
	for element: PBElement.Type in [PBElement.Type.SAGE, PBElement.Type.FIRE]:
		var burn := PBBuff.new()
		burn.id = StringName("probe_%d" % element)
		burn.kind = PBBuff.Kind.PERIODIC
		burn.friendly = false
		burn.duration_seconds = 2.0
		burn.period_seconds = 1.0
		burn.mods = {PBBuffRules.HARM: 100.0}
		var source := PBHarmContext.new()
		source.element = element
		source.has_element = true
		PBSkillRules.apply_one_enemy(enemy, burn, burn.mods, _cfg, 0, source)
		expected += (
			100.0
			* _cfg.damage_multiplier(PBElement.relation(element, enemy.element))
			* (1.25 if element == PBElement.Type.SAGE else 1.0)
		)
	var shield := PBBuff.new()
	shield.id = &"probe_shield"
	enemy.buffs.add(shield, {PBBuffRules.SHIELD: 150.0}, 0, 100, 0)
	var harm: float = PBBuffRules.advance_enemy(enemy, 20, _cfg)
	assert_almost_eq(harm, expected, 0.001)
	enemy.take_damage(harm, 20)
	assert_almost_eq(enemy.max_hp - enemy.hp, expected * 2.0 - 150.0, 0.001)


func test_instant_harm_is_not_scaled_twice_and_expired_haze_has_no_bonus() -> void:
	for tick: int in [1, 21]:
		var enemy := _enemy()
		_haze(enemy)
		var buff := PBBuff.new()
		buff.id = &"probe_harm"
		buff.mods = {PBBuffRules.HARM: 100.0}
		var source := PBHarmContext.new()
		source.element = PBElement.Type.SAGE
		source.has_element = true
		PBSkillRules.apply_one_enemy(enemy, buff, buff.mods, _cfg, tick, source)
		var raw: float = (
			100.0 * _cfg.damage_multiplier(PBElement.relation(source.element, enemy.element))
		)
		assert_almost_eq(enemy.max_hp - enemy.hp, raw * (2.5 if tick == 1 else 1.0), 0.001)


func test_damage_to_kill_agrees_with_element_bonus_shield_and_refresh() -> void:
	var enemy := _enemy()
	enemy.hp = 100.0
	_haze(enemy)
	_haze(enemy, 1, 10)
	assert_eq(enemy.buffs.count(10), 1, "同 ID 刷新，不能把易伤叠乘")
	var shield := PBBuff.new()
	shield.id = &"probe_shield"
	enemy.buffs.add(shield, {PBBuffRules.SHIELD: 150.0}, 0, 100, 0)
	assert_almost_eq(enemy.damage_to_kill(25, PBElement.Type.SAGE), 100.0, 0.001)
	assert_true(enemy.take_damage(100.0, 25, null, false, PBElement.Type.SAGE))


func test_haze_validation_and_description() -> void:
	var skill: PBSkill = _cfg.skills.by_id(&"haze_illusion")
	var buff: PBBuff = skill.on_hit[0].duplicate(true)
	assert_eq(PBBuffRules.validate(buff), "")
	var body := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_string_contains(body, "禁攻")
	assert_string_contains(body, "4 秒")
	assert_string_contains(body, "仙属性伤害额外 ×1.25")
	buff.friendly = true
	assert_ne(PBBuffRules.validate(buff), "")
	buff.friendly = false
	buff.mods[PBBuffRules.SAGE_HURT_SCALE] = NAN
	assert_ne(PBBuffRules.validate(buff), "")


func test_real_multi_target_haze_applies_all_effects_only_after_each_projectile_lands() -> void:
	var patches: Dictionary = {}
	for bond: PBBond in _cfg.bonds.all():
		if bond.id == &"team_eight":
			patches = bond.member_skill_patches
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[PBUnit.new(_cfg.characters.by_id(&"kurenai"))],
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
		if cast.skill.id == &"haze_illusion":
			one.skills = [cast]
			break
	one.pos = Vector2(0.2, 0.0)
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	var wave := PBWave.new()
	wave.count = 5
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.6
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	assert_true(sim.cast_skill_at(one, sim.enemies()[3], 1))
	PBCastTestClock.release(sim, one)
	assert_eq(sim.enemies()[3].buffs.count(1), 0)
	for i: int in 4:
		sim.step()
	for index: int in 5:
		var enemy := sim.enemies()[index]
		assert_eq(enemy.ready_to_fire(10), index == 4)
		assert_eq(enemy.element_hurt_scale(PBElement.Type.SAGE, 10), 1.0 if index == 4 else 1.25)
		assert_eq(enemy.buffs.amount(PBBuffRules.HURT, 10), 1.0 if index == 4 else 2.0)
