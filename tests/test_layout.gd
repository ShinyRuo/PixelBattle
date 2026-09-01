extends GutTest
## 排版：**屏幕上的每一块都得落在 640×360 里面**。M5-6。
##
## ## 为什么这需要一条测试
##
## 超出去**不报错**。溢出的那一截只是画在屏幕外，游戏跑起来一切正常，
## 单元测试全绿 —— 而 M5-2 到 M5-5 期间两块抽屉一直伸出屏幕 65 像素
## （[constant PBLayout.DRAWER_BAND] 从 588 窄到 508，而卡的步距还是老的），
## 三个里程碑没有一次发现。
##
## 那种错原来只有截图能抓，而截图要人去看。这个文件把它变成一条断言：
## 一块面板挪到界外，`check.ps1` 当场红。
##
## ## 两层断言
##
## 1. **[PBLayout] 的每一个 `Rect2` 常量** —— 走 `get_script_constant_map()`，
##    所以以后新加一块面板自动被覆盖，不用回来改这个文件
## 2. **真场景里每一个 [Control]** —— 常量对了不代表面板里的控件也对，
##    抽屉那次错的正是「框在界内、里面的卡摆到界外」

const BATTLE_SCENE := "res://scenes/battle.tscn"

## `get_script_constant_map()` 是 [Script] 的**实例**方法，
## 而 `PBLayout` 这个名字在语法上是个类型 —— 直接点上去解析期就报
## 「Cannot call non-static function ... directly」。要拿到那份常量表
## 得先把脚本当资源加载回来。
const LAYOUT_SCRIPT := "res://src/view/layout.gd"

## 允许贴边，但不许出去。浮点上留半个像素的余量。
const SLACK: float = 0.5


func test_every_layout_constant_fits_on_screen() -> void:
	var constants: Dictionary = (load(LAYOUT_SCRIPT) as GDScript).get_script_constant_map()
	var seen: int = 0
	for name: String in constants:
		var value: Variant = constants[name]
		if typeof(value) != TYPE_RECT2:
			continue
		seen += 1
		_assert_inside(value as Rect2, "PBLayout.%s" % name)
	assert_gt(seen, 5, "应该扫到一批矩形常量，扫不到说明反射那一步坏了")


func test_the_modal_layers_fit_on_screen() -> void:
	# 弹层的位置是算出来的（[method PBLayout.modal_rect]），不是常量 ——
	# 上面那条扫不到它。而它正是抽屉时代溢出的那一块。
	#
	# 高度**只到 360 为止**：算式只挪位置、不缩高度，而一层比屏幕还高的
	# 弹层是子类自己的 bug，悄悄压扁它只会把病灶藏起来。
	# 340 那一档钉的是钳位：照原式算它会从 B 的中线垂到界外。
	for height: float in [40.0, 116.0, 220.0, 340.0, 360.0]:
		_assert_inside(PBLayout.modal_rect(height), "modal_rect(%.0f)" % height)


func test_the_ground_plus_the_headroom_still_fit_in_the_field_box() -> void:
	# M6-a 压了 y 轴（[constant PBLayout.Y_SCALE]），于是 B 这个框里
	# 装着两截：**上面留给头顶的 [constant PBLayout.SPRITE_HEADROOM]**，
	# 下面是地面带。两截加起来超过框的话，最下面那排小人的脚会踩进底栏，
	# 而**那一截只是画在面板底下，不报错**——和抽屉出界一模一样的形状。
	#
	# 两个数各自都会被改：`field_height` 是配平旋钮（M5-2 动过一次），
	# 头顶那截要跟着真素材的身高走。所以钉的是它们的**和**。
	var cfg := PBSimConfig.new()
	var field := Vector2(cfg.field_length, cfg.field_height)
	var bottom: float = PBLayout.lane_bottom(field)
	assert_lte(
		bottom,
		PBLayout.FIELD_BOTTOM + SLACK,
		"地面带垂到 B 外面了：%.1f > %.1f" % [bottom, PBLayout.FIELD_BOTTOM]
	)
	assert_gte(
		PBLayout.GROUND_TOP - PBLayout.FIELD_TOP,
		PBLayout.SPRITE_HEADROOM - SLACK,
		"头顶那一截被吃掉了，最上面那排的头会戳进 A 顶栏"
	)


func test_a_circle_on_the_ground_is_an_ellipse_on_screen() -> void:
	# 战场上的射程与大招半径仍然是**真圆**（M4-a 立的），只是屏幕做了一次
	# 各向异性变换。画成正圆等于让玩家去躲一个不存在的纵向判定 ——
	# 那正是 M3.5-h 记着的那个错，M6-a 把它翻了个面。
	var field := Vector2(1.0, 0.44)
	var radius: float = 0.2
	var middle := Vector2(0.5, 0.22)
	var at := PBLayout.to_screen(middle, field)
	var ring := PBLayout.ground_disc(at, radius * PBLayout.px_per_unit(field))
	assert_gt(ring.size(), 8, "该给出一圈点")

	# 圈上的每一个点，换回战场坐标之后离圆心都该正好一个半径 ——
	# 那就是「屏幕上是椭圆、战场里是圆」这句话的可执行版本。
	for i: int in ring.size():
		var back := PBLayout.to_field(ring[i], field)
		assert_almost_eq(back.distance_to(middle), radius, 0.001, "第 %d 个点跑偏了" % i)


