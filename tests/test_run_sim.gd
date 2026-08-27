extends GutTest
## [PBRunSim] 的整局模拟测试，外加 [PBEconomyRules] 的表校验。
##
## 这一层不测「数值配得对不对」—— 那正是 M-1 要跑出来的答案，写死断言等于
## 先射箭后画靶。这里只测**模型的自洽性**：确定性、单调性、守恒、表的完整性。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()
	# 测试里把上限压低，跑满 200 波会让整个测试套慢下来。
	_cfg.max_wave = 60


func _run(strategy_id: StringName, run_seed: int = 1000) -> PBRunResult:
	return PBRunSim.run(_cfg, PBStrategyRegistry.make(strategy_id), run_seed)


func test_every_registered_strategy_can_be_built_and_run() -> void:
	for id: StringName in PBStrategyRegistry.IDS:
		var strategy := PBStrategyRegistry.make(id)
		assert_not_null(strategy, "流派 %s 应能被造出来" % id)
		assert_eq(strategy.id, id, "流派 %s 的 id 字段应与注册名一致" % id)
		var result := _run(id)
		assert_gt(result.wave_reached, 0, "流派 %s 至少应打完第 1 波" % id)


func test_unknown_strategy_returns_null() -> void:
	assert_null(PBStrategyRegistry.make(&"nonexistent"), "不认识的流派应返回 null")


func test_same_seed_reproduces_the_run_exactly() -> void:
	# §12 的地基。同种子两局必须逐字段一致，否则存档回滚和每日种子都无从谈起。
	for id: StringName in PBStrategyRegistry.IDS:
		var a := _run(id, 777)
		var b := _run(id, 777)
		assert_eq(a.wave_reached, b.wave_reached, "%s：同种子应卡在同一波" % id)
		assert_eq(a.total_kills, b.total_kills, "%s：同种子的击杀数应一致" % id)
		assert_eq(a.gold_earned, b.gold_earned, "%s：同种子的总收入应一致" % id)
		assert_eq(a.gacha_pulls, b.gacha_pulls, "%s：同种子的抽卡次数应一致" % id)


func test_different_seeds_produce_different_runs() -> void:
	# 反过来也要成立：种子不同结果全一样，说明 RNG 根本没接进去。
	var waves := {}
	for run_seed: int in range(1, 30):
		waves[_run(&"balanced", run_seed).wave_reached] = true
	assert_gt(waves.size(), 1, "不同种子应跑出不同结果，否则 RNG 没生效")


func test_strategy_objects_are_not_reused_across_runs() -> void:
	# 流派对象带可变字段，跨局复用会让上一局的状态渗进下一局 ——
	# 这种污染在结果里看不出来，只能靠这条测试拦。
	var first := PBStrategyRegistry.make(&"balanced")
	var second := PBStrategyRegistry.make(&"balanced")
	assert_ne(first.get_instance_id(), second.get_instance_id(), "每次 make 应给新实例")


func test_higher_growth_never_helps_the_player() -> void:
	# 单调性：GROWTH 是整条难度曲线的主控，调高只可能更难。
	# 用配对比较（同一批种子）消掉运气，再比中位数。
	var medians: Array[float] = []
	for growth: float in [1.10, 1.125, 1.15]:
		_cfg.growth = growth
		var reached: Array[int] = []
		for run_seed: int in range(1, 25):
			reached.append(_run(&"balanced", run_seed).wave_reached)
		reached.sort()
		medians.append(float(reached[reached.size() / 2]))
	assert_lte(medians[1], medians[0], "GROWTH 1.125 不该比 1.10 更容易")
	assert_lte(medians[2], medians[1], "GROWTH 1.15 不该比 1.125 更容易")


func test_hit_wave_cap_is_flagged_not_silently_folded_in() -> void:
	# 打穿上限和卡在上限是两回事。混为一谈会把 GROWTH 校准得偏低。
	_cfg.max_wave = 3
	var result := _run(&"balanced", 5)
	assert_eq(result.wave_reached, 3, "应打到人为设定的上限")
	assert_true(result.hit_wave_cap, "撞上限必须被标出来")


func test_battle_duration_is_tracked_for_the_spec_target() -> void:
	# §01 要求单波战斗 30–45 秒。M-1 只负责把它量出来，不负责让它达标。
	var result := _run(&"balanced", 31)
	assert_gt(result.mean_battle_seconds(), 0.0, "应记录到战斗时长")
	assert_between(result.duration_hit_rate(), 0.0, 1.0, "达标率应是个比例")


func test_gacha_table_bands_are_complete_and_sum_to_100() -> void:
	# §08 的概率表。少写一档或加错和，会让某个波段的抽卡概率悄悄偏掉。
	for row: Array in PBEconomyRules.GACHA_TABLE:
		var total: float = float(row[1]) + float(row[2]) + float(row[3]) + float(row[4])
		assert_almost_eq(total, 100.0, 1e-6, "波次 ≤%d 段的概率应加总为 100" % int(row[0]))


func test_gacha_gets_better_over_time() -> void:
	# §08 的节奏设计：30 波后开始爆种。高稀有度概率必须单调上升。
	var previous: float = -1.0
	for row: Array in PBEconomyRules.GACHA_TABLE:
		var high_rarity: float = float(row[3]) + float(row[4])
		assert_gt(high_rarity, previous, "SSR+USR 概率应随波段单调上升")
		previous = high_rarity


