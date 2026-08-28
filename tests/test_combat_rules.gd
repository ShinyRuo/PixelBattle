extends GutTest
## [PBCombatRules] 的排队模型测试，外加 [PBUnit] 的战力换算。
##
## 这里守的是模型的**边界行为**：DPS 为零、DPS 无穷大、刚好够、刚好不够。
## 解析式近似最容易在边界上出荒谬结果（负数时长、漏怪数超过总数），
## 而那种错误在几万局的统计里会被平均掉，看不出来。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 4242


func _wave(index: int = 1) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


func test_overwhelming_dps_clears_everything() -> void:
	var wave := _wave(1)
	var out := PBCombatRules.resolve(wave, 1e9, 0.0, _cfg)
	assert_true(out.cleared, "碾压级 DPS 应全清")
	assert_eq(out.kills, wave.count, "击杀数应等于总数")
	assert_eq(out.leaked, 0, "不应有漏怪")
	assert_eq(out.base_damage, 0.0, "全清时基地不该掉血")


func test_zero_dps_leaks_the_entire_wave() -> void:
	# 全员派去做任务、或阵容被克到近乎无伤，都会走到这一支。
	# 它是合法状态，不是除零错误。
	var wave := _wave(1)
	var out := PBCombatRules.resolve(wave, 0.0, 0.0, _cfg)
	assert_false(out.cleared, "零 DPS 不可能清波")
	assert_eq(out.leaked, wave.count, "应全部漏光")
	assert_eq(out.kills, 0, "不应有任何击杀")
	assert_gt(out.base_damage, 0.0, "全漏应该扣基地血")


func test_kills_plus_leaks_always_equals_the_wave_count() -> void:
	# 守恒律。一个敌人要么被杀要么漏过去，不该凭空多出来或消失。
	var wave := _wave(25)
	for dps: float in [0.0, 1.0, 50.0, 500.0, 5000.0, 1e6]:
		var out := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
		assert_eq(out.kills + out.leaked, wave.count, "DPS=%.0f 时击杀+漏怪应等于总数" % dps)


func test_more_dps_never_produces_more_leaks() -> void:
	# 单调性。DPS 越高漏得越少，中间不该有反转 —— 排队模型里
	# 「打快了反而漏更多」是典型的时钟推进写错的症状。
	var wave := _wave(30)
	var previous: int = wave.count + 1
	for dps: float in [10.0, 100.0, 400.0, 1200.0, 4000.0, 20000.0]:
		var out := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
		assert_lte(out.leaked, previous, "DPS 提高到 %.0f 后漏怪数不该反增" % dps)
		previous = out.leaked


func test_battle_duration_is_tick_aligned() -> void:
	# §14 铁律：定帧 20 tick/s。M-1 虽然不逐 tick 推进，时长也必须对齐到整 tick，
	# 这样 M0 换成真模拟时两边数字可以直接对照。
	var wave := _wave(17)
	for dps: float in [37.0, 411.0, 1234.5]:
		var out := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
		var in_ticks: float = out.battle_seconds * float(_cfg.tick_rate)
		assert_almost_eq(in_ticks, round(in_ticks), 1e-6, "战斗时长应落在整 tick 上")
		assert_eq(out.ticks, int(round(in_ticks)), "ticks 字段应与秒数一致")


func test_defense_tech_reduces_leak_damage() -> void:
	# §07：防御科技 = 基地减伤 +4%/级。这是它在模型里唯一的作用点。
	var wave := _wave(12)
	var bare := PBCombatRules.resolve(wave, 0.0, 0.0, _cfg)
	var armored := PBCombatRules.resolve(wave, 0.0, 0.40, _cfg)
	assert_lt(armored.base_damage, bare.base_damage, "防御科技应减少基地受伤")
	assert_almost_eq(armored.base_damage, bare.base_damage * 0.6, 1e-6, "40% 减伤应精确生效")


func test_boss_leaks_hurt_more() -> void:
	var normal := _wave(9)
	var boss := PBWaveRules.build(10, _cfg, _rng)
	assert_true(boss.is_boss(), "第 10 波应是 BOSS 波")
	var per_normal_leak := PBCombatRules.resolve(normal, 0.0, 0.0, _cfg).base_damage / normal.count
	var per_boss_leak := PBCombatRules.resolve(boss, 0.0, 0.0, _cfg).base_damage / boss.count
	assert_gt(per_boss_leak, per_normal_leak, "漏掉一个 BOSS 应比漏掉一个杂兵疼得多")


