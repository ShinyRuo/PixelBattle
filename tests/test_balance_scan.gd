extends GutTest
## **慢档：靠整局扫描才能验的配平结论。** 默认不跑，`.\scripts\check.ps1 -Deep` 才跑。
##
## ## 为什么单独分一档
##
## 这里每条都要跑完整的局，而 `rational` 一局要 **2.1 秒** —— 它每花一笔钱就
## 重估一遍全部候选项（[method PBStratRational._buy_best] 里六次 `mean_dps`，
## 每次五个属性各排一遍全仓），后期一波要买几十笔。
## `balanced` 那种写死优先级的流派只要 93 毫秒，**差 22 倍**。
##
## 分档前整套测试 98 秒，其中 83 秒在这些用例里。**改一行代码等 98 秒，
## 人就会开始不跑自检** —— 那比测试慢危险得多。
##
## ## 判据：进这里的是「贵 **且** 结论型」，不是「贵」
##
## 只按耗时分会把自洽性测试也扔进来（确定性、记账守恒、拆分路径对拍），
## 那些是**改代码就会红**的，必须每次都跑，再贵也留在快档。
##
## 这里的几条测的是**配平数值的结论**：装备定价、经济位不是陷阱也不支配、
## GROWTH 单调。它们会因为**调参**而红 —— 而调参正是眼下高频发生的事，
## 每次改 `PBSimConfig` 里一个数就等一分半钟没有道理。
##
## **所以什么时候必须跑 `-Deep`**：改了 [PBSimConfig] 的任何数值、
## 改了 [PBValuation] 的估值口径、动了角色表的属性/稀有度分布、里程碑验收。
## 日常改代码不用。
##
## ## 跳过是显式的，不是静默的
##
## 走 GUT 的 `should_skip_script()` 而不是把文件挪进不扫描的目录：
## GUT 在**实例化脚本之后**才判跳过，所以本文件的解析错误照样会在快档暴露，
## 报告里也会打出 `- [Script skipped]` 并计入 risky。
## 挪目录的话，这个文件哪天解析不过都没人知道 —— 那正是自检契约里
## 「测试静默消失」要防的东西。

## 打开慢档的环境变量。`check.ps1 -Deep` 负责设它。
const DEEP_ENV: String = "PB_DEEP"

const SEEDS: Array[int] = [20260827, 991, 4242, 70707, 13]

## 经济位那两条用的种子。
##
## **原来只有三个，那是个欠功率的仪器。** 它量的是一个约 1% 的配对差值，
## 而单局波次的种子间方差远大于 1% —— 三个种子测不出这个量级，
## 一直是靠运气绿的。M3-a 换战斗模型之后它翻了面（113 vs 118 波），
## 但同一个对比加到 12 个种子是 43.5 vs 43.1，**结论其实没变**。
##
## 十个种子把它变成一个真能用的仪器。代价是慢档再慢几十秒，
## 而慢档本来就是 opt-in 的（`-Deep`）—— 一个测不准的结论型断言比慢危险得多。
const SLOT_SEEDS: Array[int] = [20260827, 4242, 991, 70707, 13, 55, 8123, 4096, 31337, 606]

## 「经济位不是陷阱」允许的劣势带宽。
##
## 判据是**不得显著更差**，不是**一定不更差**：即使加到十个种子，
## 一个 ±1% 量级的配对差值仍然带着噪声，写成严格不等号等于要求运气。
## 2% 以内算噪声，超过 2% 才是「选了它真的更差」。
const SLOT_TOLERANCE: float = 0.98

var _cache: Dictionary = {}


## 返回类型**故意不标注**。父类 [method GutTest.should_skip_script] 声明的是
## `-> Variant`，而 GUT 逐个文件调 `warnings_manager.load_script_using_custom_warnings()`
## 重载脚本时，只要本文件不是目录里第一个被解析的，那次重载就会把这个显式
## `-> Variant` 判成「与父类签名不符」，整个文件 **解析失败**。
##
## 后果正是 §「自检契约」里那条要防的事：GUT 只打一行 WARNING 就跳过整个文件、
## 照样返回 0，用例数悄悄少一截。这个坑从这个文件建起就在，
## 只是它当时字典序排第一、前面没有别的文件先加载，一直没被触发 ——
## M3-a 新增的 `test_attacker.gd` 是第一个排在它前面的文件。
##
## 不标注等价于 Variant，签名比较因此走不到那条路径上。**别把它加回来。**
func should_skip_script():
	if OS.get_environment(DEEP_ENV) != "":
		return false
	return "慢档配平扫描 —— 用 .\\scripts\\check.ps1 -Deep 跑"


