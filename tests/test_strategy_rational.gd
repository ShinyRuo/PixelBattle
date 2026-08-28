extends GutTest
## [PBStratRational] 的测试。
##
## 这个流派是**校 §10 装备定价用的仪器**，不是一种玩法。所以这里测的不是
## 「它能打多少波」，而是**它作为仪器还准不准**：
##
## 1. 它真的看价格（其余流派不看，这正是它存在的理由）
## 2. 它不比写死优先级的 `balanced` 差（否则「会算账」的前提就不成立）
## 3. 它的估值口径覆盖了后期最要紧的那一项：重复卡

const SEEDS: Array[int] = [20260827, 991, 4242, 70707, 13]


func _run_with(part_cost: int, seed_value: int) -> PBRunResult:
	var cfg := PBSimConfig.new()
	if part_cost > 0:
		cfg.equip_part_cost = part_cost
	return PBRunSim.run(cfg, PBStratRational.new(), seed_value)


func test_the_registry_knows_it() -> void:
	var strategy := PBStrategyRegistry.make(&"rational")
	assert_not_null(strategy, "registry 应该造得出 rational")
	assert_eq(strategy.id, &"rational", "id 应该对得上 CSV 里的列值")


func test_it_actually_responds_to_the_equipment_price() -> void:
	# **本文件最要紧的一条，也是这个流派存在的全部理由。**
	#
	# 其余流派的花钱顺序写死，`gacha_still_pays()` 看的是板凳坐没坐满，
	# 从头到尾没有任何判断读过 `equip_part_cost` —— 拿它们扫价格，
	# 扫出来的只是「剩下的钱能多买几个配件」，不是「玩家会不会改买装备」。
	# 用一个不看价格的玩家去校准价格，问出来的答案没有意义。
	var cheap: int = 0
	var expensive: int = 0
	for seed_value: int in SEEDS:
		cheap += _run_with(0, seed_value).final_equip_parts
		expensive += _run_with(1350, seed_value).final_equip_parts
	assert_gt(cheap, 0, "按定好的价格应该真的会买装备")
	# 断言的是**比值**，不是「旧价下买 0 个」。
	# 定价那次扫描时旧价确实是 0，但 §07 把角都改成随波次走之后玩家富了不少，
	# 抽卡更早饱和，于是旧价下也会买几个。价格敏感性没变，绝对值变了 ——
	# 把绝对值写进断言会让它随经济的任何一次调整误报。
	assert_gt(cheap, expensive * 3, "价格翻 4.5 倍，买到的配件应少一个数量级")


func test_equipment_price_satisfies_the_spec_hard_constraint() -> void:
	# **§10 的硬约束：装备必须比抽卡「便宜」，否则经济系统会塌。**
	#
	# 这条守着它。原文说的是「每 1% 战力的成本低于抽卡」，但那个比值依赖
	# 抽卡在当时的边际收益，没法写成一个静态断言。**能写成断言的是它的后果**：
	# 一个会算账的玩家真的会去买。买成 0 就等于金币坑不存在，
	# 而 §07 的「经济位 = 战力空位」和 §06 的「羁绊 ↔ 金币」都建立在金币有价值上。
	#
	# 涨价、削弱成品加成、或者哪天把抽卡改强了，都会让这条红。
	var parts: int = 0
	for seed_value: int in SEEDS:
		parts += _run_with(0, seed_value).final_equip_parts
	var mean: float = float(parts) / float(SEEDS.size())
	assert_gt(mean, 5.0, "会算账的玩家整局应买到足够多的配件，装备才算得上金币坑")

	# 另一头也要守：坑不能在局中就被填满，否则后期金币又没去处。
	# 满装整队需要 出战席 × 3 件 × 3 配件 = 90 个。
	var cfg := PBSimConfig.new()
	var full: int = cfg.deploy_slots_max * cfg.equip_items_per_unit * cfg.equip_parts_per_item
	assert_lt(mean, float(full) * 0.7, "装备也不该便宜到局中就装满 —— 那样后期金币又没处去了")


func test_it_is_not_worse_than_the_hand_written_priority() -> void:
	# 「会算账」如果打不过写死的优先级，说明估值口径有问题，
	# 那这把尺子量出来的价格结论也就不能信。
	var rational_total: int = 0
	var balanced_total: int = 0
	for seed_value: int in SEEDS:
		var cfg := PBSimConfig.new()
		rational_total += PBRunSim.run(cfg, PBStratRational.new(), seed_value).wave_reached
		balanced_total += PBRunSim.run(cfg, PBStratBalanced.new(), seed_value).wave_reached
	assert_gt(rational_total, balanced_total, "按边际收益花钱应当不差于写死的花钱顺序")


