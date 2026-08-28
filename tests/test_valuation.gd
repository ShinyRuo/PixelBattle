extends GutTest
## [PBValuation] 的测试。
##
## 它同时被模拟玩家（比价）和准备阶段界面（显示「买下去涨多少」）调用，
## **两边必须给出同一个数**，所以它的正确性比一般的辅助函数更要紧：
## 算错了不报错，只表现为「玩家按界面上的数做决定，却和策划调参的依据对不上」。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func _roster_of(count: int) -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	state.tech_pop = _cfg.tech_pop_max
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i: int in count:
		state.add_unit(
			PBUnit.new(
				rng.randi_range(0, 5) as PBElement.Type,
				rng.randi_range(0, 3) as PBUnit.Rarity,
				rng.randi_range(0, _cfg.characters_per_bucket - 1)
			)
		)
	return state


func test_picking_by_effective_power_is_strictly_optimal() -> void:
	# **这条是「阵容面板只展示、不让玩家自由选人」那个决定的依据。**
	#
	# 伤害公式是 `Σ(上场单位的有效战力) × 科技 × 羁绊 × 装备`，
	# 后三个乘数都不依赖于「上了谁」（羁绊看仓库人数、装备看位置数），
	# 所以按有效战力取前 N 就是最优解 —— 自由选人只能选得更差。
	#
	# 这里拿三种别的排法对比：裸战力排、倒序排、随机排。
	# 哪一种赢了，上面那个结论就不成立，阵容 UI 就该改成可选。
	var state := _roster_of(24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991

	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		var slots: int = state.open_slots(_cfg)
		var best: float = PBValuation.dps_of(
			PBValuation.deployed_for(state, element, _cfg), element, state, _cfg
		)

		var by_raw := PBValuation.deployed_by_raw_power(state, _cfg)
		assert_gte(best, PBValuation.dps_of(by_raw, element, state, _cfg), "按裸战力排不该更强")

		var reversed: Array[PBUnit] = state.all_units()
		reversed.reverse()
		var tail := reversed.slice(0, slots)
		assert_gte(best, PBValuation.dps_of(tail, element, state, _cfg), "倒序排不该更强")

		for _try: int in 5:
			var shuffled: Array[PBUnit] = state.all_units()
			shuffled.shuffle()
			var sample := shuffled.slice(0, slots)
			assert_gte(best, PBValuation.dps_of(sample, element, state, _cfg), "随便排不该更强")


func test_rotation_is_worth_more_when_the_roster_covers_the_counter() -> void:
	# 阵容面板上「换人多赚 x%」那一行的意义：它随卡池和波次属性一起动。
	# 卡池里没有克星的那一波，差值应该塌到接近 0。
	var covered := PBRunSim.new_state(_cfg)
	var bare := PBRunSim.new_state(_cfg)
	for i: int in 8:
		# 一个五系齐全，一个全是物理（物理不参与克制环，§03）。
		covered.add_unit(PBUnit.new((i % 5) as PBElement.Type, PBUnit.Rarity.SR, i % 2))
		bare.add_unit(PBUnit.new(PBElement.Type.PHYSICAL, PBUnit.Rarity.SR, i % 2))

	var element := PBElement.Type.THUNDER
	var covered_gain: float = _rotation_gain(covered, element)
	var bare_gain: float = _rotation_gain(bare, element)
	assert_gt(covered_gain, bare_gain, "有克星的卡池，换人才值钱")
	assert_almost_eq(bare_gain, 0.0, 1e-6, "纯物理卡池换人一分钱都不多赚 —— 它不参与克制环")


func _rotation_gain(state: PBRunState, element: PBElement.Type) -> float:
	var smart: float = PBValuation.dps_of(
		PBValuation.deployed_for(state, element, _cfg), element, state, _cfg
	)
	var naive: float = PBValuation.dps_of(
		PBValuation.deployed_by_raw_power(state, _cfg), element, state, _cfg
	)
	if naive <= 0.0:
		return 0.0
	return smart / naive - 1.0


func test_dispatch_estimates_leave_no_trace_on_the_state() -> void:
	# 两个估值函数都用「改一下、量一次、改回来」，而它们量的是 `dispatched` ——
	# 那个字段归 [method PBRunSim.lock_plan] 管。漏改回来的话，
	# 玩家在准备阶段每看一眼任务卡，本波的羁绊就掉一层，而且不报任何错。
	var state := _roster_of(10)
	var wave := PBWaveRules.build(9, _cfg, RandomNumberGenerator.new())
	var units := PBValuation.deployed_for(state, wave.element, _cfg)
	var before: float = PBValuation.mean_dps(state, _cfg)

	PBValuation.dispatch_loss(state, _cfg, before, 3)
	PBValuation.dps_if_dispatched(state, wave, units, 3, _cfg)

	assert_eq(state.dispatched, 0, "估值不该留下派遣标记")
	assert_almost_eq(PBValuation.mean_dps(state, _cfg), before, 1e-6, "估值不该改动队伍战力")


func test_the_leak_threshold_is_the_real_cliff() -> void:
	# 任务卡拿这个数当分母，所以它必须真的是那条线：
	# 差一点点在上面就一个不漏，差一点点在下面就开始漏。
	#
	# 二分成立的前提是 `resolve` 对 dps 单调 ——
	# 那条性质由 `test_more_dps_never_produces_more_leaks` 锁着。
	var rng := RandomNumberGenerator.new()
	for wave_index: int in [1, 7, 20, 30, 41]:
		var wave := PBWaveRules.build(wave_index, _cfg, rng)
		var cliff: float = PBValuation.leak_threshold_dps(wave, 0.0, _cfg)
		assert_gt(cliff, 0.0, "第 %d 波应该存在一条悬崖" % wave_index)
		assert_eq(
			PBCombatRules.resolve(wave, cliff * 1.02, 0.0, _cfg).leaked,
			0,
			"第 %d 波：比悬崖高一点就不该漏" % wave_index
		)
		assert_gt(
			PBCombatRules.resolve(wave, cliff * 0.98, 0.0, _cfg).leaked,
			0,
			"第 %d 波：比悬崖低一点就该开始漏" % wave_index
		)


func test_dispatching_costs_dps_until_the_bench_passes_the_bond_cap() -> void:
	# 派出去的人羁绊失效（§06），所以代价是**整队一起降** ——
	# 被派的是待命台上本来就不上场的人，他们自己的输出一点没少。
	# 这一点手推很容易推反，所以钉一条。
	var thin := _roster_of(7)
	var loss: float = PBValuation.dispatch_loss(thin, _cfg, PBValuation.mean_dps(thin, _cfg), 3)
	assert_gt(loss, 0.0, "板凳没到羁绊上限时，派人一定要付代价")

	# 卡池深到超过 bond_unit_cap 之后，派遣是白捡的钱。
	#
	# 前置条件是**派完之后还在上限之上**，不是「派之前在上限之上」——
	# 后者是我第一版写的，它松得刚好放过了真正的失败情形：
	# 板凳 15 人、上限 12、派 4 个人，派之前是 12 档，派之后掉到 11。
	# 抽 40 次是为了凑够唯一卡 —— 重复卡在仓库里会合并，抽 20 次只有十几张。
	var deep := _roster_of(40)
	assert_gte(deep.roster.size() - 4, _cfg.bond_unit_cap, "派完之后仍要在羁绊上限之上")
	var free_loss: float = PBValuation.dispatch_loss(
		deep, _cfg, PBValuation.mean_dps(deep, _cfg), 4
	)
	assert_almost_eq(free_loss, 0.0, 1e-9, "过了羁绊上限，派人不该再掉战力")


func test_the_roster_panel_shows_the_multiplier_on_every_deployed_card() -> void:
	# §03 说原版最大的短板是克制关系不可见。面板每一格都要写出倍率，
	# 否则玩家还是只能靠背。
	var state := _roster_of(12)
	var wave := PBWaveRules.build(3, _cfg, RandomNumberGenerator.new())
	var panel := PBRosterPanel.new()
	add_child_autofree(panel)
	panel.refresh(state, _cfg, wave)

	var deployed := PBValuation.deployed_for(state, wave.element, _cfg)
	assert_gt(deployed.size(), 0, "这个卡池应该派得出人")
	for i: int in deployed.size():
		var text: String = (panel._slots[i] as Label).text
		var expected: float = (
			deployed[i].effective_power(wave.element, _cfg) / deployed[i].power(_cfg)
		)
		assert_true(text.contains("×%.2f" % expected), "第 %d 格应写明克制倍率：%s" % [i, text])

	# 没坐满的位置要看得出是空的，而不是留着上一波的残留。
	for i: int in range(deployed.size(), _cfg.deploy_slots_max):
		assert_eq((panel._slots[i] as Label).text, "—", "空位应显示成空")


func test_the_roster_panel_says_so_when_the_counter_is_missing() -> void:
	# 「为什么这一波突然打不动」是原版最恼人的一处 —— §03 点名要补。
	var state := PBRunSim.new_state(_cfg)
	for i: int in 6:
		state.add_unit(PBUnit.new(PBElement.Type.PHYSICAL, PBUnit.Rarity.SR, i % 2))
	var wave := PBWaveRules.build(1, _cfg, RandomNumberGenerator.new())
	var panel := PBRosterPanel.new()
	add_child_autofree(panel)
	panel.refresh(state, _cfg, wave)
	assert_true(panel._rotation.text.contains("缺"), "纯物理卡池应明确提示缺克星：%s" % panel._rotation.text)
