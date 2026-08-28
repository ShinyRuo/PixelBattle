class_name PBBond
extends Resource
## 一组羁绊的静态定义。§09 的数据结构，M2-b。
##
## 和 [PBCharacter] 一样是 `Resource` 而不是 `RefCounted`，理由也一样：
## 羁绊表要存成 `data/bonds/*.tres`，**换皮时只改 `data/`，`src/core/` 一行不动**
## （§14 铁律 5）。加载 `.tres` 发生在 core 外面，core 只认这个类型。
##
## ## 档位为什么是三条平行数组而不是 `Array[PBBondTier]`
##
## §09 的规格写的是 `tiers: Array[PBBondTier]`。M2 只做**数值层**
## （功能档要大招、多目标、敌人位置操纵，那三样都在 M3），
## 所以一个档位现在只有「几个人」「加多少战力」「解锁哪个功能」三个标量。
##
## 为这三个标量再套一层嵌套 Resource，`.tres` 里会变成一堆 `SubResource`，
## 手写和 `git diff` 都难读，而这两样正是把数据放进 `.tres` 的全部理由。
## 等 M3 的功能档真需要「一个档位挂一串效果」时再升级成 [code]PBBondTier[/code]，
## 那时它承载的东西才配得上一层类型。
##
## ## 档位是「取到达的最高档」，不是逐档累加
##
## §09 的档位表（2 档数值 → 3 档功能 → 4 档强化功能）读的是**升级**，
## 不是叠加。所以 [member tier_power] 存的是**该档的总加成**，
## 不是相对上一档的增量。

## 怎么判断一个单位算不算这组羁绊的成员。
enum Match {
	## 按 [member member_ids] 点名。小队型 / 阵营型的命名羁绊走这条。
	MEMBERS,
	## 按属性。§09 的「属性型（同系）」兜底羁绊走这条 ——
	## 点名的话每换一次角色表都要同步改一遍成员表，漏改不报错。
	ELEMENT,
	## 匹配所有人。**只有 [method PBBondTable.synthetic] 用它。**
	##
	## 存在的唯一理由是让 M2-b 的结构层引入可以对拍：
	## 一组「所有人都算成员、每人一档」的羁绊，
	## 在数值上恰好等于 M-1 那条「每人 +6%、封顶 12 人」的替身曲线。
	## 换真羁绊表是下一步，那一步的数值变化必须能和这一步的重构分开看。
	EVERYONE,
}

## 全局唯一 id。代码里不出现羁绊名，一律走 id（§14 铁律 5）。
@export var id: StringName = &""

## 查语言表用的键。
@export var name_key: String = ""

@export var match_mode: Match = Match.MEMBERS

## [constant Match.MEMBERS] 时的成员名单，元素是 [member PBCharacter.id]。
@export var member_ids: Array[StringName] = []

## [constant Match.ELEMENT] 时匹配的属性。
@export var match_element: PBElement.Type = PBElement.Type.PHYSICAL

## 各档需要几个成员。**必须升序**，[method PBBondTable.add] 会查。
@export var tier_counts: Array[int] = []

## 各档给的战力加成（**该档的总加成**，不是增量）。与 [member tier_counts] 等长。
@export var tier_power: Array[float] = []

## 各档解锁的功能，空表示纯数值档。
##
## **M2 全是空的** —— 功能档（聚拢 / 吸附 / 定身 / 减速）要大招系统、
## 多目标分配、敌人位置操纵，三样都在 M3。字段先立着，是因为 §09 的硬性规范
## 「每个羁绊的最高档必须解锁一个机制」是这套设计的核心，
## 不留位置的话 M3 要动数据格式，已有的 `.tres` 全得改。
@export var tier_function_keys: Array[StringName] = []


## 这个单位算不算本组的成员。
func counts(unit: PBUnit) -> bool:
	if unit == null:
		return false
	return counts_character(unit.character)


## 这个**角色**算不算本组的成员。
##
## 和 [method counts] 分开，是因为估值要问「**假如**抽到这个角色，羁绊会涨多少」——
## 那时手上还没有对应的 [PBUnit]，只有角色表里的一条定义。
func counts_character(character: PBCharacter) -> bool:
	if character == null:
		return false
	match match_mode:
		Match.EVERYONE:
			return true
		Match.ELEMENT:
			return character.element == match_element
		_:
			return member_ids.has(character.id)


## 到场 [param active] 个成员时，激活的是第几档。**0 表示没激活。**
##
## 单独暴露档数而不是只给倍率，是因为 §06 的验收原话是
## 「派了羁绊掉几档，准备阶段能一眼看出」——「档」指的就是这个数。
func tier_at(active: int) -> int:
	var tier: int = 0
	for i: int in tier_counts.size():
		if active >= tier_counts[i]:
			tier = i + 1
		else:
			break
	return tier


## 到场 [param active] 个成员时给多少战力加成。没激活给 0。
func bonus_at(active: int) -> float:
	var tier: int = tier_at(active)
	if tier <= 0 or tier > tier_power.size():
		return 0.0
	return tier_power[tier - 1]


## 满档需要几个人。名单/属性池不够这个数时，这组羁绊的最高档是够不着的。
func full_tier_count() -> int:
	if tier_counts.is_empty():
		return 0
	return tier_counts[tier_counts.size() - 1]
