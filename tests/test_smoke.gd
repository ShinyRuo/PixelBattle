extends GutTest
## 冒烟测试：证明「引擎 + 测试框架 + 命令行」这条闭环是通的。
##
## GUT 约定：文件名以 test_ 开头，测试方法以 test_ 开头，继承 GutTest。
## 跑法：scripts/check.ps1，或 VSCode 里 Ctrl+Shift+B。
##
## 命名用英文：中文函数名 GDScript 本身能跑，但 gdlint 的 function-name
## 规则不认（必须匹配 snake_case 正则）。中文放注释和断言消息里。

const MAIN_SCENE := "res://scenes/main.tscn"
const PLAYER_SCRIPT := "res://src/player/player.gd"


func test_main_scene_loads() -> void:
	assert_not_null(load(MAIN_SCENE), "scenes/main.tscn 应该能被加载")


func test_player_default_speed() -> void:
	var player: CharacterBody2D = load(PLAYER_SCRIPT).new()
	assert_eq(player.speed, 220.0, "玩家默认速度应为 220")
	player.free()


func test_main_scene_has_player_node() -> void:
	var root := _spawn_main()
	assert_not_null(root.get_node_or_null("Player"), "主场景里应该有名为 Player 的节点")


func test_player_stays_still_without_input() -> void:
	var root := _spawn_main()
	var player: CharacterBody2D = root.get_node("Player")
	var start_pos := player.position
	# 没有任何输入，跑几个物理帧后位置应该不变
	await wait_physics_frames(3)
	assert_eq(player.position, start_pos, "无输入时玩家不应移动")


## 实例化主场景并挂到测试树上。
## add_child_autofree 会在用例结束后自动释放，避免 GUT 报内存泄漏。
func _spawn_main() -> Node:
	var scene: PackedScene = load(MAIN_SCENE)
	var root := scene.instantiate()
	add_child_autofree(root)
	return root
