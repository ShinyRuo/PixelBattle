@tool
extends EditorPlugin
## 「战场形象」插件的外壳。M6-l。
##
## **这里只做挂载，一行逻辑都没有。** 面板本体是
## `src/tools/actor_forge_panel.gd`，流水线是 `src/tools/actor_forge.gd` ——
## 两个都在 `src/` 下，于是 `check.ps1` 的 gdlint 和 GUT 都扫得到它们。
## `addons/` 是第三方插件的地方，那一档不 lint 也不测（见 CLAUDE.md）,
## 把自己的代码放进去等于给它免检。
##
## 挂在**底栏**而不是主屏：底栏那一排按钮（输出、调试器…）是编辑器里
## 最容易找到的地方，而这个工具的用户是「不太用编辑器的人」。

var _panel: Control


func _enter_tree() -> void:
	_panel = preload("res://src/tools/actor_forge_panel.gd").new()
	add_control_to_bottom_panel(_panel, "战场形象")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
