@tool
class_name PBPixelatePanel
extends Control
## 编辑器底栏那块「降采样」面板：选一张图 → 六个档位并排出结果 → 挑中一个 → 存盘。
##
## **并排摊开是它存在的全部理由**：「降到多少像素高」光看数字选不出来，每个角色的临界点都不一样。
## 一行图像处理都不在这里，全在 [PBPixelate]（命令行 [PBPixelateCli] 调的是同一个类）。
## **预览用小图，存盘才放大**：小图配最近邻拉伸看起来一模一样。

## 预览卡片有多大（正方形）。
const CARD: float = 176.0

const SIDE_WIDTH: float = 240.0

var _forge := PBPixelate.new()

var _source: Image = null
var _prepared: Image = null
var _path: String = ""
var _chosen: int = -1

var _cards: Array[Button] = []
var _shots: Array[Image] = []
var _grid: GridContainer
var _status: RichTextLabel
var _file_label: Label
var _colors_spin: SpinBox
var _tol_spin: SpinBox
var _key_check: CheckBox
var _open_dialog: FileDialog
var _save_dialog: FileDialog


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 320.0)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.add_child(_build_side())
	row.add_child(_build_grid())
	_say("挑一张图。产出直接当视频模型的首帧图用。")


## 左边一栏，从上往下就是操作顺序。
func _build_side() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(SIDE_WIDTH, 0.0)
	box.add_theme_constant_override("separation", 6)

	box.add_child(_button("① 选图…", _on_pick))
	_file_label = Label.new()
	_file_label.text = "（还没选）"
	_file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_file_label)

	_colors_spin = SpinBox.new()
	_colors_spin.min_value = 0
	_colors_spin.max_value = 64
	_colors_spin.value = PBPixelate.DEFAULT_COLORS
	_colors_spin.tooltip_text = "调色板压到几种颜色，0 = 不压。比降分辨率更去「插画感」。"
	box.add_child(_titled("颜色数", _colors_spin))

	_tol_spin = SpinBox.new()
	_tol_spin.min_value = 0.0
	_tol_spin.max_value = 0.8
	_tol_spin.step = 0.01
	_tol_spin.value = PBPixelate.DEFAULT_TOL
	_tol_spin.tooltip_text = "抠洋红的容差。粉发的角色别往上调 —— 0.34 就开始啃头发。"
	box.add_child(_titled("抠背景容差", _tol_spin))

	_key_check = CheckBox.new()
	_key_check.text = "背景是洋红"
	_key_check.button_pressed = true
	_key_check.tooltip_text = "关掉之后不抠背景，直接按 RGB 缩（背景不是 #FF00FF 时用）。"
	box.add_child(_key_check)

	box.add_child(_button("② 出六档预览", _on_render))
	box.add_child(_button("③ 保存选中的这一档…", _on_save))

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(SIDE_WIDTH, 90.0)
	box.add_child(_status)
	return box


func _build_grid() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	return scroll


func _on_pick() -> void:
	if _open_dialog == null:
		_open_dialog = FileDialog.new()
		_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_open_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"])
		_open_dialog.size = Vector2i(760, 520)
		_open_dialog.file_selected.connect(_on_file_chosen)
		add_child(_open_dialog)
	_open_dialog.popup_centered()


func _on_file_chosen(path: String) -> void:
	_source = PBPixelate.read(path)
	if _source == null:
		_say("[color=#ff8080]读不出这张图：%s[/color]" % path)
		return
	_path = path
	_prepared = null
	_file_label.text = path.get_file()
	_say("%s　%d×%d。按②出预览。" % [path.get_file(), _source.get_width(), _source.get_height()])


## 六档一起出。抠色那一趟只跑一次，剩下的都是缩放。
func _on_render() -> void:
	if _source == null:
		_say("[color=#ffd080]先选一张图。[/color]")
		return
	_forge.colors = int(_colors_spin.value)
	_forge.tol = _tol_spin.value
	_forge.keyed = _key_check.button_pressed
	_prepared = _forge.prepare(_source)

	for child: Node in _grid.get_children():
		child.queue_free()
	_cards.clear()
	_shots.clear()
	_chosen = -1

	for level: int in PBPixelate.LEVELS:
		_forge.height = level
		var n := _forge.factor(_source.get_height())
		var small := _forge.shrink(_prepared, n)
		_shots.append(small)
		_grid.add_child(_build_card(small, level, n))
	_say("六档出好了。点一张选中，再按③保存。")


## 一张预览卡：图 + 「多高、几倍块」。
##
## 卡片本身是 [Button]（`toggle_mode`）而不是 [TextureRect] 加一层
## 输入处理 —— 选中态、悬停态、焦点态引擎已经画好了，自己描一圈边
## 只会和编辑器主题对不上。
func _build_card(small: Image, level: int, n: int) -> Control:
	var box := VBoxContainer.new()
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(CARD, CARD)
	card.icon = ImageTexture.create_from_image(small)
	card.expand_icon = true
	# 预览必须最近邻，否则看到的是被引擎糊过的图，而那不是产出的样子
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var index := _cards.size()
	card.pressed.connect(func() -> void: _on_choose(index))
	_cards.append(card)
	box.add_child(card)

	var label := Label.new()
	label.text = "%d 高 · %d 倍块 · %d×%d" % [level, n, small.get_width(), small.get_height()]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


func _on_choose(index: int) -> void:
	_chosen = index
	for i: int in _cards.size():
		_cards[i].button_pressed = i == index
	var small := _shots[index]
	_say(
		(
			"选中 %d 高（%d×%d）。按③保存。"
			% [PBPixelate.LEVELS[index], small.get_width(), small.get_height()]
		)
	)


func _on_save() -> void:
	if _chosen < 0:
		_say("[color=#ffd080]先点一张预览选中它。[/color]")
		return
	if _save_dialog == null:
		_save_dialog = FileDialog.new()
		_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_save_dialog.filters = PackedStringArray(["*.png ; PNG"])
		_save_dialog.size = Vector2i(760, 520)
		_save_dialog.file_selected.connect(_on_save_chosen)
		add_child(_save_dialog)
	_save_dialog.current_dir = _path.get_base_dir()
	var stem := _path.get_file().get_basename()
	_save_dialog.current_file = "%s_px%d.png" % [stem, PBPixelate.LEVELS[_chosen]]
	_save_dialog.popup_centered()


## 存的是**放大回去**的那一张：视频模型要的是正常分辨率的首帧图，
## 而喂它 93×93 会得到一段被它自己插值糊回去的视频。
func _on_save_chosen(path: String) -> void:
	var small := _shots[_chosen]
	_forge.height = PBPixelate.LEVELS[_chosen]
	var n := _forge.factor(_source.get_height())
	var err := _forge.enlarge(small, n).save_png(path)
	if err != OK:
		_say("[color=#ff8080]写不进去（%d）：%s[/color]" % [err, path])
		return
	_say("[color=#90e090]存好了：%s[/color]\n这张直接当视频模型的首帧图用。" % path.get_file())


func _say(text: String) -> void:
	_status.text = text


func _titled(title: String, node: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = title
	box.add_child(label)
	box.add_child(node)
	return box


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	return button
