extends GutTest
## [PBQuestCard] 的测试。M1-d。
##
## §06 的验收原话是「**派了羁绊掉几档，准备阶段能一眼看出**」。
## 这一组断言就是照那句话逐条对的 —— 卡面缺哪一格，哪条就红。
##
## ## M5-6：一半断言从标签搬到了说明卡
##
## 这块面板从 548 像素宽掉到 100（[constant PBLayout.E_QUEST]），
## 三行散文一行都写不下，整句搬进了 [method PBQuestCard.tip_body]。
## 所以「掉哪几组羁绊」「两个分支各剩多少 DPS」这些断言现在对着
## 那几个组句函数，而不是面板上的 [Label] ——
## **要验的本来就是那句话在不在，不是它画在哪一格**。
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


## 造一个**真的凑齐了一组羁绊**的局面。M6-j。
##
## 在场名单没挑过时按仓库顺序取前 N（[method PBRunState.field_units]），
## 所以同系的那几个必须排在最前面 —— 排在后面的话他们进不了在场名单，
## 羁绊照样是零，而断言的失败信息会指向「卡面没写」这个假原因。
##
## 挑属性型而不是小队型：属性型只要「同系四个人」，
## 不依赖角色表里正好有哪几个人，角色表增删时它不会悄悄失效。
func _state_with_a_bond(count: int) -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	var by_element: Dictionary = {}
	for character: PBCharacter in _cfg.characters.all():
		if not by_element.has(character.element):
			by_element[character.element] = [] as Array[PBCharacter]
		var bucket: Array = by_element[character.element]
		bucket.append(character)
	var picked: Array[PBCharacter] = []
	for element: Variant in by_element:
		var bucket: Array = by_element[element]
		if bucket.size() >= 4 and picked.is_empty():
			for i: int in 4:
				picked.append(bucket[i])
	assert_false(picked.is_empty(), "角色表里得有一个属性凑得满四个人")
	for character: PBCharacter in _cfg.characters.all():
		if picked.size() >= count:
			break
		if not picked.has(character):
			picked.append(character)
	for character: PBCharacter in picked:
		state.add_unit(PBUnit.new(character))
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
	# **M6-j 起这个局面要专门凑一组羁绊出来。** 羁绊改成全有或全无之后
	# （见 [PBBond]），按角色表顺序取 7 张卡一组都凑不齐 ——
	# 于是「派人会掉哪一组」这条断言没有东西可掉，测不到它要测的分支。
	var state := _state_with_a_bond(7)
	var plan := _plan_of(6, 2)  # A 级，派 3 人
	var card := _card()
	card.reset(state, plan)

	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	var kept := PBBondRules.active_tiers(_bonded_with(state, 0), _cfg.bonds)
	var sent := PBBondRules.active_tiers(_bonded_with(state, need), _cfg.bonds)

	var broken: Array[PBBond] = []
	for bond: PBBond in _cfg.bonds.all():
		if int(sent.get(bond.id, 0)) < int(kept.get(bond.id, 0)):
			broken.append(bond)
	assert_false(broken.is_empty(), "这个局面派 %d 人应该真的会掉档，否则测不到东西" % need)

	var body: String = card.tip_body(state, _cfg, plan)
	for bond: PBBond in broken:
		assert_true(
			body.contains(PBLocale.of_bond(bond)),
			"掉档的羁绊要点名写出来（缺 %s）：%s" % [PBLocale.of_bond(bond), body]
		)
	assert_true(body.contains("战力 −"), "还要给出对应的战力损失：%s" % body)


func test_the_card_never_shows_a_raw_key_instead_of_a_name() -> void:
	# 羁绊名走 [PBLocale]。语言表缺一条时它会回退到 key，
	# 那在文档注释里是有意为之，但**摆到卡面上就是 bug** ——
	# 玩家会看到「bond.xxx 3→2 档」。
	var state := _state_of(7)
	var plan := _plan_of(6, 2)
	var card := _card()
	card.reset(state, plan)
	var body: String = card.tip_body(state, _cfg, plan)
	assert_false(body.contains("bond."), "说明卡漏出了 name_key：%s" % body)


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


func test_the_card_shows_both_branches_of_the_dispatch_cost() -> void:
	# 卡面必须把**两个分支**都写出来。只写「接了还剩多少」的话玩家没有参照物，
	# 那个数字读不出是多是少；两个数并排摆着，减法才做得成。
	#
	# 断的是「派人之后必须严格更低」—— 相等就说明代价在卡面上是看不见的。
	var state := _state_of(9)
	var plan := _plan_of(12, 3)
	var card := _card()
	card.reset(state, plan)

	var units := PBValuation.deployed_for(state, plan.wave.element, _cfg)
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	var kept: float = PBValuation.dps_if_dispatched(state, plan.wave, units, 0, _cfg)
	var sent: float = PBValuation.dps_if_dispatched(state, plan.wave, units, need, _cfg)

	assert_gt(kept, sent, "派了人 DPS 必须掉 —— 不然这张卡上根本没有取舍")
	var body: String = card.tip_body(state, _cfg, plan)
	assert_true(body.contains("不接 %.0f DPS" % kept), "不接那一支要照实写：%s" % body)
	assert_true(body.contains("接了 %.0f DPS" % sent), "接了那一支要照实写：%s" % body)
	# 两个分支不能渲染成同一个字符串，否则「有取舍」这件事只存在于代码里。
	assert_ne("%.0f" % kept, "%.0f" % sent, "两个分支不能四舍五入成同一个数")


