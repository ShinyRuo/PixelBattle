class_name PBBuffStrip
extends Control
## 选中那个忍者身上挂着的效果，一格一个图标。
##
## **在信息栏里，不在人物头顶**：当前几何下头顶只剩 4 像素
## （`FIELD_TOP 34 + SPRITE_HEADROOM 64 − 身高 60 = 38`，`38 − 34 = 4`）。要头顶图标得先压
## `field_height` 或撑大 B，两条都改配平。
##
## 和战场上的染色分工：染色（[method tinted]）答「**谁**身上有东西」，这一条答「**是什么、还剩多久**」。
## 几何在 [PBUnitInfo] 那边（[constant PBUnitInfo.STRIP_AT]）：血蓝条和右上角头像之间，四格 10 像素步距。
##
## **鼠标停在一格上弹出那一份的详情**（[method PBEffectWords.buff_body]）。图标暂时是纯色方块，
## 所以名字和效果只能靠这张卡说。

## 鼠标停在第几格上。参数顺序对齐 [method PBTooltip.show_hint]。
signal hint_requested(at: Rect2, title: String, body: String)

## 鼠标离开了那一格。
signal hint_closed

## 摆得下几个。第 [constant SLOTS] 格在超出时变成「还有几个」的记号。
const SLOTS: int = 4

## 一格画多大、格与格之间隔多远。**差 1 像素是有意的** ——
## 步距等于格宽的话四个方块糊成一条，数不出有几个。
const CELL: float = 9.0
const PITCH: float = 10.0

## 增益暖、减益冷。和 [PBAimLines] 的三色同一条道理：
## 两类东西长得一样的话，这一格就只剩「他身上有东西」这一句话，
## 而那句话染色已经说过了。
const GOOD_FILL := Color(0.92, 0.72, 0.35, 0.85)
const GOOD_EDGE := Color(1.0, 0.86, 0.55, 0.95)
const BAD_FILL := Color(0.42, 0.62, 0.92, 0.85)
const BAD_EDGE := Color(0.60, 0.80, 1.0, 0.95)

## 「还剩多久」那一条：格子底边上的一道 1 像素亮线，越短表示越快到期。
const CLOCK_H: float = 1.0
const CLOCK := Color(1.0, 1.0, 1.0, 0.9)

## 战场上那一层染得多重。**很轻** —— 敌人的颜色本来就在讲属性和血量
## （[method PBEnemyPool._color_of]），染狠了会把那两句话盖掉，
## 而属性是 §03 整套克制系统在屏幕上唯一的读数。
const FIELD_TINT: float = 0.35

## 超出 [constant SLOTS] 时最后一格的样子：一个空框加一条竖杠，
## **不写数字** —— 8 号字塞不进 9 像素见方，塞进去是一团糊。
const MORE_EDGE := Color(0.78, 0.80, 0.86, 0.9)

## 每一格：暖还是冷、还剩几成。两条平行数组，**每帧重填**，
## 所以不在这儿存 [PBBuffState] 的引用 —— 那份状态归 sim，这里只留画得出的量。
var _friendly: Array[bool] = []
var _left: PackedFloat32Array = PackedFloat32Array()

## 超出的那几个有没有。
var _overflow: bool = false

## 画着的那几格各是哪一份，下标同 [member _friendly]。**只给悬停卡用** —— 重不重画仍然只看上面那三个量，
## 拿引用比的话暂停中每帧都算「变了」。
var _states: Array[PBBuffState] = []
var _tick: int = 0
var _cfg: PBSimConfig = null

## 鼠标正停在第几格。-1 = 不在任何一格上。
var _hovered: int = -1


func _ready() -> void:
	# `PASS` 而不是 `STOP`：自己要收悬停，但不替底下的东西拦点击。
	mouse_filter = Control.MOUSE_FILTER_PASS
	size = Vector2(float(SLOTS) * PITCH, CELL)


## 把 [param bag] 这一 tick 的样子摆出来。**每渲染帧调一次。**
##
## [param cfg] 只用来把 [member PBBuff.duration_seconds] 换成 tick，
## 好算出「还剩几成」——[PBBuffState] 只记到期时刻，不记自己有多长。
func show_bag(bag: PBBuffBag, at_tick: int, cfg: PBSimConfig) -> void:
	var friendly: Array[bool] = []
	var left := PackedFloat32Array()
	var extra: bool = false
	_states = []
	_tick = at_tick
	_cfg = cfg
	for state: PBBuffState in bag.states():
		if not state.is_live(at_tick):
			continue
		if friendly.size() >= SLOTS - 1 and bag.count(at_tick) > SLOTS:
			# 满了还有剩：最后一格留给「还有」的记号，不再往里塞 ——
			# 塞进去的话玩家看到的是四个图标，而他身上其实有六个。
			extra = true
			break
		if friendly.size() >= SLOTS:
			break
		friendly.append(state.buff.friendly)
		left.append(_share(state, at_tick, cfg))
		_states.append(state)
	_apply(friendly, left, extra)


