extends GutTest
## [PBWaveRules] 的波次生成测试。对应施工策划案 §04。

## §04 的轮转表原样搬过来：波次 mod 6 → 敌方属性 / 需要的输出 / 废掉的输出。
## 三列一起验的理由：属性轮转、克星查询、被克判定是三段独立代码，
## 单验任何一段都可能「自洽地全错」。用策划案的表当外部真值才拦得住。
##
## **物理那一行只有两列**（M9-f）：它不废掉任何一系，见
## [method test_the_physical_wave_has_no_counter_and_wastes_nobody]。
const ROTATION := [
	{
		"mod": 1,
		"enemy": PBElement.Type.FIRE,
		"want": PBElement.Type.WATER,
		"dead": PBElement.Type.WIND
	},
	{
		"mod": 2,
		"enemy": PBElement.Type.THUNDER,
		"want": PBElement.Type.WIND,
		"dead": PBElement.Type.EARTH
	},
	{
		"mod": 3,
		"enemy": PBElement.Type.WATER,
		"want": PBElement.Type.EARTH,
		"dead": PBElement.Type.FIRE
	},
	{
		"mod": 4,
		"enemy": PBElement.Type.EARTH,
		"want": PBElement.Type.THUNDER,
		"dead": PBElement.Type.WATER
	},
	{
		"mod": 5,
		"enemy": PBElement.Type.WIND,
		"want": PBElement.Type.FIRE,
		"dead": PBElement.Type.THUNDER
	},
	# 物理波：没有克星（[method PBElement.counter_of] 的兜底分支答它自己），
	# 也不废掉任何一系 —— 所以这一行没有 `dead`。
	{
		"mod": 0,
		"enemy": PBElement.Type.PHYSICAL,
		"want": PBElement.Type.PHYSICAL,
	},
]

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345


func test_wave_element_rotation_matches_spec_table() -> void:
	# 连查 3 个周期，确保轮转真的在循环而不是只对了第一圈。
	# **按数组长度取模，不写死** —— M9-f 把周期从 5 改成了 6，
	# 写死的那一版会在物理进来的那天整体错位一格。
	var cycle: int = PBWaveRules.WAVE_ELEMENTS.size()
	assert_eq(ROTATION.size(), cycle, "轮转表和 WAVE_ELEMENTS 的长度必须一致")
	for wave: int in range(1, cycle * 3 + 1):
		var row: Dictionary = ROTATION[(wave - 1) % cycle]
		assert_eq(
			PBWaveRules.element_of(wave), row["enemy"], "第 %d 波敌方属性应为 %s" % [wave, row["mod"]]
		)
		var want := PBElement.counter_of(PBWaveRules.element_of(wave))
		assert_eq(want, row["want"], "第 %d 波需要的输出属性对不上" % wave)
		if not row.has("dead"):
			continue
		assert_eq(
			PBElement.relation(row["dead"], row["enemy"]),
			PBElement.Relation.WEAK,
			"第 %d 波应废掉 %s 系输出" % [wave, row["dead"]]
		)


## 物理波是克制系统的空档（M9-f，玩家定的）。
##
## 单独一条而不是塞进上面那张表：表里第三列问的是「哪一系被废掉」，
## 而物理波的答案是**一个都没有** —— 那不是表里的一个值，是这一行没有那一列。
func test_the_physical_wave_has_no_counter_and_wastes_nobody() -> void:
	assert_true(PBWaveRules.WAVE_ELEMENTS.has(int(PBElement.Type.PHYSICAL)), "物理应该在轮转里（M9-f）")
	for attacker: int in PBElement.RING:
		assert_eq(
			PBElement.relation(attacker as PBElement.Type, PBElement.Type.PHYSICAL),
			PBElement.Relation.NEUTRAL,
			"物理波不该克制也不该被克制任何一系"
		)
	assert_eq(
		PBElement.relation(PBElement.Type.PHYSICAL, PBElement.Type.PHYSICAL),
		PBElement.Relation.PHYSICAL,
		"物理忍者打物理波仍然走物理那一档 —— 那是他在这一波唯一的优势"
	)


