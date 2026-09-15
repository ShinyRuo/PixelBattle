extends GutTest
## 敌人护甲（M12-c4 批十四，玩家定的：忍者有的敌人都该有）。
##
## 这里错了都不报错：护甲只写进了敌人却没人读；忍术和持续伤害也被护甲减了（原版法术无视护甲）；
## 降护甲降到负数反而放大伤害；护甲穿透在溅射那一路漏算。

const PHYS := PBDamageKind.Type.PHYSICAL

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _armoured_enemy(armor: float, at: float = 0.3) -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = 100000.0
	out.hp = out.max_hp
	out.armor = armor
	out.distance = at
	return out


func _hitter() -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = 1000.0
	one.attack = 100.0
	one.attack_speed = 1.0
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


func _lost(enemy: PBEnemy) -> float:
	return enemy.max_hp - enemy.hp


func test_tougher_shapes_and_later_waves_have_more_armor() -> void:
	# 断言写规则不写数：精英比小怪厚、BOSS 比精英厚、同一档越往后越厚。
	for wave: int in [1, 20, 60]:
		var minion: float = _cfg.enemy_armor(PBWave.Shape.NORMAL, wave)
		var elite: float = _cfg.enemy_armor(PBWave.Shape.ELITE, wave)
		var boss: float = _cfg.enemy_armor(PBWave.Shape.BOSS, wave)
		assert_eq(_cfg.enemy_armor(PBWave.Shape.SWARM, wave), minion, "潮水波也是小怪")
		assert_gt(elite, minion, "精英比小怪厚")
		assert_gt(boss, elite, "BOSS 比精英厚")
		assert_eq(_cfg.enemy_armor(PBWave.Shape.MEGA_BOSS, wave), boss, "超级 BOSS 也是 BOSS")
	var early: float = _cfg.enemy_armor(PBWave.Shape.NORMAL, 1)
	assert_gt(_cfg.enemy_armor(PBWave.Shape.NORMAL, 40), early, "越往后越厚")


func test_a_spawned_enemy_carries_the_armor_of_its_wave() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var wave := PBWaveRules.build(30, _cfg, rng)
	assert_eq(wave.armor_each, _cfg.enemy_armor(wave.shape, 30), "波次快照上记着")
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.01, 1.0, 0)
	assert_eq(enemy.armor, wave.armor_each, "出生时带上")


func test_a_normal_attack_is_cut_by_the_armor_curve() -> void:
	var enemy := _armoured_enemy(10.0)
	var enemies: Array[PBEnemy] = [enemy]
	PBStrikeRules.land(_hitter(), enemy, 100.0, false, enemies, _cfg, 0, null, PBCombatOutcome.new())
	var kept: float = 1.0 - PBStatRules.damage_reduction(10.0, _cfg)
	assert_lt(kept, 1.0, "前提：10 点护甲真的减伤")
	assert_almost_eq(_lost(enemy), 100.0 * kept, 0.001, "和忍者挨打同一条曲线")


func test_lowering_and_piercing_armor_never_amplifies_damage() -> void:
	var hitter := _hitter()
	var broken := _armoured_enemy(10.0)
	var shred := PBBuff.new()
	shred.id = &"probe_shred"
	shred.kind = PBBuff.Kind.DURATION
	shred.duration_seconds = 5.0
	PBSkillRules.apply_one_enemy(broken, shred, {PBBuffRules.ENEMY_DEFENCE: -4.0}, _cfg, 0)
	assert_almost_eq(
		PBStrikeRules.mitigated(hitter, broken, 100.0, PHYS, _cfg, 0),
		100.0 * (1.0 - PBStatRules.damage_reduction(6.0, _cfg)),
		0.001,
		"降 4 点就按 6 点算"
	)
	hitter.armor_pen = 0.5
	assert_almost_eq(
		PBStrikeRules.mitigated(hitter, _armoured_enemy(10.0), 100.0, PHYS, _cfg, 0),
		100.0 * (1.0 - PBStatRules.damage_reduction(5.0, _cfg)),
		0.001,
		"穿透一半就按一半算"
	)
	var bare := _armoured_enemy(2.0)
	PBSkillRules.apply_one_enemy(bare, shred, {PBBuffRules.ENEMY_DEFENCE: -30.0}, _cfg, 0)
	assert_eq(PBStrikeRules.mitigated(null, bare, 100.0, PHYS, _cfg, 0), 100.0, "降到负数也只是不减，不放大")


func test_splash_is_cut_by_each_victims_own_armor() -> void:
	var hitter := _hitter()
	hitter.splash_damage = 0.5
	var center := _armoured_enemy(0.0, 0.3)
	var beside := _armoured_enemy(20.0, 0.31)
	var enemies: Array[PBEnemy] = [center, beside]
	PBStrikeRules.land(hitter, center, 100.0, false, enemies, _cfg, 0, null, PBCombatOutcome.new())
	assert_almost_eq(_lost(center), 100.0, 0.001, "主目标没有护甲")
	assert_almost_eq(
		_lost(beside), 50.0 * (1.0 - PBStatRules.damage_reduction(20.0, _cfg)), 0.001, "溅到的按它自己的护甲减"
	)


func test_damage_over_time_ignores_armor() -> void:
	# 原版法术伤害无视护甲：持续伤害按原数掉。
	var enemy := _armoured_enemy(50.0)
	var burn := PBBuff.new()
	burn.id = &"probe_burn"
	burn.kind = PBBuff.Kind.PERIODIC
	burn.duration_seconds = 3.0
	burn.period_seconds = 1.0
	PBSkillRules.apply_one_enemy(enemy, burn, {PBBuffRules.HARM: 40.0}, _cfg, 0)
	var harm: float = 0.0
	for tick: int in range(0, _cfg.tick_rate + 1):
		harm += PBBuffRules.advance_enemy(enemy, tick)
	assert_almost_eq(harm, 40.0, 0.001, "持续伤害一点不减")


func test_only_the_strike_rules_read_enemy_armor() -> void:
	# 一处判：护甲只在 `mitigated` 里折算。别处直接读 `.armor` 的话，那一路就是第二把尺子。
	var seen := 0
	for path: String in _scripts("res://src"):
		var text := FileAccess.get_file_as_string(path)
		var reads := false
		for marker: String in [".armor ", ".armor\n", ".armor)"]:
			reads = reads or text.contains(marker)
		if not reads:
			continue
		seen += 1
		assert_true(path.ends_with("strike_rules.gd"), "%s 自己读了敌人护甲" % path)
	assert_gt(seen, 0, "前提：扫得到读护甲的地方")


func _scripts(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	for sub: String in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	return out
