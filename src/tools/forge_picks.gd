@tool
class_name PBForgePicks
extends VBoxContainer
## 「战场形象」面板里那块**挑帧名单**。M9-l 从 [PBActorForgePanel] 拆出来 ——
## 那个文件又顶到了 gdlint 的 1000 行上限，而那条上限「超了不是错，
## 是该拆了的信号」（同 M8-g 拆 [PBForgeEraser]）。
##
## ## 这一刀切在哪
##
## 面板上剩下的每一块都在**推进状态**：翻到第几帧、这一帧的偏移是多少、
## 缩放比是多少、导出往盘上写了什么。而这一块从头到尾只做一件事 ——
## 维护「这一段用哪几帧、按什么顺序」那张表，**一个别人的字段都不碰**。
##
## ## 它不知道帧长什么样
##
## 名单里存的是**下标**，不是路径也不是贴图。所以这个类不读盘、不量帧，
## 也不认识 [PBActorForge] 那条流水线 —— 翻帧、预览、导出全在面板那边。
## 它要的只有三样：现在是哪一段、停在第几帧、这一段一共几帧
## （[method aim_at]，和 [method PBForgeEraser.aim_at] 同形）。

## 名单变了，面板要重画「✓已选」那个记号。
##
## **不自己去改那行字**：那行字是面板的（[method PBActorForgePanel._show]），
## 两处都能往里写的话，「谁最后说的那句」会由调用顺序偷偷决定。
signal changed

## 列表里点了一行 —— 面板把画面翻到那一帧去。
signal show_frame(index: int)

## 状态栏要说的话。理由同 [signal PBForgeEraser.said]。
signal said(text: String)

## `{段名: Array[int]}`，**切段不丢**，四段各挑各的。
##
## 里面存的是**下标的序列**，所以它是 [Array] 不是集合：
## 顺序就是播放顺序，而且同一帧可以出现两次（[method _on_copy]）。
var _picks: Dictionary = {}

var _anim: String = ""
var _shots: Array = []
var _index: int = 0

var _list: ItemList


func _ready() -> void:
	for anim: String in PBActorForge.anim_names():
		_picks[anim] = [] as Array[int]
	var marks := HBoxContainer.new()
	marks.add_child(_button("＋ 要这一帧", _on_take))
	marks.add_child(_button("全部选择", _on_all))
	add_child(marks)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0.0, 76.0)
	_list.item_selected.connect(_on_row)
	add_child(_list)
	var edits := HBoxContainer.new()
	edits.add_child(_button("↑", func() -> void: _move(-1)))
	edits.add_child(_button("↓", func() -> void: _move(1)))
	edits.add_child(_button("复制", _on_copy))
	edits.add_child(_button("移除", _on_drop))
	edits.add_child(_button("清空", func() -> void: _set_to([] as Array[int])))
	add_child(edits)


## 面板现在停在哪一段的哪一帧。
##
## **它不重画列表**，而翻帧每一下都会调它 —— 重画会清掉列表里那个选中项，
## 于是「点一行 → 按移除」这条路在第一步就把自己毁了（点一行就是翻帧）。
func aim_at(anim: String, shots: Array, index: int) -> void:
	_anim = anim
	_shots = shots
	_index = index


## 重画列表。**换段、重新载入帧之后要调**：那两下名单本身没变，
## 但它属于另一段、或者属于另一批帧了。
func refresh() -> void:
	_list.clear()
	var picked := picks_of(_anim)
	for slot: int in picked.size():
		_list.add_item("第 %d 帧 → %s_%d" % [picked[slot], _anim, slot])


func picks_of(anim: String) -> Array[int]:
	return _picks.get(anim, [] as Array[int])


## 写一段的名单。
##
## **只有写到当前这一段才重画、才发信号** —— ① 一次写四段
## （[method PBActorForgePanel._on_export_all]），另外三段的列表这会儿
## 根本不在屏幕上，重画它们只会把当前这一段的选中项清掉。
func set_picks(anim: String, picked: Array[int]) -> void:
	_picks[anim] = picked
	if anim != _anim:
		return
	refresh()
	changed.emit()


## 当前这一段的名单里有第 [param index] 帧吗（面板拿它画「✓已选」）。
func holds(index: int) -> bool:
	return picks_of(_anim).has(index)


## 要这一帧。**再按一次就是取消** —— 一个按钮两个方向，
## 省掉「我到底选没选中」这个要去列表里数的问题。
func _on_take() -> void:
	if _shots.is_empty():
		return
	var picked := picks_of(_anim)
	if picked.has(_index):
		picked.erase(_index)
	else:
		picked.append(_index)
	_set_to(picked)


