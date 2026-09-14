extends GutTest
## 怪物的 30 种分类（6 属性 × 5 形态）与死亡那一段。M9-a/b/c。
##
## ## 为什么这几条值得测
##
## 这三样错了都**不报错**：
##
## - 档次或远近判错 → 挂错一张皮，屏幕上是「一只小怪长着精英的样子」
## - 皮键拼错一个字 → [PBActorLibrary] 查不到就**退回白模**，
##   表现是「素材接进来了还是白模」，而那正是 M6-e 造预览台要挡的那一层
## - 尸体没演完就藏 / 演完不藏 → 前者是怪凭空消失（M9-b 之前的样子），
##   后者是战场上堆满永远不走的尸体，而两样都不会有一句报错

const FORMS: Array[String] = ["melee", "ranged", "elite_melee", "elite_ranged", "boss"]

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func _wave(shape: PBWave.Shape, count: int) -> PBWave:
	var wave := PBWave.new()
	wave.index = 1
	wave.shape = shape
	wave.count = count
	wave.hp_each = 100.0
	wave.atk_each = 5.0
	wave.element = PBElement.Type.FIRE
	return wave


func _spawned(shape: PBWave.Shape, count: int) -> Array[PBEnemy]:
	var out: Array[PBEnemy] = []
	PBSpawnRules.fill(out, _wave(shape, count), _cfg, 0.05, 0.5)
	return out


func test_the_wave_shape_decides_the_rank() -> void:
	# **潮水波也是小怪、超级 BOSS 也是 BOSS**：屏幕上要分的是「长什么样」，
	# 而潮水波的怪和常规波的怪是同一种东西（只是更多更薄）。
	assert_eq(_spawned(PBWave.Shape.NORMAL, 3)[0].rank, PBEnemy.Rank.MINION, "常规波是小怪")
	assert_eq(_spawned(PBWave.Shape.SWARM, 3)[0].rank, PBEnemy.Rank.MINION, "潮水波也是小怪")
	assert_eq(_spawned(PBWave.Shape.ELITE, 3)[0].rank, PBEnemy.Rank.ELITE, "精英波是精英")
	assert_eq(_spawned(PBWave.Shape.BOSS, 2)[0].rank, PBEnemy.Rank.BOSS, "BOSS 波是 BOSS")
	assert_eq(_spawned(PBWave.Shape.MEGA_BOSS, 1)[0].rank, PBEnemy.Rank.BOSS, "超级 BOSS 也是")


func test_ranged_is_recorded_not_inferred_from_the_reach() -> void:
	# **这是「两把尺子」那一条**：`ranged` 必须是记下来的，不是从 `reach`
	# 反推的 —— 哪天两个射程配成同一个数，反推那一路就会把远程怪认成近战，
	# 而所有位置数字看起来都完全正确。
	#
	# 这里两头都断言：记的那个要和 `enemy_is_ranged` 一致，
	# 而射程也要跟着它走。
	var enemies := _spawned(PBWave.Shape.NORMAL, 12)
	for i: int in enemies.size():
		var enemy: PBEnemy = enemies[i]
		assert_eq(enemy.ranged, _cfg.enemy_is_ranged(i), "第 %d 只的远近要和配置一致" % i)
		var want: float = _cfg.enemy_reach_ranged if enemy.ranged else _cfg.enemy_reach
		assert_almost_eq(enemy.reach, want, 1e-9, "第 %d 只的射程要跟着它自己那一档走" % i)


func test_every_boss_is_ranged_with_its_own_reach() -> void:
	# **BOSS 一律远程是规则**（玩家定的），不是槽位取模碰巧落进远程那一档：
	# 远程占比调成 0、BOSS 再多几只，照样全是远程、全用 BOSS 那一档射程。
	# `*_boss` 那张皮的 `attack` 段因此要按**放术**画。
	_cfg.enemy_ranged_share = 0.0
	for shape: PBWave.Shape in [PBWave.Shape.BOSS, PBWave.Shape.MEGA_BOSS]:
		for enemy: PBEnemy in _spawned(shape, 12):
			assert_true(enemy.ranged, "BOSS 一律远程")
			assert_almost_eq(enemy.reach, _cfg.enemy_reach_boss, 1e-9, "BOSS 用自己那一档射程")
	for enemy: PBEnemy in _spawned(PBWave.Shape.ELITE, 12):
		assert_false(enemy.ranged, "前提：远程占比 0 时别的波一个远程都没有")