func test_full_five_element_coverage_needed_per_cycle() -> void:
	# §04 的核心主张：一个完整周期要求的输出属性恰好覆盖全部五系，
	# 所以玩家不可能靠单系阵容混过一个周期。
	#
	# **M9-f 之后周期是 6 波，多出来的那一格是物理**（物理波的「克星」是物理
	# 自己）—— 所以这里断言的是「五系一个不少，外加物理那一格」，
	# 而不是把答案数改成 6 就算完：只数个数的话，某一系掉出轮转
	# 而物理重复两次也照样是 6。
	var needed := {}
	for wave: int in range(1, PBWaveRules.WAVE_ELEMENTS.size() + 1):
		needed[PBElement.counter_of(PBWaveRules.element_of(wave))] = true
	for element: int in PBElement.RING:
		assert_true(needed.has(element), "一个周期应要求全部五系输出，否则阵容会固化")
	assert_true(needed.has(int(PBElement.Type.PHYSICAL)), "物理波要求的是物理系输出")
	assert_eq(needed.size(), PBElement.RING.size() + 1, "一个周期要求的输出属性应恰好是五系 + 物理")


func test_growth_scale_starts_at_one_and_compounds() -> void:
	# 断言的是**指数关系**，不是 GROWTH 当前取值 —— 那是个会被反复重锚的调参旋钮
	# （已经从 1.125 改到 1.10 一次），把它的值写死在这里只会让每次调参都误报一次红。
	assert_eq(PBWaveRules.growth_scale(1, _cfg), 1.0, "第 1 波成长倍数应为 1.0")
	assert_almost_eq(PBWaveRules.growth_scale(2, _cfg), _cfg.growth, 1e-9, "第 2 波应为 GROWTH^1")
	assert_almost_eq(
		PBWaveRules.growth_scale(9, _cfg), pow(_cfg.growth, 8), 1e-9, "第 9 波应为 GROWTH^8"
	)
	# 但取值落在 §04 声明的区间里这件事要守住 —— 跑出区间说明有人绕过了决策流程。
	assert_between(_cfg.growth, 1.10, 1.15, "GROWTH 应落在 §04 声明的 1.10–1.15 区间内")


func test_first_wave_matches_base_values() -> void:
	# 第 1 波必须原样等于 BASE 值。差一位（用 n 而不是 n-1 做指数）在这里立刻暴露。
	var wave := PBWaveRules.build(1, _cfg, _rng)
	assert_eq(wave.atk_each, _cfg.atk_base, "第 1 波攻击应等于 ATK_BASE")
	assert_eq(wave.index, 1, "波次序号应从 1 开始")


func test_reward_is_linear_not_exponential() -> void:
	# §04 特意让奖金走线性。跟着血量的指数曲线走，后期金币溢出，抽卡不再是决策。
	# 等距取样才能比增量：跨 9 波和跨 10 波的差本来就不该相等。
	var first := PBWaveRules.build(1, _cfg, _rng).reward_gold
	var eleventh := PBWaveRules.build(11, _cfg, _rng).reward_gold
	var twenty_first := PBWaveRules.build(21, _cfg, _rng).reward_gold
	assert_eq(eleventh - first, twenty_first - eleventh, "等距波次的奖金增量应恒定，说明是线性的")
	assert_eq(first, _cfg.gold_base + _cfg.gold_rate, "第 1 波奖金 = GOLD_BASE + GOLD_RATE")

	# 同时验它没跟着血量的指数曲线跑：第 40 波血量涨了几百倍，奖金只该涨几倍。
	var fortieth := PBWaveRules.build(40, _cfg, _rng)
	var hp_ratio := fortieth.hp_each / PBWaveRules.build(1, _cfg, _rng).hp_each
	var gold_ratio := float(fortieth.reward_gold) / float(first)
	assert_gt(hp_ratio, gold_ratio * 5.0, "血量增速应远高于奖金增速，否则后期金币会溢出")


