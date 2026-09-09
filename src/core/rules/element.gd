class_name PBElement
extends RefCounted
## 属性与克制关系。施工策划案 §03 的地基，声明为不可改。
##
## 克制环：火 → 风 → 雷 → 土 → 水 → 火。`A → B` 表示 A 打 B 吃克制加成。
## 物理不参与克制环，对任何属性都是同一个恒定系数。
## **仙也不在环上，但它和物理正好相反** —— 见 [constant Type.SAGE]。
##
## 本类只回答「攻方属性对守方属性是什么关系」，**不回答倍率是多少**。
## 倍率是配平旋钮（尤其 `MULT_PHYSICAL`，§03 称之为全局最敏感的一个），
## 放在 [PBSimConfig] 里跟着参数扫描一起变。克制环几乎不动，倍率天天动，
## 两者住在一起迟早会有人为了调倍率误改环。
##
## ## 这张表是原版的，不是我们拍的
##
## 整张矩阵从《忍法战场》v1.5.80 的地图文件里解出来
## （`war3mapMisc.txt` 的 `DamageBonus*`，被作者改过、不是引擎默认值），
## 见 [url]Docs/原版数据_忍法战场v1.5.80.md[/url] §2。
## 五系那一环与我们此前自己拍的**一字不差**，倍率也正是 200% / 50%；
## 仙这一档是这次对齐时补上的。`test_element` 里有一条把整张矩阵逐格钉住。

## 属性。**前六个在环上或与环无关，SAGE 是第七个且规则完全不同。**
##
## [b]物理[/b]（PHYSICAL）是中立位：打谁都一样，谁打它也一样。
##
## [b]仙[/b]（SAGE）是它的反面 —— **打谁都吃满克制，谁打它都被减半**。
## 原版里同时拿到「攻仙 + 防仙」的只有已被我们删掉的 USR 神卡；
## 留下的三张各拿一半（佩恩、兜是攻仙，重吾是防仙），那是原版有意的拆分。
##
## **新属性只能追加在末尾。** 这几个值直接存进 `data/` 的 `.tres`
## 与存档里，往中间插一个会让所有既有数据整体错位一格，
## 而它不报错 —— 表现是「所有角色的属性都变成了下一个」。
enum Type { FIRE, WIND, THUNDER, EARTH, WATER, PHYSICAL, SAGE }

## 攻方对守方的关系。倍率由 [method PBSimConfig.damage_multiplier] 给出。
##
## **五系之间有五档不是三档**（M12-a 对齐原版时改的），
## 而且它们是[method ring_distance]的纯函数 —— 见那个方法顶上那张表。
##
## **同系并进 WEAK，不单开一档。** 原版这两格是同一个数（0.50），
## 而合成一档换到的是：卡面那套「亮边 / 压暗」的显示
## （[method PBUnitTile._edge_for]）不用再加一个分支 ——
## 漏加分支的表现是「同系的卡看起来一切正常，实际只打五成」。
## 要把这两格分开调的那天再拆，那时显示那边也必须一起改。
##
## **仙对非仙、非仙对仙同理不另设档位**：前者就是 COUNTER、后者就是 WEAK，
## 倍率与环上那两档逐位相同（原版矩阵里也是同一个数）。
enum Relation {
	COUNTER,  ## 2.00 —— 环距 1「我克它」，或「攻方是仙、守方不是」
	WEAK,  ## 0.50 —— 环距 4「它克我」、环距 0「同系」，或「守方是仙」
	NEUTRAL,  ## 1.00 —— 环距 3，隔两个，谁也不沾谁
	PHYSICAL,  ## 1.00 —— 攻方是物理，不上环
	DISTANT,  ## 0.75 —— 环距 2，隔一个。**原版有这一档，我们此前没有**
	SAGE_MIRROR,  ## 1.50 —— 仙打仙。既不是克制也不是无关
}

## 克制环。键是攻方属性，值是被它克制的那一个。
## 五个属性各出现一次做键、一次做值 —— 这是个单环排列，test_element 会验。
const COUNTERS := {
	Type.FIRE: Type.WIND,
	Type.WIND: Type.THUNDER,
	Type.THUNDER: Type.EARTH,
	Type.EARTH: Type.WATER,
	Type.WATER: Type.FIRE,
}

