extends GutTest
## [PBAttacker] 与射程 / 多目标分配的测试。M3-a。
##
## ## 这个文件守的是什么
##
## M3-a 把战斗从「整队一个标量 DPS」换成一组攻击者，动的是 M0 以来
## 所有数值结论的地基。所以这里的头一条是**对拍**：整队折回一个覆盖全场的
## 单体攻击者时，结果必须与旧路径逐字段相同。
##
## 那条断言不成立的话，后面量出来的「单波时长变长了 / 场上有人了」
## 分不清是射程的功劳，还是改造顺手改坏了原有语义 ——
## 而这两种情况的处理方式完全相反。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260828


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


func _sim(wave: PBWave, dps: float) -> PBBattleSim:
	return PBBattleSim.new(wave, dps, 0.0, _cfg)


func test_one_whole_field_attacker_reproduces_the_scalar_dps_path() -> void:
	# **M3-a 的对拍锚点。**
	#
	# 射程改造把「整队一个标量 DPS」换成一组攻击者。改造正确的判据是：
	# 把整队折回**一个覆盖全场的单体攻击者**时，结果必须与旧路径逐字段相同。
	# 这条不成立的话，后面量出来的「单波时长变长了」分不清是射程的功劳
	# 还是改造顺手改坏了原有语义。
	for wave_index: int in [3, 17, 29, 42]:
		var wave := _wave(wave_index)
		for dps: float in [80.0, 600.0, 4500.0]:
			var scalar := _sim(wave, dps).run_to_end()
			# **对角，不是长度**：二维之后最远的敌人在角落上，
			# 用长度造出来的退化攻击者够不着它，而现象只是「tick 数差几个」。
			var solo: Array[PBAttacker] = [PBAttacker.whole_field(dps, _cfg.field_diagonal())]
			var rebuilt := PBBattleSim.new(wave, 0.0, 0.0, _cfg, solo).run_to_end()
			assert_eq(rebuilt.kills, scalar.kills, "第 %d 波 DPS=%.0f：击杀数应完全相同" % [wave_index, dps])
			assert_eq(rebuilt.leaked, scalar.leaked, "第 %d 波 DPS=%.0f：漏怪数应完全相同" % [wave_index, dps])
			assert_eq(rebuilt.ticks, scalar.ticks, "第 %d 波 DPS=%.0f：tick 数应完全相同" % [wave_index, dps])


func test_attacker_dps_sums_to_the_reported_team_dps() -> void:
	# 界面上报的战力和战场上真打出来的伤害必须是同一个数。
	# 分成两份各算一遍是这个项目反复警告的那类 bug：不报错，只是慢慢分叉。
	var deployed: Array[PBUnit] = []
	for element: int in [PBElement.Type.FIRE, PBElement.Type.WATER, PBElement.Type.PHYSICAL]:
		deployed.append(PBUnit.of(_cfg, element as PBElement.Type, PBUnit.Rarity.SR))
	var reported: float = PBCombatRules.team_dps(
		deployed, PBElement.Type.WIND, 1.18, 1.32, PackedFloat64Array(), _cfg
	)
	var total: float = 0.0
	for attacker: PBAttacker in PBCombatRules.build_attackers(
		deployed, PBElement.Type.WIND, 1.18, 1.32, PackedFloat64Array(), _cfg
	):
		total += attacker.dps
	assert_almost_eq(total, reported, reported * 1e-9, "攻击者 DPS 之和应等于报出去的队伍 DPS")


func test_range_decides_who_can_be_hit() -> void:
	# 射程外的敌人对这个攻击者不存在 —— 这是「各打各的」成立的前提。
	# 站在基地口、射程为零的攻击者，只有等敌人走到脚下才打得到。
	var wave := _wave(6)
	var point_blank := PBAttacker.new()
	point_blank.dps = 1e9
	point_blank.pos = Vector2.ZERO
	point_blank.reach = 0.0
	var attackers: Array[PBAttacker] = [point_blank]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, attackers)
	sim.step()
	assert_eq(sim.result().kills, 0, "敌人还在半路，射程为零的攻击者一个都够不着")
	var out := sim.run_to_end()
	assert_eq(out.kills + out.leaked, wave.count, "守恒律在有射程之后照样成立")


func test_area_attack_hits_several_enemies_at_once() -> void:
	# AOE 的价值写在命中数上（§02 那条乘法关系），不是写在溢出上。
	# 把出场窗口压成 0 让整波同时在场，否则第 1 tick 只有一个目标可打。
	_cfg.spawn_window = 0.0
	_cfg.aoe_max_targets = 3
	var wave := _wave(9)
	assert_gt(wave.count, 4, "这一波要有足够多的敌人才测得出多目标")
	var blast := PBAttacker.new()
	blast.dps = wave.hp_each * float(_cfg.tick_rate)
	blast.pos = Vector2.ZERO
	blast.reach = _cfg.field_diagonal()
	blast.shape = PBAttacker.Shape.AOE
	blast.max_targets = _cfg.aoe_max_targets
	var attackers: Array[PBAttacker] = [blast]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, attackers)
	sim.step()
	assert_eq(sim.result().kills, 3, "一 tick 应该正好打死 max_targets 个，不多不少")


func test_area_attack_does_not_carry_overflow() -> void:
	# 溢出对 AOE 不结算：让它既打多个又吃溢出，密集波里等于无限伤害。
	_cfg.spawn_window = 0.0
	_cfg.aoe_max_targets = 2
	var wave := _wave(9)
	var blast := PBAttacker.new()
	blast.dps = wave.total_hp() * 10.0 * float(_cfg.tick_rate)
	blast.pos = Vector2.ZERO
	blast.reach = _cfg.field_diagonal()
	blast.shape = PBAttacker.Shape.AOE
	blast.max_targets = _cfg.aoe_max_targets
	var attackers: Array[PBAttacker] = [blast]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, attackers)
	sim.step()
	assert_eq(sim.result().kills, 2, "再高的伤害也只能打死 max_targets 个")
