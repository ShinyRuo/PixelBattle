extends GutTest
## 子弹的**美术**：谁用哪一颗、怎么混合、没配命中段用什么、每一发从第几帧播（从 `test_shot_view.gd` 拆出来，那边管弹道与火花的链路）。
##
## 这一层错了全都不报错：配了还是白模、苦无半透明、打中的地方冒出一把苦无、每发子弹随机停在某一帧。

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


func after_each() -> void:
	# 下面几条往子弹表里塞了假资源，换回盘上那一份。
	PBShotLibrary.reload()


## 往子弹表里塞一份假资源，键 [param key]。飞行段 [param fly_frames] 帧，[param with_hit] 为假就不配命中段。
func _fake_shot(
	key: StringName,
	additive_fly: bool,
	additive_hit: bool,
	fly_frames: int = 1,
	with_hit: bool = true
) -> PBShotSkin:
	var fly: Array[Texture2D] = []
	for _i: int in fly_frames:
		fly.append_array(_one_texture())
	var hit: Array[Texture2D] = []
	if with_hit:
		hit = _one_texture()
	var skin := PBShotForge.new().assemble(String(key), fly, hit)
	skin.additive_fly = additive_fly
	skin.additive_hit = additive_hit
	PBShotLibrary._cached = {key: skin}
	PBShotLibrary._loaded = true
	return skin


func _one_texture() -> Array[Texture2D]:
	var image := Image.create_empty(6, 6, false, Image.FORMAT_RGBA8)
	return [ImageTexture.create_from_image(image)] as Array[Texture2D]


## 出战席：一个配了普攻子弹 [param shot] 的忍者。
func _deployed(shot: StringName) -> Array[PBUnit]:
	var character := PBCharacter.make(&"probe_ninja", PBElement.Type.FIRE, PBUnit.Rarity.R)
	character.shot_key = shot
	var out: Array[PBUnit] = [PBUnit.new(character)]
	return out


# ── 普攻子弹配给谁 ──────────────────────────────────────────────


func test_an_ally_bullet_uses_the_shot_its_ninja_is_configured_with() -> void:
	# 配置在名册上、逐个忍者配（不按属性推）。读错一处的表现是「配了还是白模」。
	var art := _fake_shot(&"probe_shot", true, true)
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	sim.shots()[0].launch(squad[0].pos, 0, 10.0, 0.01, false, PBElement.Type.FIRE, 0)

	pool.sync_shots(sim, _deployed(&"probe_shot"), null, _field())
	assert_eq(pool._fly[0].sprite_frames, art.frames, "己方这一发画的是他配的那颗子弹")
	pool.sync_shots(sim, _deployed(&""), null, _field())
	assert_eq(pool._fly[0].sprite_frames, PBWhiteModel.shot().frames, "没配的退回白模")


func test_an_enemy_bullet_stays_white() -> void:
	# 敌人没有名册那一格。**槽位号和己方重叠**（都从 0 起）—— 不分敌我去查出战席的话，
	# 0 号敌人会拿着 0 号忍者的子弹打过来。
	_fake_shot(&"probe_shot", true, true)
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	sim.shots()[0].launch(sim.enemies()[0].pos(), 0, 10.0, 0.01, true, PBElement.Type.FIRE, 0)
	pool.sync_shots(sim, _deployed(&"probe_shot"), null, _field())
	assert_eq(pool._fly[0].sprite_frames, PBWhiteModel.shot().frames, "敌人的子弹是白模")


