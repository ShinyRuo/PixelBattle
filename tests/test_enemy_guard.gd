extends GutTest
## 敌人护盾与受伤倍率：消耗守恒、溢出换算，以及实际伤害路径不能漏接。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0


func _enemy(at: float = 0.3) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at, 0)
	return enemy


func _buff(id: StringName, mods: Dictionary, seconds: float = 2.0) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = seconds
	buff.mods = mods
	return buff


func _hang(enemy: PBEnemy, buff: PBBuff, tick: int = 0) -> void:
	PBSkillRules.apply_all_enemy(enemy, [buff], 1, _cfg, tick)


func test_damage_scales_before_shield_and_then_reaches_health() -> void:
	var enemy := _enemy()
	_hang(
		enemy,
		_buff(
			&"guard",
			{PBBuffRules.SHIELD: 40.0, PBBuffRules.HURT: 2.0, PBBuffRules.DAMAGE_TAKEN: 0.25}
		)
	)
	enemy.take_damage(100.0, 1)
	assert_eq(enemy.hp, 90.0, "100 × 2 × 0.25，先消耗 40 护盾再扣 10 血")
	assert_eq(enemy.buffs.shield_left(1), 0.0)
	enemy.take_damage(20.0, 2)
	assert_eq(enemy.hp, 80.0, "护盾不能被下一次命中重复使用")


func test_stacked_shields_refresh_and_expire_without_changing_definition() -> void:
	var enemy := _enemy()
	var shared := _buff(&"first", {PBBuffRules.SHIELD: 40.0}, 1.0)
	_hang(enemy, shared)
	_hang(enemy, _buff(&"second", {PBBuffRules.SHIELD: 30.0}, 3.0))
	enemy.take_damage(50.0, 1)
	assert_eq(enemy.hp, 100.0)
	assert_eq(enemy.buffs.shield_left(1), 20.0)
	assert_eq(float(shared.mods[PBBuffRules.SHIELD]), 40.0, "消耗的是实例，不改定义")
	_hang(enemy, shared, 2)
	assert_eq(enemy.buffs.shield_left(2), 60.0, "同 id 覆盖为新护盾，第二份保持余量")
	assert_eq(enemy.buffs.shield_left(22), 60.0, "最后有效 tick 仍能挡")
	assert_eq(enemy.buffs.shield_left(23), 20.0, "未 sweep 也要忽略过期护盾")
	enemy.take_damage(25.0, 23)
	assert_eq(enemy.hp, 95.0)


func test_immunity_and_negative_damage_cannot_spend_shields_or_heal() -> void:
	var enemy := _enemy()
	_hang(enemy, _buff(&"shield", {PBBuffRules.SHIELD: 40.0}))
	enemy.take_damage(50.0, 0)
	assert_eq(enemy.hp, 90.0)
	_hang(enemy, _buff(&"shield", {PBBuffRules.SHIELD: 40.0}))
	for scale: float in [0.0, -1.0]:
		_hang(enemy, _buff(&"immune", {PBBuffRules.DAMAGE_TAKEN: scale}))
		enemy.take_damage(1000.0, 1)
		assert_eq(enemy.hp, 90.0)
		assert_eq(enemy.buffs.shield_left(1), 40.0)
		assert_true(is_inf(enemy.damage_to_kill(1)))
	enemy.buffs.clear()
	enemy.take_damage(-100.0, 1)
	assert_eq(enemy.hp, 90.0, "负伤害不变成治疗")


func test_a_dodge_never_consumes_the_shield() -> void:
	var enemy := _enemy()
	enemy.dodge = 1.0
	_hang(enemy, _buff(&"shield", {PBBuffRules.SHIELD: 40.0}))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	enemy.take_damage(100.0, 1, rng, true)
	assert_eq(enemy.dodge_count, 1)
	assert_eq(enemy.buffs.shield_left(1), 40.0)
	assert_eq(enemy.hp, 100.0)


func test_damage_to_kill_matches_actual_cost_and_does_not_consume() -> void:
	var enemy := _enemy()
	_hang(
		enemy,
		_buff(
			&"guard",
			{PBBuffRules.SHIELD: 40.0, PBBuffRules.HURT: 2.0, PBBuffRules.DAMAGE_TAKEN: 0.25}
		)
	)
	assert_eq(enemy.damage_to_kill(1), 280.0)
	assert_eq(enemy.damage_to_kill(1), 280.0, "查询不扣盾")
	assert_true(enemy.take_damage(280.0, 1), "算出的伤害恰好能杀死")
	assert_eq(enemy.hp, 0.0)
	assert_eq(enemy.buffs.shield_left(1), 0.0)


func test_continuous_overflow_pays_for_shield_and_damage_scale() -> void:
	var first := _enemy()
	var second := _enemy(0.4)
	_hang(first, _buff(&"guard", {PBBuffRules.SHIELD: 40.0, PBBuffRules.DAMAGE_TAKEN: 0.5}))
	var hitter := PBAttacker.whole_field(350.0 * _cfg.tick_rate, 2.0)
	hitter.prime(_cfg.tick_rate)
	var out := PBCombatOutcome.new()
	PBStrikeRules.deal([hitter], [first, second], [], 0, _cfg, 1, null, null, out)
	assert_false(first.alive)
	assert_eq(second.hp, 30.0, "350 中付掉 280，只能给下一个 70")
	assert_eq(out.kills, 1)


