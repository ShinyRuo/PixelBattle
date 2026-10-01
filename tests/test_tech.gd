extends GutTest
## 训练科技（M12-h3）：四条近战 / 远程分线的属性词条，取代「攻击科技 ×1.06」。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _first_of(tier_is_melee: bool) -> PBUnit:
	for character: PBCharacter in _cfg.characters.all():
		if (character.reach_tier() == PBCharacter.Reach.MELEE) == tier_is_melee:
			return PBUnit.new(character)
	fail_test("名册里该既有近战也有远程")
	return null


func _stocked_state() -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	for character: PBCharacter in _cfg.characters.all():
		state.add_unit(PBUnit.new(character))
	return state


# ── 表 ──────────────────────────────────────────────────────────


func test_every_word_is_a_stat_key() -> void:
	# 行为键写进来会被 [method PBStatRules.collect] 静默丢掉 —— 配了不生效。
	for branch: StringName in PBTechRules.BRANCHES:
		assert_true(PBTechRules.PER_LEVEL.has(branch), "%s 该有每级词条" % branch)
		assert_true(PBTechRules.FOR_MELEE.has(branch), "%s 该说清加给近战还是远程" % branch)
		var words: Dictionary = PBTechRules.PER_LEVEL[branch]
		assert_false(words.is_empty(), "%s 不许是空的" % branch)
		for key: StringName in words:
			assert_true(PBStatRules.is_known(key), "%s 的 %s 必须是属性层的键" % [branch, key])
	assert_eq(PBTechRules.PER_LEVEL.size(), PBTechRules.BRANCHES.size(), "表里不许有没上架的线")


func test_melee_lines_skip_ranged_and_aim_skips_melee() -> void:
	var melee := _first_of(true)
	var ranged := _first_of(false)
	var all_five := {}
	for branch: StringName in PBTechRules.BRANCHES:
		all_five[branch] = PBTechRules.MAX_LEVEL
	var on_melee := PBTechRules.unit_mods(melee, all_five)
	var on_ranged := PBTechRules.unit_mods(ranged, all_five)
	assert_almost_eq(float(on_melee[PBStatRules.ATTACK]), 250.0, 0.001, "近战只吃训练攻击那 5×50")
	assert_true(on_melee.has(PBStatRules.DEFENCE), "训练防御加给近战")
	assert_true(on_melee.has(PBStatRules.HP_BONUS), "训练生命加给近战")
	assert_almost_eq(float(on_ranged[PBStatRules.ATTACK]), 150.0, 0.001, "远程只吃训练精准那 5×30")
	assert_false(on_ranged.has(PBStatRules.DEFENCE), "训练防御不加给远程")
	assert_false(on_ranged.has(PBStatRules.ATTACK_SPEED), "训练攻击的攻速不加给远程")


func test_levels_scale_the_words_linearly() -> void:
	var melee := _first_of(true)
	var mods := PBTechRules.unit_mods(melee, {PBTechRules.TRAIN_ATTACK: 3})
	assert_almost_eq(float(mods[PBStatRules.ATTACK]), 150.0, 0.001, "3 级 = 3 份")
	assert_almost_eq(float(mods[PBStatRules.ATTACK_SPEED]), 0.15, 0.0001, "率型也按级数累加")
	assert_true(PBTechRules.unit_mods(melee, {}).is_empty(), "一级没升就什么都不给")


# ── 接线 ────────────────────────────────────────────────────────


func test_no_training_leaves_the_unit_words_untouched() -> void:
	var state := _stocked_state()
	var units: Array[PBUnit] = [_first_of(true), _first_of(false)]
	var bare := PBEquipRules.unit_mods(units, state.equip_parts, _cfg, state.equipped)
	assert_eq(PBCombatRules.unit_mods(units, state, _cfg), bare, "没升科技时只剩装备那一份")


func test_training_reaches_the_attackers_through_the_shared_fold() -> void:
	# 走 [method PBCombatRules.unit_mods] —— 全部折叠点拿的都是这一份。
	var state := PBRunSim.new_state(_cfg)
	var units: Array[PBUnit] = [_first_of(true), _first_of(false)]
	var before := PBCombatRules.build_attackers(
		units,
		PBElement.Type.PHYSICAL,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		{},
		{},
		PBCombatRules.unit_mods(units, state, _cfg)
	)
	state.training[PBTechRules.TRAIN_ATTACK] = 2
	state.training[PBTechRules.TRAIN_HP] = 5
	var after := PBCombatRules.build_attackers(
		units,
		PBElement.Type.PHYSICAL,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		{},
		{},
		PBCombatRules.unit_mods(units, state, _cfg)
	)
	assert_gt(after[0].attack, before[0].attack, "近战的攻击力该真的涨")
	assert_gt(after[0].attack_speed, before[0].attack_speed, "近战的攻速该真的涨")
	assert_gt(after[0].max_hp, before[0].max_hp, "近战的生命该真的涨")
	assert_eq(after[1].attack, before[1].attack, "远程一分都不该吃到近战那三条")
	assert_eq(after[1].max_hp, before[1].max_hp, "远程一分都不该吃到近战那三条")


