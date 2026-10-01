extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _caster(level: int, enabled: bool) -> PBAttacker:
	var patches: Dictionary = {}
	if enabled:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"leaf_and_root":
				patches = bond.member_skill_patches
	var unit := PBUnit.new(_cfg.characters.by_id(&"hiruzen"))
	unit.level = level
	var one: PBAttacker = (
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
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"fire_dragon":
			one.skills = [cast]
			break
	return one


func _enemy() -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	wave.element = PBElement.Type.PHYSICAL
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.5, 0)
	return enemy


func test_bond_boosts_initial_and_all_seven_burn_ticks_at_every_level() -> void:
	for level: int in range(1, 11):
		var one := _caster(level, true)
		var cast := one.skills[0]
		var enemy := _enemy()
		cast.spot = enemy.pos()
		PBSkillRules.land(cast, [enemy], 0, _cfg, 0, one, cast.skill.damage)
		assert_almost_eq(enemy.max_hp - enemy.hp, 280.0 * level, 0.001)
		var total: float = 0.0
		for tick: int in range(1, 161):
			var hurt: float = PBBuffRules.advance_enemy(enemy, tick, _cfg)
			var due: bool = tick <= 140 and tick % 20 == 0
			assert_almost_eq(hurt, 84.0 * level if due else 0.0, 0.001)
			total += hurt
		assert_almost_eq(total, 588.0 * level, 0.001)


func test_unbonded_burn_and_shared_resource_stay_unchanged() -> void:
	var shared: PBBuff = _cfg.skills.by_id(&"fire_dragon").on_hit[0]
	var boosted := _caster(5, true).skills[0].skill
	var plain := _caster(5, false).skills[0].skill
	assert_eq(float(shared.mods[PBBuffRules.HARM]), 60.0)
	assert_eq(float(shared.mods_growth[PBBuffRules.HARM]), 60.0)
	assert_almost_eq(float(boosted.on_hit[0].mods[PBBuffRules.HARM]), 84.0, 0.0001)
	assert_eq(float(plain.on_hit[0].mods[PBBuffRules.HARM]), 60.0)
	assert_eq(plain.damage, 1000.0)
	assert_eq(boosted.on_hit[0].duration_seconds, shared.duration_seconds)
	assert_eq(boosted.on_hit[0].period_seconds, shared.period_seconds)


func test_harm_patch_preserves_control_and_scales_attribute_payload_on_copy() -> void:
	var buff := PBBuff.new()
	buff.mods = {PBBuffRules.HARM: 10.0, PBBuffRules.ENEMY_SPEED_SCALE: 0.7}
	buff.mods_growth = {PBBuffRules.HARM: 5.0}
	buff.harm_stat = &"intellect"
	buff.harm_mult = 2.0
	var skill := PBSkill.new()
	skill.on_hit = [buff]
	var copy := skill.clone()
	PBSkillPatchRules.apply(copy, {PBSkillPatchRules.ON_HIT_HARM_SCALE: 1.4})
	var source := PBHarmContext.new()
	source.attributes = {&"intellect": 100.0}
	var result: Dictionary = PBBuffFormula.resolve(copy.on_hit[0], copy.on_hit[0].mods, source)
	assert_almost_eq(float(result[PBBuffRules.HARM]), 294.0, 0.0001)
	assert_eq(float(result[PBBuffRules.ENEMY_SPEED_SCALE]), 0.7)
	assert_eq(float(buff.mods[PBBuffRules.HARM]), 10.0)
	assert_eq(float(buff.mods_growth[PBBuffRules.HARM]), 5.0)
	assert_eq(buff.harm_mult, 2.0)


func test_burn_keeps_ninjutsu_resistance_and_fire_matchup() -> void:
	var one := _caster(1, true)
	var cast := one.skills[0]
	var enemy := _enemy()
	enemy.element = PBElement.Type.WIND
	enemy.armor = 10000.0
	enemy.ninjutsu_resist = 0.5
	cast.spot = enemy.pos()
	PBSkillRules.land(cast, [enemy], 0, _cfg, 0, one, cast.skill.damage)
	one.alive = false
	var expected: float = (
		84.0 * _cfg.damage_multiplier(PBElement.relation(PBElement.Type.FIRE, enemy.element)) * 0.5
	)
	assert_almost_eq(PBBuffRules.advance_enemy(enemy, 20, _cfg), expected, 0.001)
