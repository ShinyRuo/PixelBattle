@tool
class_name PBForgeCanvas
extends Control
## 「战场形象」面板右边那块预览（收鼠标：点锚点、涂橡皮、拉框）。
##
## **自己画，不用 [TextureRect]**：辅助线要和图用同一个变换，交给容器缩放的话两者差几个像素。
##
## 三层：**包围盒**（蓝，[method Image.get_used_rect]，有地面阴影的帧框会横贯整图）、
## **量出来的脚底十字**（黄，不调锚点时人会怎么坐进画布）、**调整之后的十字**（青，加上手动偏移）。
## 后两条**必须分色**：黄是测量，青是预测（[method PBActorForge._seat] 在成品上会重新量一次脚底，可能差一像素）。
##
## 信号发出去的一律是**中间帧像素**，屏幕坐标只在这个类里存在 —— 换算错了的表现是「点哪儿都偏一点」。

## 用户在图上点了一下：「真正的脚在这儿」。
signal anchor_aimed(at: Vector2i)

## 画笔涂过一下。
signal dabbed(at: Vector2i)

## 框选擦掉一块。
signal wiped(area: Rect2i)

## 一笔画完（松开左键）——面板拿它当「该写盘、该重量这一帧」的信号。
## 涂的过程中不发：每一笔都存盘 + 重量的话，拖着涂就跟不上手了。
signal stroke_ended

## 鼠标这一下是干什么的。**一个枚举不是两个 bool** —— 两个 bool 的
## 「都开着」是个说不清的状态，那一下点击算哪个会由分支顺序偷偷决定
## （[member PBFieldPicker.aim_mode] 就是这条）。
enum Tool {
	ANCHOR,  ## 点一下 = 把锚点挪到这儿
	ERASE,  ## 涂 / 框 = 擦掉
}

## 橡皮的笔尖。
enum Nib {
	BRUSH,  ## 圆画笔，贴着脚边的零碎用它
	RECT,  ## 拉框，横贯整图的地面阴影用它
}

## 刻度画到画布上限的几倍高。**固定，不跟着当前这一帧变** ——
## 超上限的帧要能看见它超出去多少，而不是被裁在框顶上。
const RULER_HEADROOM: float = 1.25

## 每隔多少**成品像素**一道细刻度。30 成品像素 = 10 个逻辑像素（高清档 3 倍）。
const TICK_STEP: int = 30

## 脚底那条线离控件底边留几像素。贴着底边的话鞋底和边框糊在一起。
const GROUND_PAD: float = 16.0

const BACK_COLOR := Color(0.09, 0.10, 0.13, 1.0)
const BOX_COLOR := Color(0.38, 0.62, 0.95, 0.85)
const FEET_COLOR := Color(0.98, 0.85, 0.45, 0.95)
const AIM_COLOR := Color(0.45, 0.90, 0.85, 0.95)
const NIB_COLOR := Color(0.98, 0.45, 0.45, 0.85)
const TICK_COLOR := Color(1.0, 1.0, 1.0, 0.07)
const GROUND_COLOR := Color(0.62, 0.66, 0.76, 0.70)
const STAND_COLOR := Color(0.42, 0.85, 0.55, 0.80)
const CEILING_COLOR := Color(0.95, 0.65, 0.35, 0.85)

## 站姿在成品像素里多高（那条绿线）、画布上限在哪（那条橙线）。
## **由面板交进来，不在这儿算** —— 两个数都跟 [member PBActorForge.scale_up]
## 有关，各算一份的话刻度和导出会对同一件事说两个数。
var _stand: int = 0
var _ceiling: int = 0

var _texture: Texture2D = null
var _fit := Vector2i.ZERO
var _shot: Dictionary = {}
var _nudge := Vector2i.ZERO
var _scale: float = 1.0
var _tool: int = Tool.ANCHOR
var _nib: int = Nib.BRUSH
var _brush: int = 12
var _cursor := Vector2i.ZERO
var _from := Vector2i.ZERO
var _dragging: bool = false


## 换一帧。[param scale] 是这一段的缩放比（中间帧 → 成品），
## 青线要拿它把成品像素的偏移换算回中间帧坐标。
func show_frame(texture: Texture2D, shot: Dictionary, nudge: Vector2i, scale: float) -> void:
	_texture = texture
	_shot = shot
	_nudge = nudge
	_scale = maxf(scale, 0.0001)
	queue_redraw()


