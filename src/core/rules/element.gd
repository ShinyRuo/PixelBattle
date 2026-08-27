class_name PBElement
extends RefCounted
## 五系属性与克制关系。施工策划案 §03 的地基，声明为不可改。
##
## 克制环：火 → 风 → 雷 → 土 → 水 → 火。`A → B` 表示 A 打 B 吃克制加成。
## 物理不参与克制环，对任何属性都是同一个恒定系数。
##
## 本类只回答「攻方属性对守方属性是什么关系」，**不回答倍率是多少**。
## 倍率是配平旋钮（尤其 `MULT_PHYSICAL`，§03 称之为全局最敏感的一个），
## 放在 [PBSimConfig] 里跟着参数扫描一起变。克制环几乎不动，倍率天天动，
## 两者住在一起迟早会有人为了调倍率误改环。

## 属性。PHYSICAL 是第六种，不在克制环上。
enum Type { FIRE, WIND, THUNDER, EARTH, WATER, PHYSICAL }

## 攻方对守方的关系。倍率由 [method PBSimConfig.damage_multiplier] 给出。
enum Relation {
	COUNTER,  ## 攻方克制守方
	WEAK,  ## 攻方被守方克制
	NEUTRAL,  ## 无关属性
	PHYSICAL,  ## 攻方是物理，不吃克制
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


## 攻方属性 [param attacker] 打守方属性 [param defender] 的克制关系。
static func relation(attacker: Type, defender: Type) -> Relation:
	if attacker == Type.PHYSICAL:
		return Relation.PHYSICAL
	if defender == Type.PHYSICAL:
		return Relation.NEUTRAL
	if COUNTERS[attacker] == defender:
		return Relation.COUNTER
	if COUNTERS[defender] == attacker:
		return Relation.WEAK
	return Relation.NEUTRAL


## 能克制 [param defender] 的那个属性 —— 即「打这一波该带什么」。
## §03 要求准备阶段显示「克制覆盖 2/5，风系空缺」，算的就是这个。
static func counter_of(defender: Type) -> Type:
	for attacker: int in RING:
		if COUNTERS[attacker] == defender:
			return attacker
	return Type.PHYSICAL
