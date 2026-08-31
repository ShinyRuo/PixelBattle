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

## 各档解锁的功能，空表示纯数值档。取值见 [PBBondFunctionRules] 的那组常量。
##
## M2 全是空的（那时大招系统还不存在）；**M3-f 填上了 5 组命名羁绊**。
@export var tier_function_keys: Array[StringName] = []

## 各档的功能由**谁**来带，元素是 [member PBCharacter.id]，与
## [member tier_function_keys] 等长。空表示这一档没有功能。
##
## ## 为什么功能要指定载体，而不是全组共享
##
## §09 的原话是「李洛克大招获得聚拢」「鹿丸大招定身」——**一个组只出一个载体**。
## 发给全组的话，凯班满档会同时有 4 发聚拢，功能就变成了乘以人数的倍率，
## 而 §09 立功能档的全部理由正是**让高手的优势离开倍率、进入机制**
## （见本节末尾那条结构性冲突）。一发聚拢和四发聚拢是两种东西：
## 前者是一次要判断时机的操作，后者只是更高的伤害。
##
## ## 载体没上场，功能就不兑现
##
## 羁绊的**数值**档按「在场」算（§09），但功能挂在载体的大招上，
## 而不上场的人没有大招。所以功能档多一条门槛：
## 凑齐人数 **且** 载体真的在打这一波。
##
## **M3.5-i 之前这条门槛更重**：那时在场 = 出战席 + 待命台，
## 把载体排进出战席意味着挤掉一个人。待命台删掉之后在场就是出战席，
## 门槛只剩「别把载体派去做任务」。方向没变，力度弱了 ——
## 要不要补回来归数值回归。抽不到载体的局仍然不算废：
## §11 的七尾是纯聚拢大招，正是为「不依赖特定羁绊的聚怪路径」而存在的。
@export var tier_function_carriers: Array[StringName] = []


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
