@tool
class_name PBArtBindingPage
extends VBoxContainer
## 把已有成品素材绑定到技能；缺少结算入口的表现不能伪装成已接入。

var _bindings := PBArtBindings.new()
var _skills: OptionButton
var _flight_modes: OptionButton
var _shots: OptionButton
var _status: Label
var _actions: OptionButton
var _starts: OptionButton
var _start_bindings := PBCastArtBindings.new()
var _preview: AnimatedSprite2D


func _ready() -> void:
	name = "技能表现"
	add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "技能表现：选技能 → 选择形象动作 + 起手光 + 命名技能子弹"
	add_child(title)
	_skills = OptionButton.new()
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: PackedStringArray in _bindings.skills():
		_skills.add_item("%s · %s · %s" % [row[2], row[1], row[0]])
		_skills.set_item_metadata(_skills.item_count - 1, row[0])
	_skills.item_selected.connect(func(_index: int) -> void: _show_cast())
	add_child(_skills)
	var cast_row := HBoxContainer.new()
	add_child(cast_row)
	_actions = OptionButton.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_row.add_child(_actions)
	_button(cast_row, "刷新动作列表", _show_cast)
	_button(cast_row, "绑定所选动作", _assign_action)
	_button(cast_row, "取消专属施法（使用攻击动作）", _clear_cast)
	_button(cast_row, "打开资产清单", _open_catalog)
	var shot_row := HBoxContainer.new()
	add_child(shot_row)
	_flight_modes = OptionButton.new()
	for title_text: String in ["沿用默认", "不显示子弹", "指定子弹"]:
		_flight_modes.add_item(title_text)
	shot_row.add_child(_flight_modes)
	_flight_modes.item_selected.connect(
		func(index: int) -> void: _shots.disabled = index != PBArtBindings.Flight.NAMED
	)
	_shots = OptionButton.new()
	_shots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shot_row.add_child(_shots)
	_button(shot_row, "刷新子弹列表", _refresh_shots)
	_button(shot_row, "绑定技能子弹", _assign_shot)
	var start_row := HBoxContainer.new()
	add_child(start_row)
	_starts = OptionButton.new()
	_starts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_row.add_child(_starts)
	_button(start_row, "刷新起手光列表", _refresh_starts)
	_button(start_row, "绑定起手光", _assign_start)
	_refresh_starts()
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = (
		"动作：在战场形象工具切图，导出 skill1 / skill2 并生成形象表，再来本页选择。"
		+ "预览为 10 fps；本页不改变战斗施法时序。\n"
		+ "起手光：在「起手光效」页切图保存，再在这里选择；无起手光可解除绑定。\n"
		+ "子弹：先在「子弹」页生成资源；可选沿用默认、不显示子弹或指定子弹；隐藏仅影响飞行图，不改变命中与延迟。\n"
		+ "忍者环身光使用「BUFF光效」页；范围与连线使用「区域与连线」页。"
	)
	add_child(help)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var preview_box := Control.new()
	preview_box.custom_minimum_size.y = 110.0
	preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(preview_box)
	_preview = AnimatedSprite2D.new()
	_preview.position = Vector2(120, 55)
	preview_box.add_child(_preview)
	_refresh_shots()
	_show_cast()


func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)


func _skill_id() -> String:
	return str(_skills.get_selected_metadata()) if _skills.selected >= 0 else ""


func _assign_action() -> void:
	if _actions.selected >= 0:
		_report(_bindings.assign_animation(_skill_id(), _actions.get_selected_metadata()))


func _clear_cast() -> void:
	_report(_bindings.clear_cast(_skill_id()))


func _assign_shot() -> void:
	_report(
		_bindings.assign_flight(
			_skill_id(), _flight_modes.selected, str(_shots.get_selected_metadata())
		)
	)


func _refresh_shots() -> void:
	_shots.clear()
	_shots.add_item("请选择命名子弹")
	_shots.set_item_metadata(0, "")
	var files := DirAccess.get_files_at(_bindings.shot_dir)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			_shots.add_item(file.get_basename())
			_shots.set_item_metadata(_shots.item_count - 1, file.get_basename())


func _report(error: String) -> void:
	_status.text = "已保存。" if error.is_empty() else error
	if Engine.is_editor_hint() and error.is_empty():
		EditorInterface.get_resource_filesystem().scan()
	_show_cast()


func _show_cast() -> void:
	_refresh_starts()
	var skill_path := "%s/%s.tres" % [_bindings.skill_dir, _skill_id()]
	if ResourceLoader.exists(skill_path):
		var skill := load(skill_path) as PBSkill
		var mode := PBArtBindings.Flight.DEFAULT
		if PBSkillStartArt.flight_hidden(StringName(_skill_id())):
			mode = PBArtBindings.Flight.HIDDEN
		elif skill.shot_key != &"":
			mode = PBArtBindings.Flight.NAMED
		_flight_modes.select(mode)
		_shots.disabled = mode != PBArtBindings.Flight.NAMED
		_shots.select(0)
		for i: int in _shots.item_count:
			if str(_shots.get_item_metadata(i)) == String(skill.shot_key):
				_shots.select(i)
	var path := _bindings.actor_path(_skill_id())
	_preview.visible = false
	_actions.clear()
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var skin := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBActorSkin
	if skin == null or skin.frames == null:
		return
	for anim: StringName in skin.frames.get_animation_names():
		if skin.frames.get_frame_count(anim) != 6:
			continue
		_actions.add_item(String(anim))
		_actions.set_item_metadata(_actions.item_count - 1, anim)
		if anim == skin.skill_anim(StringName(_skill_id())):
			_actions.select(_actions.item_count - 1)
	_preview.sprite_frames = skin.frames
	_preview.scale = Vector2.ONE * skin.pixel_scale * 2.0
	var anim := skin.skill_anim(StringName(_skill_id()))
	_preview.speed_scale = 10.0 / maxf(skin.frames.get_animation_speed(anim), 0.01)
	_preview.play(anim)
	_preview.visible = true


func _open_catalog() -> void:
	OS.shell_open(ProjectSettings.globalize_path("res://Docs/美术资产清单.md"))


func _refresh_starts() -> void:
	_starts.clear()
	_starts.add_item("无起手光")
	_starts.set_item_metadata(0, "")
	var selected := _start_bindings.read(_skill_id())
	for key: String in _start_bindings.keys():
		_starts.add_item(key)
		_starts.set_item_metadata(_starts.item_count - 1, key)
		if key == String(selected):
			_starts.select(_starts.item_count - 1)


func _assign_start() -> void:
	_report(_start_bindings.assign(_skill_id(), str(_starts.get_selected_metadata())))
