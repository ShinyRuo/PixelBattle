extends GutTest
## 战场形象这一层：**哪一帧该播哪段动画**，以及那张皮的兜底。M6-b。
##
## ## 为什么这块值得一个文件
##
## 动画错了**不报错**。播错一段、朝反一边、脚底差一格 —— 全都是
## 「跑得起来、看起来也没炸」的那种错，只有盯着屏幕看才发现，
## 而这个项目已经为这种形状的 bug 付过几次代价（M5-10 那一次活了三个里程碑）。
##
## [PBActorPose] 收的全是裸值，不碰 sim 的任何字段，所以这里可以直接
## 造几组数走一遍，不用起一局战斗。

## 攻击段占几帧。测试里取一个好数，真机上由攻击间隔换算
## （[method PBAllyPool._hold_frames]）。
const HOLD: int = 4


func test_a_shot_puts_him_into_the_attack_pose() -> void:
	# 出手在 sim 里没有事件，但「下一发挪后了」这件事只有出手才做得到。
	var pose := PBActorPose.new()
	pose.reset(Vector2(0.3, 0.2), PBActorPose.FACE_RIGHT)
	pose.update(Vector2(0.3, 0.2), true, 20, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.IDLE, "站着没动就是待机")
	pose.update(Vector2(0.3, 0.2), true, 24, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "`next_shot_at` 变大就是刚出了一手")


func test_the_attack_pose_lasts_a_few_frames() -> void:
	# **sim 是 20 tick/s，画面是 60 帧。** 照直比「这一帧刚出手吗」的话，
	# 一次挥击只会显示一帧 —— 玩家看到的是一次闪烁，不是一个动作。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD)
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD)
	for i: int in HOLD - 1:
		pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD)
		assert_eq(pose.state, PBActorPose.State.ATTACK, "第 %d 帧还该在挥" % i)
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.IDLE, "播完就该回到待机")


func test_moving_holds_the_run_pose_across_the_gap_between_ticks() -> void:
	# 三个物理帧里只有一帧位置会变。不赖住的话，跑起来的人会
	# 1 帧 run、2 帧 idle 地闪 —— 而两边的坐标都完全正确。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD)
	pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.RUN, "位置变了就是在跑")
	pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD)
	pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.RUN, "隔着一个 tick 的空档还该在跑")
	for _i: int in PBActorPose.MOVE_HOLD:
		pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.IDLE, "真站定了才回待机")


func test_being_dead_beats_everything_else() -> void:
	# 倒地那一段压过施法和挥击。反过来的话，一个在施法延迟里被打死的人
	# 会保持施法姿势站到这一波结束。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD)
	pose.update(Vector2(0.02, 0.0), false, 8, true, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.DEAD, "死了就是倒地，不管手上在干什么")


func test_he_looks_at_his_target_and_falls_back_to_where_he_is_headed() -> void:
	# 三档：有目标看目标 → 没目标看走向 → 都没有就保持原朝向。
	# 最后那一条不是偷懒：每帧重算一个默认值会让他在目标死掉的
	# 那一瞬间「唰」地转回去。
	var pose := PBActorPose.new()
	pose.reset(Vector2(0.5, 0.2), PBActorPose.FACE_RIGHT)
	pose.update(Vector2(0.5, 0.2), true, 0, false, 0.1, HOLD)
	assert_eq(pose.facing, PBActorPose.FACE_LEFT, "目标在左边就该转过去")
	pose.update(Vector2(0.4, 0.2), true, 0, false, NAN, HOLD)
	assert_eq(pose.facing, PBActorPose.FACE_LEFT, "没目标时看走向，他正往左走")
	pose.update(Vector2(0.4, 0.2), true, 0, false, NAN, HOLD)
	assert_eq(pose.facing, PBActorPose.FACE_LEFT, "站定了就保持，不许自己转回去")
	pose.update(Vector2(0.45, 0.2), true, 0, false, NAN, HOLD)
	assert_eq(pose.facing, PBActorPose.FACE_RIGHT, "被击退往右挪就该转过来")


func test_the_first_frame_is_not_a_shot() -> void:
	# 开波那一下 [method PBAttacker.revive] 会重排 `next_shot_at`，
	# 而这边手上还没有「上一次是第几 tick」这个参照 ——
	# 不挡住的话每一波的第一帧全队都在挥空。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 999, false, NAN, HOLD)
	assert_eq(pose.state, PBActorPose.State.IDLE, "第一帧不该算成一次出手")


func test_the_white_model_has_every_animation_the_states_ask_for() -> void:
	# **这条测的是「链路今天就是通的」。** `assets/` 一张图都没有，
	# 走的全是白模那一条；缺一段的表现是
	# [method AnimatedSprite2D.play] 静默不播 —— 人卡在上一帧，不报错。
	var skin := PBWhiteModel.ally()
	for state: int in PBActorPose.State.values():
		var anim: StringName = skin.anim_for(state)
		assert_true(skin.has(anim), "第 %d 档拿到的 `%s` 得真的存在" % [state, anim])
	assert_true(skin.tint_by_element, "白模只有一个形状，五系全靠染色分")