func test_normal_hit_absorbed_by_shield_cannot_leech_health() -> void:
	var enemy := _enemy()
	_hang(enemy, _buff(&"guard", {PBBuffRules.SHIELD: 40.0, PBBuffRules.DAMAGE_TAKEN: 0.5}))
	var hitter := PBAttacker.new()
	hitter.max_hp = 1000.0
	hitter.hp = 500.0
	hitter.lifesteal = 1.0
	PBStrikeRules.land(hitter, enemy, 60.0, false, [enemy], _cfg, 1, null, PBCombatOutcome.new())
	assert_eq(enemy.hp, 100.0)
	assert_eq(enemy.buffs.shield_left(1), 10.0)
	assert_eq(hitter.hp, 500.0, "吸血只看实际掉血，护盾不算")


func test_projectile_and_ground_skill_use_the_same_defences() -> void:
	for mode: String in ["attack", "skill_shot", "ground"]:
		var enemy := _enemy()
		_hang(enemy, _buff(&"guard", {PBBuffRules.SHIELD: 40.0, PBBuffRules.DAMAGE_TAKEN: 0.5}))
		if mode == "ground":
			var skill := PBSkill.new()
			skill.damage = 100.0
			skill.radius = 0.2
			var cast := PBSkillCast.new(skill)
			cast.cast(enemy.pos(), 0)
			PBSkillRules.land(cast, [enemy], 0, _cfg, 1, null, 100.0)
		else:
			var shot := PBProjectile.new()
			shot.launch(Vector2.ZERO, 0, 100.0, 1.0)
			if mode == "skill_shot":
				shot.skill = PBSkill.new()
			PBShotRules.advance([shot], [enemy], [], _cfg, 1, null, PBCombatOutcome.new())
		assert_eq(enemy.hp, 90.0)
		assert_eq(enemy.buffs.shield_left(1), 0.0)


func test_instant_harm_cannot_bypass_enemy_guard() -> void:
	var enemy := _enemy()
	_hang(enemy, _buff(&"guard", {PBBuffRules.SHIELD: 40.0, PBBuffRules.DAMAGE_TAKEN: 0.5}))
	var harm := PBBuff.new()
	harm.id = &"harm_probe"
	harm.mods = {PBBuffRules.HARM: 100.0}
	assert_false(PBSkillRules.apply_all_enemy(enemy, [harm], 1, _cfg, 1))
	assert_eq(enemy.hp, 90.0)
	assert_eq(enemy.buffs.shield_left(1), 0.0)


func test_periodic_damage_consumes_guard_and_counts_death_once_in_battle() -> void:
	var wave := PBWave.new()
	wave.hp_each = 100.0
	wave.count = 1
	_cfg.march_seconds = 1000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg)
	var enemy: PBEnemy = sim.enemies()[0]
	_hang(enemy, _buff(&"guard", {PBBuffRules.SHIELD: 40.0, PBBuffRules.DAMAGE_TAKEN: 0.5}, 3.0))
	var burn := _buff(&"burn", {PBBuffRules.HARM: 200.0}, 3.0)
	burn.kind = PBBuff.Kind.PERIODIC
	burn.period_seconds = 0.5
	_hang(enemy, burn)
	for tick: int in 10:
		sim.step()
	assert_eq(enemy.hp, 40.0, "第一跳扣完盾，实际掉 60 血")
	assert_eq(sim.result().kills, 0)
	for tick: int in 12:
		sim.step()
	assert_false(enemy.alive)
	assert_eq(sim.result().kills, 1)


func test_reflected_damage_uses_enemy_guard_and_spawn_clears_it() -> void:
	var enemy := _enemy()
	_hang(enemy, _buff(&"guard", {PBBuffRules.SHIELD: 40.0, PBBuffRules.DAMAGE_TAKEN: 0.5}))
	var target := PBAttacker.new()
	target.max_hp = 1000.0
	target.hp = 1000.0
	target.reflect = 1.0
	target.def_element = PBElement.Type.PHYSICAL
	PBStrikeRules.hurt_ally(
		target, enemy, 100.0, PBElement.Type.PHYSICAL, _cfg, 1, null, null, PBCombatOutcome.new()
	)
	assert_eq(enemy.hp, 90.0)
	var wave := PBWave.new()
	wave.hp_each = 100.0
	enemy.spawn(wave, 0.0, 1.0, 0)
	assert_eq(enemy.buffs.shield_left(0), 0.0)
	assert_eq(enemy.damage_to_kill(0), 100.0)


func test_enemy_guard_is_not_reimplemented_in_damage_callers() -> void:
	for path: String in [
		"res://src/core/rules/strike_rules.gd",
		"res://src/core/rules/shot_rules.gd",
		"res://src/core/rules/skill_rules.gd",
		"res://src/core/sim/battle_sim.gd"
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("PBBuffRules.SHIELD"), "%s 不该自己读护盾" % path)
		assert_false(text.contains("PBBuffRules.DAMAGE_TAKEN"), "%s 不该自己乘受伤倍率" % path)
		assert_false(text.contains(".absorb("), "%s 不该自己扣盾" % path)
