extends GutTest
## §06 / §07 / §08 / §10 的规则表与派生量校验。
##
## 和 `test_run_sim.gd` 分开是有理由的：那边测的是**整局模拟的自洽性**
## （确定性、单调性、守恒），这边测的是**表和公式本身**。
## 两件事的失效模式不同 —— 表写错是「某个波段的概率悄悄偏了」，
## 模拟写错是「结论整体漂移」，混在一个文件里读的人分不清该看哪条。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


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
	var one := PBEconomyRules.kakuzu_income(1, 20, _cfg)
	var two := PBEconomyRules.kakuzu_income(2, 20, _cfg)
	var three := PBEconomyRules.kakuzu_income(3, 20, _cfg)
	assert_gt(two, one, "第二个角都仍有正收益")
	assert_lt(two - one, one, "第二个的边际收益应低于第一个")
	assert_lt(three - two, two - one, "边际收益应持续递减")
	assert_eq(PBEconomyRules.kakuzu_income(0, 20, _cfg), 0, "没有角都就没有回合收入")


func test_kakuzu_income_grows_with_the_wave_index() -> void:
	# **常数收益是「角都从来没人选」的根因。**
	#
	# 波次奖金是 45+6n、任务是 160+22n，都跟着波次涨，只有角都是常数 85 ——
	# 于是它占掉的那个出战位越到后期越值钱，而它给的钱不变。
	# 实测后果：每一个不被强制的流派，角都占总收入的比例都是 0%。
	assert_gt(
		PBEconomyRules.kakuzu_income(1, 30, _cfg),
		PBEconomyRules.kakuzu_income(1, 5, _cfg),
		"第 30 波的角都收益应高于第 5 波，否则它会随波次贬值到没人要"
	)


func test_dispatch_costs_bonds() -> void:
	# §06 的核心：派遣期间羁绊不生效。没有这个代价，「要羁绊还是要钱」
	# 就没有取舍，派满永远最优 —— 正是 §06 想改掉的原版毛病。
	var state := PBRunState.new()
	for i: int in 8:
		state.add_unit(PBUnit.of(_cfg, (i % 5) as PBElement.Type, PBUnit.Rarity.SR))
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
