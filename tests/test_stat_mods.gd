extends GutTest
## 属性词条（M12-h1）：装备、羁绊、尾兽光环、角色被动给的「加几点力量 /
## 几点攻击力 / 几成攻速」。词汇表在 [PBStatRules]。
##
## ## 为什么它不能和行为词条（[PBPassiveRules]）合成一张表
##
## **生效的时刻不同，而那个差别是结构性的**：
##
## 1. **二级属性是从一级属性派生的**（`生命 = 100 + 力量×80`、
##    `攻击力 = 1 + 主属性×3.5`）—— 事后加力量只是加了一个孤立的数字，
##    血和攻击力一点都不会动。
## 2. **攻击力还要排在属性克制之前** —— [member PBAttacker.attack] 是
##    `stats.atk × 克制倍率`，事后加的那 200 点**不吃克制**，而原版是吃的。
##    表现是「带克制系装备的收益比裸的低一截」，而它不报错。
##
## 所以这个文件钉三头：**空词条逐位不变**（一切既有配平数字的前提）、
## **一级属性真的往下派生**、**攻击力真的吃克制**。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _someone() -> PBUnit:
	return PBUnit.new(_cfg.characters.all()[0])


func test_an_empty_mod_table_changes_absolutely_nothing() -> void:
	# 同 M3.5-f 装备那条「空着 = 一字不差」：`+= 0.0` 与 `*= 1.0` 都是精确的，
	# 所以没有任何词条时全部既有配平数字一位都不许动。
	var unit := _someone()
	var bare := unit.stats(_cfg)
	var same := unit.stats(_cfg, {})
	assert_eq(bare.strength, same.strength, "力量")
	assert_eq(bare.agility, same.agility, "敏捷")
	assert_eq(bare.intellect, same.intellect, "智力")
	assert_eq(bare.hp, same.hp, "生命")
	assert_eq(bare.atk, same.atk, "攻击力")
	assert_eq(bare.def, same.def, "防御")
	assert_eq(bare.attack_speed, same.attack_speed, "攻速")


func test_a_point_of_strength_really_turns_into_health() -> void:
	# **这一条是这一层存在的理由。** 一级属性必须在算二级之前注入 ——
	# 事后加的话血、攻击力、防御、攻速一个都不会跟着动。
	var unit := _someone()
	var bare := unit.stats(_cfg)
	var buffed := unit.stats(_cfg, {PBStatRules.STRENGTH: 10.0})
	assert_almost_eq(buffed.strength, bare.strength + 10.0, 0.0001, "力量该加上去")
	assert_gt(buffed.hp, bare.hp, "而血该跟着涨")
	assert_almost_eq(
		buffed.hp - bare.hp,
		10.0 * PBStatRules.HP_PER_STRENGTH,
		0.01,
		"涨的量该正好是原版那个系数"
	)


func test_all_stats_moves_all_three_at_once() -> void:
	# 原版的「全属性 +15」。它和单项**相加**，不是二选一。
	var unit := _someone()
	var bare := unit.stats(_cfg)
	var buffed := unit.stats(
		_cfg, {PBStatRules.ALL_STATS: 5.0, PBStatRules.AGILITY: 3.0}
	)
	assert_almost_eq(buffed.strength, bare.strength + 5.0, 0.0001, "力量 +5")
	assert_almost_eq(buffed.agility, bare.agility + 8.0, 0.0001, "敏捷 +5 再 +3")
	assert_almost_eq(buffed.intellect, bare.intellect + 5.0, 0.0001, "智力 +5")


func test_all_stats_bonus_scales_his_own_stats_but_not_the_points() -> void:
	# 羁绊的「提升 20% 的全属性」。放大的是角色自己的三围（含等级成长），
	# 装备给的点数排在后面加 —— 放大点数的话装备越多这一句越强。
	var unit := _someone()
	unit.level = 10
	var bare := unit.stats(_cfg)
	var scaled := unit.stats(_cfg, {PBStatRules.ALL_STATS_BONUS: 0.2})
	assert_almost_eq(scaled.strength, bare.strength * 1.2, 0.0001, "力量 ×1.2")
	assert_almost_eq(scaled.agility, bare.agility * 1.2, 0.0001, "敏捷 ×1.2")
	assert_almost_eq(scaled.intellect, bare.intellect * 1.2, 0.0001, "智力 ×1.2")
	assert_gt(scaled.hp, bare.hp, "血跟着三围派生")
	assert_gt(scaled.atk, bare.atk, "攻击力跟着主属性派生")
	var both := unit.stats(
		_cfg, {PBStatRules.ALL_STATS_BONUS: 0.2, PBStatRules.ALL_STATS: 30.0}
	)
	assert_almost_eq(both.strength, bare.strength * 1.2 + 30.0, 0.0001, "点数不跟着放大")


func test_the_flat_words_land_on_the_derived_stats() -> void:
	var unit := _someone()
	var bare := unit.stats(_cfg)
	var buffed := unit.stats(
		_cfg,
		{
			PBStatRules.ATTACK: 200.0,
			PBStatRules.DEFENCE: 10.0,
			PBStatRules.MAX_HP: 1200.0,
		}
	)
	assert_almost_eq(buffed.atk, bare.atk + 200.0, 0.0001, "攻击力 +200 点")
	assert_almost_eq(buffed.def, bare.def + 10.0, 0.0001, "防御 +10 点")
	assert_almost_eq(buffed.hp, bare.hp + 1200.0, 0.0001, "生命 +1200 点")


