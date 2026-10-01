extends GutTest
## [PBStratRational] 的**快档**测试：不跑整局，只直接量估值函数。
##
## 这个流派是**校 §10 装备定价用的仪器**，不是一种玩法。所以这里测的不是
## 「它能打多少波」，而是**它作为仪器还准不准**。
##
## ## 分档
##
## 「它跑出来的局符不符合配平结论」（真的会买装备、经济位不是陷阱、不比
## `balanced` 差）全部搬去了 `test_balance_scan.gd` —— 那些每条都要跑完整的局，
## `rational` 一局 2.1 秒，合起来 83 秒，占了整套测试的 85%。
## 判据与迁移理由写在那个文件的开头。
##
## **留在这里的四条不跑任何一局**，直接对 [PBValuation] 的函数下断言。
## 它们是「改代码就会红」的那一类，所以每次自检都跑。


func test_the_registry_knows_it() -> void:
	var strategy := PBStrategyRegistry.make(&"rational")
	assert_not_null(strategy, "registry 应该造得出 rational")
	assert_eq(strategy.id, &"rational", "id 应该对得上 CSV 里的列值")


func test_gacha_is_worth_less_once_the_bench_is_full_of_good_cards() -> void:
	# 抽卡的边际价值必须随卡池变好而衰减 —— §10 的「装备是后期金币的主要去处」
	# 整个建立在这条曲线上。不衰减的话拐点永远不出现，装备定多少钱都没人买。
	var cfg := PBSimConfig.new()

	var empty := PBRunSim.new_state(cfg)
	empty.add_unit(PBUnit.of(cfg, PBElement.Type.FIRE, PBUnit.Rarity.R))
	var early: float = PBValuation.gacha_gain(empty, cfg)

	var stacked := PBRunSim.new_state(cfg)
	stacked.tech_pop = cfg.tech_pop_max
	for element: int in PBElement.Type.size():
		for variant: int in cfg.characters_per_bucket:
			stacked.add_unit(PBUnit.of(cfg, element as PBElement.Type, PBUnit.Rarity.SSR, variant))
	var late: float = PBValuation.gacha_gain(stacked, cfg)

	assert_gt(early, late, "板凳全是顶档 之后，再抽一张的边际价值应显著低于开局")


func test_a_duplicate_is_worth_the_same_body_but_no_bond() -> void:
	# **M5-9 把「重复卡只加星级进度」整段拿掉了**：重复抽到的是另一个人，
	# 他立刻能上场、能升级、能带装备，作为**战力**和新卡一模一样。
	#
	# 差的那一份在羁绊那一侧：羁绊按**角色**算档
	# （[method PBBondRules.active_count]），同名的第二个人一组都不多。
	var cfg := PBSimConfig.new()
	var virgin := PBRunSim.new_state(cfg)
	var owned := PBRunSim.new_state(cfg)
	for rarity: int in cfg.rarity_power.size():
		for element: int in PBElement.Type.size():
			for variant: int in cfg.characters_per_bucket:
				owned.add_unit(
					PBUnit.of(cfg, element as PBElement.Type, rarity as PBUnit.Rarity, variant)
				)

	# 门槛固定为 0，两边只差「卡池里有没有这些角色」—— 拿两个完整局面去比
	# 会把「队伍强弱」混进来，那条差异不是这里要测的东西。
	var fresh: float = PBValuation.expected_surplus(PBElement.Type.FIRE, 0.0, virgin, cfg)
	var dupes: float = PBValuation.expected_surplus(PBElement.Type.FIRE, 0.0, owned, cfg)
	assert_gt(fresh, 0.0, "空卡池时每一抽都是新卡，期望收益应为正")
	assert_almost_eq(dupes, fresh, fresh * 1e-6, "作为战力，重复卡和新卡一样值钱")

	assert_gt(
		PBValuation.expected_bond_gain(virgin, cfg),
		PBValuation.expected_bond_gain(owned, cfg),
		"羁绊那一侧才是重复卡的差价 —— 抽满之后再抽一张，一组羁绊都不多"
	)