func test_the_enemy_shot_table_lists_exactly_the_kinds_that_shoot() -> void:
	# 会开枪的是远程小怪、远程精英、BOSS（BOSS 一律远程），× 6 种属性 = 18 种。
	# 表里多一行近战的，面板上就能给一种不开枪的怪配子弹；少一行，那一种就配不了 —— 两样都不报错。
	var want: Array[StringName] = []
	for element: PBElement.Type in PBEnemyPool.ELEMENT_NAMES:
		for rank: int in [PBEnemy.Rank.MINION, PBEnemy.Rank.ELITE, PBEnemy.Rank.BOSS]:
			var key := PBEnemyPool.skin_key(element, rank, true)
			if not want.has(key):
				want.append(key)
	var have: Array[StringName] = []
	for cells: PackedStringArray in PBEnemyShotTable.rows():
		have.append(StringName(cells[0]))
	assert_eq(have.size(), 18, "18 种")
	for key: StringName in want:
		assert_true(have.has(key), "敌人子弹表里少了 %s" % key)
	for key: StringName in have:
		assert_true(want.has(key), "敌人子弹表里的 %s 不开枪" % key)


func test_there_are_thirty_distinct_skin_keys() -> void:
	# 6 属性 × 5 形态。**重了就有两种怪抢同一张皮**，而屏幕上看起来
	# 只是「这两种怪长得一样」。
	var seen: Dictionary = {}
	for element: PBElement.Type in PBEnemyPool.ELEMENT_NAMES:
		for rank: int in [PBEnemy.Rank.MINION, PBEnemy.Rank.ELITE, PBEnemy.Rank.BOSS]:
			for ranged: bool in [false, true]:
				seen[PBEnemyPool.skin_key(element, rank, ranged)] = true
	assert_eq(seen.size(), 30, "6 属性 × 5 形态 = 30 个键，实际 %d" % seen.size())


func test_the_boss_skin_does_not_split_by_reach() -> void:
	# 玩家定的：BOSS 只有一种形象。**近远那一维在 BOSS 这一档要被吃掉** ——
	# 不吃的话就是 36 种，而出图那一侧只准备了 30 张。
	var near := PBEnemyPool.skin_key(PBElement.Type.WATER, PBEnemy.Rank.BOSS, false)
	var far := PBEnemyPool.skin_key(PBElement.Type.WATER, PBEnemy.Rank.BOSS, true)
	assert_eq(near, far, "BOSS 不分近远")
	assert_true(String(near).ends_with("_boss"), "BOSS 那一档的后缀是 boss，实际 %s" % near)


func test_every_form_name_shows_up_in_a_key() -> void:
	# 键是 `enemy_<属性>_<形态>` 拼出来的，而**只有一处拼它**
	# （[method PBEnemyPool.skin_key]）。这条钉住那五个后缀就是出图目录名 ——
	# 两处各拼一份的话，出好的素材装不进来而工具一句话都不说。
	var got: Array[String] = []
	for form: int in FORMS.size():
		var rank: int = PBEnemy.Rank.MINION
		if form == 4:
			rank = PBEnemy.Rank.BOSS
		elif form >= 2:
			rank = PBEnemy.Rank.ELITE
		got.append(String(PBEnemyPool.skin_key(PBElement.Type.FIRE, rank, form % 2 == 1)))
	for form: int in FORMS.size():
		assert_eq(got[form], "enemy_fire_%s" % FORMS[form], "第 %d 种形态的键" % form)


func test_the_white_model_grows_with_the_rank() -> void:
	# 形状那一维已经被属性占满了（§02 要求去色后仍能凭剪影分五系），
	# 所以档次只能靠大小说。**三档必须真的不一样大** ——
	# 一样大的话「这一波是精英波」在屏幕上今天没有任何一处看得见。
	var sizes: Array[int] = []
	for bulk: float in PBEnemyPool.RANK_BULK:
		var skin := PBWhiteModel.enemy(5, bulk)
		sizes.append(skin.frames.get_frame_texture(&"idle", 0).get_height())
	assert_lt(sizes[0], sizes[1], "精英要比小怪大")
	assert_lt(sizes[1], sizes[2], "BOSS 要比精英大")


