extends GutTest
## [PBQuestCard] 的测试。M1-d。
##
## §06 的验收原话是「**派了羁绊掉几档，准备阶段能一眼看出**」。
## 这一组断言就是照那句话逐条对的 —— 卡面缺哪一格，哪条就红。
##
## 任务是 M1 里**唯一真正的两难**（阵容不是，见 `test_valuation.gd` 里
## `test_picking_by_effective_power_is_strictly_optimal`），所以这张卡上的
## 每个数都直接决定玩家的选择，错了不报错、只表现为「玩家做了个错误决定」。

var _cfg: PBSimConfig


func before_each() -> void:
	# **走 PBGameData 而不是 PBSimConfig.new()。** M2-b 之后两者差得很远：
	# 后者装的是给对拍用的合成羁绊表（一组「所有人都算成员」的假羁绊），
	# 拿它测卡面会让断言对着 `syn_headcount` 这种永远不会出现在游戏里的名字。
	# 卡面测试的全部意义就是「玩家会看到什么」，那就得喂真数据。
	_cfg = PBGameData.config()


## 造一个有 [param count] 张**互不相同**的卡的局面。
##
## **不能靠随机抽。** 真角色表只有 30 个角色，而且（属性 × 稀有度）的格子
## 不是满的，`PBUnit.of` 遇到空格会退化到同稀有度的任意一个 —— 撞得很厉害。
## 原来那版随机抽 7 次实际只进 5 张，于是待命台不够派任务，
## **整条断言跑到了「派不出」那个分支上**，测的完全不是它要测的东西。
##
## 按表的顺序取是确定的（装载器按文件名排序，见 [PBCharacterLoader]）。
func _state_of(count: int, maxed_pop: bool = false) -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	if maxed_pop:
		state.tech_pop = _cfg.tech_pop_max
	var all := _cfg.characters.all()
	for i: int in mini(count, all.size()):
		state.add_unit(PBUnit.new(all[i]))
	assert_eq(state.roster.size(), mini(count, all.size()), "这批卡应该互不相同")
	return state


func _plan_of(wave_index: int, grade: int) -> PBWavePlan:
	var plan := PBWavePlan.new()
	plan.wave = PBWaveRules.build(wave_index, _cfg, RandomNumberGenerator.new())
	plan.quest_grade = grade
	return plan


func _card() -> PBQuestCard:
	var card := PBQuestCard.new()
	add_child_autofree(card)
	return card


func test_the_card_names_which_bonds_dispatch_would_break() -> void:
	# §06 的验收原话「派了羁绊掉几档，准备阶段能一眼看出」。
	#
	# **M2-b 之后这条重写过。** 旧版断的是「羁绊 7 → 4 档」这种**人头数**，
	# 那在替身曲线下成立（一个人就是一档），装上真羁绊表之后就不成立了 ——
	# 档位是每组羁绊各有各的。而且玩家要的本来也不是一个标量，
	# 是「我会失去哪一组」。
	var state := _state_of(7)
	var plan := _plan_of(6, 2)  # A 级，派 3 人
	var card := _card()
	card.reset(state, _cfg, plan)

	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	var kept := PBBondRules.active_tiers(_bonded_with(state, 0), _cfg.bonds)
	var sent := PBBondRules.active_tiers(_bonded_with(state, need), _cfg.bonds)

	var broken: Array[PBBond] = []
	for bond: PBBond in _cfg.bonds.all():
		if int(sent.get(bond.id, 0)) < int(kept.get(bond.id, 0)):
			broken.append(bond)
	assert_false(broken.is_empty(), "这个局面派 %d 人应该真的会掉档，否则测不到东西" % need)

	for bond: PBBond in broken:
		assert_true(
			card._bond.text.contains(PBLocale.of_bond(bond)),
			"掉档的羁绊要点名写出来（缺 %s）：%s" % [PBLocale.of_bond(bond), card._bond.text]
		)
	assert_true(card._bond.text.contains("战力 −"), "还要给出对应的战力损失：%s" % card._bond.text)


func test_the_card_never_shows_a_raw_key_instead_of_a_name() -> void:
	# 羁绊名走 [PBLocale]。语言表缺一条时它会回退到 key，
	# 那在文档注释里是有意为之，但**摆到卡面上就是 bug** ——
	# 玩家会看到「bond.xxx 3→2 档」。
	var state := _state_of(7)
	var card := _card()
	card.reset(state, _cfg, _plan_of(6, 2))
	assert_false(card._bond.text.contains("bond."), "卡面漏出了 name_key：%s" % card._bond.text)


