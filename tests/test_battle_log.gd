extends GutTest
## 战斗日志播报。§02，M6-j。
##
## ## 这个文件守的是什么
##
## 播报有一类特别难发现的失败：**某一种事件根本没被记下来，而面板照样有内容**
## （另外五种把它盖住了）。所以这里逐条钉「这一种真的记下来了」，
## 而不是只断「日志非空」。
##
## 另外两条是它存在的前提：**扫描那一路一个字都不记**（默认 null，
## 一局几万 tick），以及**怪物死亡不记**（玩家定的：一波死几十只，
## 每只一行会把另外五种全部冲掉）。

const CROSS_TICKS: int = 500

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	# 压平战场：本文件测的是「记没记下来」，纵向一条都不涉及。
	_cfg.field_height = 0.0
	_cfg.enemy_ranged_share = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260902


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## **攻速必须给一个真值。** 攻速为 0 走的是 [method PBStrikeRules._pour_damage]
## 那条连续输出的退化路径（M3-a 的对拍锚点），它每 tick 浇一次伤害 ——
## 播报不接在那一条上，接了就是每 tick 一行。真角色表里没有攻速为 0 的人
## （[method PBCombatRules.build_attackers] 从属性算），所以那条路上游戏里走不到。
func _unit(at_x: float, hp: float, dps: float, reach: float = 0.2) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = dps
	out.attack_speed = 1.0
	out.pos = Vector2(at_x, 0.0)
	out.reach = reach
	out.max_hp = hp
	out.hp = hp
	out.def_element = PBElement.Type.PHYSICAL
	return out


func _sim(wave: PBWave, squad: Array[PBAttacker], log: PBBattleLog = null) -> PBBattleSim:
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.log_to = log
	return sim


func _kinds(log: PBBattleLog) -> Array:
	var out: Array = []
	for entry: Dictionary in log.entries:
		if not out.has(entry["kind"]):
			out.append(entry["kind"])
	return out


func test_a_scan_run_records_nothing_at_all() -> void:
	# **这是它敢接进 sim 的全部理由。** 批量扫描一局跑几万 tick，
	# 每一发都记就是几十万次分配 —— 而那些字一个人都不会看。
	# 默认关掉之后，扫描那一路和 M6-j 之前逐字节相同。
	var squad: Array[PBAttacker] = [_unit(0.30, 1.0e9, 50.0)]
	var sim := _sim(_wave(9), squad)
	sim.run_to_end()
	assert_null(sim.log_to, "不塞日志进去就该一直是 null")


func test_both_directions_of_damage_get_recorded() -> void:
	# 「谁对谁造成了 XX 点伤害」——**两个方向都要**。
	# 只记一边的话玩家看到的是一场自己单方面输出（或者单方面挨打）的战斗。
	var log := PBBattleLog.new()
	var squad: Array[PBAttacker] = [_unit(0.30, 1.0e9, 50.0)]
	_sim(_wave(9), squad, log).run_to_end()
	var kinds := _kinds(log)
	assert_true(kinds.has(PBBattleLog.Kind.HIT_ENEMY), "忍者打敌人要记")
	assert_true(kinds.has(PBBattleLog.Kind.HIT_ALLY), "敌人打忍者也要记")
	for entry: Dictionary in log.entries:
		if entry["kind"] == PBBattleLog.Kind.HIT_ENEMY:
			assert_gte(int(entry["source"]), 0, "打人的那个必须有下标，否则面板上是个问号")
			assert_gt(float(entry["amount"]), 0.0, "记一发 0 伤害没有意义")


