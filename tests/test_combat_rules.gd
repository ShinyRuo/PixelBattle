extends GutTest
## [PBCombatRules] 的排队模型测试，外加 [PBUnit] 的战力换算。
##
## 这里守的是模型的**边界行为**：DPS 为零、DPS 无穷大、刚好够、刚好不够。
## 解析式近似最容易在边界上出荒谬结果（负数时长、漏怪数超过总数），
## 而那种错误在几万局的统计里会被平均掉，看不出来。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 4242


func _wave(index: int = 1) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


func test_overwhelming_dps_clears_everything() -> void:
	var wave := _wave(1)
	var out := PBCombatRules.resolve(wave, 1e9, 0.0, _cfg)
	assert_true(out.cleared, "碾压级 DPS 应全清")
	assert_eq(out.kills, wave.count, "击杀数应等于总数")
	assert_eq(out.leaked, 0, "不应有漏怪")
	assert_eq(out.base_damage, 0.0, "全清时基地不该掉血")


func test_zero_dps_leaks_the_entire_wave() -> void:
	# 全员派去做任务、或阵容被克到近乎无伤，都会走到这一支。
	# 它是合法状态，不是除零错误。
	var wave := _wave(1)
	var out := PBCombatRules.resolve(wave, 0.0, 0.0, _cfg)
	assert_false(out.cleared, "零 DPS 不可能清波")
	assert_eq(out.leaked, wave.count, "应全部漏光")
	assert_eq(out.kills, 0, "不应有任何击杀")
	assert_gt(out.base_damage, 0.0, "全漏应该扣基地血")


func test_kills_plus_leaks_always_equals_the_wave_count() -> void:
	# 守恒律。一个敌人要么被杀要么漏过去，不该凭空多出来或消失。
	var wave := _wave(25)
	for dps: float in [0.0, 1.0, 50.0, 500.0, 5000.0, 1e6]:
		var out := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
		assert_eq(out.kills + out.leaked, wave.count, "DPS=%.0f 时击杀+漏怪应等于总数" % dps)


func test_more_dps_never_produces_more_leaks() -> void:
	# 单调性。DPS 越高漏得越少，中间不该有反转 —— 排队模型里
	# 「打快了反而漏更多」是典型的时钟推进写错的症状。
	var wave := _wave(30)
	var previous: int = wave.count + 1
	for dps: float in [10.0, 100.0, 400.0, 1200.0, 4000.0, 20000.0]:
		var out := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
		assert_lte(out.leaked, previous, "DPS 提高到 %.0f 后漏怪数不该反增" % dps)
		previous = out.leaked


func test_battle_duration_is_tick_aligned() -> void:
	# §14 铁律：定帧 20 tick/s。M-1 虽然不逐 tick 推进，时长也必须对齐到整 tick，
	# 这样 M0 换成真模拟时两边数字可以直接对照。
	var wave := _wave(17)
	for dps: float in [37.0, 411.0, 1234.5]:
		var out := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
		var in_ticks: float = out.battle_seconds * float(_cfg.tick_rate)
		assert_almost_eq(in_ticks, round(in_ticks), 1e-6, "战斗时长应落在整 tick 上")
		assert_eq(out.ticks, int(round(in_ticks)), "ticks 字段应与秒数一致")


func test_defense_tech_reduces_leak_damage() -> void:
	# §07：防御科技 = 基地减伤 +4%/级。这是它在模型里唯一的作用点。
	var wave := _wave(12)
	var bare := PBCombatRules.resolve(wave, 0.0, 0.0, _cfg)
	var armored := PBCombatRules.resolve(wave, 0.0, 0.40, _cfg)
	assert_lt(armored.base_damage, bare.base_damage, "防御科技应减少基地受伤")
	assert_almost_eq(armored.base_damage, bare.base_damage * 0.6, 1e-6, "40% 减伤应精确生效")


