@tool
class_name PBBuffArtPage
extends VBoxContainer
## 预览与战斗共用前后层绘制器，保存后下次运行读取。

var asset_dir: String = "res://assets/fx/buffs"
var cast_preview: bool = false
var instant_only: bool = false

var _bindings := PBBuffArtBindings.new()
var _blend: OptionButton
var _buffs: OptionButton
var _skin: PBBuffSkin
var _fields: Dictionary = {}
var _dialog: FileDialog
var _status: Label
var _back: PBBuffGlow
var _front: PBBuffGlow
var _front_selected: bool = false
var _elapsed: float = 0.0
var _sheet: PBFieldSheetControls
var _sheet_preview: PBFieldSheetPreview
var _layer: OptionButton
var _pending: Dictionary = {}
var _busy: bool = false
var _playing: bool = true
var _frame: SpinBox


func _ready() -> void:
	if instant_only:
		name = "瞬时恢复"
		asset_dir = "res://assets/fx/instant_buffs"
		_bindings.output_dir = "res://data/instant_buff_art"
	else:
		name = "BUFF光效"
	_build_choices()
	var row := HBoxContainer.new()
	add_child(row)
	_button(row, "导入背后层 PNG", func() -> void: _choose(false))
	_button(row, "导入身前层 PNG", func() -> void: _choose(true))
	_button(row, "清除背后层", func() -> void: _clear(false))
	_button(row, "清除身前层", func() -> void: _clear(true))
	_button(row, "保存光效", _save)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 440
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)
	_layer = OptionButton.new()
	_layer.add_item("切图目标：背后层")
	_layer.add_item("切图目标：身前层")
	_layer.item_selected.connect(func(_i: int) -> void: _restore_sheet())
	side.add_child(_layer)
	_sheet = PBFieldSheetControls.new()
	_sheet.cut_requested.connect(_cut)
	_sheet.source_changed.connect(_show_source)
	side.add_child(_sheet)
	_button(side, "一键切图并保存光效", _cut_and_save)
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(preview)
	_sheet_preview = PBFieldSheetPreview.new()
	_sheet_preview.custom_minimum_size = Vector2(260, 200)
	preview.add_child(_sheet_preview)
	var play_row := HBoxContainer.new()
	preview.add_child(play_row)
	var play := CheckBox.new()
	play.text = "播放"
	play.button_pressed = true
	play.toggled.connect(func(on: bool) -> void: _playing = on)
	play_row.add_child(play)
	_frame = PBFieldSheetControls.number(play_row, "帧", 1, 64, 1)
	_blend = OptionButton.new()
	_blend.add_item("混合：加色光效（光晕、亮色粒子）")
	_blend.add_item("混合：普通透明（黑影、灰雾、实体缠绕）")
	_blend.item_selected.connect(func(_i: int) -> void: _update_skin())
	side.add_child(_blend)
	var fields := GridContainer.new()
	fields.columns = 4
	side.add_child(fields)
	for title: String in ["帧率", "缩放", "脚底X", "脚底Y", "偏移X", "偏移Y"]:
		var label := Label.new()
		label.text = title
		fields.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = -4096
		spin.max_value = 4096
		spin.step = 0.01
		fields.add_child(spin)
		_fields[title] = spin
		spin.value_changed.connect(func(_v: float) -> void: _update_skin())
	var help := Label.new()
	help.text = (
		"选择整张序列图 → 设置网格与去底 → 切图预览 → 保存。前后层同画布；光晕选加色，黑影/灰雾选普通透明。\n"
		+ "支持忍者与敌方持续状态；列表标注阵营。灰色人形为脚底锚点参照。\n"
		+ "保存后下一次运行生效。"
	)
	if cast_preview:
		help.text = (
			"起手光：复用前后层与脚底锚点，不挂数值 BUFF。\n"
			+ "六帧建议 20 fps；0–0.3 秒单次播放，释放/打断立即消失。\n"
			+ "预览含短暂停顿后重播；保存后到技能表现页选择此光效。"
		)
	elif instant_only:
		help.text = ("瞬时恢复：不进入持续 BUFF 槽，真实结算发生时按效果键播放一次。\n" + "推荐透明六帧、8 fps；当前只使用身前层，保存后战斗自动读取。")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(help)
	_status = Label.new()
	add_child(_status)
	var stage := Control.new()
	stage.custom_minimum_size.y = 120
	preview.add_child(stage)
	_back = PBBuffGlow.new()
	_back.position = Vector2(180, 105)
	stage.add_child(_back)
	var actor := Polygon2D.new()
	actor.position = _back.position
	actor.polygon = PackedVector2Array(
		[
			Vector2(-8, 0),
			Vector2(-10, -42),
			Vector2(-6, -60),
			Vector2(6, -60),
			Vector2(10, -42),
			Vector2(8, 0)
		]
	)
	actor.color = Color(0.4, 0.45, 0.5)
	stage.add_child(actor)
	_front = PBBuffGlow.new()
	_front.front = true
	_front.position = _back.position
	stage.add_child(_front)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_dialog.access = FileDialog.ACCESS_RESOURCES
	_dialog.filters = PackedStringArray(["*.png ; PNG 光效帧"])
	_dialog.files_selected.connect(_import)
	add_child(_dialog)
	_select()


