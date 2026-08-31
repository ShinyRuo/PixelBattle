extends GutTest
## 手感那一段：命中白闪、伤害飘字、击杀顿帧、落点预示带。§02，M3.5-h。
##
## ## 这个文件守的是一条铁律
##
## **顿帧绝不能碰 tick 序列。** 它只是几帧不推进，等同于按了几帧暂停；
## 走完之后 tick 一个不多一个不少。用「跳过一个 tick」或者
## `Engine.time_scale` 来做的话，同一个种子跑出来的局会慢慢对不上，
## 而 §12 的存档回滚、§13 的战报回放与每日种子全都建立在那条一致性上。
##
## 其余几条测的是「这个反馈真的会出现，而且不会在不该出现的时候出现」。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const FIXED_SEED: int = 20260830

## 战场尺寸 `(长, 高)`。落点预示要靠它把 sim 坐标换成屏幕坐标（M4-a）。
const FIELD := Vector2(1.0, 0.25)

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


func _wave() -> PBWave:
	return PBWaveRules.build(3, _cfg, _rng)


## 一场打得动的战斗。
func _battle(dps: float) -> PBBattleSim:
	return PBBattleSim.new(_wave(), dps, 0.0, _cfg, [] as Array[PBAttacker])


## 一局自动推进的战斗画面，同种子。
func _spawn() -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = true
	add_child_autofree(root)
	return root


# ── 逐帧血量比对 ──────────────────────────────────────────────


func test_the_first_poll_never_reports_damage() -> void:
	# 第一帧没有「上一帧」。不特判的话，快照初值 0 会让整波敌人
	# 在开波瞬间各挨一发等于满血的伤害 —— 满屏飘字。
	var sim := _battle(400.0)
	var watch := PBDamageWatch.new()
	sim.step()
	assert_eq(watch.poll(sim.enemies(), sim.current_tick()).size(), 0, "第一次比对该只建快照")


func test_it_reports_who_got_hit_this_frame() -> void:
	var sim := _battle(400.0)
	var watch := PBDamageWatch.new()
	for _i: int in 3:
		sim.step()
		watch.poll(sim.enemies(), sim.current_tick())
	var seen: int = 0
	for _i: int in 40:
		sim.step()
		seen += watch.poll(sim.enemies(), sim.current_tick()).size()
		if seen > 0:
			break
	assert_gt(seen, 0, "打得动的时候总该有人挨打")


func test_small_hits_flash_but_do_not_float_a_number() -> void:
	# 逐 tick 的普攻每次只掉一点点血。每一下都飘字的话，
	# 一波潮水就是一屏滚动的「3」。
	var sim := _battle(30.0)
	var watch := PBDamageWatch.new()
	var hits: int = 0
	var shown: int = 0
	for _i: int in 60:
		sim.step()
		for hit: Dictionary in watch.poll(sim.enemies(), sim.current_tick()):
			hits += 1
			if float(hit["shown"]) > 0.0:
				shown += 1
	assert_gt(hits, 0, "小伤害也要报出来（那一层是白闪）")
	assert_lt(shown, hits, "但不该每一下都飘一个数")


func test_a_kill_always_floats_a_number() -> void:
	# 最后一下掉的血可能只有 1%，但那一下是玩家最想看到的一下。
	var sim := _battle(4000.0)
	var watch := PBDamageWatch.new()
	var killed_and_shown: int = 0
	for _i: int in 120:
		sim.step()
		for hit: Dictionary in watch.poll(sim.enemies(), sim.current_tick()):
			if bool(hit["killed"]):
				assert_gt(float(hit["shown"]), 0.0, "击杀必须飘出一个数")
				killed_and_shown += 1
	assert_gt(killed_and_shown, 0, "这场应该打死过人")


