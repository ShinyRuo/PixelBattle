extends GutTest


func after_each() -> void:
	PBSkillStartArt._hidden.clear()


func test_ground_visual_can_be_hidden_without_changing_impact() -> void:
	var cfg := PBSimConfig.new()
	cfg.aim_policy = PBAimRules.Policy.NONE
	cfg.spawn_window = 0
	var unit := PBAttacker.new()
	unit.slot = 0
	unit.max_hp = 1000
	unit.max_mp = 100
	unit.pos = Vector2(0.2, 0.3)
	var skill := PBSkill.new()
	skill.id = &"flight_probe"
	skill.target = PBSkill.Target.GROUND
	skill.delay_ticks = 8
	skill.damage = 30
	skill.radius = 1
	unit.skills = [PBSkillCast.new(skill)]
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000
	var sim := PBBattleSim.new(wave, 0, 0, cfg, [unit])
	var enemy := sim.enemies()[0]
	enemy.speed = 0
	enemy.distance = 0.6
	enemy.lane = 0.3
	enemy.damage_per_shot = 0
	var pool := PBShotPool.new()
	add_child_autofree(pool)
	sim.cast_skill(unit, enemy.pos(), 1)
	PBCastTestClock.until(sim, 6)
	pool.sync_shots(sim, [], null, Vector2.ONE)
	assert_eq(pool.shown(), 1)
	PBSkillStartArt._hidden[skill.id] = true
	pool.sync_shots(sim, [], null, Vector2.ONE)
	assert_eq(pool.shown(), 0)
	assert_false(pool._casts[0].visible, "上帧精灵必须回收")
	assert_eq(unit.skills[0].lands_at, 14)
	PBCastTestClock.until(sim, 13)
	assert_eq(enemy.hp, 1000.0)
	sim.step()
	assert_lt(enemy.hp, 1000.0)
	assert_eq(unit.skills[0].impact_tick, 14)


func test_hidden_projectile_remains_alive_and_normal_attack_still_draws() -> void:
	var cfg := PBSimConfig.new()
	var wave := PBWave.new()
	wave.count = 1
	var sim := PBBattleSim.new(wave, 0, 0, cfg)
	var pool := PBShotPool.new()
	add_child_autofree(pool)
	var shot := sim.shots()[0]
	shot.launch(Vector2.ZERO, 0, 10, 0.2, false, PBElement.Type.FIRE, 0)
	shot.skill = PBSkill.new()
	shot.skill.id = &"hidden_projectile_probe"
	PBSkillStartArt._hidden[shot.skill.id] = true
	pool.sync_shots(sim, [], null, Vector2.ONE)
	assert_eq(pool.shown(), 0)
	assert_true(shot.alive)
	shot.skill = null
	pool.sync_shots(sim, [], null, Vector2.ONE)
	assert_eq(pool.shown(), 1)


func test_hiding_does_not_suppress_hit_sparks() -> void:
	var cfg := PBSimConfig.new()
	var wave := PBWave.new()
	wave.count = 1
	var sim := PBBattleSim.new(wave, 0, 0, cfg)
	var pool := PBShotPool.new()
	add_child_autofree(pool)
	var book := PBBattleLog.new()
	book.hit(0, 0, 0, 10, false)
	pool.sync_shots(sim, [], book, Vector2.ONE)
	assert_gt(pool.sparks(), 0)
