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
## 这里守的是**做成品的那台机器**，
## 而 `tests/test_forge_panel.gd` 守的是**机器前面那块操作台**（M8-g 拆出去的）。

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


func test_a_source_frame_that_is_not_mid_sized_keeps_its_feet() -> void:
	# **图集那条路（M8-f）切出来的格子各有各的大小。** `compose` 里那次
	# `blit_rect` 原来按 [constant PBActorForge.MID]（960×540）写死裁 ——
	# 比它高的帧下半截会被直接丢掉，也就是**脚没了**，
	# 而画布、对齐、坐标全部看起来完全正确。
	var dir: String = "%s/tallframe" % ROOT
	DirAccess.make_dir_recursive_absolute(dir)
	# 一张比 MID 高得多的窄图，人贴着底边站着。
	var source := Image.create_empty(200, 900, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.0, 0.0, 0.0, 0.0))
	source.fill_rect(Rect2i(80, 100, 40, 800), Color(0.8, 0.5, 0.3, 1.0))
	source.save_png("%s/001.png" % dir)

	var shots := _forge.measure(dir)
	assert_eq(shots.size(), 1, "量得到那一帧")
	var scale_of := _forge.scales({"idle": shots, "run": shots, "attack": shots})
	_forge.fit_canvas({"idle": shots}, scale_of, {"idle": [0] as Array[int]})
	var image := _forge.compose(shots[0], float(scale_of["idle"]))
	var used := image.get_used_rect()
	assert_gt(used.size.y, 0, "人得还在，别被裁没了")
	assert_eq(used.end.y, image.get_height(), "脚必须还踩在画布底边上")
	assert_almost_eq(
		float(used.size.y), float(_forge.texture_height()), 2.0, "身高该缩到目标值，说明整个人都在"
	)


func test_measuring_one_frame_matches_measuring_the_whole_take() -> void:
	# 擦除那条路（M6-r）擦完只重量手上这一张 —— 97 张全扫一遍在编辑器里
	# 就是「松开鼠标卡半秒」。两条路因此必须同源，否则「预览里量的」
	# 和「导出时量的」会分叉，**而预览正是这几个数唯一被看见的地方**。
	var dir := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var shots := _forge.measure(dir)
	assert_eq(shots.size(), 3, "三帧都要量到")
	for shot: Dictionary in shots:
		var one := _forge.measure_one(shot["path"])
		assert_eq(one["used"], shot["used"], "包围盒该一样")
		assert_eq(one["feet_x"], shot["feet_x"], "脚底中点该一样")
		assert_eq(one["mask"], shot["mask"], "剪影该一样")


func test_a_manual_nudge_moves_the_body_by_exactly_that_many_pixels() -> void:
	# 手动锚点（M6-r）的单位是**成品像素** —— 用中间帧像素的话，
	# 按一下方向键屏幕上可能一动不动，表现是「这个按钮是坏的吧」。
	#
	# **零偏移必须逐位等于不传**：一个偏移都没调过的角色，出来的帧和
	# M6-o 那一版一字不差 —— 那是这个参数敢加在这条路上的全部理由
	# （同 M3.5-f 装备那条「空着 = 一字不差」）。
	var dir := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var shots := _forge.measure(dir)
	var scale_of := _forge.scales({"idle": shots, "run": shots, "attack": shots})
	_forge.fit_canvas({"idle": shots}, scale_of, {"idle": [0] as Array[int]})
	var scale: float = float(scale_of["idle"])

	var plain := _forge.compose(shots[0], scale)
	assert_eq(
		_forge.compose(shots[0], scale, Vector2i.ZERO).get_data(),
		plain.get_data(),
		"零偏移必须和不传逐位相同"
	)
	var moved := _forge.compose(shots[0], scale, Vector2i(3, -2))
	assert_eq(
		moved.get_used_rect().position - plain.get_used_rect().position,
		Vector2i(3, -2),
		"偏移几格，人就该挪几格"
	)


func test_re_extracting_a_take_also_drops_the_erase_backups() -> void:
	# 备份目录（[constant PBFrameTouch.ORIG_DIR]）跟着中间帧一起活。
	# 留着上一条视频那一份的话，「还原这一帧」会还原成另一个角色的一帧 ——
	# 而中间帧尺寸恒为 [constant PBActorForge.MID]，所以**它不报错**。
	var dir := _fake_take("%s/idle" % ROOT, 2, Rect2i(460, 100, 40, 360))
	var touch := PBFrameTouch.new()
	assert_eq(touch.open("%s/000.png" % dir, []), "", "先擦一帧，好让备份建起来")
	var backup: String = PBFrameTouch.backup_of("%s/000.png" % dir)
	assert_true(FileAccess.file_exists(backup), "备份该在")
	_forge.wipe_frames(dir)
	assert_false(FileAccess.file_exists(backup), "重抽帧要把上一条的备份一起清掉")


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


func test_a_crouched_take_borrows_idles_scale_when_asked() -> void:
	# **玩家实际踩到的那条**（M8-g）：按图集切的时候，`run` 那张六格全是弓着腰的
	# 跑姿，最高的一格也只有站姿的七成（实测 615 vs 880）。逐段归一化把那 615
	# 当成了身高，跑动的人因此被放大四成 —— 而每一帧看起来都很正常，
	# 只是他一跑起来就变大只。
	var tall := _fake_take("%s/idle" % ROOT, 3, Rect2i(460, 100, 40, 360))
	var low := _fake_take("%s/run" % ROOT, 3, Rect2i(460, 240, 40, 220))
	var takes := {"idle": _forge.measure(tall), "run": _forge.measure(low)}

	var apart := _forge.scales(takes)
	assert_gt(float(apart["run"]), float(apart["idle"]) * 1.3, "逐段归一化会把弓着腰那一段放大")

	var shared := _forge.scales(takes, true)
	assert_eq(float(shared["run"]), float(shared["idle"]), "借了之后两段的比必须逐位相同")
	assert_eq(float(shared["idle"]), float(apart["idle"]), "idle 自己那一份不受影响")
	assert_eq(float(shared["dead"]), float(shared["idle"]), "dead 本来就借 idle 的")


func test_borrowing_needs_an_idle_to_borrow_from() -> void:
	# 没有 `idle` 还照借的话，那个借来的比会停在 1.0 —— 也就是「一个像素都不缩」，
	# 人以中间帧的原始尺寸怼进画布。**悄悄退回逐段更糟**：那一段会不声不响地
	# 大四成，而屏幕上没有任何一句话说过这件事。
	var low := _fake_take("%s/run" % ROOT, 3, Rect2i(460, 240, 40, 220))
	var only := {"run": _forge.measure(low)}
	assert_true(_forge.scales(only, true).is_empty(), "借不到就该返回空字典")
	assert_gt(float(_forge.scales(only).get("run", 0.0)), 0.0, "不借的那一路照旧算得出")


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