func test_pity_guarantees_an_ssr() -> void:
	# §08：连续 20 抽无 SSR 及以上，第 21 抽必出。
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var unit := PBEconomyRules.roll_gacha(1, _cfg.gacha_pity, _cfg, rng)
	assert_gte(int(unit.rarity), int(PBUnit.Rarity.SSR), "保底触发时必须出 SSR 及以上")


func test_tech_costs_climb_and_stop_at_max_level() -> void:
	for branch: StringName in [&"gold", &"pop", &"atk", &"def"]:
		var previous: int = -1
		for level: int in 6:
			var cost := PBEconomyRules.tech_cost(branch, level, _cfg)
			assert_gt(cost, previous, "%s 科技第 %d 级应比上一级贵" % [branch, level])
			previous = cost
	assert_eq(PBEconomyRules.tech_cost(&"gold", _cfg.tech_gold_max, _cfg), -1, "满级应返回 -1")
	assert_eq(PBEconomyRules.tech_cost(&"nope", 0, _cfg), -1, "不认识的分支应返回 -1")


func test_kakuzu_income_falls_off_sharply() -> void:
	# §07 的改动：递减从原版的减半改成 k^−1.5，更陡。
	# 这样「上第二个角都」是真实的战力牺牲，不是无脑叠。
	var one := PBEconomyRules.kakuzu_income(1, _cfg)
	var two := PBEconomyRules.kakuzu_income(2, _cfg)
	var three := PBEconomyRules.kakuzu_income(3, _cfg)
	assert_gt(two, one, "第二个角都仍有正收益")
	assert_lt(two - one, one, "第二个的边际收益应低于第一个")
	assert_lt(three - two, two - one, "边际收益应持续递减")
	assert_eq(PBEconomyRules.kakuzu_income(0, _cfg), 0, "没有角都就没有回合收入")


func test_dispatch_costs_bonds() -> void:
	# §06 的核心：派遣期间羁绊不生效。没有这个代价，「要羁绊还是要钱」
	# 就没有取舍，派满永远最优 —— 正是 §06 想改掉的原版毛病。
	var state := PBRunState.new()
	for i: int in 8:
		state.add_unit(PBUnit.new((i % 5) as PBElement.Type, PBUnit.Rarity.SR))
	var full := state.bond_mult(_cfg)
	state.dispatched = 3
	assert_lt(state.bond_mult(_cfg), full, "派遣中的忍者不应再提供羁绊加成")


func test_equipment_is_a_bottomless_gold_sink() -> void:
	# §10 的装备是后期金币的主要去处。**缺了它整个经济系统会被误判成「不重要」** ——
	# 抽卡有天花板（卡池只有 4×6×variant 张），中期就抽满，之后金币边际收益趋近于零。
	# 装备没有那个天花板：满装一队要 10×3×3×1350 = 121,500 金，比一整局总收入还多。
	var state := PBRunState.new()
	state.tech_pop = 6  # 出战席开到 10 个位置
	var bare := state.equip_mult(_cfg)
	assert_eq(bare, 1.0, "没有装备时不该有加成")

	# 配件要凑够数才合成一件成品，不满 3 个不产生任何战力。
	state.equip_parts = _cfg.equip_parts_per_item - 1
	assert_eq(state.equip_mult(_cfg), 1.0, "配件不满一件成品时不该有加成")

	state.equip_parts = _cfg.equip_parts_per_item
	assert_gt(state.equip_mult(_cfg), 1.0, "凑满一件成品应产生加成")

	# 一路买到装满整队，加成应持续上升 —— 这正是它能当无底坑的原因。
	var previous := state.equip_mult(_cfg)
	for _step: int in 20:
		state.equip_parts += _cfg.equip_parts_per_item * 3
		var now := state.equip_mult(_cfg)
		assert_gte(now, previous, "装满整队之前，加成不该下降")
		previous = now


func test_equipment_saturates_and_stops_absorbing() -> void:
	# 装满之后不能再涨，否则金币变成无限战力，比抽卡万能还糟。
	var state := PBRunState.new()
	var slots := state.deploy_capacity(_cfg)
	state.equip_parts = slots * _cfg.equip_items_per_unit * _cfg.equip_parts_per_item
	var full := state.equip_mult(_cfg)
	state.equip_parts *= 10
	assert_eq(state.equip_mult(_cfg), full, "装满整队后再买配件不该继续加战力")
	var expected := 1.0 + _cfg.equip_power_per_item * float(_cfg.equip_items_per_unit)
	assert_almost_eq(full, expected, 1e-6, "满装的加成应等于「每人 3 件 × 每件加成」")


func test_quest_table_matches_spec_costs() -> void:
	# §06 任务表：C/B 派 2 人，A/S 派 3 人，SSS 派 4 人。
	# SSS 要 4 人而待命台初始只有 3 格 —— 人口科技的追求目标就是这么来的。
	assert_eq(PBEconomyRules.quest_cost_units(0), 2, "C 级任务派 2 人")
	assert_eq(PBEconomyRules.quest_cost_units(4), 4, "SSS 级任务派 4 人")
	assert_gt(PBEconomyRules.quest_cost_units(4), _cfg.standby_slots_base, "SSS 应超出初始待命格数")
	for grade: int in PBEconomyRules.QUEST_TABLE.size():
		var early := PBEconomyRules.quest_reward(grade, 1)
		var late := PBEconomyRules.quest_reward(grade, 40)
		assert_gt(late, early, "任务奖励应随波次增长")