func test_refreshing_the_card_never_runs_a_battle() -> void:
	# **准备阶段不许算战斗。** 这张卡在每一次 `_refresh_panels` 里都刷新一遍，
	# 而那是每一次点击都会走的路 —— 这里的每一毫秒都直接变成点击延迟。
	#
	# 曾经有一行「本波打空要 x DPS」走 [method PBValuation.leak_threshold_dps]，
	# 它二分 32 次、每次跑完一整场仗，实测 457 毫秒。表现是
	# 「抽到第一张卡之后，点开仓库要等半秒」——**不报错，也不会被别的测试抓到**，
	# 因为算出来的数完全正确，只是贵了三个数量级。
	#
	# 阈值放到 100 毫秒是有意的宽：这里要挡的是「又往里塞了一个战斗模拟」
	# 这种量级的回归，不是几毫秒的抖动。慢机器上也不该误报。
	var state := _state_of(12)
	var plan := _plan_of(12, 3)
	var card := _card()
	card.reset(state, plan)  # 先热一遍，别把首次加载算进去

	var started: int = Time.get_ticks_usec()
	for _i: int in 3:
		card.refresh(PBSelection.new(), state, plan)
	var each: float = float(Time.get_ticks_usec() - started) / 3000.0
	assert_lt(each, 100.0, "刷新一次任务卡花了 %.1f 毫秒 —— 里面多半又跑起战斗了" % each)

	# 说明卡不在每次点击的路上（要玩家自己点「详情」），但它一样不许跑战斗 ——
	# 那一行悬崖当初就藏在这几句里。
	started = Time.get_ticks_usec()
	for _i: int in 3:
		card.tip_body(state, _cfg, plan)
	var tip: float = float(Time.get_ticks_usec() - started) / 3000.0
	assert_lt(tip, 100.0, "组一次说明卡花了 %.1f 毫秒 —— 里面多半又跑起战斗了" % tip)


func test_the_reward_and_the_headcount_are_both_on_the_card() -> void:
	# 两个数缺一不可：只写奖励玩家不知道代价，只写人数玩家不知道值不值。
	var state := _state_of(8)
	for grade: int in PBEconomyRules.QUEST_TABLE.size():
		var plan := _plan_of(15, grade)
		var card := _card()
		card.reset(state, plan)
		var reward: int = PBEconomyRules.quest_reward(grade, plan.wave.index)
		var need: int = PBEconomyRules.quest_cost_units(grade)
		if need > state.dispatch_available(_cfg):
			continue
		assert_true(card._terms.text.contains("%d 金" % reward), "%d 级：%s" % [grade, card._terms.text])
		# M6-k 压成「需 N · 已 M」——面板从 142 高掉到 58，那一行要和奖励并排。
		assert_true(card._need.text.contains("需 %d" % need), card._need.text)
		assert_true(
			card._head.text.contains(String(PBEconomyRules.QUEST_GRADES[grade])), card._head.text
		)


func test_the_panel_says_pass_or_fail_before_the_wave_starts() -> void:
	# **人数不符是一次有代价的失误**：那几个人照样离场，只是拿不到奖励。
	# 把它留到结算才说等于让玩家事后才知道自己错了 ——
	# 所以三种状态都要在开打**之前**读得出来。
	var state := _state_of(9)
	# 1 号是 B 级 —— `QUEST_TABLE` 里要 2 个人（2 号的 A 级要 3 个）。
	var plan := _plan_of(6, 1)
	var card := _card()
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	assert_eq(need, 2, "这一档该要 2 个人，否则下面三支测不全")

	card.reset(state, plan)
	assert_true(card._away.text.contains("未派"), card._away.text)
	assert_false(PBQuestCard.is_done(state, plan), "空着不算完成")

	state.dispatch_manual.append(state.roster.values()[0].key())
	card.reset(state, plan)
	assert_true(card._away.text.contains("失败"), "差一个就得当场写明失败：%s" % card._away.text)
	assert_false(PBQuestCard.is_done(state, plan), "1/2 不算完成")

	state.dispatch_manual.append(state.roster.values()[1].key())
	card.reset(state, plan)
	assert_true(card._away.text.contains("可完成"), card._away.text)
	assert_true(PBQuestCard.is_done(state, plan), "拖满了就算接下了")


func test_too_many_is_a_failure_too() -> void:
	# **槽位比需求多是有意的**（[constant PBEconomyRules.QUEST_SLOTS] = 4）。
	# 槽数跟着需求走的话玩家塞不进多余的人，「人数不符」这条判定
	# 就只剩「塞不满」一种，塞多了不可能发生 —— 那等于半条规则。
	var state := _state_of(9)
	var plan := _plan_of(6, 1)  # B 级，要 2 个人
	var card := _card()
	for i: int in 3:
		state.dispatch_manual.append(state.roster.values()[i].key())
	card.reset(state, plan)
	assert_false(PBQuestCard.is_done(state, plan), "3 个人去做一个 2 人的任务也是失败")
	assert_true(card._away.text.contains("失败"), card._away.text)
	assert_gt(PBEconomyRules.QUEST_SLOTS, 2, "槽位必须多于本波需求，否则塞不进第三个")


func test_all_four_slots_are_always_on_screen() -> void:
	# 空槽也要画出来。M5-6 那一版只显示派了几个就画几个 ——
	# 判定改成看人数之后，「有几个槽、现在占了几个」成了**必须看得见**的信息，
	# 否则「人数不符」是一条无处可读的规则。
	var state := _state_of(9)
	var card := _card()
	card.reset(state, _plan_of(6, 2))
	var tiles := card.find_children("", "PBUnitTile", true, false)
	assert_eq(tiles.size(), PBEconomyRules.QUEST_SLOTS, "四个槽一次建满")
	for tile: PBUnitTile in tiles:
		assert_true(tile.visible, "空槽也得摆在那儿")
		assert_null(tile.unit, "一个人都没派的时候四个都该是空的")