func test_it_says_so_when_dispatch_breaks_nothing() -> void:
	# 被派走的人**没在给任何一组羁绊顶档**时，这一波派遣是白捡的钱，
	# 卡面要明说 —— 不说的话玩家会以为任务永远要付代价。
	#
	# ## 这条分支在 M2-b 之后变罕见了，那是设计上的改善
	#
	# 旧的替身曲线按人头算、封顶 12 人，所以**只要板凳够深，派遣就恒定免费**——
	# M1-d 把那一格当成整张卡最值钱的信息。装上真羁绊表之后不再成立：
	# 没有全局上限了，每个成员都在给自己那几组做贡献，
	# 板凳末尾的人也可能正顶着某一档。
	#
	# 于是 §06 的「这一波我要羁绊，还是要钱」**几乎总是真取舍**，
	# 而不是「板凳深了就白拿」。这比原来好，但分支仍然存在，仍然要测。
	#
	# 局面用 set_field 直接摆，不靠抽卡碰运气 —— 碰得到的概率太低，
	# 那样的测试会随机变红，而随机红的测试很快就会被人无视。
	var state := PBRunSim.new_state(_cfg)
	state.tech_pop = _cfg.tech_pop_max
	var field: Array[PBUnit] = []
	for character: PBCharacter in _cfg.characters.all():
		if character.element == PBElement.Type.THUNDER:
			var unit := PBUnit.new(character)
			state.add_unit(unit)
			field.append(unit)
	state.set_field(field)
	assert_eq(field.size(), 5, "这一系要有 5 个角色，派走 1 个之后才还撑得住 4 人档")

	# 派 1 个之后这一系还剩 4 个，仍然吃着同一档；也没有别的组被顶着。
	var kept := PBBondRules.active_tiers(_bonded_with(state, 0), _cfg.bonds)
	var sent := PBBondRules.active_tiers(_bonded_with(state, 1), _cfg.bonds)
	assert_eq(sent, kept, "这个局面应该一档都不掉，否则测不到「免费」那一支")

	var text: String = _card()._bond_text(state, _cfg, 1)
	assert_true(text.contains("没有羁绊会掉档"), "一档都不掉的时候要明说：%s" % text)
	# **不能再写「战力不变」。** M3.5-i 删掉待命台之前派的是不上场的板凳，
	# 那句是对的；现在派的是在场的人，他这一波真的不打了。
	assert_true(text.contains("这一波不上场"), text)
	assert_false(text.contains("战力不变"), "派出去的人现在会离场，战力不可能不变：%s" % text)


## 派 [param dispatch] 个人之后还有谁在给羁绊计数。**用完必须还原** ——
## 估值函数漏掉「改回来」会让玩家每看一眼任务卡就掉一层羁绊，
## `test_dispatch_estimates_leave_no_trace_on_the_state` 守的就是这条。
func _bonded_with(state: PBRunState, dispatch: int) -> Array[PBUnit]:
	var before: int = state.dispatched
	state.dispatched = dispatch
	var units := state.bonded_units(_cfg)
	state.dispatched = before
	return units


func test_the_card_measures_the_cost_against_the_cliff_not_against_base_damage() -> void:
	# 第一版这里断的是「基地会掉多少血」，实测下来两个分支在几乎每一波
	# 都是同一个 0（见 [method PBValuation.leak_threshold_dps] 的说明）——
	# 单服务器排队没有中间态，那个量在悬崖前没有分辨率。
	#
	# 换成富余倍数之后两个分支才真的分得开。这一条就是钉那件事：
	# **派人之后的富余必须严格小于不派**，否则代价在卡面上是看不见的。
	var state := _state_of(9)
	var plan := _plan_of(12, 3)
	var card := _card()
	card.reset(state, _cfg, plan)

	var units := PBValuation.deployed_for(state, plan.wave.element, _cfg)
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	# 和卡面一样按真实射程结构量悬崖（M3-a）。这里少传 attackers 的话，
	# 测试拿解析式排队模型算、卡面拿真战斗模型算，比的是两套战斗规则。
	var preview := PBCombatRules.build_attackers(
		units,
		plan.wave.element,
		state.atk_mult(_cfg),
		state.bond_mult(_cfg),
		PBEquipRules.unit_multipliers(units, state.equip_parts, _cfg),
		_cfg
	)
	var cliff: float = PBValuation.leak_threshold_dps(
		plan.wave, state.def_reduction(_cfg), _cfg, preview
	)
	var kept: float = PBValuation.dps_if_dispatched(state, plan.wave, units, 0, _cfg)
	var sent: float = PBValuation.dps_if_dispatched(state, plan.wave, units, need, _cfg)

	assert_gt(kept, sent, "派了人 DPS 必须掉 —— 不然这张卡上根本没有取舍")
	assert_true(card._outcome.text.contains("%.0f DPS" % cliff), "悬崖要写出来：%s" % card._outcome.text)
	assert_true(
		card._outcome.text.contains("不接 %.0f（富余 %.2f×）" % [kept, kept / cliff]),
		"不接的富余要照实写：%s" % card._outcome.text
	)
	assert_true(
		card._outcome.text.contains("接了 %.0f（富余 %.2f×）" % [sent, sent / cliff]),
		"接了的富余要照实写：%s" % card._outcome.text
	)
	# 显示精度也要够。后期两个分支挨得很近（实测第 40 波是 1.61× 对 1.55×），
	# 一位小数会把它们四舍五入成同一个数，代价就在卡面上消失了 ——
	# 这正是第一版犯的错，只是换了个地方犯。
	assert_ne("富余 %.2f×" % (kept / cliff), "富余 %.2f×" % (sent / cliff), "两个分支不能渲染成同一个字符串")


