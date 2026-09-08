extends GutTest
## 「战场形象」那块面板（[PBActorForgePanel] + [PBForgeSource] + `addons/` 那层外壳）。
## M8-g 从 `test_actor_forge.gd` 拆出来 —— 那个文件破了 gdlint 的 20 个公开方法上限，
## 而那条上限「超了不是错，是该拆了的信号」，这次它指的地方是对的。
##
## ## 拆在哪条线上
##
## `test_actor_forge.gd` 守的是**做成品的那台机器**（量、缩、坐底边、描边），
## 这里守的是**机器前面那块操作台**：控件建不建得出来、开关跟不跟着来源走、
## 两个导出按钮走不走同一条写盘路、插件外壳指的路径存不存在。
##
## 这几条**全都只在编辑器里露脸**，而编辑器里出的错很容易被当成
## 「插件没装好」放过去 —— 所以要在游戏进程里跑一遍。

const ROOT := "user://forge_panel_test"


func before_each() -> void:
	_wipe(ROOT)


func after_all() -> void:
	_wipe(ROOT)


func test_the_panel_builds_and_starts_empty() -> void:
	# 少一个控件、少一个 `connect`，这里就炸。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_eq(panel._picks.size(), PBActorForge.anim_names().size(), "四段一开始各挂一份空名单")
	assert_true(PBActorForge.anim_names().has(panel._anim()), "下拉框选中的得是个真段名")
	assert_true(panel._picked().is_empty(), "一开始什么都没挑")
	assert_true(panel._mid_dir().begins_with(PBActorForgePanel.MID_ROOT), "中间帧目录要在 build 下")
	# **高清档不再是一个开关**（M6-n）—— 面板不问，流水线默认就是它。
	# 忘了这条的表现是出一套 60 像素的像素画素材，而它不报错。
	assert_eq(panel._forge.scale_up, PBActorForge.HD_FACTOR, "面板该默认走高清档")
	# **修帧那两本账一开局都得是空的**（M6-r）：一个偏移都没调、一笔都没擦的
	# 角色，出来的帧必须和 M6-o 那一版一字不差。
	assert_eq(panel._nudge_now(), Vector2i.ZERO, "一开局不该有任何手动偏移")
	assert_true(panel._mark_table().is_empty(), "一开局不该有任何橡皮笔迹")
	# 两块工具面板**互斥显示** —— 全摆着的话「这一下点在图上是干什么的」
	# 就得靠人自己记，而点错的表现是「怎么擦掉一块」或者「怎么人整个歪了」。
	assert_true(panel._anchor_box.visible, "默认是调锚点")
	assert_false(panel._eraser.visible, "橡皮那一块默认收着")


func test_the_sheet_route_borrows_idles_scale_and_the_video_route_does_not() -> void:
	# 这个开关**跟着来源下拉框走**，不是另一个勾 —— 分开的话「按图集切但忘了勾」
	# 的表现是跑动那一段大四成，而屏幕上一切正常（M8-g）。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_false(panel._source.shares_idle_scale(), "默认是视频路线，逐段各自量")
	assert_false(panel._needs_idle("run"), "视频路线下 run 不用借")
	assert_true(panel._needs_idle("dead"), "dead 什么时候都要借")
	panel._source._from_pick.select(PBForgeSource.From.SHEET)
	assert_true(panel._source.shares_idle_scale(), "选了图集就该借 idle 的比")
	assert_true(panel._needs_idle("run"), "图集路线下 run 要借")


