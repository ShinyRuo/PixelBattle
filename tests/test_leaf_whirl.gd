extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.march_seconds = 1000000.0
	_cfg.unit_min_gap = 0.0


func _caster(level: int = 1, patch: Dictionary = {}) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"rock_lee"))
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
			{&"rock_lee": {&"leaf_whirl": patch}}
		)[0]
	)


func _enemy(at: float = 0.5) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at, 0)
	return enemy


func test_ten_levels_use_fixed_taijutsu_damage_without_attack_scaling() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var skill := one.skills[0].skill
		assert_eq(skill.damage, 50.0 * level)
		assert_eq(skill.kind, PBDamageKind.Type.TAIJUTSU)
		assert_eq(skill.element, PBElement.Type.PHYSICAL)
		assert_eq(skill.power_mult, 0.0)
		assert_eq(skill.hit_count, 7)
		assert_eq(skill.radius, 0.125)


func test_real_cast_has_seven_half_second_hits_and_locks_movement_and_attacks() -> void:
	var one := _caster()
	one.ultimate = null
	one.home = Vector2(0.5, 0.0)
	one.pos = one.home
	one.move_speed = 0.02
	one.attack = 10000.0
	one.reach = 0.01
	one.max_hp = 0.0
	one.mp_regen = 0.0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var enemy := sim.enemies()[0]
	enemy.distance = 0.6
	enemy.speed = 0.0
	enemy.armor = 0.0
	enemy.damage_per_shot = 0.0
	var mana: float = one.mp
	assert_true(sim.cast_skill_now(one, 1))
	for tick: int in range(1, 77):
		sim.step()
		assert_false(sim.can_cast(one, 1))
		assert_eq(one.pos, one.home)
		assert_false(one.ready_to_fire(tick))
		assert_almost_eq(
			enemy.max_hp - enemy.hp, maxf(floorf((tick - 6) / 10.0), 0.0) * 50.0, 0.001
		)
	assert_eq(sim.barrages()[0].fired, 7)
	assert_false(sim.barrages()[0].active())
	assert_almost_eq(one.mp, mana - 10.0, 0.001)
	assert_true(one.ready_to_fire(77))


func test_each_pulse_rechecks_targets_and_stops_after_caster_dies() -> void:
	var one := _caster()
	one.pos = Vector2(0.5, 0.0)
	var sequence := PBSkillBarrage.new()
	sequence.begin(one, one.skills[0], 10)
	var enemy := _enemy(0.8)
	sequence.advance([enemy], 0, _cfg, 10, null, null)
	assert_eq(enemy.hp, enemy.max_hp)
	enemy.distance = 0.6
	sequence.advance([enemy], 0, _cfg, 20, null, null)
	assert_eq(enemy.max_hp - enemy.hp, 50.0)
	one.alive = false
	sequence.advance([enemy], 0, _cfg, 30, null, null)
	assert_eq(enemy.max_hp - enemy.hp, 50.0)
	assert_false(sequence.active())


func test_ninjutsu_immunity_ignores_penetration_but_not_taijutsu() -> void:
	for kind: PBDamageKind.Type in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
		for tick: int in [1, 70, 71]:
			var one := _caster()
			one.alive = true
			one.hp = one.max_hp
			one.defence = 0.0
			one.ninjutsu_resist = 0.0
			PBSkillRules.apply_on_self(one, one.skills[0], _cfg, 0)
			PBStrikeRules.hurt_ally(
				one,
				_enemy(),
				100.0,
				PBElement.Type.PHYSICAL,
				_cfg,
				tick,
				null,
				null,
				PBCombatOutcome.new(),
				PBEnemyHitContext.new([], false, kind, 1.0, 1.0)
			)
			var immune: bool = kind == PBDamageKind.Type.NINJUTSU and tick <= 70
			assert_almost_eq(one.max_hp - one.hp, 0.0 if immune else 100.0, 0.001)


func test_bond_boosts_every_pulse_and_gathers_new_arrivals() -> void:
	var one := _caster(
		5,
		{
			PBSkillPatchRules.POWER_SCALE: 1.5,
			PBSkillPatchRules.RADIUS_SCALE: 1.5,
			PBSkillPatchRules.GATHER: 1.0
		}
	)
	one.pos = Vector2(0.5, 0.0)
	assert_eq(one.skills[0].skill.damage, 375.0)
	assert_eq(one.skills[0].skill.radius, 0.1875)
	var sequence := PBSkillBarrage.new()
	sequence.begin(one, one.skills[0], 10)
	var enemy := _enemy(0.68)
	sequence.advance([enemy], 0, _cfg, 10, null, null)
	assert_eq(enemy.pos(), one.pos)
	enemy.distance = 0.65
	sequence.advance([enemy], 0, _cfg, 20, null, null)
	assert_eq(enemy.pos(), one.pos)
	assert_eq(enemy.max_hp - enemy.hp, 750.0)


func test_tooltip_describes_each_hit_immunity_and_channel() -> void:
	var body := PBEffectWords.skill_body(_caster().skills[0].skill, _cfg)
	assert_string_contains(body, "共 7 段")
	assert_string_contains(body, "免疫忍术伤害")
	assert_string_contains(body, "原地施放")
