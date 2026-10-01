extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.march_seconds = 1000000.0


func _caster(level: int = 1, enabled: bool = true) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"deidara"))
	unit.level = level
	var patches: Dictionary = {}
	if enabled:
		patches = {&"deidara": {&"clay_self_destruct": {PBSkillPatchRules.ON_DEATH: 1.0}}}
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
			patches
		)[0]
	)


func _enemy(hp: float = 10000.0, at: float = 0.5) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = hp
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at, 0)
	return enemy


func test_levels_and_kind_are_independent_of_skill_element() -> void:
	assert_true(_caster(1, false).death_casts.is_empty())
	for level: int in range(1, 11):
		var one := _caster(level)
		var skill := one.death_casts[0].skill
		assert_eq(skill.damage, level * 250.0)
		assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(skill.element, PBElement.Type.PHYSICAL)
		assert_eq(skill.power_mult, 0.0)
		for cast: PBSkillCast in one.skills:
			assert_ne(cast.skill.id, &"clay_self_destruct")


func test_each_target_uses_own_max_hp_and_linear_distance_falloff() -> void:
	var one := _caster(4)
	var cast := one.death_casts[0]
	cast.spot = Vector2(0.5, 0.0)
	for spec: Vector3 in [
		Vector3(10000, 0.5, 3600), Vector3(20000, 0.7, 3900), Vector3(10000, 0.9, 1800)
	]:
		var enemy := _enemy(spec.x, spec.y)
		enemy.hp = enemy.max_hp * 0.9
		assert_almost_eq(PBSkillDamage.area_damage(cast, enemy, cast.skill.damage), spec.z, 0.001)


func test_raw_formula_cap_precedes_existing_damage_multipliers() -> void:
	var one := _caster(10)
	var cast := one.death_casts[0]
	cast.spot = Vector2(0.5, 0.0)
	var boss := _enemy(1000000.0)
	assert_eq(PBSkillDamage.area_damage(cast, boss, cast.skill.damage), 13000.0)
	assert_eq(PBSkillDamage.area_damage(cast, boss, cast.skill.damage * 3.0), 39000.0)


func test_ninjutsu_resistance_penetration_and_shield_apply_once() -> void:
	var one := _caster()
	one.ninjutsu_bonus = 0.5
	one.ninjutsu_pen = 0.5
	one.taijutsu_bonus = 99.0
	var cast := one.death_casts[0]
	cast.spot = Vector2(0.5, 0.0)
	var enemy := _enemy()
	enemy.armor = 10000.0
	enemy.ninjutsu_resist = 0.4
	var shield := PBBuff.new()
	shield.id = &"probe_clay_shield"
	shield.kind = PBBuff.Kind.DURATION
	enemy.buffs.add(shield, {PBBuffRules.SHIELD: 100.0}, 0, 40, 0)
	var rolled := PBCritRules.hit(one, cast.skill.damage, cast.skill.kind, 1)
	PBSkillRules.land(cast, [enemy], 0, _cfg, 1, one, rolled[PBCritRules.DAMAGE])
	assert_almost_eq(enemy.max_hp - enemy.hp, (250.0 + 800.0) * 2.0 * 1.5 * 0.8 - 100.0, 0.001)


func test_sourceless_death_waits_then_bursts_once_without_moving() -> void:
	var one := _caster()
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	one.pos = Vector2(0.5, 0.0)
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var inside := sim.enemies()[0]
	var outside := sim.enemies()[1]
	inside.distance = 0.5
	inside.armor = 0.0
	inside.ninjutsu_resist = 0.0
	inside.speed = 0.0
	outside.distance = 0.95
	outside.speed = 0.0
	PBStrikeRules.wound_ally(one, 1.0e9, _cfg, 0, null, null, sim.result())
	sim.step()
	assert_eq(inside.hp, inside.max_hp)
	for tick: int in range(2, 21):
		sim.step()
	assert_almost_eq(inside.max_hp - inside.hp, 2100.0, 0.001)
	assert_eq(outside.hp, outside.max_hp)
	assert_false(one.death_pending)
	var after: float = inside.hp
	sim.step()
	assert_eq(inside.hp, after)
	assert_eq(sim.result().allies_lost, 1)


