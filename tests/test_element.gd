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

## 原版矩阵的行列顺序。
const MATRIX_ORDER: Array[int] = [
	PBElement.Type.FIRE,
	PBElement.Type.WIND,
	PBElement.Type.THUNDER,
	PBElement.Type.EARTH,
	PBElement.Type.WATER,
	PBElement.Type.PHYSICAL,
	PBElement.Type.SAGE,
]

## 原版矩阵，行 = 攻方、列 = 守方，顺序同 [constant MATRIX_ORDER]。
##
## **这张表是从地图文件里解出来的，不是我们拍的**
## （`war3mapMisc.txt` 的 `DamageBonus*`，见
## `Docs/原版数据_忍法战场v1.5.80.md` §2.3）。逐格钉住它的理由是：
## 倍率错一格不会让任何别的测试变红，只会让某一对属性的博弈悄悄失效。
const MATRIX: Array = [
	[0.50, 2.00, 0.75, 1.00, 0.50, 1.00, 0.50],  # 火
	[0.50, 0.50, 2.00, 0.75, 1.00, 1.00, 0.50],  # 风
	[1.00, 0.50, 0.50, 2.00, 0.75, 1.00, 0.50],  # 雷
	[0.75, 1.00, 0.50, 0.50, 2.00, 1.00, 0.50],  # 土
	[2.00, 0.75, 1.00, 0.50, 0.50, 1.00, 0.50],  # 水
	[1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.50],  # 物理
	[2.00, 2.00, 2.00, 2.00, 2.00, 2.00, 1.50],  # 仙
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


func test_same_element_is_punished_not_merely_unhelpful() -> void:
	# **M12-a 把这条整个反了过来。** 在那之前断的是「同属性对撞应无加成」，
	# 而原版矩阵里同系那一格是 0.50 —— 带一个和本波同系的忍者不是
	# 「白带」，是**主动做错**，和被克吃一样的惩罚。
	#
	# 这一档并进 WEAK 而不是自立门户，理由见 [enum PBElement.Relation]。
	var cfg := PBSimConfig.new()
	for element: int in ELEMENTS:
		assert_eq(
			PBElement.relation(element, element), PBElement.Relation.WEAK, "同属性对撞在原版是 0.50，不是无加成"
		)
	assert_eq(cfg.damage_multiplier(PBElement.Relation.WEAK), 0.50, "同系与被克共用 0.50")


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
	assert_eq(cfg.damage_multiplier(PBElement.Relation.COUNTER), 2.00, "克制 2.00")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.WEAK), 0.50, "被克与同系 0.50")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.NEUTRAL), 1.00, "隔两个 1.00")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.DISTANT), 0.75, "隔一个 0.75")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.PHYSICAL), 1.00, "物理 1.00")
	assert_eq(cfg.damage_multiplier(PBElement.Relation.SAGE_MIRROR), 1.50, "仙打仙 1.50")


func test_physical_multiplier_stays_below_the_danger_line() -> void:
	# §03 的明文警告：MULT_PHYSICAL 调到 1.15 以上，堆物理躺赢成为最优解，
	# 属性系统当场作废。这条断言的作用是让「顺手调一下试试」变成一次红色测试，
	# 而不是三个月后才发现构筑全部收敛。
	#
	# **M12-a 把下界从「> 1.0」改成「== 无关属性」。** 在那之前物理是一个
	# 高 5% 的保底补丁；对齐原版之后它恰好等于中立，价值改由
	# 「对每一系都不会选错」提供 —— 而同一步把同系压到了 0.50，
	# 那才是物理队真正的收益来源。
	var cfg := PBSimConfig.new()
	assert_lt(cfg.mult_physical, 1.15, "MULT_PHYSICAL ≥ 1.15 会让物理纯队成为最优解（§03）")
	assert_eq(cfg.mult_physical, cfg.mult_neutral, "物理是中立位，不是加成位")
	assert_lt(cfg.mult_physical, cfg.mult_counter, "物理必须显著低于克制，否则没人配属性")


func test_the_whole_matrix_matches_the_original_map() -> void:
	var cfg := PBSimConfig.new()
	for row: int in MATRIX_ORDER.size():
		for col: int in MATRIX_ORDER.size():
			var attacker: int = MATRIX_ORDER[row]
			var defender: int = MATRIX_ORDER[col]
			var got: float = cfg.damage_multiplier(PBElement.relation(attacker, defender))
			assert_almost_eq(
				got,
				float(MATRIX[row][col]),
				0.0001,
				"攻%d 打 防%d 应为 %.2f" % [attacker, defender, MATRIX[row][col]]
			)


