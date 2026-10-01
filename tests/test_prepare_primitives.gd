extends GutTest
## 战场直接操作的四条 core 前置（§02 / §03A / §06 / §08）。M3.5-e。
##
## ## 这个文件守的是什么
##
## 界面还没做，但它要读的四样东西都在这一层：
##
## 1. **派出去的是哪几个** —— 以前只有一个数字，「哪 4 个」数据层答不出来
## 2. **抽卡三选一** —— 钱先扣、候选存进状态，玩家可以在中间停下来想
## 3. **任务重刷** —— §06 写了两年的规则，一直没实现
## 4. **忍者升级** —— §03A 的等级已经进战斗了，缺的是花钱那条原语
##
## 先做这一层是有理由的：**界面拿它们当数据源，顺序反了要返工。**

var _cfg: PBSimConfig
var _rng: PBRngStreams
var _wave_rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = PBRngStreams.new(20260829)
	# 波型是波次下标的纯函数，不占三条流里的任何一条（铁律 3）——
	# 所以测试自己拿一个 RNG 造波，不去动 gacha / quest / combat。
	_wave_rng = RandomNumberGenerator.new()
	_wave_rng.seed = 20260829


func _stocked_state() -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	for character: PBCharacter in _cfg.characters.all():
		state.add_unit(PBUnit.new(character))
	return state


# ── 派出去的是哪几个 ──────────────────────────────────────────


func test_the_dispatched_roster_says_exactly_who_went() -> void:
	# 以前 `dispatched` 只有一个数字，而 §02 的战场要显示那几个头像。
	var state := _stocked_state()
	state.dispatched = 3
	var sent := state.dispatch_picks(_cfg)
	assert_eq(sent.size(), 3, "派了几个就该报几个")
	for unit: PBUnit in sent:
		assert_false(state.bonded_units(_cfg).has(unit), "被派出去的不该还在算羁绊")


func test_who_went_and_who_still_counts_are_two_halves_of_one_cut() -> void:
	# **故意写成互补的两个切片。** 各写一份判断的话，「谁失效了」和
	# 「界面上显示谁在做任务」迟早对不上 —— 玩家一眼看得出（头像亮着
	# 但羁绊掉了），代码里却不报错。
	var state := _stocked_state()
	for count: int in [0, 1, 4]:
		state.dispatched = count
		var field := state.field_units(_cfg)
		assert_eq(
			state.bonded_units(_cfg).size() + state.dispatch_picks(_cfg).size(),
			field.size(),
			"派 %d 人时两半该正好拼回在场名单" % count
		)


func test_locking_the_plan_records_the_names_and_settling_clears_them() -> void:
	var state := _stocked_state()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var strategy := PBStratBalanced.new()
	# 挑一个真的要派人的任务等级，否则这条测不到东西。
	while PBEconomyRules.quest_cost_units(plan.quest_grade) <= 0:
		plan.quest_grade = PBEconomyRules.roll_quest(_rng.quest)
	PBRunSim.lock_plan(state, plan, strategy.deploy(state, plan.wave, _cfg), true, _cfg)
	assert_eq(state.dispatched_ids.size(), state.dispatched, "名单长度该等于派遣人数")
	var outcome := PBRunSim.resolve_battle(plan, state.def_reduction(_cfg), _cfg)
	PBRunSim.settle_wave(state, plan, outcome, _cfg, _rng)
	assert_true(state.dispatched_ids.is_empty(), "结算之后该清空")


# ── 抽卡三选一 ────────────────────────────────────────────────


func test_one_pull_puts_three_cards_on_the_table() -> void:
	var state := PBRunSim.new_state(_cfg)
	state.gold = 100000
	var wave := PBWaveRules.build(5, _cfg, _wave_rng)
	assert_true(PBShopRules.open_offer(state, wave, _cfg, _rng), "钱够该摆得出来")
	assert_eq(state.pending_offer.size(), _cfg.gacha_offer_size, "该摆出三张")
	assert_true(state.roster.is_empty(), "还没挑，仓库里不该有东西")


func test_the_money_is_gone_before_the_choice_so_the_offer_must_be_saved() -> void:
	# 钱在掷之前就扣了，所以候选必须落在状态里 —— 真人会在这里停下来想，
	# 中间可能存档、可能关掉游戏。存在返回值里的话那笔钱就白花了。
	var state := PBRunSim.new_state(_cfg)
	state.gold = 100000
	var before: int = state.gold
	PBShopRules.open_offer(state, PBWaveRules.build(5, _cfg, _wave_rng), _cfg, _rng)
	assert_lt(state.gold, before, "摆出来的那一刻钱就该扣了")
	assert_eq(state.pending_offer.size(), _cfg.gacha_offer_size, "而候选存在状态里")


func test_taking_one_discards_the_rest_without_a_refund() -> void:
	# 弃掉的不进任何池子、不返金币。给补偿的话「选哪张」的代价被抹平，
	# 决策又没了 —— 那是三选一存在的全部理由。
	var state := PBRunSim.new_state(_cfg)
	state.gold = 100000
	PBShopRules.open_offer(state, PBWaveRules.build(5, _cfg, _wave_rng), _cfg, _rng)
	var wanted: PBUnit = state.pending_offer[1]
	var purse: int = state.gold
	assert_true(PBShopRules.take_offer(state, 1), "挑第二张该成功")
	assert_eq(state.roster.size(), 1, "只该进一张")
	assert_true(state.roster.has(wanted.key()), "进的该是挑的那张")
	assert_eq(state.gold, purse, "弃掉的不返钱")
	assert_true(state.pending_offer.is_empty(), "挑完该清空")


