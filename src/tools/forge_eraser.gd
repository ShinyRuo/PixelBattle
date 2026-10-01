@tool
class_name PBForgeEraser
extends VBoxContainer
## 「战场形象」面板里那块**橡皮**：当场改盘上那张 png（备份目录、撤销栈、逐帧的笔迹账）。
## 锚点只是往一本账里写一个 [Vector2i]，留在面板上；橡皮是自带副作用的子系统，所以单独一个类。
##
## **它不自己重量帧**：擦完必须重量 `used` 和 `feet_x`（画布宽度、脚底中线、缩放比都从它们派生），
## 但那本账在面板手上 —— 这里只发信号说「这几帧变了」。各量各的话面板上的包围盒和导出时量的迟早分叉。

## 擦了一笔，盘上这几帧变了。**橡皮还在手上**（撤销栈要接着用），
## 所以面板重量完刷新一下就行，别重读贴图。
signal touched(indexes: PackedInt32Array)

## 「还原这一帧」或者「套到整段」做完了。**橡皮已经放下**，
## 盘上的图换了内容，面板要从盘上重读这一帧。
signal reset(indexes: PackedInt32Array)

## 笔尖换了（形状或粗细）—— 预览那块要跟着换光标。
signal tool_changed

## 状态栏要说的话。**不自己持有那个标签**：状态栏是面板的东西，
## 两处都能往里写的话，「谁最后说的那句」会由调用顺序偷偷决定。
signal said(text: String)

const BRUSH_MIN: int = 2
const BRUSH_MAX: int = 64
const BRUSH_DEFAULT: int = 12

## `{段名: {帧号: Array[Dictionary]}}`。**笔迹是数据不是像素**（见 [PBFrameTouch]
## 类顶），所以「套到整段」只是把同一串重放 97 遍，和逐帧手擦出来的逐字节相同。
var _marks: Dictionary = {}

var _touch: PBFrameTouch = null
var _anim: String = ""
var _shots: Array = []
var _index: int = 0
var _texture: ImageTexture = null

var _nib_pick: OptionButton
var _brush: HSlider
var _brush_label: Label


func _ready() -> void:
	_nib_pick = OptionButton.new()
	_nib_pick.add_item("画笔（按住涂）")
	_nib_pick.add_item("框选（拉一个矩形）")
	_nib_pick.item_selected.connect(func(_i: int) -> void: _refresh_nib())
	add_child(_nib_pick)
	_brush_label = Label.new()
	add_child(_brush_label)
	_brush = HSlider.new()
	_brush.min_value = float(BRUSH_MIN)
	_brush.max_value = float(BRUSH_MAX)
	_brush.step = 1.0
	_brush.value = float(BRUSH_DEFAULT)
	_brush.value_changed.connect(func(_v: float) -> void: _refresh_nib())
	add_child(_brush)
	var row := HBoxContainer.new()
	row.add_child(_button("撤销一笔", _on_undo))
	row.add_child(_button("还原这一帧", _on_restore))
	add_child(row)
	add_child(_button("这几笔套到整段", _on_erase_all))
	_refresh_nib()


## 换帧 / 换段了。**橡皮跟着放下** —— 留着的话下一笔会落在上一帧那张图上，
## 而相邻两帧长得几乎一样，要等存完盘翻回去才看得出擦错了张。
func aim_at(anim: String, shots: Array, index: int, texture: ImageTexture) -> void:
	_anim = anim
	_shots = shots
	_index = index
	_texture = texture
	_touch = null


## 这一段的笔迹账。面板拿它判断「一笔都没擦过」。
func marks_of(anim: String) -> Dictionary:
	if not _marks.has(anim):
		_marks[anim] = {}
	return _marks[anim]


func nib() -> int:
	return maxi(_nib_pick.selected, 0) if _nib_pick != null else 0


func brush() -> int:
	return int(_brush.value) if _brush != null else BRUSH_DEFAULT


# ── 画布那三个信号 ──────────────────────────────────────────────


func on_dabbed(at: Vector2i) -> void:
	if not _ensure_touch():
		return
	_touch.dab(at, brush())
	_repaint()


func on_wiped(area: Rect2i) -> void:
	if not _ensure_touch():
		return
	_touch.wipe(area)
	_repaint()


## 松手：写回中间帧，然后让面板**重量这一帧**。
func on_stroke_ended() -> void:
	if _touch == null:
		return
	var err := _touch.save()
	if err != "":
		said.emit("[color=#e06666]%s[/color]" % err)
		return
	marks_of(_anim)[_index] = _touch.marks().duplicate()
	touched.emit(PackedInt32Array([_index]))


# ── 按钮 ────────────────────────────────────────────────────────


func _on_undo() -> void:
	if _touch == null:
		said.emit("这一帧这一次还没擦过。要退回抽帧那一刻按「还原这一帧」。")
		return
	_touch.undo()
	_repaint()
	on_stroke_ended()


## 退回**抽帧那一刻**。和「撤销」不是一回事：撤销只退这一次会话攒下的几笔，
## 而擦除是当场写盘的 —— 上一次开编辑器时擦掉的东西已经在盘上那张图里了。
func _on_restore() -> void:
	if not _ensure_touch():
		return
	var err := _touch.restore()
	if err != "":
		said.emit("[color=#e06666]%s[/color]" % err)
		return
	marks_of(_anim).erase(_index)
	_touch = null
	reset.emit(PackedInt32Array([_index]))
	said.emit("这一帧回到抽帧那会儿了。")


## 把这一帧的笔迹重放到本段每一帧上。
##
## **镜头不动，那条地面阴影在 97 帧里是同一个位置** —— 框一次就该管整段。
func _on_erase_all() -> void:
	var marks: Array = _touch.marks() if _touch != null else marks_of(_anim).get(_index, [])
	if marks.is_empty():
		said.emit("[color=#e06666]这一帧还没擦过 —— 先擦一笔，再套到整段。[/color]")
		return
	var table: Dictionary = marks_of(_anim)
	var done := PackedInt32Array()
	for i: int in _shots.size():
		var touch := PBFrameTouch.new()
		var err := touch.open(_shots[i]["path"], marks)
		if err == "":
			err = touch.save()
		if err != "":
			said.emit("[color=#e06666]%s[/color]" % err)
			return
		table[i] = marks.duplicate()
		done.append(i)
	_touch = null
	reset.emit(done)
	said.emit("[color=#71d08c]%d 笔套到 %s 段全部 %d 帧。[/color]" % [marks.size(), _anim, _shots.size()])


# ── 小工具 ──────────────────────────────────────────────────────


## 涂的过程中只换屏幕上那张贴图。**存盘和重量留到松手** ——
## 每一笔都存一张 png 再把这一帧重量一遍的话，拖着涂就跟不上手了。
func _repaint() -> void:
	if _touch == null or _texture == null:
		return
	_texture.update(_touch.image())
	tool_changed.emit()


## 让手上那块橡皮对准当前这一帧。**返回 false = 已经说过话了、别往下走。**
func _ensure_touch() -> bool:
	if _shots.is_empty():
		return false
	var path: String = _shots[_index]["path"]
	if _touch != null and _touch.path() == path:
		return true
	var touch := PBFrameTouch.new()
	var err := touch.open(path, marks_of(_anim).get(_index, []))
	if err != "":
		said.emit("[color=#e06666]%s[/color]" % err)
		return false
	_touch = touch
	return true


func _refresh_nib() -> void:
	_brush_label.text = "笔刷半径 %d（框选时用不上）" % brush()
	tool_changed.emit()


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button
