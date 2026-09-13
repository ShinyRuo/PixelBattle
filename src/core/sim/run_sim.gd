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
## 5. 结算战斗
## 6. 收入流入账
##
## 准备阶段（2–4）在模型里不消耗时间，只有战斗产生被动收入 —— 否则挂机就是无限金币。

## §01 的单波时长目标区间（秒）。
const TARGET_DURATION_MIN: float = 30.0
const TARGET_DURATION_MAX: float = 45.0


## 跑一局。[param run_seed] 决定三条 RNG 流，同一个种子必然跑出同一个结果。
static func run(cfg: PBSimConfig, strategy: PBStrategy, run_seed: int) -> PBRunResult:
	var rng := PBRngStreams.new(run_seed)
	var state := new_state(cfg)
	# §11：尾兽**开局选定、全程不变**。所以它在开波循环之外落定一次，
	# 而不是每波问一遍 —— 每波能换的话，「在哪一波交底牌」这个决策就没了，
	# 玩家只要每波换上最克这一波的那只即可。
	state.beast_id = strategy.choose_beast(cfg)

	var result := PBRunResult.new()
	result.strategy_id = strategy.id
	result.growth = cfg.growth
	result.run_seed = run_seed

	while state.wave_index <= cfg.max_wave:
		var plan := plan_wave(state, strategy, cfg, rng)
		var outcome := resolve_battle(plan, state.def_reduction(cfg), cfg)
		settle_wave(state, plan, outcome, cfg, rng, result)
		if state.base_hp <= 0.0:
			break
		state.wave_index += 1

	# 撞上限而不是被打穿。统计时这些局必须单独挑出来，
	# 混进分位数会把「打穿了上限」误读成「卡在第 200 波」。
	result.hit_wave_cap = state.base_hp > 0.0
	_snapshot(state, result)
	_snapshot_power(state, cfg, result)
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
##
## 本函数是 [method begin_wave] → 花钱选人 → [method lock_plan] 三步的合成。
## 脚本玩家一口气跑完，真人玩家在中间那段停下来慢慢做 —— 见 [method begin_wave]。
static func plan_wave(
	state: PBRunState, strategy: PBStrategy, cfg: PBSimConfig, rng: PBRngStreams
) -> PBWavePlan:
	var plan := begin_wave(state, cfg, rng)
	# 尾兽升级问在 `prepare` 之前：它和抽卡、科技抢同一笔钱，顺序反了的话尾兽等级永远停在 1。
	strategy.upgrade_beast(state, cfg)
	strategy.prepare(state, plan.wave, cfg, rng)
	lock_plan(
		state,
		plan,
		strategy.deploy(state, plan.wave, cfg),
		strategy.accept_quest(state, plan.wave, plan.quest_grade, cfg),
		cfg
	)
	return plan


## 开波：生成敌人参数、掷出本波任务。**之后就是准备阶段。**
##
## 真人走「`begin_wave` → 停下来 → 玩家用 `pull_once` / `buy_tech` 等原语花钱 → `lock_plan`」，
## 与脚本玩家共用同一批原语和同一个顺序（脚本的 `prepare()` 是同步的，真人做不到）。
##
## **本函数只消费 `quest` 流一次**（波型走 `wave_rng`，纯函数）。次序动了批量校出来的数值
## 就和实际玩到的对不上，且不报错。
static func begin_wave(state: PBRunState, cfg: PBSimConfig, rng: PBRngStreams) -> PBWavePlan:
	var plan := PBWavePlan.new()
	plan.wave = preview_wave(state.wave_index, cfg, rng)
	plan.quest_grade = PBEconomyRules.roll_quest(rng.quest)
	# 暴击那条流是**派生的纯函数**，取一次零副作用 —— 所以上面那句
	# 「本函数只消费 quest 流一次」照旧成立（同 `wave_rng`）。
	plan.crit_rng = rng.battle_rng(state.wave_index)
	return plan