func test_the_preview_zoom_is_one_ruler_across_a_take() -> void:
	# **玩家实际看到的那条**（M8-g）：图集路线上每一格是切出来多大就多大，
	# 而预览原来按**每一帧自己**的尺寸铺满控件 —— 于是矮的那格被放大两倍多，
	# 屏幕上「躺下的人最大」，而实际那一格的墨迹只有站姿的三分之二。
	# 预览这块面板的全部用处就是判断「这一格对不对」，它自己得是一把不变的尺子。
	var canvas := PBForgeCanvas.new()
	add_child_autofree(canvas)
	canvas.size = Vector2(400, 400)
	var tall := ImageTexture.create_from_image(
		Image.create_empty(100, 400, false, Image.FORMAT_RGBA8)
	)
	# **两张的最长边不能一样长。** 400×400 的控件里，100×400 和 400×100
	# 铺满之后缩放比都是 1.0 —— 那样两条断言就都是碰巧成立的。
	var flat := ImageTexture.create_from_image(
		Image.create_empty(200, 50, false, Image.FORMAT_RGBA8)
	)
	var shot := {"used": Rect2i(0, 0, 10, 10), "feet_x": 5.0}

	# 不交基准 = M8-g 之前的行为：两帧各自铺满，缩放比因此不同。
	canvas.show_frame(tall, shot, Vector2i.ZERO, 1.0)
	var loose_tall: float = canvas._view_scale()
	canvas.show_frame(flat, shot, Vector2i.ZERO, 1.0)
	assert_ne(canvas._view_scale(), loose_tall, "没有基准时两帧的缩放比本来就不同")

	# 交了基准之后必须逐位相同 —— 差一点点的表现是「这一格好像大一圈」，
	# 而人会去重出那张图集。
	canvas.fit_to(Vector2i(400, 400))
	canvas.show_frame(tall, shot, Vector2i.ZERO, 1.0)
	var fixed: float = canvas._view_scale()
	canvas.show_frame(flat, shot, Vector2i.ZERO, 1.0)
	assert_eq(canvas._view_scale(), fixed, "交了基准之后一段里每一帧的缩放比必须一样")

	# 贴底：矮的那帧画在下面，不是浮在正中 —— 脚坐在底边上是这条流水线唯一的锚。
	assert_almost_eq(canvas._view_rect().end.y, 400.0, 0.01, "矮的那帧该贴着底边")


func test_the_frame_counter_says_how_many_there_are() -> void:
	# 原来是「第 %d / %d」配 `size() - 1`，六帧永远显示成「/ 5」——
	# 一个 0 起的下标配一个「总数减一」的分母，读起来就是「5 帧里的第 4 帧」，
	# 而那时候人会去找丢掉的那一帧。**下标仍然 0 起**：挑帧列表存的就是它。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var dir := _fake_take("%s/idle" % ROOT, 6, Rect2i(460, 100, 40, 360))
	panel._shots = panel._forge.measure(dir)
	panel._show(4)
	assert_true(panel._count_label.text.contains("共 6 帧"), "得说出总共几帧")
	assert_true(panel._count_label.text.begins_with("第 4 帧"), "下标照旧 0 起")


func test_an_untouched_zoom_changes_nothing_at_all() -> void:
	# **这是这个滑块敢加在导出那条路上的全部理由**（同 `_nudges` 那条）：
	# 一个没调过的角色，出来的缩放比和没有这个滑块的那一版**逐位相同**。
	# 差一点点的表现是全库素材静悄悄地整体变了一档，而没有任何一处会报错。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var shots := panel._forge.measure(_fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360)))
	var bare: float = float(panel._forge.scales({"idle": shots})["idle"])
	assert_eq(panel._zoom_of("idle"), 1.0, "没调过就是 1.00")
	assert_eq(panel._scale_for("idle", shots), bare, "没调过时导出用的比必须一字不差")
	assert_eq(panel._zoomed({"idle": bare})["idle"], bare, "①那条路同理")


func test_the_zoom_multiplies_exactly_and_both_export_paths_see_it() -> void:
	# **两个导出按钮必须看到同一个倍率。** ②走 `_scale_for`、①走 `_zoomed`，
	# 漏乘一处的表现是「四段一把重出之后，我调过的那一段又变回去了」，
	# 而屏幕上写着「四段出好了」。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var shots := panel._forge.measure(_fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360)))
	var bare: float = float(panel._forge.scales({"idle": shots})["idle"])
	panel._zooms["idle"] = 0.86
	assert_almost_eq(panel._scale_for("idle", shots), bare * 0.86, 1e-9, "②那条路要乘上去")
	assert_almost_eq(panel._zoomed({"idle": bare})["idle"], bare * 0.86, 1e-9, "①那条路也要")