func test_resetting_forgets_the_previous_wave() -> void:
	# 不清的话，开波第一帧会把「上一波那个槽位剩 3 点血」和
	# 「这一波满血」的差算成一次伤害。
	var sim := _battle(4000.0)
	var watch := PBDamageWatch.new()
	for _i: int in 60:
		sim.step()
		watch.poll(sim.enemies(), sim.current_tick())
	watch.reset()
	var fresh := _battle(4000.0)
	fresh.step()
	assert_eq(watch.poll(fresh.enemies(), fresh.current_tick()).size(), 0, "清过之后又是第一帧")


# ── 顿帧不碰 tick 序列 ────────────────────────────────────────


func test_hitstop_never_changes_the_tick_sequence() -> void:
	# **本文件最要紧的一条。** 顿帧只是几帧不推进，走完之后
	# tick 一个不多一个不少 —— 那是 §12 / §13 的地基。
	# **两局必须同时起跑。** 先跑完一局再起另一局的话，第一局在第二局
	# 跑的那段时间里还在推进 —— 量出来的差值是那段时间，不是顿帧。
	# **量得早一点**（M4-d）：一次全刷之后单波短得多，等到五十几帧
	# 两局可能都已经打完了 —— 那时两边的 tick 都停在终点上，
	# 差值恒为 0，这条看着绿其实什么都没测。
	var plain := _spawn()
	var stopped := _spawn()
	await wait_physics_frames(4)
	# 硬塞一段顿帧。之后两局吃到的物理帧数完全一样，差的正好是这 12 帧。
	stopped._hitstop_frames = 12
	await wait_physics_frames(18)

	assert_false(plain._battle.is_finished(), "还没打完 —— 打完了就量不到差值了")
	assert_eq(
		stopped._battle.current_tick(),
		plain._battle.current_tick() - 4,
		"顿了 12 个物理帧就该正好晚 4 个 tick（每 3 帧一个 tick），不多不少"
	)
	var a: PBCombatOutcome = plain._battle.result()
	var b: PBCombatOutcome = stopped._battle.result()
	assert_eq(a.kills + a.leaked >= b.kills + b.leaked, true, "顿帧只会让它走得慢，不会走出别的结果")


func test_a_swarm_does_not_stutter_on_every_kill() -> void:
	# 潮水波一秒能死七八个，每个都顿一下就是持续抖动 ——
	# 那时顿帧不再是强调，而是卡顿。
	var root := _spawn()
	await wait_physics_frames(20)
	if root._plan.wave.shape != PBWave.Shape.SWARM:
		pass_test("这一局的第一波不是潮水波，这条用例不适用")
		return
	var stopped_frames: int = 0
	for _i: int in 90:
		await wait_physics_frames(1)
		if root._hitstop_frames > 0:
			stopped_frames += 1
	assert_lt(stopped_frames, 45, "潮水波里顿帧不该占掉一半的帧")


# ── 落点预示带 ────────────────────────────────────────────────


func test_the_telegraph_only_shows_while_a_strike_is_in_the_air() -> void:
	# 施法延迟存在的全部理由就是让玩家看得见落点（[PBUltimate] 顶部）。
	# 落地之后还画着的话，玩家会去躲一发已经结算完的大招。
	var pool := PBTelegraphPool.new()
	add_child_autofree(pool)
	var ult := PBUltimate.new()
	ult.radius = 0.2
	ult.delay_ticks = 10
	ult.spot = Vector2(0.5, 0.1)
	ult.lands_at = 30
	var attacker := PBAttacker.new()
	attacker.ultimate = ult
	var squad: Array[PBAttacker] = [attacker]

	pool.sync_pending(squad, 25, FIELD)
	assert_gt(pool.shown(), 0, "还在空中时该画出来")
	pool.sync_pending(squad, 30, FIELD)
	assert_eq(pool.shown(), 0, "落地那一刻就该收掉")

	ult.spot = PBUltimate.NO_SPOT
	pool.sync_pending(squad, 20, FIELD)
	assert_eq(pool.shown(), 0, "没有待落地的大招时什么都不画")