## 花金币重刷本波的任务（§06）。买不起返回 false。
##
## 重刷次数由玩家决定，同一颗种子跑出来的局因此不唯一 —— 那是玩家的选择进了随机流，
## 所以存档必须存流状态（铁律 3）。重刷**不三选一**：任务只有「接不接」一个决策。
static func reroll_quest(
	state: PBRunState, plan: PBWavePlan, cfg: PBSimConfig, rng: PBRngStreams
) -> bool:
	# 已经锁定的不能再刷 —— 锁定时派遣人数已经落定，改任务等级会让
	# 「派了几个人」和「这个任务要几个人」对不上，而那不报错。
	if plan.quest_accepted:
		return false
	if not state.spend(PBEconomyRules.quest_reroll_cost(plan.wave.index, cfg)):
		return false
	plan.quest_grade = PBEconomyRules.roll_quest(rng.quest)
	return true


## 锁定：确定上场名单与派遣，算出有效 DPS。**准备阶段结束时调一次。**
## 派遣必须在算 DPS 之前落定（派出去的人羁绊失效），顺序反了派遣就没有代价。不消费任何随机流。
static func lock_plan(
	state: PBRunState,
	plan: PBWavePlan,
	deployed: Array[PBUnit],
	quest_accepted: bool,
	cfg: PBSimConfig
) -> void:
	plan.deployed = deployed
	plan.quest_accepted = quest_accepted
	# **走的是几个人，和任务成不成功是两件事**：任务栏里几个人就走几个，人数不符只是拿不到奖励。
	# 名单空着时按「接了就派 need 个」算（脚本玩家的末尾规则）。
	state.dispatched = (
		state.dispatch_manual.size()
		if not state.dispatch_manual.is_empty()
		else (PBEconomyRules.quest_cost_units(plan.quest_grade) if plan.quest_accepted else 0)
	)
	# 把「派出去的是哪几个」记下来给界面。**在算羁绊之前记**，晚一步 `dispatched` 可能已经被清了。
	state.dispatched_ids.clear()
	for unit: PBUnit in state.dispatch_picks(cfg):
		state.dispatched_ids.append(unit.key())
	# 被派走的人这一波不上场，漏了这一步他会既在做任务又在打仗。
	# 脚本流派走不进这个 filter（末尾规则派的人本来就不在 `deployed` 里）。
	if not state.dispatched_ids.is_empty():
		var fighting: Array[PBUnit] = []
		for unit: PBUnit in plan.deployed:
			if not state.dispatched_ids.has(unit.key()):
				fighting.append(unit)
		plan.deployed = fighting
	# 功能档必须在 `dispatched` 落定之后算 —— 派出去的人羁绊失效（§06），
	# 顺序反了会让「派遣」不再掉功能档，而那正是派遣该付的代价。
	plan.bond_functions = PBBondRules.active_functions(
		state.bonded_units(cfg), plan.deployed, cfg.bonds
	)
	plan.bond_passives = PBBondRules.active_passives(
		state.bonded_units(cfg), plan.deployed, cfg.bonds
	)
	plan.bond_skill_patches = PBBondRules.active_skill_patches(
		state.bonded_units(cfg), plan.deployed, cfg.bonds
	)
	plan.attackers = PBCombatRules.build_attackers(
		plan.deployed,
		plan.wave.element,
		state.bond_mult(cfg),
		PBCombatRules.unit_multipliers(plan.deployed, state, cfg),
		cfg,
		PBBeastRules.beast_of(state, cfg),
		state.beast_level,
		state.beast_cooldown_ticks,
		# **这三份缺一不可**：少传的那份算出来存在计划上却没人取，羁绊成员效果或技能补丁
		# 在真游戏里不生效，而测试直接调 `build_attackers` 抓不到（`test_bond_members.gd` 走完整条路钉着）。
		plan.bond_functions,
		plan.bond_passives,
		plan.bond_skill_patches,
		PBCombatRules.unit_mods(plan.deployed, state, cfg)
	)
	# 玩家拖出来的开战位置盖在自动站位上（§02），排在建攻击者之后。名单空着时什么都不做。
	PBFormationRules.apply(plan.attackers, plan.deployed, state.formation, cfg)
	# 报出去的战力就是这批攻击者的和，不另算一份 —— 见 [member PBWavePlan.dps]。
	plan.dps = PBCombatRules.total_dps(plan.attackers)


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
	_settle_income(state, plan, outcome, cfg, rng)
	state.base_hp -= outcome.base_damage
	state.dispatched = 0
	state.dispatched_ids.clear()
	# **任务栏里站着的人下一波还站在那儿**：派遣的语义是「这个人去做任务」，不是「这一波去做」。
	# 只剔掉已经不在卡池里的 —— 留着的话 [method PBRunState.field_slots] 会为不存在的人多留一个位置。
	var staying: Array[StringName] = []
	for key: StringName in state.dispatch_manual:
		if state.roster.has(key):
			staying.append(key)
	state.dispatch_manual = staying
	# 尾兽的冷却跨波接着走 —— 它是底牌，稀缺性全靠这一行（§11）。
	var beast_attacker := PBBeastRules.attacker_in(plan.attackers)
	if beast_attacker != null and beast_attacker.ultimate != null:
		state.beast_cooldown_ticks = beast_attacker.ultimate.cooldown_left(outcome.ticks)
	if result != null:
		result.wave_reached = state.wave_index


