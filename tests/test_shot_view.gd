extends GutTest
## 子弹的美术、出手点、命中火花（M8-a）。
##
## ## 这个文件守的是「画面和判定说的是同一件事」
##
## sim 里子弹从**脚底**飞到**脚底**（那边是个平面，没有高度轴），
## 而屏幕上它必须从**枪口**飞到**胸口**。两者是同一次飞行的重新参数化 ——
## 进度仍然是 sim 算的那个比例。抄成两份的话，画面上的子弹会在
## 「已经打中了」之后还飞一小段，而那正是 [PBShotPool] 顶上那条
## 「渲染层不许撒谎」要挡的东西。

const FIXED_SEED: int = 20260908

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


func _field() -> Vector2:
	return Vector2(_cfg.field_length, _cfg.field_height)


func _shooter(slot: int = 0) -> PBAttacker:
	var out := PBAttacker.new()
	out.slot = slot
	out.dps = 0.0
	out.attack_speed = 0.0
	out.pos = Vector2(0.3, 0.0)
	out.max_hp = 1000.0
	out.hp = out.max_hp
	return out


func _sim(squad: Array[PBAttacker]) -> PBBattleSim:
	return PBBattleSim.new(PBWaveRules.build(4, _cfg, _rng), 0.0, 0.0, _cfg, squad)


func _pool() -> PBShotPool:
	var pool := PBShotPool.new()
	add_child_autofree(pool)
	return pool


# ── 白模：链路今天就是通的 ──────────────────────────────────────


func test_the_white_shot_carries_both_a_flight_and_a_hit() -> void:
	# 分成两份资源的话，「配了子弹忘了配特效」的表现是打中之后什么都不发生，
	# 而它不报错。白模因此也必须两段齐全 —— 它是第一个「换皮」的样本。
	var art := PBWhiteModel.shot()
	assert_true(art.has(art.anim_fly), "飞行那一段该有")
	assert_true(art.has(art.anim_hit), "命中那一段也该有")
	assert_gt(art.hit_seconds(), 0.0, "命中那一段该有时长，否则火花不知道活多久")


func test_a_missing_shot_folder_is_not_an_error() -> void:
	# `assets/` 里一张子弹图都没有，目录长期是空的 —— 正确的行为是退回白模，
	# 不是每帧刷一条错（同 [PBActorLibrary]）。
	assert_eq(PBShotLibrary.load_from("res://data/_no_such_folder").size(), 0, "空表，不报错")
	assert_null(PBShotLibrary.skin_for(&"_nothing_here"), "查不到就是 null，调用方退白模")


# ── 出手点 ──────────────────────────────────────────────────────


func test_the_muzzle_is_above_the_feet_and_the_chest_below_the_head() -> void:
	# 这两个数在 M8-a 之前根本不存在：子弹是**从脚踝射向脚踝**的，
	# 而人从 M6-m 起有 60 像素高。
	var skin := PBActorSkin.new()
	skin.height_px = 60.0
	assert_lt(skin.muzzle().y, 0.0, "枪口在脚底上方（屏幕 y 向下）")
	assert_lt(skin.muzzle().y, skin.chest().y, "枪口要比胸口高")
	assert_gt(skin.chest().y, -skin.head_px(), "胸口不能高过头顶")


func test_the_muzzle_follows_the_texture_scale() -> void:
	# [member PBActorSkin.muzzle_offset] 填的是**画布像素**（同 `foot_offset`），
	# 而屏幕上的偏移要乘 [member PBActorSkin.pixel_scale] ——
	# 不乘的话高清档（贴图比屏幕大三倍）的枪口会落在膝盖上。
	var skin := PBActorSkin.new()
	skin.muzzle_offset = Vector2(4.0, -30.0)
	skin.pixel_scale = 0.5
	assert_eq(skin.muzzle(), Vector2(2.0, -15.0), "配了就按配的算，并且乘缩放")