func test_no_control_in_the_real_scene_hangs_off_the_edge() -> void:
	# **常量对了不代表控件也对。** 抽屉那次错的正是这一层：
	# 带子在界内，而三张卡按老的步距摆，右边那张出去了 65 像素。
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = 20260827
	root.auto_play = false
	add_child_autofree(root)
	root._enter_prepare()
	# 两层模态平时是收着的，摊开才量得到里面的卡。
	root._state.gold = 999999
	root._on_command(&"gacha")
	root._beasts.open()
	root._beasts.refresh(root._state, root._cfg)
	await wait_physics_frames(2)

	var hud: Node = root.get_node("HUD")
	var checked: int = 0
	for node: Node in hud.find_children("", "Control", true, false):
		var control := node as Control
		if control.size == Vector2.ZERO or _in_popup(control, hud):
			continue
		checked += 1
		_assert_inside(control.get_global_rect(), "%s（%s）" % [control.name, control.get_class()])
	assert_gt(checked, 50, "应该量到一屏的控件，量不到说明遍历那一步坏了")


# ── 谁画在谁前面（M6-a）────────────────────────────────────────


func test_both_sides_sort_by_the_same_ground_point() -> void:
	# y 排序按**节点自己的 y** 排，所以敌我两边的节点位置必须都是
	# 「脚踩在哪」。一边锚在脚下、一边锚在中心的话，两把尺子差一个身高 ——
	# 一个站在前面的忍者会被站在他后面的敌人盖住，**而两边的坐标都完全正确**。
	#
	# 画布怎么往上抬是那张皮的事（[method PBActorSkin.draw_offset]），
	# 但**节点的位置只能是落脚点**，这条测的就是它。
	var field := Vector2(1.0, 0.44)
	var allies := PBAllyPool.new()
	var enemies := PBEnemyPool.new()
	add_child_autofree(allies)
	add_child_autofree(enemies)

	var attacker := PBAttacker.new()
	attacker.pos = Vector2(0.4, 0.3)
	attacker.max_hp = 100.0
	attacker.hp = 100.0
	attacker.slot = 0
	var squad: Array[PBAttacker] = [attacker]
	allies.sync_allies(squad, [] as Array[PBUnit], field, [] as Array[PBEnemy])
	assert_eq(
		(allies.get_child(0) as Node2D).position,
		PBLayout.to_screen(attacker.pos, field),
		"己方的锚必须正好在落脚点上"
	)

	var cfg := PBSimConfig.new()
	var wave := PBWaveRules.build(3, cfg, RandomNumberGenerator.new())
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.01, 0.4, 0, 0.3)
	enemy.arm(0.02, 4, 1.0, 0.0)
	var mob: Array[PBEnemy] = [enemy]
	enemies.sync_enemies(mob, 0, field)
	var drawn: AnimatedSprite2D = null
	for node: Node in enemies.get_children():
		if (node as AnimatedSprite2D).visible:
			drawn = node as AnimatedSprite2D
			break
	assert_not_null(drawn, "该画出这一个敌人")
	assert_eq(drawn.position, PBLayout.to_screen(enemy.pos(), field), "敌人的节点也必须在落脚点上")
	assert_lt(drawn.offset.y, 0.0, "画布要靠 offset 往上抬，不能抬节点自己")
	assert_false(drawn.centered, "居中的话原点就在画布中心，不是脚底")


func test_the_scene_still_sorts_the_two_pools_together() -> void:
	# 两个池子原来是**兄弟节点**，也就是所有己方永远画在所有敌人下面。
	# 扁平的方块和多边形看不出来；有身高的精灵一进来就穿模。
	# 少一个 `y_sort_enabled`（或者有人把池子搬出 `Actors`）整套排序就静默失效。
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	add_child_autofree(root)
	for path: String in ["Actors", "Actors/Deployed", "Actors/Enemies"]:
		var node := root.get_node_or_null(path) as Node2D
		assert_not_null(node, "场景里应该有 %s" % path)
		assert_true(node.y_sort_enabled, "%s 得开 y 排序，不然敌我不在同一层排" % path)


## 这个控件是不是长在一个弹出窗口里（[OptionButton] 的下拉列表就是，M6-d）。
##
## 那种控件**不归 [PBLayout] 管**：它装在一个独立的 [Window] 里，
## 位置和大小由引擎在弹出那一刻算，和 640×360 这块画布没有关系 ——
## 引擎给的默认尺寸是 512×512，照直量必然「出界」。
##
## 这不是给测试开的后门：**这一条测的是「我们自己摆的东西有没有摆出去」**，
## 而弹出窗口不是我们摆的。
##
## **只往上走到 [param stop_at] 为止。** 一路走到底的话每个控件都会命中 ——
## `get_tree().root` 本身就是一个 [Window]，于是这道过滤会把一屏控件全放过去，
## 而那正是「测试还在跑但什么都没测」的形状（`checked` 那条断言拦住了它）。
func _in_popup(control: Control, stop_at: Node) -> bool:
	var node: Node = control
	while node != null and node != stop_at:
		if node is Window:
			return true
		node = node.get_parent()
	return false


func _assert_inside(rect: Rect2, who: String) -> void:
	var edge: Vector2 = rect.position + rect.size
	assert_true(
		(
			rect.position.x >= -SLACK
			and rect.position.y >= -SLACK
			and edge.x <= PBLayout.SCREEN.x + SLACK
			and edge.y <= PBLayout.SCREEN.y + SLACK
		),
		"%s 伸出屏幕：%s ~ %s（画面 %s）" % [who, rect.position, edge, PBLayout.SCREEN]
	)