func test_a_second_pull_cannot_start_before_the_first_is_resolved() -> void:
	# 允许的话，玩家可以连点几次把候选覆盖掉，前几笔钱凭空消失。
	var state := PBRunSim.new_state(_cfg)
	state.gold = 100000
	var wave := PBWaveRules.build(5, _cfg, _wave_rng)
	assert_true(PBShopRules.open_offer(state, wave, _cfg, _rng), "第一次该成功")
	var purse: int = state.gold
	assert_false(PBShopRules.open_offer(state, wave, _cfg, _rng), "没挑完不该能再抽")
	assert_eq(state.gold, purse, "被拒的那次不该扣钱")


func test_the_pity_counter_reads_the_best_of_the_three() -> void:
	# 三张一起视为**一次**抽卡。三张各保各的话，保底会变成刷 SSR 的最优路径。
	var state := PBRunSim.new_state(_cfg)
	state.gold = 100000
	state.gacha_pity = _cfg.gacha_pity
	PBShopRules.open_offer(state, PBWaveRules.build(5, _cfg, _wave_rng), _cfg, _rng)
	assert_gte(PBEconomyRules.best_rarity(state.pending_offer), int(PBUnit.Rarity.SSR), "保底该在三张里兑现")
	assert_eq(state.gacha_pity, 0, "兑现之后保底计数该清零")


func test_the_scripted_pull_still_works_end_to_end() -> void:
	# 脚本玩家走「摆出来 + 自己挑一张」，一步到位 ——
	# 批量扫描那一整套不能因为界面多了一步就跑不动。
	var state := PBRunSim.new_state(_cfg)
	state.gold = 100000
	var strategy := PBStratBalanced.new()
	assert_true(
		strategy.pull_once(state, PBWaveRules.build(5, _cfg, _wave_rng), _cfg, _rng), "该抽得动"
	)
	assert_eq(state.roster.size(), 1, "该进一张")
	assert_true(state.pending_offer.is_empty(), "不该留下没挑完的候选")


# ── 任务重刷 ──────────────────────────────────────────────────


func test_rerolling_a_quest_costs_gold_and_rolls_again() -> void:
	# §06 写了两年的规则（`50 + 5n`，每波不限次数），一直没实现。
	var state := _stocked_state()
	state.gold = 100000
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var purse: int = state.gold
	var seen: Dictionary = {plan.quest_grade: true}
	for _i: int in 20:
		assert_true(PBRunSim.reroll_quest(state, plan, _cfg, _rng), "钱够该刷得动")
		seen[plan.quest_grade] = true
	assert_lt(state.gold, purse, "重刷要花钱")
	assert_gt(seen.size(), 1, "刷了 20 次该见到不止一种等级")


func test_a_locked_quest_can_no_longer_be_rerolled() -> void:
	# 锁定时派遣人数已经落定，改任务等级会让「派了几个人」和
	# 「这个任务要几个人」对不上，而那不报错。
	var state := _stocked_state()
	state.gold = 100000
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	plan.quest_accepted = true
	var purse: int = state.gold
	assert_false(PBRunSim.reroll_quest(state, plan, _cfg, _rng), "接了就不能再刷")
	assert_eq(state.gold, purse, "被拒的那次不该扣钱")


func test_rerolling_is_refused_when_broke() -> void:
	var state := _stocked_state()
	state.gold = 0
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	var grade: int = plan.quest_grade
	assert_false(PBRunSim.reroll_quest(state, plan, _cfg, _rng), "没钱该刷不动")
	assert_eq(plan.quest_grade, grade, "而且任务不该变")


# ── 忍者升级 ──────────────────────────────────────────────────


func test_levelling_a_ninja_costs_gold_and_makes_it_stronger() -> void:
	var state := _stocked_state()
	state.gold = 100000
	var unit: PBUnit = state.roster.values()[0]
	var before: float = unit.power(_cfg)
	var purse: int = state.gold
	assert_true(PBShopRules.level_up(state, unit, _cfg), "钱够该升得动")
	assert_eq(unit.level, 2, "该升到 2 级")
	assert_gt(unit.power(_cfg), before, "而且真的变强")
	assert_lt(state.gold, purse, "要花钱")


func test_levelling_gets_more_expensive_and_stops_at_the_cap() -> void:
	# 和 §07 的科技树同形状（`base × mult^Lv`）—— 它俩抢同一笔钱，
	# 同形状才比得出来该先买哪个。
	var previous: int = 0
	for level: int in range(1, _cfg.unit_level_max):
		var cost := PBEconomyRules.unit_level_cost(level, _cfg)
		assert_gt(cost, previous, "第 %d 级该比上一级贵" % level)
		previous = cost
	assert_eq(PBEconomyRules.unit_level_cost(_cfg.unit_level_max, _cfg), -1, "满级该报 -1")


func test_a_broke_player_cannot_level_anyone() -> void:
	var state := _stocked_state()
	state.gold = 0
	var unit: PBUnit = state.roster.values()[0]
	assert_false(PBShopRules.level_up(state, unit, _cfg), "没钱该升不动")
	assert_eq(unit.level, 1, "而且等级不该动")


func test_scripted_strategies_do_not_buy_levels_on_their_own() -> void:
	# **加这条原语不该改动任何既有配平数字。** 让扫描流派开始买等级
	# 会把 M-1 以来的全部数字一起改掉，而那是数值回归该做的决定，
	# 不该由一次接线动作顺带完成。
	var state := PBRunSim.new_state(_cfg)
	var strategy := PBStratBalanced.new()
	var wave := PBWaveRules.build(5, _cfg, _wave_rng)
	state.gold = 100000
	strategy.prepare(state, wave, _cfg, _rng)
	for unit: PBUnit in state.roster.values():
		assert_eq(unit.level, 1, "脚本流派不该自己去买等级")