func test_a_bullet_leaves_the_muzzle_not_the_feet() -> void:
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var shot: PBProjectile = sim.shots()[0]
	shot.launch(squad[0].pos, 0, 10.0, 0.01, false, PBElement.Type.PHYSICAL, 0)

	pool.sync_shots(sim, [], null, _field())
	assert_eq(pool.shown(), 1, "在飞的那一发要画出来")
	var feet := PBLayout.to_screen(squad[0].pos, _field())
	assert_lt(pool.at(0).y, feet.y, "出膛的点在脚底上方")


func test_the_bullet_on_screen_walks_the_same_fraction_the_sim_flew() -> void:
	# **进度是 sim 算的那一个**：屏幕上重新算一遍的话，两条弹道会分叉，
	# 而分叉的表现是「子弹还在半路，伤害数字已经飘出来了」。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var mark: PBEnemy = sim.enemies()[0]
	var shot: PBProjectile = sim.shots()[0]
	shot.launch(squad[0].pos, mark.slot, 10.0, 0.01, false, PBElement.Type.PHYSICAL, 0)

	pool.sync_shots(sim, [], null, _field())
	var start := pool.at(0)
	# 挪到正中间：sim 里飞了一半，屏幕上就该正好在两端的中点。
	shot.pos = squad[0].pos.lerp(mark.pos(), 0.5)
	pool.sync_shots(sim, [], null, _field())
	var middle := pool.at(0)
	shot.pos = mark.pos()
	pool.sync_shots(sim, [], null, _field())
	var landed := pool.at(0)

	assert_almost_eq(middle.x, (start.x + landed.x) * 0.5, 0.5, "飞了一半就画在一半上")
	assert_almost_eq(middle.y, (start.y + landed.y) * 0.5, 0.5, "两轴都是")


# ── 命中火花 ────────────────────────────────────────────────────


func test_a_hit_lights_a_spark_and_it_goes_out_on_its_own() -> void:
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var book := PBBattleLog.new()

	pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.sparks(), 0, "什么都没发生的时候不该有火花")

	book.hit(1, 0, sim.enemies()[0].slot, 12.0, false)
	pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.sparks(), 1, "播报里多一条命中，屏幕上就该多一朵火花")

	for _i: int in 120:
		pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.sparks(), 0, "它自己会灭 —— 池子不会被一朵火花永久占住")


func test_a_melee_hit_lights_one_too() -> void:
	# 玩家定的：近远统一。近战没有子弹可看，反而更需要那一下 ——
	# 走播报那条路它是顺带成立的，因为播报本来就不分远近。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var book := PBBattleLog.new()
	# 敌人打忍者那个方向也一样（`to_ally` 为真）。
	book.hit(1, sim.enemies()[0].slot, 0, 9.0, true)
	pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.sparks(), 1, "两个方向的命中都要出火花")


func test_the_spark_still_fires_after_the_log_has_wrapped() -> void:
	# **M8-a 顺带修的那条真 bug。** 上限是环形的，写满之后
	# `entries.size()` 恒等于 CAP，于是「消化到第几条」和「一共有几条」
	# 永远相等 —— 特效从此再也不触发，而日志面板一切正常。
	# M7-f 的施法回音从落地那天起就带着这条，200 条大概只有三四波。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var book := PBBattleLog.new()
	for i: int in PBBattleLog.CAP + 5:
		book.note(i, "撑满它")
	pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.sparks(), 0, "前提：这些不是命中，不该出火花")
	assert_eq(book.entries.size(), PBBattleLog.CAP, "前提：日志已经写满了")

	book.hit(1, 0, sim.enemies()[0].slot, 12.0, false)
	pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.sparks(), 1, "写满之后新来的命中照样要出火花")


func test_the_cursor_counts_entries_ever_written_not_entries_kept() -> void:
	# 上一条的根因本身。各家渲染层自己去减那道差的话，抄漏一处的表现是
	# 「某一种特效在长局里会消失」，所以这道减法收在日志自己身上。
	var book := PBBattleLog.new()
	for i: int in PBBattleLog.CAP + 20:
		book.note(i, "第 %d 条" % i)
	assert_eq(book.total, PBBattleLog.CAP + 20, "记过多少条是只增不减的")
	assert_eq(book.fresh_from(book.total), PBBattleLog.CAP, "全消化完了就没有新的")
	assert_eq(book.fresh_from(book.total - 3), PBBattleLog.CAP - 3, "差三条就从倒数第三条起")
	assert_eq(book.fresh_from(0), 0, "一条都没消化过就从头开始（丢掉的那些追不回来）")


