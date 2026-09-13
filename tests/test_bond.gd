extends GutTest
## [PBBond] / [PBBondTable] / [PBBondRules] 的测试。M2-b1。
##
## 这一步是**当作可对拍的重构做的**：羁绊从「数人头」换成查表结算，
## 但默认装的是一张精确复现旧曲线的合成表，所以整套 CSV 应该逐位不变。
## 换真羁绊表是 M2-b2，那一步的数值变化必须能和这一步的重构分开看 ——
## 混在一起的话，一旦数字对不上就分不清是重构写错了还是数据本来就该变。
##
## 所以本文件最要紧的是 `test_the_synthetic_table_reproduces_the_stand_in_curve`。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func _unit(element: PBElement.Type, rarity := PBUnit.Rarity.R, variant := 0) -> PBUnit:
	return PBUnit.of(_cfg, element, rarity, variant)


## 第 [param index] 张**互不相同**的卡，0 到 47 各不相同。
##
## 不能靠「同一格取不同 variant」凑人数 —— 一格只有
## [member PBSimConfig.characters_per_bucket] 个角色，下标会 `posmod` 绕回去，
## 重复的卡在仓库里合并成星级，**人数悄悄比想的少**。
## 拿 `i % 6, R, i / 6` 造 20 张实际只进 12 张，正好卡在羁绊计数上限上，
## 于是「上限之后派遣免费」这条根本没被测到。所以三个维度一起走。
func _distinct(index: int) -> PBUnit:
	var per: int = maxi(_cfg.characters_per_bucket, 1)
	var elements: int = PBElement.Type.size()
	return PBUnit.of(
		_cfg,
		((index / per) % elements) as PBElement.Type,
		((index / (per * elements)) % PBUnit.Rarity.size()) as PBUnit.Rarity,
		index % per
	)


# ── 对拍 ────────────────────────────────────────────────────────


func test_the_synthetic_table_reproduces_the_stand_in_curve() -> void:
	# **本文件的正题。** 合成羁绊表在任何（人数, 派遣数）上都必须给出
	# 和旧公式 `1 + 0.06 × min(在场 − 派遣, 12)` 一模一样的倍率。
	#
	# 扫到 24 张卡是有意的：把在场上限（M3.5-i 之后是出战席的 10）
	# 和羁绊计数上限（12）都扫过去才算扫全。
	var state := PBRunSim.new_state(_cfg)
	state.tech_pop = _cfg.tech_pop_max
	for i: int in 24:
		state.add_unit(_distinct(i))
		assert_eq(state.roster.size(), i + 1, "第 %d 张应该是新卡，不是重复卡" % i)
		for dispatch: int in 5:
			state.dispatched = dispatch
			var counted: int = mini(
				maxi(mini(state.roster.size(), state.open_slots(_cfg)) - dispatch, 0),
				_cfg.bond_unit_cap
			)
			assert_almost_eq(
				state.bond_mult(_cfg),
				1.0 + _cfg.bond_power_per_unit * float(counted),
				0.000001,
				"查表结算与旧公式不一致：%d 张卡、派 %d 人" % [state.roster.size(), dispatch]
			)
		state.dispatched = 0


func test_dispatch_still_costs_bond_tiers() -> void:
	# 派遣的代价不能在重构里丢掉 —— 丢了不报错，只表现为
	# 「派满永远最优」，而那会让 §06 整个赌注在扫描里得出假结论。
	var state := PBRunSim.new_state(_cfg)
	for i: int in 6:
		state.add_unit(_distinct(i))
	var kept: float = state.bond_mult(_cfg)
	state.dispatched = 3
	assert_lt(state.bond_mult(_cfg), kept, "派出去的人羁绊应该失效（§06）")