func _build_choices() -> void:
	_buffs = OptionButton.new()
	for line: String in FileAccess.get_file_as_string("res://data/buffs.tsv").split("\n"):
		if line.begins_with("#") or line.strip_edges().is_empty():
			continue
		var row := line.split("\t")
		if (row[2] == "瞬间") != instant_only:
			continue
		var buff := load("res://data/buffs/%s.tres" % row[0]) as PBBuff
		var side := "友方" if buff.friendly else "敌方"
		_buffs.add_item("[%s] %s · %s" % [side, row[1], row[0]])
		_buffs.set_item_metadata(_buffs.item_count - 1, row[0])
	add_child(_buffs)
	_buffs.item_selected.connect(func(_i: int) -> void: _select())


func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)


func _id() -> String:
	return str(_buffs.get_item_metadata(_buffs.selected))


func _select() -> void:
	_skin = null
	_pending.clear()
	var skin := _bindings.read(_id())
	if cast_preview and not ResourceLoader.exists("%s/%s.tres" % [_bindings.output_dir, _id()]):
		skin.fps = 20.0
	var values := [
		skin.fps, skin.pixel_scale, skin.anchor.x, skin.anchor.y, skin.offset.x, skin.offset.y
	]
	var index := 0
	for spin: SpinBox in _fields.values():
		spin.value = values[index]
		index += 1
	_blend.select(skin.blend_style)
	_skin = skin
	_restore_sheet()
	_status.text = "已加载；修改后请保存。"


func _update_skin() -> void:
	if _skin == null:
		return
	_skin.blend_style = _blend.selected as PBBuffSkin.BlendStyle
	_skin.fps = _fields["帧率"].value
	_skin.pixel_scale = _fields["缩放"].value
	_skin.anchor = Vector2(_fields["脚底X"].value, _fields["脚底Y"].value)
	_skin.offset = Vector2(_fields["偏移X"].value, _fields["偏移Y"].value)
	_status.text = "尚未保存"


func _choose(front: bool) -> void:
	_front_selected = front
	_dialog.popup_centered_ratio(0.7)


func _import(paths: PackedStringArray) -> void:
	var error := _bindings.import_layer(_skin, paths, _front_selected)
	if error == "":
		_pending.erase(_front_selected)
	_status.text = error if error != "" else "已导入预览，点击保存生效"


func _clear(front: bool) -> void:
	if front:
		_skin.front_frames = []
	else:
		_skin.back_frames = []
	_skin.placeholder = false
	_pending.erase(front)
	_status.text = "已清除预览层，点击保存生效"


func _save() -> void:
	if _busy:
		return
	if not _id().is_valid_identifier():
		_status.text = "请填写合法的光效键（英文、数字、下划线）"
		return
	_busy = true
	_set_editable(self, false)
	var error := ""
	var skin := _skin.duplicate() as PBBuffSkin
	for front: bool in _pending:
		var images: Array[Image] = _pending[front]
		var dir := "%s/%s/%s" % [asset_dir, _id(), "front" if front else "back"]
		error = PBFxForge.write(images, dir, "frame")
		if error != "":
			break
		var paths := PackedStringArray()
		for i: int in images.size():
			paths.append("%s/frame_%d.png" % [dir, i])
		await _rescan(paths)
		error = _bindings.import_layer(skin, paths, front)
		if error != "":
			break
	if error == "":
		error = _bindings.save(_id(), skin)
	if error == "":
		_skin = skin
		_pending.clear()
		await _rescan()
	_status.text = error if error != "" else "已保存：%s/%s.tres" % [_bindings.output_dir, _id()]
	_busy = false
	_set_editable(self, true)