func test_blending_follows_each_segment_and_is_cleared_on_reuse() -> void:
	# 一枚苦无（普通混合）打出一团火花（加法混合）。槽位会被下一发接管，所以混合方式每次都要重写。
	_fake_shot(&"probe_shot", false, true)
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var book := PBBattleLog.new()
	sim.shots()[0].launch(squad[0].pos, 0, 10.0, 0.01, false, PBElement.Type.FIRE, 0)
	book.hit(1, 0, sim.enemies()[0].slot, 12.0, false)

	pool.sync_shots(sim, _deployed(&"probe_shot"), book, _field())
	assert_null(pool._fly[0].material, "实体的飞行段是普通混合")
	assert_eq(pool.sparks(), 1, "前提：出了一朵火花")
	var spark: CanvasItemMaterial = pool._hits[0].material
	assert_not_null(spark, "发光的命中段挂上了材质")
	assert_eq(spark.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "而且是加法混合")

	_fake_shot(&"probe_shot", true, true)
	pool.sync_shots(sim, _deployed(&"probe_shot"), null, _field())
	assert_not_null(pool._fly[0].material, "换成发光的子弹，同一个槽位挂上加法")
	pool.sync_shots(sim, _deployed(&""), null, _field())
	assert_null(pool._fly[0].material, "再换回白模，材质要清掉")


func test_a_shot_without_a_hit_segment_sparks_with_the_default() -> void:
	# 玩家定的。不拦的话会拿飞行段顶上：打中的地方冒出一把苦无。
	_fake_shot(&"probe_shot", false, false, 1, false)
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var book := PBBattleLog.new()
	book.hit(1, 0, sim.enemies()[0].slot, 12.0, false)
	pool.sync_shots(sim, _deployed(&"probe_shot"), book, _field())
	assert_eq(pool.sparks(), 1, "照样有火花")
	assert_eq(pool._hits[0].sprite_frames, PBWhiteModel.shot().frames, "用的是默认火花")


func test_every_bullet_starts_its_flight_on_the_first_frame() -> void:
	# 玩家定的。池子复用精灵，不重置的话新的一发接着上一发的进度往下演，看起来像随机停在某一帧。
	_fake_shot(&"probe_shot", false, false, 4)
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var mark: PBEnemy = sim.enemies()[0]
	var shot: PBProjectile = sim.shots()[0]
	var deployed := _deployed(&"probe_shot")
	shot.launch(squad[0].pos, mark.slot, 10.0, 0.01, false, PBElement.Type.FIRE, 0)
	pool.sync_shots(sim, deployed, null, _field())
	var node: AnimatedSprite2D = pool._fly[0]
	assert_eq(node.frame, 0, "刚出膛是第 1 帧")

	node.set_frame_and_progress(2, 0.5)
	shot.pos = squad[0].pos.lerp(mark.pos(), 0.3)
	pool.sync_shots(sim, deployed, null, _field())
	assert_eq(node.frame, 2, "同一发还在飞，进度不许被打断")

	# 落地之后同一个槽立刻又射出一发（射手没挪窝，出膛点一模一样）。
	shot.launch(squad[0].pos, mark.slot, 10.0, 0.01, false, PBElement.Type.FIRE, 0)
	pool.sync_shots(sim, deployed, null, _field())
	assert_eq(node.frame, 0, "新的一发从第 1 帧重播")


func test_a_bullet_keeps_its_sprite_when_an_earlier_one_lands() -> void:
	# 挤着排的话前面一发落地、后面一发换到另一个精灵上，播放进度跟着跳。
	_fake_shot(&"probe_shot", false, false, 4)
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := _sim(squad)
	var pool := _pool()
	var mark: PBEnemy = sim.enemies()[0]
	var deployed := _deployed(&"probe_shot")
	for i: int in 2:
		sim.shots()[i].launch(squad[0].pos, mark.slot, 10.0, 0.01, false, PBElement.Type.FIRE, 0)
	pool.sync_shots(sim, deployed, null, _field())
	pool._fly[1].set_frame_and_progress(3, 0.2)
	sim.shots()[0].alive = false
	pool.sync_shots(sim, deployed, null, _field())
	assert_true(pool._fly[1].visible, "第二发还画在它自己的精灵上")
	assert_eq(pool._fly[1].frame, 3, "而且进度没动")
	assert_eq(pool.shown(), 1, "只剩一发在飞")
