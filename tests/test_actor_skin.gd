extends GutTest
## 一份形象（[PBActorSkin]）该保证的事。M9-e 从 `test_actor_pose.gd` 拆出来 ——
## 那个文件破了 gdlint 的 20 个公开方法上限，而那条上限
## 「超了不是错，是该拆了的信号」，这次它指的地方是对的。
##
## ## 拆在哪条线上
##
## `test_actor_pose.gd` 守的是**姿势机**：这一帧该播哪一段、起手什么时候开始、
## 演完了停不停。这里守的是**那份素材本身的性质**：脚底在哪、画布多大、
## 段名对不对得上、命中落在第几帧。
##
## 两边都不报错，但报错的样子完全不同 —— 姿势机错了是「动作不对」，
## 素材性质错了是「人浮在地上」或者「卡在上一帧」。


func test_the_art_is_mirrored_when_it_faces_away_from_where_he_looks() -> void:
	# **玩家报的那条**（M9-m）：「怪物从右往左走却播放的是向右的动画，
	# 看起来是倒着走的」。
	#
	# 根因是敌我两个池子各写了一份翻转判断，**而符号是反的** ——
	# 己方 `facing == FACE_LEFT`，敌人 `facing == FACE_RIGHT`。白模是个
	# 左右几乎对称的多边形，所以这条从 M6-b 起错着没人看得见。
	#
	# 四种组合全钉上：两个朝向 × 源图朝哪边画的。
	var right := PBActorSkin.new()
	right.source_faces = PBActorSkin.Facing.RIGHT
	assert_false(right.flips_for(PBActorPose.FACE_RIGHT), "朝右画的人看向右边，不该翻")
	assert_true(right.flips_for(PBActorPose.FACE_LEFT), "朝右画的人看向左边，必须翻")

	var left := PBActorSkin.new()
	left.source_faces = PBActorSkin.Facing.LEFT
	assert_true(left.flips_for(PBActorPose.FACE_RIGHT), "朝左画的人看向右边，必须翻")
	assert_false(left.flips_for(PBActorPose.FACE_LEFT), "朝左画的人看向左边，不该翻")

	# 流水线出的素材一律填 RIGHT（[method PBActorForge.link]），白模也是 ——
	# 所以「往左走要翻」是今天全部素材实际走的那一档。
	assert_eq(
		PBWhiteModel.enemy(6).source_faces,
		PBActorSkin.Facing.RIGHT,
		"白模也是朝右画的，敌人往左走时必须翻"
	)


