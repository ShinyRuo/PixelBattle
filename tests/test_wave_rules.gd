extends GutTest
## [PBWaveRules] 的波次生成测试。对应施工策划案 §04。

## §04 的轮转表原样搬过来：波次 mod 5 → 敌方属性 / 需要的输出 / 废掉的输出。
## 三列一起验的理由：属性轮转、克星查询、被克判定是三段独立代码，
## 单验任何一段都可能「自洽地全错」。用策划案的表当外部真值才拦得住。
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
		"mod": 0,
		"enemy": PBElement.Type.WIND,
		"want": PBElement.Type.FIRE,
		"dead": PBElement.Type.THUNDER
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
	for wave: int in range(1, 16):
		var row: Dictionary = ROTATION[(wave - 1) % 5]
		assert_eq(
			PBWaveRules.element_of(wave), row["enemy"], "第 %d 波敌方属性应为 %s" % [wave, row["mod"]]
		)
		assert_eq(PBWaveRules.counter_element_of(wave), row["want"], "第 %d 波需要的输出属性对不上" % wave)
		assert_eq(
			PBElement.relation(row["dead"], row["enemy"]),
			PBElement.Relation.WEAK,
			"第 %d 波应废掉 %s 系输出" % [wave, row["dead"]]
		)


func test_full_five_element_coverage_needed_per_cycle() -> void:
	# §04 的核心主张：每 5 波要求的输出属性恰好覆盖全部五系，
	# 所以玩家不可能靠单系阵容混过一个完整周期。
	var needed := {}
	for wave: int in range(1, 6):
		needed[PBWaveRules.counter_element_of(wave)] = true
	assert_eq(needed.size(), 5, "一个 5 波周期应要求全部五系输出，否则阵容会固化")


func test_growth_scale_starts_at_one_and_compounds() -> void:
	assert_eq(PBWaveRules.growth_scale(1, _cfg), 1.0, "第 1 波成长倍数应为 1.0")
	assert_almost_eq(PBWaveRules.growth_scale(2, _cfg), 1.125, 1e-9, "第 2 波应为 GROWTH^1")
	assert_almost_eq(PBWaveRules.growth_scale(9, _cfg), pow(1.125, 8), 1e-9, "第 9 波应为 GROWTH^8")


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