func test_area_parameters_reject_unsupported_shapes_and_tooltip_explains_formula() -> void:
	var skill := _caster().death_casts[0].skill
	assert_eq(PBSkillDamage.validate(skill), "")
	var text := PBEffectWords.skill_body(skill, _cfg)
	assert_string_contains(text, "目标最大生命 8%")
	assert_string_contains(text, "13000")
	assert_string_contains(text, "忍术伤害")
	skill.target = PBSkill.Target.ENEMY
	assert_ne(PBSkillDamage.validate(skill), "")
	skill.target = PBSkill.Target.GROUND
	skill.damage_base = 0.0
	assert_ne(PBSkillDamage.validate(skill), "")


func _moving_battle(one: PBAttacker) -> PBBattleSim:
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.01
	one.home = Vector2(0.3, 0.0)
	one.pos = one.home
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.6
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
		enemy.ninjutsu_resist = 0.0
	return sim


func _kill(one: PBAttacker, source: PBEnemy, sim: PBBattleSim) -> void:
	PBStrikeRules.hurt_ally(
		one,
		source,
		1.0e9,
		PBElement.Type.PHYSICAL,
		_cfg,
		sim.current_tick(),
		null,
		null,
		sim.result()
	)


func test_death_moves_twenty_steps_then_explodes_without_becoming_alive() -> void:
	var one := _caster()
	var sim := _moving_battle(one)
	var source := sim.enemies()[0]
	_kill(one, source, sim)
	assert_eq(one.death_target, source.pos())
	for tick: int in range(1, 21):
		sim.step()
		assert_false(one.alive)
		assert_false(one.is_targetable())
		assert_false(one.ready_to_fire(tick))
		assert_almost_eq(one.pos.x, 0.3 + tick * 0.01, 0.00001)
		if tick < 20:
			assert_eq(source.hp, source.max_hp)
	assert_lt(source.hp, source.max_hp)
	assert_eq(one.death_move_until, -1)
	var hp: float = source.hp
	sim.step()
	assert_eq(source.hp, hp)
	assert_eq(sim.result().allies_lost, 1)


func test_dead_or_moving_killer_does_not_change_saved_destination() -> void:
	var one := _caster()
	var sim := _moving_battle(one)
	var source := sim.enemies()[0]
	_kill(one, source, sim)
	source.distance = 0.1
	source.alive = false
	for tick: int in 20:
		sim.step()
	assert_almost_eq(one.pos.x, 0.5, 0.00001)
	assert_eq(one.death_target, Vector2(0.6, 0.0))
	assert_lt(sim.enemies()[1].hp, sim.enemies()[1].max_hp)


func test_arrival_stops_movement_but_does_not_shorten_fuse() -> void:
	var one := _caster()
	var sim := _moving_battle(one)
	var source := sim.enemies()[0]
	source.distance = 0.32
	_kill(one, source, sim)
	for tick: int in 19:
		sim.step()
	assert_eq(one.pos, Vector2(0.32, 0.0))
	assert_eq(source.hp, source.max_hp)
	sim.step()
	assert_lt(source.hp, source.max_hp)


func test_revive_clears_pending_motion_and_casts() -> void:
	var one := _caster()
	var sim := _moving_battle(one)
	_kill(one, sim.enemies()[0], sim)
	sim.step()
	assert_true(one.death_casts[0].is_pending())
	one.revive()
	assert_eq(one.death_tick, -1)
	assert_eq(one.death_target, Vector2.INF)
	assert_eq(one.death_move_until, -1)
	assert_false(one.death_casts[0].is_pending())


func test_surviving_lethal_hit_does_not_start_death_motion() -> void:
	var one := _caster()
	var sim := _moving_battle(one)
	one.revives = 1
	_kill(one, sim.enemies()[0], sim)
	assert_true(one.alive)
	assert_false(one.death_pending)
	assert_eq(one.death_tick, -1)
	assert_eq(one.death_target, Vector2.INF)
