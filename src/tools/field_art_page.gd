@tool
class_name PBFieldArtPage
extends VBoxContainer

var _bindings := PBFieldArtBindings.new()
var _choices: OptionButton
var _rows: Array[Dictionary] = []
var _fps: SpinBox
var _width: SpinBox
var _scale: SpinBox
var _offset_x: SpinBox
var _offset_y: SpinBox
var _status: Label
var _range: Label
var _preview: PBFieldArtPreview
var _sheet_preview: PBFieldSheetPreview
var _sheet: PBFieldSheetControls
var _dialog: FileDialog
var _skin: PBFieldSkin
var _generated: bool = false
var _busy: bool = false
var _cut_images: Array[Image] = []


func _ready() -> void:
	name = "区域与连线"
	_choices = OptionButton.new()
	_rows = _bindings.choices()
	for row: Dictionary in _rows:
		_choices.add_item("%s · %s" % [row.name, row.id])
	_choices.item_selected.connect(func(_i: int) -> void: _select())
	add_child(_choices)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_build_side(body)
	_build_preview(body)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_RESOURCES
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_dialog.filters = PackedStringArray(["*.png ; 已切好的 PNG 帧"])
	_dialog.files_selected.connect(_import)
	add_child(_dialog)
	if not _rows.is_empty():
		_select()


func _build_side(body: Node) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 430
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)
	_sheet = PBFieldSheetControls.new()
	_sheet.cut_requested.connect(_cut)
	_sheet.source_changed.connect(_show_source)
	side.add_child(_sheet)
	_button(side, "一键切图并保存到所选技能", _cut_and_save)
	var buttons := HBoxContainer.new()
	side.add_child(buttons)
	_button(buttons, "导入已切 PNG", func() -> void: _dialog.popup_centered_ratio(0.7))
	_button(buttons, "清除素材", _clear)
	_button(buttons, "保存配置", _save)
	var timing := HBoxContainer.new()
	side.add_child(timing)
	_fps = _number(timing, "帧率", 1, 60, 10)
	_width = _number(timing, "连线宽", 1, 64, 5)
	var placement := HBoxContainer.new()
	side.add_child(placement)
	_scale = _number(placement, "特效缩放", 0.1, 4, 1, 0.05)
	_offset_x = _number(placement, "偏移 X", -2, 2, 0, 0.05)
	_offset_y = _number(placement, "Y", -2, 2, 0, 0.05)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = (
		"先选技能 → 选整图与背景 → 切图预览 → 保存。\n"
		+ "区域使用俯视图；普通透明混合。烟雾模式仅提取灰黑暗部。\n"
		+ "缩放和偏移只改美术，偏移单位为判定半径。多圆按实际配置预览。"
	)
	side.add_child(help)


func _build_preview(body: Node) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(column)
	_sheet_preview = PBFieldSheetPreview.new()
	_sheet_preview.custom_minimum_size = Vector2(260, 130)
	column.add_child(_sheet_preview)
	_range = Label.new()
	_range.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_range)
	var controls := HBoxContainer.new()
	column.add_child(controls)
	var play := CheckBox.new()
	play.text = "播放"
	play.button_pressed = true
	play.toggled.connect(func(on: bool) -> void: _preview.paused = not on)
	controls.add_child(play)
	var frame := PBFieldSheetControls.number(controls, "帧", 1, 64, 1)
	frame.value_changed.connect(func(v: float) -> void: _preview.selected_frame = int(v) - 1)
	var zoom := PBFieldSheetControls.number(controls, "预览倍率", 0.25, 4, 1, 0.25)
	zoom.value_changed.connect(func(v: float) -> void: _preview.zoom = v)
	var guides := CheckBox.new()
	guides.text = "范围线"
	guides.button_pressed = true
	guides.toggled.connect(func(on: bool) -> void: _preview.guides = on)
	controls.add_child(guides)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(260, 170)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	column.add_child(stage)
	var background := ColorRect.new()
	background.color = Color(0.38, 0.42, 0.46)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	_preview = PBFieldArtPreview.new()
	stage.add_child(_preview)
	stage.resized.connect(func() -> void: _preview.position = stage.size * 0.5)


func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)


