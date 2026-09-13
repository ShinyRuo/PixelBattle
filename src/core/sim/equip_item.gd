class_name PBEquipItem
extends Resource
## 一件**成品装备**的静态定义。§10 的第二级，M3-c。
##
## ## 三级合成树在这里的位置
##
## [codeblock]
## 配件（7 种，忍具箱随机出）→ 成品（3 个配件，按固定配方）→ 真武（3 件同款 + 卷轴）
## [/codeblock]
##
## 本类是中间那一级。**配方是固定的、按配件种类点名的**，
## 不是「随便三个配件换一件」—— 那个区别是这次改造的实质内容之一：
## 忍具箱随机出配件，而配方点名要哪几种，于是**一定会囤下用不上的配件**。
## M-1 的替身曲线里没有这个损耗，装备因此被系统性高估。
##
## ## 为什么它是 Resource
##
## 和 [PBCharacter]、[PBBond] 同一个理由：要存成 `data/` 下的 `.tres`，
## 检查器可视化编辑、git diff 可读、换皮只改数据（§14 铁律 5）。
## 加载发生在 core 外面（`ResourceLoader` 在 core 里禁用）。

## 装备分类（§10）。**决定这件装备挂在谁身上才生效。**
##
## §10 原话是「法术装挂物理角色身上不生效」，而这正是 M-1 那条
## 无差别全队倍率**高估装备、稀释 §03 属性系统**的根源：
## 替身曲线里装备对谁都一样有用，于是它成了「阵容深度」的完美替代品，
## 而阵容深度正是换人策略需要的东西。
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

## 持有者的战力加成（乘算，0.20 = +20%）。
##
## ## 为什么有些成品是 0
##
## §10 的六件成品里有两件的效果在当前战斗模型下**不产生任何伤害**：
##
## ## ⚠ 它现在是**估值分，不是效果** —— 效果在 [member mods] 里
##
## 排序（[method PBEquipRules.assign] 贪心给最强的那个）、过滤
## （合不出来就不摆上货架）、比价（[method PBValuation.equip_box_gain]）
## 这三处要一个标量「这件有多值钱」，而词条是一张表，比不出大小。
##
## ## 它曾经把两件装备钉死在 0 长达九个里程碑
##
## 原话是「吸血型 —— 己方单位不会死，回血没有去处」「格挡型 ——
## **敌人不还手**，没有伤害可挡」。那两句在 M3-c 是真的，
## 而**敌人从 M3.5-b / M5-7 起就会还手、己方从那时起就会死** ——
## 没人回头改，于是 6 件成品里 2 件恒为 0，它们的配件跟着下架。
##
## **这种事只能靠断言拦**：`tests/test_equip_data.gd` 有一条钉着
## **「有 [member mods] 却 `power <= 0`」不许出现** ——
## 那正是「有效果却被估值当成废物」的形状。
@export var power: float = 0.0

## 这件装备**真正给什么**（M12-h2）。形状是 `{词条键: 量}`，
## 两张词汇表都能写：[PBStatRules]（属性，算三围那一刻注入）和
## [PBPassiveRules]（行为，建人之后装）。
##
## ## 它取代了「+N% 战力」
##
## 在它之前一件装备就是一个乘在 [member PBAttacker.dps] 上的倍率，
## 而原版的装备全是**属性词条**（`攻击力+200 攻速+20% 力量+30 防御+10`）。
## 倍率那个形状表达不了它们 —— 玩家在属性栏里找不到「+20% 战力」
## 对应哪一个数，而「力量+30」要一路派生到血、攻击力、防御、攻速上。
##
## **降级照旧记账**：护甲穿透、忍术伤害、忍术抗性、吸血、
## 「几率抵挡 N 点普攻」这几条今天没有读点，所以那几件只落下了它们的属性那一半。
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