func test_gacha_is_worth_less_once_the_bench_is_full_of_good_cards() -> void:
	# 抽卡的边际价值必须随卡池变好而衰减 —— §10 的「装备是后期金币的主要去处」
	# 整个建立在这条曲线上。不衰减的话拐点永远不出现，装备定多少钱都没人买。
	var cfg := PBSimConfig.new()
	var strategy := PBStratRational.new()

	var empty := PBRunSim.new_state(cfg)
	empty.add_unit(PBUnit.new(PBElement.Type.FIRE, PBUnit.Rarity.R))
	var early: float = strategy._gacha_gain(empty, cfg)

	var stacked := PBRunSim.new_state(cfg)
	stacked.tech_pop = cfg.tech_pop_max
	for element: int in PBElement.Type.size():
		for variant: int in cfg.characters_per_bucket:
			stacked.add_unit(PBUnit.new(element as PBElement.Type, PBUnit.Rarity.USR, variant))
	var late: float = strategy._gacha_gain(stacked, cfg)

	assert_gt(early, late, "板凳全是 USR 之后，再抽一张的边际价值应显著低于开局")


func test_duplicate_cards_are_valued_below_new_ones() -> void:
	# 卡池只有 48 张（§08），后期四分之三的抽卡是重复卡，只能加星。
	# 把每一抽都当新卡会系统性高估后期抽卡 —— 而后期正是
	# 「该继续抽还是该转装备」的分界区，偏差刚好落在结论上。
	var cfg := PBSimConfig.new()
	var strategy := PBStratRational.new()

	# 直接量估值函数本身，门槛固定为 0，这样两边只差「卡池占掉了多少格」——
	# 拿两个完整局面去比会把「队伍强弱」混进来，那条差异不是这里要测的东西。
	var virgin := PBRunSim.new_state(cfg)
	var owned := PBRunSim.new_state(cfg)
	for rarity: int in cfg.rarity_power.size():
		for element: int in PBElement.Type.size():
			for variant: int in cfg.characters_per_bucket:
				owned.add_unit(
					PBUnit.new(element as PBElement.Type, rarity as PBUnit.Rarity, variant)
				)

	var fresh: float = strategy._expected_surplus(PBElement.Type.FIRE, 0.0, virgin, cfg)
	var dupes: float = strategy._expected_surplus(PBElement.Type.FIRE, 0.0, owned, cfg)
	assert_gt(fresh, 0.0, "空卡池时每一抽都是新卡，期望收益应为正")
	assert_lt(dupes, fresh * 0.2, "卡池抽满之后每一抽都是重复卡，收益应低一个数量级")


func test_bond_prediction_matches_the_real_formula() -> void:
	# 「再抽一张值多少」有一部分来自羁绊。预测用的公式要是和结算用的不是同一份，
	# 偏差只会表现为「模拟玩家略微不理性」，不报任何错。
	var cfg := PBSimConfig.new()
	var state := PBRunSim.new_state(cfg)
	for i: int in 5:
		state.add_unit(PBUnit.new(PBElement.Type.FIRE, PBUnit.Rarity.R, i))
	assert_eq(state.bond_mult_for(state.roster.size(), cfg), state.bond_mult(cfg), "同一个人数应给出同一个倍率")
	assert_gt(state.bond_mult_for(6, cfg), state.bond_mult(cfg), "板凳没坐满时多一张卡应该多一份羁绊")


func test_it_never_overspends() -> void:
	# 比价逻辑里每个分支都要先判断买不买得起。漏一处就会出现负金币，
	# 而负金币在统计里只表现为「这个流派特别强」。
	# 开局金币是直接塞进 state.gold 的，不走 earn()，所以要单独加回来。
	var budget: int = PBSimConfig.new().starting_gold
	for seed_value: int in SEEDS:
		var result := _run_with(200, seed_value)
		assert_gte(result.gold_earned + budget, result.gold_spent, "花掉的钱不该超过赚到的加开局给的")


func test_the_economy_slot_is_not_a_trap() -> void:
	# **§07 改写后的验收：角都不能是陷阱。**
	#
	# 原来的常数 85 就是个陷阱 —— 一个会算账的玩家选了它反而更差
	# （43.0 → 42.1 波）。因为波次奖金和任务奖励都随波次涨，只有它不涨，
	# 而它占掉的那个出战位越到后期越值钱。
	#
	# 对照组把角都收益调成 0，等价于「没有这张卡」。有它不该比没它差。
	var with_slot: int = 0
	var without: int = 0
	for seed_value: int in [20260827, 4242, 991]:
		var live := PBSimConfig.new()
		with_slot += PBRunSim.run(live, PBStratRational.new(), seed_value).wave_reached
		var muted := PBSimConfig.new()
		muted.kakuzu_base = 0.0
		muted.kakuzu_rate = 0.0
		without += PBRunSim.run(muted, PBStratRational.new(), seed_value).wave_reached
	assert_gte(with_slot, without, "上角都不该让会算账的玩家变差 —— 那就是把它做成了陷阱")


func test_the_economy_slot_does_not_dominate() -> void:
	# 另一头：§07 明确警告「最优解会收敛成开局无脑铺经济，整个前期决策消失」。
	# 判据是角都占总收入的比例 —— 实测 45+24n 会到 44%，那已经越线了。
	var cfg := PBSimConfig.new()
	var share: float = 0.0
	for seed_value: int in [20260827, 4242, 991]:
		share += PBRunSim.run(cfg, PBStratRational.new(), seed_value).gold_share(&"kakuzu")
	assert_lt(share / 3.0, 0.35, "角都占收入超过 35% 就退化成「无脑铺经济」了")
