class_name PBRunSim
extends RefCounted
## 跑完一整局：从第 1 波打到基地被打穿，或撞上 `max_wave` 上限。
##
## 每一波的顺序是刻意排的，换顺序会改变结果：
##
## 1. 生成本波参数与本波任务（`quest` 流）
## 2. 玩家花钱（`gacha` 流）—— 抽到的卡本波就能上
## 3. 选上场单位
## 4. 决定接不接任务 —— **必须在算 DPS 之前**，因为派遣会削掉羁绊加成
## 5. 算有效 DPS，结算战斗
## 6. 四条收入流入账（`combat` 流掷纲手掉落）
##
## §01 说准备阶段不限时、可存档退出，所以第 2–4 步在真实游戏里是玩家慢慢想的；
## 模型里它们不消耗时间，只有第 5 步的战斗产生 [member PBSimConfig.gold_tick_base]
## 那条被动收入 —— 否则挂机就是无限金币。

## §01 的单波时长目标区间（秒）。
const TARGET_DURATION_MIN: float = 30.0
const TARGET_DURATION_MAX: float = 45.0


## 跑一局。[param run_seed] 决定三条 RNG 流，同一个种子必然跑出同一个结果。
static func run(cfg: PBSimConfig, strategy: PBStrategy, run_seed: int) -> PBRunResult:
	var rng := PBRngStreams.new(run_seed)
	var state := new_state(cfg)

	var result := PBRunResult.new()
	result.strategy_id = strategy.id
	result.growth = cfg.growth
	result.run_seed = run_seed

	while state.wave_index <= cfg.max_wave:
		var plan := plan_wave(state, strategy, cfg, rng)
		var outcome := _resolve_battle(plan.wave, plan.dps, state.def_reduction(cfg), cfg)
		settle_wave(state, plan, outcome, cfg, rng, result)
		if state.base_hp <= 0.0:
			break
		state.wave_index += 1

	# 撞上限而不是被打穿。统计时这些局必须单独挑出来，
	# 混进分位数会把「打穿了上限」误读成「卡在第 200 波」。
	result.hit_wave_cap = state.base_hp > 0.0
	_snapshot(state, result)
	return result


## 造一个开局状态。批量模拟和游戏画面都走这里，免得两边的开局条件不一致 ——
## 那种不一致会表现为「批量校出来的波次和实际玩到的对不上」，且不报任何错。
static func new_state(cfg: PBSimConfig) -> PBRunState:
	var state := PBRunState.new()
	state.base_hp = cfg.base_hp
	state.gold = cfg.starting_gold
	return state


## 构造第 [param wave_index] 波的参数。**零副作用，可以随便调。**
##
## §03 要求「下一波属性预告常驻 HUD，提前 1 波显示」，§04 要求波型也一起公示。
## 靠的就是这个函数不消耗任何顺序随机流 —— 见 [method PBRngStreams.wave_rng]。
static func preview_wave(wave_index: int, cfg: PBSimConfig, rng: PBRngStreams) -> PBWave:
	return PBWaveRules.build(wave_index, cfg, rng.wave_rng(wave_index))


## 准备一波：生成敌人、让玩家花钱、选上场名单、决定接不接任务、算出有效 DPS。
##
## **批量模拟和游戏画面共用这一个入口。** 两边各写一份的话，RNG 的调用次序
## 迟早分叉，「批量校出来的数值」和「实际玩到的手感」会对不上且不报错。
##
## 内部顺序不能换，理由见本类顶部的说明。
static func plan_wave(
	state: PBRunState, strategy: PBStrategy, cfg: PBSimConfig, rng: PBRngStreams
) -> PBWavePlan:
	var plan := PBWavePlan.new()
	plan.wave = preview_wave(state.wave_index, cfg, rng)
	plan.quest_grade = PBEconomyRules.roll_quest(rng.quest)

	strategy.prepare(state, plan.wave, cfg, rng)

	plan.deployed = strategy.deploy(state, plan.wave, cfg)
	plan.quest_accepted = strategy.accept_quest(state, plan.wave, plan.quest_grade, cfg)
	state.dispatched = (
		PBEconomyRules.quest_cost_units(plan.quest_grade) if plan.quest_accepted else 0
	)

	plan.dps = PBCombatRules.team_dps(
		plan.deployed,
		plan.wave.element,
		state.atk_mult(cfg),
		state.bond_mult(cfg),
		state.equip_mult(cfg),
		cfg
	)
	return plan