## 把切出来的每一格**按顺序**填进名单（M9-l，玩家定的）。
##
## ## 它替掉的是「自动挑」
##
## 那个按钮走 [method PBActorForge.select]，而那套算法是按「从几十上百帧的
## 视频里挑 6 帧」写的 —— 图集那条路进来的就已经是 6 格，全在它掐掉的
## 范围里。整件事的来龙去脉和实测数字在 [method PBActorForge.frames_for]。
##
## ## 顺序就是这一步的全部内容
##
## 图集那 6 格本来就是美术按顺序画好的一段动画，所以这里**不排序、不去重、
## 不挑**，`0..n-1` 原样填进去。帧序错了不报错：跑动那一段一瘸一拐、
## 攻击那一段「先掉血后挥手」（出手落在
## [member PBSimConfig.attack_hit_frame]，那一格是数出来的）。
func _on_all() -> void:
	if _shots.is_empty():
		return
	var picked: Array[int] = []
	picked.assign(range(_shots.size()))
	_set_to(picked)
	var want: int = PBForgeSource.cells_wanted()
	if picked.size() == want:
		said.emit("[color=#71d08c]%s 段 %d 帧全选上了[/color]，顺序就是切出来的顺序。" % [_anim, want])
		return
	said.emit(
		"[color=#e0a666]全选了 %d 帧，而一段要 %d 帧[/color]。多了用「移除」删，少了用「复制」补。"
		% [picked.size(), want]
	)


## 把选中的那一帧在名单里**再放一份**，插在它后面。M9-e。
##
## ## 为什么「＋ 要这一帧」做不到
##
## 那个按钮是**开关**（在名单里就拿掉、不在就加上），所以同一帧按两次
## 等于没按。而 [member PBSimConfig.anim_frames] 要求每一段 6 帧 ——
## 源片里凑不够 6 个像样姿势的时候，就得**把某一帧停久一点**。
##
## ## 和载入时那次补有什么不同
##
## [method PBActorSkin.hold_last_to] 也补，但它只会重复**最后一帧**（那是
## 兜底，对 27 个已入库的角色一视同仁）。这里能选**停哪一帧** ——
## 攻击段常常是想让「伸得最远」那一格多停两帧，而不是让收招拖长。
##
## ## 复制的**恒是当前这一帧**
##
## 列表里那个选中项只用来**区分同一帧的哪一份**（复制过之后同一帧会出现
## 两次），不用来决定复制谁 —— 用它决定的话，翻帧不会清掉旧的选中项，
## 于是「翻到第 5 帧按复制，出来的是第 2 帧」，而屏幕上两处各说各的。
func _on_copy() -> void:
	if _shots.is_empty():
		return
	var picked := picks_of(_anim)
	var rows := _list.get_selected_items()
	var at: int = -1
	if not rows.is_empty() and picked[rows[0]] == _index:
		at = rows[0]
	else:
		at = picked.find(_index)
	if at < 0:
		said.emit("[color=#e06666]这一帧还不在名单里 —— 先按「＋ 要这一帧」。[/color]")
		return
	var frame: int = picked[at]
	picked.insert(at + 1, frame)
	_set_to(picked)
	_list.select(at + 1)
	said.emit("第 %d 帧多留了一份，这一段现在 %d 帧。" % [frame, picked.size()])


func _on_drop() -> void:
	var rows := _list.get_selected_items()
	if rows.is_empty():
		return
	var picked := picks_of(_anim)
	picked.remove_at(rows[0])
	_set_to(picked)


## 调整顺序。**顺序就是播放顺序** —— 命中那一帧要落在
## [member PBSimConfig.attack_hit_frame] 上，排错了游戏里就是
## 「先掉血、后挥手」。
func _move(by: int) -> void:
	var rows := _list.get_selected_items()
	if rows.is_empty():
		return
	var from: int = rows[0]
	var to: int = from + by
	var picked := picks_of(_anim)
	if to < 0 or to >= picked.size():
		return
	var moved: int = picked[from]
	picked.remove_at(from)
	picked.insert(to, moved)
	_set_to(picked)
	_list.select(to)


func _on_row(row: int) -> void:
	var picked := picks_of(_anim)
	if row < 0 or row >= picked.size():
		return
	show_frame.emit(picked[row])


func _set_to(picked: Array[int]) -> void:
	set_picks(_anim, picked)


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button
