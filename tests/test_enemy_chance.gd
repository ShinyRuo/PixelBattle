extends GutTest
## 敌人普攻闪避 / 暴击：实际出手接线、BUFF 到期、对象池复用与随机流隔离。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260915


func _enemy(at: float = 0.3) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	wave.atk_each = 100.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at, 0)
	enemy.arm(2.0, 100, 100.0, 0.0)
	return enemy


func _hitter() -> PBAttacker:
	var unit := PBAttacker.new()
	unit.attack = 100.0
	unit.attack_speed = 1.0
	unit.max_hp = 1000.0
	unit.pos = Vector2.ZERO
	unit.reach = 2.0
	unit.prime(_cfg.tick_rate)
	unit.revive()
	return unit


func _hang(enemy: PBEnemy, mods: Dictionary) -> void:
	var buff := PBBuff.new()
	buff.id = &"chance_probe"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 1.0
	PBSkillRules.apply_one_enemy(enemy, buff, mods, _cfg, 0)


func test_config_reaches_spawn_and_reuse_clears_old_chances() -> void:
	_cfg.enemy_dodge = 0.4
	_cfg.enemy_crit_chance = 0.3
	_cfg.enemy_crit_bonus = 0.5
	var copy := _cfg.clone()
	var wave := PBWaveRules.build(1, copy, _rng)
	var enemy := _enemy()
	enemy.spawn(wave, 0.0, 1.0, 0)
	assert_eq(enemy.dodge, 0.4)
	assert_eq(enemy.crit_chance, 0.3)
	assert_eq(enemy.crit_bonus, 0.5)
	_hang(enemy, {PBBuffRules.DODGE: 1.0})
	enemy.take_damage(10.0, 0, _rng, true)
	assert_eq(enemy.dodge_count, 1)
	var plain := PBWave.new()
	plain.hp_each = 1000.0
	enemy.spawn(plain, 0.0, 1.0, 0)
	assert_eq(enemy.dodge, 0.0)
	assert_eq(enemy.crit_chance, 0.0)
	assert_eq(enemy.crit_bonus, 0.0)
	assert_eq(enemy.dodge_count, 0)
	assert_eq(enemy.buffs.amount(PBBuffRules.DODGE, 0), 0.0)


func test_zero_chances_leave_rng_unchanged_and_null_rng_does_not_roll() -> void:
	var enemy := _enemy()
	var before: int = _rng.state
	enemy.take_damage(10.0, 0, _rng, true)
	assert_false(PBCritRules.enemy_strike(enemy, 0, _rng)[PBCritRules.CRIT])
	assert_eq(_rng.state, before)
	enemy.dodge = 1.0
	enemy.crit_chance = 1.0
	enemy.take_damage(10.0, 0, null, true)
	assert_eq(enemy.hp, 980.0)
	assert_false(PBCritRules.enemy_strike(enemy, 0)[PBCritRules.CRIT])
	assert_eq(_rng.state, before)


func test_dodge_buff_expires_and_non_attacks_do_not_roll() -> void:
	var enemy := _enemy()
	_hang(enemy, {PBBuffRules.DODGE: 2.0})
	enemy.take_damage(100.0, 0, _rng, true)
	assert_eq(enemy.hp, 1000.0, "概率钳到 100%")
	var before: int = _rng.state
	enemy.take_damage(100.0, 0, _rng)
	assert_eq(enemy.hp, 900.0, "技能 / 持续伤害不闪避")
	assert_eq(_rng.state, before)
	enemy.take_damage(100.0, _cfg.tick_rate + 1, _rng, true)
	assert_eq(enemy.hp, 800.0, "有效期包含末 tick，下一 tick 恢复命中")
	assert_eq(_rng.state, before, "到期不掷骰")
	assert_eq(enemy.dodge, 0.0, "临时效果没有改基础值")


func test_dodged_attack_has_no_leech_splash_or_on_hit_effects() -> void:
	var enemy := _enemy()
	enemy.dodge = 1.0
	var beside := _enemy(0.31)
	var enemies: Array[PBEnemy] = [enemy, beside]
	var hitter := _hitter()
	hitter.hp = 500.0
	hitter.lifesteal = 1.0
	hitter.splash_damage = 1.0
	hitter.crit_on_hit = 0.5
	var buff := PBBuff.new()
	buff.id = &"on_attack_probe"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 1.0
	buff.mods = {PBBuffRules.STUN: 1.0}
	hitter.attack_buffs.append(buff)
	var book := PBBattleLog.new()
	var out := PBCombatOutcome.new()
	PBStrikeRules.land(hitter, enemy, 100.0, true, enemies, _cfg, 0, book, out, _rng)
	assert_eq(enemy.hp, 1000.0)
	assert_eq(beside.hp, 1000.0)
	assert_eq(hitter.hp, 500.0)
	assert_eq(hitter.buffs.amount(PBBuffRules.CRIT_CHANCE, 0), 0.0)
	assert_eq(enemy.buffs.amount(PBBuffRules.STUN, 0), 0.0)
	assert_eq(book.total, 0, "未命中不播报伤害")
	assert_eq(out.kills, 0)