## 跑一局，**同参数只跑一次**。
##
## 模拟是确定性的（同种子必然同结果，`test_run_sim` 里那条锁着），
## 所以这个缓存是纯粹省时间，**不损失任何严谨性**。
##
## 省得不少：「默认配置 + rational」这一组在下面六条里被要了 21 次，
## 而不同的种子只有 5 个。
##
## ## 配置必须走 [method PBGameData.config]，不能是裸的 `PBSimConfig.new()`
##
## 裸构造拿到的是 M-1 的**合成卡池 + 替身羁绊曲线**，不是游戏真跑的那份数据。
## M2 把两张表都换成了 `data/` 下的真表，而这个文件没跟上 ——
## 于是整个慢档扫描一直在给一副游戏里不存在的牌下配平结论。
##
## 这不是理论风险，实测两边会给出**相反**的结论：同样十个种子，
## 「上经济位」在合成表下是 −2.35%（陷阱），在真表下是 +2.29%（不是陷阱）。
## §07 那条验收按前者会被判定成需要重新定价，而真游戏里它根本没坏。
func _run(
	seed_value: int, part_cost: int = 0, strategy_id: StringName = &"rational", mute_slot := false
) -> PBRunResult:
	var key: String = "%d|%d|%s|%s" % [seed_value, part_cost, strategy_id, mute_slot]
	if _cache.has(key):
		return _cache[key]
	var cfg := PBGameData.config()
	if part_cost > 0:
		cfg.equip_part_cost = part_cost
	if mute_slot:
		cfg.economy_slot_base = 0.0
		cfg.economy_slot_rate = 0.0
	var result := PBRunSim.run(cfg, PBStrategyRegistry.make(strategy_id), seed_value)
	_cache[key] = result
	return result


# ── §10 装备定价 ────────────────────────────────────────────────


func test_it_actually_responds_to_the_equipment_price() -> void:
	# **[PBStratRational] 存在的全部理由。**
	#
	# 其余流派的花钱顺序写死，`gacha_still_pays()` 看的是板凳坐没坐满，
	# 从头到尾没有任何判断读过 `equip_part_cost` —— 拿它们扫价格，
	# 扫出来的只是「剩下的钱能多买几个配件」，不是「玩家会不会改买装备」。
	# 用一个不看价格的玩家去校准价格，问出来的答案没有意义。
	var cheap: int = 0
	var expensive: int = 0
	for seed_value: int in SEEDS:
		cheap += _run(seed_value).final_equip_parts
		expensive += _run(seed_value, 1350).final_equip_parts
	assert_gt(cheap, 0, "按定好的价格应该真的会买装备")
	# 断言的是**比值**，不是「旧价下买 0 个」。
	# 定价那次扫描时旧价确实是 0，但 §07 把经济位改成随波次走之后玩家富了不少，
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
		parts += _run(seed_value).final_equip_parts
	var mean: float = float(parts) / float(SEEDS.size())
	assert_gt(mean, 5.0, "会算账的玩家整局应买到足够多的配件，装备才算得上金币坑")

	# 另一头也要守：坑不能在局中就被填满，否则后期金币又没去处。
	# 满装整队需要 出战席 × 3 件 × 3 配件 = 90 个。
	var cfg := PBSimConfig.new()
	var full: int = cfg.deploy_slots_max * cfg.equip_items_per_unit * cfg.equip_parts_per_item
	assert_lt(mean, float(full) * 0.7, "装备也不该便宜到局中就装满 —— 那样后期金币又没处去了")


# ── 估值口径本身准不准 ──────────────────────────────────────────


