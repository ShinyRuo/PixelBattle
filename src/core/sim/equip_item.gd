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
## - **吸血型**（造成伤害的一部分转成治疗）—— 己方单位不会死，回血没有去处
## - **格挡型**（一定概率挡下一次伤害）—— **敌人不还手**，没有伤害可挡
##
## 这两件照实填 0，**不把防御效果折算成伤害**。折算了就等于在模型里
## 凭空发明一份收益，而调参的人会拿着那份收益去定价。
## 等 [PBBattleSim] 有了「敌人还手」之后它们才会有值，那时改的是这里的数据。
@export var power: float = 0.0


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
