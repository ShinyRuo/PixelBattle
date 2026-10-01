extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0


func _one() -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"kushina"))
	var one := (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	one.ultimate = null
	one.move_speed = 0.0
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	one.max_hp = 1000.0
	one.hp = 500.0
	one.defence = 0.0
	one.def_element = PBElement.Type.PHYSICAL
	one.pos = Vector2(0.4, 0.2)
	var skill := one.skills[0].skill
	skill.heal_aura_hit_chance = 1.0
	skill.heal_aura_lost = 0.07
	skill.heal_aura_period_ticks = 1000
	return one


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 445
	return rng


func _battle(one: PBAttacker, ranged: bool = false) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one], _rng())
	one.hp = 500.0
	one.next_shot_at = 10000
	var enemy := sim.enemies()[0]
	enemy.distance = 0.41
	enemy.lane = 0.2
	enemy.spawn_tick = 0
	enemy.speed = 0.0
	enemy.damage_per_shot = 100.0
	enemy.element = PBElement.Type.PHYSICAL
	enemy.windup_ticks = 3
	enemy.next_shot_at = 0
	enemy.shot_speed = 0.001 if ranged else 0.0
	return sim


func test_reaction_heals_pre_hit_missing_health_once_during_melee_windup() -> void:
	var one := _one()
	var sim := _battle(one)
	sim.step()
	assert_eq(one.hp, 535.0)
	assert_true(sim.enemies()[0].swinging)
	sim.step()
	sim.step()
	assert_eq(one.hp, 535.0, "前摇中不能重复触发")
	sim.step()
	assert_eq(one.hp, 435.0, "先恢复 35，再承受 100，不能按伤后缺血恢复 42")


func test_ranged_projectile_does_not_heal_again_when_it_lands() -> void:
	var one := _one()
	var sim := _battle(one, true)
	sim.step()
	assert_eq(one.hp, 535.0)
	for tick: int in range(2, 5):
		sim.step()
	assert_eq(one.hp, 535.0, "远程起手回复，弹道未落地")
	sim.enemies()[0].next_shot_at = 10000
	for tick: int in 20:
		sim.step()
	assert_eq(one.hp, 435.0)


func test_blinded_attack_still_triggers_recovery_at_start() -> void:
	var one := _one()
	var sim := _battle(one)
	var blind := PBBuff.new()
	blind.id = &"reaction_blind"
	blind.kind = PBBuff.Kind.DURATION
	sim.enemies()[0].buffs.add(blind, {PBBuffRules.ENEMY_HIT_SCALE: 0.0}, 0, 100, 0)
	for tick: int in 4:
		sim.step()
	assert_eq(one.hp, 535.0)


func test_duplicate_sources_roll_once_and_dead_or_outside_sources_do_not_roll() -> void:
	var source := _one()
	var duplicate := _one()
	var target := PBAttacker.new()
	target.alive = true
	target.max_hp = 1000.0
	target.hp = 500.0
	target.pos = Vector2(0.625, 0.2)
	var rng := _rng()
	var expected := _rng()
	expected.randf()
	PBHealingAuraRules.on_attacked(target, [source, duplicate, target], rng)
	assert_eq(target.hp, 535.0)
	assert_eq(rng.state, expected.state)
	target.pos = Vector2(0.6251, 0.2)
	PBHealingAuraRules.on_attacked(target, [source, duplicate, target], rng)
	assert_eq(target.hp, 535.0)
	assert_eq(rng.state, expected.state)
	target.pos = Vector2(0.5, 0.2)
	source.alive = false
	duplicate.alive = false
	PBHealingAuraRules.on_attacked(target, [source, duplicate, target], rng)
	assert_eq(target.hp, 535.0)
	assert_eq(rng.state, expected.state)
	PBHealingAuraRules.on_attacked(target, [source], null)
	assert_eq(target.hp, 535.0)
