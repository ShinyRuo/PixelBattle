@tool
class_name PBFxSegment
extends VBoxContainer
## 「战场特效」面板里的**一段**（飞行段 / 命中段）：选图、背景、帧数、尺寸、切图。
##
## 切图走 [PBFxForge]，和命令行 `scripts/make_fx.ps1` 是同一条流水线。切出来的帧同时留在 [member images] 里给预览用 ——
## 预览不读导入后的贴图，所以切完立刻就能看，不用等编辑器导入。

## 说一句话给面板的状态栏（带 BBCode 颜色）。
signal said(text: String)
## 点了「切图」。切到哪个目录由页面定（键在页面上）。
signal cut_requested
## [member images] 换了（切完或者从盘上读回来）。
signal changed

const MODES := ["黑底 · 发光（加法混合）", "洋红底 · 实体（普通混合）"]

## 段名（`fly` / `hit`），也是帧文件名的前缀。
var anim: StringName = &"fly"

## 这一段当前的帧（切完的或者从盘上读回来的）。
var images: Array[Image] = []

var _title: String = ""
var _default_size: int = 48
var _default_frames: int = 3
var _sheet_path: String = ""
var _path_label: Label
var _mode_pick: OptionButton
var _frames: SpinBox
var _size: SpinBox
var _dialog: FileDialog


func _init(
	segment: StringName = &"fly", title: String = "", size: int = 48, frame_count: int = 3
) -> void:
	anim = segment
	_title = title
	_default_size = size
	_default_frames = frame_count


func _ready() -> void:
	var head := Label.new()
	head.text = _title
	add_child(head)

	var pick := HBoxContainer.new()
	var browse := Button.new()
	browse.text = "选图…"
	browse.pressed.connect(_on_browse)
	pick.add_child(browse)
	_path_label = Label.new()
	_path_label.text = "（还没选）"
	_path_label.clip_text = true
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_child(_path_label)
	add_child(pick)

	_mode_pick = OptionButton.new()
	for text: String in MODES:
		_mode_pick.add_item(text)
	_mode_pick.tooltip_text = "出图时画在什么底上。发光的（火、雷、查克拉、火花）用黑底，实心的（苦无、手里剑）用洋红底"
	_mode_pick.item_selected.connect(func(_i: int) -> void: changed.emit())
	add_child(_mode_pick)

	var numbers := HBoxContainer.new()
	_frames = _spin(numbers, "帧数", 0, 12, _default_frames, "图上画了几帧。切出来的格数对不上就报错；0 = 不检查")
	_size = _spin(numbers, "长边", 16, 512, _default_size, "成品画布长边多少像素（屏幕尺寸 × 3）")
	add_child(numbers)

	var cut := Button.new()
	cut.text = "切图"
	cut.pressed.connect(func() -> void: cut_requested.emit())
	add_child(cut)


## 背景模式。
func mode() -> PBFxForge.Mode:
	return PBFxForge.Mode.KEY if _mode_pick.selected == 1 else PBFxForge.Mode.DARK


func use_mode(to: PBFxForge.Mode) -> void:
	_mode_pick.select(1 if to == PBFxForge.Mode.KEY else 0)
	changed.emit()


## 这一段该不该用加法混合：**黑底就是加法**（规格 §2.2），不另开一个开关让它和背景对不上。
func additive() -> bool:
	return mode() == PBFxForge.Mode.DARK


## 换一张图集（面板外面也能调，测试走这里）。
func use_sheet(path: String) -> void:
	_sheet_path = path
	if _path_label != null:
		_path_label.text = path.get_file()
		_path_label.tooltip_text = path


## 切图，写进 [param out_dir]。**返回错误信息，空串 = 成功。**
func cut(out_dir: String) -> String:
	if _sheet_path == "":
		return "%s：先选一张图。" % _title
	var sheet := Image.load_from_file(_sheet_path)
	if sheet == null or sheet.is_empty():
		return "%s：读不到图 %s" % [_title, _sheet_path]
	var want: int = int(_frames.value)
	var frames := PBFxForge.new().slice(
		sheet, mode(), PBFxForge.Anchor.CENTER, int(_size.value), want
	)
	if frames.is_empty():
		return "%s：一格都没切出来 —— 背景选对了吗？格与格之间留空了吗？" % _title
	if want > 0 and frames.size() != want:
		return "%s：切出 %d 格，要的是 %d 格 —— 多半是两帧的光晕连在了一起，重出时把间距拉大。" % [_title, frames.size(), want]
	var err := PBFxForge.write(frames, out_dir, String(anim))
	if err != "":
		return "%s：%s" % [_title, err]
	images = frames
	changed.emit()
	return ""


## 从盘上读回这一段已经切好的帧（`<anim>_<序号>.png`）。返回读到几帧。
##
## 走 [method Image.load_from_file]，不走导入 —— 刚切完、编辑器还没导入的时候也读得到。
func load_from(dir_path: String) -> int:
	images = []
	var i: int = 0
	while true:
		var path: String = "%s/%s_%d.png" % [dir_path, anim, i]
		if not FileAccess.file_exists(path):
			break
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty():
			break
		images.append(image)
		i += 1
	changed.emit()
	return images.size()


## 一句话说这一段现在是什么样。
func summary() -> String:
	if images.is_empty():
		return "%s：还没有帧" % _title
	return "%s：%d 帧，%d×%d" % [_title, images.size(), images[0].get_width(), images[0].get_height()]


func _on_browse() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图片"])
		_dialog.file_selected.connect(
			func(path: String) -> void:
				use_sheet(path)
				said.emit("%s 选好了图：%s。按「切图」。" % [_title, path.get_file()])
		)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _spin(
	row: HBoxContainer, label: String, low: int, high: int, value: int, tip: String
) -> SpinBox:
	var text := Label.new()
	text.text = label
	row.add_child(text)
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.value = value
	box.tooltip_text = tip
	row.add_child(box)
	return box