func test_the_count_is_capped_so_a_deep_roster_dispatches_for_free() -> void:
	# 在场人数够多时派遣**不掉羁绊** —— 掉的档被计数上限吃掉了。
	# 这是派遣决策里最反直觉的一格，任务卡专门显示它（M1-d）。
	#
	# 「不掉羁绊」不等于「免费」：M3.5-i 删掉待命台之后派出去的人
	# 真的不上场，少那一份输出是另一笔账（见 [method PBValuation.dispatch_loss]）。
	# 本条只管羁绊这一半。
	#
	# ## 上限在出厂配置下已经够不着了
	#
	# 在场上限从「出战 10 + 待命 6 = 16」掉到了 10，而
	# [member PBSimConfig.bond_unit_cap] 还是 12 —— **派任何人都会掉档**。
	# 所以这里把上限压到一个够得着的值再测：验的是**规则**还在，
	# 而「出厂那个 12 该改成多少」是数值回归的事，不该由一条测试顺手拍板。
	_cfg.bond_unit_cap = 5
	_cfg.bonds = PBBondTable.synthetic(_cfg.bond_power_per_unit, _cfg.bond_unit_cap)
	var state := PBRunSim.new_state(_cfg)
	state.tech_pop = _cfg.tech_pop_max
	for i: int in 20:
		state.add_unit(_distinct(i))
	# 前提：在场人数减掉派遣之后仍然压得住计数上限，否则测的是别的东西。
	var on_field: int = mini(state.roster.size(), state.open_slots(_cfg))
	assert_gte(on_field - 3, _cfg.bond_unit_cap, "在场人数得多到派 3 个人还压得住上限")

	var kept: float = state.bond_mult(_cfg)
	state.dispatched = 3
	assert_eq(state.bond_mult(_cfg), kept, "在场人数远超计数上限时，派几个人都不该掉档")


# ── 档位查表 ────────────────────────────────────────────────────


func _three_tier_bond() -> PBBond:
	# §09 的小队型规格：2 / 3 / 4 档。
	var bond := PBBond.new()
	bond.id = &"t_squad"
	bond.match_mode = PBBond.Match.MEMBERS
	bond.tier_counts = [2, 3, 4]
	bond.tier_power = [0.10, 0.25, 0.40]
	return bond


func test_tiers_upgrade_instead_of_stacking() -> void:
	# §09 的档位表读的是**升级**（2 档 → 3 档 → 4 档），不是叠加。
	# 写成叠加的话满档会给 0.75 而不是 0.40，多组羁绊一起通胀到离谱。
	var bond := _three_tier_bond()
	assert_eq(bond.bonus_at(1), 0.0, "不够 2 人不该激活")
	assert_eq(bond.bonus_at(2), 0.10, "2 人吃第 1 档")
	assert_eq(bond.bonus_at(3), 0.25, "3 人吃第 2 档，不是 1+2 档相加")
	assert_eq(bond.bonus_at(4), 0.40, "4 人吃第 3 档")
	assert_eq(bond.bonus_at(9), 0.40, "超过满档人数不再涨")


func test_tier_and_distance_are_both_readable() -> void:
	# §06 的验收原话是「派了羁绊掉几档，准备阶段能一眼看出」——
	# 界面要的是**档数**和**离下一档差几个人**，不是一个小数倍率。
	var bond := _three_tier_bond()
	var members: Array[PBUnit] = [_unit(PBElement.Type.FIRE), _unit(PBElement.Type.WIND)]
	for unit: PBUnit in members:
		bond.member_ids.append(unit.character.id)

	assert_eq(bond.tier_at(0), 0, "没人到场是 0 档")
	assert_eq(bond.tier_at(3), 2, "3 个人是第 2 档")
	assert_eq(PBBondRules.active_tiers(members, _cfg.bonds).size(), 1, "合成表只有一组羁绊")


# ── 成员判定的三种模式 ──────────────────────────────────────────


