class_name PBTooltip
extends Control
## 点开的说明卡。§02，M5-5。
##
## ## 为什么长句必须从面板里搬出来
##
## 新布局（[PBLayout]）把每一块都压窄了：忍具仓库 110 像素、装备栏 44、
## 指令卡的格子 58×29。字号 8 下一个汉字约 8 像素 ——
## **装备栏一格写得下五个字**，而「+20% 战力，需要 3 个配件，法术装挂不上物理角色」
## 是三十几个。
##
## 所以那些句子不是被删了，是搬到了这里：**格子上只留图标和数字，
## 点一下才展开整句**。这也是玩家画那张布局图时点名要的东西
## （「点击装备的时候用 tooltip 形式显示装备信息」）。
##
## ## 点开，不是悬停
##
## 悬停触发在这个尺寸下很难受：格子只有 20 像素见方，鼠标划过一排
## 会连着弹出五张卡。而且**手机没有悬停** —— §01 要求 PC + 手机双端，
## 一个只在 PC 上存在的信息通道等于在手机上把那段信息删了。
##
## ## 点哪儿都关得掉（M5-7）
##
## M5-5 到 M5-6 之间**没有任何地方调过 [method hide_card]** ——
## 弹出来的卡会一直盖在战场上，玩家只能重开一局。那是个纯 bug，
## 但它暴露的是一个设计缺口：**一张不会自己消失的说明卡没有出口。**
##
## 补法是一块盖满全屏、吃掉一次点击的 [member _catch]。
## 那一下点击**不会同时落到底下的东西上** —— 那是所有弹出层的标准行为，
## 也正是玩家的预期：他先关掉挡路的东西，再点他要点的。
## 「顺手穿透过去」听起来更方便，实际是每次都误触一个按钮。
##
## `Esc` 是第二条路，排在收模态之前（见 [method PBBattleView._unhandled_input]）——
## 手上有东西盖着的时候，那一下的意思一定是「先把它收掉」。
##
## ## 它自己不知道任何游戏规则
##
## 调用方给标题和正文，这一层只管排版和「别超出屏幕」。
## 让它去查装备表的话，指令卡、羁绊、任务卡将来各要一条查表路径，
## 而那几条迟早在措辞上分叉。

## 卡片的宽度。**固定宽度、自动换行**：宽度跟着内容变的话，
## 同一排格子点过去每张卡都是不同的形状，眼睛要重新找一遍标题在哪。
const CARD_WIDTH: float = 160.0

## 离屏幕边缘至少留这么多，免得卡片贴边看不清。
const MARGIN: float = 4.0

var _panel: Panel
var _title: Label
var _body: RichTextLabel

## 盖满全屏、吃掉一次点击的那一层。**它就是「关掉」这个操作**，见类顶部。
var _catch: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# 加在最前面：卡片和文字要画在它上面，而它只负责收鼠标。
	# 藏起来的控件收不到事件，所以卡片没摊开时它一点都不挡路。
	_catch = Control.new()
	_catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catch.mouse_filter = Control.MOUSE_FILTER_STOP
	_catch.gui_input.connect(_on_catch)
	add_child(_catch)
	_panel = PBSkin.panel(self, Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, 40.0)), PBSkin.PANEL_SOLID)
	_title = PBSkin.label(self, Vector2.ZERO, CARD_WIDTH - 10.0, PBSkin.FONT_TITLE, PBSkin.TITLE)
	_body = PBSkin.rich(self, Rect2(Vector2.ZERO, Vector2(CARD_WIDTH - 10.0, 60.0)))
	_body.fit_content = true


## 在 [param anchor]（屏幕矩形）旁边摊开一张说明卡。
##
## **优先摆在它上面**：这几块面板都在屏幕底栏，往下摆会直接出界，
## 而往上摆盖住的是战场 —— 准备阶段那儿本来就在等玩家决定。
func show_card(anchor: Rect2, title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_catch.visible = true
	visible = true
	# RichTextLabel 的 `fit_content` 要等它自己排版完才知道高度，
	# 所以先摆好宽度、等一帧、再定位。少了这一步第一次点开会摆错地方。
	await get_tree().process_frame
	if not visible:
		return
	var height: float = _title.size.y + _body.get_content_height() + 8.0
	var at := Vector2(
		clampf(anchor.position.x, MARGIN, get_viewport_rect().size.x - CARD_WIDTH - MARGIN),
		maxf(anchor.position.y - height - 2.0, MARGIN)
	)
	_panel.position = at
	_panel.size = Vector2(CARD_WIDTH, height)
	_title.position = at + Vector2(5.0, 2.0)
	_body.position = at + Vector2(5.0, _title.size.y + 2.0)
	_body.size.x = CARD_WIDTH - 10.0


## 悬停版：**同一张卡，但不吃点击**（M6-j）。
##
## 类顶部那段「点开，不是悬停」讲的是**格子** —— 20 像素见方的东西
## 划过去会连弹五张卡，而手机上压根没有悬停。**一行字不是格子**：
## 它有名字、有宽度、划过去只可能命中一行，而玩家要的正是
## 「我想知道这组羁绊都有谁」这种一瞥即走的问题。
##
## 不吃点击是这一档唯一的区别：悬停卡摊着的时候，底下那些面板
## 必须照样点得到 —— 鼠标从字上移开它就没了，而那一下点击已经发出去了。
func show_hint(anchor: Rect2, title: String, body: String) -> void:
	show_card(anchor, title, body)
	_catch.visible = false


## 摊着没有。`Esc` 那条链靠它决定这一下该收谁。
func is_open() -> bool:
	return visible


## 收起来。**任何一次点击都会先收它** —— 一张不会自己消失的说明卡
## 会一直盖着底下的东西，而玩家以为界面卡住了。
func hide_card() -> void:
	visible = false


## 点在卡片外面（其实卡片上也算）—— 收掉，并且**吃掉这一下**。
##
## `accept_event()` 不能省：不吃的话这次点击会继续传到
## [method PBBattleView._unhandled_input]，于是「关掉说明卡」
## 顺带在战场上选中了一个人，而玩家只按了一下。
func _on_catch(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	hide_card()
	accept_event()
