extends GutTest
## 玩家自己挑派谁去做任务（§06，M3.5-g）。
##
## ## 这个文件守的是三件事
##
## 1. **一个人都不挑时，和 M2 到 M3.5-f 的末尾规则一字不差** ——
##    脚本流派一个字都不填，全部既有配平数字不动
## 2. **挑够了才算数。** 名单长度对不上就整份作废退回末尾规则，
##    因为 [method PBValuation.dps_if_dispatched] 那一路只知道「派几个」
## 3. **派走的人不上场。** 漏了那一步他会既在做任务又在打仗，两边都不报错
##
## M3.5-i 又加了三条，各钉住一个真的发生过的 bug。它们的共同形状是
## **同一件事有两把尺子**：一处判断「行不行」，另一处执行，两处读的名单不同 ——
## 表现全是「界面说行，点下去没反应」或者「同一个人同时出现在两排」，
## 而两种都不报错。

const BATTLE_SCENE := "res://scenes/battle.tscn"

var _cfg: PBSimConfig
var _rng: PBRngStreams
var _wave_rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = PBRngStreams.new(20260830)
	_wave_rng = RandomNumberGenerator.new()
	_wave_rng.seed = 20260830


func _stocked_state() -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	for character: PBCharacter in _cfg.characters.all():
		state.add_unit(PBUnit.new(character))
	PBStratBalanced.new().bring_to_field(state, _cfg)
	return state


## 一局停在准备阶段的真画面，手上有 [param cards] 张卡。
##
## 界面那三条只能这么测：**它们量的正是「按钮怎么写」和「点下去做什么」
## 对不对得上**，而那两半分别住在 [PBCommandCard] 和 [PBBattleView] 里。
func _view_with(cards: int) -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = 20260830
	root.auto_play = false
	add_child_autofree(root)
	await wait_physics_frames(2)
	for character: PBCharacter in root._cfg.characters.all().slice(0, cards):
		root._state.add_unit(PBUnit.new(character))
	root._refresh_panels()
	return root


func _deploy_of(root: Node2D) -> Array[PBUnit]:
	return root._strategy.deploy(root._state, root._plan.wave, root._cfg)


func test_with_nobody_picked_it_is_still_the_old_tail_rule() -> void:
	# **数值回归的锚。** 手动挑人是纯加法进来的，没人挑时结果必须一模一样。
	var state := _stocked_state()
	state.dispatched = 3
	var pool := state.field_units(_cfg)
	var away := state.dispatch_picks(_cfg)
	assert_eq(away.size(), 3, "派了几个就该报几个")
	for i: int in 3:
		assert_eq(away[i], pool[pool.size() - 3 + i], "没人挑时仍该是板凳末尾那几个")


func test_a_full_pick_wins_over_the_tail_rule() -> void:
	var state := _stocked_state()
	var pool := state.field_units(_cfg)
	state.dispatched = 2
	# 挑排最前面的两个 —— 末尾规则绝不会选中他们。
	for unit: PBUnit in [pool[0], pool[1]]:
		assert_true(PBShopRules.toggle_dispatch(state, unit, 2, _cfg), "在场的人该挑得上")
	var away := state.dispatch_picks(_cfg)
	assert_true(away.has(pool[0]) and away.has(pool[1]), "挑了谁就该派谁")
	assert_false(away.has(pool[pool.size() - 1]), "板凳末尾这一次不该被抓去")


func test_a_half_finished_pick_falls_back_instead_of_going_short() -> void:
	# 名单只在长度刚好对上时才算数：估值那一路是临时改 `dispatched` 再问一遍，
	# 它只知道「派几个」。半份名单生效的话那条路会拿着人数对不上的名单去算，
	# 而结果只是「卡面上的数字略微不对」，不报错。
	var state := _stocked_state()
	var pool := state.field_units(_cfg)
	state.dispatched = 3
	PBShopRules.toggle_dispatch(state, pool[0], 3, _cfg)
	var away := state.dispatch_picks(_cfg)
	assert_eq(away.size(), 3, "还是要派够 3 个")
	assert_false(away.has(pool[0]), "只挑了 1 个，整份作废退回末尾规则")


func test_the_valuation_path_still_gets_a_straight_answer() -> void:
	# 估值临时把 `dispatched` 改成别的数再问一遍。人数和名单对不上时
	# 必须干脆地退回末尾规则，而不是给一份长度不对的名单。
	var state := _stocked_state()
	var pool := state.field_units(_cfg)
	state.dispatched = 2
	PBShopRules.toggle_dispatch(state, pool[0], 2, _cfg)
	PBShopRules.toggle_dispatch(state, pool[1], 2, _cfg)
	for count: int in [1, 3, 4]:
		assert_eq(
			state.dispatch_picks(_cfg, count).size(), count, "问派 %d 个就该答 %d 个" % [count, count]
		)


