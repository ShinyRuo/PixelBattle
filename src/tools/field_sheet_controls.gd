@tool
class_name PBFieldSheetControls
extends VBoxContainer

signal cut_requested
signal source_changed

var forge := PBFieldSheetForge.new()
var source: Image
var images: Array[Image] = []
var _path: LineEdit
var _dialog: FileDialog
var _background: OptionButton
var _layout: OptionButton
var _columns: SpinBox
var _rows: SpinBox
var _count: SpinBox
var _size: SpinBox
var _gap: SpinBox
var _floor: SpinBox
var _center: CheckBox


func _ready() -> void:
	var line := HBoxContainer.new()
	add_child(line)
	_path = LineEdit.new()
	_path.placeholder_text = "aires 下的 AI 序列帧整图路径"
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.text_submitted.connect(use_sheet)
	line.add_child(_path)
	var browse := Button.new()
	browse.text = "选整图…"
	browse.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.7))
	line.add_child(browse)
	_background = OptionButton.new()
	for title: String in ["透明底（保留透明度）", "黑底发光", "洋红底", "白底/浅棋盘 · 灰黑烟雾"]:
		_background.add_item(title)
	add_child(_background)
	_layout = OptionButton.new()
	_layout.add_item("规则网格（从左到右、从上到下）")
	_layout.add_item("按空白带自动切分")
	add_child(_layout)
	var grid := HBoxContainer.new()
	add_child(grid)
	_columns = number(grid, "列", 1, 16, 3)
	_rows = number(grid, "行", 1, 16, 2)
	_count = number(grid, "帧", 1, 64, 6)
	var output := HBoxContainer.new()
	add_child(output)
	_size = number(output, "输出边长", 16, 1024, 256)
	_gap = number(output, "空白间距", 1, 128, 12)
	var smoke := HBoxContainer.new()
	add_child(smoke)
	_floor = number(smoke, "烟雾去底阈值", 0.5, 1, 0.93, 0.01)
	_floor.tooltip_text = "仅灰黑烟雾模式使用。降低可去除更深的棋盘格，也会削弱浅烟。"
	_center = CheckBox.new()
	_center.text = "各帧内容居中（保留整段统一比例）"
	_center.button_pressed = true
	add_child(_center)
	var cut := Button.new()
	cut.text = "切图并预览"
	cut.pressed.connect(func() -> void: cut_requested.emit())
	add_child(cut)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.current_dir = ProjectSettings.globalize_path("res://aires/skills")
	_dialog.filters = PackedStringArray(["*.png,*.webp,*.jpg,*.jpeg ; AI 序列帧整图"])
	_dialog.file_selected.connect(use_sheet)
	add_child(_dialog)


func use_sheet(path: String) -> void:
	_path.text = path
	source = Image.load_from_file(path)
	images.clear()
	forge.cells.clear()
	source_changed.emit()


func cut() -> String:
	# 直接粘贴路径后点按钮也能工作，不要求额外按回车。
	var path := _path.text.strip_edges().replace("\\", "/")
	if not path.is_absolute_path() and not path.begins_with("res://"):
		path = "res://" + path
	source = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	forge.columns = int(_columns.value)
	forge.rows = int(_rows.value)
	forge.count = int(_count.value)
	forge.output_size = int(_size.value)
	forge.gap = int(_gap.value)
	forge.smoke_floor = _floor.value
	forge.automatic = _layout.selected == 1
	forge.center_frames = _center.button_pressed
	forge.background = _background.selected as PBFieldSheetForge.Background
	images = forge.slice(source)
	source_changed.emit()
	return forge.error


func settings() -> Dictionary:
	return {
		"path": ProjectSettings.localize_path(_path.text.replace("\\", "/")),
		"columns": _columns.value,
		"rows": _rows.value,
		"count": _count.value,
		"size": _size.value,
		"gap": _gap.value,
		"floor": _floor.value,
		"background": _background.selected,
		"layout": _layout.selected,
		"center": _center.button_pressed
	}


func restore(saved: Dictionary) -> void:
	_path.text = str(saved.get("path", ""))
	source = null
	images.clear()
	forge.cells.clear()
	_columns.value = saved.get("columns", 3)
	_rows.value = saved.get("rows", 2)
	_count.value = saved.get("count", 6)
	_size.value = saved.get("size", 256)
	_gap.value = saved.get("gap", 12)
	_floor.value = saved.get("floor", 0.93)
	_background.select(int(saved.get("background", 0)))
	_layout.select(int(saved.get("layout", 0)))
	_center.button_pressed = saved.get("center", true)
	if FileAccess.file_exists(_path.text):
		source = Image.load_from_file(_path.text)
	source_changed.emit()


static func number(
	parent: Node, title: String, low: float, high: float, value: float, step: float = 1
) -> SpinBox:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	parent.add_child(spin)
	return spin
