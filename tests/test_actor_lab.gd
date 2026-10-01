extends GutTest
## 战场形象预览台（[PBActorLab]）。M6-e。
##
## ## 这个文件测的是「这个工具没坏」，不是「素材对不对」
##
## 预览台本身是给人看的 —— 动画好不好看、比例对不对，只有眼睛能判。
## 但它有三件事是**机器该守住的**，而且都不报错：
##
## 1. 场景起得来（面板在代码里摆，一个空引用就是整场黑屏）
## 2. **脚底真的落在地面线上**，放大之后也是 —— 它是这个工具的量具，
##    量具本身歪了的话，看出来的每一条结论都是错的
## 3. 下拉框和角色表对得上（少一个角色 = 那个角色永远预览不到）

const LAB_SCENE := "res://scenes/actor_lab.tscn"


func _open() -> PBActorLab:
	var root: PBActorLab = (load(LAB_SCENE) as PackedScene).instantiate()
	add_child_autofree(root)
	return root


func test_the_lab_opens_with_every_character_in_the_picker() -> void:
	var lab := _open()
	var table := PBCharacterLoader.table()
	assert_gt(table.size(), 0, "真角色表该装得进来")
	assert_eq(_picker(lab).item_count, table.size(), "下拉框少一个角色，那个角色就永远预览不到")


func test_the_other_family_holds_all_thirty_monster_kinds() -> void:
	# 30 种怪的皮键是**拼出来的**，而拼错了不报错（[PBActorLibrary] 安静地
	# 退回白模）。少列一种的表现是「这一种永远验不到」，
	# 而它恰恰是最需要人眼验的那一批 —— 接素材时只有这里看得见。
	var lab := _open()
	lab._swap_family()
	var want: Dictionary = {}
	for element: PBElement.Type in PBEnemyPool.ELEMENT_NAMES:
		for rank: int in PBActorLab.FOE_RANKS:
			for ranged: bool in [false, true]:
				want[PBEnemyPool.skin_key(element, rank, ranged)] = true
	assert_eq(want.size(), 30, "30 种是 §04 定的，这条先量准分母")
	assert_eq(_picker(lab).item_count, 30, "下拉框少一种怪，那一种就永远预览不到")
	var got: Dictionary = {}
	for entry: Dictionary in lab._entries:
		got[entry["key"]] = true
	assert_eq(got, want, "预览台列的键必须和战斗里查的是同一批")


func test_the_form_names_line_up_with_the_skin_key_halves() -> void:
	# 两排东西是同一件事的两种写法（一排进皮键、一排给人看），
	# 而下标是 [method PBEnemyPool.form_of] 给的。长度对不上就是错位，
	# 表现是「精英近战那一格写着 BOSS」——所有键都还是对的。
	assert_eq(PBActorLab.FOE_FORMS.size(), PBEnemyPool.FORM_NAMES.size(), "形态名两排得一样长")


func test_a_monster_is_dressed_exactly_like_it_is_on_the_battlefield() -> void:
	# **两头都要钉。** 有真素材就得和战场查到的是同一张；没有就得退回**怪那张**
	# 白模 —— 退回己方那张时屏幕上照样站着一个人，画布、脚底、坐标全部正确，
	# 只是这个工具对「这一种怪在游戏里长什么样」这个它唯一要回答的问题
	# 给出了一个错的答案。
	#
	# **上一版写的是进度不是规则**：它跳过有素材的那几种、只量剩下的，
	# 于是 30 张怪全接上的那天一种都量不到，当场变红 ——
	# 而红的是「美术做完了」。同 M10-b 那条从「每个角色都有头像」
	# 换成「每一张头像都要有主」。
	var lab := _open()
	lab._swap_family()
	for i: int in lab._entries.size():
		var entry: Dictionary = lab._entries[i]
		lab._choose(i)
		var want: PBActorSkin = PBActorLibrary.skin_for(entry["key"])
		if want == null:
			var element: PBElement.Type = entry["element"]
			var rank: int = entry["rank"]
			want = PBEnemyPool.white_for(element, rank)
		assert_same(lab._skin, want, "「%s」穿的得和战场上那只是同一张" % entry["title"])
	assert_eq(lab._entries.size(), 30, "30 种一种都不许漏 —— 遍历坏了的话上面什么都没量")


func test_the_foot_lands_on_the_ground_line() -> void:
	# **这是量具本身。** 预览台是用来验「脚底对没对齐」的，
	# 所以它自己摆的那个精灵必须先对齐 —— 不然看出来的结论全是错的。
	var lab := _open()
	var foot: Vector2 = _foot(lab.get_node("Anchor").get_child(0) as AnimatedSprite2D)
	assert_almost_eq(foot.x, PBActorLab.FOOT.x, 0.001, "脚底没落在落脚点上（横）")
	assert_almost_eq(foot.y, PBActorLab.FOOT.y, 0.001, "脚底没落在落脚点上（纵）")