func test_the_white_enemy_can_actually_play_a_death() -> void:
	# **M9-b 之前这一段根本不存在**：敌人一死节点当帧就藏，所以没人发现
	# 白模只有 idle / run / attack 三段。现在死亡要演完才消失，
	# 缺这一段的表现是「怪死了原地站着几帧再凭空消失」——
	# [method PBActorSkin.anim_for] 会退回 `idle`，而那不报错。
	var skin := PBWhiteModel.enemy(5, 1.0)
	assert_true(skin.frames.has_animation(&"dead"), "白模敌人得有倒地那一段")
	assert_gt(skin.frames.get_frame_count(&"dead"), 1, "倒地得有好几帧，不然看不出在倒")
	assert_false(skin.frames.get_animation_loop(&"dead"), "倒地不循环 —— 循环就是一直在倒")
	assert_true(PBActorPose.holds_last(PBActorPose.State.DEAD), "而且演完要停在最后一帧")


func test_a_dead_enemy_stays_on_screen_until_the_death_animation_is_over() -> void:
	# **玩家提的那一条**（M9-b）：怪死了要把倒地演完再消失。
	#
	# 在这之前 [method PBEnemyPool.sync_enemies] 直接用
	# [method PBEnemy.is_active]（「活着而且已经出场」），于是怪一死当帧就藏，
	# 屏幕上是凭空消失 —— 而己方那边早就是演完再留着。
	var pool := PBEnemyPool.new()
	add_child_autofree(pool)
	await wait_process_frames(1)
	var enemies := _spawned(PBWave.Shape.NORMAL, 1)
	var field := Vector2(1.0, 0.44)

	pool.sync_enemies(enemies, 0, field)
	assert_true(pool._nodes[0].visible, "活着当然要画")

	enemies[0].alive = false
	pool.sync_enemies(enemies, 1, field)
	assert_true(pool._nodes[0].visible, "刚死 —— 倒地那一段还没演完，得留着")
	assert_eq(pool._poses[0].state, PBActorPose.State.DEAD, "而且真的在演倒地")
	assert_eq(pool._nodes[0].animation, &"dead", "播的得是倒地那一段")

	# 演完了停在最后一帧（`pause` 不是 `stop`：`stop` 会把帧号清回 0，
	# 见 CLAUDE.md 已知坑位）。
	pool._nodes[0].pause()
	pool.sync_enemies(enemies, 2, field)
	assert_false(pool._nodes[0].visible, "演完就该藏了")


func test_a_finished_death_does_not_start_over() -> void:
	# `AnimatedSprite2D` 在「停在最后一帧」时再调一次 `play()` 就是重播 ——
	# 而 [method PBEnemyPool._animate] 原来写的是「没在播就 `play`」。
	# M9-b 之前敌人一死就藏，所以这条从来没机会发作；现在会。
	# 表现是尸体在地上一遍遍重新倒下。
	var pool := PBEnemyPool.new()
	add_child_autofree(pool)
	await wait_process_frames(1)
	var enemies := _spawned(PBWave.Shape.NORMAL, 1)
	var field := Vector2(1.0, 0.44)
	pool.sync_enemies(enemies, 0, field)
	enemies[0].alive = false
	pool.sync_enemies(enemies, 1, field)
	pool._nodes[0].pause()
	var frame: int = pool._nodes[0].frame
	pool._animate(0, enemies[0])
	assert_false(pool._nodes[0].is_playing(), "演完了就别再播一遍")
	assert_eq(pool._nodes[0].frame, frame, "帧号也不许被拨回去")


func test_a_fresh_enemy_takes_the_slot_back_from_a_corpse() -> void:
	# 一波打完槽位分给下一波，而上一具尸体可能还没演完。**不用额外记账** ——
	# 新怪还没出场就藏（`has_spawned`），已经出场就照常画它自己。
	# 这条钉的是「没有那本账也对」，因为那本账我写完又删了。
	var pool := PBEnemyPool.new()
	add_child_autofree(pool)
	await wait_process_frames(1)
	var field := Vector2(1.0, 0.44)
	var dead := _spawned(PBWave.Shape.NORMAL, 1)
	pool.sync_enemies(dead, 0, field)
	dead[0].alive = false
	pool.sync_enemies(dead, 1, field)
	assert_true(pool._nodes[0].visible, "先造出一具还在演的尸体")

	# 下一波接管这一格：还没出场 → 藏。
	var next := _spawned(PBWave.Shape.ELITE, 3)
	next[0].spawn_tick = 5
	pool.sync_enemies(next, 0, field)
	assert_false(pool._nodes[0].visible, "接管这一格的新怪还没出场，不许画上一具尸体")

	# 出场了 → 画它自己，姿势也从倒地切回来。
	pool.sync_enemies(next, 5, field)
	assert_true(pool._nodes[0].visible, "新怪出场就该画")
	assert_ne(pool._poses[0].state, PBActorPose.State.DEAD, "姿势得从倒地切回来")


