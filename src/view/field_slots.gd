class_name PBFieldSlots
extends Control
## C / D 区：左边那两个可点的形象（**尾兽、大本营**）。
## M3.5-e；M4-f 换掉过一排；M5-3 把仓库那一排交给了 [PBRosterBay]；
## M5-6 把出任务那一排交给了 [PBQuestCard]。
##
## ## 为什么这两样在一个类里
##
## 它们是同一件事的两种形态：**一个能被选中、然后在指令卡上出现指令的槽位**。
## 分成两个类的话，「点了 C 要不要取消 D 的选中」这条规则会散在两处，
## 而那种不一致的表现是「同时亮着两个选中框」——看得见，但改起来要翻几个文件。
##
## ## 三排头像先后都搬走了，这是好事
##
## 这个类原来还管着两排忍者头像：仓库那一排（M5-3 交给 [PBRosterBay]）、
## 出任务那一排（M5-6 交给 [PBQuestCard]）。搬走的理由是同一条 ——
## **一个忍者只在一处出现**，而「他在哪一块面板上」本身就是他的身份。
## 头像挂在一个叫「战场槽位」的类上时，那个身份得靠底色和标签额外说一遍。
##
## 剩下的两个不是忍者，所以留在这儿：尾兽和大本营各自只有一个，
## 谁都不会搬到别的面板上去。

## 玩家点了某个槽位。
signal slot_picked(kind: PBSelection.Kind, unit_id: StringName)

## **坐标住在 [PBLayout] 里**，这里只取短名字 —— 见那个文件顶上的排版图。
const COLUMN_X: float = PBLayout.C_BEAST.position.x
const BEAST_Y: float = PBLayout.C_BEAST.position.y
const BASE_Y: float = PBLayout.D_BASE.position.y

const SLOT_SIZE := PBLayout.C_BEAST.size

var _beast: Button
var _base: Button
var _mark: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 选中框画在两个按钮底下，靠 move_child 提到对应位置 —— 和 [PBRosterBay]
	# 同一套：一个比槽位大三像素的实心块，槽位盖在上面，效果是一圈描边。
	_mark = ColorRect.new()
	_mark.color = PBSkin.TITLE
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	add_child(_mark)

	_beast = _add_button(Vector2(COLUMN_X, BEAST_Y), PBSelection.Kind.BEAST)
	_base = _add_button(Vector2(COLUMN_X, BASE_Y), PBSelection.Kind.BASE)


## 按当前状态重画。
func refresh(selection: PBSelection, state: PBRunState) -> void:
	_beast.text = "尾兽\n%s" % ("Lv%d" % state.beast_level if state.beast_id != &"" else "空")
	_base.text = "大本营\n%d" % int(state.base_hp)

	# **每次重画都从头摆一遍。** 增量维护的话，一个槽位藏起来时那个框会
	# 留在原地，看起来像选中了空气。
	_mark.visible = true
	match selection.kind:
		PBSelection.Kind.BEAST:
			_show_mark(_beast)
		PBSelection.Kind.BASE:
			_show_mark(_base)
		_:
			_mark.visible = false


func _show_mark(on: Button) -> void:
	_mark.position = on.position - Vector2(3.0, 3.0)
	_mark.size = on.size + Vector2(6.0, 6.0)
	move_child(_mark, 0)


## 左边那一列的一个按钮。**`custom_minimum_size` 和 `size` 都要给** ——
## 只给 `size` 的话，按钮会被自己的最小尺寸挤成一条窄缝，
## 里面的两个字被逐字折行成竖排，看着像字体坏了。
func _add_button(at: Vector2, kind: PBSelection.Kind) -> Button:
	var button := Button.new()
	button.position = at
	button.custom_minimum_size = SLOT_SIZE
	button.size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(button)
	button.pressed.connect(func() -> void: slot_picked.emit(kind, &""))
	add_child(button)
	return button