# ── 花钱 ────────────────────────────────────────────────────────


func test_buying_raises_one_line_and_stops_at_max() -> void:
	var state := PBRunSim.new_state(_cfg)
	state.gold = 1000000
	var strategy := PBStratBalanced.new()
	for _i: int in PBTechRules.MAX_LEVEL:
		assert_true(strategy.buy_tech(state, PBTechRules.TRAIN_HP, _cfg), "没满级该买得动")
	assert_false(strategy.buy_tech(state, PBTechRules.TRAIN_HP, _cfg), "满级之后该买不动")
	assert_eq(state.training_level(PBTechRules.TRAIN_HP), PBTechRules.MAX_LEVEL, "停在满级")
	assert_eq(state.training_level(PBTechRules.TRAIN_AIM), 0, "别的线不该跟着动")


func test_valuation_puts_the_training_back_exactly() -> void:
	# 估值是「改一下、量一次、改回来」。0 级要还原成**没有这个键**，
	# 否则 [method PBCombatRules.unit_mods] 那条空表快路径从此失效。
	var state := _stocked_state()
	var base: float = PBValuation.mean_dps(state, _cfg)
	var gain: float = 0.0
	for branch: StringName in PBTechRules.BRANCHES:
		gain += PBValuation.tech_gain(state, _cfg, branch, base)
	assert_true(state.training.is_empty(), "量完该原样放回")
	assert_gt(gain, 0.0, "加攻击力的那两条该量得出战力")
	state.training[PBTechRules.TRAIN_AIM] = 2
	PBValuation.tech_gain(state, _cfg, PBTechRules.TRAIN_AIM, base)
	assert_eq(state.training, {PBTechRules.TRAIN_AIM: 2}, "已有等级也要原样放回")


# ── 指令卡 ──────────────────────────────────────────────────────


func test_the_shelves_fit_the_card() -> void:
	var cells: int = PBCommandCard.COLUMNS * PBCommandCard.ROWS
	# 首页：六项 + 科技 ▸ + 重抽任务 + 开打。
	assert_lte(PBShopLabels.BASE_KINDS.size() + 3, cells, "首页要装得下")
	assert_lte(PBShopLabels.TRAINING_KINDS.size() + 1, cells, "科技页要装得下返回键")
	var both: Array[StringName] = []
	both.append_array(PBShopLabels.BASE_KINDS)
	both.append_array(PBShopLabels.TRAINING_KINDS)
	assert_eq(PBShopLabels.KINDS, both, "全部购买项 = 两页合起来")
	for kind: StringName in PBShopLabels.TRAINING_KINDS:
		# [PBBattleView] 的兜底是「去掉 tech_ 前缀交给 buy_tech」。
		var branch := StringName(String(kind).trim_prefix("tech_"))
		assert_true(PBTechRules.is_branch(branch), "%s 去掉前缀要是一条训练线" % kind)
	assert_eq(PBShopLabels.TRAINING_KINDS.size(), PBTechRules.BRANCHES.size(), "每条线都上架")


func test_the_tech_page_opens_closes_and_resets() -> void:
	var card := PBCommandCard.new()
	add_child_autofree(card)
	var state := _stocked_state()
	state.gold = 100000
	var plan := PBRunSim.begin_wave(state, _cfg, PBRngStreams.new(7))
	var base := PBSelection.of_kind(PBSelection.Kind.BASE)
	card.refresh(base, state, _cfg, plan)
	var page := _slot_of(card, PBCommandCard.CMD_TECH_PAGE)
	assert_gte(page, 0, "首页该有「科技 ▸」")
	assert_gte(_slot_of(card, PBCommandCard.CMD_START), 0, "首页该有开打")

	watch_signals(card)
	card._on_slot_pressed(page)
	assert_signal_not_emitted(card, "command", "翻页不许往外发 —— 发出去会被当成一条科技去买")
	for kind: StringName in PBShopLabels.TRAINING_KINDS:
		assert_gte(_slot_of(card, kind), 0, "科技页该摆着 %s" % kind)
	assert_eq(_slot_of(card, PBCommandCard.CMD_START), -1, "科技页不摆开打")

	card._on_slot_pressed(_slot_of(card, PBCommandCard.CMD_BACK))
	assert_gte(_slot_of(card, PBCommandCard.CMD_START), 0, "返回之后开打回来了")

	card._on_slot_pressed(_slot_of(card, PBCommandCard.CMD_TECH_PAGE))
	card.refresh(PBSelection.of_kind(PBSelection.Kind.BEAST), state, _cfg, plan)
	card.refresh(base, state, _cfg, plan)
	assert_gte(_slot_of(card, PBCommandCard.CMD_START), 0, "换过选中对象再回来该是首页")


func _slot_of(card: PBCommandCard, id: StringName) -> int:
	for i: int in PBCommandCard.COLUMNS * PBCommandCard.ROWS:
		if card.command_at(i) == id:
			return i
	return -1
