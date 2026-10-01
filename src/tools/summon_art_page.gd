@tool
class_name PBSummonArtPage
extends VBoxContainer
## 复用两套素材加工工具的成品，为每类召唤物绑定四态与普攻子弹。

var _bindings := PBSummonArtBindings.new()
var _summons: OptionButton
var _actors: OptionButton
var _shots: OptionButton
var _spawns: OptionButton
var _actions: OptionButton
var _status: Label
var _preview: AnimatedSprite2D
var _bullet: AnimatedSprite2D
var _help: Label


func _ready() -> void:
	name = "召唤物表现"
	add_theme_constant_override("separation", 10)
	_summons = OptionButton.new()
	for row: Dictionary in _bindings.entries():
		_summons.add_item(row.label)
		_summons.set_item_metadata(_summons.item_count - 1, row.id)
	_summons.item_selected.connect(func(_i: int) -> void: _refresh())
	add_child(_summons)
	_actors = _picker("四态形象（战场形象工具生成）")
	_shots = _picker("远程普攻子弹（子弹工具生成）")
	_spawns = _picker("出生烟（环身光工具生成，可选）")
	_actors.item_selected.connect(func(_i: int) -> void: _show_preview())
	_shots.item_selected.connect(func(_i: int) -> void: _show_preview())
	var row := HBoxContainer.new()
	add_child(row)
	_button(row, "刷新资源 / 读取已保存绑定", _refresh)
	_button(row, "保存召唤物绑定", _save)
	_button(row, "打开配置流程", _open_guide)
	_actions = OptionButton.new()
	for action: String in ["idle", "run", "attack", "dead"]:
		_actions.add_item(action)
	_actions.item_selected.connect(func(_i: int) -> void: _show_preview())
	add_child(_actions)
	_help = Label.new()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_help)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var area := Control.new()
	area.custom_minimum_size = Vector2(400, 180)
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(area)
	_preview = AnimatedSprite2D.new()
	_preview.position = Vector2(120, 150)
	_preview.centered = false
	area.add_child(_preview)
	_bullet = AnimatedSprite2D.new()
	_bullet.position = Vector2(300, 100)
	area.add_child(_bullet)
	_refresh()


func _picker(title: String) -> OptionButton:
	var label := Label.new()
	label.text = title
	add_child(label)
	var pick := OptionButton.new()
	add_child(pick)
	return pick


func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)


func _id() -> String:
	return str(_summons.get_selected_metadata()) if _summons.selected >= 0 else ""


func _fill(pick: OptionButton, directory: String, selected: StringName) -> void:
	pick.clear()
	pick.add_item("未指定（保持默认表现）")
	pick.set_item_metadata(0, "")
	for key: String in _bindings.keys(directory):
		pick.add_item(key)
		pick.set_item_metadata(pick.item_count - 1, key)
		if StringName(key) == selected:
			pick.select(pick.item_count - 1)
	if selected != &"" and pick.selected == 0:
		pick.add_item("缺失资源：%s" % selected)
		pick.set_item_metadata(pick.item_count - 1, String(selected))
		pick.select(pick.item_count - 1)


func _refresh() -> void:
	var art := _bindings.read(_id())
	_fill(_actors, _bindings.actor_dir, art.actor_key)
	_fill(_shots, _bindings.shot_dir, art.shot_key)
	_fill(_spawns, _bindings.spawn_dir, art.spawn_fx_key)
	_help.text = (
		(
			"① 战场形象：角色键可用 summon_%s；导入 AI 序列图，分别切图、导出四段六帧并生成形象表。\n"
			+ "② 子弹页：使用独立命名键生成飞行段；不需要新增受击特效。\n"
			+ "③ 本页选择上述成品并保存；也可选择已有忍者形象复用。\n"
			+ "子弹绑定只改变远程攻击的外观，不会把近战召唤物变成远程。"
			+ "未指定时普通召唤物使用白模，幻影沿用本体形象；子弹使用默认白模。"
		)
		% _id()
	)
	_show_preview()


func _save() -> void:
	var error := _bindings.assign(
		_id(), str(_actors.get_selected_metadata()), str(_shots.get_selected_metadata()),
		str(_spawns.get_selected_metadata())
	)
	_status.text = "已保存；下次运行战斗生效。" if error == "" else error
	if error == "" and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _show_preview() -> void:
	_preview.visible = false
	_bullet.visible = false
	var actor_path := "%s/%s.tres" % [_bindings.actor_dir, _actors.get_selected_metadata()]
	if ResourceLoader.exists(actor_path):
		var art := (
			ResourceLoader.load(actor_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBActorSkin
		)
		if art != null and art.frames != null:
			_preview.sprite_frames = art.frames
			_preview.offset = art.draw_offset()
			_preview.scale = Vector2.ONE * art.pixel_scale * 2.0
			_preview.texture_filter = art.filter_mode()
			_preview.flip_h = art.flips_for(PBActorPose.FACE_RIGHT)
			var states := [
				PBActorPose.State.IDLE,
				PBActorPose.State.RUN,
				PBActorPose.State.ATTACK,
				PBActorPose.State.DEAD
			]
			_preview.play(art.anim_for(states[_actions.selected]))
			_preview.set_frame_and_progress(0, 0.0)
			_preview.visible = true
	var shot_path := "%s/%s.tres" % [_bindings.shot_dir, _shots.get_selected_metadata()]
	if ResourceLoader.exists(shot_path):
		var art := (
			ResourceLoader.load(shot_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBShotSkin
		)
		if art != null and art.has(art.anim_fly):
			_bullet.sprite_frames = art.frames
			_bullet.scale = Vector2.ONE * art.pixel_scale * 2.0
			_bullet.texture_filter = art.filter_mode()
			var material := CanvasItemMaterial.new()
			material.blend_mode = (
				CanvasItemMaterial.BLEND_MODE_ADD
				if art.additive_fly
				else CanvasItemMaterial.BLEND_MODE_MIX
			)
			_bullet.material = material
			_bullet.play(art.anim_fly)
			_bullet.visible = true


func _open_guide() -> void:
	OS.shell_open(ProjectSettings.globalize_path("res://Docs/召唤物表现配置.md"))
