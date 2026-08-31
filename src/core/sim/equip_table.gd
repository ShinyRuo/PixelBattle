class_name PBEquipTable
extends RefCounted
## 全部配件与成品（§10）。合成看它、估值按它算、忍具箱从它出货。
##
## 和 [PBCharacterTable] / [PBBondTable] 同一个套路：
## 真表由 core 外面的加载器从 `data/equipment/*.tres` 装进来，
## 另有一张 [method synthetic] 造的合成表当默认值 ——
## **身份层作为可对拍的重构引入，换真数据是下一步**，
## 那一步的数值变化必须能和这一步的重构分开看。

## 全部配件 id（§10 的 7 种）。忍具箱等概率从这里出一个。
var parts: Array[StringName] = []

## 全部成品。
var items: Array[PBEquipItem] = []


## 造一张只有一种配件、一种「万能成品」的表。
##
## **这是 M-1 那条替身曲线的结构等价物**：任意 `parts_per_item` 个配件
## 换一件对谁都生效的成品，没有配方点名、没有分类匹配、没有囤积损耗。
## 留着它是为了让「换真装备表」那一步的数值变化能单独看见 ——
## 真表一上来就会同时引入配方损耗和分类匹配两件事，混在一起就分不开了。
static func synthetic(parts_per_item: int, power_per_item: float) -> PBEquipTable:
	var out := PBEquipTable.new()
	out.parts = [&"part"]
	var recipe: Array[StringName] = []
	for _i: int in maxi(parts_per_item, 1):
		recipe.append(&"part")
	# 分类填 PHYSICAL 但 fits() 会被合成表的使用者绕过去 —— 见 [PBEquipRules]。
	out.items = [PBEquipItem.make(&"item", PBEquipItem.Category.PHYSICAL, recipe, power_per_item)]
	return out


## 这张表是不是那条替身曲线（**没有分类匹配、对谁都生效**）。
##
## [PBEquipRules] 靠它决定要不要跳过分类匹配。做成「问表」而不是
## 在配置上再开一个开关：开关会和表分头设置，总有一天对不上，
## 而「合成表天生没有分类」是这张表自己的性质。
func is_synthetic() -> bool:
	return parts.size() == 1 and items.size() == 1


func item(item_id: StringName) -> PBEquipItem:
	for entry: PBEquipItem in items:
		if entry.id == item_id:
			return entry
	return null


## 造一张真表。加载器校验完 `.tres` 之后调这个。
static func of(part_ids: Array[StringName], item_list: Array[PBEquipItem]) -> PBEquipTable:
	var out := PBEquipTable.new()
	out.parts = part_ids
	out.items = item_list
	return out
