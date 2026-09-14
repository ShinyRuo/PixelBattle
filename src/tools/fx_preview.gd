@tool
class_name PBFxPreview
extends ColorRect
## 「战场特效」面板右边的预览：暗底上循环播两段（飞行 / 命中），**按游戏里的混合方式叠**。
##
## 画的是切出来的 [Image]，不是导入后的贴图 —— 切完立刻能看。每一段按 1:1 像素画，
## 那正是 1080p 下它在屏幕上的大小（贴图是逻辑尺寸的 3 倍，1080p 是逻辑画面的 3 倍）。
##
## 命中段也循环播：游戏里它只播一遍，但预览里播一遍就停住的话，人得反复点才看得清。

## 底色。战场的地面偏暗，在纯黑上看加法混合的发光类会显得比游戏里亮。
const GROUND := Color(0.16, 0.18, 0.2)

## 预览放大几倍。1:1 太小（普攻子弹 48 像素），2 倍才看得清边缘有没有脏。
const ZOOM: float = 2.0

var _views: Array[TextureRect] = []
var _textures: Array = [[], []]
var _fps: PackedFloat32Array = PackedFloat32Array([12.0, 20.0])
var _clock: float = 0.0
var _glow := CanvasItemMaterial.new()


func _ready() -> void:
	color = GROUND
	_glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	add_child(row)
	for _i: int in 2:
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(view)
		_views.append(view)


## 换一段的内容。[param which] 0 = 飞行段，1 = 命中段。
func show_segment(which: int, images: Array[Image], fps: float, additive: bool) -> void:
	var textures: Array[ImageTexture] = []
	for image: Image in images:
		textures.append(ImageTexture.create_from_image(image))
	_textures[which] = textures
	_fps[which] = maxf(fps, 1.0)
	var view: TextureRect = _views[which]
	view.material = _glow if additive else null
	var box := Vector2.ZERO
	for image: Image in images:
		box = box.max(Vector2(image.get_size()))
	view.custom_minimum_size = box * ZOOM
	_tick()


## 这一段在播几帧。测试拿它确认「切完就换上了」。
func frame_count(which: int) -> int:
	return (_textures[which] as Array).size()


## 这一段是不是按加法混合在画。
func is_additive(which: int) -> bool:
	return _views[which].material != null


## 底栏收起来时不播 —— 这是个 `@tool` 节点，编辑器开着它就一直在跑。
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	_tick()


func _tick() -> void:
	for which: int in _views.size():
		var textures: Array = _textures[which]
		if textures.is_empty():
			_views[which].texture = null
			continue
		var at: int = int(_clock * _fps[which]) % textures.size()
		_views[which].texture = textures[at]