func test_nobody_works_out_the_mirroring_on_their_own() -> void:
	# **一把尺子**。上面那条钉的是规则本身，这一条钉的是「只有一处问它」——
	# 而 M9-m 那个 bug 恰恰是规则没错、有人自己又推了一遍，还推反了。
	#
	# 单元测试抓不到那种复制：两个池子各自都「能跑」，只是其中一个
	# 演的是倒着走的人。所以这里直接扫源码。
	for path: String in ["res://src/view/enemy_pool.gd", "res://src/view/ally_pool.gd",
		"res://src/tools/actor_lab.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "读得到 %s 才谈得上扫" % path)
		for line: String in text.split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#") or not code.contains("flip_h"):
				continue
			if not code.contains("=") or code.contains("=="):
				continue
			assert_true(
				code.contains("flips_for"),
				"%s 自己算了一遍翻转：%s —— 走 PBActorSkin.flips_for" % [path, code]
			)


func test_a_short_attack_take_is_padded_to_six_frames() -> void:
	# **玩家定的**（M9-e）：不够六帧就重复最后一帧补到六帧。
	#
	# 出手落在第 4 帧，而整段被压进一个攻击间隔里 —— 「第几帧」这句话
	# 只有在每一段都是同样多帧的时候才是同一个意思。库里 27 个角色是按
	# 老规矩导的，3~6 帧都有：一段 4 帧的挥击摊在同一个间隔上，
	# 出手那一刻落在它的第 3 帧，手还在挥出去的路上而子弹已经飞了。
	var skin := PBActorSkin.new()
	var frames := SpriteFrames.new()
	frames.add_animation(&"attack")
	frames.set_animation_loop(&"attack", false)
	var one := ImageTexture.create_from_image(
		Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	)
	var last := ImageTexture.create_from_image(
		Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	)
	frames.add_frame(&"attack", one)
	frames.add_frame(&"attack", one)
	frames.add_frame(&"attack", last)
	skin.frames = frames

	skin.hold_last_to(&"attack", 6)
	assert_eq(frames.get_frame_count(&"attack"), 6, "补到 6 帧")
	for i: int in range(2, 6):
		assert_eq(frames.get_frame_texture(&"attack", i), last, "第 %d 帧该是最后那一张" % i)
	# **补的是最后一帧，前面几帧一格都不许动** —— 动了就等于改了已有的姿势。
	assert_eq(frames.get_frame_texture(&"attack", 0), one, "第 0 帧原样")

	# 补过一次就不再补：资源是缓存的，不挡住的话每重载一次就长几帧。
	skin.hold_last_to(&"attack", 6)
	assert_eq(frames.get_frame_count(&"attack"), 6, "补过就别再补")


func test_a_looping_take_is_never_padded() -> void:
	# 循环段（待机、跑动）补上去的表现是「跑两步顿一下」——
	# 多出来的那几帧会停在循环的接缝上，而它不报错。
	var skin := PBActorSkin.new()
	var frames := SpriteFrames.new()
	frames.add_animation(&"run")
	frames.set_animation_loop(&"run", true)
	var one := ImageTexture.create_from_image(
		Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	)
	frames.add_frame(&"run", one)
	frames.add_frame(&"run", one)
	skin.frames = frames
	skin.hold_last_to(&"run", 6)
	assert_eq(frames.get_frame_count(&"run"), 2, "循环段不许补")


func test_the_white_model_attack_peaks_on_the_hit_frame() -> void:
	# 白模是代码画的，所以**直接画到 6 帧**，不靠补。
	# 而且伸得最远那一帧要正好落在出手的那一格上 ——
	# 不然白模那一路的画面和伤害对不上，而库里 27 个角色之外全是白模。
	var cfg := PBSimConfig.new()
	for skin: PBActorSkin in [PBWhiteModel.ally(), PBWhiteModel.enemy(5, 1.0)]:
		var anim: StringName = skin.anim_attack
		assert_eq(skin.frames.get_frame_count(anim), cfg.anim_frames, "白模攻击段该是 6 帧")
		var peak: int = 0
		var far: int = -1
		for i: int in cfg.anim_frames:
			var used := skin.frames.get_frame_texture(anim, i).get_image().get_used_rect()
			if used.size.x > far:
				far = used.size.x
				peak = i
		assert_eq(peak, cfg.attack_hit_frame - 1, "伸得最远的该是第 %d 帧" % cfg.attack_hit_frame)


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
	# 敌人的白模没有施法段（怪不放忍术），所以那一档必须退回待机。
	#
	# **这条以前测的是倒地段** —— M9-b 给敌人白模补上倒地之后前提就没了。
	# 换成施法段不是为了让它继续绿：兜底那一层要挡的是
	# [method AnimatedSprite2D.play] 遇到不存在的动画**静默不播**
	# （人卡在上一帧，不报错），而那件事和具体是哪一段无关。
	var skin := PBWhiteModel.enemy(5)
	assert_false(skin.has(&"cast"), "敌人白模本来就没画施法那一段")
	# **施法退回的是攻击段，不是待机** —— 那是 [method PBActorSkin.anim_for]
	# 里写死的一条规则（放术时挥个手总比站着不动像话），不是通用兜底。
	assert_eq(skin.anim_for(PBActorPose.State.CAST), skin.anim_attack, "施法查不到退回攻击段")
	# 通用兜底才是退回待机 —— 拼错一个字的名字走的是这一条。
	assert_eq(skin.resolve(&"根本没有这一段"), skin.anim_idle, "兜底那一层必须在")
	# 倒地那一段**现在有了**，而且它不能退回待机 —— 退回去的话
	# 「死了之后演完再消失」就变成了「站着不动几帧再凭空消失」（M9-b）。
	assert_true(skin.has(&"dead"), "M9-b 之后敌人白模有倒地段了")
	assert_eq(skin.anim_for(PBActorPose.State.DEAD), &"dead", "有就得真播它")


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
