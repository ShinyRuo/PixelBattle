extends GutTest
## [PBBattleSim] 的逐 tick 战斗测试。M0-a。
##
## 最要紧的是**对拍**：逐 tick 模型和 [PBCombatRules] 的解析式排队模型
## 在同样输入下应该给出一致的结果 —— 排队模型本来就是这个模型在
## 「输出恒定、单目标、敌人不还手」前提下的闭式解。
##
## 两边对不上就说明改造引入了 bug，而这种 bug 在批量统计里会被平均掉，
## 只表现为「波次结论悄悄偏了几波」，不对拍根本发现不了。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	# **整波从同一条起跑线出发**（M4-d）。排队模型的前提就是那个 ——
	# 它是一条一维队列，不知道「方阵后面几列出生在战场之外」这回事。
	# 留着阵型深度的话，对拍会差出后排走进战场那几十个 tick，
	# 而那个差和伤害模型一点关系都没有。
	_cfg.spawn_column_gap = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260827


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


func _sim(wave: PBWave, dps: float, def_reduction: float = 0.0) -> PBBattleSim:
	return PBBattleSim.new(wave, dps, def_reduction, _cfg)


# ── 基本语义 ────────────────────────────────────────────────────


func test_overwhelming_dps_clears_everything() -> void:
	var wave := _wave(1)
	var out := _sim(wave, 1e9).run_to_end()
	assert_true(out.cleared, "碾压级 DPS 应全清")
	assert_eq(out.kills, wave.count, "击杀数应等于总数")
	assert_eq(out.leaked, 0, "不应有漏怪")
	assert_eq(out.base_damage, 0.0, "全清时基地不该掉血")


func test_zero_dps_leaks_the_entire_wave() -> void:
	var wave := _wave(1)
	var out := _sim(wave, 0.0).run_to_end()
	assert_false(out.cleared, "零 DPS 不可能清波")
	assert_eq(out.leaked, wave.count, "应全部漏光")
	assert_eq(out.kills, 0, "不应有任何击杀")
	assert_gt(out.base_damage, 0.0, "全漏应该扣基地血")


func test_kills_plus_leaks_always_equals_the_wave_count() -> void:
	# 守恒律。一个敌人要么被杀要么漏过去，不该凭空多出来或消失。
	var wave := _wave(25)
	for dps: float in [0.0, 1.0, 50.0, 500.0, 5000.0, 1e6]:
		var out := _sim(wave, dps).run_to_end()
		assert_eq(out.kills + out.leaked, wave.count, "DPS=%.0f 时击杀+漏怪应等于总数" % dps)


func test_more_dps_never_produces_more_leaks() -> void:
	var wave := _wave(30)
	var previous: int = wave.count + 1
	for dps: float in [10.0, 100.0, 400.0, 1200.0, 4000.0, 20000.0]:
		var out := _sim(wave, dps).run_to_end()
		assert_lte(out.leaked, previous, "DPS 提高到 %.0f 后漏怪数不该反增" % dps)
		previous = out.leaked


# ── 逐 tick 的特有行为 ──────────────────────────────────────────


func test_stepping_advances_one_tick_at_a_time() -> void:
	# view 层靠 step() 一帧推进若干 tick，倍速就是改这个「若干」（§14）。
	var sim := _sim(_wave(20), 500.0)
	assert_eq(sim.current_tick(), 0, "刚建好应该是第 0 tick")
	sim.step()
	assert_eq(sim.current_tick(), 1, "step 一次应推进一个 tick")
	for _i: int in 9:
		sim.step()
	assert_eq(sim.current_tick(), 10, "step 十次应推进十个 tick")


func test_stepping_to_the_end_matches_run_to_end() -> void:
	# 倍速不能引入任何数值差异 —— §14 的铁律。
	# 一次一个 tick 和一口气跑完，结果必须逐字段相同。
	# 必须复用同一个 wave 对象：_wave() 会消耗 _rng，调两次会掷出不同的波型，
	# 那就变成拿两波不同的敌人在对比，测试会红但红的是测试不是代码。
	var wave := _wave(22)
	var stepped := _sim(wave, 700.0)
	while not stepped.is_finished():
		stepped.step()
	var at_once := _sim(wave, 700.0).run_to_end()
	var by_step := stepped.result()
	assert_eq(by_step.kills, at_once.kills, "分步与一次跑完的击杀数应相同")
	assert_eq(by_step.leaked, at_once.leaked, "分步与一次跑完的漏怪数应相同")
	assert_eq(by_step.ticks, at_once.ticks, "分步与一次跑完的 tick 数应相同")