func test_a_missing_animation_falls_back_instead_of_freezing() -> void:
	# 敌人的白模没有倒地段和施法段（它们用不上），所以这两档必须退回待机。
	var skin := PBWhiteModel.enemy(5)
	assert_false(skin.has(&"dead"), "敌人白模本来就没画倒地那一段")
	assert_eq(skin.anim_for(PBActorPose.State.DEAD), skin.anim_idle, "查不到就退回待机")
	assert_eq(skin.resolve(&"根本没有这一段"), skin.anim_idle, "兜底那一层必须在")


func test_the_foot_sits_on_the_bottom_middle_of_the_canvas() -> void:
	# **整份素材规格里最要紧的一个数。** 脚底记错一格，这个人和别人的
	# 前后关系就错一格，而所有坐标看起来都完全正确（M6-a 那条 y 排序）。
	for skin: PBActorSkin in [PBWhiteModel.ally(), PBWhiteModel.enemy(3)]:
		var canvas := skin.canvas_size()
		assert_gt(canvas.x, 0.0, "画布尺寸得读得出来，读不出来锚点就是错的")
		assert_eq(skin.anchor(), Vector2(canvas.x * 0.5, canvas.y), "默认锚是底边中点")
		assert_eq(skin.draw_offset(), -skin.anchor(), "偏移把脚底挪到原点上")


func test_the_foot_stays_on_the_ground_after_scaling_up() -> void:
	# **偏移和放大不能各乘一遍。** [member Sprite2D.offset] 是在节点缩放
	# **之前**作用的，而放大走 [member Node2D.scale] —— 两处都乘
	# [member PBActorSkin.pixel_scale] 等于把偏移平方，人浮在地面上方
	# 一整个身高。`pixel_scale` 恒为 1 时看不出来（1 的平方还是 1），
	# 而白模正好是 1，所以这条要等真素材填 2 的那天才发作，**且不报错**。
	var skin := PBWhiteModel.ally()
	skin = skin.duplicate() as PBActorSkin
	skin.pixel_scale = 3.0
	var sprite := AnimatedSprite2D.new()
	sprite.centered = false
	sprite.sprite_frames = skin.frames
	sprite.offset = skin.draw_offset()
	sprite.scale = Vector2.ONE * skin.pixel_scale
	add_child_autofree(sprite)
	# 画布底边中点（也就是脚底那一点）必须正好落在节点原点上。
	#
	# **要连 [member Sprite2D.offset] 一起算。** 它是绘制属性、不进节点变换，
	# 所以 `get_global_transform()` 里没有它 —— 只拿变换乘画布坐标的话，
	# 量到的是「没有偏移时脚底在哪」，这条断言会永远为假。
	var canvas := skin.canvas_size()
	var foot: Vector2 = sprite.transform * (sprite.offset + Vector2(canvas.x * 0.5, canvas.y))
	assert_almost_eq(foot.x, 0.0, 0.001, "放大之后脚底横向跑偏了")
	assert_almost_eq(foot.y, 0.0, 0.001, "放大之后人浮在地面上方了")


func test_every_frame_in_a_skin_is_the_same_size() -> void:
	# [method PBActorSkin.canvas_size] 只读第一帧。尺寸不齐的话
	# 脚底锚对得上第一帧、对不上其余帧 —— 人会在动画里上下跳。
	var skin := PBWhiteModel.ally()
	var want := skin.canvas_size()
	for anim: String in skin.frames.get_animation_names():
		for i: int in skin.frames.get_frame_count(anim):
			var texture: Texture2D = skin.frames.get_frame_texture(anim, i)
			assert_eq(texture.get_size(), want, "`%s` 第 %d 帧尺寸不一样" % [anim, i])


func test_pausing_and_speeding_up_reach_the_animation_too() -> void:
	# **不跟着走的话，暂停时一群人还在原地跑步。** §02 特意把暂停当成一个
	# 正经的操作时机（「哪几个人在打同一个目标」得一眼看出来），
	# 那一刻画面必须是静止的局面，不是一段循环播放的舞蹈。
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	var field := Vector2(1.0, 0.44)
	var squad: Array[PBAttacker] = [_standing()]
	var nobody: Array[PBUnit] = []
	var empty: Array[PBEnemy] = []

	pool.sync_allies(squad, nobody, field, empty)
	var sprite := pool.find_children("", "AnimatedSprite2D", true, false)[0] as AnimatedSprite2D
	assert_gt(sprite.speed_scale, 0.0, "平时该在播")

	pool.set_anim_speed(0.0)
	pool.sync_allies(squad, nobody, field, empty)
	assert_eq(sprite.speed_scale, 0.0, "暂停和顿帧时必须停住")

	pool.set_anim_speed(3.0)
	pool.sync_allies(squad, nobody, field, empty)
	assert_eq(sprite.speed_scale, 3.0, "3 倍速时人也要快三倍")


