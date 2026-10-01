class_name PBRosterBay
extends Control
## F 区：**忍者仓库**，常驻 + 可滚动（§05 / §02）。
##
## **只装仓库里的人**：在场的画在战场上、出任务的在任务栏（[PBQuestCard]），一个忍者只在一处出现。
##
## **滚动是自己算的，不是 [ScrollContainer]**：那个容器的默认滚动条会吃掉这个 130 像素宽框里的一整列格子。
## 这里是裁剪 + 行偏移 + 滚轮。
##
## **本类自己也实现了一遍拖放协议**：[PBDropArea] 和裁剪层 [member _clip] 是兄弟，而引擎找放置目标
## 只沿父链往上走（`Viewport::_gui_drop`），经过不了那个兄弟 —— 不补的话只有正好落在某张卡上才收得住，
## 从战场拖回来十次有八次弹回去。[PBDropArea] 留着管标题行和四周留白。

## 玩家点了仓库里的一张卡。
signal unit_picked(unit_id: StringName)

## 滚了一行，请调用方重画一次 —— 本类不持有 state，自己重画不出来。
signal scrolled

## 有人把一张卡拖进仓库了（§02 的拖放三区）。
signal card_dropped(from_zone: StringName, unit_id: StringName, to_zone: StringName)

## 一行摆几个。格子 30 宽，框内宽 122 —— 四列正好，留不出间隙，
## 靠格子自己的深色底分隔。
const COLUMNS: int = 4
const PITCH := Vector2(30.0, 35.0)

## 标题那一行占多高。
const TITLE_H: float = 12.0

## 框四周留白。左右各 4，下面留 2 —— 上面那一格给标题。
const PAD: float = 4.0

## 一次建满多少张卡（§14：战斗中零新建节点）。**显示容量，不是规则** ——
## 重复抽到的是另一个人，张数只受抽卡次数限制，超出的部分滚不到（记在待决策表上）。
const CAP: int = 60

var _tiles: Array[PBUnitTile] = []
var _ring: ColorRect
var _title: Label
var _clip: Control
var _rows_shown: int = 1
var _row_offset: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rect: Rect2 = PBLayout.F_ROSTER
	PBSkin.panel(self, rect)
	# **整块都能接**，不只是那些格子：仓库空着的时候一个可见的格子都没有，
	# 而「把人拖回一个空仓库」正是最该成立的那一下。加在最前面，
	# 好让格子画在它上面（Godot 的 2D 绘制顺序就是子节点顺序）。
	var drop := PBDropArea.new()
	drop.cover(rect, PBUnitTile.ZONE_STASH)
	drop.card_dropped.connect(
		func(from: StringName, id: StringName, _at: Vector2) -> void:
			card_dropped.emit(from, id, PBUnitTile.ZONE_STASH)
	)
	add_child(drop)
	_title = PBSkin.label(
		self,
		rect.position + Vector2(PAD, 1.0),
		rect.size.x - PAD * 2.0,
		PBSkin.FONT_BODY,
		PBSkin.TITLE
	)

	# 裁剪区：滚出去的那几行必须真的看不见，否则会漫到 G 和 H 上面。
	_clip = Control.new()
	_clip.position = rect.position + Vector2(PAD, TITLE_H)
	_clip.size = Vector2(rect.size.x - PAD * 2.0, rect.size.y - TITLE_H - 2.0)
	_clip.clip_contents = true
	# 要收滚轮，所以这一层**不能**是 IGNORE。
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_clip.gui_input.connect(_on_scroll)
	add_child(_clip)

	_rows_shown = maxi(int(_clip.size.y / PITCH.y), 1)

	# 选中框画在全部格子底下，靠 move_child 提到对应位置 —— 和 [PBFieldSlots]
	# 同一套：一个比格子大三像素的实心块，格子盖在上面，效果是一圈描边。
	_ring = ColorRect.new()
	_ring.color = PBSkin.TITLE
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_clip.add_child(_ring)

	# 按上限一次建满，之后只改内容和位置（§14）。
	for i: int in CAP:
		var tile := PBUnitTile.new()
		tile.visible = false
		tile.zone = PBUnitTile.ZONE_STASH
		tile.picked.connect(func(hit: PBUnitTile) -> void: unit_picked.emit(hit.unit.key()))
		tile.dropped.connect(card_dropped.emit)
		_clip.add_child(tile)
		_tiles.append(tile)


## 按当前状态重画。[param deployed] 与 [param away] 是要**减掉**的两档 ——
## 它们各自在战场上和出任务那一排有位置。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	wave: PBWave,
	deployed: Array[PBUnit],
	away: Array[PBUnit]
) -> void:
	var idle := idle_units(state, deployed, away)
	var rows: int = int(ceilf(float(idle.size()) / float(COLUMNS)))
	# 卡变少（上场 / 派出去）之后偏移可能已经翻过了尾巴，
	# 那时整个框是空的，而玩家看不出是「没有卡」还是「滚过头了」。
	_row_offset = clampi(_row_offset, 0, maxi(rows - _rows_shown, 0))

	_title.text = "仓库 %d　出战 %d/%d" % [idle.size(), deployed.size(), state.open_slots(cfg)]
	if rows > _rows_shown:
		_title.text += "　↕%d/%d" % [_row_offset + 1, rows - _rows_shown + 1]

	_ring.visible = false
	for i: int in _tiles.size():
		var tile: PBUnitTile = _tiles[i]
		tile.visible = i < idle.size()
		if not tile.visible:
			continue
		tile.position = Vector2(
			float(i % COLUMNS) * PITCH.x, float(i / COLUMNS - _row_offset) * PITCH.y
		)
		tile.set_unit(idle[i], wave.element)
		if selection.kind == PBSelection.Kind.UNIT and selection.unit_id == idle[i].key():
			_mark(tile)


## 仓库里的人：手上全部的卡，减掉上场的和出任务的。
##
## **现算而不是让调用方传第三份名单**：它是前两份的补集，
## 传进来就有可能和那两份对不上，而对不上的表现是「同一个人出现在两处」。
static func idle_units(
	state: PBRunState, deployed: Array[PBUnit], away: Array[PBUnit]
) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for unit: PBUnit in state.all_units():
		if not deployed.has(unit) and not away.has(unit):
			out.append(unit)
	return out


## 裁剪层里的空位也要收得住拖放，见类顶部那段。
##
## **只认卡，不认装备**：忍具拖到仓库上没有意义，而返回 true 会让
## 引擎把「可以放」的光标显示出来，然后松手什么都不发生 ——
## 那比直接不接更像坏了。
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return not PBUnitTile.card_of(data).is_empty()


func _drop_data(_at: Vector2, data: Variant) -> void:
	var card := PBUnitTile.card_of(data)
	if not card.is_empty():
		card_dropped.emit(StringName(card["zone"]), StringName(card["unit"]), PBUnitTile.ZONE_STASH)


## 滚轮翻行。**钳在两头**，滚过尾巴会得到一个空框。
func _on_scroll(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_rows(1)
	elif click.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_rows(-1)


func scroll_rows(direction: int) -> void:
	_row_offset = maxi(_row_offset + direction, 0)
	scrolled.emit()


func _mark(tile: PBUnitTile) -> void:
	_ring.position = tile.position - Vector2(2.0, 2.0)
	_ring.size = PBUnitTile.TILE_SIZE + Vector2(4.0, 4.0)
	_ring.visible = true
	_clip.move_child(_ring, 0)
