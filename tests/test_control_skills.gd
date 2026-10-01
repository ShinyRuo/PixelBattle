extends GutTest
## 原版无伤害技能：自身周围控制、防御加成、单体缠绕及等级时间窗口。

const GUARD_SECONDS := [2, 2, 3, 3, 3, 4, 4, 5, 5, 6]
const STUN_SECONDS := [1.0, 1.0, 1.5, 1.5, 1.5, 2.0, 2.0, 2.0, 2.0, 2.5]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.march_seconds = 1000000.0


func _caster(id: StringName, level: int = 1) -> PBAttacker:
	for character: PBCharacter in _cfg.characters.all():
		if character.skill_ids.has(id):
			var unit := PBUnit.new(character)
			unit.level = level
			return (
				PBCombatRules
				. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
			)
	fail_test("没有技能所属角色")
	return PBAttacker.new()


func _cast(one: PBAttacker, id: StringName) -> PBSkillCast:
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == id:
			return cast
	return null


func _enemy(at: Vector2 = Vector2(0.5, 0.3)) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 10000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at.x, 0, at.y)
	return enemy


func test_control_skills_do_not_invent_damage_at_any_level() -> void:
	for id: StringName in [&"susanoo", &"deep_forest"]:
		for level: int in range(1, 11):
			var one := _caster(id, level)
			var cast := _cast(one, id)
			assert_eq(cast.skill.damage, 0.0)
			assert_eq(cast.skill.power_mult, 0.0)
			assert_eq(cast.skill.shot_cross_seconds, 0.0)
			assert_eq(cast.skill.slow_ticks, 0, "控制不能误用全场减速")
			assert_string_contains(PBEffectWords.skill_body(cast.skill, _cfg, level), "无直接伤害")
	var periodic := _cast(_caster(&"wood_descent"), &"wood_descent")
	assert_string_contains(PBEffectWords.skill_body(periodic.skill, _cfg), "忍术伤害")


func test_guard_and_stun_use_original_ten_level_durations() -> void:
	for level: int in range(1, 11):
		var one := _caster(&"susanoo", level)
		var cast := _cast(one, &"susanoo")
		one.pos = Vector2(0.5, 0.3)
		var enemy := _enemy()
		PBSkillRules.apply_on_self(one, cast, _cfg, 9)
		PBSkillRules.land_on_field(cast, [enemy], 0, _cfg, 10, one, 0.0)
		var guard_end: int = 9 + GUARD_SECONDS[level - 1] * _cfg.tick_rate
		var stun_end: int = 10 + int(STUN_SECONDS[level - 1] * _cfg.tick_rate)
		assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, guard_end), 10.0 * level)
		assert_eq(one.buffs.amount(PBBuffRules.NINJUTSU_RESIST, guard_end), 0.4)
		assert_eq(one.buffs.amount(PBBuffRules.DAMAGE_TAKEN, guard_end), 1.0)
		assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, guard_end + 1), 0.0)
		assert_eq(one.buffs.amount(PBBuffRules.NINJUTSU_RESIST, guard_end + 1), 0.0)
		assert_false(enemy.ready_to_fire(stun_end))
		assert_true(enemy.ready_to_fire(stun_end + 1))
		assert_eq(enemy.hp, enemy.max_hp)


func test_self_area_uses_current_caster_position_and_two_dimensional_radius() -> void:
	var one := _caster(&"susanoo")
	one.pos = Vector2(0.5, 0.3)
	var cast := _cast(one, &"susanoo")
	cast.spot = Vector2.ZERO
	var inside := _enemy(Vector2(0.6, 0.3))
	var outside_x := _enemy(Vector2(0.7, 0.3))
	var outside_y := _enemy(Vector2(0.5, 0.5))
	PBSkillRules.land_on_field(cast, [inside, outside_x, outside_y], 0, _cfg, 0, one, 0.0)
	assert_false(inside.ready_to_fire(1))
	assert_true(outside_x.ready_to_fire(1))
	assert_true(outside_y.ready_to_fire(1))
	inside.speed = 0.1
	inside.march_to(Vector2.ZERO, 1.0, 1)
	assert_eq(inside.pos(), Vector2(0.6, 0.3))
	inside.march_to(Vector2.ZERO, 1.0, 21)
	assert_ne(inside.pos(), Vector2(0.6, 0.3))