func test_named_bonds_match_by_id_not_by_element() -> void:
	# §14 铁律 5：代码里不出现角色名，羁绊也一样只认 id。
	var bond := _three_tier_bond()
	var member := _unit(PBElement.Type.FIRE)
	var outsider := _unit(PBElement.Type.FIRE, PBUnit.Rarity.R, 1)
	bond.member_ids.append(member.character.id)
	assert_true(bond.counts(member), "点名的人该算成员")
	assert_false(bond.counts(outsider), "同属性但没点名的人不该算 —— 命名羁绊认的是身份")


func test_element_bonds_do_not_need_a_member_list() -> void:
	# §09 的「属性型（同系）」兜底羁绊。**点名会是个维护陷阱**：
	# 每改一次角色表都要同步改成员表，漏改不报错，只表现为
	# 「新角色好像不吃属性羁绊」。
	var bond := PBBond.new()
	bond.id = &"t_fire"
	bond.match_mode = PBBond.Match.ELEMENT
	bond.match_element = PBElement.Type.FIRE
	bond.tier_counts = [2, 4]
	bond.tier_power = [0.06, 0.14]
	assert_true(bond.counts(_unit(PBElement.Type.FIRE)), "同系该算")
	assert_false(bond.counts(_unit(PBElement.Type.WATER)), "别的系不该算")
	assert_eq(bond.member_ids.size(), 0, "属性型羁绊不该需要成员名单")


# ── 表本身 ──────────────────────────────────────────────────────


func test_the_table_refuses_bad_tier_data() -> void:
	# 档位表写歪了**不会崩，只会让某一档静默失效** —— 那种偏差只表现为
	# 「这组羁绊好像没什么用」，是最难查的一类。所以在入口拦。
	var table := PBBondTable.new()

	var mismatched := PBBond.new()
	mismatched.id = &"t_bad_len"
	mismatched.tier_counts = [2, 3]
	mismatched.tier_power = [0.1]
	assert_false(table.add(mismatched), "档位两条数组不等长应被拒")

	var unsorted := PBBond.new()
	unsorted.id = &"t_unsorted"
	unsorted.tier_counts = [4, 2]
	unsorted.tier_power = [0.1, 0.2]
	assert_false(table.add(unsorted), "档位人数不是升序应被拒")

	var nameless := PBBond.new()
	assert_false(table.add(nameless), "缺 id 应被拒")

	var good := _three_tier_bond()
	assert_true(table.add(good), "合法的该收下")
	assert_false(table.add(_three_tier_bond()), "id 重复应被拒")
	assert_eq(table.size(), 1, "被拒的都不该进表")


func test_multiple_bonds_add_up_instead_of_multiplying() -> void:
	# §09 说「同一角色可同时属于多个羁绊」。相乘的话多组收益指数叠加，
	# 「能凑羁绊的卡全塞进去」立刻变成唯一解 —— 那正是 §05 记着的原版漏洞。
	var table := PBBondTable.new()
	var units: Array[PBUnit] = [
		_unit(PBElement.Type.FIRE), _unit(PBElement.Type.FIRE, PBUnit.Rarity.R, 1)
	]

	for i: int in 2:
		var bond := PBBond.new()
		bond.id = StringName("t_ring_%d" % i)
		bond.match_mode = PBBond.Match.ELEMENT
		bond.match_element = PBElement.Type.FIRE
		bond.tier_counts = [2]
		bond.tier_power = [0.10]
		assert_true(table.add(bond), "第 %d 组该收下" % i)

	assert_almost_eq(
		PBBondRules.power_bonus(units, table), 0.20, 0.000001, "两组各 0.10 应该是 0.20（相加），不是 0.21（相乘）"
	)


func test_an_empty_table_is_simply_no_bonds() -> void:
	# 装载器装不出东西时不该崩，也不该白送加成 —— 该表现为「没有羁绊」。
	var units: Array[PBUnit] = [_unit(PBElement.Type.FIRE)]
	assert_eq(PBBondRules.power_bonus(units, PBBondTable.new()), 0.0, "空表不该给加成")
	assert_eq(PBBondRules.power_bonus(units, null), 0.0, "没有表也不该崩")