func test_a_dead_ninja_is_announced_but_a_dead_monster_is_not() -> void:
	# 玩家的原话：**忍者死亡（怪物死亡不算）**。
	# 一波死几十只怪，每只一行会把另外五种播报全部冲掉。
	var log := PBBattleLog.new()
	# 血和伤害都要留余量：1 血的人在敌人一够着就倒，一只怪都来不及打死（前提断言会红，而播报没错）。
	var squad: Array[PBAttacker] = [_unit(0.30, 200.0, 500.0)]
	var sim := _sim(_wave(9), squad, log)
	sim.run_to_end()
	assert_eq(sim.result().allies_lost, 1, "前提：这个忍者真的被打死了")
	assert_gt(sim.result().kills, 0, "前提：也真的打死了一些怪")
	var downs: int = 0
	for entry: Dictionary in log.entries:
		if entry["kind"] == PBBattleLog.Kind.ALLY_DOWN:
			downs += 1
	assert_eq(downs, 1, "忍者倒下要记，而且只记一次")
	# 怪物那一侧没有对应的 Kind —— 断言它压根不存在，比断「条数不多」结实。
	assert_false(PBBattleLog.Kind.has("ENEMY_DOWN"), "怪物死亡不该有播报类型")


func test_a_leak_says_how_much_the_base_took() -> void:
	# 基地掉血在画面上只有一瞬间的提示，而它恰恰是「这一波为什么没守住」
	# 唯一的证据。**一个人都不带**，整波必定漏光。
	var log := PBBattleLog.new()
	var sim := _sim(_wave(9), [] as Array[PBAttacker], log)
	sim.run_to_end()
	assert_gt(sim.result().leaked, 0, "前提：这一波确实漏了")
	var hits: int = 0
	var total: float = 0.0
	for entry: Dictionary in log.entries:
		if entry["kind"] == PBBattleLog.Kind.BASE_HIT:
			hits += 1
			total += float(entry["amount"])
	assert_eq(hits, sim.result().leaked, "漏一只就该记一条")
	assert_almost_eq(total, sim.result().base_damage, 0.01, "记下来的伤害要和结算对得上")


func test_casting_a_jutsu_is_announced_at_release() -> void:
	# **下达那一刻记，不是落地那一刻**：玩家点下去就该看见回音，
	# 而落地还隔着一整段施法延迟（§02 要的预判窗口）。
	# 落点策略关掉：自动档会在开波第一 tick 替他放掉，那时这条断言
	# 数到的是自动那一发，而不是手动下达的这一发。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	var log := PBBattleLog.new()
	var squad: Array[PBAttacker] = [_unit(0.30, 1.0e9, 50.0)]
	var skill := PBSkill.new()
	skill.radius = 0.2
	skill.damage = 10.0
	squad[0].ultimate = PBSkillCast.new(skill)
	var sim := _sim(_wave(9), squad, log)
	sim.step()
	assert_true(sim.cast_skill(squad[0], Vector2(0.5, 0.0)), "前提：这一发放得出去")
	# 玩家下的令先攒一个 tick（M7-h，见 [PBSkillOrders]）——
	# 播报记的是**出手**那一刻，而那一刻在下一个 tick 上。
	PBCastTestClock.release(sim, squad[0])
	var casts: int = 0
	for entry: Dictionary in log.entries:
		if entry["kind"] == PBBattleLog.Kind.ULTIMATE:
			casts += 1
	assert_eq(casts, 1, "第 4 帧释放记一条，不等落地")


func test_the_ring_buffer_drops_the_oldest_not_the_newest() -> void:
	# 一局能打上百波，而只有最新的几十行有人看。
	# 反过来（记满就停）会让日志停在第一波，那一格屏幕从此再不更新 ——
	# 而它看起来只是「日志好像不动了」。
	var log := PBBattleLog.new()
	for i: int in PBBattleLog.CAP + 20:
		log.note(i, "第 %d 条" % i)
	assert_eq(log.entries.size(), PBBattleLog.CAP, "上限该钳住")
	assert_eq(log.entries[0]["text"], "第 20 条", "丢的是最老的")
	assert_eq(
		log.entries[log.entries.size() - 1]["text"], "第 %d 条" % (PBBattleLog.CAP + 19), "最新的一条必须还在"
	)
