class_name PBEquipBay
extends Control
## I 区：**选中那个忍者的三个装备槽**（§10）。只在显示某个忍者时出现。
##
## **手动挂的拖得动，自动补的拖不动**（压暗）：规矩是手动优先、自动补满（[member PBRunState.equipped]），
## 自动补的卸了下一帧又会被补回来。
## 挂不挂得上由 [method PBEquipRules.pin] 判，界面这一层不重复判 —— 判两遍迟早口径不同。

## 有人把一件装备拖到槽上了（= 挂上）。
signal item_equipped(item_id: StringName)

## 玩家点了某一格，请摊开一张说明卡。参数顺序对齐 [method PBTooltip.show_card]。
signal tip_requested(at: Rect2, title: String, body: String)

const PITCH: float = 24.0
const PAD: float = 4.0
const TITLE_H: float = 11.0

var _slots: Array[PBItemTile] = []
var _title: Label
var _table: PBEquipTable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rect: Rect2 = PBLayout.I_EQUIP
	PBSkin.panel(self, rect)
	# 整块都能接：三个槽哪一个空着不该由玩家去瞄准 —— 挂上去是「给这个人」，
	# 不是「放进第 2 格」（§10 的槽位之间没有区别）。
	var drop := PBDropArea.new()
	drop.cover(rect, PBUnitTile.ZONE_FIELD)
	drop.item_dropped.connect(
		func(_from: StringName, id: StringName) -> void: item_equipped.emit(id)
	)
	add_child(drop)

	_title = PBSkin.label(
		self,
		rect.position + Vector2(PAD, 0.0),
		rect.size.x - PAD * 2.0,
		PBSkin.FONT_BODY,
		PBSkin.TITLE
	)
	for i: int in PBSimConfig.new().equip_items_per_unit:
		var tile := PBItemTile.new()
		tile.position = rect.position + Vector2(PAD + 8.0, TITLE_H + float(i) * PITCH)
		tile.visible = false
		tile.zone = PBUnitTile.ZONE_FIELD
		tile.picked.connect(_on_tile_picked)
		add_child(tile)
		_slots.append(tile)


## [param deployed] 是「现在开打的话会是谁」—— **装备只发给上场的人**（§10），
## 所以没上场的忍者这一栏是空的，标题要说清是为什么。
func refresh(
	unit: PBUnit,
	state: PBRunState,
	cfg: PBSimConfig,
	deployed: Array[PBUnit],
	editable: bool = true
) -> void:
	_table = cfg.equipment
	var index: int = deployed.find(unit) if unit != null else -1
	if index < 0:
		_title.text = "装备\n未上场"
		for tile: PBItemTile in _slots:
			tile.visible = false
		return

	var held: PackedStringArray = (
		PBEquipRules.assign(deployed, state.equip_parts, cfg, state.equipped)[index]
	)
	var pins: Array = PBEquipRules.pinned_of(state.equipped, unit.key()).duplicate()
	_title.text = "装备 %d/%d" % [held.size(), cfg.equip_items_per_unit]
	for i: int in _slots.size():
		var tile: PBItemTile = _slots[i]
		tile.visible = i < held.size()
		if not tile.visible:
			continue
		var item_id := StringName(held[i])
		# **自动补上的压暗、拖不动**：卸了下一帧又会被补回来。
		var manual: bool = pins.has(item_id)
		if manual:
			pins.erase(item_id)
		tile.set_item(cfg.equipment.item(item_id), 1, not manual)
		tile.draggable = manual and editable


## 说明卡走 [PBShopLabels]，和忍具仓库那边点开的是同一张。
func _on_tile_picked(tile: PBItemTile) -> void:
	var item := _table.item(tile.item_id) if _table != null else null
	if item != null:
		tip_requested.emit(
			Rect2(tile.position, tile.size),
			PBLocale.text(item.name_key),
			PBShopLabels.item_body(item, _table)
		)