func test_ring_multipliers_are_a_function_of_distance() -> void:
	# 五系那 25 组不是随手填的，是环距的纯函数。写成断言之后，
	# 有人为了「让水强一点」单独改一格，这里立刻红 —— 而只改一格
	# 会让环失去对称性，那正是 §03 最不能出的错。
	var cfg := PBSimConfig.new()
	var want: Array[float] = [0.50, 2.00, 0.75, 1.00, 0.50]
	for attacker: int in ELEMENTS:
		for defender: int in ELEMENTS:
			var dist: int = PBElement.ring_distance(attacker, defender)
			assert_between(dist, 0, 4, "五系之间的环距应在 0–4")
			assert_almost_eq(
				cfg.damage_multiplier(PBElement.relation(attacker, defender)),
				want[dist],
				0.0001,
				"环距 %d 的倍率应为 %.2f" % [dist, want[dist]]
			)


func test_sage_beats_everything_and_is_halved_by_everything() -> void:
	# 仙是物理的反面：物理对谁都一样，仙对谁都占优。
	# 原版把「攻仙」和「防仙」拆开发给不同角色（同时拿到两半的只有
	# 已被删掉的 USR 神卡），所以这两条要分别验。
	for element: int in PBElement.PICKABLE:
		assert_eq(
			PBElement.relation(PBElement.Type.SAGE, element),
			PBElement.Relation.COUNTER,
			"仙打任何常规属性都应吃满克制"
		)
		assert_eq(
			PBElement.relation(element, PBElement.Type.SAGE),
			PBElement.Relation.WEAK,
			"任何常规属性打仙都应减半"
		)
	assert_eq(
		PBElement.relation(PBElement.Type.SAGE, PBElement.Type.SAGE),
		PBElement.Relation.SAGE_MIRROR,
		"仙打仙自成一档"
	)


func test_sage_is_not_a_pickable_element() -> void:
	# 仙不进 [constant PBElement.PICKABLE]，所以合成卡池、波次属性里都不会有它。
	# 这条钉的是那份名单本身 —— 有人「顺手补全」把仙加进去的话，
	# 合成表会凭空多出一批克制一切的角色，而没有任何断言会因此变红。
	assert_false(PBElement.PICKABLE.has(PBElement.Type.SAGE), "仙不是可发牌的属性")
	assert_false(PBElement.RING.has(PBElement.Type.SAGE), "仙不在克制环上")
	assert_eq(PBElement.ring_distance(PBElement.Type.SAGE, PBElement.Type.FIRE), -1, "仙不上环")
	for element: int in PBElement.PICKABLE:
		assert_ne(PBElement.counter_of(element), PBElement.Type.SAGE, "counter_of 不该答仙")


func test_no_wave_and_no_synthetic_character_is_ever_sage() -> void:
	# 敌人那两张表（[constant PBEnemyPool.ELEMENT_SIDES] / `ELEMENT_NAMES`）
	# **故意没有仙这一格**，靠的就是这条前提。哪天真刷出一只仙系怪，
	# 它会安静地领到物理的皮，而两处都只是 `.get(…, 兜底)`。
	for element: int in PBWaveRules.WAVE_ELEMENTS:
		assert_ne(element, PBElement.Type.SAGE, "波次属性里不该出现仙")
	var table := PBCharacterTable.synthetic(1)
	for character: PBCharacter in table.all():
		assert_ne(character.element, PBElement.Type.SAGE, "合成卡池不该发出仙系角色")


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
	assert_eq(cfg.rarity_power.size(), PBUnit.Rarity.size(), "战力阶梯要和稀有度档数一样长")
	for i: int in range(1, cfg.rarity_power.size()):
		var step: float = cfg.rarity_power[i] / cfg.rarity_power[i - 1]
		assert_gt(step, 1.0, "高稀有度不该比低稀有度弱")
		assert_lt(step, 1.45, "稀有度阶梯 ≥1.45 会让「升一档」替代「换克制系」，属性系统失效")

	# 反过来也要守：顶档若与 R 差不多，抽卡在数值上就没意义了，
	# §08 的「30 波后爆种」体感会消失。
	#
	# **M10-a 砍成三档之后这个下界从 1.8 降到 1.6**：少乘一档，顶档从 2.2
	# 掉到 1.69。它仍然踩在「抽到高稀有度是明显升级」这条线上，但余量薄了 ——
	# 要补回去只能提步长，而上面那条 1.45 的上界正好挡着。**两条一起看就是
	# 「三档 + ×1.30」已经把这个空间用满了**，再要就得动数值，归数值回归。
	var top_to_bottom: float = cfg.rarity_power[cfg.rarity_power.size() - 1] / cfg.rarity_power[0]
	assert_gt(top_to_bottom, 1.6, "顶档对 R 的差距太小，抽到高稀有度就没有升级感了")
