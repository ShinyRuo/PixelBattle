@tool
extends EditorPlugin

var _panel: Control


func _enter_tree() -> void:
	_panel = preload("res://src/tools/fx_forge_panel.gd").new()
	add_control_to_bottom_panel(_panel, "战场特效")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