func test_it_is_not_worse_than_the_hand_written_priority() -> void:
	# 「会算账」如果打不过写死的优先级，说明估值口径有问题，
	# 那这把尺子量出来的价格结论也就不能信。
	var rational_total: int = 0
	var balanced_total: int = 0
	for seed_value: int in SEEDS:
		rational_total += _run(seed_value).wave_reached
		balanced_total += _run(seed_value, 0, &"balanced").wave_reached
	assert_gt(rational_total, balanced_total, "按边际收益花钱应当不差于写死的花钱顺序")


func test_it_never_overspends() -> void:
	# 比价逻辑里每个分支都要先判断买不买得起。漏一处就会出现负金币，
	# 而负金币在统计里只表现为「这个流派特别强」。
	# 开局金币是直接塞进 state.gold 的，不走 earn()，所以要单独加回来。
	var budget: int = PBSimConfig.new().starting_gold
	for seed_value: int in SEEDS:
		var result := _run(seed_value, 200)
		assert_gte(result.gold_earned + budget, result.gold_spent, "花掉的钱不该超过赚到的加开局给的")


# ── §07 经济位 ──────────────────────────────────────────────────


func test_the_economy_slot_is_not_a_trap() -> void:
	# **§07 改写后的验收：经济位不能是陷阱。**
	#
	# 原来的常数 85 就是个陷阱 —— 一个会算账的玩家选了它反而更差
	# （43.0 → 42.1 波）。因为波次奖金和任务奖励都随波次涨，只有它不涨，
	# 而它占掉的那个出战位越到后期越值钱。
	#
	# 对照组把经济位收益调成 0，等价于「没有这张卡」。有它不该**显著**比没它差。
	# 为什么是「显著」而不是「不得更差」，见 [constant SLOT_TOLERANCE]。
	var with_slot: int = 0
	var without: int = 0
	for seed_value: int in SLOT_SEEDS:
		with_slot += _run(seed_value).wave_reached
		without += _run(seed_value, 0, &"rational", true).wave_reached
	assert_gte(
		float(with_slot),
		float(without) * SLOT_TOLERANCE,
		(
			"上经济位不该让会算账的玩家变差 —— 那就是把它做成了陷阱（有 %d 波 / 无 %d 波）"
			% [with_slot, without]
		)
	)


func test_the_economy_slot_does_not_dominate() -> void:
	# 另一头：§07 明确警告「最优解会收敛成开局无脑铺经济，整个前期决策消失」。
	# 判据是经济位占总收入的比例 —— 实测 45+24n 会到 44%，那已经越线了。
	var share: float = 0.0
	for seed_value: int in SLOT_SEEDS:
		share += _run(seed_value).gold_share(&"economy_slot")
	assert_lt(share / float(SLOT_SEEDS.size()), 0.35, "经济位占收入超过 35% 就退化成「无脑铺经济」了")


# ── §04 难度曲线 ────────────────────────────────────────────────


func test_higher_growth_never_helps_the_player() -> void:
	# 单调性：GROWTH 是整条难度曲线的主控，调高只可能更难。
	# 用配对比较（同一批种子）消掉运气，再比中位数。
	#
	# 从 `test_run_sim.gd` 搬来的 —— 它一条就要跑 72 局。虽然用的是便宜的
	# `balanced`，但它测的是**参数的性质**而不是模型的自洽性，判据上属于这一档。
	var medians: Array[float] = []
	for growth: float in [1.10, 1.125, 1.15]:
		var reached: Array[int] = []
		for run_seed: int in range(1, 25):
			var cfg := PBSimConfig.new()
			cfg.growth = growth
			# 跑满 200 波纯属浪费 —— 这三档都在 60 波以内分出胜负。
			cfg.max_wave = 60
			reached.append(PBRunSim.run(cfg, PBStratBalanced.new(), run_seed).wave_reached)
		reached.sort()
		medians.append(float(reached[reached.size() / 2]))
	assert_lte(medians[1], medians[0], "GROWTH 1.125 不该比 1.10 更容易")
	assert_lte(medians[2], medians[1], "GROWTH 1.15 不该比 1.125 更容易")
