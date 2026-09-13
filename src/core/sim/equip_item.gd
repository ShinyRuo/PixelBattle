class_name PBEquipItem
extends Resource
## 一件**成品装备**的静态定义（§10）。
##
## [codeblock]
## 配件（7 种，忍具箱随机出）→ 成品（3 个配件，按固定配方）→ 真武（3 件同款 + 卷轴）
## [/codeblock]
##
## 本类是中间那一级。**配方按配件种类点名**，所以随机出的配件一定会囤下用不上的。
## 是 Resource：存成 `data/` 下的 `.tres`，换皮只改数据（铁律 5）。

## 装备分类（§10）。**决定这件装备挂在谁身上才生效**（法术装挂物理角色不生效）。
enum Category {
	PHYSICAL,  ## 物理装：只对物理属性角色生效
	MAGIC,  ## 法术装：只对五系角色生效
	TANK,  ## 坦克装：防御向，见 [member power] 的说明
}

## 全局唯一 id。**代码里不出现装备名，一律走 id**（§14 铁律 5）。
@export var id: StringName = &""

## 查语言表用的键。
@export var name_key: String = ""

@export var category: Category = Category.PHYSICAL

## 配方：要哪几个配件。**元素是配件 id，重复出现表示要多个。**
##
## 用一个平铺数组而不是 `{id: 数量}` 字典，是因为它要存进 `.tres` ——
## 数组在检查器里能直接编辑，嵌套字典不能。长度就是所需配件总数。
@export var recipe: Array[StringName] = []

## **估值分，不是效果** —— 效果在 [member mods] 里。
##
## 排序（[method PBEquipRules.assign]）、过滤（合不出来不上架）、比价
## （[method PBValuation.equip_box_gain]）要一个标量，而词条是一张表。
##
## **有 [member mods] 就必须 `power > 0`**（`tests/test_equip_data.gd` 钉着）：
## 为 0 的成品会被当成废物，它独占的配件跟着下架，而它不报错。
@export var power: float = 0.0

## 这件装备**真正给什么**，形状是 `{词条键: 量}`。两张词汇表都能写：
## [PBStatRules]（属性，算三围那一刻注入）和 [PBPassiveRules]（行为，建人之后装）。
##
## **降级记账**：护甲穿透、忍术伤害、忍术抗性、吸血、「几率抵挡 N 点普攻」没有读点，
## 那几件只落下了属性那一半。
@export var mods: Dictionary = {}


## 配方里要几个 [param part_id]。
func needs(part_id: StringName) -> int:
	var count: int = 0
	for entry: StringName in recipe:
		if entry == part_id:
			count += 1
	return count


## 这件装备对 [param element] 属性的角色生效吗（§10 的分类匹配）。
##
## 物理装配物理角色、法术装配五系角色。坦克装谁都不匹配 ——
## 当前的角色表里没有「坦克」这个身份，而且它的效果本来就是防御向的。
func fits(element: PBElement.Type) -> bool:
	match category:
		Category.PHYSICAL:
			return element == PBElement.Type.PHYSICAL
		Category.MAGIC:
			return element != PBElement.Type.PHYSICAL
		_:
			return false


## 造一件成品。测试和合成表用这个，省得手写 `.tres`。
static func make(
	item_id: StringName,
	item_category: Category,
	item_recipe: Array[StringName],
	item_power: float,
	item_name_key: String = ""
) -> PBEquipItem:
	var out := PBEquipItem.new()
	out.id = item_id
	out.category = item_category
	out.recipe = item_recipe
	out.power = item_power
	out.name_key = item_name_key if item_name_key != "" else String(item_id)
	return out