func _cut() -> bool:
	if _busy:
		return false
	var error := _sheet.cut()
	if error != "":
		_status.text = error
		return false
	var textures: Array[Texture2D] = []
	for image: Image in _sheet.images:
		textures.append(ImageTexture.create_from_image(image))
	var front := _layer.selected == 1
	var trial := _skin.duplicate() as PBBuffSkin
	if front:
		trial.front_frames = textures
	else:
		trial.back_frames = textures
	error = trial.problem()
	if error != "":
		_status.text = error
		return false
	trial.placeholder = false
	trial.tint = Color.WHITE
	trial.set_meta("sheet_front" if front else "sheet_back", _sheet.settings())
	_skin = trial
	_pending[front] = _sheet.images.duplicate()
	_elapsed = 0
	_status.text = "切出 %d 帧；调整脚底和缩放后保存。" % textures.size()
	return true


func _cut_and_save() -> void:
	if _cut():
		await _save()


func _restore_sheet() -> void:
	_sheet.restore(_skin.get_meta("sheet_front" if _layer.selected == 1 else "sheet_back", {}))


func _show_source() -> void:
	if _sheet_preview != null:
		_sheet_preview.show_sheet(_sheet.source, _sheet.forge.cells)


func _set_editable(node: Node, enabled: bool) -> void:
	if node is BaseButton:
		node.disabled = not enabled
	elif node is SpinBox or node is LineEdit:
		node.editable = enabled
	for child: Node in node.get_children():
		_set_editable(child, enabled)


func _rescan(paths: PackedStringArray = []) -> void:
	var editor := Engine.get_singleton(&"EditorInterface")
	if editor == null:
		return
	var files = editor.get_resource_filesystem()
	files.scan()
	for _tick: int in 600:
		await get_tree().process_frame
		if not files.is_scanning():
			break
	# 扫描结束不代表异步纹理导入已完成；等源图摘要一致，避免读取上一版。
	for _tick: int in 200:
		if _imports_ready(paths):
			return
		await get_tree().create_timer(0.05).timeout


func _imports_ready(paths: PackedStringArray) -> bool:
	for path: String in paths:
		var config := ConfigFile.new()
		if config.load(path + ".import") != OK:
			return false
		var imported: String = config.get_value("remap", "path", "")
		var stamp := imported.get_basename() + ".md5"
		if not ResourceLoader.exists(path) or not FileAccess.file_exists(stamp):
			return false
		var expected := 'source_md5="%s"' % FileAccess.get_md5(path)
		if not FileAccess.get_file_as_string(stamp).contains(expected):
			return false
	return true


func _process(delta: float) -> void:
	if _skin == null or _back == null:
		return
	if _playing:
		_elapsed += delta
	else:
		_elapsed = (_frame.value - 1) / maxf(_skin.fps, 0.01)
	var skin := _skin if _skin.problem() == "" else null
	var age := fmod(_elapsed, 0.9) if cast_preview and _playing else _elapsed
	if cast_preview and _playing and age >= 0.3:
		skin = null
	var tick := floori(age * 20.0)
	if cast_preview and skin != null:
		_back.preview_once(skin, tick, 20)
		_front.preview_once(skin, tick, 20)
	elif instant_only and skin != null:
		var duration := float(maxi(skin.front_frames.size(), skin.back_frames.size())) / skin.fps
		age = fmod(_elapsed, duration + 0.6) if _playing else _elapsed
		tick = floori(age * 20.0)
		if age < duration:
			_back.preview_once(skin, tick, 20)
			_front.preview_once(skin, tick, 20)
		else:
			_back.clear()
			_front.clear()
	else:
		_back.preview(skin, tick)
		_front.preview(skin, tick)