func test_real_monster_art_is_not_tinted_by_its_element() -> void:
	# 白模只有一个形状，五系全靠色相分；**真素材各画各的**，再乘一层属性色
	# 会把美术定的颜色整个拉偏。己方那边一直认 `tint_by_element`
	# （[method PBAllyPool._tint]），敌人这边一直**无条件乘** ——
	# M9-c 之前敌人只有白模，所以这条从来没机会发作。
	# 发作起来是「接进来的火系怪整个偏橙红」，而没有一处会报错。
	var pool := PBEnemyPool.new()
	add_child_autofree(pool)
	await wait_process_frames(1)
	var enemies := _spawned(PBWave.Shape.NORMAL, 1)
	pool.sync_enemies(enemies, 0, Vector2(1.0, 0.44))

	# **两半都显式摆出来。** 上一版只摆了真素材那一半，白模那一半靠
	# 「这一格默认装的就是白模」—— 而 30 张怪接上之后它默认装的是真素材，
	# 于是当场变红，红的是「美术做完了」（同 `test_actor_lab` 那条）。
	var white_skin: PBActorSkin = PBEnemyPool.white_for(enemies[0].element, enemies[0].rank)
	pool._skins[0] = white_skin
	var white: Color = pool._color_of(0, enemies[0])
	var want: Color = PBEnemyPool.ELEMENT_COLORS[PBElement.Type.FIRE]
	assert_almost_eq(white.r, want.r, 0.01, "白模要染属性色 —— 五系全靠它分")

	var real := PBActorSkin.new()
	real.tint_by_element = false
	pool._skins[0] = real
	var got: Color = pool._color_of(0, enemies[0])
	assert_almost_eq(got.r, 1.0, 0.001, "真素材不许被属性色乘一层（红）")
	assert_almost_eq(got.g, 1.0, 0.001, "绿")
	assert_almost_eq(got.b, 1.0, 0.001, "蓝")


func test_a_hurt_monster_still_darkens_even_with_real_art() -> void:
	# **血量与白闪两层照旧对真素材生效**：它们讲的是「还剩多少血」和
	# 「刚挨了一下」，和这个怪本来什么颜色是两回事。
	# 一刀切成「真素材不碰 modulate」的话，满血 BOSS 挨一整波普攻画面上没动静。
	var pool := PBEnemyPool.new()
	add_child_autofree(pool)
	await wait_process_frames(1)
	var enemies := _spawned(PBWave.Shape.NORMAL, 1)
	pool.sync_enemies(enemies, 0, Vector2(1.0, 0.44))
	var real := PBActorSkin.new()
	real.tint_by_element = false
	pool._skins[0] = real
	enemies[0].hp = enemies[0].max_hp * 0.1
	assert_lt(pool._color_of(0, enemies[0]).r, 0.9, "快死了还是要暗下来")


func test_every_frame_of_one_rank_is_the_same_size() -> void:
	# [member PBActorSkin.canvas_size] 只读第 0 帧，所以一张皮里各帧尺寸不一
	# **不报错**，只表现为这个怪在动画之间忽大忽小、脚还会离地。
	# 倒地那几帧是压扁出来的，最容易踩这条。
	var skin := PBWhiteModel.enemy(6, 1.9)
	var want := skin.frames.get_frame_texture(&"idle", 0).get_size()
	for anim: StringName in skin.frames.get_animation_names():
		for i: int in skin.frames.get_frame_count(anim):
			var got := skin.frames.get_frame_texture(anim, i).get_size()
			assert_eq(got, want, "%s 第 %d 帧的画布得和 idle 第 0 帧一样" % [anim, i])
