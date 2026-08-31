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

	var checked: int = 0
	for node: Node in root.get_node("HUD").find_children("", "Control", true, false):
		var control := node as Control
		if control.size == Vector2.ZERO:
			continue
		checked += 1
		_assert_inside(control.get_global_rect(), "%s（%s）" % [control.name, control.get_class()])
	assert_gt(checked, 50, "应该量到一屏的控件，量不到说明遍历那一步坏了")


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