## 一格都不画。
func clear() -> void:
	_states = []
	_apply([], PackedFloat32Array(), false)
	_hover_at(Vector2(-1.0, -1.0))


## 鼠标在这一条上的 [param local] 处（本地坐标）。停在哪一格上就要那一格的卡，**格与格之间那 1 像素不算**。
func _hover_at(local: Vector2) -> void:
	var index: int = floori(local.x / PITCH)
	var inside: bool = (
		local.y >= 0.0
		and local.y <= CELL
		and index >= 0
		and index < _states.size()
		and local.x - float(index) * PITCH <= CELL
	)
	if not inside:
		if _hovered >= 0:
			_hovered = -1
			hint_closed.emit()
		return
	if index == _hovered or _cfg == null:
		return
	_hovered = index
	var state: PBBuffState = _states[index]
	var at := Rect2(global_position + Vector2(float(index) * PITCH, 0.0), Vector2(CELL, CELL))
	hint_requested.emit(
		at, PBEffectWords.buff_title(state.buff), PBEffectWords.buff_body(state, _tick, _cfg)
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_hover_at(click.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_at(Vector2(-1.0, -1.0))


## 现在画着几个图标（不含「还有」那一格）。测试拿它确认满了会收口。
func shown() -> int:
	return _friendly.size()


## 有没有画着「还有」那一格。
func has_overflow() -> bool:
	return _overflow


## 战场上那个单位该染成什么颜色。[param base] 是它本来的颜色，返回值直接给 `modulate`。
##
## **「暖 = 增益、冷 = 减益」只有这一处**，否则面板上那一格和战场上那个人会对同一份 buff 说两种颜色。
## **两样都有时按减益染**：减益没看见是要死人的。空袋子返回逐位相同的颜色（`modulate` 是乘上去的）。
static func tinted(base: Color, bag: PBBuffBag, at_tick: int) -> Color:
	var good: bool = false
	var bad: bool = false
	for state: PBBuffState in bag.states():
		if not state.is_live(at_tick):
			continue
		if state.buff.friendly:
			good = true
		else:
			bad = true
	if bad:
		return base.lerp(BAD_EDGE, FIELD_TINT)
	return base.lerp(GOOD_EDGE, FIELD_TINT) if good else base


## 这一份还剩几成（0..1）。算不出长度就当满的 —— 画一条空的时钟线
## 会让一个刚挂上的 buff 看起来马上就要没了。
static func _share(state: PBBuffState, at_tick: int, cfg: PBSimConfig) -> float:
	var whole: int = state.buff.duration_ticks(cfg)
	if whole <= 0:
		return 1.0
	return clampf(float(state.left(at_tick)) / float(whole), 0.0, 1.0)


## 变了才重画。**暂停时这道门是全部的意义**：画面一动不动，
## 三个量一个都没变，于是一帧都不用重绘（同 [method PBAimLines._apply]）。
func _apply(friendly: Array[bool], left: PackedFloat32Array, extra: bool) -> void:
	if _friendly == friendly and _left == left and _overflow == extra:
		return
	_friendly = friendly
	_left = left
	_overflow = extra
	queue_redraw()


func _draw() -> void:
	for i: int in _friendly.size():
		var at := Vector2(float(i) * PITCH, 0.0)
		var box := Rect2(at, Vector2(CELL, CELL))
		draw_rect(box, GOOD_FILL if _friendly[i] else BAD_FILL)
		draw_rect(box, GOOD_EDGE if _friendly[i] else BAD_EDGE, false, 1.0)
		# 时钟线画在格子里面的底边上，不在外面 —— 外面那一行属于下一格。
		var span: float = CELL * _left[i]
		if span > 0.0:
			draw_rect(Rect2(at + Vector2(0.0, CELL - CLOCK_H), Vector2(span, CLOCK_H)), CLOCK)
	if not _overflow:
		return
	var last := Vector2(float(SLOTS - 1) * PITCH, 0.0)
	draw_rect(Rect2(last, Vector2(CELL, CELL)), MORE_EDGE, false, 1.0)
	# 一竖一横：一个加号，说的是「还有」。
	draw_line(last + Vector2(CELL * 0.5, 2.0), last + Vector2(CELL * 0.5, CELL - 2.0), MORE_EDGE)
	draw_line(last + Vector2(2.0, CELL * 0.5), last + Vector2(CELL - 2.0, CELL * 0.5), MORE_EDGE)
