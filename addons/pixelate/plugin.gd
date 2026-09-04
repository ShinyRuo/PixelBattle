@tool
extends EditorPlugin
## 「降采样」插件的外壳。M6-p。
##
## **这里只做挂载，一行逻辑都没有。** 面板本体是
## `src/tools/pixelate_panel.gd`，流水线是 `src/tools/pixelate.gd` ——
## 两个都在 `src/` 下，于是 `check.ps1` 的 gdlint 和 GUT 都扫得到它们。
## `addons/` 那一档不 lint 也不测（见 CLAUDE.md），把自己的代码放进去
## 等于给它免检。
##
## 挂在**底栏**，和「战场形象」并排：两块面板是同一条工作流的上下游 ——
## 这块把立绘压成像素图，那块把视频压成成品帧。

var _panel: Control


func _enter_tree() -> void:
	_panel = preload("res://src/tools/pixelate_panel.gd").new()
	add_control_to_bottom_panel(_panel, "降采样")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
