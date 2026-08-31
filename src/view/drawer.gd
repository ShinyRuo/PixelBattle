class_name PBDrawer
extends Control
## 从战场那条道上弹出来的抽屉面板的公共底座。§02 的战场直接操作，M3.5-f。
##
## ## 为什么四块弹窗共用一个底座
##
## 抽屉有四种（仓库、装备栏、抽卡三选一、选尾兽），而它们的**框**是同一件事：
## 一块面板底、一行标题、一个关闭按钮、底下一行提示。各写一遍的话，
## 四个标题的字号和四个关闭按钮的位置会各差两像素 —— 单独看每一个都对，
## 连着开四次就像四个不同的软件。
##
## ## 为什么敢盖住战场
##
## [constant BAND] 正压在战场那条道上（134–248）。**准备阶段战场是空的** ——
## 敌人要等 [method PBBattleView._finish_prepare] 才生成，而抽屉只在准备阶段开。
## 所以「不能影响玩家观察战场」这条要求在这里是自动满足的：
## 开着抽屉的时候没有战场可看，而开打之后抽屉全部关掉。
##
## 反过来，把抽屉挤到别处（比如再往下叠一层）就要跟信息栏和指令卡抢那 108px，
## 而那两块是**战斗中也要看的**。
##
## ## 一次只开一块
##
## 谁开谁关由 [PBBattleView] 统一裁决，本类只管自己显不显示。
## 各抽屉自己抢显示权的话，「点了忍者弹装备栏、但仓库还开着」这种叠着两块
## 的局面迟早出现，而它不报错，只是下面那块永远点不到。

## 玩家把这块抽屉关掉了。
signal closed

## 抽屉占的那块地方：战场那条道 + 羁绊带 + 预告行。
##
## **左边那 40px 让给 [PBFieldSlots] 的按钮列**（尾兽 / 大本营 / 仓库）。
## 盖住它的话，「仓库」那个按钮会藏在自己开出来的抽屉底下 ——
## 开得起来，关不掉。那一列因此是全程可点的一条常驻工具栏。
const BAND := Rect2(44.0, 134.0, 592.0, 114.0)

## 标题行与底部提示行各占多高，中间剩下的都是内容区。
const TITLE_H: float = 14.0
const HINT_H: float = 12.0

var _title: Label
var _hint: RichTextLabel
var _body: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	PBSkin.panel(self, BAND, PBSkin.PANEL_SOLID)
	_title = PBSkin.label(
		self, BAND.position + Vector2(8.0, 2.0), BAND.size.x - 70.0, PBSkin.FONT_TITLE, PBSkin.TITLE
	)
	# 提示行走 [RichTextLabel] 而不是 [Label]：图例要在文字里嵌小色块
	# （仓库那三档身份色），而那只有 BBCode 表达得了。
	_hint = PBSkin.rich(
		self,
		Rect2(
			BAND.position + Vector2(8.0, BAND.size.y - HINT_H - 1.0),
			Vector2(BAND.size.x - 16.0, HINT_H + 2.0)
		)
	)
	_hint.add_theme_color_override("default_color", PBSkin.DIM)

	var shut := Button.new()
	shut.position = BAND.position + Vector2(BAND.size.x - 56.0, 1.0)
	shut.size = Vector2(50.0, 13.0)
	shut.text = "关闭 Esc"
	PBSkin.style_button(shut, PBSkin.Tone.QUIET)
	shut.pressed.connect(close)
	add_child(shut)

	# 内容区自己是个不吃鼠标的容器，子控件照常收事件 ——
	# 子类因此可以用一套从 (0,0) 起算的局部坐标摆东西。
	_body = Control.new()
	_body.position = BAND.position + Vector2(0.0, TITLE_H)
	_body.size = Vector2(BAND.size.x, BAND.size.y - TITLE_H - HINT_H)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_build_body()


## 子类在这里摆自己的控件，父类已经把框和内容区准备好了。
##
## **按上限一次建满，之后只改内容**（§14）—— 和敌人池、指令卡同一条规矩。
func _build_body() -> void:
	pass


func open() -> void:
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## 内容区。子类摆控件时 add 到这上面，坐标从它的左上角起算。
func body() -> Control:
	return _body


func set_title(text: String) -> void:
	_title.text = text


## 底下那行小字。**每块抽屉都要写点什么** —— 一块只有按钮没有说明的面板，
## 玩家点第一下之前不知道会发生什么，而这些操作有的是不可逆的（三选一）。
func set_hint(text: String) -> void:
	_hint.text = text
