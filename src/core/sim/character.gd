class_name PBCharacter
extends Resource
## 一个角色的静态定义。§09 的数据结构，M2-a。
##
## ## 为什么它是 Resource 而不是 RefCounted
##
## 因为角色表要存成 `data/` 下的 `.tres`：检查器里可视化编辑、git diff 可读、
## **换皮时只改 `data/` 与语言表，`src/core/` 一行不动**（§14 铁律 5）。
## 只有 Resource 能被序列化成 `.tres`。
##
## `extends Resource` 不违反「core 零引擎依赖」—— 它不是 Node、不碰场景树、
## 不读 delta。真正被 core 纯度检查挡住的是 `ResourceLoader`，
## **所以「加载 .tres」这件事必须发生在 core 外面**，core 只认这个类型。
## 那正是想要的分工：core 不知道文件从哪来，测试可以直接造表。
##
## ## 和 [PBUnit] 的区别
##
## 本类是**角色本身**（不可变，全局唯一一份）；[PBUnit] 是**玩家手上的那张卡**
## （有张数、有星级，一局一份）。两者一对多。
##
## ## 已知的省略（§09 写了但 M2-a 不做）
##
## - `base_stats: PBStats` —— 现在战力只有一条 `rarity_power` 阶梯，没有多维属性
## - `skill_ids: Array[StringName]` —— 技能/大招系统在 M3
##
## 两者都等有了对应系统再加，现在放进来只是占位字段，会误导人以为它们生效了。

## 全局唯一 id。**代码里不出现角色名，一律走 id**（§14 铁律 5）。
##
## 它同时是 [method PBUnit.key] 的返回值，也就是仓库字典的键，
## 以及 §12 存档里记录「我有哪些卡」的那个值。改 id 等于让老存档认不出卡。
@export var id: StringName = &""

## 查语言表用的键。显示名只在这一层出现，`src/` 其余地方一个字都不该有。
@export var name_key: String = ""

## 查图集用的键。M2 是白模阶段，先留着不用（真美术在 M5）。
@export var icon_key: String = ""

## 输出属性（§03）。
##
## **注意 §03 的铁律：真正的 `element` 是挂在伤害事件上的，不是挂在单位上。**
## 现在一个角色只有一个技能，两者恰好重合。M3 接真技能表时必须拆开，
## 否则「迪达拉本体土属性但大招是火系」这类角色做不出来。
@export var element: PBElement.Type = PBElement.Type.PHYSICAL

## 稀有度（§08）。
##
## 类型借用 [enum PBUnit.Rarity]。§09 的规格里叫 `PBRarity.Type`，
## 改名是纯粹的调用点搬迁、零行为变化，等有必要时再做。
@export var rarity: PBUnit.Rarity = PBUnit.Rarity.R


## 造一个角色。字段全部只读语义 —— 造完不要再改。
static func make(
	character_id: StringName,
	character_element: PBElement.Type,
	character_rarity: PBUnit.Rarity,
	character_name_key: String = ""
) -> PBCharacter:
	var out := PBCharacter.new()
	out.id = character_id
	out.element = character_element
	out.rarity = character_rarity
	out.name_key = character_name_key if character_name_key != "" else String(character_id)
	return out
