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
			PBUnit.of(
				_cfg,
				rng.randi_range(0, 5) as PBElement.Type,
				rng.randi_range(0, PBUnit.Rarity.size() - 1) as PBUnit.Rarity,
				rng.randi_range(0, _cfg.characters_per_bucket - 1)
			)
		)
	return state


## 用**本地** rng 洗一份牌。`Array.shuffle()` 读的是全局 RNG，
## 那正是 §14 铁律 3 禁掉的东西 —— 它的状态由同一个进程里跑过的一切决定，
## 于是「测试红不红」取决于前面跑了哪些文件，改一个无关的测试就可能翻面。
func _shuffled(units: Array[PBUnit], rng: RandomNumberGenerator) -> Array[PBUnit]:
	var out := units.duplicate()
	for i: int in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: PBUnit = out[i]
		out[i] = out[j]
		out[j] = swap
	return out


## 「另一种排法没有赢」—— 允许最后几位的误差。
##
## ## 为什么不能用严格的 `>=`（M9-f 撞上的）
##
## 物理波（M9-f 加进轮转的那一格）上**没有任何一系被克制**，于是
## 「按有效战力排」和「按裸战力排」选出的是**同一批人**，只是顺序不同 ——
## 而浮点求和的顺序会改变最后几位（实测差 −4.5e-13）。
## 严格 `>=` 在那一波量的是加法结合律，不是这条测试要守的结论。
##
## 容差取相对值而不是一个绝对数：这些 DPS 在几千的量级，
## 而卡池一变就是另一个量级，写死的 `1e-9` 迟早在某个量级下变成
## 「什么都拦不住」或者「一直红」。
func _not_beaten(best: float, other: float, message: String) -> void:
	assert_gte(best, other - 1e-9 * maxf(absf(best), 1.0), message)


func test_picking_by_effective_power_is_strictly_optimal() -> void:
	# **这条是「阵容面板只展示、不让玩家自由选人」那个决定的依据。**
	#
	# 伤害公式是 `Σ(上场单位的有效战力) × 科技 × 羁绊 × 装备`，
	# 后三个乘数都不依赖于「上了谁」（羁绊看仓库人数、装备看位置数），
	# 所以按有效战力取前 N 就是最优解 —— 自由选人只能选得更差。
	#
	# 这里拿三种别的排法对比：裸战力排、倒序排、随机排。
	# 哪一种赢了，上面那个结论就不成立，阵容 UI 就该改成可选。
	#
	# **三种排法都必须从在场名单里挑，不能从全仓挑。** M2-c 之后
	# [method PBValuation.deployed_for] 只在在场名单里选人（出战席必然是它的子集），
	# 拿全仓的随机样本去比就是两个不同的池子在对比 —— 运气好的样本能从
	# 板凳外捞到更强的卡，赢了也不说明「按有效战力排不是最优」。
	# 这个口径错误一直在，只是靠 `Array.shuffle()` 读全局 RNG 的运气盖着；
	# 换成本地 rng 之后它是确定性的，永远不会再靠运气红或绿。
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
		_not_beaten(best, PBValuation.dps_of(by_raw, element, state, _cfg), "按裸战力排不该更强")

		var reversed: Array[PBUnit] = state.field_units(_cfg)
		reversed.reverse()
		var tail := reversed.slice(0, slots)
		_not_beaten(best, PBValuation.dps_of(tail, element, state, _cfg), "倒序排不该更强")

		for _try: int in 5:
			var sample := _shuffled(state.field_units(_cfg), rng).slice(0, slots)
			_not_beaten(best, PBValuation.dps_of(sample, element, state, _cfg), "随便排不该更强")


func test_rotation_is_worth_more_when_the_roster_covers_the_counter() -> void:
	# 阵容面板上「换人多赚 x%」那一行的意义：它随卡池和波次属性一起动。
	# 卡池里没有克星的那一波，差值应该塌到接近 0。
	var covered := PBRunSim.new_state(_cfg)
	var bare := PBRunSim.new_state(_cfg)
	for i: int in 8:
		# 一个五系齐全，一个全是物理（物理不参与克制环，§03）。
		covered.add_unit(PBUnit.of(_cfg, (i % 5) as PBElement.Type, PBUnit.Rarity.SR, i % 2))
		bare.add_unit(PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR, i % 2))

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


func test_dispatching_always_costs_dps_and_costs_more_the_more_you_send() -> void:
	# 派出去的代价有**两截**：羁绊失效（整队一起降）+ 他这一波不上场。
	#
	# ## 这一条 M3.5-i 换过一次判据
	#
	# 旧版断的是「卡池深过 `bond_unit_cap` 之后派遣是白捡的钱」——
	# 那在待命台还在的时候成立：派的是不上场的板凳，掉的档又被计数上限吃掉。
	# **待命台删掉之后那一支不存在了**：在场上限从 16 掉到 10（出战席），
	# 而计数上限是 12，够都够不着；何况派走的人现在真的离场。
	#
	# 所以现在钉的是新规矩下必须成立的那两条：代价恒为正、且派得越多越贵。
	# 「出厂那个 12 该改成多少」是数值回归的事，不该由一条测试顺手拍板。
	var state := _roster_of(12)
	var base: float = PBValuation.mean_dps(state, _cfg)
	var one: float = PBValuation.dispatch_loss(state, _cfg, base, 1)
	var three: float = PBValuation.dispatch_loss(state, _cfg, base, 3)
	assert_gt(one, 0.0, "派人一定要付代价 —— 不然 §06 那个取舍在模型里不存在")
	assert_gt(three, one, "派得越多越贵")


func test_the_info_panel_shows_both_element_multipliers() -> void:
	# §03 说原版最大的短板是克制关系不可见，而 §03A 把它拆成了两条线：
	# **攻元素克不克得动这一波、防元素扛不扛得住这一波**。
	# 只写一个「火系」的话，玩家读到的还是旧模型。
	var state := _roster_of(12)
	var wave := PBWaveRules.build(3, _cfg, RandomNumberGenerator.new())
	var deployed := PBValuation.deployed_for(state, wave.element, _cfg)
	assert_gt(deployed.size(), 0, "这个卡池应该派得出人")

	var panel := PBUnitInfo.new()
	add_child_autofree(panel)
	var unit: PBUnit = deployed[0]
	panel.refresh(PBSelection.of_unit(unit.key()), state, _cfg, wave, deployed)

	var text: String = panel._body.text
	var attack: float = _cfg.damage_multiplier(PBElement.relation(unit.element, wave.element))
	var defend: float = _cfg.damage_multiplier(PBElement.relation(wave.element, unit.def_element))
	assert_true(text.contains("×%.2f" % attack), "该写明攻元素对本波的倍率：%s" % text)
	assert_true(text.contains("×%.2f" % defend), "也该写明挨打的倍率：%s" % text)


func test_the_info_panel_falls_back_to_the_team_account_with_nobody_selected() -> void:
	# 没选人时把整队的账写在这里 —— 空着不写等于浪费屏幕上最好的一块地方。
	var state := _roster_of(6)
	var wave := PBWaveRules.build(3, _cfg, RandomNumberGenerator.new())
	var panel := PBUnitInfo.new()
	add_child_autofree(panel)
	var nobody: Array[PBUnit] = []
	panel.refresh(PBSelection.new(), state, _cfg, wave, nobody)
	assert_true(panel._body.text.contains("羁绊"), "没选人时该显示整队的账：%s" % panel._body.text)