## 参与克制环的五个属性，数组顺序即环的顺序。不含 PHYSICAL。
## 声明成 Array[int] 而不是 Array[Type]：GDScript 的类型化数组不支持枚举，
## 枚举底层就是 int，这里退回 int 是语言限制不是偷懒。
const RING: Array[int] = [Type.FIRE, Type.WIND, Type.THUNDER, Type.EARTH, Type.WATER]

## 一个**普通**角色或一波怪可以是哪些属性 —— 五系环 + 物理，**不含仙**。
##
## 需要这份名单，是因为「枚举里的每个值都是一个合法的普通属性」这句话
## 从仙加进来的那天起就不成立了，而在那之前到处都在用 `Type.size()` 铺格子
## （[method PBCharacterTable.synthetic] 就是一处）。照 `size()` 铺的话，
## 合成卡池会凭空多出一批**克制一切**的仙系角色，
## **而它不报错** —— 只是所有拿合成表跑出来的配平结论一起失真。
##
## 仙不进这份名单不是漏了：它是三个特定角色身上的东西，
## 不是一个可以随便发牌的桶。
const PICKABLE: Array[int] = [
	Type.FIRE,
	Type.WIND,
	Type.THUNDER,
	Type.EARTH,
	Type.WATER,
	Type.PHYSICAL,
]


## 攻方在环上要走几步才走到守方 —— 两个都在环上时是 0–4，否则 −1。
##
## **五系之间的全部倍率都是这个数的函数**，原版 25 组配对逐格验证过：
##
## [codeblock]
## 环距 0  同系      0.50   ← 带同系不是「没加成」，是主动错误
## 环距 1  我克它    2.00
## 环距 2  隔一个    0.75
## 环距 3  隔两个    1.00
## 环距 4  它克我    0.50
## [/codeblock]
##
## 选对与选错因此差 **4 倍**（2.00 对 0.50），而不是我们此前的 2 倍。
static func ring_distance(attacker: Type, defender: Type) -> int:
	var from: int = RING.find(attacker)
	var to: int = RING.find(defender)
	if from < 0 or to < 0:
		return -1
	return (to - from + RING.size()) % RING.size()


## 攻方属性 [param attacker] 打守方属性 [param defender] 的克制关系。
##
## **这几条的顺序不能动。** 「守方是仙」必须排在物理那两条之前 ——
## 排在后面的话，物理打仙会走成 [constant Relation.PHYSICAL]（1.00）
## 而不是被减半，而它不报错，只表现为「重吾好像没那么肉」。
static func relation(attacker: Type, defender: Type) -> Relation:
	if attacker == Type.SAGE:
		return Relation.SAGE_MIRROR if defender == Type.SAGE else Relation.COUNTER
	if defender == Type.SAGE:
		return Relation.WEAK
	if attacker == Type.PHYSICAL:
		return Relation.PHYSICAL
	if defender == Type.PHYSICAL:
		return Relation.NEUTRAL
	match ring_distance(attacker, defender):
		1:
			return Relation.COUNTER
		2:
			return Relation.DISTANT
		3:
			return Relation.NEUTRAL
		_:
			# 环距 0（同系）与 4（它克我）在原版是同一个数，见 [enum Relation]。
			return Relation.WEAK


## 能克制 [param defender] 的那个属性 —— 即「打这一波该带什么」。
## §03 要求准备阶段显示「克制覆盖 2/5，风系空缺」，算的就是这个。
##
## **只在五系环上找，永远不答「仙」。** 仙确实克制一切，
## 所以照字面算的话每一波的答案都是仙 —— 而那是一句没有信息量的建议：
## 全名册只有两个仙系攻击的角色，玩家凑不出「每波都带仙」。
## 这个函数答的是「去仓库里挑谁」，不是「理论上谁最克它」。
static func counter_of(defender: Type) -> Type:
	for attacker: int in RING:
		if COUNTERS[attacker] == defender:
			return attacker
	return Type.PHYSICAL