func test_boss_leaks_hurt_more() -> void:
	var normal := _wave(9)
	var boss := PBWaveRules.build(10, _cfg, _rng)
	assert_true(boss.is_boss(), "第 10 波应是 BOSS 波")
	var per_normal_leak := PBCombatRules.resolve(normal, 0.0, 0.0, _cfg).base_damage / normal.count
	var per_boss_leak := PBCombatRules.resolve(boss, 0.0, 0.0, _cfg).base_damage / boss.count
	assert_gt(per_boss_leak, per_normal_leak, "漏掉一个 BOSS 应比漏掉一个杂兵疼得多")


func test_counter_element_is_worth_about_twice_physical() -> void:
	# §03 的支点：克制对物理接近两倍。
	# **倍率从配置读，不写死** —— M12-a 把物理从 1.05 改成原版的 1.00，
	# 写死的那一版红的是「有人改了物理倍率」，而那件事本来就该由
	# `test_element` 那两条专门的断言去管。
	var water := PBUnit.of(_cfg, PBElement.Type.WATER, PBUnit.Rarity.SR)
	var physical := PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR)
	var fire_wave := PBElement.Type.FIRE
	var ratio := water.effective_power(fire_wave, _cfg) / physical.effective_power(fire_wave, _cfg)
	var want: float = _cfg.mult_counter / _cfg.mult_physical
	assert_almost_eq(ratio, want, 1e-6, "克制系对物理应是 %.2f 倍" % want)
	assert_gt(want, 1.8, "克制对物理的差距塌到 1.8 倍以下，换人就不值得做了")


func test_a_static_five_element_team_now_loses_to_physical() -> void:
	# **这是 M-1 最重要的一条测试，M12-a 把它的结论推翻了一半。**
	#
	# 旧模型（三档：2.0 / 1.0 / 0.5）下，五系全员固定上场的平均倍率是
	# `(2.0 + 0.5 + 1.0×3) / 5 = 1.10`，而纯物理 1.05 —— 固定阵容仍**略胜**。
	#
	# 换成原版的五档之后（同系 0.50、隔一个 0.75、隔两个 1.00），
	# 打一波火：水克制 2.00、土隔一个 0.75、雷隔两个 1.00、风被克 0.50、
	# **火自己同系也是 0.50** —— 平均 `4.75 / 5 = 0.95`，而物理恰好 1.00。
	# **固定五系阵容现在打不过纯物理队。**
	#
	# 这不是回归，是原版有意的设计：物理买的是「永远不会选错」，
	# 而五系买的是「选对了赚一倍」。不肯换人就等于只承担了选错的代价
	# 而没有拿走选对的收益。§03 那 2.0 倍的加成**全部**来自每波换人 ——
	# 这条比旧版更硬地说明了这件事。
	#
	# 断言的作用不变：将来有人把策略脚本改成固定上场、跑出
	# 「属性系统没用」的结论时，这里会先红，提醒他是模型错了不是设计错了。
	var static_team: Array[PBUnit] = []
	for element: int in PBElement.RING:
		static_team.append(PBUnit.of(_cfg, element as PBElement.Type, PBUnit.Rarity.SR))
	var physical_team: Array[PBUnit] = []
	for _i: int in 5:
		physical_team.append(PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR))

	var static_dps := PBCombatRules.team_dps(
		static_team, PBElement.Type.FIRE, 1.0, 1.0, PackedFloat64Array(), _cfg
	)
	var physical_dps := PBCombatRules.team_dps(
		physical_team, PBElement.Type.FIRE, 1.0, 1.0, PackedFloat64Array(), _cfg
	)
	var edge := static_dps / physical_dps
	assert_between(edge, 0.90, 1.00, "不换人的五系阵容应略输给纯物理队（原版五档矩阵）")
	assert_lt(edge, 1.0, "固定阵容一旦反超物理，「每波换人」就不再是必要操作")


func test_rotating_the_team_unlocks_the_real_advantage() -> void:
	# 同样五张卡，换成「只上克制系」之后差距应该拉开到接近两倍。
	var counter := PBUnit.of(_cfg, PBElement.Type.WATER, PBUnit.Rarity.SR)
	var rotated: Array[PBUnit] = []
	for _i: int in 5:
		rotated.append(counter)
	var physical_team: Array[PBUnit] = []
	for _i: int in 5:
		physical_team.append(PBUnit.of(_cfg, PBElement.Type.PHYSICAL, PBUnit.Rarity.SR))

	var rotated_dps := PBCombatRules.team_dps(
		rotated, PBElement.Type.FIRE, 1.0, 1.0, PackedFloat64Array(), _cfg
	)
	var physical_dps := PBCombatRules.team_dps(
		physical_team, PBElement.Type.FIRE, 1.0, 1.0, PackedFloat64Array(), _cfg
	)
	assert_gt(rotated_dps / physical_dps, 1.8, "换上克制系后应拉开到接近两倍")


