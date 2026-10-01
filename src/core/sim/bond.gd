class_name PBBond
extends Resource
## 一组羁绊的静态定义（§09）。
##
## 是 Resource：存成 `data/bonds/*.tres`，换皮只改数据（铁律 5），加载在 core 外面。
##
## 档位是三条平行数组（人数 / 加成 / 功能）而不是嵌套 Resource：嵌套在 `.tres` 里是一堆
## `SubResource`，手写和 `git diff` 都难读。**取到达的最高档，不逐档累加**，
## [member tier_power] 存的是该档的总加成。
##
## **`data/bonds/` 里每组只有一档：不凑齐就不生效**（玩家定的）。这个类仍然支持多档：
## [method PBBondTable.synthetic] 那条对拍曲线是一人一档的。

## 怎么判断一个单位算不算这组羁绊的成员。
enum Match {
	## 按 [member member_ids] 点名。小队型 / 阵营型的命名羁绊走这条。
	MEMBERS,
	## 按属性。§09 的「属性型（同系）」兜底羁绊走这条 ——
	## 点名的话每换一次角色表都要同步改一遍成员表，漏改不报错。
	ELEMENT,
	## 匹配所有人。**只有 [method PBBondTable.synthetic] 用它**（替身曲线的对拍）。
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

## 各档解锁的功能，空表示纯数值档。取值见 [PBBondFunctionRules] 的那组常量。
@export var tier_function_keys: Array[StringName] = []

## 各档的功能由**谁**来带，元素是 [member PBCharacter.id]，与 [member tier_function_keys] 等长。
##
## **一组只出一个载体**：发给全组的话满档会同时有好几发聚拢，功能就变回了乘以人数的倍率 ——
## 一发聚拢是一次要判断时机的操作，四发只是更高的伤害。
##
## **载体没上场，功能就不兑现**：功能挂在载体的大招上，不上场的人没有大招。
@export var tier_function_carriers: Array[StringName] = []

## 满档时**每个在场成员各拿自己那一份**。形状是 `{角色 id: {被动键: 量}}`，词汇表见 [PBPassiveRules]。
##
## 原版每组给每个成员各发一份**不一样**的效果。这不违反「一组只出一个载体」：
## 那条防的是给每人发同一份倍率，而这里给每人发不同的机制。倍率型仍然不许人手一份。
## 不在场就不兑现。
@export var member_functions: Dictionary = {}
## 每成员的整波开场效果；数值与静态成员补丁不得重复配置。
@export var member_buffs: Dictionary = {}

## 满档时**每个在场成员各自的技能补丁**。形状是 `{角色id: {技能id: {补丁键: 量}}}`，
## 词汇表见 [PBSkillPatchRules]。原版羁绊的主形状（「强化本人的某个具名技能」）。
##
## 和 [member member_functions] 分两个字段：一个改的是人，一个改的是他那一发 ——
## 落点、词汇表、门槛（补丁还要求他真的配了那个技能）都不同。
@export var member_skill_patches: Dictionary = {}


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


## 到场 [param active] 个成员时解锁哪个功能。空表示这一档是纯数值档。
func function_at(active: int) -> StringName:
	var tier: int = tier_at(active)
	if tier <= 0 or tier > tier_function_keys.size():
		return &""
	return tier_function_keys[tier - 1]


## 到场 [param active] 个成员时，功能由哪个角色带。空表示没有功能或没指定载体。
func function_carrier_at(active: int) -> StringName:
	var tier: int = tier_at(active)
	if tier <= 0 or tier > tier_function_carriers.size():
		return &""
	return tier_function_carriers[tier - 1]


## 满档需要几个人。名单/属性池不够这个数时，这组羁绊的最高档是够不着的。
func full_tier_count() -> int:
	if tier_counts.is_empty():
		return 0
	return tier_counts[tier_counts.size() - 1]
