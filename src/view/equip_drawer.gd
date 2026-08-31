class_name PBEquipDrawer
extends PBDrawer
## 忍者装备栏 + 配件仓库。§10，M3.5-f。
##
## ## 它把「自动分配」变成了「可以插手的自动分配」
##
## M3-c 到 M3.5-e 之间，装备是**全自动**的：[method PBEquipRules.assign]
## 按加成从高到低发给吃得下的人，玩家连自己身上挂了什么都看不到。
## 那在批量扫描里够用（脚本玩家本来也不会挑），但对真人来说
## 是一整个系统藏在屏幕后面。
##
## 现在的规矩是**手动优先、自动补满**（见 [member PBRunState.equipped]）：
## 挂上去的先占位，剩下的空位照旧自动填。所以「一件都不挂」和以前完全一样，
## 而想插手的人随时插得进去 —— 不需要先声明「我要手动管装备」。
##
## ## 挂不上要说出来，不能只是列不出来
##
## §10 的分类匹配意味着**挂不上是常态**：法术装挂不上物理角色。
## 只把挂不上的项从列表里去掉的话，玩家看到的是「仓库里明明合出了那件东西，
## 这里却没有」—— 他会以为是界面坏了。所以提示行照实报个数。
##
## ## 自动补上的那几件不给「卸下」按钮
##
## 卸了下一帧又会被自动补回来，看起来像按钮点不动。所以只有**手动挂的**
## 那几件是可点的，自动的那几件在文字上标着「（自动）」。

## 玩家要把 [param item_id] 挂到当前选中的人身上。
signal equip_requested(item_id: StringName)

## 玩家要卸下 [param item_id]。
signal unequip_requested(item_id: StringName)

const SLOT_SIZE := Vector2(150.0, 22.0)
const PICK_SIZE := Vector2(120.0, 22.0)

## 「可挂上」那一栏最多摆几个。摆不下的在提示行里报个数 ——
## 后期仓库里能合出十几件，全摆出来会把这一栏挤成一片糊字。
const MAX_PICKS: int = 6

var _slots: Array[Button] = []
var _picks: Array[Button] = []

## 每一格现在代表哪件成品。**回传的必须是 id，不是按钮上那行显示名**
## （§14 铁律 5：代码里不出现装备名）。和 [PBCommandCard] 的 `_bound` 同一套路。
var _slot_ids: Array[StringName] = []
var _pick_ids: Array[StringName] = []

var _slot_head: Label
var _pick_head: Label
var _stock: RichTextLabel


func _build_body() -> void:
	set_title("装备")
	_slot_head = PBSkin.label(body(), Vector2(8.0, 0.0), 164.0, PBSkin.FONT_BODY, PBSkin.DIM)
	_pick_head = PBSkin.label(body(), Vector2(178.0, 0.0), 250.0, PBSkin.FONT_BODY, PBSkin.DIM)

	for i: int in PBSimConfig.new().equip_items_per_unit:
		var slot := Button.new()
		slot.position = Vector2(8.0, 14.0 + float(i) * 24.0)
		slot.size = SLOT_SIZE
		PBSkin.style_button(slot)
		slot.pressed.connect(func() -> void: _emit_at(_slot_ids, i, true))
		body().add_child(slot)
		_slots.append(slot)
		_slot_ids.append(&"")

	for i: int in MAX_PICKS:
		var pick := Button.new()
		pick.position = Vector2(178.0 + float(i / 3) * 128.0, 14.0 + float(i % 3) * 24.0)
		pick.size = PICK_SIZE
		PBSkin.style_button(pick, PBSkin.Tone.QUIET)
		pick.pressed.connect(func() -> void: _emit_at(_pick_ids, i, false))
		body().add_child(pick)
		_picks.append(pick)
		_pick_ids.append(&"")

	_stock = PBSkin.rich(body(), Rect2(436.0, 0.0, 148.0, 86.0))


## [param deployed] 是「现在开打的话会是谁」—— 装备只发给上场的人，
## 所以没上场的忍者这一栏是空的，而那要说清楚，不能显示成「一件都没有」。
func refresh(unit: PBUnit, state: PBRunState, cfg: PBSimConfig, deployed: Array[PBUnit]) -> void:
	_stock.text = _stock_text(state, cfg)
	if unit == null:
		set_title("装备")
		set_hint("先点一个忍者。")
		_clear()
		return

	set_title("装备 · %s" % PBLocale.of_character(unit.character))
	var index: int = deployed.find(unit)
	if index < 0:
		set_hint("他没在出战席上 —— 装备只发给上场的人（§10）。先「派上场」再回来挂。")
		_clear()
		return

	var held: PackedStringArray = PBEquipRules.assign(
		deployed, state.equip_parts, cfg, state.equipped
	)[index]
	_fill_slots(held, PBEquipRules.pinned_of(state.equipped, unit.key()), cfg)
	_fill_picks(unit, state, cfg, deployed, held.size() < cfg.equip_items_per_unit)