func test_each_take_keeps_its_own_zoom() -> void:
	# 一个数存在面板上的话，切到别的段还留着上一段的倍率 ——
	# 表现是「我从来没调过 run，导出来却小了一圈」。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel._anim_pick.select(0)
	panel._set_zoom(0.80)
	var first: String = panel._anim()
	panel._anim_pick.select(1)
	panel._switch_anim()
	var second: String = panel._anim()
	assert_ne(first, second, "得真换了一段才谈得上串味")
	assert_eq(panel._zoom_of(second), 1.0, "没调过的那一段还是 1.00")
	assert_eq(panel._zoom_of(first), 0.80, "调过的那一段留着")
	# 换段时滑块**不许发信号** —— 发了就等于把上一段的数写进新段。
	assert_false(panel._zooms.has(second), "光是切过去不该给新段记一笔")


func test_erasing_still_makes_the_panel_remeasure_the_frame() -> void:
	# **这条缝是 M8-g 新造的**：橡皮搬进 [PBForgeEraser] 之后它只改盘，
	# 而「量帧」留在面板手上，中间隔着一个信号。接断了的表现是
	# **屏幕上图擦干净了，导出来的还是那张偏的** —— 两处都不报错。
	#
	# 量的是 `used`：擦掉地面阴影之后它才会回到真正的鞋底上，
	# 而画布宽度、脚底中线、缩放比全是从它派生的。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel._shots = panel._forge.measure(_fake_take("%s/idle" % ROOT, 2, Rect2i(460, 100, 40, 360)))
	panel._show(0)
	var before: Rect2i = panel._shots[0]["used"]
	assert_eq(before.size, Vector2i(40, 360), "先确认量到的就是那根竖条")

	# 框掉下半截。
	panel._eraser.on_wiped(Rect2i(400, before.position.y + 180, 200, 400))
	panel._eraser.on_stroke_ended()
	assert_lt(panel._shots[0]["used"].size.y, before.size.y, "擦完面板必须重新量过这一帧")
	assert_false(panel._mark_table().is_empty(), "这一笔要记进笔迹账，撤销和「套到整段」全靠它")


func test_copying_a_frame_puts_a_second_copy_right_after_it() -> void:
	# **玩家要的那个按钮**（M9-e）：「选一帧点击复制，能够复制当前帧」。
	#
	# 「＋ 要这一帧」是个开关（在就拿掉、不在就加上），所以同一帧按两次
	# 等于没按 —— 而每一段要 6 帧，源片凑不够时就得把某一帧停久一点。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel._shots = panel._forge.measure(_fake_take("%s/idle" % ROOT, 4, Rect2i(460, 100, 40, 360)))
	panel._set_picked([0, 2, 3] as Array[int])

	panel._show(2)
	panel._on_copy()
	assert_eq(panel._picked(), [0, 2, 2, 3] as Array[int], "复制的那一份要插在它后面")

	# **插在后面，不是追加到末尾** —— 顺序就是播放顺序，追到末尾等于
	# 把「停久一点」变成「结尾多播一帧别的姿势」。
	panel._show(0)
	panel._on_copy()
	assert_eq(panel._picked(), [0, 0, 2, 2, 3] as Array[int], "第 0 帧那一份也插在它自己后面")


func test_copying_a_frame_that_is_not_picked_says_so() -> void:
	# 不在名单里的帧没有「后面」可插。**说一句比静默不动好** ——
	# 静默的表现是「这个按钮好像坏了」，而人会一直点。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel._shots = panel._forge.measure(_fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360)))
	panel._set_picked([0] as Array[int])
	panel._show(2)
	panel._on_copy()
	assert_eq(panel._picked(), [0] as Array[int], "没在名单里就别动名单")
	assert_true(panel._status.text.contains("还不在名单里"), "得说出为什么没反应")


