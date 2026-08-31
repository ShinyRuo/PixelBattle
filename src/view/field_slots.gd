class_name PBFieldSlots
extends Control
## 战场左侧那一列可点的东西，加上右半边的两排头像：
## **尾兽槽、大本营、仓库、出任务中**。M3.5-e；M4-f 换掉了其中一排。
##
## ## 为什么这几样在一个类里
##
## 它们是同一件事的几种形态：**一个能被选中、然后在指令卡上出现指令的槽位**。
## 分成几个类的话，「点了 A 要不要取消 B 的选中」这条规则会散在几处，
## 而那种不一致的表现是「同时亮着两个选中框」——看得见，但改起来要翻几个文件。
##
## ## M4-f：出战席那一排换成了仓库
##
## 上场的忍者现在**直接画在战场上、可以拖动摆位**（§02），
## 所以再摆一排出战席头像就是同一件事的第二个显示，而两处迟早对不上。
## 腾出来的位置给了屏幕上原来一直看不见的那一档：**仓库里的人**。
##
## ## 出任务中的人也要显示
##
## §06 的派遣把人送走，羁绊跟着失效。**不显示的话玩家只能从
## 「羁绊怎么少了一档」反推是谁走了**，而那是他自己刚做的决定，
## 界面没有理由让他去猜。只显示头像、不给指令 —— 他们这一波确实动不了。

## 玩家点了某个槽位。忍者槽会带上是谁。
signal slot_picked(kind: PBSelection.Kind, unit_id: StringName)

## 玩家点了「仓库」。**不是一种选中** —— 它开的是一块抽屉（[PBRosterDrawer]），
## 而抽屉开着的时候选中的仍然是刚才那个人。混进 [signal slot_picked] 的话
## 就得给 [enum PBSelection.Kind] 加一个「选中了仓库」，
## 而那件事在指令卡上没有任何指令可给。
signal stash_toggled

## 尾兽槽、大本营、仓库叠在最左边一小列；出战席与出任务各排成**一横排**。
##
## 竖着排过一版，10 个出战位 × 17px 一直伸到 y=266，
## 把羁绊带和信息栏全压在下面 —— 截图一看就知道。
## 横排之后左边只占 40px，战场那条道整个空出来。
##
## 这一列**故意伸进战场那条道的左端**（y 一直到 182）：那正是原版
## 大本营所在的位置，而战斗中这一列会整块隐藏，挡不着任何东西。
const COLUMN_X: float = 2.0
const BEAST_Y: float = 88.0
const BASE_Y: float = 120.0
const STASH_Y: float = 152.0

## **仓库那一排**（M4-f）：还没上场的卡。
##
## ## 它取代了原来的出战席那一排
##
## 上场的忍者现在直接画在战场上、可以拖动摆位（§02），所以再摆一排头像
## 就是**同一件事的第二个显示**，而两处迟早对不上。腾出来的位置给了
## 屏幕上原来一直看不见的那一档：**仓库里的人**。
##
## 两排都摆在战场的**右半边**（界限之外）：玩家只在界限左边摆兵，
## 右半边准备阶段本来就是空的，而战斗中这两排整块隐藏。
const IDLE_X: float = 336.0
const IDLE_Y: float = 100.0
const DEPLOY_STEP: float = 34.0

## 出任务中的头像排在仓库下面 —— 它们不参与战斗，混在一起会被误认成能上场。
const DISPATCH_X: float = 336.0
const DISPATCH_Y: float = 158.0

const SLOT_SIZE := Vector2(40.0, 30.0)

## 一排最多摆几个。摆不下的写进标签（「还有 N 张」），
## **不换行** —— 换行会挤进出任务那一排。
const ROW_MAX: int = 7

## 两排头像上面各一行小字。
const LABEL_Y: float = 89.0
const DISPATCH_LABEL_Y: float = 147.0

var _beast: Button
var _base: Button
var _stash: Button
var _deploy_tiles: Array[PBUnitTile] = []
var _dispatch_tiles: Array[PBUnitTile] = []
var _marks: Array[ColorRect] = []
var _deploy_label: Label
var _dispatch_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_beast = _add_button(Vector2(COLUMN_X, BEAST_Y), PBSelection.Kind.BEAST)
	_base = _add_button(Vector2(COLUMN_X, BASE_Y), PBSelection.Kind.BASE)
	_stash = _add_button(Vector2(COLUMN_X, STASH_Y), PBSelection.Kind.NONE)
	# 仓库不是一种选中（见 [signal stash_toggled]），所以它自己接一条线，
	# 而不是走 `_add_button` 默认那条。
	_stash.pressed.connect(func() -> void: stash_toggled.emit())

	_deploy_label = _add_label(Vector2(IDLE_X, LABEL_Y), 270.0)
	_dispatch_label = _add_label(Vector2(DISPATCH_X, DISPATCH_LABEL_Y), 270.0)

	# 按上限一次建满，之后只改内容 —— 和敌人池、指令卡同一条规矩（§14）。
	for i: int in ROW_MAX:
		_deploy_tiles.append(
			_add_tile(Vector2(IDLE_X + float(i) * DEPLOY_STEP, IDLE_Y), false)
		)
	# 派遣人数的上限是 SSS 任务的 4 人（§06 的任务表）。
	for i: int in 4:
		_dispatch_tiles.append(
			_add_tile(Vector2(DISPATCH_X + float(i) * DEPLOY_STEP, DISPATCH_Y), true)
		)