func test_who_still_counts_is_always_the_complement() -> void:
	# 「谁失效了」和「界面上显示谁在做任务」对不上的话，玩家一眼看得出
	# （头像亮着但羁绊掉了），代码里却不报错。
	var state := _stocked_state()
	var pool := state.field_units(_cfg)
	state.dispatched = 2
	PBShopRules.toggle_dispatch(state, pool[0], 2, _cfg)
	PBShopRules.toggle_dispatch(state, pool[1], 2, _cfg)
	var counted := state.bonded_units(_cfg)
	var away := state.dispatch_picks(_cfg)
	assert_eq(counted.size() + away.size(), pool.size(), "两半该正好拼回在场名单")
	for unit: PBUnit in away:
		assert_false(counted.has(unit), "被派出去的不该还在算羁绊")


func test_a_warehouse_card_can_be_sent_even_with_the_field_full() -> void:
	# 人口满时这条路**静默失败**：卡弹回来，没有任何解释（M5-13 修）。
	# 而从战场上拖过去却做得到 —— 同一件事两条路，一条通一条不通。
	#
	# 死结在顺序上：座位数 `field_slots` = 人口 + 已经派出去几个，
	# 所以在这一笔派遣记下来之前，多出来的那一格还不存在。
	var state := _stocked_state()
	var strategy := PBStratBalanced.new()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var roster := strategy.deploy(state, plan.wave, _cfg)
	assert_eq(roster.size(), state.field_slots(_cfg), "前提：人口是满的")
	var stashed: PBUnit = null
	for unit: PBUnit in state.all_units():
		if not roster.has(unit):
			stashed = unit
			break
	assert_not_null(stashed, "前提：卡池比人口大，仓库里还有人")

	PBCardMoves.move(
		state,
		strategy,
		plan,
		stashed,
		PBUnitTile.ZONE_STASH,
		PBUnitTile.ZONE_QUEST,
		PBCardMoves.NO_SPOT,
		_cfg
	)
	assert_true(state.dispatch_manual.has(stashed.key()), "人口满也该进得了任务栏")
	# 「记了派遣」和「进 field 名单」是同一件事的两半（见
	# [method PBCardMoves._send_to_quest]）：只做前一半的话，
	# `dispatch_picks` 在 `field_units` 里找不到他，**整份名单作废退回末尾规则**。
	assert_true(state.field_units(_cfg).has(stashed), "而且要同时进 field 名单")
	state.dispatched = state.dispatch_manual.size()
	assert_true(state.dispatch_picks(_cfg).has(stashed), "结算时点得到他")
	assert_false(state.bonded_units(_cfg).has(stashed), "他这一波不算羁绊")


func test_the_dispatch_command_does_what_dragging_there_does() -> void:
	# 指令卡上那一格在 M5-13 之前直接调 [method PBShopRules.toggle_dispatch]，
	# **只改了两处状态里的一处** —— 于是「拖得进但按不进」这种不一致
	# 有了滋生的地方，而它不报错。
	var dragged := _sent_by(true)
	var pressed := _sent_by(false)
	assert_eq(pressed[0], dragged[0], "两条路该记下同一份派遣名单")
	assert_eq(pressed[1], dragged[1], "field 名单也该一模一样")


## 把仓库里第一个人送进任务栏：[param drag] 为真走拖放，否则走指令卡那一格。
## 返回 `[派遣名单, field 名单]`。
func _sent_by(drag: bool) -> Array:
	var state := _stocked_state()
	var strategy := PBStratBalanced.new()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var roster := strategy.deploy(state, plan.wave, _cfg)
	var stashed: PBUnit = null
	for unit: PBUnit in state.all_units():
		if not roster.has(unit):
			stashed = unit
			break
	if drag:
		PBCardMoves.move(
			state,
			strategy,
			plan,
			stashed,
			PBUnitTile.ZONE_STASH,
			PBUnitTile.ZONE_QUEST,
			PBCardMoves.NO_SPOT,
			_cfg
		)
	else:
		PBCardMoves.toggle_quest(state, strategy, plan, stashed, _cfg)
	return [state.dispatch_manual.duplicate(), state.field.duplicate()]


