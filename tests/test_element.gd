extends GutTest
## [PBElement] 的克制环测试。对应施工策划案 §03。
##
## §03 声明克制环是「全局地基，不可改」。所以这里测的不是「代码有没有实现我写的表」，
## 而是「这张表在结构上还是不是一个合法的克制环」—— 单环、无自克、关系对称。
## 有人手滑把两条边指向同一个属性，环会退化成链，五系覆盖的策略瞬间失效，
## 而这种错误在游戏里表现为「某个属性莫名其妙没人克」，极难从现象反推。

const ELEMENTS: Array[int] = [
	PBElement.Type.FIRE,
	PBElement.Type.WIND,
	PBElement.Type.THUNDER,
	PBElement.Type.EARTH,
	PBElement.Type.WATER,
]


func test_ring_covers_all_five_elements() -> void:
	assert_eq(PBElement.RING.size(), 5, "克制环应恰好包含五个属性")
	assert_eq(PBElement.COUNTERS.size(), 5, "每个属性都该克制恰好一个属性")
	for element: int in ELEMENTS:
		assert_true(PBElement.COUNTERS.has(element), "属性 %d 缺少克制目标" % element)


func test_ring_is_a_single_cycle() -> void:
	# 从火出发一路跟着克制关系走，必须恰好走满五步才回到火。
	# 少于五步说明环断成了小环，走不回来说明它根本不是环。
	var current: int = PBElement.Type.FIRE
	var visited: Array[int] = []
	for _step: int in 5:
		assert_false(visited.has(current), "克制环上出现重复属性，说明环退化了")
		visited.append(current)
		current = PBElement.COUNTERS[current]
	assert_eq(current, PBElement.Type.FIRE, "走满五步应回到起点，克制环必须是单环")
	assert_eq(visited.size(), 5, "单环应覆盖全部五个属性")


func test_no_element_counters_itself() -> void:
	for element: int in ELEMENTS:
		assert_ne(PBElement.COUNTERS[element], element, "属性 %d 不应克制自己" % element)


func test_counter_and_weak_are_symmetric() -> void:
	# A 克 B，则 B 必然被 A 克。这两个判定走不同分支，可能各自写错。
	for attacker: int in ELEMENTS:
		var defender: int = PBElement.COUNTERS[attacker]
		assert_eq(
			PBElement.relation(attacker, defender),
			PBElement.Relation.COUNTER,
			"%d 应克制 %d" % [attacker, defender]
		)
		assert_eq(
			PBElement.relation(defender, attacker),
			PBElement.Relation.WEAK,
			"%d 打 %d 应为被克" % [defender, attacker]
		)


func test_same_element_is_neutral() -> void:
	for element: int in ELEMENTS:
		assert_eq(PBElement.relation(element, element), PBElement.Relation.NEUTRAL, "同属性对撞应无加成")


func test_each_element_has_exactly_one_counter_and_one_victim() -> void:
	# 「覆盖度」UI 靠的就是每个属性有且只有一个克星。有两个克星，
	# 玩家凑五系的压力就少一档；一个都没有，那一波无解。
	for defender: int in ELEMENTS:
		var counters: Array[int] = []
		for attacker: int in ELEMENTS:
			if PBElement.relation(attacker, defender) == PBElement.Relation.COUNTER:
				counters.append(attacker)
		assert_eq(counters.size(), 1, "属性 %d 应恰好有一个克星" % defender)
		assert_eq(PBElement.counter_of(defender), counters[0], "counter_of 应返回那个克星")


func test_physical_never_participates_in_the_ring() -> void:
	# 物理是保底补丁，进了克制环整个 §03 就塌了。
	for element: int in ELEMENTS:
		assert_eq(
			PBElement.relation(PBElement.Type.PHYSICAL, element),
			PBElement.Relation.PHYSICAL,
			"物理打任何属性都应是 PHYSICAL 关系"
		)
		assert_eq(
			PBElement.relation(element, PBElement.Type.PHYSICAL),
			PBElement.Relation.NEUTRAL,
			"任何属性打物理都不应有克制加成"
		)
	assert_false(PBElement.RING.has(PBElement.Type.PHYSICAL), "物理不应出现在克制环上")


func test_default_multipliers_match_spec() -> void:
	var cfg := PBSimConfig.new()
	assert_eq(cfg.damage_multiplier(PBElement.Relation.COUNTER), 2.00, "§03 克制默认 2.00")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.WEAK), 0.50, "§03 被克默认 0.50")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.NEUTRAL), 1.00, "§03 无关默认 1.00")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.PHYSICAL), 1.05, "§03 物理默认 1.05")


func test_physical_multiplier_stays_below_the_danger_line() -> void:
	# §03 的明文警告：MULT_PHYSICAL 调到 1.15 以上，堆物理躺赢成为最优解，
	# 属性系统当场作废。这条断言的作用是让「顺手调一下试试」变成一次红色测试，
	# 而不是三个月后才发现构筑全部收敛。
	var cfg := PBSimConfig.new()
	assert_lt(cfg.mult_physical, 1.15, "MULT_PHYSICAL ≥ 1.15 会让物理纯队成为最优解（§03）")
	assert_gt(cfg.mult_physical, 1.0, "物理低于 1.0 就不再是保底补丁了")
	assert_lt(cfg.mult_physical, cfg.mult_counter, "物理必须显著低于克制，否则没人配属性")


func test_rarity_ladder_stays_flatter_than_the_counter_bonus() -> void:
	# 和上面那条是同一类防线，守的是另一个方向。
	#
	# 稀有度阶梯和克制倍率是**同一种货币**（都是 DPS 倍率），所以能互相替代。
	# 阶梯一旦逼近克制倍率，「升一档稀有度」就等于「换上克制系」，
	# 玩家没有理由再为属性调整阵容 —— §03 整套设计被架空，而且不会报任何错，
	# 只会表现为「大家都在堆最高稀有度」。
	#
	# 初版阶梯是 ×1.84（对克制的 ×2.0），M-1 实测换人只值 1.25 倍战力。
	# 压到 ×1.30 后升到 1.39 倍。1.45 以上是完全没用的平台，所以卡在 1.45。
	var cfg := PBSimConfig.new()
	assert_eq(cfg.rarity_power.size(), 4, "稀有度应有 R/SR/SSR/USR 四档")
	for i: int in range(1, cfg.rarity_power.size()):
		var step: float = cfg.rarity_power[i] / cfg.rarity_power[i - 1]
		assert_gt(step, 1.0, "高稀有度不该比低稀有度弱")
		assert_lt(step, 1.45, "稀有度阶梯 ≥1.45 会让「升一档」替代「换克制系」，属性系统失效")

	# 反过来也要守：USR 若与 R 差不多，抽卡在数值上就没意义了，
	# §08 的「30 波后爆种」体感会消失。
	var top_to_bottom: float = cfg.rarity_power[3] / cfg.rarity_power[0]
	assert_gt(top_to_bottom, 1.8, "USR 对 R 的差距太小，抽到高稀有度就没有升级感了")
