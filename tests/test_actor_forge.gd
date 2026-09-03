extends GutTest
## 视频转素材那条流水线（[PBActorForge]）。M6-f 的逻辑，M6-l 抽出来之后才测得到。
##
## ## 为什么这几条值得测
##
## 这条流水线的失败**全都不报错**：脚浮起一像素、画布被一帧杂点撑宽、
## 上一次多挑的那两帧留在目录里跟着进游戏 —— 出来的东西看起来都很正常，
## 只有在游戏里盯着一个 41 像素高的小人才看得出来。
##
## `tests/test_actor_data.gd` 守的是**成品**（目录里那几张 png 对不对），
## 这里守的是**做成品的那台机器**。

const ROOT := "user://forge_test"

var _forge: PBActorForge


func before_each() -> void:
	_forge = PBActorForge.new()
	_forge.assets_dir = "%s/assets" % ROOT
	_forge.data_dir = "%s/data" % ROOT
	_wipe(ROOT)


func after_all() -> void:
	_wipe(ROOT)


## 造一段假中间帧：透明底上一个实心竖条，就是「一个人」。
##
## **尺寸必须是真的 [constant PBActorForge.MID]** —— [method PBActorForge.compose]
## 里那次 `blit_rect` 按它裁，小一圈的话人会被切掉一块，
## 而那正是这几条断言要量的东西。
func _fake_take(dir_path: String, count: int, body: Rect2i) -> String:
	DirAccess.make_dir_recursive_absolute(dir_path)
	for i: int in count:
		var image := Image.create_empty(
			PBActorForge.MID.x, PBActorForge.MID.y, false, Image.FORMAT_RGBA8
		)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		# 每一帧高一点点，好让「呼吸」那一档挑得出高低两帧。
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


func test_the_powershell_path_uses_the_same_ffmpeg_filter() -> void:
	# **两条路调的是同一个 ffmpeg，滤镜链却各写了一份**（PowerShell 那边没法
	# 读 GDScript 的常量）。那三段缺一不可 —— 尤其 `premultiply`：
	# 少了它，缩放会把洋红渗进人物边缘，**而 alpha 看起来完全正常**。
	#
	# 所以这里逐字符钉住：改了一边不改另一边，这条就红。
	var script := FileAccess.get_file_as_string("res://scripts/make_actor.ps1")
	assert_ne(script, "", "读得到那个脚本才谈得上比对")
	assert_true(
		script.contains(PBActorForge.FILTER),
		"make_actor.ps1 的滤镜链和 PBActorForge.FILTER 不一样了：\n%s" % PBActorForge.FILTER
	)


func test_the_canvas_is_fitted_to_the_chosen_frames_only() -> void:
	# **先挑帧再定画布。** 按全部 97 帧算的话，AI 视频里任何一帧的杂点
	# 都会把画布撑宽，而那一帧根本不会进游戏 —— 画布白白大一圈，
	# 人在里面缩成一团，**而所有数字看起来都完全正确**。
	var dir := _fake_take("%s/idle" % ROOT, 4, Rect2i(460, 100, 40, 360))
	var shots := _forge.measure(dir)
	assert_eq(shots.size(), 4, "四帧都要量到")
	# 手工塞一帧「杂点」：人旁边多出来一块，包围盒因此宽得多。
	var wide: Dictionary = (shots[0] as Dictionary).duplicate()
	wide["used"] = Rect2i(200, 100, 560, 360)
	shots.append(wide)

	var takes := {"idle": shots}
	var scale_of := {"idle": 0.1}
	var narrow: Vector2i = _forge.fit_canvas(takes, scale_of, {"idle": [0] as Array[int]})
	var with_junk: Vector2i = _forge.fit_canvas(takes, scale_of, {"idle": [0, 4] as Array[int]})
	assert_lt(narrow.x, with_junk.x, "挑中那一帧才算数 —— 没挑的杂点不该撑宽画布")


