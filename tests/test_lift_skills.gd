extends GutTest
## 起手击飞与落地控制分时结算，渲染不能改变地面坐标。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.march_seconds = 1000000.0
	_cfg.unit_min_gap = 0.0


func _caster(id: StringName, level: int = 1) -> PBAttacker:
	for character: PBCharacter in _cfg.characters.all():
		if character.skill_ids.has(id):
			var unit := PBUnit.new(character)
			unit.level = level
			var one: PBAttacker = (
				PBCombatRules
				. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
			)
			for cast: PBSkillCast in one.skills:
				if cast.skill.id == id:
					one.skills = [cast]
					break
			one.ultimate = null
			one.attack = 0.0
			one.dps = 0.0
			one.move_speed = 0.0
			one.pos = Vector2(0.4, 0.0)
			return one
	fail_test("缺少技能所属角色")
	return null


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 3
	wave.hp_each = 1000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	sim.enemies()[1].lane = 0.1
	sim.enemies()[2].lane = 0.12
	return sim


func test_earth_lifts_primary_then_deals_area_damage_and_primary_stun() -> void:
	var one := _caster(&"rising_earth")
	var sim := _sim(one)
	var primary: PBEnemy = sim.enemies()[0]
	var near: PBEnemy = sim.enemies()[1]
	var far: PBEnemy = sim.enemies()[2]
	assert_true(sim.cast_skill_at(one, primary, 1))
	PBCastTestClock.release(sim, one)
	assert_eq(primary.hp, primary.max_hp)
	assert_eq(primary.buffs.amount(PBBuffRules.AIRBORNE, 1), 1.0)
	assert_false(primary.ready_to_fire(1))
	assert_eq(near.buffs.count(1), 0)
	for i: int in 19:
		sim.step()
	assert_eq(primary.hp, primary.max_hp)
	sim.step()
	assert_lt(primary.hp, primary.max_hp)
	assert_lt(near.hp, near.max_hp)
	assert_eq(far.hp, far.max_hp)
	assert_true(near.ready_to_fire(26))
	assert_false(primary.ready_to_fire(36))
	assert_true(primary.ready_to_fire(37))
	assert_eq(sim._slow_until, -1)
	assert_eq(one.skills[0].skill.element, PBElement.Type.EARTH)
	assert_eq(one.skills[0].skill.kind, PBDamageKind.Type.NINJUTSU)


func test_landing_stun_has_original_ten_level_durations() -> void:
	var times := [0.5, 0.5, 1.0, 1.0, 1.0, 1.5, 1.5, 1.5, 1.5, 2.0]
	for level: int in range(1, 11):
		var one := _caster(&"rising_earth", level)
		var sim := _sim(one)
		var cast := one.skills[0]
		cast.cast_on(0, 0)
		PBSkillRules.prepare_target(cast, sim.enemies(), _cfg, 1)
		PBSkillRules.land_on_enemy(cast, sim.enemies(), _cfg, 20, one, 100.0)
		var end: int = 20 + int(times[level - 1] * _cfg.tick_rate)
		assert_false(sim.enemies()[0].ready_to_fire(end))
		assert_true(sim.enemies()[0].ready_to_fire(end + 1))


func test_preparation_does_not_refresh_each_tick_and_recast_resets_it() -> void:
	var one := _caster(&"rising_earth")
	var sim := _sim(one)
	var cast := one.skills[0]
	cast.cast_on(0, 0)
	for tick: int in range(1, 20):
		PBSkillRules.prepare_target(cast, sim.enemies(), _cfg, tick)
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.AIRBORNE, 26), 0.0)
	cast.land(20)
	cast.cast_on(0, 100)
	PBSkillRules.prepare_target(cast, sim.enemies(), _cfg, 101)
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.AIRBORNE, 110), 1.0)
	cast.reset()
	assert_false(cast.start_applied)


func test_dead_target_does_not_explode_on_neighbors_or_receive_preparation() -> void:
	var one := _caster(&"rising_earth")
	var sim := _sim(one)
	var primary: PBEnemy = sim.enemies()[0]
	var near: PBEnemy = sim.enemies()[1]
	sim.cast_skill_at(one, primary, 1)
	PBCastTestClock.release(sim, one)
	primary.alive = false
	for i: int in 20:
		sim.step()
	assert_eq(near.hp, near.max_hp)
	var cast := one.skills[0]
	cast.cast_on(0, 100)
	PBSkillRules.prepare_target(cast, sim.enemies(), _cfg, 101)
	assert_false(cast.is_pending())


func test_piston_hits_own_circle_with_lift_and_slow_but_no_horizontal_push() -> void:
	var one := _caster(&"piston_fist")
	var sim := _sim(one)
	var near: PBEnemy = sim.enemies()[1]
	var far: PBEnemy = sim.enemies()[2]
	var previous: Vector2 = near.pos()
	assert_true(sim.cast_skill_now(one, 1))
	PBCastTestClock.release(sim, one)
	assert_lt(near.hp, near.max_hp)
	assert_eq(near.pos(), previous)
	assert_eq(far.hp, far.max_hp)
	assert_eq(near.buffs.amount(PBBuffRules.AIRBORNE, 26), 1.0)
	assert_eq(near.buffs.amount(PBBuffRules.AIRBORNE, 27), 0.0)
	assert_false(near.ready_to_fire(26))
	assert_true(near.ready_to_fire(27))
	assert_eq(near.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 27), 0.5)
	assert_eq(near.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 66), 0.5)
	assert_eq(near.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 67), 1.0)
	assert_eq(sim._slow_until, -1)


func test_airborne_render_height_is_tick_based_and_shadow_position_is_unchanged() -> void:
	var one := _caster(&"rising_earth")
	var sim := _sim(one)
	var cast := one.skills[0]
	cast.cast_on(0, 0)
	PBSkillRules.prepare_target(cast, sim.enemies(), _cfg, 1)
	var pool := PBEnemyPool.new()
	autofree(pool)
	var enemy: PBEnemy = sim.enemies()[0]
	assert_almost_eq(pool._lift(enemy, 0), 0.0, 0.00001)
	assert_almost_eq(pool._lift(enemy, 10), 18.0, 0.00001)
	assert_almost_eq(pool._lift(enemy, 20), 0.0, 0.00001)
	assert_eq(pool._lift(enemy, 21), 0.0)
	assert_eq(enemy.pos(), Vector2(0.5, 0.0))


func test_invalid_start_effects_and_lift_without_control_are_rejected() -> void:
	var skill := _cfg.skills.by_id(&"rising_earth").clone()
	skill.delay_ticks = 0
	assert_ne(PBSkillDamage.validate(skill), "")
	var buff := PBBuff.new()
	buff.kind = PBBuff.Kind.DURATION
	buff.friendly = false
	buff.mods = {PBBuffRules.AIRBORNE: 1.0}
	assert_ne(PBBuffFormula.validate(buff), "")