func show_nothing() -> void:
	_texture = null
	_shot = {}
	queue_redraw()


## 这一段里最大的那一帧。只用来判断「这一段最宽的那一帧会不会横着出框」（高度由刻度定死，见 [method _mag]）。
## 按段不按帧：图集每一格尺寸不同，各自铺满的话屏幕上躺下的人最大，预览就成了一把会变的尺子。
func fit_to(box: Vector2i) -> void:
	_fit = box
	queue_redraw()


## 刻度上标哪两条线：站姿多高、画布上限在哪（都是**成品像素**）。
##
## 面板在建好这块预览之后交一次就够 —— 两个数只跟
## [member PBActorForge.scale_up] 有关，一局之内不会变。
func mark_at(stand: int, ceiling: int) -> void:
	_stand = maxi(stand, 0)
	_ceiling = maxi(ceiling, 0)
	queue_redraw()


func use_tool(tool_now: int, nib: int, brush: int) -> void:
	_tool = tool_now
	_nib = nib
	_brush = maxi(brush, 1)
	queue_redraw()


## 屏幕上这一点落在中间帧的哪个像素上。
func frame_at(local: Vector2) -> Vector2i:
	var view: float = _view_scale()
	var shown := _view_rect()
	return Vector2i(((local - shown.position) / view).floor())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACK_COLOR)
	_draw_ruler()
	if _texture == null or _shot.is_empty():
		return
	var shown := _view_rect()
	var view: float = _view_scale()
	draw_texture_rect(_texture, shown, false)
	var used: Rect2i = _shot["used"]
	draw_rect(
		Rect2(shown.position + Vector2(used.position) * view, Vector2(used.size) * view),
		BOX_COLOR,
		false,
		1.0
	)
	_draw_guides(shown, view)
	if _tool == Tool.ERASE:
		_draw_nib(shown, view)


## 背景上那把尺子。单位是**成品像素**，[method _view_scale] 保证它在一段里是常数，翻帧、换段都不变。
## 两条线：**站姿**（绿）和**画布上限**（橙）—— 人头越过橙线就是导出时会被切头。
## 画在贴图底下：尺子是背景，不该盖住人。
func _draw_ruler() -> void:
	if _ceiling <= 0:
		return
	var mag: float = _mag()
	var ground: float = _ground_y()
	var top: float = _ruler_top()
	var at: int = TICK_STEP
	while float(at) < top:
		if at != _stand and at != _ceiling:
			var y: float = ground - float(at) * mag
			draw_line(Vector2(0.0, y), Vector2(size.x, y), TICK_COLOR, 1.0)
		at += TICK_STEP
	_rule_line(ground, "地面 0", GROUND_COLOR)
	_rule_line(ground - float(_stand) * mag, "站姿 %d" % _stand, STAND_COLOR)
	_rule_line(ground - float(_ceiling) * mag, "上限 %d" % _ceiling, CEILING_COLOR)