func test_enemies_do_not_exist_before_their_spawn_tick() -> void:
	# 整波在 spawn_window 内陆续出场，不是一开始全在场上。
	#
	# **M4-d 把默认窗口改成了 0（一次全刷），所以这里要自己开一个** ——
	# 机制还在，解析式排队模型也还在读它，只是不再是默认玩法。
	_cfg.spawn_window = 10.0
	var wave := _wave(40)
	var sim := _sim(wave, 0.0)
	assert_gt(wave.count, 1, "这一波应该有多个敌人，否则测不出出场节奏")
	assert_lt(sim.active_enemies().size(), wave.count, "第 0 tick 不该全员在场")
	sim.run_to_end()
	assert_eq(sim.enemies().size(), wave.count, "全部敌人都应被建出来")


func test_overflow_damage_carries_to_the_next_enemy() -> void:
	# 一 tick 的伤害够打死好几个时，溢出必须结算。
	# 漏掉溢出会让战斗时长被系统性拉长，而那正是 §01 验收要看的数。
	#
	# 把出场窗口压成 0 让整波同时出现 —— 否则第 1 tick 场上只有一个敌人，
	# 溢出伤害无处可去，测的就不是溢出了。
	_cfg.spawn_window = 0.0
	var wave := _wave(15)
	assert_gt(wave.count, 3, "这一波要有足够多的敌人才测得出溢出")
	# 给两倍余量，不要卡在「伤害正好等于总血量」那个点上：
	# 溢出是一路减出来的，减几十次之后浮点误差足以让最后一个差一丝血没死。
	# 那是浮点的正常行为，不是溢出逻辑的问题，测试不该建在那条边界上。
	var one_tick_kills_all: float = wave.total_hp() * 2.0 * float(_cfg.tick_rate)
	var sim := _sim(wave, one_tick_kills_all)
	sim.step()
	assert_eq(sim.result().kills, wave.count, "一 tick 的伤害够打死整波时，应该一次全清")


func test_damage_cannot_reach_enemies_that_have_not_spawned() -> void:
	# 溢出伤害只在**已出场**的敌人之间传递。打不到还没出现的敌人 ——
	# 否则整个出场节奏就失去意义，一波会在第 1 tick 被秒掉。
	#
	# 同样要自己开出怪窗口（M4-d 把默认改成了 0）：一次全刷的话
	# 场上本来就没有「还没出场的敌人」，这一条无从测起。
	_cfg.spawn_window = 10.0
	var wave := _wave(15)
	assert_gt(wave.count, 3, "这一波要有足够多的敌人")
	var sim := _sim(wave, wave.total_hp() * float(_cfg.tick_rate))
	sim.step()
	assert_eq(sim.result().kills, 1, "第 1 tick 只有一个敌人出场，再高的伤害也只能打死它")


func test_battle_always_terminates() -> void:
	# 敌人每 tick 都在前进，迟早抵达基地，所以战斗必定结束。
	# 撞上安全阀说明配置错了（比如速度配成 0），那是要立刻发现的事。
	for wave_index: int in [1, 10, 33, 50, 77]:
		var sim := _sim(_wave(wave_index), 0.0)
		sim.run_to_end()
		assert_true(sim.is_finished(), "第 %d 波应能正常结束" % wave_index)
		assert_lt(sim.current_tick(), PBBattleSim.MAX_TICKS, "不该撞上安全阀")


# ── 与解析式排队模型对拍 ────────────────────────────────────────


