extends GutTest
## 两层属性表与攻防双元素。§03A，M3.5-a。
##
## ## 这个文件守的是什么
##
## §03A 推翻了 M1 的伤害模型（一个 `power` 标量），代价是明知的。
## 换模型时最容易出的不是数值错，是**接线错**：
##
## 1. 二级属性没接上 —— 升级了但基础属性不动，玩家只看到「等级涨了没变强」
## 2. 攻防两个元素**接反了** —— 克制关系整个镜像过来，而它照样跑得动、
##    照样出得来数字，只是每一场都算错
## 3. `power()` 换成派生量之后**和战斗层脱钩** —— 界面报一个数、
##    战场打另一个数，这正是 CLAUDE.md 那条「四块面板与比价同源」防的病
##
## 所以这里逐条钉的是「链路是通的」，不是「数值是对的」。
## 数值全是占位值，按现行的工作方式留到系统齐了再一起扫。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _any_character() -> PBCharacter:
	return _cfg.characters.all()[0]


# ── 二级属性 → 基础属性 ────────────────────────────────────────


func test_levelling_raises_the_secondary_attributes_by_their_own_growth() -> void:
	# 每个角色的成长值不一样，那是「定位」的唯一数据来源 ——
	# 全表同一条成长曲线的话，力量型和智力型就只剩一个名字上的区别。
	var character := _any_character()
	var one := PBStatRules.of(character, 1, 1, _cfg)
	var ten := PBStatRules.of(character, 10, 1, _cfg)
	assert_almost_eq(
		ten.strength, one.strength + character.strength_growth * 9.0, 1e-6, "力量该按自己的成长涨"
	)
	assert_almost_eq(ten.agility, one.agility + character.agility_growth * 9.0, 1e-6, "敏捷同理")
	assert_almost_eq(ten.intellect, one.intellect + character.intellect_growth * 9.0, 1e-6, "智力同理")


func test_the_secondary_attributes_actually_reach_the_base_ones() -> void:
	# **最容易静默断掉的一条**：字段填了、等级涨了，但系数没接上，
	# 于是升级只让信息栏上三个数字变大，血、攻、防一动不动。
	var character := _any_character()
	var one := PBStatRules.of(character, 1, 1, _cfg)
	var ten := PBStatRules.of(character, 10, 1, _cfg)
	assert_gt(ten.hp, one.hp, "力量涨了，血就该涨")
	assert_gt(ten.mp, one.mp, "智力涨了，蓝就该涨")
	assert_gt(ten.atk, one.atk, "主属性涨了，攻就该涨")
	assert_gt(ten.def, one.def, "敏捷涨了，防就该涨")
	assert_gt(ten.attack_speed, one.attack_speed, "敏捷涨了，攻速就该涨")


func test_only_the_primary_attribute_drives_attack() -> void:
	# §03A 沿用 War3 的骨架：攻击力只由主属性决定，另外两项各管自己那条线。
	# 三项都吃攻击的话，「主属性」这个概念就没有意义了。
	var character := _any_character().duplicate() as PBCharacter
	character.primary = PBCharacter.Primary.STRENGTH
	var base := PBStatRules.of(character, 1, 1, _cfg)

	var stronger := character.duplicate() as PBCharacter
	stronger.strength += 10.0
	assert_gt(PBStatRules.of(stronger, 1, 1, _cfg).atk, base.atk, "加主属性该加攻")

	var smarter := character.duplicate() as PBCharacter
	smarter.intellect += 10.0
	assert_almost_eq(PBStatRules.of(smarter, 1, 1, _cfg).atk, base.atk, 1e-6, "副属性不该影响攻")
	assert_gt(PBStatRules.of(smarter, 1, 1, _cfg).mp, base.mp, "但它该加蓝")