func test_both_export_buttons_write_frames_the_same_way() -> void:
	# **两个导出按钮（M6-o）必须共用一份 compose+写盘。** 各写一份的话
	# 「①出的帧和②出的帧差一像素」迟早发生，而它不报错 ——
	# 表现是重导过的那一段比别的段高矮一点点。
	#
	# 这里直接拿面板那个共用函数写两遍，比对逐字节。
	var panel := PBActorForgePanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var dir := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var shots := panel._forge.measure(dir)
	panel._forge.assets_dir = "%s/assets" % ROOT
	panel._forge.data_dir = "%s/data" % ROOT
	var scale: float = float(panel._forge.scales({"idle": shots})["idle"])
	panel._forge.fit_canvas({"idle": shots}, {"idle": scale}, {"idle": [0] as Array[int]})

	assert_eq(panel._write_take("a", "idle", shots, [0], scale), "", "第一次写盘")
	assert_eq(panel._write_take("b", "idle", shots, [0], scale), "", "第二次写盘")
	var one := FileAccess.get_file_as_bytes("%s/assets/a/idle_0.png" % ROOT)
	var two := FileAccess.get_file_as_bytes("%s/assets/b/idle_0.png" % ROOT)
	assert_gt(one.size(), 0, "得真写出来了才谈得上比对")
	assert_eq(one, two, "同一段同一帧，两条路出的图必须逐字节相同")


func test_the_plugin_points_at_a_panel_that_exists() -> void:
	# **插件的外壳在 `addons/`，而那一档 `check.ps1` 不 lint 也不测**
	# （见 CLAUDE.md 的目录约定）。所以路径写错了没有任何一关拦得住 ——
	# 表现是编辑器启动时弹一句红字，而人一般不看那儿。
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://addons/actor_forge/plugin.cfg"), OK, "plugin.cfg 要读得进来")
	var script: String = "res://addons/actor_forge/%s" % cfg.get_value("plugin", "script", "")
	assert_true(FileAccess.file_exists(script), "plugin.cfg 指的脚本不存在：%s" % script)
	var shell := FileAccess.get_file_as_string(script)
	assert_true(
		shell.contains("res://src/tools/actor_forge_panel.gd"),
		"外壳该 preload src/tools 里那块面板 —— 逻辑不放 addons"
	)
	var project := FileAccess.get_file_as_string("res://project.godot")
	assert_true(
		project.contains("res://addons/actor_forge/plugin.cfg"),
		"project.godot 里没启用这个插件，编辑器底栏不会出现那个按钮"
	)


## 造一段假中间帧：透明底上一个实心竖条，就是「一个人」。
##
## **和 `test_actor_forge.gd` 那份是同一个东西**，抄过来是因为 GUT 的用例
## 只按文件收集，两个文件之间没有共享夹具的地方。
##
## **尺寸必须是真的 [constant PBActorForge.MID]** —— [method PBActorForge.compose]
## 里那次 `blit_rect` 按它裁，小一圈的话人会被切掉一块。
func _fake_take(dir_path: String, count: int, body: Rect2i) -> String:
	DirAccess.make_dir_recursive_absolute(dir_path)
	for i: int in count:
		var image := Image.create_empty(
			PBActorForge.MID.x, PBActorForge.MID.y, false, Image.FORMAT_RGBA8
		)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		var box := Rect2i(body.position - Vector2i(0, i), body.size + Vector2i(0, i))
		for y: int in box.size.y:
			for x: int in box.size.x:
				image.set_pixel(box.position.x + x, box.position.y + y, Color(0.8, 0.5, 0.3, 1.0))
		image.save_png("%s/%03d.png" % [dir_path, i])
	return dir_path


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe("%s/%s" % [dir_path, sub])
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)
