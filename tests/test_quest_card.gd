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
	_cfg = PBSimConfig.new()


func _state_of(count: int, maxed_pop: bool = false) -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	if maxed_pop:
		state.tech_pop = _cfg.tech_pop_max
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for _i: int in count:
		state.add_unit(
			PBUnit.new(
				rng.randi_range(0, 5) as PBElement.Type,
				rng.randi_range(0, 3) as PBUnit.Rarity,
				rng.randi_range(0, _cfg.characters_per_bucket - 1)
			)
		)
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


func test_the_card_spells_out_how_many_bond_tiers_dispatch_costs() -> void:
	# §06 的验收原话。倍率不能代替档数 —— 玩家看不出自己离上限还有多远。
	var state := _state_of(7)
	var plan := _plan_of(6, 2)  # A 级，派 3 人
	var card := _card()
	card.reset(state, _cfg, plan)

	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	var before: int = state.bonded_count_for(state.roster.size(), 0, _cfg)
	var after: int = state.bonded_count_for(state.roster.size(), need, _cfg)
	assert_gt(before, after, "这个卡池还没到羁绊上限，派人一定掉档")
	assert_true(
		card._bond.text.contains("%d → %d 档" % [before, after]), "羁绊档数要写出来：%s" % card._bond.text
	)
	assert_true(card._bond.text.contains("掉 %d 档" % (before - after)), card._bond.text)
	assert_true(card._bond.text.contains("战力 −"), "还要给出对应的战力损失：%s" % card._bond.text)


func test_a_deep_bench_makes_dispatch_free_and_the_card_says_so() -> void:
	# 板凳深到超过 bond_unit_cap 之后，被派走的人本来就不在羁绊计数里 ——
	# **这一波派遣是白捡的钱**。这是整张卡上最反直觉、也最值钱的一格信息，
	# 漏掉它玩家会一直以为任务永远要付代价。
	# 抽 40 次是为了凑够唯一卡 —— 重复卡在仓库里会合并（§08：同卡 3 张升 1 星），
	# 抽 20 次只有十几张，够不到上限。
	var state := _state_of(40, true)
	var plan := _plan_of(30, 4)  # SSS，派 4 人，最贵的一档
	var card := _card()
	card.reset(state, _cfg, plan)

	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	assert_gte(state.roster.size() - need, _cfg.bond_unit_cap, "派完之后仍要在羁绊上限之上")
	assert_eq(
		state.bonded_count_for(state.roster.size(), need, _cfg),
		state.bonded_count_for(state.roster.size(), 0, _cfg),
		"卡池过了上限，派 %d 个人不该掉档" % need
	)
	assert_true(card._bond.text.contains("不变"), "免费的时候要明说：%s" % card._bond.text)
	assert_true(card._bond.text.contains("上限 %d" % _cfg.bond_unit_cap), card._bond.text)


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
	var cliff: float = PBValuation.leak_threshold_dps(plan.wave, state.def_reduction(_cfg), _cfg)
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
		if need > state.standby_available(_cfg):
			continue
		assert_true(card._head.text.contains("%d 金" % reward), "%d 级：%s" % [grade, card._head.text])
		assert_true(card._head.text.contains("需派 %d 人" % need), card._head.text)
		assert_true(
			card._head.text.contains(String(PBEconomyRules.QUEST_GRADES[grade])), card._head.text
		)


func test_it_says_the_bench_is_too_thin_instead_of_just_greying_out() -> void:
	# 派不出去的时候要说清是「人不够」而不是「不划算」，
	# 否则玩家会去调阵容找一个根本不存在的原因。
	var state := _state_of(3)
	var plan := _plan_of(2, 4)  # SSS 要派 4 人，这个卡池连待命台都没坐上
	var card := _card()
	card.reset(state, _cfg, plan)

	assert_eq(state.standby_available(_cfg), 0, "这个卡池待命台应该是空的")
	assert_true(card._toggle.disabled, "派不出去就不该能点")
	assert_true(card._bond.text.contains("派不出去"), card._bond.text)
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