func test_card_identity_includes_the_variant() -> void:
	# 没有 variant，「火系 SSR」全游戏只有一张，玩家永远凑不出四个克制系上场，
	# §03 的换人策略在模型里被人为掐死一半。这条守着卡池不退化。
	var seen := {}
	for rarity: int in PBUnit.Rarity.size():
		# 铺 [constant PBElement.PICKABLE] 不铺 `Type.size()`（M12-a）：
		# 仙那三格在合成表里是空的，而 [method PBCharacterTable.pick]
		# 撞到空格会走退化路径 —— 退化出来的卡键和别的格重复，
		# 于是「卡片身份键不应撞车」会红，而红的原因和它要测的东西无关。
		for element: int in PBElement.PICKABLE:
			for variant: int in _cfg.characters_per_bucket:
				var unit := PBUnit.of(
					_cfg, element as PBElement.Type, rarity as PBUnit.Rarity, variant
				)
				assert_false(seen.has(unit.key()), "卡片身份键不应撞车")
				seen[unit.key()] = true
	var expected: int = PBUnit.Rarity.size() * PBElement.PICKABLE.size() * _cfg.characters_per_bucket
	assert_eq(seen.size(), expected, "卡池大小应为 稀有度 × 属性 × 每格角色数")
	# **§09 那条「PC 首发 40+ 角色」量的是 `data/characters/`，不是这张合成表**
	# （M10-a 砍成三档之后它只有 36 格）。合成表是一条替身曲线，它只需要
	# 大到「每格都填得满、抽卡不走退化路径」，那条 40+ 由名册那一侧兑现（M10-b）。
	assert_gte(expected, 30, "合成卡池小到这个地步，抽卡会一直撞空格走退化路径")


func test_enough_counter_cards_exist_to_fill_the_bench() -> void:
	# 出战席最多 10 个位置。同一属性的可用角色数 = 4 稀有度 × 每格角色数。
	# 这个数太小的话，「上满克制系」在模型里就是做不到的事，
	# 属性系统的价值会被系统性低估。
	var per_element: int = 4 * _cfg.characters_per_bucket
	assert_gte(per_element, _cfg.deploy_slots_base, "单一属性的角色数应够填满初始出战席")


func test_a_duplicate_draw_is_another_person_not_a_star() -> void:
	# **M5-9 换掉了 §08 的「同卡 3 张升 1 星」。** 那条规则下抽到重复的
	# 等于白抽 —— 一张卡什么都不变（要三张才跳一次），而界面上没有
	# 任何地方显示张数，玩家看到的就是「这一抽没了」。
	var state := PBRunSim.new_state(_cfg)
	var first := PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.R)
	var second := PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.R)
	state.add_unit(first)
	state.add_unit(second)
	assert_eq(state.roster.size(), 2, "两张同名卡是两个人，各占一格")
	assert_ne(first.key(), second.key(), "**键必须不同** —— 同键的话装备会挂到另一个身上")
	assert_eq(first.character.id, second.character.id, "但仍然是同一个角色")
	assert_eq(second.star(), 1, "星级不再由张数派生")
	assert_eq(first.power(_cfg), second.power(_cfg), "两个人一样强")


func test_the_first_copy_keeps_the_bare_character_id() -> void:
	# 「一个角色一张卡」这个既有情形下，存档、在场名单、摆位、装备
	# 四份状态里的键**一字不差** —— 本项目每次换身份层都留这条退化路径。
	var state := PBRunSim.new_state(_cfg)
	var unit := PBUnit.of(_cfg, PBElement.Type.WATER, PBUnit.Rarity.SR)
	state.add_unit(unit)
	assert_eq(unit.key(), unit.character.id, "第一张仍然是光秃秃的角色 id")