func test_splash_uses_each_victims_dodge() -> void:
	var center := _enemy()
	var beside := _enemy(0.31)
	beside.dodge = 1.0
	var hitter := _hitter()
	hitter.splash_damage = 1.0
	PBStrikeRules.land(
		hitter, center, 100.0, false, [center, beside], _cfg, 0, null, PBCombatOutcome.new(), _rng
	)
	assert_eq(center.hp, 900.0)
	assert_eq(beside.hp, 1000.0)
	assert_eq(beside.dodge_count, 1)


func test_normal_and_piercing_projectiles_use_enemy_dodge() -> void:
	var enemies: Array[PBEnemy] = [_enemy(), _enemy(0.35), _enemy(0.40)]
	for i: int in enemies.size():
		enemies[i].slot = i
		enemies[i].dodge = 1.0
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 0.02)
	shot.pierce_left = 0.25
	var shots: Array[PBProjectile] = [shot]
	var out := PBCombatOutcome.new()
	for tick: int in 50:
		PBShotRules.advance(shots, enemies, [], _cfg, tick, null, out, _rng)
	assert_false(shot.alive)
	for enemy: PBEnemy in enemies:
		assert_eq(enemy.hp, 1000.0)
		assert_eq(enemy.dodge_count, 1, "穿过后不重复掷骰")


func test_enemy_critical_buffs_add_clamp_and_expire() -> void:
	var enemy := _enemy()
	enemy.crit_chance = 0.25
	enemy.crit_bonus = 0.25
	_hang(enemy, {PBBuffRules.CRIT_CHANCE: 1.0, PBBuffRules.CRIT_DAMAGE: 0.5})
	var swing := PBCritRules.enemy_strike(enemy, 0, _rng)
	assert_true(swing[PBCritRules.CRIT])
	assert_eq(swing[PBCritRules.DAMAGE], 275.0, "基础二倍 + 常驻和临时暴伤")
	enemy.crit_chance = 0.0
	var before: int = _rng.state
	swing = PBCritRules.enemy_strike(enemy, _cfg.tick_rate + 1, _rng)
	assert_false(swing[PBCritRules.CRIT])
	assert_eq(swing[PBCritRules.DAMAGE], 100.0)
	assert_eq(_rng.state, before)


func test_real_melee_and_ranged_attacks_keep_departure_critical_result() -> void:
	for ranged: bool in [false, true]:
		var wave := PBWave.new()
		wave.hp_each = 10000.0
		wave.atk_each = 100.0
		wave.count = 1
		wave.element = PBElement.Type.PHYSICAL
		var hitter := _hitter()
		hitter.attack = 0.0
		hitter.def_element = PBElement.Type.PHYSICAL
		var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [hitter], _rng)
		var book := PBBattleLog.new()
		sim.log_to = book
		var enemy: PBEnemy = sim.enemies()[0]
		enemy.arm(2.0, 100, 100.0, 0.05 if ranged else 0.0, ranged)
		_hang(enemy, {PBBuffRules.CRIT_CHANCE: 1.0})
		sim.step()
		enemy.buffs.clear()
		for tick: int in 30:
			sim.step()
		assert_eq(hitter.hp, 800.0, "近战与飞行期间效果消失的子弹都保留二倍伤害")
		var hits: int = 0
		for entry: Dictionary in book.entries:
			if entry["kind"] == PBBattleLog.Kind.HIT_ALLY:
				hits += 1
				assert_true(entry["crit"], "暴击标记传到播报")
		assert_eq(hits, 1)


func test_real_single_and_area_attacks_reach_enemy_dodge() -> void:
	for area: bool in [false, true]:
		var wave := PBWave.new()
		wave.hp_each = 1000.0
		wave.count = 1
		wave.dodge_each = 1.0
		var hitter := _hitter()
		if area:
			hitter.shape = PBAttacker.Shape.AOE
			hitter.max_targets = 2
		var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [hitter], _rng)
		for tick: int in 25:
			sim.step()
		var enemy: PBEnemy = sim.enemies()[0]
		assert_eq(enemy.hp, 1000.0)
		assert_gt(enemy.dodge_count, 0, "实际出手必须传入战斗随机流")