func test_the_attack_animation_is_squeezed_into_one_attack_interval() -> void:
	# 素材的帧率是美术定的，出手间隔是数值定的 —— 两者没有理由相等。
	# 不缩的话，攻速慢的那个播完之后干站着大半个间隔，
	# 攻速快的那个上一段还没播完下一发已经出去了。
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	var skin := PBWhiteModel.ally()
	var anim: StringName = skin.anim_for(PBActorPose.State.ATTACK)
	var seconds: float = skin.anim_seconds(anim)
	assert_gt(seconds, 0.0, "攻击段得有长度")

	# 一个 20 tick 的间隔就是 1 秒，缩放该正好是「素材多长 ÷ 1 秒」。
	var slow: float = pool._fit(skin, anim, 20)
	assert_almost_eq(slow, seconds, 0.001, "慢攻速要把这一段拉满整个间隔")
	assert_lt(slow, 1.0, "0.25 秒的挥击摊进 1 秒，得放慢")
	assert_gt(pool._fit(skin, anim, 4), slow, "攻速越快这一段播得越急")
	assert_gte(pool._fit(skin, anim, 600), PBAllyPool.FIT_MIN, "夹住，别拉成慢动作")
	assert_lte(pool._fit(skin, anim, 1), PBAllyPool.FIT_MAX, "也别糊成一片")


func test_the_dead_animation_plays_once_and_holds_the_last_frame() -> void:
	# 玩家报的：人死了之后倒地动画一遍遍重演。
	#
	# **根因不在素材的循环标志上** —— `data/actors/frames/*.tres` 里
	# `dead` 的 `loop` 已经是 0 了。一段非循环动画演完之后
	# [AnimatedSprite2D] 只是**停下**，而 [method AnimatedSprite2D.play]
	# 在「停在最后一帧」时会从头重来 —— 于是每帧调一次 `play` 的渲染层
	# 把它变回了循环。白模的倒地段只有一帧，所以这条从 M6-b 起就错着，
	# 直到真素材（好几帧的 `dead`）进来才看得见。
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	var skin := _clip(&"dead", 3)
	var sprite: AnimatedSprite2D = pool._sprites[0]
	sprite.sprite_frames = skin.frames

	pool._animate(0, skin, &"dead", 1.0, true)
	assert_eq(sprite.animation, &"dead", "换到倒地段该播一遍")

	# 演完的自然状态：停在最后一帧、进度满、不再播。`pause` 而不是 `stop` ——
	# 后者会把位置清回 0，那就不是「演完了」的样子了。
	sprite.set_frame_and_progress(2, 1.0)
	sprite.pause()
	pool._animate(0, skin, &"dead", 1.0, true)
	assert_eq(sprite.frame, 2, "演完就停在最后一帧，不许从头再来")
	assert_false(sprite.is_playing(), "而且不该被重新推起来")


func test_a_finished_attack_still_replays_for_the_next_shot() -> void:
	# 上一条不许顺手把这一条弄坏：两发之间状态一直是
	# [constant PBActorPose.State.ATTACK]，所以下一遍**只能**靠
	# 「上一遍演完了」来触发 —— 这正是那行 `not is_playing()` 存在的理由。
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	var skin := _clip(&"attack", 3)
	var sprite: AnimatedSprite2D = pool._sprites[0]
	sprite.sprite_frames = skin.frames

	pool._animate(0, skin, &"attack", 1.0, false)
	sprite.set_frame_and_progress(2, 1.0)
	sprite.pause()
	pool._animate(0, skin, &"attack", 1.0, false)
	assert_eq(sprite.frame, 0, "不停住的那一档要从头再演一遍")


func test_only_the_dead_state_holds_its_last_frame() -> void:
	# 倒地是一个**终态**，别的都不是：待机与跑动本来就循环，
	# 攻击与施法每触发一次演一遍。
	assert_true(PBActorPose.holds_last(PBActorPose.State.DEAD), "倒地停住")
	for state: int in [
		PBActorPose.State.IDLE,
		PBActorPose.State.RUN,
		PBActorPose.State.ATTACK,
		PBActorPose.State.CAST,
	]:
		assert_false(PBActorPose.holds_last(state), "别的档都要接着演")


## 一段 [param count] 帧的**非循环**动画，挂在一张空皮上。
func _clip(anim: StringName, count: int) -> PBActorSkin:
	var frames := SpriteFrames.new()
	frames.add_animation(anim)
	frames.set_animation_loop(anim, false)
	frames.set_animation_speed(anim, 10.0)
	for _i: int in count:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		frames.add_frame(anim, ImageTexture.create_from_image(image))
	frames.remove_animation(&"default")
	var skin := PBActorSkin.new()
	skin.frames = frames
	skin.anim_dead = anim
	return skin


## 一个站在场上、还活着的攻击者。血量不为 0 才画得出来 ——
## 0 表示「这不是一个真单位，只是一个标量」，见 [member PBAttacker.max_hp]。
func _standing() -> PBAttacker:
	var attacker := PBAttacker.new()
	attacker.pos = Vector2(0.3, 0.2)
	attacker.max_hp = 100.0
	attacker.hp = 100.0
	attacker.attack_speed = 1.0
	attacker.slot = 0
	attacker.prime(20)
	return attacker