func test_counter_element_is_worth_about_twice_physical() -> void:
	# §03 的支点：克制 2.0 对物理 1.05，接近两倍。
	var water := PBUnit.of(_cfg, PBElement.Type.WATER, PBUnit.Rarity.SR)
	var physical := PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR)
	var fire_wave := PBElement.Type.FIRE
	var ratio := water.effective_power(fire_wave, _cfg) / physical.effective_power(fire_wave, _cfg)
	assert_almost_eq(ratio, 2.0 / 1.05, 1e-6, "克制系对物理应接近 1.9 倍")


func test_a_static_five_element_team_barely_beats_physical() -> void:
	# **这是 M-1 最重要的一条测试。**
	#
	# 五系阵容如果全员固定上场，对任意一波的平均倍率是 (2.0+0.5+1.0×3)/5 = 1.10，
	# 而纯物理是 1.05 —— 只差 5%。§03 那 2.0 倍的克制加成全部来自**每波换人**。
	#
	# 这条断言的作用是把这个事实钉死：将来有人把策略脚本改成固定上场，
	# 跑出「属性系统没用」的结论时，这里会先红，提醒他是模型错了不是设计错了。
	var static_team: Array[PBUnit] = []
	for element: int in PBElement.RING:
		static_team.append(PBUnit.of(_cfg, element as PBElement.Type, PBUnit.Rarity.SR))
	var physical_team: Array[PBUnit] = []
	for _i: int in 5:
		physical_team.append(PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR))

	var static_dps := PBCombatRules.team_dps(static_team, PBElement.Type.FIRE, 1.0, 1.0, 1.0, _cfg)
	var physical_dps := PBCombatRules.team_dps(
		physical_team, PBElement.Type.FIRE, 1.0, 1.0, 1.0, _cfg
	)
	var edge := static_dps / physical_dps
	assert_between(edge, 1.0, 1.10, "不换人的五系阵容对物理只有个位数百分比的优势")


func test_rotating_the_team_unlocks_the_real_advantage() -> void:
	# 同样五张卡，换成「只上克制系」之后差距应该拉开到接近两倍。
	var counter := PBUnit.of(_cfg, PBElement.Type.WATER, PBUnit.Rarity.SR)
	var rotated: Array[PBUnit] = []
	for _i: int in 5:
		rotated.append(counter)
	var physical_team: Array[PBUnit] = []
	for _i: int in 5:
		physical_team.append(PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR))

	var rotated_dps := PBCombatRules.team_dps(rotated, PBElement.Type.FIRE, 1.0, 1.0, 1.0, _cfg)
	var physical_dps := PBCombatRules.team_dps(
		physical_team, PBElement.Type.FIRE, 1.0, 1.0, 1.0, _cfg
	)
	assert_gt(rotated_dps / physical_dps, 1.8, "换上克制系后应拉开到接近两倍")


func test_card_identity_includes_the_variant() -> void:
	# 没有 variant，「火系 SSR」全游戏只有一张，玩家永远凑不出四个克制系上场，
	# §03 的换人策略在模型里被人为掐死一半。这条守着卡池不退化。
	var seen := {}
	for rarity: int in 4:
		for element: int in 6:
			for variant: int in _cfg.characters_per_bucket:
				var unit := PBUnit.of(
					_cfg, element as PBElement.Type, rarity as PBUnit.Rarity, variant
				)
				assert_false(seen.has(unit.key()), "卡片身份键不应撞车")
				seen[unit.key()] = true
	var expected: int = 4 * 6 * _cfg.characters_per_bucket
	assert_eq(seen.size(), expected, "卡池大小应为 稀有度 × 属性 × 每格角色数")
	assert_gte(expected, 40, "卡池规模应对得上 §09 的「PC 首发 40+ 角色」")


func test_enough_counter_cards_exist_to_fill_the_bench() -> void:
	# 出战席最多 10 个位置。同一属性的可用角色数 = 4 稀有度 × 每格角色数。
	# 这个数太小的话，「上满克制系」在模型里就是做不到的事，
	# 属性系统的价值会被系统性低估。
	var per_element: int = 4 * _cfg.characters_per_bucket
	assert_gte(per_element, _cfg.deploy_slots_base, "单一属性的角色数应够填满初始出战席")


func test_star_ups_need_three_copies() -> void:
	# §08：同卡 3 张升 1 星。
	var unit := PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.R)
	assert_eq(unit.star(), 1, "第 1 张是 1 星")
	unit.copies = 3
	assert_eq(unit.star(), 1, "3 张仍是 1 星")
	unit.copies = 4
	assert_eq(unit.star(), 2, "第 4 张升到 2 星")
	unit.copies = 7
	assert_eq(unit.star(), 3, "第 7 张升到 3 星")
	assert_gt(unit.power(_cfg), PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.R).power(_cfg))