## 结算一波战斗。**任何要打一波的地方都走这里，不要自己挑模型。**
##
## 逐 tick 模型有射程和多目标分配，解析式排队模型没有，两者给出不同的结果 ——
## 「选哪个模型」只能有一处，否则快进出来的存档和真打出来的对不上。
## [method PBCombatRules.resolve] 只是退化情形的参照物（`test_attacker.gd` 拿它对拍）。
static func resolve_battle(
	plan: PBWavePlan, def_reduction: float, cfg: PBSimConfig
) -> PBCombatOutcome:
	if cfg.use_tick_battle:
		return PBBattleSim.new(
			plan.wave, plan.dps, def_reduction, cfg, plan.attackers, plan.crit_rng
		).run_to_end()
	return PBCombatRules.resolve(plan.wave, plan.dps, def_reduction, cfg)


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


## 收入流入账（§07）。
##
## 击杀掉落在模型里**无条件生效**（它对所有策略是同一个常数，不影响相对比较）；
## 经济位保留了占位代价，因为「经济位 = 战力空位」正是靠它度量的。
## 收整个 [param plan]：功能表（木叶三忍关掉负收益）也在计划里。
static func _settle_income(
	state: PBRunState,
	plan: PBWavePlan,
	outcome: PBCombatOutcome,
	cfg: PBSimConfig,
	rng: PBRngStreams
) -> void:
	var wave: PBWave = plan.wave
	state.earn(wave.reward_gold, &"wave")
	state.earn(
		PBEconomyRules.passive_income(outcome.battle_seconds, state.tech_gold, cfg), &"passive"
	)
	# 木叶三忍的功能档（§09）在这里兑现：负收益不再触发，正收益提高。
	state.earn(
		PBEconomyRules.kill_drop_income(
			outcome.kills,
			cfg,
			rng.combat,
			PBBondFunctionRules.grants_gold_floor(plan.bond_functions)
		),
		&"kill_drop"
	)
	state.earn(
		PBEconomyRules.economy_slot_income(state.economy_slot_count, wave.index, cfg),
		&"economy_slot"
	)
	if plan.quest_accepted:
		state.earn(PBEconomyRules.quest_reward(plan.quest_grade, wave.index), &"quest")


## 把「羁绊倍率」和「出战席裸战力」分开记下来。
## 技能阶梯是两者的乘积，只记波次的话「羁绊涨得不够」和「涨了但被战力损失吃掉」读起来一样，
## 而两种情况的修法相反。
static func _snapshot_power(state: PBRunState, cfg: PBSimConfig, result: PBRunResult) -> void:
	result.final_bond_mult = state.bond_mult(cfg)
	var power: float = 0.0
	for unit: PBUnit in PBValuation.deployed_by_raw_power(state, cfg):
		power += unit.power(cfg)
	result.final_deployed_power = power


static func _snapshot(state: PBRunState, result: PBRunResult) -> void:
	result.total_kills = state.total_kills
	result.total_leaked = state.total_leaked
	result.gold_earned = state.gold_earned
	result.gacha_pulls = state.gacha_pulls
	result.final_tech_gold = state.tech_gold
	result.final_tech_pop = state.tech_pop
	for branch: StringName in state.training:
		result.final_training += state.training_level(branch)
	result.final_tech_def = state.tech_def
	result.final_roster_size = state.roster.size()
	result.final_equip_parts = PBEquipRules.part_total(state.equip_parts)
	result.gold_spent = state.gold_spent
	result.gold_by_source = state.gold_by_source.duplicate()