func test_zooming_keeps_the_foot_on_the_ground_line() -> void:
	# 放大是这个工具的核心功能（27 像素高的人光看原大什么都验不了），
	# 而放大恰恰是 [method PBActorSkin.draw_offset] 那条平方 bug 的触发条件。
	#
	# **两个阵营各量一遍**：怪退回的是另一张白模（画布是方的、按档次变大），
	# 而量具歪没歪和皮是哪一张有关。
	var lab := _open()
	var sprite: AnimatedSprite2D = lab.get_node("Anchor").get_child(0)
	for family: int in 2:
		for zoom: int in PBActorLab.ZOOMS:
			lab._set_zoom(zoom)
			var foot: Vector2 = _foot(sprite)
			assert_almost_eq(foot.y, PBActorLab.FOOT.y, 0.001, "放大 %d× 之后人浮起来了" % zoom)
			assert_almost_eq(foot.x, PBActorLab.FOOT.x, 0.001, "放大 %d× 之后人横向跑偏了" % zoom)
		lab._swap_family()


func test_every_state_plays_something_that_exists() -> void:
	# [method AnimatedSprite2D.play] 遇到不存在的动画只是**静默不播**，
	# 表现是「这个角色卡在上一帧」——从现象反推极难。
	var lab := _open()
	var sprite: AnimatedSprite2D = lab.get_node("Anchor").get_child(0)
	for row: Array in PBActorLab.STATES:
		lab._play(row[1] as int)
		assert_true(sprite.sprite_frames.has_animation(sprite.animation), "「%s」播的那一段得真的存在" % row[0])


func test_stepping_a_frame_pauses_first() -> void:
	# 不先停住的话，下一个渲染帧就把刚挪到的那一帧盖掉了 ——
	# 表现是「按了单帧但画面没变」，而它每次都「没变」。
	var lab := _open()
	var sprite: AnimatedSprite2D = lab.get_node("Anchor").get_child(0)
	lab._play(PBActorPose.State.RUN)
	var before: int = sprite.frame
	lab._step(1)
	assert_false(sprite.is_playing(), "单帧步进要先停住")
	assert_ne(sprite.frame, before, "帧号该往前走一格")


func test_nothing_in_the_lab_hangs_off_the_edge() -> void:
	# 和 `test_layout.gd` 同一条：**超出屏幕不报错**，溢出的那一截
	# 只是画在界外，跑起来一切正常。这里的矩形不在 [PBLayout] 里
	# （它是工具场景，不参与那套排版），所以得单独钉一条。
	var lab := _open()
	await wait_physics_frames(2)
	var hud: Node = lab.get_node("HUD")
	var checked: int = 0
	for node: Node in hud.find_children("", "Control", true, false):
		var control := node as Control
		if control.size == Vector2.ZERO or _in_popup(control, hud):
			continue
		checked += 1
		var rect: Rect2 = control.get_global_rect()
		var edge: Vector2 = rect.position + rect.size
		assert_true(
			(
				rect.position.x >= -0.5
				and rect.position.y >= -0.5
				and edge.x <= PBLayout.SCREEN.x + 0.5
				and edge.y <= PBLayout.SCREEN.y + 0.5
			),
			"%s 伸出屏幕：%s ~ %s" % [control.name, rect.position, edge]
		)
	assert_gt(checked, 10, "该量到一板子控件，量不到说明遍历那一步坏了")


func _picker(lab: PBActorLab) -> OptionButton:
	var panel: Node = lab.get_node("HUD/Panel")
	return panel.find_children("", "OptionButton", true, false)[0]


## 这个精灵的**脚底**现在落在屏幕的哪一点。
##
## **必须连 [member Sprite2D.offset] 一起算。** 它是绘制属性、不进节点变换，
## 所以 `get_global_transform()` 里没有它 —— 只拿变换乘画布坐标的话，
## 量到的是「假如没有偏移，脚底会在哪」，和屏幕上画出来的东西无关。
func _foot(sprite: AnimatedSprite2D) -> Vector2:
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	var canvas: Vector2 = texture.get_size()
	return sprite.get_global_transform() * (sprite.offset + Vector2(canvas.x * 0.5, canvas.y))


## [OptionButton] 的下拉列表装在一个独立的 [Window] 里，尺寸由引擎在弹出
## 那一刻算，和 640×360 这块画布没关系 —— 照直量必然「出界」。
## **只往上走到 [param stop_at] 为止**，见 `test_layout.gd` 里的同名函数。
func _in_popup(control: Control, stop_at: Node) -> bool:
	var node: Node = control
	while node != null and node != stop_at:
		if node is Window:
			return true
		node = node.get_parent()
	return false