func test_stars_scale_the_whole_card_but_do_not_change_its_shape() -> void:
	# 等级顺着定位长，星级整体变强 —— 两条轴刻意分开。
	# 合成一条的话，「升级」和「抽到重复卡」变成同一件事的两种付款方式，
	# 而 §07 的经济张力恰恰建在「这两笔钱抢同一个预算」上。
	var character := _any_character()
	var one_star := PBStatRules.of(character, 1, 1, _cfg)
	var two_star := PBStatRules.of(character, 1, 2, _cfg)
	assert_gt(two_star.atk, one_star.atk, "升星该加攻")
	assert_gt(two_star.hp, one_star.hp, "升星该加血")
	assert_eq(two_star.strength, one_star.strength, "升星不该动二级属性")
	assert_eq(two_star.agility, one_star.agility, "升星不该动二级属性")


# ── 攻防双元素 ────────────────────────────────────────────────


func test_attack_and_defence_elements_are_two_different_questions() -> void:
	# **拆开的全部意义在这里**：一张卡在「它打谁」和「它扛谁」两条线上
	# 指向不同的波次。合成一个的话两轴永远同进同退，拆开就白拆了。
	var mixed: int = 0
	for character: PBCharacter in _cfg.characters.all():
		if character.element != character.def_element:
			mixed += 1
	assert_gt(mixed, 0, "至少要有角色的攻防元素不同，否则这一节等于没做")


func test_the_strike_reads_the_attackers_attack_and_the_defenders_defence() -> void:
	# 接反了照样跑得动、照样出数字，只是每一场都算错 —— 所以要钉方向。
	# 火克风：火攻打风防该是克制，反过来该是被克。
	var counter: float = PBStatRules.strike_damage(
		100.0, PBElement.Type.FIRE, 0.0, PBElement.Type.WIND, _cfg
	)
	var weak: float = PBStatRules.strike_damage(
		100.0, PBElement.Type.WIND, 0.0, PBElement.Type.FIRE, _cfg
	)
	# **基准不能用「火打火」**（M12-a）：同系在原版矩阵里是 0.50，
	# 和被克一个数 —— 拿它当无加成的参照，「被克 < 无加成」会永远相等而红。
	# 真正的无加成是环距 3「隔两个」，火对土就是。
	var neutral: float = PBStatRules.strike_damage(
		100.0, PBElement.Type.FIRE, 0.0, PBElement.Type.EARTH, _cfg
	)
	var mirror: float = PBStatRules.strike_damage(
		100.0, PBElement.Type.FIRE, 0.0, PBElement.Type.FIRE, _cfg
	)
	assert_gt(counter, neutral, "火攻打风防该吃克制")
	assert_lt(weak, neutral, "风攻打火防该被克")
	assert_eq(mirror, weak, "同系与被克在原版是同一个数")


func test_armour_never_reaches_full_immunity() -> void:
	# 线性减免下，敌人 ATK 按 `GROWTH^n` 指数涨而防御是加法涨的，
	# 两条曲线必然交叉：交叉前无敌、交叉后裸奔，中间没有过渡。
	assert_eq(PBStatRules.damage_reduction(0.0, _cfg), 0.0, "没防御就没减伤")
	var huge: float = PBStatRules.damage_reduction(100000.0, _cfg)
	assert_lt(huge, 1.0, "堆到天上也不该完全免疫")
	assert_gt(huge, 0.9, "但堆到天上该很接近")
	assert_gt(
		PBStatRules.damage_reduction(100.0, _cfg),
		PBStatRules.damage_reduction(50.0, _cfg),
		"防御越高减伤越多"
	)


func test_armour_actually_cuts_the_damage() -> void:
	var bare: float = PBStatRules.strike_damage(
		100.0, PBElement.Type.PHYSICAL, 0.0, PBElement.Type.PHYSICAL, _cfg
	)
	var armoured: float = PBStatRules.strike_damage(
		100.0, PBElement.Type.PHYSICAL, 50.0, PBElement.Type.PHYSICAL, _cfg
	)
	assert_lt(armoured, bare, "有防御该少挨打")
	assert_gt(armoured, 0.0, "但不该被挡光")


# ── 与旧模型的接缝 ────────────────────────────────────────────