## 按当前状态重画。[param deployed] 是「现在开打的话会是谁」，
## [param away] 是「这一波谁去做任务」。
##
## 派遣名单由调用方算好传进来，本类不自己问 —— 它有三种口径
## （已锁定的 `dispatched_ids` / 接了任务的预览 / 玩家钦定但还没接），
## 而选哪一种取决于现在是哪个阶段，那是 [PBBattleView] 才知道的事。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	wave: PBWave,
	deployed: Array[PBUnit],
	away: Array[PBUnit]
) -> void:
	_beast.text = "尾兽\n%s" % ("Lv%d" % state.beast_level if state.beast_id != &"" else "空")
	_base.text = "大本营\n%d" % int(state.base_hp)
	# 仓库里有几张没上场的卡。**数出来摆在按钮上** —— 不写数字的话，
	# 玩家没有理由去点开它，而「派上场」那条指令只在里面点得到。
	#
	# 出任务的人也要减掉：他们已经不在 [param deployed] 里了（M3.5-i），
	# 不减的话派一个人出去仓库的数字就凭空 +1。
	_stash.text = "仓库\n%d" % maxi(state.roster.size() - deployed.size() - away.size(), 0)

	# **这一排现在是仓库，不是出战席**（M4-f）：上场的人直接画在战场上。
	# 摆不下的只写个数 —— 换行会挤进出任务那一排。
	var idle := _idle_units(state, deployed, away)
	_deploy_label.text = "仓库 %d 张　出战 %d/%d（战场上拖动摆位）" % [
		idle.size(), deployed.size(), state.open_slots(cfg)
	]
	if idle.size() > ROW_MAX:
		_deploy_label.text += "　…还有 %d，按 V" % (idle.size() - ROW_MAX)
	for i: int in _deploy_tiles.size():
		var tile: PBUnitTile = _deploy_tiles[i]
		tile.visible = i < idle.size()
		if tile.visible:
			tile.set_unit(idle[i], wave.element)

	# §06：出任务的人这一波不在场。
	_dispatch_label.text = "出任务 %d 人（羁绊不算他们）" % away.size()
	_dispatch_label.visible = not away.is_empty()
	for i: int in _dispatch_tiles.size():
		var tile: PBUnitTile = _dispatch_tiles[i]
		tile.visible = i < away.size()
		if tile.visible:
			tile.set_unit(away[i], wave.element)

	_mark(selection)


## 仓库里的人：手上全部的卡，减掉上场的和出任务的。
##
## 现算而不是让调用方传第三份名单：它是前两份的补集，
## 传进来就有可能和那两份对不上，而对不上的表现是「同一个人出现在两处」。
func _idle_units(
	state: PBRunState, deployed: Array[PBUnit], away: Array[PBUnit]
) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for unit: PBUnit in state.all_units():
		if not deployed.has(unit) and not away.has(unit):
			out.append(unit)
	return out


## 把选中框画到对的地方。**每次重画都从头摆一遍** ——
## 增量维护的话，一个槽位藏起来时那个框会留在原地，看起来像选中了空气。
func _mark(selection: PBSelection) -> void:
	for rect: ColorRect in _marks:
		rect.visible = false
	match selection.kind:
		PBSelection.Kind.BEAST:
			_show_mark(0, _beast.position, _beast.size)
		PBSelection.Kind.BASE:
			_show_mark(0, _base.position, _base.size)
		PBSelection.Kind.UNIT:
			_mark_tile(_deploy_tiles, selection.unit_id)
		PBSelection.Kind.DISPATCHED:
			_mark_tile(_dispatch_tiles, selection.unit_id)
		_:
			pass


func _mark_tile(tiles: Array[PBUnitTile], unit_id: StringName) -> void:
	for tile: PBUnitTile in tiles:
		if tile.visible and tile.unit != null and tile.unit.key() == unit_id:
			_show_mark(0, tile.position, tile.size)
			return


func _show_mark(index: int, at: Vector2, of_size: Vector2) -> void:
	while _marks.size() <= index:
		var rect := ColorRect.new()
		rect.color = PBSkin.TITLE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		add_child(rect)
		_marks.append(rect)
	# 画成一个比槽位大两像素的实心块，槽位盖在它上面 —— 效果是一圈描边，
	# 而属性底色一点没被遮住。
	var rect: ColorRect = _marks[index]
	rect.position = at - Vector2(3.0, 3.0)
	rect.size = of_size + Vector2(6.0, 6.0)
	rect.visible = true
	move_child(rect, 0)


func _add_tile(at: Vector2, dispatched: bool) -> PBUnitTile:
	var tile := PBUnitTile.new()
	tile.position = at
	tile.visible = false
	tile.picked.connect(
		func(hit: PBUnitTile) -> void:
			slot_picked.emit(
				PBSelection.Kind.DISPATCHED if dispatched else PBSelection.Kind.UNIT,
				hit.unit.key()
			)
	)
	add_child(tile)
	return tile


## 左边那一列的一个按钮。**`custom_minimum_size` 和 `size` 都要给** ——
## 只给 `size` 的话，按钮会被自己的最小尺寸挤成一条窄缝，
## 里面的两个字被逐字折行成竖排，看着像字体坏了。
func _add_button(at: Vector2, kind: PBSelection.Kind) -> Button:
	var button := Button.new()
	button.position = at
	button.custom_minimum_size = SLOT_SIZE
	button.size = SLOT_SIZE
	PBSkin.style_button(button)
	if kind != PBSelection.Kind.NONE:
		button.pressed.connect(func() -> void: slot_picked.emit(kind, &""))
	add_child(button)
	return button


func _add_label(at: Vector2, width: float) -> Label:
	return PBSkin.label(self, at, width, PBSkin.FONT_BODY, PBSkin.DIM)
