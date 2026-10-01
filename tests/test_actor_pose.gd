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
	pose.update(Vector2(0.3, 0.2), true, 20, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.IDLE, "站着没动就是待机")
	pose.update(Vector2(0.3, 0.2), true, 24, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "`next_shot_at` 变大就是刚出了一手")


func test_the_swing_is_what_the_sim_says_it_is() -> void:
	# **玩家报的那一条**（M9-e）：「子弹在攻击动作开始的时候就射出去了」。
	#
	# 起手是 sim 那边的一个状态（[member PBAttacker.swinging]）：冷却转好
	# **而且射程内有人**才抬手。这边照着它起跑 —— 不自己拿 `next_shot_at`
	# 反推，因为起手占半个间隔时，「离下一发还有多远」在收招期间和起手期间
	# 是同一个数，两段分不开。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 20, false, NAN, HOLD, true, false, 6)
	assert_eq(pose.state, PBActorPose.State.IDLE, "还没抬手就该站着")
	pose.update(Vector2.ZERO, true, 20, false, NAN, HOLD, true, true, 6)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "抬手了就进攻击段")


func test_a_new_swing_says_so_exactly_once() -> void:
	# **上升沿**。[method AnimatedSprite2D.play] 对已经在播的同一段什么都不做，
	# 所以池子要靠这个信号把动画拨回第 0 帧；而它持续为真的话每帧都拨，
	# 人就永远停在起手那一格上。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 20, false, NAN, HOLD, true, false, 6)
	assert_false(pose.swing_began, "还没抬手")
	pose.update(Vector2.ZERO, true, 20, false, NAN, HOLD, true, true, 6)
	assert_true(pose.swing_began, "抬手这一帧要把动画拨回第 0 帧")
	pose.update(Vector2.ZERO, true, 20, false, NAN, HOLD, true, true, 6)
	assert_false(pose.swing_began, "起手期里只报一次")
	# 出手 → 收招 → 下一次抬手，要再报一次。
	pose.update(Vector2.ZERO, true, 32, false, NAN, HOLD, true, false, 6)
	assert_false(pose.swing_began, "收招期间不报")
	pose.update(Vector2.ZERO, true, 32, false, NAN, HOLD, true, true, 6)
	assert_true(pose.swing_began, "下一轮抬手要再报一次")


func test_without_a_windup_it_behaves_exactly_as_before() -> void:
	# **两个参数都不给就是 M9-e 之前的样子。** 默认值就是「不抬手、起手 0 帧」，
	# 所以没跟上的调用方行为一字不差 —— 那是它们敢加进这个热路径的全部理由。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 20, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.IDLE, "没抬手就不该进攻击段")
	pose.update(Vector2.ZERO, true, 24, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "照旧是出手了才播")


func test_the_windup_is_taken_out_of_the_recovery_not_added_to_it() -> void:
	# 出手之后剩下的是**收招**，长度得减掉起手那一段。不减的话每一手都占满
	# 一整个间隔再加上起手，两手之间的攻击段首尾相接 —— 人再也回不到待机。
	var hold: int = 20
	var windup: int = 6
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 20, false, NAN, hold, true, true, windup)
	pose.update(Vector2.ZERO, true, 24, false, NAN, hold, true, false, windup)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "刚出手，在收招")
	for _i: int in hold - windup:
		pose.update(Vector2.ZERO, true, 24, false, NAN, hold, true, false, windup)
	assert_eq(pose.state, PBActorPose.State.IDLE, "收招演完要回到待机")


func test_the_windup_comes_from_the_sim_not_from_the_animation() -> void:
	# 出手落在第几帧只有一处说了算（[member PBSimConfig.attack_hit_frame]）。
	assert_eq(PBActorPose.windup_frames(6, 3.0), 18, "6 tick 的起手 = 18 个渲染帧")
	assert_eq(PBActorPose.windup_frames(0, 3.0), 0, "不起手就是 0")


func test_the_hit_frame_decides_how_long_the_windup_is() -> void:
	# 第 4 帧（共 6 帧）出手 = 前 3 帧是起手，也就是间隔的一半。
	var cfg := PBSimConfig.new()
	assert_eq(cfg.attack_hit_frame, 4, "默认第 4 帧出手（玩家定的）")
	assert_eq(cfg.anim_frames, 6, "四段都是 6 帧")
	assert_eq(cfg.windup_ticks(12), 6, "12 tick 的间隔，前 3/6 是起手")
	assert_eq(cfg.windup_ticks(1), 0, "间隔只有 1 tick 时没有起手可留")
	cfg.attack_hit_frame = 6
	assert_lt(cfg.windup_ticks(4), 4, "起手不许占满一整个间隔")


func test_the_attack_pose_lasts_a_few_frames() -> void:
	# **sim 是 20 tick/s，画面是 60 帧。** 照直比「这一帧刚出手吗」的话，
	# 一次挥击只会显示一帧 —— 玩家看到的是一次闪烁，不是一个动作。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD, true)
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD, true)
	for i: int in HOLD - 1:
		pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD, true)
		assert_eq(pose.state, PBActorPose.State.ATTACK, "第 %d 帧还该在挥" % i)
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.IDLE, "播完就该回到待机")


