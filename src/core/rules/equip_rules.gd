class_name PBEquipRules
extends RefCounted
## 装备的合成与分配（§10 的三级树）。
##
## 三件事让装备不是一条全队倍率：**配方点名**（随机出的配件一定会囤下用不上的）、
## **分类匹配**（法术装挂物理角色不生效）、**整数分配**（每人最多 3 件）。


## 手上的配件能合出哪些成品，各几件。返回 `{成品 id: 件数}`。
##
## **贪心，按加成从高到低合。** 不做全局最优的背包搜索，两个理由：
## 一是玩家也不会做背包搜索，模拟玩家比真人聪明会得出偏乐观的结论；
## 二是它在估值里一局要跑几万次，指数搜索直接把批量扫描拖垮。
static func craftable(parts: Dictionary, table: PBEquipTable) -> Dictionary:
	var pool: Dictionary = parts.duplicate()
	var ranked: Array[PBEquipItem] = table.items.duplicate()
	ranked.sort_custom(func(a: PBEquipItem, b: PBEquipItem) -> bool: return a.power > b.power)

	var out: Dictionary = {}
	for entry: PBEquipItem in ranked:
		# 加成为 0 的成品一件都不合 —— 合了就是把配件烧掉换一个没用的东西。
		# §10 里那两件防御向的成品在当前模型下正是这种（见 [member PBEquipItem.power]）。
		if entry.power <= 0.0:
			continue
		while _can_craft(pool, entry):
			for part_id: StringName in entry.recipe:
				pool[part_id] = int(pool.get(part_id, 0)) - 1
			out[entry.id] = int(out.get(entry.id, 0)) + 1
	return out


static func _can_craft(pool: Dictionary, entry: PBEquipItem) -> bool:
	if entry.recipe.is_empty():
		return false
	for part_id: StringName in entry.recipe:
		if int(pool.get(part_id, 0)) < entry.needs(part_id):
			return false
	return true


## 每个出战单位身上**实际挂着哪几件**成品（与 [param deployed] 同序），元素是成品 id。
##
## [param pinned] 是玩家手动挂的（[member PBRunState.equipped]），**先占位**；
## 剩下的空位按估值分从高到低发给吃得下、还有空位的人。装不下的压在仓库里。
##
## **词条从这份名单派生**（[method unit_mods]），不另算一遍 ——
## 两份的表现是「面板上写着挂了某件，战斗里按没挂算」。
static func assign(
	deployed: Array[PBUnit], parts: Dictionary, cfg: PBSimConfig, pinned: Dictionary = {}
) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for _i: int in deployed.size():
		out.append(PackedStringArray())
	var table: PBEquipTable = cfg.equipment
	if deployed.is_empty() or table == null:
		return out

	var owned := craftable(parts, table)
	# 合成表没有分类概念，对谁都生效 —— 那是替身曲线的定义（见 [PBEquipTable]）。
	var ignore_category: bool = table.is_synthetic()

	for i: int in deployed.size():
		for raw: Variant in pinned.get(deployed[i].key(), []):
			if out[i].size() >= cfg.equip_items_per_unit:
				break
			var item := table.item(StringName(raw))
			if not _can_give(item, owned, deployed[i], ignore_category):
				continue
			owned[item.id] = int(owned[item.id]) - 1
			out[i].append(String(item.id))

	var ranked: Array[PBEquipItem] = table.items.duplicate()
	ranked.sort_custom(func(a: PBEquipItem, b: PBEquipItem) -> bool: return a.power > b.power)
	for entry: PBEquipItem in ranked:
		var remaining: int = int(owned.get(entry.id, 0))
		if remaining <= 0 or entry.power <= 0.0:
			continue
		for i: int in deployed.size():
			if remaining <= 0:
				break
			if not ignore_category and not entry.fits(deployed[i].element):
				continue
			# **先把靠前的人装满再往后发。** [param deployed] 已经按有效战力排过序，
			# 而每件装备是乘在持有者自己的输出上的 —— 同一件装备挂在输出更高的人
			# 身上收益更大，所以「填满强的再给弱的」就是这里的最优解。
			var give: int = mini(cfg.equip_items_per_unit - out[i].size(), remaining)
			for _k: int in maxi(give, 0):
				out[i].append(String(entry.id))
			remaining -= maxi(give, 0)
		owned[entry.id] = remaining
	return out


## 这件成品现在发得出去吗（存在、还有货、加成不为 0、分类对得上）。
static func _can_give(
	item: PBEquipItem, owned: Dictionary, unit: PBUnit, ignore_category: bool
) -> bool:
	if item == null or item.power <= 0.0:
		return false
	if int(owned.get(item.id, 0)) <= 0:
		return false
	return ignore_category or item.fits(unit.element)


## 每个单位身上那几件装备**加起来给了什么**（与 [param deployed] 同序）。
## 由 [method assign] 那份名单派生。**同键相加不覆盖**。
static func unit_mods(
	deployed: Array[PBUnit], parts: Dictionary, cfg: PBSimConfig, pinned: Dictionary = {}
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i: int in deployed.size():
		out.append({})
	var table: PBEquipTable = cfg.equipment
	if deployed.is_empty() or table == null:
		return out
	var held := assign(deployed, parts, cfg, pinned)
	for i: int in deployed.size():
		for item_id: String in held[i]:
			var item := table.item(StringName(item_id))
			if item == null:
				continue
			for key: StringName in item.mods:
				out[i][key] = float(out[i].get(key, 0.0)) + float(item.mods[key])
	return out


## 玩家把一件成品挂到某个人身上。已经满 3 件就挂不上，返回 false。
##
## **只管记账，不管这件东西现在合不合得出来** —— 合不出来的条目在
## [method assign] 里自动失效（见 [member PBRunState.equipped]）。
## 在这里就拦掉的话，玩家先挂后拆配件时会莫名其妙掉一格，
## 而他并不知道那一格是被谁清掉的。
static func pin(
	pinned: Dictionary, unit_id: StringName, item_id: StringName, cfg: PBSimConfig
) -> bool:
	var list: Array = pinned.get(unit_id, [])
	if list.size() >= cfg.equip_items_per_unit:
		return false
	list.append(item_id)
	pinned[unit_id] = list
	return true


## 卸下一件。挂着好几件同款时只卸一件。
static func unpin(pinned: Dictionary, unit_id: StringName, item_id: StringName) -> bool:
	var list: Array = pinned.get(unit_id, [])
	var at: int = list.find(item_id)
	if at < 0:
		return false
	list.remove_at(at)
	if list.is_empty():
		pinned.erase(unit_id)
	else:
		pinned[unit_id] = list
	return true


## 这个人身上钦定了哪几件（不含自动补上的那些）。
static func pinned_of(pinned: Dictionary, unit_id: StringName) -> Array:
	return pinned.get(unit_id, [])


## 整队还能再吃下几件成品。**「装备买满了没有」靠它判断，不靠件数除以位数** ——
## 分类匹配之后，「还有空位」和「那个空位吃得下手上这件」是两回事。
static func open_item_slots(deployed: Array[PBUnit], cfg: PBSimConfig) -> int:
	return deployed.size() * cfg.equip_items_per_unit


## 仓库里配件的总数。存档记的是分种类的字典，报数要的是一个数。
static func part_total(parts: Dictionary) -> int:
	var total: int = 0
	for part_id: StringName in parts:
		total += int(parts[part_id])
	return total


## 收一个配件进仓库。
static func add_part(parts: Dictionary, part_id: StringName) -> void:
	parts[part_id] = int(parts.get(part_id, 0)) + 1