func test_guard_reduces_actual_enemy_taijutsu_and_ninjutsu_separately() -> void:
	var one := _caster(&"susanoo", 5)
	var cast := _cast(one, &"susanoo")
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	PBSkillRules.apply_on_self(one, cast, _cfg, 0)
	for kind: PBDamageKind.Type in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
		for tick: int in [1, 61]:
			one.hp = one.max_hp
			var expected: float = 100.0
			if kind == PBDamageKind.Type.TAIJUTSU:
				expected *= (
					1.0
					- PBStatRules.damage_reduction(one.defence + (50.0 if tick == 1 else 0.0), _cfg)
				)
			else:
				expected *= 1.0 - one.ninjutsu_resist - (0.4 if tick == 1 else 0.0)
			PBStrikeRules.hurt_ally(
				one,
				null,
				100.0,
				PBElement.Type.PHYSICAL,
				_cfg,
				tick,
				null,
				null,
				PBCombatOutcome.new(),
				PBEnemyHitContext.new([], false, kind)
			)
			assert_almost_eq(one.max_hp - one.hp, expected, 0.001)


func test_roots_bind_only_the_selected_enemy_for_level_duration() -> void:
	for level: int in range(1, 11):
		var one := _caster(&"deep_forest", level)
		var cast := _cast(one, &"deep_forest")
		var target := _enemy()
		var neighbor := _enemy()
		cast.target_slot = 0
		PBSkillRules.land_on_enemy(cast, [target, neighbor], _cfg, 4, one, 0.0)
		var until: int = 4 + (level + 1) * 10
		assert_false(target.ready_to_fire(until))
		assert_true(target.ready_to_fire(until + 1))
		assert_eq(target.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, until), 0.0)
		assert_eq(target.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, until + 1), 1.0)
		assert_true(neighbor.ready_to_fire(4))
		assert_eq(target.hp, target.max_hp)


func _sim(one: PBAttacker, cast: PBSkillCast) -> PBBattleSim:
	one.ultimate = null
	one.skills = [cast]
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.max_hp = 0.0
	one.max_mp = 100.0
	one.mp_regen = 0.0
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 10000.0
	return PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])


func test_real_battle_applies_roots_without_projectile_or_damage() -> void:
	var one := _caster(&"deep_forest", 10)
	var cast := _cast(one, &"deep_forest")
	var sim := _sim(one, cast)
	var enemy := sim.enemies()[0]
	assert_true(sim.cast_skill_at(one, enemy, 1))
	PBCastTestClock.release(sim, one)
	assert_false(enemy.ready_to_fire(1))
	assert_eq(enemy.hp, enemy.max_hp)
	assert_eq(one.mp, 59.0)
	assert_eq(cast.ready_at, 286)
	for shot: PBProjectile in sim.shots():
		assert_false(shot.alive)
	assert_false(enemy.ready_to_fire(116))
	assert_true(enemy.ready_to_fire(117))


func test_real_battle_self_cast_does_not_stun_the_whole_field() -> void:
	var one := _caster(&"susanoo")
	var cast := _cast(one, &"susanoo")
	var sim := _sim(one, cast)
	one.pos = Vector2(0.5, 0.0)
	sim.enemies()[0].distance = 0.6
	sim.enemies()[1].distance = 0.9
	assert_true(sim.cast_skill_now(one, 1))
	PBCastTestClock.release(sim, one)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1), 10.0)
	assert_false(sim.enemies()[0].ready_to_fire(1))
	assert_true(sim.enemies()[1].ready_to_fire(1))
	assert_eq(one.mp, 87.0)
	assert_eq(cast.ready_at, 366)
	for enemy: PBEnemy in sim.enemies():
		assert_eq(enemy.hp, enemy.max_hp)


func test_self_area_knockback_stays_local_and_zero_radius_remains_global() -> void:
	var one := _caster(&"susanoo")
	one.pos = Vector2(0.5, 0.3)
	var skill := PBSkill.new()
	skill.target = PBSkill.Target.NONE
	skill.radius = 0.15
	skill.knockback = 0.1
	var cast := PBSkillCast.new(skill)
	var inside := _enemy(Vector2(0.6, 0.3))
	inside.start_x = 1.0
	var outside := _enemy(Vector2(0.9, 0.3))
	PBSkillRules.land_on_field(cast, [inside, outside], 0, _cfg, 0, one, 10.0)
	assert_almost_eq(inside.distance, 0.7, 0.001)
	assert_eq(outside.hp, outside.max_hp)
	skill.radius = 0.0
	PBSkillRules.land_on_field(cast, [inside, outside], 0, _cfg, 1, one, 10.0)
	assert_eq(outside.hp, outside.max_hp - 10.0)