func test_the_pick_stops_at_the_headcount_the_quest_asks_for() -> void:
	var state := _stocked_state()
	var pool := state.field_units(_cfg)
	for i: int in 2:
		assert_true(PBShopRules.toggle_dispatch(state, pool[i], 2, _cfg), "前两个挑得上")
	assert_false(PBShopRules.toggle_dispatch(state, pool[2], 2, _cfg), "只要 2 人时第 3 个该挑不上")
	# 取消永远做得到 —— 满了之后换人的唯一出路。
	assert_true(PBShopRules.toggle_dispatch(state, pool[0], 2, _cfg), "再点一次是取消")
	assert_true(PBShopRules.toggle_dispatch(state, pool[2], 2, _cfg), "腾出位置之后换得了人")


func test_a_dispatched_starter_does_not_also_fight() -> void:
	# **玩家可以派一个出战席上的人去做任务。** 那是「要钱还是要战力」的强化版，
	# 但他这一波就不该再出现在战场上 —— 漏掉这一步的表现是
	# 「既在做任务又在打仗」，而两边都不报错。
	var state := _stocked_state()
	var strategy := PBStratBalanced.new()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var deployed := strategy.deploy(state, plan.wave, _cfg)
	var star: PBUnit = deployed[0]
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	assert_true(PBShopRules.toggle_dispatch(state, star, need, _cfg), "出战席上的人也派得出去")
	for unit: PBUnit in state.field_units(_cfg):
		if state.dispatch_manual.size() >= need:
			break
		if unit != star:
			PBShopRules.toggle_dispatch(state, unit, need, _cfg)

	PBRunSim.lock_plan(state, plan, deployed, true, _cfg)
	assert_true(state.dispatched_ids.has(star.key()), "他应该真的被派出去了")
	assert_false(plan.deployed.has(star), "被派走的人不该还在上场名单里")
	for unit: PBUnit in plan.deployed:
		assert_false(state.dispatched_ids.has(unit.key()), "上场名单里不该有任何一个出任务的人")


func test_the_quest_slots_keep_their_people_next_wave() -> void:
	# 派遣的语义是「**这个人**去做任务」，不是「这一波去做任务」（M5-12）。
	# 一波一清的话，玩家一张卡都没动过，人却自己回到了战场上。
	var state := _stocked_state()
	var strategy := PBStratBalanced.new()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	for unit: PBUnit in state.field_units(_cfg):
		PBShopRules.toggle_dispatch(state, unit, need, _cfg)
	var picked := state.dispatch_manual.duplicate()
	assert_false(picked.is_empty(), "前提：真往任务栏里放了人")
	PBRunSim.lock_plan(state, plan, strategy.deploy(state, plan.wave, _cfg), true, _cfg)
	PBRunSim.settle_wave(state, plan, PBRunSim.resolve_battle(plan, 0.0, _cfg), _cfg, _rng)
	assert_eq(state.dispatch_manual, picked, "结算之后他们还站在任务栏里")
	assert_eq(state.dispatched, 0, "但这一波的派遣人数该清零")


func test_a_quest_slot_frees_up_when_that_card_is_gone() -> void:
	# 留着一个已经不在卡池里的 key，[method PBRunState.field_slots]
	# 会永远为一个不存在的人多留一个位置 —— 玩家看到的是
	# 「人口那一格明明还有空位，却怎么也拖不上去」。
	var state := _stocked_state()
	var strategy := PBStratBalanced.new()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	var going: PBUnit = state.field_units(_cfg)[0]
	assert_true(PBShopRules.toggle_dispatch(state, going, need, _cfg), "先把他派出去")
	PBRunSim.lock_plan(state, plan, strategy.deploy(state, plan.wave, _cfg), true, _cfg)
	state.roster.erase(going.key())
	PBRunSim.settle_wave(state, plan, PBRunSim.resolve_battle(plan, 0.0, _cfg), _cfg, _rng)
	assert_false(state.dispatch_manual.has(going.key()), "卡没了，槽也该空出来")


# ── 两把尺子（M3.5-i 修的三个 bug）────────────────────────────


func test_whoever_the_command_card_lets_you_pick_the_quest_card_lets_you_send() -> void:
	# **真的发生过**：开局 3 张卡、出战席 4 格，玩家在指令卡上挑得动两个人去做任务，
	# 任务卡却写着「待命台只有 0 人，派不出去」并且按钮是灰的。
	#
	# 根因是两把尺子：指令卡的门槛是「在不在场」，任务卡的门槛是
	# `standby_available`（卡池 − 出战席空位 = 3 − 4，钳到 0）。
	# 在派遣只能派板凳的年代它们不冲突；玩家能钦定出战席上的人之后就冲突了。
	var state := PBRunSim.new_state(_cfg)
	for character: PBCharacter in _cfg.characters.all().slice(0, 3):
		state.add_unit(PBUnit.new(character))
	PBStratBalanced.new().bring_to_field(state, _cfg)
	assert_lt(state.roster.size(), state.open_slots(_cfg), "要的正是「卡比位子少」这个局面")

	var offered: int = 0
	for unit: PBUnit in state.all_units():
		if PBShopRules.toggle_dispatch(state, unit, 2, _cfg):
			offered += 1
	assert_eq(offered, 2, "指令卡该放行两个人")
	assert_gte(state.dispatch_available(_cfg), 2, "指令卡放行的，任务卡就必须派得出 —— 同一把尺子")


