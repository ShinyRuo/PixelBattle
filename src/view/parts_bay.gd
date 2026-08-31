class_name PBPartsBay
extends Control
## G 区：**忍具仓库**，常驻。§10 / §02，M5-5。
##
## ## 上排是合得出的成品，下排是配件
##
## §10 的三级树里这两级完全不同：**成品能挂到人身上**（拖到 [PBEquipBay] 去），
## **配件只能等配方凑齐**。摆成两排、颜色也分开，是因为
## 「我现在能装备什么」和「我还差什么」是玩家在这块面板上问的两个不同问题。
##
## ## 七个配件格永远都在，包括个数为 0 的
##
## 少一格就少一条信息：**「这一种我一个都没有」正是配方凑不齐的原因**。
## 只摆有的那几种时，玩家看到的是一排数字，看不出缺口在哪 ——
## 而缺口才是他下一笔钱该往哪花的依据。
##
## ## 50 格上限现在只是显示容量
##
## 配件在 core 里是「种类 → 个数」的计数（[member PBRunState.equip_parts]），
## 没有格子也没有上限。要做成真上限得先回答「满了怎么办」
## （不让买 / 自动合成 / 溢出丢弃），那是一条会改玩法的规则，不在这一步。

## 玩家点了某件东西，请摊开一张说明卡。**参数顺序对齐
## [method PBTooltip.show_card]** —— 接线时一句 `connect` 就够，
## 中间那一跳（拿到 id 再去查表）没有存在的必要。
signal tip_requested(at: Rect2, title: String, body: String)

## 有人把一件装备拖回仓库了（= 卸下）。
signal item_returned(item_id: StringName)

## 上排最多摆几件成品。摆不下的在标题里报个数。
const MAX_ITEMS: int = 5

const PITCH: float = 21.0
const PAD: float = 4.0
const TITLE_H: float = 11.0

var _items: Array[PBItemTile] = []
var _parts: Array[PBItemTile] = []
var _title: Label
var _table: PBEquipTable


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
	var origin := rect.position + Vector2(PAD, TITLE_H)
	for i: int in MAX_ITEMS:
		_items.append(_add_tile(origin + Vector2(float(i) * PITCH, 0.0)))
	# 七种配件排成两行，和上排的成品隔开一行。
	for i: int in 7:
		_parts.append(
			_add_tile(origin + Vector2(float(i % 5) * PITCH, PITCH + 8.0 + float(i / 5) * PITCH))
		)


func refresh(state: PBRunState, cfg: PBSimConfig) -> void:
	var table: PBEquipTable = cfg.equipment
	if table == null:
		return
	_table = table
	var spare := PBEquipRules.craftable(state.equip_parts, table)
	var ids: Array = spare.keys()
	_title.text = "忍具 %d　配件 %d" % [ids.size(), PBEquipRules.part_total(state.equip_parts)]
	if ids.size() > MAX_ITEMS:
		_title.text += "　+%d" % (ids.size() - MAX_ITEMS)
	for i: int in _items.size():
		var tile: PBItemTile = _items[i]
		tile.visible = i < ids.size()
		if tile.visible:
			tile.set_item(table.item(ids[i]), int(spare[ids[i]]))
	for i: int in _parts.size():
		var tile: PBItemTile = _parts[i]
		tile.visible = i < table.parts.size()
		if tile.visible:
			tile.set_part(table.parts[i], int(state.equip_parts.get(table.parts[i], 0)))


func _add_tile(at: Vector2) -> PBItemTile:
	var tile := PBItemTile.new()
	tile.position = at
	tile.visible = false
	tile.zone = PBUnitTile.ZONE_STASH
	tile.picked.connect(_on_tile_picked)
	add_child(tile)
	return tile


## 拼说明卡的文字。**文案全部走 [PBShopLabels]** ——
## 装备栏那边点开的是同一张卡，各写一份迟早在措辞上分叉。
func _on_tile_picked(tile: PBItemTile) -> void:
	var at := Rect2(tile.position, tile.size)
	if not tile.draggable:
		tip_requested.emit(
			at, PBLocale.text("equip_part.%s" % tile.item_id), PBShopLabels.part_body()
		)
		return
	var item := _table.item(tile.item_id) if _table != null else null
	if item != null:
		tip_requested.emit(at, PBLocale.text(item.name_key), PBShopLabels.item_body(item, _table))
