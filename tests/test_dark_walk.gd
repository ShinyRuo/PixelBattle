extends GutTest

const SECONDS := [2, 2, 3, 3, 3, 4, 4, 5, 5, 6]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _enemy(y: float = 0.0) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.5, 0, y)
	return enemy


func _land(enemy: PBEnemy, level: int = 1, tick: int = 1) -> void:
	var cast := PBSkillCast.new(_cfg.skills.by_id(&"dark_walk"), level)
	cast.spot = enemy.pos()
	PBSkillRules.land(cast, [enemy], 0, _cfg, tick, null, 100.0)


func test_all_levels_expire_three_effects_together_without_stun() -> void:
	for level: int in range(1, 11):
		var enemy := _enemy()
		_land(enemy, level)
		var end: int = 1 + SECONDS[level - 1] * _cfg.tick_rate
		for key: StringName in [
			PBBuffRules.ENEMY_HIT_SCALE,
			PBBuffRules.ENEMY_ATTACK_SPEED_SCALE,
			PBBuffRules.ENEMY_SPEED_SCALE
		]:
			assert_eq(enemy.buffs.amount(key, end), 0.5)
			assert_eq(enemy.buffs.amount(key, end + 1), 1.0)
		assert_true(enemy.ready_to_fire(1))
		assert_eq(enemy.hp, 99900.0)


func test_movement_attack_interval_and_seeded_miss_use_effect() -> void:
	var enemy := _enemy()
	_land(enemy)
	enemy.speed = 0.1
	enemy.march_to(Vector2.ZERO, 1.0, 2)
	assert_almost_eq(enemy.distance, 0.45, 0.00001)
	enemy.attack_interval = 20
	enemy.windup_ticks = 0
	enemy.on_fired(2)
	assert_eq(enemy.next_shot_at, 42)
	var rng := RandomNumberGenerator.new()
	var reference := RandomNumberGenerator.new()
	rng.seed = 20260916
	reference.seed = 20260916
	for i: int in 30:
		assert_eq(PBBuffRules.misses(enemy, 2, rng), reference.randf() >= 0.5)
	var saved: int = rng.state
	assert_false(PBBuffRules.misses(enemy, 42, rng))
	assert_eq(rng.state, saved)
	enemy.on_fired(42)
	assert_eq(enemy.next_shot_at, 62)


func test_real_sim_delays_local_effect_and_does_not_slow_field() -> void:
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.march_seconds = 1000000.0
	_cfg.unit_min_gap = 0.0
	var unit := PBUnit.new(_cfg.characters.by_id(&"tobirama"))
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"dark_walk":
			one.skills = [cast]
			break
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var inside: PBEnemy = sim.enemies()[0]
	var outside: PBEnemy = sim.enemies()[1]
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	outside.lane = 0.16
	assert_true(sim.cast_skill(one, inside.pos(), 1))
	sim.step()
	assert_eq(inside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)
	for i: int in 17:
		sim.step()
	assert_eq(inside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 18), 0.5)
	assert_eq(outside.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 18), 1.0)
	assert_eq(outside.hp, outside.max_hp)
	assert_eq(sim._slow_until, -1)


func test_tooltip_lists_local_effects_and_level_duration() -> void:
	var skill := _cfg.skills.by_id(&"dark_walk")
	var body := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_false(body.contains("全场减速"))
	assert_string_contains(body, "6 秒")
	assert_eq(skill.radius, 0.15)
	assert_eq(skill.slow_ticks, 0)