# ── 技能的子弹 ──────────────────────────────────────────────────


func test_a_ground_skill_in_flight_is_drawn_as_a_bullet() -> void:
	# **地面档那段施法延迟本来就是飞行时间**（M3-b 起就在），
	# 只是屏幕上一直只有一个落点预示圈。这里没有新加任何飞行：
	# 进度读的是 `lands_at`，伤害仍然在那一 tick 结算。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var skill := PBSkill.new()
	skill.radius = 0.1
	skill.delay_ticks = 20
	skill.cooldown_ticks = 100
	squad[0].skills.append(PBSkillCast.new(skill))
	squad[0].skills[0].reset()
	sim.step()
	assert_true(sim.cast_skill(squad[0], Vector2(0.7, 0.0), 1), "前提：这一发放得出去")
	sim.step()

	pool.sync_shots(sim, [], null, _field())
	assert_eq(pool.shown(), 1, "在飞的那一发技能要画出来")
	var early := pool.at(0)
	for _i: int in 10:
		sim.step()
	pool.sync_shots(sim, [], null, _field())
	assert_eq(pool.shown(), 1, "还在飞")
	assert_gt(pool.at(0).x, early.x, "而且真的往落点挪了")

	for _i: int in 20:
		sim.step()
	pool.sync_shots(sim, [], null, _field())
	assert_eq(pool.shown(), 0, "落地那一刻就收 —— 判定结束了，画面也该结束")


func test_a_skill_without_a_cast_delay_never_draws_a_bullet() -> void:
	# 锁定档（治疗）延迟恒为 0（[method PBSkillRules.validate] 拦着）——
	# 画一发瞬间到达的子弹等于画一条撒谎的弹道。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var skill := PBSkill.new()
	skill.target = PBSkill.Target.ALLY
	skill.affects = PBSkill.Party.ALLIES
	skill.cooldown_ticks = 100
	squad[0].skills.append(PBSkillCast.new(skill))
	squad[0].skills[0].reset()
	sim.step()
	sim.cast_skill_on(squad[0], squad[0], 1)
	sim.step()

	pool.sync_shots(sim, [], null, _field())
	assert_eq(pool.shown(), 0, "瞬发的那一档不画子弹")


# ── 池子 ────────────────────────────────────────────────────────


func test_the_pool_is_built_once_and_never_grows() -> void:
	# §14：热路径一次 `.new()` 都不许有。子弹与火花两个池子都按上限一次建满。
	var pool := _pool()
	var built: int = pool.get_child_count()
	assert_eq(built, PBShotPool.CAPACITY + PBShotPool.CASTS + PBShotPool.IMPACTS, "三个池子一次建满")

	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var book := PBBattleLog.new()
	for i: int in 200:
		book.hit(i, 0, sim.enemies()[0].slot, 1.0, false)
		sim.shots()[i % PBBattleSim.SHOT_CAPACITY].launch(
			squad[0].pos, 0, 1.0, 0.01, false, PBElement.Type.PHYSICAL, 0
		)
		pool.sync_shots(sim, [], book, _field())
	assert_eq(pool.get_child_count(), built, "跑了两百帧，一个节点都没多出来")
	assert_lte(pool.sparks(), PBShotPool.IMPACTS, "火花也钳在上限里")


func test_clearing_puts_everything_back() -> void:
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	sim.shots()[0].launch(squad[0].pos, 0, 1.0, 0.01, false, PBElement.Type.PHYSICAL, 0)
	pool.sync_shots(sim, [], null, _field())
	assert_eq(pool.shown(), 1, "前提：有一发在飞")

	pool.clear()
	assert_eq(pool.shown(), 0, "收干净")
	assert_eq(pool.sparks(), 0, "火花也收干净")
