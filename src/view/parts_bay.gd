class_name PBPartsBay
extends Control
## G 区：**忍具仓库**，常驻 + 可滚动（§10）。
##
## 上排是合得出的成品（能拖到 [PBEquipBay] 挂上人），下面是配件（只能等配方凑齐）——
## 「我现在能装备什么」和「我还差什么」是两个问题。
##
## 流式格子 + 裁剪滚动（同 [PBRosterBay]），**列数按框宽算**，所以缩框不会少摆东西。
## **七种配件全摆着，包括个数为 0 的**：「这一种我一个都没有」正是配方凑不齐的原因。
## 50 格只是显示容量；配件在 core 里是计数，没有上限（要做上限得先回答「满了怎么办」）。

## 玩家点了某件东西，请摊开一张说明卡。**参数顺序对齐
## [method PBTooltip.show_card]** —— 接线时一句 `connect` 就够，
## 中间那一跳（拿到 id 再去查表）没有存在的必要。
signal tip_requested(at: Rect2, title: String, body: String)

## 有人把一件装备拖回仓库了（= 卸下）。
signal item_returned(item_id: StringName)

## 滚了一行，请调用方重画一次 —— 本类不持有 state，自己重画不出来。
## 和 [signal PBRosterBay.scrolled] 是同一条。
signal scrolled

## 一次建满多少格（§14：战斗中零新建节点）。成品最多七种、配件七种，
## 各自还可能有多份要分行摆 —— 40 是个宽到不用再想的数。
const CAP: int = 40

const PITCH: float = 21.0
const PAD: float = 4.0
const TITLE_H: float = 11.0

## 成品和配件之间空一行。两级东西的用法完全不同，挨着摆会被当成一片。
const GAP_ROWS: int = 1

var _tiles: Array[PBItemTile] = []
var _title: Label
var _table: PBEquipTable
var _clip: Control
var _columns: int = 3
var _rows_shown: int = 1
var _row_offset: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rect: Rect2 = PBLayout.G_PARTS
	PBSkin.panel(self, rect)
	# 整块都能接：卸下一件装备是往「忍具仓库」拖，而不是往某个具体格子拖 ——
	# 那个格子还不存在（它正挂在人身上）。
	var drop := PBDropArea.new()
	drop.cover(rect, PBUnitTile.ZONE_STASH)
	drop.item_dropped.connect(func(_from: StringName, id: StringName) -> void: item_returned.emit(id))
	add_child(drop)

	_title = PBSkin.label(
		self, rect.position + Vector2(PAD, 0.0), rect.size.x - PAD * 2.0,
		PBSkin.FONT_BODY, PBSkin.TITLE
	)

	# 裁剪区：滚出去的那几行必须真的看不见，否则会漫到 F 和 H 上面。
	_clip = Control.new()
	_clip.position = rect.position + Vector2(PAD, TITLE_H)
	_clip.size = Vector2(rect.size.x - PAD * 2.0, rect.size.y - TITLE_H - 2.0)
	_clip.clip_contents = true
	# 要收滚轮，所以这一层**不能**是 IGNORE。
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_clip.gui_input.connect(_on_scroll)
	add_child(_clip)

	# **列数是算出来的，不是写死的。** 写死的话 [PBLayout] 一改框宽，
	# 最右边那一列就画到隔壁面板上去了 —— 而那不报错。
	_columns = maxi(int(_clip.size.x / PITCH), 1)
	_rows_shown = maxi(int(_clip.size.y / PITCH), 1)

	for i: int in CAP:
		var tile := PBItemTile.new()
		tile.visible = false
		tile.zone = PBUnitTile.ZONE_STASH
		tile.picked.connect(_on_tile_picked)
		_clip.add_child(tile)
		_tiles.append(tile)


func refresh(state: PBRunState, cfg: PBSimConfig) -> void:
	var table: PBEquipTable = cfg.equipment
	if table == null:
		return
	_table = table
	var spare := PBEquipRules.craftable(state.equip_parts, table)
	var ids: Array = spare.keys()
	var item_rows: int = int(ceilf(float(ids.size()) / float(_columns)))
	var part_rows: int = int(ceilf(float(table.parts.size()) / float(_columns)))
	var rows: int = item_rows + (GAP_ROWS if item_rows > 0 else 0) + part_rows
	# 滚过尾巴之后整个框是空的，而玩家看不出是「没有东西」还是「滚过头了」。
	_row_offset = clampi(_row_offset, 0, maxi(rows - _rows_shown, 0))

	_title.text = "忍具 %d　配件 %d" % [ids.size(), PBEquipRules.part_total(state.equip_parts)]
	if rows > _rows_shown:
		_title.text += "　↕%d/%d" % [_row_offset + 1, rows - _rows_shown + 1]

	var slot: int = 0
	for i: int in ids.size():
		_place(slot, i, 0)
		_tiles[slot].set_item(table.item(ids[i]), int(spare[ids[i]]))
		slot += 1
	var below: int = item_rows + (GAP_ROWS if item_rows > 0 else 0)
	for i: int in table.parts.size():
		if slot >= _tiles.size():
			break
		_place(slot, i, below)
		_tiles[slot].set_part(table.parts[i], int(state.equip_parts.get(table.parts[i], 0)))
		slot += 1
	for i: int in range(slot, _tiles.size()):
		_tiles[i].visible = false


## 把第 [param slot] 个格子摆到「第 [param index] 个、从第 [param base] 行起」那一格上。
func _place(slot: int, index: int, base: int) -> void:
	var tile: PBItemTile = _tiles[slot]
	tile.visible = true
	tile.position = Vector2(
		float(index % _columns) * PITCH,
		float(base + index / _columns - _row_offset) * PITCH
	)


## 滚轮翻行。**钳在两头**，滚过尾巴会得到一个空框。
func _on_scroll(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_row_offset += 1
	elif click.button_index == MOUSE_BUTTON_WHEEL_UP:
		_row_offset = maxi(_row_offset - 1, 0)
	else:
		return
	scrolled.emit()


## 拼说明卡的文字。**文案全部走 [PBShopLabels]** ——
## 装备栏那边点开的是同一张卡，各写一份迟早在措辞上分叉。
func _on_tile_picked(tile: PBItemTile) -> void:
	var at := Rect2(tile.global_position, tile.size)
	if not tile.draggable:
		tip_requested.emit(
			at, PBLocale.text("equip_part.%s" % tile.item_id), PBShopLabels.part_body()
		)
		return
	var item := _table.item(tile.item_id) if _table != null else null
	if item != null:
		tip_requested.emit(at, PBLocale.text(item.name_key), PBShopLabels.item_body(item, _table))