func test_the_reward_and_the_headcount_are_both_on_the_card() -> void:
	# 两个数缺一不可：只写奖励玩家不知道代价，只写人数玩家不知道值不值。
	var state := _state_of(8)
	for grade: int in PBEconomyRules.QUEST_TABLE.size():
		var plan := _plan_of(15, grade)
		var card := _card()
		card.reset(state, _cfg, plan)
		var reward: int = PBEconomyRules.quest_reward(grade, plan.wave.index)
		var need: int = PBEconomyRules.quest_cost_units(grade)
		if need > state.dispatch_available(_cfg):
			continue
		assert_true(card._head.text.contains("%d 金" % reward), "%d 级：%s" % [grade, card._head.text])
		assert_true(card._head.text.contains("需派 %d 人" % need), card._head.text)
		assert_true(
			card._head.text.contains(String(PBEconomyRules.QUEST_GRADES[grade])), card._head.text
		)


func test_it_says_there_are_too_few_people_instead_of_just_greying_out() -> void:
	# 派不出去的时候要说清是「人不够」而不是「不划算」，
	# 否则玩家会去调阵容找一个根本不存在的原因。
	#
	# **门槛口径 M3.5-i 换过一次。** 旧的是 `standby_available`（溢出到板凳上的
	# 那几个），而指令卡的「派去任务」放行的是**在场**的人 —— 两把尺子，
	# 于是会出现「已经挑了 2 个人，卡面还说待命台 0 人派不出去」。
	var state := _state_of(3)
	var plan := _plan_of(2, 4)  # SSS 要派 4 人，这个卡池只有 3 张
	var card := _card()
	card.reset(state, _cfg, plan)

	assert_lt(state.dispatch_available(_cfg), 4, "这个卡池应该凑不出 SSS 要的 4 个人")
	assert_true(card._toggle.disabled, "派不出去就不该能点")
	assert_true(card._bond.text.contains("场上只有"), card._bond.text)
	assert_true(card._bond.text.contains("派不出"), card._bond.text)
	assert_false(card.accepted(), "派不出去时不能算成已接")


func test_it_starts_unaccepted_every_wave() -> void:
	# 默认不接：没决定就是没决定。默认接的话，一个没注意到这张卡的玩家
	# 会莫名其妙在 BOSS 波掉羁绊，而他连自己付了代价都不知道。
	var state := _state_of(9)
	var card := _card()
	card.reset(state, _cfg, _plan_of(6, 2))
	assert_false(card.accepted(), "新的一波默认不接")

	card.toggle()
	assert_true(card.accepted(), "点一下应该接下")
	card.toggle()
	assert_false(card.accepted(), "再点一下应该取消")

	card.toggle()
	card.reset(state, _cfg, _plan_of(7, 2))
	assert_false(card.accepted(), "换波之后要归零 —— 上一波接了不等于这一波也接")


func test_the_toggle_emits_so_the_other_panels_can_follow() -> void:
	var state := _state_of(9)
	var card := _card()
	card.reset(state, _cfg, _plan_of(6, 2))
	watch_signals(card)
	card.toggle()
	assert_signal_emitted_with_parameters(card, "quest_toggled", [true])