func _rule_line(y: float, text: String, color: Color) -> void:
	draw_line(Vector2(0.0, y), Vector2(size.x, y), color, 1.0)
	var font := get_theme_default_font()
	if font == null:
		return
	draw_string(font, Vector2(4.0, y - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)


## 两个十字：量出来的（黄）和调整之后的（青）。见类顶那段。
func _draw_guides(shown: Rect2, view: float) -> void:
	var used: Rect2i = _shot["used"]
	var feet: float = float(_shot["feet_x"])
	var ground: float = float(used.end.y)
	_cross(shown, view, feet, ground, FEET_COLOR)
	if _nudge == Vector2i.ZERO:
		return
	# 偏移存的是**成品像素**（按一下方向键就是游戏里真的一格），
	# 画到中间帧上要除回缩放比。
	var back: float = 1.0 / _scale
	_cross(shown, view, feet - float(_nudge.x) * back, ground - float(_nudge.y) * back, AIM_COLOR)


func _cross(shown: Rect2, view: float, at_x: float, at_y: float, color: Color) -> void:
	var x: float = shown.position.x + at_x * view
	var y: float = shown.position.y + at_y * view
	draw_line(Vector2(x, shown.position.y), Vector2(x, shown.end.y), color, 1.0)
	draw_line(Vector2(shown.position.x, y), Vector2(shown.end.x, y), color, 1.0)


## 橡皮的形状跟着鼠标走。**没有它就没法判断这一笔会吃掉多少** ——
## 而擦到脚上是看不出来的：鞋底那几排本来就细。
func _draw_nib(shown: Rect2, view: float) -> void:
	if _nib == Nib.RECT:
		if not _dragging:
			return
		var box := Rect2i(_from, _cursor - _from).abs()
		draw_rect(
			Rect2(shown.position + Vector2(box.position) * view, Vector2(box.size) * view),
			NIB_COLOR,
			false,
			1.0
		)
		return
	var at := shown.position + Vector2(_cursor) * view
	draw_arc(at, float(_brush) * view, 0.0, TAU, 24, NIB_COLOR, 1.0)


func _gui_input(event: InputEvent) -> void:
	if _texture == null or _shot.is_empty():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_cursor = frame_at(motion.position)
		if _dragging:
			_drag_to(_cursor)
		queue_redraw()
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_cursor = frame_at(click.position)
	if click.pressed:
		_press()
	else:
		_release()
	queue_redraw()


func _press() -> void:
	_dragging = true
	_from = _cursor
	_drag_to(_cursor)


## 拖动中。**锚点档也跟着拖** —— 点一下定位之后还想挪一点点时，
## 松开再点是两下操作，而这两下之间那一格的差别正是要调的东西。
func _drag_to(at: Vector2i) -> void:
	match _tool:
		Tool.ANCHOR:
			anchor_aimed.emit(at)
		Tool.ERASE:
			if _nib == Nib.BRUSH:
				dabbed.emit(at)


func _release() -> void:
	if not _dragging:
		return
	_dragging = false
	if _tool != Tool.ERASE:
		return
	if _nib == Nib.RECT:
		var box := Rect2i(_from, _cursor - _from).abs()
		if box.size.x <= 0 or box.size.y <= 0:
			return
		wiped.emit(box)
	stroke_ended.emit()


## 整张图等比装进这块控件的哪一块。**横向居中，纵向把「脚底」坐到刻度的 0 上**
## （[method PBActorForge._seat] 把 `used.end.y` 坐到画布底边），尺子上读到的高度就是导出 PNG 里的高度。
func _view_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, size)
	if _texture == null:
		return full
	var view: float = _view_scale()
	var shown: Vector2 = Vector2(_texture.get_size()) * view
	var feet: float = shown.y
	if not _shot.is_empty():
		feet = float((_shot["used"] as Rect2i).end.y) * view
	return Rect2(Vector2((full.size.x - shown.x) * 0.5, _ground_y() - feet), shown)


## 中间帧像素 → 屏幕像素 = `成品尺度 × 固定放大率`，**不是「铺满这个框」**（铺满的话所有动作看起来一样大，
## 而游戏里差着一圈）。[member _scale] 是「中间帧 → 成品」（手动缩放滑块已经乘在里面），
## [method _mag] 是「成品 → 屏幕」，只跟尺子高度和这一段最宽那一帧有关，跟当前这一帧无关。
func _view_scale() -> float:
	if _texture == null:
		return 1.0
	return _mag() * _scale


## 成品像素 → 屏幕像素。**这一段里是个常数。**
##
## 正常情况下由尺子的高度定死（`框高 ÷ 刻度顶`），这样换段、翻帧、
## 换角色都是同一把尺子。**只有一种情况会缩小**：这一段最宽的那一帧
## 按这个放大率画出来会横着出框（带长武器的角色）——那时按宽度让步，
## 而尺子上的**数字照旧是对的**，只是每一格窄一点。
func _mag() -> float:
	var by_height: float = size.y / _ruler_top()
	var wide: float = maxf(_fit_box().x * _scale, 1.0)
	return minf(by_height, size.x / wide)


## 刻度画到多高（成品像素）。上限还没交进来时给一个够用的默认值，
## 免得除以零。
func _ruler_top() -> float:
	var top: float = float(_ceiling) * RULER_HEADROOM
	return top if top > 1.0 else 360.0


## 刻度的 0 在屏幕的哪一行 —— 也就是脚底那条线。
func _ground_y() -> float:
	return maxf(size.y - GROUND_PAD, 1.0)


## 缩放按哪个尺寸算。没交过 [method fit_to] 就退回当前这一帧自己（一段只有一帧时唯一的答案）。
func _fit_box() -> Vector2:
	if _fit.x > 0 and _fit.y > 0:
		return Vector2(_fit)
	if _texture == null:
		return Vector2.ONE
	return Vector2(_texture.get_size())