func test_matches_the_analytic_model_across_the_dps_range() -> void:
	# **本文件最重要的一条。**
	#
	# 排队模型是逐 tick 模型的闭式解，两者应该给出一致的击杀/漏怪数。
	# 允许 1 个的偏差：逐 tick 把时间离散化了，恰好卡在抵达那一 tick 的
	# 敌人可能落到边界的另一侧。超过 1 个就是真的不一致。
	for wave_index: int in [1, 7, 15, 23, 31, 44]:
		var wave := _wave(wave_index)
		for dps: float in [50.0, 200.0, 800.0, 3000.0, 12000.0]:
			var ticked := _sim(wave, dps).run_to_end()
			var analytic := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
			assert_almost_eq(
				float(ticked.leaked),
				float(analytic.leaked),
				1.0,
				"第 %d 波 DPS=%.0f：两个模型的漏怪数应一致" % [wave_index, dps]
			)


func test_matches_the_analytic_model_on_battle_duration() -> void:
	# 时长也要对得上 —— §01 的「单波 30–45 秒」验收是拿它算的，
	# 两个模型给出不同的时长会让 M-1 的结论和 M0 的观感对不上。
	for wave_index: int in [5, 19, 36]:
		var wave := _wave(wave_index)
		for dps: float in [300.0, 1500.0, 9000.0]:
			var ticked := _sim(wave, dps).run_to_end()
			var analytic := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
			var gap: float = absf(ticked.battle_seconds - analytic.battle_seconds)
			assert_lt(gap, 1.0, "第 %d 波 DPS=%.0f：两个模型的时长差应小于 1 秒" % [wave_index, dps])


func test_defense_tech_reduces_leak_damage_the_same_way() -> void:
	var wave := _wave(12)
	var bare := _sim(wave, 0.0, 0.0).run_to_end()
	var armored := _sim(wave, 0.0, 0.40).run_to_end()
	assert_almost_eq(armored.base_damage, bare.base_damage * 0.6, 1e-3, "40% 减伤应精确生效")
	var analytic := PBCombatRules.resolve(wave, 0.0, 0.40, _cfg)
	assert_almost_eq(armored.base_damage, analytic.base_damage, 1e-3, "与解析模型的基地伤害应一致")


# ── M0 的节奏结论（守着一个很容易踩的陷阱）──────────────────────


## 场上同时有几个敌人（按 tick 取平均）。诊断工具 `wave_pacing.gd` 算的是同一个量。
func _mean_on_field(wave: PBWave, dps: float) -> float:
	var battle := _sim(wave, dps)
	var total: int = 0
	var ticks: int = 0
	while not battle.is_finished() and battle.current_tick() < PBBattleSim.MAX_TICKS:
		battle.step()
		total += battle.active_enemies().size()
		ticks += 1
	return float(total) / float(maxi(ticks, 1))


func test_stretching_the_spawn_window_makes_the_field_emptier_not_fuller() -> void:
	# **这条守的是一个会让人自以为达标的陷阱。**
	#
	# §01 要求单波 30–45 秒。默认配置只有 12 秒，而调大 `spawn_window`
	# 能让 100% 的波次落进那个区间 —— 实测 35/35。
	# 但那是假的：时长变长的部分全是「在等出怪」，战场反而更空。
	#
	# M0 从数据里拟合出来的关系是：
	#
	#     场上人数 ≈ 清怪时间 / 出怪窗口
	#
	# 分母变大，人数就变小。所以 §01 那句话说的其实是**清怪时间**，
	# 不是出怪窗口 —— 详见《开发路线图》「M0 的答案 · Q3」。
	var wave := _wave(12)
	var dps: float = 2000.0

	_cfg.spawn_window = 10.0
	var tight_seconds: float = _sim(wave, dps).run_to_end().battle_seconds
	var tight_crowd: float = _mean_on_field(wave, dps)

	_cfg.spawn_window = 30.0
	var stretched_seconds: float = _sim(wave, dps).run_to_end().battle_seconds
	var stretched_crowd: float = _mean_on_field(wave, dps)

	assert_gt(stretched_seconds, tight_seconds * 2.0, "拉长出怪窗口确实能把单波时长撑上去")
	assert_lt(stretched_crowd, tight_crowd, "但战场只会更空 —— 这就是它不能当达标手段的原因")
