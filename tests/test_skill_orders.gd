extends GutTest
## 暂停下攒指令、取消暂停一起放（§02，M7-h）。sim 那一侧，见 [PBSkillOrders]。
##
## ## 这个文件守的是「暂停时状态一个字都不变」
##
## 「同时放」在这一步之前就成立了 —— 暂停时 tick 不推进，几发的 `lands_at`
## 算出来本来就是同一个数。**真正不对的是另一半**：玩家点下去那一刻蓝就扣了、
## 自增益当场挂上、播报当场多一行，而且**反悔不了**。
## 《博德之门2》那套暂停的定义恰恰是「画面和状态都冻住，只收指令」。
##
## ## 以及「排队和当场放逐位等价」
##
## 放的时机排在 `_tick += 1` **之前**，所以两条路算出来的 `lands_at`
## 与冷却是同一个数 —— 这一步因此不改任何配平数字，
## 而最后那条测试直接对拍两局把它钉死。

const FIXED_SEED: int = 20260907

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	# 自动档会替玩家放大招，而这个文件量的是玩家自己下的令。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 一个不出手的忍者：这个文件只关心技能，普攻会把敌人打光、战斗提前结束。
func _idle(slot: int = 0) -> PBAttacker:
	var out := PBAttacker.new()
	out.slot = slot
	out.dps = 0.0
	out.attack_speed = 0.0
	out.pos = Vector2(0.3, 0.0)
	out.reach = 0.0
	out.max_hp = 1.0e9
	out.hp = out.max_hp
	out.max_mp = 1000.0
	out.mp = 1000.0
	return out


func _skill(tier: int, delay: int = 0) -> PBSkill:
	var out := PBSkill.new()
	out.id = &"probe"
	out.target = tier
	out.affects = (PBSkill.Party.ALLIES if tier == PBSkill.Target.ALLY else PBSkill.Party.ENEMIES)
	out.radius = 1.0
	out.cooldown_ticks = 100
	out.delay_ticks = delay
	out.mp_cost = 10.0
	return out


func _give(live: PBAttacker, tier: int, delay: int = 0) -> PBSkillCast:
	var cast := PBSkillCast.new(_skill(tier, delay))
	live.skills.append(cast)
	return cast


func test_a_wave_starts_with_an_empty_queue() -> void:
	# 攻击者对象跨波复用，上一波没放出去的令漏进这一波的表现是
	# 「开波自己放了一发」，而它不报错。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	_give(squad[0], PBSkill.Target.NONE)
	sim.step()
	assert_true(sim.cast_skill_now(squad[0], 1), "前提：令下得出去")

	var next := PBBattleSim.new(_wave(5), 0.0, 0.0, _cfg, squad)
	assert_eq(next.orders().count(), 0, "开波指令队列是空的")
	assert_eq(next.order_of(squad[0]), -1, "上一波那条不许漏过来")


func test_the_order_waits_and_nothing_moves_while_it_waits() -> void:
	# **正题的前一半**：下了令，游戏状态一个字都不变。
	var book := PBBattleLog.new()
	var squad: Array[PBAttacker] = [_idle()]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	sim.log_to = book
	var cast := _give(squad[0], PBSkill.Target.NONE)
	cast.reset()
	sim.step()
	var mp: float = squad[0].mp

	assert_true(sim.cast_skill_now(squad[0], 1), "令收下了")
	assert_eq(sim.order_of(squad[0]), 1, "攒在手上")
	assert_false(cast.is_pending(), "但技能还没出手")
	assert_almost_eq(squad[0].mp, mp, 1e-9, "蓝一点都不该扣 —— 他还没放")
	assert_eq(_casts_logged(book), 0, "播报也不该多一行")

	sim.step()
	assert_eq(sim.order_of(squad[0]), -1, "推进一个 tick 就放出去了")
	assert_eq(_casts_logged(book), 0, "起手还没释放")
	PBCastTestClock.release(sim, squad[0])
	assert_eq(_casts_logged(book), 1, "播报也是这时候才记")


## 播报里记了几发忍术。**只数这一种** —— 敌人还手那几条每 tick 都在涨。
func _casts_logged(book: PBBattleLog) -> int:
	var count: int = 0
	for entry: Dictionary in book.entries:
		if int(entry.get("kind", -1)) == PBBattleLog.Kind.ULTIMATE:
			count += 1
	return count