func _number(
	parent: Node, title: String, low: float, high: float, value: float, step: float = 1
) -> SpinBox:
	var spin := PBFieldSheetControls.number(parent, title, low, high, value, step)
	spin.value_changed.connect(func(_v: float) -> void: _update())
	return spin


func _select() -> void:
	_skin = null
	_generated = false
	_cut_images.clear()
	var row: Dictionary = _rows[_choices.selected]
	var skin := _bindings.read(row.kind, row.id)
	_fps.value = skin.fps
	_width.value = skin.link_width
	_scale.value = skin.area_scale
	_offset_x.value = skin.area_offset.x
	_offset_y.value = skin.area_offset.y
	_width.editable = row.kind == "links"
	_skin = skin
	_preview.skin = skin
	_preview.kind = row.kind
	_preview.skill = load("res://data/skills/%s.tres" % row.id) if row.kind != "links" else null
	_preview._age = 0
	_sheet.restore(skin.get_meta("sheet", {}))
	_range.text = _preview.range_text()
	_status.text = "已加载；保存仅更新所选技能的美术资源"


func _update() -> void:
	if _skin == null:
		return
	_skin.fps = _fps.value
	_skin.link_width = _width.value
	_skin.area_scale = _scale.value
	_skin.area_offset = Vector2(_offset_x.value, _offset_y.value)
	_status.text = "尚未保存"


func _show_source() -> void:
	if _sheet_preview != null:
		_sheet_preview.show_sheet(_sheet.source, _sheet.forge.cells)


func _cut() -> void:
	if _busy:
		return
	_sheet.forge.square_canvas = _rows[_choices.selected].kind != "links"
	var error := _sheet.cut()
	if error != "":
		_status.text = error
		return
	_skin.frames.clear()
	_cut_images = _sheet.images.duplicate()
	for image: Image in _sheet.images:
		_skin.frames.append(ImageTexture.create_from_image(image))
	_skin.placeholder = false
	_skin.tint = Color.WHITE
	_preview._age = 0
	_generated = true
	_skin.set_meta("sheet", _sheet.settings())
	_status.text = "切出 %d 帧，已预览；保存后绑定到当前技能" % _sheet.images.size()


func _cut_and_save() -> void:
	if _busy:
		return
	_cut()
	if _sheet.forge.error == "" and _generated:
		await _save()


func _import(paths: PackedStringArray) -> void:
	if _busy:
		return
	var error := _bindings.import_frames(_skin, paths)
	if error == "":
		_generated = false
		_skin.remove_meta("sheet")
	_status.text = error if error != "" else "已导入预览，点击保存生效"


func _clear() -> void:
	if _busy:
		return
	_skin.frames = []
	_skin.placeholder = false
	_generated = false
	_status.text = "已清除预览，点击保存生效"


func _save() -> void:
	if _busy:
		return
	_busy = true
	_set_editable(self, false)
	_choices.disabled = true
	var row: Dictionary = _rows[_choices.selected]
	var skin := _skin.duplicate() as PBFieldSkin
	var error := ""
	if _generated:
		var dir := "res://assets/fx/fields/%s/%s" % [row.kind, row.id]
		error = PBFxForge.write(_cut_images, dir, "frame")
		if error == "":
			await _rescan()
			var paths := PackedStringArray()
			for i: int in _cut_images.size():
				paths.append("%s/frame_%d.png" % [dir, i])
			error = _bindings.import_frames(skin, paths)
	if error == "":
		error = _bindings.save(row.kind, row.id, skin)
	if error == "":
		_skin = skin
		_preview.skin = skin
		_generated = false
		await _rescan()
	_status.text = error if error != "" else "已保存并绑定：data/field_art/%s/%s.tres" % [row.kind, row.id]
	_choices.disabled = false
	_busy = false
	_set_editable(self, true)
	_width.editable = row.kind == "links"


func _set_editable(node: Node, enabled: bool) -> void:
	if node is BaseButton:
		node.disabled = not enabled
	elif node is SpinBox or node is LineEdit:
		node.editable = enabled
	for child: Node in node.get_children():
		_set_editable(child, enabled)


func _rescan() -> void:
	var editor := Engine.get_singleton(&"EditorInterface")
	if editor == null:
		return
	var files = editor.get_resource_filesystem()
	files.scan()
	for _tick: int in 600:
		await get_tree().process_frame
		if not files.is_scanning():
			return
