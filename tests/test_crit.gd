extends GutTest
## 暴击系统（M10-c）。

## ## 这个文件守的是什么
##
## 暴击是这个项目**第一次把随机数放进战斗内部**，所以三条里有两条不是
## 「暴击打得对不对」，而是「它有没有把别的东西弄坏」：
##
## 1. **没有来源时一位都不动** —— 全部既有配平数字不许因为这一步改变
## 2. **不掷骰就是不掷骰** —— 暴击率为 0 时那条流一步都不许走
## 3. 掷中了真的多打，而且只多打在出手上（忍术不吃，玩家定的）

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260909


# ── 一位都不动 ────────────────────────────────────────────────


func test_the_same_seed_still_plays_out_the_same_way_with_dice_in_the_battle() -> void:
	# 暴击是这个项目第一次把随机数放进战斗内部，所以 §12 存档回滚、
	# §13 每日种子、战报回放三样能力**要重新验一遍**：同一颗种子跑两次，
	# 五个结算字段必须逐位相同。
	var first := _run()
	var again := _run()
	assert_eq(again.wave_reached, first.wave_reached, "波数")
	assert_eq(again.total_kills, first.total_kills, "击杀")
	assert_eq(again.total_leaked, first.total_leaked, "漏怪")
	assert_eq(again.gold_earned, first.gold_earned, "金币")
	assert_eq(again.gacha_pulls, first.gacha_pulls, "抽卡次数")


func test_taking_the_battle_dice_leaves_the_other_three_streams_alone() -> void:
	# **这条就是 `battle_rng` 存在的全部理由。**
	#
	# [method PBValuation._leaks_at] 每一波要凭空跑几十场战斗做悬崖二分，
	# 而跑几场取决于二分收敛得多快，也就是取决于队伍强度。
	# 那些战斗和真打的那一场共用一条**顺序**流的话，
	# 「这一局有没有做过估值」就会改变真实战斗的暴击序列。
	#
	# 派生流是 `(种子, 波次)` 的纯函数，所以取多少次都一样、也不动别的流。
	var streams := PBRngStreams.new(4242)
	var before: int = streams.combat.state
	var once: float = streams.battle_rng(7).randf()
	var twice: float = streams.battle_rng(7).randf()
	assert_eq(once, twice, "同一波取两次该拿到同一条流")
	assert_eq(streams.combat.state, before, "取它不许动 combat 流")
	assert_ne(streams.battle_rng(8).randf(), once, "不同波该是不同的流")


func test_a_zero_chance_striker_never_touches_the_stream() -> void:
	# **早退是一条正确性规则，不是优化。** 掷了就算不暴击也已经拨动了流，
	# 于是后面每一次掷骰的结果都挪一位 —— 而那条流同时喂着
	# [method PBAttacker.whole_field] 那条与解析式排队模型对拍的退化路径。
	var attacker := PBAttacker.new()
	attacker.dps = 100.0
	attacker.prime(_cfg.tick_rate)
	var before: int = _rng.state
	var swing := PBCritRules.strike(attacker, 0, _rng)
	assert_eq(_rng.state, before, "暴击率为 0 时一步都不该走")
	assert_false(swing[PBCritRules.CRIT], "也不该暴")
	assert_eq(swing[PBCritRules.DAMAGE], attacker.strike_for(0), "伤害和不掷骰时一模一样")


func test_no_dice_at_all_means_no_crit_even_at_full_chance() -> void:
	# 批量扫描、悬崖二分、老的构造点全都不传 rng。那时**必须**是不暴击，
	# 而不是「按期望值折算」—— 折算过的那份和真打出来的不是同一个数，
	# 而两者在同一份报表里并排出现（§09 的技能阶梯就是这么量的）。
	var attacker := PBAttacker.new()
	attacker.dps = 100.0
	attacker.crit_chance = 1.0
	attacker.prime(_cfg.tick_rate)
	var swing := PBCritRules.strike(attacker, 0, null)
	assert_false(swing[PBCritRules.CRIT], "没有骰子就不暴击")
	assert_eq(swing[PBCritRules.DAMAGE], attacker.strike_for(0), "伤害不变")


# ── 掷中了真的多打 ────────────────────────────────────────────


func test_a_sure_crit_hits_for_the_configured_multiplier() -> void:
	var attacker := PBAttacker.new()
	attacker.dps = 100.0
	attacker.crit_chance = 1.0
	attacker.prime(_cfg.tick_rate)
	var swing := PBCritRules.strike(attacker, 0, _rng)
	assert_true(swing[PBCritRules.CRIT], "暴击率 100% 就该暴")
	assert_almost_eq(
		float(swing[PBCritRules.DAMAGE]),
		attacker.strike_for(0) * (1.0 + PBCritRules.CRIT_DAMAGE_BASE),
		0.0001,
		"暴击该按 crit_damage_base 多打"
	)


func test_the_two_sources_of_crit_add_up_instead_of_replacing() -> void:
	# 常驻那一份在 [member PBAttacker.crit_chance]（羁绊光环），
	# 临时那一份在效果袋里（M10-d 的「命中后短时提暴击」要用）。
	# **相加不是取大**：取大的话两个来源里弱的那个等于白配，而它不报错。
	var attacker := PBAttacker.new()
	attacker.crit_chance = 0.2
	assert_almost_eq(PBCritRules.chance_of(attacker, 0), 0.2, 0.0001, "只有常驻那一份")
	_hang(attacker, PBBuffRules.CRIT_CHANCE, 0.3)
	assert_almost_eq(PBCritRules.chance_of(attacker, 0), 0.5, 0.0001, "两份该加起来")


