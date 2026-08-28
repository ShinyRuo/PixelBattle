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


func test_income_streams_add_up_to_the_gold_that_actually_moved() -> void:
	# 分流记账是诊断 §07 的入口，而记账最容易出的错是**漏记一条流** ——
	# 漏了不报错，只表现为「某条流看起来不重要」，而那正是要下结论的地方。
	#
	# 不变式：开局金币 + 五条流之和 − 花掉的 = 手上剩的。
	# 注意左边不能用 gold_earned —— 它只累计正数，而纲手会掉负数（§07 有意保留）。
	var cfg := PBSimConfig.new()
	for seed_value: int in [20260827, 4242, 991]:
		var state := PBRunSim.new_state(cfg)
		var strategy := PBStratBalanced.new()
		var rng := PBRngStreams.new(seed_value)
		for _wave: int in 12:
			var plan := PBRunSim.plan_wave(state, strategy, cfg, rng)
			var outcome := PBCombatRules.resolve(plan.wave, plan.dps, state.def_reduction(cfg), cfg)
			PBRunSim.settle_wave(state, plan, outcome, cfg, rng)
			if state.base_hp <= 0.0:
				break
			state.wave_index += 1

		var total: int = 0
		for source: StringName in PBEconomyRules.GOLD_SOURCES:
			total += int(state.gold_by_source.get(source, 0))
		assert_eq(
			cfg.starting_gold + total - state.gold_spent,
			state.gold,
			"五条收入流之和对不上账，说明有一条没记 —— 种子 %d" % seed_value
		)


func test_the_split_preparation_path_is_bit_identical_to_the_batch_path() -> void:
	# **M1-a 最要紧的一条。** 为了让真人玩家能在准备阶段停下来，
	# plan_wave 被拆成了 begin_wave（掷波次与任务）→ 花钱选人 → lock_plan（锁定）。
	#
	# 拆之后**三条 RNG 流的消费次序必须一字不差**，否则批量校出来的数值
	# 和实际玩到的会分叉 —— 而这种分叉不报任何错，只表现为
	# 「怎么手感和扫描结论对不上」。
	#
	# 这里用同一个种子跑两条路：一条走合成好的 plan_wave（批量模拟走的），
	# 一条手动 begin_wave / lock_plan（画面走的），结果必须完全一致。
	var cfg := PBSimConfig.new()
	for seed_value: int in [20260827, 4242, 991]:
		var packed := PBRunSim.run(cfg, PBStratBalanced.new(), seed_value)

		var state := PBRunSim.new_state(cfg)
		var strategy := PBStratBalanced.new()
		var rng := PBRngStreams.new(seed_value)
		while state.wave_index <= cfg.max_wave:
			var plan := PBRunSim.begin_wave(state, cfg, rng)
			strategy.prepare(state, plan.wave, cfg, rng)
			PBRunSim.lock_plan(
				state,
				plan,
				strategy.deploy(state, plan.wave, cfg),
				strategy.accept_quest(state, plan.wave, plan.quest_grade, cfg),
				cfg
			)
			var outcome := PBCombatRules.resolve(plan.wave, plan.dps, state.def_reduction(cfg), cfg)
			PBRunSim.settle_wave(state, plan, outcome, cfg, rng)
			if state.base_hp <= 0.0:
				break
			state.wave_index += 1

		assert_eq(state.wave_index, packed.wave_reached, "拆开走应到达同一波 —— 种子 %d" % seed_value)
		assert_eq(state.gacha_pulls, packed.gacha_pulls, "抽卡次数必须一致，否则 gacha 流已经错位")
		assert_eq(state.gold_earned, packed.gold_earned, "总收入必须一致，否则 quest/combat 流已经错位")
