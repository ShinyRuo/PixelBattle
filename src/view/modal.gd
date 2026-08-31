class_name PBModal
extends Control
## 盖在整个画面上的一层弹窗的公共底座。§02，M5-6。
##
## ## 它取代了抽屉（[code]PBDrawer[/code]）
##
## 抽屉从战场那条道上滑出来，四块共用一条带。**那个形态不是设计选择，
## 是当初没地方摆** —— 屏幕上唯一足够大的空地就是准备阶段空着的战场。
## M5-3 到 M5-5 把仓库、忍具、装备栏各自搬进底栏的常驻面板之后，
## 只剩下三选一和选尾兽两块，而这两块的共同点恰恰不是「大」：
##
## **它们都是「不选就不能继续」。** 三选一的钱在摆牌那一刻就扣了
## （[method PBShopRules.open_offer]），不挑一张就开打会把那笔钱一起冲掉；
## 选尾兽是整局唯一一次、不可撤销的决定。而「在你回答之前，别的都点不了」
## 正是模态的定义 —— 抽屉表达不了它，抽屉开着的时候底下那些按钮照样能点。
##
## ## 遮罩不是装饰
##
## [member _scrim] 是一块盖满全屏、吃掉鼠标的矩形。少了它，玩家能在
## 三选一摊着的时候去点仓库、去拖人上场，而那些操作在这一刻全都
## **做得成但没意义** —— 他还欠着一个回答。压暗一层同时把注意力
## 收回到弹层上，那是模态唯一的视觉语言。
##
## ## 尺寸由子类给，位置由 [PBLayout] 算
##
## 子类只回答「内容区要多高」（[method _body_height]），
## 横向居中和纵向摆在哪由 [method PBLayout.modal_rect] 一处决定。
## 各自写死坐标的话，两块弹层会差几个像素 —— 单看每一块都对，
## 连着开两次就像两个不同的软件。**而且没有一条测试抓得到**：
## 排版错误只表现在画面上（见 [PBLayout] 顶部那段）。

## 玩家把这一层关掉了。
signal closed

## 标题行与底部提示行各占多高，中间剩下的都是内容区。
const TITLE_H: float = 14.0
const HINT_H: float = 12.0

## 遮罩压暗多少。**不能全黑** —— 底下那一屏是玩家刚才在看的东西，
## 关掉之后他要立刻接着看，完全遮死等于每次开关都要重新找一遍。
const SCRIM := Color(0.02, 0.03, 0.05, 0.72)

var _title: Label
var _hint: RichTextLabel
var _body: Control
var _scrim: ColorRect
var _rect: Rect2


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# **STOP 而不是 IGNORE**：这一层要吃掉落在弹层外面的每一次点击，
	# 那就是「模态」这个词的全部内容。藏起来的控件收不到事件，
	# 所以关着的时候它一点都不挡路。
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_scrim = ColorRect.new()
	_scrim.size = PBLayout.SCREEN
	_scrim.color = SCRIM
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	_rect = PBLayout.modal_rect(TITLE_H + _body_height() + HINT_H)
	PBSkin.panel(self, _rect, PBSkin.PANEL_SOLID)
	_title = PBSkin.label(
		self,
		_rect.position + Vector2(8.0, 2.0),
		_rect.size.x - 70.0,
		PBSkin.FONT_TITLE,
		PBSkin.TITLE
	)
	# 提示行走 [RichTextLabel] 而不是 [Label]：说明里要嵌色块和粗体，
	# 而那只有 BBCode 表达得了。
	_hint = PBSkin.rich(
		self,
		Rect2(
			_rect.position + Vector2(8.0, _rect.size.y - HINT_H - 1.0),
			Vector2(_rect.size.x - 16.0, HINT_H + 2.0)
		)
	)
	_hint.add_theme_color_override("default_color", PBSkin.DIM)

	# 关闭按钮**不是每块都有**：三选一没有退路（钱已经扣了），
	# 给一个关不掉任何东西的按钮比不给更糟。
	if _closable():
		var shut := Button.new()
		shut.position = _rect.position + Vector2(_rect.size.x - 56.0, 1.0)
		shut.size = Vector2(50.0, 13.0)
		shut.text = "关闭 Esc"
		shut.focus_mode = Control.FOCUS_NONE
		PBSkin.style_button(shut, PBSkin.Tone.QUIET)
		shut.pressed.connect(close)
		add_child(shut)

	# 内容区自己是个不吃鼠标的容器，子控件照常收事件 ——
	# 子类因此可以用一套从 (0,0) 起算的局部坐标摆东西。
	_body = Control.new()
	_body.position = _rect.position + Vector2(0.0, TITLE_H)
	_body.size = Vector2(_rect.size.x, _body_height())
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_build_body()


## 子类覆盖：内容区要多高。标题行和提示行由本类加在两头。
func _body_height() -> float:
	return 90.0


## 子类覆盖：这一层给不给关闭按钮 / 认不认 `Esc`。
func _closable() -> bool:
	return true


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


## 弹层那块面板在屏幕上的位置。子类要摆超出内容区的东西时问它。
func panel_rect() -> Rect2:
	return _rect


func set_title(text: String) -> void:
	_title.text = text


## 底下那行小字。**每一层都要写点什么** —— 一块只有按钮没有说明的面板，
## 玩家点第一下之前不知道会发生什么，而这两层的操作都是不可逆的。
func set_hint(text: String) -> void:
	_hint.text = text