func test_five_orders_all_go_off_on_the_same_tick() -> void:
	# **玩家的原话**：暂停中给 5 个忍者各选目标放技能，取消暂停 5 个同时放。
	var squad: Array[PBAttacker] = []
	var casts: Array[PBSkillCast] = []
	for i: int in 5:
		var one := _idle(i)
		one.pos = Vector2(0.3, 0.0)
		squad.append(one)
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	for one: PBAttacker in squad:
		var cast := _give(one, PBSkill.Target.GROUND, 5)
		cast.reset()
		casts.append(cast)
	sim.step()

	# 「暂停」在 sim 这一侧就是「不调 step」——五条令下在同一个 tick 上。
	for i: int in 5:
		assert_true(sim.cast_skill(squad[i], Vector2(0.5, 0.0), 1), "第 %d 条令下得出" % i)
	assert_eq(sim.orders().count(), 5, "五条全攒着")
	for cast: PBSkillCast in casts:
		assert_false(cast.is_pending(), "取消暂停之前一发都没出手")

	sim.step()
	var lands: int = casts[0].lands_at
	assert_gt(lands, 0, "前提：第一发真的出手了")
	for cast: PBSkillCast in casts:
		assert_true(cast.is_pending(), "取消暂停之后五发一起出手")
		assert_eq(cast.lands_at, lands, "而且落在同一个 tick 上")


func test_a_new_order_replaces_the_one_he_was_holding() -> void:
	# 一个人手上只攒一条（同 War3 / BG2：新指令替换当前动作）。
	# 队列因此是「每人一格」的定长数组，上限是结构性的而不是拍出来的。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	_give(squad[0], PBSkill.Target.GROUND).reset()
	_give(squad[0], PBSkill.Target.GROUND).reset()
	sim.step()

	assert_true(sim.cast_skill(squad[0], Vector2(0.3, 0.0), 1), "先下第 1 格")
	assert_true(sim.cast_skill(squad[0], Vector2(0.7, 0.0), 2), "再下第 2 格")
	assert_eq(sim.orders().count(), 1, "手上还是只有一条")
	assert_eq(sim.order_of(squad[0]), 2, "后下的那条说了算")
	assert_almost_eq(sim.orders().spot_of(0).x, 0.7, 1e-6, "落点也跟着换成后下的")


func test_cancelling_leaves_no_trace() -> void:
	var squad: Array[PBAttacker] = [_idle()]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var cast := _give(squad[0], PBSkill.Target.NONE)
	cast.reset()
	sim.step()
	var mp: float = squad[0].mp

	sim.cast_skill_now(squad[0], 1)
	sim.cancel_order(squad[0])
	assert_eq(sim.orders().count(), 0, "收回之后队列是空的")
	sim.step()
	assert_false(cast.is_pending(), "收回的那一条不该在下一个 tick 冒出来")
	assert_almost_eq(squad[0].mp, mp, 1e-9, "蓝也一点没动")


func test_an_order_from_a_dead_caster_is_dropped() -> void:
	# 放出去那一刻要重新过一遍门槛 —— 暂停期间这些不会变，
	# 但实时下达时中间隔着一个 tick。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var cast := _give(squad[0], PBSkill.Target.NONE)
	cast.reset()
	sim.step()
	sim.cast_skill_now(squad[0], 1)

	squad[0].alive = false
	sim.step()
	assert_false(cast.is_pending(), "死人手上那条令就该丢掉")


func test_an_order_on_a_dead_mate_is_dropped() -> void:
	var one := _idle(0)
	var two := _idle(1)
	var squad: Array[PBAttacker] = [one, two]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var cast := _give(one, PBSkill.Target.ALLY)
	cast.reset()
	sim.step()
	assert_true(sim.cast_skill_on(one, two, 1), "下令时他还站着")

	two.alive = false
	sim.step()
	assert_false(cast.is_pending(), "轮到放的时候他已经倒了，这一条丢掉")


func test_the_auto_policy_never_goes_through_the_queue() -> void:
	# **扫描那一路一条指令都不会下**（§6：批量扫描不吃技能），
	# 而队列空时 [method PBSkillOrders.flush] 直接早退 ——
	# 这一步因此不动任何既有配平数字，那一整套断言仍由原来那些文件钉着。
	#
	# 反过来说，自动档那一支**不许**改道走队列：走了的话每一发大招
	# 都会晚一个 tick 落地，而那是配平数字，且不报错。
	_cfg.aim_policy = PBAimRules.Policy.AUTO
	var caster := _idle()
	caster.pos = Vector2(0.5, 0.0)
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(8), 0.0, 0.0, _cfg, squad)
	caster.ultimate = PBSkillCast.new(_skill(PBSkill.Target.GROUND))
	caster.ultimate.skill.damage = 1.0e6
	caster.ultimate.skill.radius = 10.0
	caster.ultimate.reset()

	# 两个 tick：第一个下达（落地那一趟排在下达之前，见 [method PBBattleSim.step]），
	# 第二个落地。**队列在这中间一次都没被用到。**
	sim.step()
	assert_eq(sim.orders().count(), 0, "自动档一条指令都没进过队列")
	PBCastTestClock.release(sim, caster)
	assert_gt(sim.result().kills, 0, "而那一发照旧按原来的节奏落了地")