func test_power_is_now_attack_times_attack_speed() -> void:
	# **这一条是可对拍重构的锚点。** 战斗层、估值、四块面板读到的仍是
	# 「每秒伤害」这同一种量，所以换模型带来的数值变化可以和接线错误分开看。
	for character: PBCharacter in _cfg.characters.all():
		var unit := PBUnit.new(character)
		var stats := unit.stats(_cfg)
		assert_almost_eq(unit.power(_cfg), stats.atk * stats.attack_speed, 1e-6, "战力 = 攻 × 攻速")


func test_the_generated_table_still_follows_the_rarity_ladder() -> void:
	# §08 的硬约束：稀有度阶梯必须显著低于克制倍率，否则「升一档稀有度」
	# 等价于「换上克制系」，§03 整套设计被架空。
	# 角色表的攻击力基数是照着 `rarity_power` 铺的，所以那条阶梯要还在。
	var by_rarity: Dictionary = {}
	for character: PBCharacter in _cfg.characters.all():
		var unit := PBUnit.new(character)
		var bucket: Array = by_rarity.get(int(character.rarity), [])
		bucket.append(unit.power(_cfg))
		by_rarity[int(character.rarity)] = bucket

	var previous: float = 0.0
	for rarity: int in PBUnit.Rarity.size():
		if not by_rarity.has(rarity):
			continue
		var total: float = 0.0
		for value: float in by_rarity[rarity]:
			total += value
		var mean: float = total / float((by_rarity[rarity] as Array).size())
		assert_gt(mean, previous, "第 %d 档的平均战力该高于上一档" % rarity)
		previous = mean


func test_a_code_made_character_still_has_a_rarity_ladder() -> void:
	# **这一条守着一个静默陷阱。** `data/` 的属性块是生成脚本铺的，
	# 代码里 `PBCharacter.make()` 造出来的角色没有 —— 不补的话每个人都吃默认值，
	# **R 和顶档的战力一模一样**，稀有度阶梯在合成表上彻底消失。
	#
	# 它不会让任何断言变红（合成表的用例查的是构成，不是强度），
	# 只会让所有用合成表的整局测试跑在一副全是白板的牌上。
	# 实测过一次：整套测试从 30 秒涨到 120 秒，而没有一条测试报错。
	var previous: float = 0.0
	for rarity: int in PBUnit.Rarity.size():
		var made := PBCharacter.make(
			StringName("probe_%d" % rarity), PBElement.Type.FIRE, rarity as PBUnit.Rarity
		)
		var power: float = PBUnit.new(made).power(_cfg)
		assert_gt(power, previous, "第 %d 档该比上一档强" % rarity)
		previous = power


func test_the_two_placeholder_ladders_do_not_drift_apart() -> void:
	# 稀有度阶梯写了两遍：`PBSimConfig.rarity_power`（真角色表的生成依据）
	# 和 `PBStatRules.PLACEHOLDER_RARITY_DPS`（代码造角色时用）。
	# 写歪了不报错，只会让合成表和真表的强度悄悄分叉。
	assert_eq(
		Array(PBStatRules.PLACEHOLDER_RARITY_DPS),
		Array(_cfg.rarity_power),
		"两份稀有度阶梯必须一致"
	)
	for rarity: int in PBUnit.Rarity.size():
		var made := PBCharacter.make(
			StringName("ladder_%d" % rarity), PBElement.Type.FIRE, rarity as PBUnit.Rarity
		)
		assert_almost_eq(
			PBUnit.new(made).power(_cfg),
			_cfg.rarity_power[rarity],
			0.01,
			"1 级 1 星的战力该正好落在阶梯上 —— 那是新旧模型的接缝"
		)


func test_levelling_up_makes_a_card_stronger_in_the_only_currency_combat_reads() -> void:
	# 等级要真的进战斗，不能只进信息栏 —— 那正是「展示层派生」那条路
	# 被否掉的理由（玩家迟早发现「加了力量没变强」）。
	var unit := PBUnit.new(_any_character())
	var before: float = unit.power(_cfg)
	unit.level = 10
	assert_gt(unit.power(_cfg), before, "升级该让战力真的涨")