func test_the_telegraph_covers_exactly_what_the_strike_will_hit() -> void:
	# **M4-a 起画的是圆，不是竖带。** 在那之前 `radius` 只作用在推进轴上，
	# 纵向是渲染层编的装饰，画成圆会让玩家去躲一个不存在的纵向判定；
	# 纵向搬进 sim 之后那条理由反过来了 —— 带子才是谎话。
	#
	# 圈心和半径差几个像素的话，玩家看到的是「大招好像打偏了」。
	var pool := PBTelegraphPool.new()
	add_child_autofree(pool)
	var ult := PBUltimate.new()
	ult.radius = 0.1
	ult.delay_ticks = 10
	ult.spot = Vector2(0.5, 0.15)
	ult.lands_at = 30
	var attacker := PBAttacker.new()
	attacker.ultimate = ult
	pool.sync_pending([attacker] as Array[PBAttacker], 25, FIELD)

	assert_eq(pool.shown(), 1, "该有一个圈")
	assert_almost_eq(
		pool.center_of(0), PBEnemyPool.to_screen(ult.spot, FIELD), Vector2(0.01, 0.01), "圈心对上落点"
	)
	# **两轴共用同一个像素比例**，所以半径是一个数而不是两个 ——
	# 各算各的话画出来是椭圆，而判定是圆。
	assert_almost_eq(
		pool.radius_of(0), ult.radius * PBEnemyPool.px_per_unit(FIELD), 0.01, "半径按同一个比例换算"
	)


# ── 飘字池与接线 ──────────────────────────────────────────────


func test_the_pool_shows_a_number_and_retires_it_on_its_own() -> void:
	var pool := PBFloatTextPool.new()
	add_child_autofree(pool)
	pool.pop(Vector2(100.0, 150.0), 1234.0, false)
	assert_eq(_visible_labels(pool), 1, "飘一个就该看得见一个")
	for _i: int in PBFloatTextPool.LIFE_FRAMES + 1:
		pool.step()
	assert_eq(_visible_labels(pool), 0, "到期该自己收回去 —— 不收的话满屏都是旧数字")


func test_big_numbers_are_compressed() -> void:
	# 后期一发大招打六位数，原样写出来一个数字就有半个屏幕宽。
	var pool := PBFloatTextPool.new()
	add_child_autofree(pool)
	pool.pop(Vector2.ZERO, 999.0, false)
	assert_eq(_first_text(pool), "999", "一万以内照原样写")
	pool.clear()
	pool.pop(Vector2.ZERO, 123456.0, false)
	assert_true(_first_text(pool).ends_with("万"), "超过一万该折成「万」：%s" % _first_text(pool))


func test_taking_damage_reaches_the_screen() -> void:
	# **接线**：血掉了 → 白闪 + 飘字。存了却不画的话，
	# `PBDamageWatch` 的单测全绿而屏幕上什么都没有。
	var root := _spawn()
	await wait_physics_frames(10)
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "这时候该已经在打了")
	var floats: PBFloatTextPool = root.get_node("Floats")
	floats.clear()

	# 手动敲掉一个已出场敌人的一大截血，再走一帧比对。
	# 直接改 sim 是测试才做的事 —— 画面本身一个字段都不回写（§14）。
	var victim: PBEnemy = null
	for enemy: PBEnemy in root._battle.enemies():
		if enemy.is_active(root._battle.current_tick()):
			victim = enemy
			break
	assert_not_null(victim, "开打之后场上该有敌人")
	victim.take_damage(victim.max_hp * 0.5)
	root._feedback()
	assert_eq(_visible_labels(floats), 1, "挨了半管血该飘出一个数")


func _visible_labels(pool: PBFloatTextPool) -> int:
	var count: int = 0
	for child: Node in pool.get_children():
		if (child as Label).visible:
			count += 1
	return count


func _first_text(pool: PBFloatTextPool) -> String:
	for child: Node in pool.get_children():
		if (child as Label).visible:
			return (child as Label).text
	return ""