## 结算一波：累计统计、四条收入入账、扣基地血、清掉派遣标记。
##
## [param result] 可以传 null —— 游戏画面只关心 [param state]，
## 不需要那份供 CSV 用的整局汇总。
static func settle_wave(
	state: PBRunState,
	plan: PBWavePlan,
	outcome: PBCombatOutcome,
	cfg: PBSimConfig,
	rng: PBRngStreams,
	result: PBRunResult = null
) -> void:
	_collect(state, result, outcome, plan.quest_accepted)
	_settle_income(state, plan.wave, outcome, plan.quest_grade, plan.quest_accepted, cfg, rng)
	state.base_hp -= outcome.base_damage
	state.dispatched = 0
	if result != null:
		result.wave_reached = state.wave_index


## 结算一波战斗。走哪个模型由 [member PBSimConfig.use_tick_battle] 决定。
##
## 两个模型语义一致、结果对得上（`test_battle_sim.gd` 有对拍断言锁着）。
## 批量校数值默认走解析式（快），游戏跑起来一定是逐 tick（要看到敌人在动）。
static func _resolve_battle(
	wave: PBWave, dps: float, def_reduction: float, cfg: PBSimConfig
) -> PBCombatOutcome:
	if cfg.use_tick_battle:
		return PBBattleSim.new(wave, dps, def_reduction, cfg).run_to_end()
	return PBCombatRules.resolve(wave, dps, def_reduction, cfg)


## 把本波的过程数据累进统计。
static func _collect(
	state: PBRunState, result: PBRunResult, outcome: PBCombatOutcome, accepted: bool
) -> void:
	state.total_kills += outcome.kills
	state.total_leaked += outcome.leaked
	state.elapsed_seconds += outcome.battle_seconds
	if result == null:
		return

	result.battle_seconds_sum += outcome.battle_seconds
	if (
		outcome.battle_seconds >= TARGET_DURATION_MIN
		and outcome.battle_seconds <= TARGET_DURATION_MAX
	):
		result.waves_in_target_duration += 1
	if accepted:
		result.quests_taken += 1


## 四条收入流入账（§07）。
##
## 注意纲水的击杀收入在 M-1 里**无条件生效** —— 真实游戏里它要占一个出战位。
## 这么简化是因为路线图的四个问题都不问「该不该上纲手」，而它对所有策略
## 是同一个常数，不影响策略之间的相对比较。角都保留了占位代价，
## 因为「经济位 = 战力空位」那条张力（§07）正是靠它度量的。
static func _settle_income(
	state: PBRunState,
	wave: PBWave,
	outcome: PBCombatOutcome,
	quest_grade: int,
	accepted: bool,
	cfg: PBSimConfig,
	rng: PBRngStreams
) -> void:
	state.earn(wave.reward_gold)
	state.earn(PBEconomyRules.passive_income(outcome.battle_seconds, state.tech_gold, cfg))
	state.earn(PBEconomyRules.tsunade_income(outcome.kills, cfg, rng.combat))
	state.earn(PBEconomyRules.kakuzu_income(state.kakuzu_count, cfg))
	if accepted:
		state.earn(PBEconomyRules.quest_reward(quest_grade, wave.index))


static func _snapshot(state: PBRunState, result: PBRunResult) -> void:
	result.total_kills = state.total_kills
	result.total_leaked = state.total_leaked
	result.gold_earned = state.gold_earned
	result.gacha_pulls = state.gacha_pulls
	result.final_tech_gold = state.tech_gold
	result.final_tech_pop = state.tech_pop
	result.final_tech_atk = state.tech_atk
	result.final_tech_def = state.tech_def
	result.final_roster_size = state.roster.size()
	result.final_equip_parts = state.equip_parts
	result.gold_spent = state.gold_spent