func test_the_canvas_never_pokes_into_the_top_bar() -> void:
	# 画布高度超过头顶那一截的话，最上面那排的头会戳进 A 顶栏 ——
	# 而 `test_layout.gd` 钉的是 [PBLayout] 的常量，钉不到素材。
	#
	# **那道墙量的是逻辑像素**，所以高清档要先除回 [member PBActorForge.scale_up]
	# 再比。忘了除的话高清素材会被压掉三分之二，而画布、坐标、锚点
	# 全部看起来完全正确。
	var dir := _fake_take("%s/tall" % ROOT, 2, Rect2i(460, 20, 40, 500))
	var shots := _forge.measure(dir)
	for up: int in [1, PBActorForge.HD_FACTOR]:
		_forge.scale_up = up
		var canvas: Vector2i = _forge.fit_canvas(
			{"idle": shots}, {"idle": 1.0 * float(up)}, {"idle": [0] as Array[int]}
		)
		assert_lte(
			float(canvas.y) / float(up), PBLayout.SPRITE_HEADROOM, "%d 倍档越过了头顶余量" % up
		)
		# **压回去这一下不许无声。** 被压掉的是头，而画布、坐标、锚点
		# 全部看起来完全正确 —— 命令行和插件都靠这个字段才说得出话。
		assert_true(_forge.clamped, "%d 倍档撞了上限却没记下来" % up)


func test_the_hd_tier_makes_a_bigger_texture_that_draws_the_same_size() -> void:
	# 高清档的全部意义就在这条：**贴图大三倍，屏幕上还是 41**。
	# 两者中任何一个没跟上都不报错 —— 贴图没变大是「还是糊的」，
	# `pixel_scale` 没跟上是「人有三个身位那么高」。
	var dir := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var shots := _forge.measure(dir)
	var seen: Array[Vector2i] = []
	for up: int in [1, PBActorForge.HD_FACTOR]:
		_forge.scale_up = up
		assert_eq(_forge.texture_height(), PBActorForge.TARGET_HEIGHT * up, "%d 倍档贴图身高" % up)
		var scale_of := _forge.scales({"idle": shots, "run": shots, "attack": shots})
		_forge.fit_canvas({"idle": shots}, scale_of, {"idle": [0] as Array[int]})
		var image := _forge.compose(shots[0], float(scale_of["idle"]))
		seen.append(image.get_used_rect().size)
		# 脚仍然要踩在底边上 —— 那条不变量和分几倍无关。
		assert_eq(image.get_used_rect().end.y, image.get_height(), "%d 倍档的脚悬空了" % up)
	assert_gt(seen[1].y, seen[0].y * 2, "高清档的贴图该明显更高，实际 %s" % str(seen))


func test_the_hd_tier_keeps_a_soft_edge() -> void:
	# 像素档把 alpha 切成 0/1（像素画不许有半透明边缘）；**高清档不能切** ——
	# 软边正是那一档买的东西，切硬了等于把 GPU 缩出来的好处又扔掉，
	# 而画面上只表现为「边缘有锯齿」。
	var dir := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 41, 360))
	var shots := _forge.measure(dir)
	var partial: Array[int] = []
	for up: int in [1, PBActorForge.HD_FACTOR]:
		_forge.scale_up = up
		var scale_of := _forge.scales({"idle": shots, "run": shots, "attack": shots})
		_forge.fit_canvas({"idle": shots}, scale_of, {"idle": [0] as Array[int]})
		var image := _forge.compose(shots[0], float(scale_of["idle"]))
		var soft: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var a: float = image.get_pixel(x, y).a
				if a > 0.01 and a < 0.99:
					soft += 1
		partial.append(soft)
	assert_eq(partial[0], 0, "像素档不许留半透明像素")
	assert_gt(partial[1], 0, "高清档该留着软边")