func _clear() -> void:
	_slot_head.text = "已挂 —"
	_pick_head.text = ""
	for i: int in _slots.size():
		_slots[i].visible = false
		_slot_ids[i] = &""
	for i: int in _picks.size():
		_picks[i].visible = false
		_pick_ids[i] = &""


func _fill_slots(held: PackedStringArray, pins: Array, cfg: PBSimConfig) -> void:
	_slot_head.text = "已挂 %d/%d" % [held.size(), cfg.equip_items_per_unit]
	var manual_left: Array = pins.duplicate()
	for i: int in _slots.size():
		var slot: Button = _slots[i]
		slot.visible = true
		if i >= held.size():
			slot.text = "空槽"
			slot.disabled = true
			_slot_ids[i] = &""
			continue
		var item_id := StringName(held[i])
		var item := cfg.equipment.item(item_id)
		var manual: bool = manual_left.has(item_id)
		if manual:
			manual_left.erase(item_id)
		slot.text = "%s +%.0f%%%s" % [
			PBLocale.text(item.name_key) if item != null else String(item_id),
			(item.power if item != null else 0.0) * 100.0,
			"" if manual else "（自动）",
		]
		slot.disabled = not manual
		_slot_ids[i] = item_id if manual else &""


func _fill_picks(
	unit: PBUnit, state: PBRunState, cfg: PBSimConfig, deployed: Array[PBUnit], has_room: bool
) -> void:
	var spare := PBEquipRules.unassigned(deployed, state.equip_parts, cfg, state.equipped)
	# 合出来了、但因为分类不匹配这个人吃不下的，不摆进可点的列表 ——
	# 点不动的按钮只会让人反复点。它们改在提示行里报个数。
	var fits: Array[StringName] = []
	var blocked: int = 0
	for item_id: StringName in spare:
		var item := cfg.equipment.item(item_id)
		if item == null:
			continue
		if item.fits(unit.element) or cfg.equipment.is_synthetic():
			fits.append(item_id)
		else:
			blocked += int(spare[item_id])

	_pick_head.text = "可挂上 %d 种" % fits.size()
	for i: int in _picks.size():
		var pick: Button = _picks[i]
		pick.visible = i < fits.size()
		_pick_ids[i] = fits[i] if pick.visible else &""
		if not pick.visible:
			continue
		var item := cfg.equipment.item(fits[i])
		pick.text = "%s ×%d" % [PBLocale.text(item.name_key), int(spare[fits[i]])]
		pick.disabled = not has_room
	set_hint(_pick_hint(fits.size(), blocked, has_room))


func _pick_hint(fits: int, blocked: int, has_room: bool) -> String:
	if not has_room:
		return "三个槽满了。先卸一件（自动挂上的卸不掉，那是空位被自动补满了）。"
	if fits > MAX_PICKS:
		return "还有 %d 种没摆下 —— 先挂掉几件再看。" % (fits - MAX_PICKS)
	if blocked > 0:
		return "仓库里另有 %d 件他吃不下（§10：法术装挂不上物理角色）。" % blocked
	if fits == 0:
		return "没有能挂给他的成品。买忍具箱开配件，凑齐配方才合得出成品。"
	return "点中间挂上，点上排卸下。手动挂的先占位，剩下的空位仍旧自动补满。"


## 右边那栏：配件仓库 + 合得出来的成品。**配件是后期金币的主要去处，要一直看得见。**
func _stock_text(state: PBRunState, cfg: PBSimConfig) -> String:
	var table: PBEquipTable = cfg.equipment
	if table == null:
		return ""
	var lines := PackedStringArray()
	lines.append(
		PBSkin.tint("配件仓库 %d 个" % PBEquipRules.part_total(state.equip_parts), PBSkin.DIM)
	)
	var parts := PackedStringArray()
	for part_id: StringName in table.parts:
		var count: int = int(state.equip_parts.get(part_id, 0))
		var text: String = "%s%d" % [PBLocale.text("equip_part.%s" % part_id), count]
		parts.append(text if count > 0 else PBSkin.tint(text, PBSkin.DIM))
	lines.append("　".join(parts))

	var owned := PBEquipRules.craftable(state.equip_parts, table)
	if owned.is_empty():
		lines.append(PBSkin.tint("还合不出成品 —— 配方点名要哪几种（§10）。", PBSkin.DIM))
		return "\n".join(lines)
	var made := PackedStringArray()
	for item_id: StringName in owned:
		made.append("%s ×%d" % [PBLocale.text(table.item(item_id).name_key), int(owned[item_id])])
	lines.append(PBSkin.tint("合得出　" + "　".join(made), PBSkin.GOOD))
	return "\n".join(lines)


func _emit_at(ids: Array[StringName], index: int, take_off: bool) -> void:
	if index < 0 or index >= ids.size() or ids[index] == &"":
		return
	if take_off:
		unequip_requested.emit(ids[index])
	else:
		equip_requested.emit(ids[index])
