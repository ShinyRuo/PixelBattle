class_name PBTouchControls
extends Control
## 浏览器和手机上的大触控目标；不改变键鼠端的既有快捷键。

signal key_requested(keycode: Key)
signal scroll_requested(zone: StringName, direction: int)
signal help_mode_changed(enabled: bool)

const BUTTON_SIZE := Vector2(66.0, 34.0)
const GAP := 4.0
const PANEL := Rect2(344.0, 34.0, 290.0, 164.0)

var _toggle: Button
var _panel: Panel
var _buttons: Dictionary = {}
var _help_mode: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle = _button(self, "操作", Vector2(515.0, 2.0), Vector2(55.0, 30.0))
	_toggle.pressed.connect(func() -> void: _panel.visible = not _panel.visible)
	_panel = PBSkin.panel(self, PANEL, PBSkin.PANEL_SOLID)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	var actions: Array[StringName] = [
		&"pause", &"speed_1", &"speed_2", &"speed_3",
		&"start", &"auto", &"cancel", &"restart", &"fullscreen",
	]
	var keys: Array[Key] = [
		KEY_SPACE, KEY_1, KEY_2, KEY_3, KEY_ENTER, KEY_A, KEY_ESCAPE, KEY_R, KEY_F11
	]
	var labels := ["暂停", "1 倍", "2 倍", "3 倍", "开打", "自动", "取消瞄准", "重开", "全屏"]
	for i: int in actions.size():
		var at := Vector2(4.0 + float(i % 4) * (BUTTON_SIZE.x + GAP),
			4.0 + float(i / 4) * (BUTTON_SIZE.y + GAP))
		var button := _button(_panel, labels[i], at, BUTTON_SIZE)
		var keycode: Key = keys[i]
		button.pressed.connect(func() -> void: key_requested.emit(keycode))
		_buttons[actions[i]] = button
	var scroll_labels := ["忍者上翻", "忍者下翻", "忍具上翻", "忍具下翻"]
	for i: int in scroll_labels.size():
		var at := Vector2(4.0 + float((i + 9) % 4) * (BUTTON_SIZE.x + GAP),
			4.0 + float((i + 9) / 4) * (BUTTON_SIZE.y + GAP))
		var button := _button(_panel, scroll_labels[i], at, BUTTON_SIZE)
		var zone: StringName = &"roster" if i < 2 else &"parts"
		var direction: int = -1 if i % 2 == 0 else 1
		button.pressed.connect(func() -> void: scroll_requested.emit(zone, direction))
	var help := _button(_panel, "点按看说明", Vector2(144.0, 118.0), Vector2(136.0, 34.0))
	help.pressed.connect(
		func() -> void:
			_help_mode = not _help_mode
			help.modulate = PBSkin.TITLE if _help_mode else Color.WHITE
			help_mode_changed.emit(_help_mode)
	)


func refresh(paused: bool, speed: int, preparing: bool, auto: bool, aiming: bool) -> void:
	_buttons[&"pause"].text = "继续" if paused else "暂停"
	_buttons[&"start"].disabled = not preparing
	_buttons[&"auto"].text = "手动" if auto else "自动"
	_buttons[&"cancel"].disabled = not aiming
	for i: int in 3:
		var button: Button = _buttons[StringName("speed_%d" % (i + 1))]
		button.modulate = PBSkin.TITLE if speed == i + 1 else Color.WHITE


func _button(parent: Control, title: String, at: Vector2, extent: Vector2) -> Button:
	var button := Button.new()
	button.text = title
	button.position = at
	button.size = extent
	button.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(button, PBSkin.Tone.PLAIN)
	parent.add_child(button)
	return button