func test_the_chance_is_clamped_so_it_can_never_exceed_certainty() -> void:
	# 两组光环 + 一个技能窗口摞起来能超过 1，而 `randf() < 1.2` 恒为真 ——
	# 那时暴击率这个数就没有意义了，屏幕上只表现为「怎么每一下都是黄的」。
	var attacker := PBAttacker.new()
	attacker.crit_chance = 0.9
	_hang(attacker, PBBuffRules.CRIT_CHANCE, 0.9)
	assert_eq(PBCritRules.chance_of(attacker, 0), 1.0, "暴击率封在 1")


func test_the_crit_damage_bonus_is_extra_not_a_multiplier() -> void:
	# 存「额外多打几成」而不是「倍数」，所以中性值是 0.0 —— 和量型键
	# （累加、空 = 0）天然对得上。存倍数的话中性值得是 1.0，
	# 两份 +50% 会被连乘成 +125%。
	var attacker := PBAttacker.new()
	attacker.crit_bonus = 0.5
	_hang(attacker, PBBuffRules.CRIT_DAMAGE, 0.5)
	assert_almost_eq(
		PBCritRules.multiplier_of(attacker, 0),
		1.0 + PBCritRules.CRIT_DAMAGE_BASE + 1.0,
		0.0001,
		"基础 + 常驻 + 临时，全是加法"
	)


# ── 接进战斗 ──────────────────────────────────────────────────


func test_a_crit_really_lands_harder_in_a_real_battle() -> void:
	# 端到端：同一支队伍、同一波、同一颗种子，只有暴击率不同。
	# 判据是**总伤害**（拿敌人剩下多少血量），不是击杀数 ——
	# 击杀是离散的，一波打不满时它对小幅增伤没有分辨率。
	var wave := PBWaveRules.build(6, _cfg, _rng)
	assert_gt(_dealt(wave, 1.0), _dealt(wave, 0.0), "会暴击的那一队该打掉更多血")


func test_the_battle_log_says_which_hit_was_a_crit() -> void:
	# **只有播报说得准。** [PBDamageWatch] 比的是血量，而血量里既有暴击
	# 也有易伤，还会把连续几帧攒成一个数 —— 「哪一下是暴击」在那一层
	# 结构上不存在。所以标记必须从 sim 这一侧发出来。
	var wave := PBWaveRules.build(6, _cfg, _rng)
	var book := PBBattleLog.new()
	var sim := _sim(wave, 1.0, book)
	for _i: int in 200:
		sim.step()
	var crits: int = 0
	var hits: int = 0
	for entry: Dictionary in book.entries:
		if int(entry.get("kind", -1)) != PBBattleLog.Kind.HIT_ENEMY:
			continue
		hits += 1
		if bool(entry.get("crit", false)):
			crits += 1
	assert_gt(hits, 0, "该打中过")
	assert_eq(crits, hits, "暴击率 100% 时每一条命中都该标着暴击")


func test_a_ranged_shot_carries_its_crit_flag_across_the_flight() -> void:
	# 掷骰在**出膛**那一刻，标记背着子弹飞（同 [member PBProjectile.skill]）——
	# 命中那一刻施法者可能已经死了，回头去问问不到。
	# 而掷点必须只有一个：分到命中那一路就又是两把尺子。
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 3, 50.0, 0.1, false, PBElement.Type.PHYSICAL, 0, null, 1, true)
	assert_true(shot.crit, "出膛时记下的标记该留着")
	shot.retire()
	assert_false(shot.crit, "回池要清掉 —— 否则下一发会背着上一发的标记飞出去")


# ── 夹具 ──────────────────────────────────────────────────────


## 挂一份只带一个键的临时效果。
func _hang(unit: PBAttacker, key: StringName, value: float) -> void:
	var buff := PBBuff.new()
	buff.id = key
	buff.kind = PBBuff.Kind.DURATION
	unit.buffs.add(buff, {key: value}, 0, 100, 0)


## 一支会/不会暴击的队伍在这一波里打掉了多少血。
func _dealt(wave: PBWave, chance: float) -> float:
	var sim := _sim(wave, chance, null)
	for _i: int in 200:
		sim.step()
	var left: float = 0.0
	for enemy: PBEnemy in sim.enemies():
		left += maxf(enemy.hp, 0.0)
	return -left


## 一场只有三个普攻手的战斗。[param chance] 是他们的常驻暴击率。
func _sim(wave: PBWave, chance: float, book: PBBattleLog) -> PBBattleSim:
	var squad: Array[PBAttacker] = []
	for i: int in 3:
		var one := PBAttacker.new()
		one.slot = i
		one.dps = 60.0
		one.attack_speed = 1.0
		one.reach = 1.0
		one.crit_chance = chance
		one.pos = Vector2(0.3, _cfg.ally_lane(i, 3))
		one.home = one.pos
		squad.append(one)
	var dice := RandomNumberGenerator.new()
	dice.seed = 777
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad, dice)
	sim.log_to = book
	return sim


## 跑完一整局（波数压到 12，这个文件不是来量配平的）。
func _run() -> PBRunResult:
	var cfg := PBGameData.config()
	cfg.max_wave = 12
	return PBRunSim.run(cfg, PBStrategyRegistry.make(&"balanced"), 31337)