func test_the_deploy_command_matches_what_pressing_it_does() -> void:
	# **真的发生过**：「派上场」点了没反应。
	#
	# 按钮文字读的是 `state.lineup`（**手排**名单，自动模式下恒为空），
	# 于是一个已经自动上场的人被写成「派上场」；点下去
	# [method PBBattleView._set_on_field] 读的是真名单、发现他已经在里面，直接返回。
	var root: Node2D = await _view_with(3)
	var star: PBUnit = _deploy_of(root)[0]
	# M6-h 之后名单是**系统替玩家维护**的（[member PBRunState.lineup_manual]
	# 为 true、[member PBRunState.lineup_by_hand] 仍为 false），
	# 而那个 bug 的前提只是「玩家还没亲手动过」——它照样成立。
	assert_false(root._state.lineup_by_hand, "这一局玩家还没亲手排过 —— 复现那个 bug 的前提")
	root._select(PBSelection.Kind.UNIT, star.key())

	assert_eq(root._command.command_at(1), PBCommandCard.CMD_BENCH, "已经在场上的人该给「收回仓库」")
	var before: int = _deploy_of(root).size()
	root._on_command(PBCommandCard.CMD_BENCH)
	assert_eq(_deploy_of(root).size(), before - 1, "点下去必须真的少一个人")
	assert_false(_deploy_of(root).has(star), "而且少的是他")


func test_a_dispatched_ninja_leaves_the_deploy_row_right_away() -> void:
	# **真的发生过**：派去做任务的忍者还站在出战席那一排上。
	#
	# 过滤只发生在 [method PBRunSim.lock_plan]，也就是「点了开打他才消失」。
	# 在那之前他同时出现在出战席和出任务两排，而他只可能在一处 ——
	# 指令卡和装备栏也跟着按「他在打这一波」算。
	var root: Node2D = await _view_with(4)
	var star: PBUnit = _deploy_of(root)[0]
	root._select(PBSelection.Kind.UNIT, star.key())
	root._on_command(PBCommandCard.CMD_DISPATCH)

	var away: Array[PBUnit] = PBFieldRoster.dispatch_preview(root._state)
	assert_true(away.has(star), "他该出现在出任务那一排")
	assert_false(root._fighting_now(away).has(star), "就不该同时还在出战席那一排")


func test_someone_on_a_quest_does_not_eat_a_population_slot() -> void:
	# **玩家报的那一条**（M5-9）：「人口只代表出战人口，现在把出任务的
	# 也算进去了」。派两个人出去 = 这一波少两个打手**且补不上**，
	# 而仓库里明明还站着人 —— 他看到的是「人口 4，场上只有 2 个，还加不进去」。
	#
	# 派遣的代价因此回到 §06 说的那一条：**掉羁绊**。
	# 「少一个打手」那半是可以用仓库里的人补回来的。
	var state := _stocked_state()
	var room: int = state.open_slots(_cfg)
	assert_eq(state.field_slots(_cfg), room, "没人出任务时两个数必须相等")

	var going: PBUnit = state.field_units(_cfg)[0]
	PBShopRules.toggle_dispatch(state, going, PBEconomyRules.QUEST_SLOTS, _cfg)
	assert_eq(state.field_slots(_cfg), room + 1, "派一个出去就该空出一格")
	assert_eq(state.open_slots(_cfg), room, "但人口本身不变 —— 那是「几个人在打」")


func test_the_scripted_player_still_sees_exactly_the_old_capacity() -> void:
	# 上面那条是**只在玩家钦定名单非空时**才生效的（[member
	# PBRunState.dispatch_manual]）。脚本流派恒定走 [member PBRunState.dispatched]
	# 的末尾规则，那一路一个字节都不动 —— 全部既有配平数字不变。
	var state := _stocked_state()
	state.dispatched = 3
	assert_true(state.dispatch_manual.is_empty(), "脚本流派从不填这份名单")
	assert_eq(state.field_slots(_cfg), state.open_slots(_cfg), "所以容量和以前一模一样")