func test_regrowing_the_canvas_keeps_the_feet_on_the_bottom_middle() -> void:
	# **一段一段导（M6-n）之后这条才是画布一致性的守卫。** 后导的那一段
	# 几乎总是更宽（出拳），旧帧要重新裱一遍 —— 裱歪了的表现是那几段
	# 整体偏一点点，而尺寸、锚点、坐标全部看起来完全正确。
	var canvas := Vector2i(20, 30)
	var mark := Image.create_empty(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	mark.fill(Color(0.0, 0.0, 0.0, 0.0))
	# **画两列宽，不是一列。** 一列的中点是 `x + 0.5`，永远落不到偶数画布的
	# 中线上 —— 那是夹具的毛病，不是重裱的。
	for y: int in 4:
		for x: int in 2:
			mark.set_pixel(canvas.x / 2 - 1 + x, canvas.y - 1 - y, Color(1.0, 1.0, 1.0, 1.0))
	assert_eq(_forge.save_frames("t", "idle", [mark] as Array[Image]), "", "先写一帧")
	assert_eq(_forge.canvas_on_disk("t"), canvas, "盘上的画布读得出来")

	var wider := Vector2i(40, 36)
	assert_eq(_forge.recanvas("t", wider), "", "重裱不该出错")
	assert_eq(_forge.canvas_on_disk("t"), wider, "重裱之后就是新画布")
	var after := Image.load_from_file("%s/assets/t/idle_0.png" % ROOT)
	var used := after.get_used_rect()
	assert_eq(used.end.y, wider.y, "脚还得踩在底边上")
	assert_almost_eq(
		float(used.position.x) + float(used.size.x) * 0.5, float(wider.x) * 0.5, 0.01, "还得在中线上"
	)


func test_composing_seats_the_feet_on_the_bottom_edge() -> void:
	# **这是整条流水线唯一真正的不变量。** 脚没坐在画布底边上的话，
	# 游戏里前后关系会错一档（谁挡谁按脚底的 y 排），
	# 而画布框、坐标、锚点全部看起来完全正确 —— M6-f 实测踩过。
	var dir := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var shots := _forge.measure(dir)
	var scale_of := _forge.scales({"idle": shots, "run": shots, "attack": shots})
	var canvas: Vector2i = _forge.fit_canvas(
		{"idle": shots}, scale_of, {"idle": [0] as Array[int]}
	)
	var image := _forge.compose(shots[0], float(scale_of["idle"]))

	assert_eq(image.get_size(), canvas, "出来的图就该是画布那么大")
	var used := image.get_used_rect()
	assert_eq(used.end.y, canvas.y, "最下面那排实心像素必须贴着画布底边")
	var middle: float = float(used.position.x) + float(used.size.x) * 0.5
	assert_almost_eq(middle, float(canvas.x) * 0.5, 1.0, "脚底中点要落在画布中线上")
	assert_almost_eq(float(used.size.y), float(_forge.texture_height()), 2.0, "身高要缩到目标值")


func test_saving_a_shorter_take_wipes_the_longer_one() -> void:
	# 这次挑 2 帧、上次挑 3 帧的话，多出来的 `idle_2.png` 会留在原地 ——
	# 而 [method PBActorForge.link] 是**一直数到断号为止**的，
	# 于是上一次那一帧会跟着进游戏，**不报错**。
	var blank: Array[Image] = []
	for i: int in 3:
		blank.append(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8))
	assert_eq(_forge.save_frames("t", "idle", blank), "", "先写三帧")
	assert_eq(_forge.save_frames("t", "idle", blank.slice(0, 2)), "", "再写两帧")
	var dir := DirAccess.open("%s/assets/t" % ROOT)
	assert_not_null(dir, "目录该在")
	var left: PackedStringArray = []
	for file_name: String in dir.get_files():
		if file_name.ends_with(".png"):
			left.append(file_name)
	assert_eq(left.size(), 2, "第三帧该被清掉，留着它会跟着进游戏：%s" % str(left))


func test_the_panel_builds_and_starts_empty() -> void:
	# 这块面板只在**编辑器**里露脸，而编辑器里出的错很容易被当成
	# 「插件没装好」放过去。这条在游戏进程里把它建一遍 ——
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


func test_the_auto_picker_survives_a_very_short_clip() -> void:
	# 四种挑法里有三种从第 [constant PBActorForge.TRIM] 帧起算（掐头去尾），
	# 而一段只有几帧的视频**根本没有那么多帧可掐**。
	# 越界的表现是编辑器里点一下「自动挑」整个卡死，而不是一句报错。
	var dir := _fake_take("%s/tiny" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var shots := _forge.measure(dir)
	for spec: Dictionary in PBActorForge.ANIMS:
		var picked := _forge.select(shots, String(spec["pick"]), int(spec["want"]))
		assert_false(picked.is_empty(), "%s 段总得挑出点什么" % spec["name"])
		for index: int in picked:
			assert_between(index, 0, shots.size() - 1, "%s 段挑了个不存在的帧" % spec["name"])