func test_running_to_the_next_target_stops_the_attack_animation() -> void:
	# **玩家报的那条**（M8-e）：「攻击的单位死后切换到下一个目标，
	# 会一边播攻击动画一边移动」。
	#
	# 根因不在 sim —— 那边攻击和移动本来就互斥（[method PBBattleSim._move_attackers]
	# 里「够得着就 `continue`」）。是**渲染层把攻击段拉长到占满一整个攻击间隔**
	# （[method PBAllyPool._hold_frames]，那是有意的），于是「刚出过一手」
	# 一直挂到下一手，而这中间目标死了、下一个够不着、人已经跑起来了。
	#
	# 实测（20 波）：56% 的 tick 在播攻击段，其中 13% 人在挪，
	# 那 13% 里 74% 是真在走路。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD, true)
	# 出一手 —— 攻击段开始，而它要占满一整个间隔。
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "刚出手就该在挥")
	# 目标死了，下一个够不着，于是开始跑 —— 攻击段还剩一大截没播完。
	pose.update(Vector2(0.01, 0.0), true, 4, false, NAN, HOLD, false)
	assert_eq(pose.state, PBActorPose.State.RUN, "跑起来就不该还在挥手")
	# 跑到位、够得着了，攻击段接着算数（倒计时没被清掉）。
	pose.update(Vector2(0.01, 0.0), true, 4, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "够得着了就该接着挥")


func test_a_shooter_standing_still_out_of_range_does_not_swing() -> void:
	# 够不着的时候**站着**也不该挥手 —— 判据是「够不够得着」，不是「挪没挪」。
	# 拿挪没挪当判据的话，一个被绳子夹住、原地贴着敌人边缘的人会一直挥空，
	# 而 M8-c 那条 bug 里的近战正是整波卡在这个位置上。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD, true)
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.ATTACK, "先挥起来")
	pose.update(Vector2.ZERO, true, 4, false, NAN, HOLD, false)
	assert_eq(pose.state, PBActorPose.State.IDLE, "够不着又没在挪，就是站着发呆")


func test_moving_holds_the_run_pose_across_the_gap_between_ticks() -> void:
	# 三个物理帧里只有一帧位置会变。不赖住的话，跑起来的人会
	# 1 帧 run、2 帧 idle 地闪 —— 而两边的坐标都完全正确。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD, true)
	pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.RUN, "位置变了就是在跑")
	pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD, true)
	pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.RUN, "隔着一个 tick 的空档还该在跑")
	for _i: int in PBActorPose.MOVE_HOLD:
		pose.update(Vector2(0.01, 0.0), true, 0, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.IDLE, "真站定了才回待机")


func test_being_dead_beats_everything_else() -> void:
	# 倒地那一段压过施法和挥击。反过来的话，一个在施法延迟里被打死的人
	# 会保持施法姿势站到这一波结束。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, HOLD, true)
	pose.update(Vector2(0.02, 0.0), false, 8, true, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.DEAD, "死了就是倒地，不管手上在干什么")


func test_he_looks_at_his_target_and_falls_back_to_where_he_is_headed() -> void:
	# 三档：有目标看目标 → 没目标看走向 → 都没有就保持原朝向。
	# 最后那一条不是偷懒：每帧重算一个默认值会让他在目标死掉的
	# 那一瞬间「唰」地转回去。
	var pose := PBActorPose.new()
	pose.reset(Vector2(0.5, 0.2), PBActorPose.FACE_RIGHT)
	pose.update(Vector2(0.5, 0.2), true, 0, false, 0.1, HOLD, true)
	assert_eq(pose.facing, PBActorPose.FACE_LEFT, "目标在左边就该转过去")
	pose.update(Vector2(0.4, 0.2), true, 0, false, NAN, HOLD, true)
	assert_eq(pose.facing, PBActorPose.FACE_LEFT, "没目标时看走向，他正往左走")
	pose.update(Vector2(0.4, 0.2), true, 0, false, NAN, HOLD, true)
	assert_eq(pose.facing, PBActorPose.FACE_LEFT, "站定了就保持，不许自己转回去")
	pose.update(Vector2(0.45, 0.2), true, 0, false, NAN, HOLD, true)
	assert_eq(pose.facing, PBActorPose.FACE_RIGHT, "被击退往右挪就该转过来")


func test_the_first_frame_is_not_a_shot() -> void:
	# 开波那一下 [method PBAttacker.revive] 会重排 `next_shot_at`，
	# 而这边手上还没有「上一次是第几 tick」这个参照 ——
	# 不挡住的话每一波的第一帧全队都在挥空。
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 999, false, NAN, HOLD, true)
	assert_eq(pose.state, PBActorPose.State.IDLE, "第一帧不该算成一次出手")


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
	var sprite := pool._sprites[0]
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