func test_boss_waves_land_on_the_spec_cadence() -> void:
	for wave: int in [10, 20, 30, 40, 60, 70]:
		var built := PBWaveRules.build(wave, _cfg, _rng)
		assert_eq(built.shape, PBWave.Shape.BOSS, "第 %d 波应为 BOSS 波" % wave)
		assert_true(built.is_boss(), "BOSS 波的 is_boss 应为真")
	for wave: int in [50, 100]:
		var built := PBWaveRules.build(wave, _cfg, _rng)
		assert_eq(built.shape, PBWave.Shape.MEGA_BOSS, "第 %d 波应为大 BOSS（优先于普通 BOSS）" % wave)


func test_non_boss_waves_never_roll_boss_shape() -> void:
	for wave: int in range(1, 50):
		if wave % 10 == 0:
			continue
		var built := PBWaveRules.build(wave, _cfg, _rng)
		assert_false(built.is_boss(), "第 %d 波不该掷出 BOSS 波型" % wave)


func test_count_is_capped_and_never_empty() -> void:
	# 上限：§04 要求任意波次同屏数量不超过 COUNT_CAP，且双端逻辑数量完全一致。
	# 下限：精英波 ×0.3 在低波次会算出不到 1 的数，取整后会变成空波。
	for wave: int in range(1, 200):
		for shape: PBWave.Shape in [PBWave.Shape.NORMAL, PBWave.Shape.SWARM, PBWave.Shape.ELITE]:
			var count := PBWaveRules.count_of(wave, _cfg, shape)
			assert_between(count, 1, _cfg.count_cap, "第 %d 波数量应落在 [1, COUNT_CAP]" % wave)


func test_swarm_is_many_and_thin_elite_is_few_and_thick() -> void:
	# 波型存在的全部意义就是让 AOE 和单体输出各有高光。
	# 两者的数量/血量关系一旦反了，构筑立刻收敛回「AOE 永远最优」。
	var swarm_count := PBWaveRules.count_of(30, _cfg, PBWave.Shape.SWARM)
	var normal_count := PBWaveRules.count_of(30, _cfg, PBWave.Shape.NORMAL)
	var elite_count := PBWaveRules.count_of(30, _cfg, PBWave.Shape.ELITE)
	assert_gt(swarm_count, normal_count, "潮水波数量应多于常规波")
	assert_lt(elite_count, normal_count, "精英波数量应少于常规波")
	assert_lt(_cfg.shape_hp_mult(PBWave.Shape.SWARM), 1.0, "潮水波单体血量应更薄")
	assert_gt(_cfg.shape_hp_mult(PBWave.Shape.ELITE), 1.0, "精英波单体血量应更厚")


func test_shape_roll_is_deterministic_for_a_given_seed() -> void:
	# 确定性是 §12 的地基。同种子两次生成必须逐波相同。
	var shapes_a: Array[int] = []
	var shapes_b: Array[int] = []
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 999
	rng_b.seed = 999
	for wave: int in range(1, 40):
		shapes_a.append(PBWaveRules.build(wave, _cfg, rng_a).shape)
		shapes_b.append(PBWaveRules.build(wave, _cfg, rng_b).shape)
	assert_eq(shapes_a, shapes_b, "同种子应生成完全相同的波型序列")


func test_wave_modifiers_field_exists_but_stays_empty_in_m1() -> void:
	# §04 要求 M-1 就预留这个字段：它会进存档结构，后加字段要做迁移，现在加是零成本。
	var wave := PBWaveRules.build(60, _cfg, _rng)
	assert_eq(wave.modifiers, [] as Array[StringName], "M-1 不产生波次词条，词条池设计在 M5")