func test_the_rate_words_multiply_after_the_flat_ones() -> void:
	# 原版两种都写（「生命值 +1200」和「提升 [1.5x等级]% 最大生命值」），
	# **成数乘在点数之后** —— 反过来的话加点数那一份也被放大，
	# 而那不是人会预期的叠加方式。
	var unit := _someone()
	var bare := unit.stats(_cfg)
	var buffed := unit.stats(
		_cfg, {PBStatRules.MAX_HP: 1000.0, PBStatRules.HP_BONUS: 0.5}
	)
	assert_almost_eq(buffed.hp, (bare.hp + 1000.0) * 1.5, 0.01, "先加点数，再乘成数")

	var faster := unit.stats(_cfg, {PBStatRules.ATTACK_SPEED: 1.0})
	assert_almost_eq(faster.attack_speed, bare.attack_speed * 2.0, 0.0001, "攻速 +100%")


func test_the_attack_word_is_multiplied_by_the_element_counter() -> void:
	# **这是「攻击力必须在这一层」的另一半理由。** 事后往攻击者身上加的话，
	# 装备给的攻击力不吃克制，而原版是吃的 —— 表现是
	# 「带克制系装备的收益比裸的低一截」，而所有数字看起来都正常。
	var unit := _someone()
	var mods := {PBStatRules.ATTACK: 100.0}
	# **挑一波他吃得到加成的** —— 按倍率找，不按「谁克谁」的方向记，
	# 那个方向我记反过一次，而记反的表现是这条断言量的是被克那一档。
	var wave: PBElement.Type = unit.element
	for candidate: PBElement.Type in PBElement.PICKABLE:
		if _cfg.damage_multiplier(PBElement.relation(unit.element, candidate)) > 1.0:
			wave = candidate
			break
	var rel := PBElement.relation(unit.element, wave)
	assert_gt(_cfg.damage_multiplier(rel), 1.0, "该找得到一波他吃加成的")
	var plain := unit.effective_attack(wave, _cfg)
	var armed := unit.effective_attack(wave, _cfg, mods)
	assert_almost_eq(
		armed - plain, 100.0 * _cfg.damage_multiplier(rel), 0.01, "那 100 点也要乘克制倍率"
	)


func test_collect_adds_up_instead_of_overwriting() -> void:
	# 两组羁绊各给 +15 点防御该是 +30。覆盖的表现是玩家凑满两组
	# 只拿到一组的量，而那不报错（同 [PBBuffBag] 同 id 整份覆盖那个坑）。
	var got := PBStatRules.collect(
		[{PBStatRules.DEFENCE: 15.0}, {PBStatRules.DEFENCE: 15.0}]
	)
	assert_almost_eq(PBStatRules.amount(got, PBStatRules.DEFENCE), 30.0, 0.0001, "该相加")


func test_collect_leaves_the_behaviour_words_alone() -> void:
	# 两张表各收自己的键。行为键漏进属性表的话它会被静默忽略，
	# 而属性键漏进行为表的话 [method PBPassiveRules.grant] 会拒收 ——
	# 两条都不报错，所以这一条钉住分工。
	var mixed := {
		PBStatRules.DEFENCE: 15.0,
		PBPassiveRules.CRIT_CHANCE: 0.2,
		PBPassiveRules.SPLASH: 0.3,
	}
	var stats_half := PBStatRules.collect([mixed])
	assert_eq(stats_half.size(), 1, "属性表只该收走防御那一条")
	assert_true(stats_half.has(PBStatRules.DEFENCE), "而且收的是它")

	var attacker := PBAttacker.new()
	var fitted: int = PBPassiveRules.equip(attacker, [mixed])
	assert_eq(fitted, 2, "行为表只该装上暴击和溅射")


func test_no_key_lives_in_both_tables() -> void:
	# 同一个键进两张表的话，它会被**算两遍** —— 一次在算三围那一刻、
	# 一次在建人之后，而屏幕上只表现为「这一条好像特别强」。
	for key: StringName in PBStatRules.ALL:
		assert_false(PBPassiveRules.is_known(key), "「%s」同时住在两张表里" % key)
	for key: StringName in PBPassiveRules.ALL:
		assert_false(PBStatRules.is_known(key), "「%s」同时住在两张表里" % key)


func test_the_shared_directory_knows_every_key_from_both_tables() -> void:
	# 三个生成器、尾兽加载器和四个测试都问 [method PBModRules.is_known]。
	# 漏掉一张表的表现是「这个键在别处能用，在这里被拒收」。
	for key: StringName in PBStatRules.ALL:
		assert_true(PBModRules.is_known(key), "属性键 %s 该认得" % key)
	for key: StringName in PBPassiveRules.ALL:
		assert_true(PBModRules.is_known(key), "行为键 %s 该认得" % key)
	assert_false(PBModRules.is_known(&"no_such_key"), "拼错的键不许认")
