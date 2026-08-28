class_name PBBondRules
extends RefCounted
## 羁绊结算（§09）。全部 static，无状态，零引擎依赖。
##
## ## 谁算数
##
## §09 的生效规则：**出战席与待命台双场景全额生效、无衰减**，
## 但**派遣出去做任务的人羁绊暂时失效**（§06 新增）。
## 所以「算数的人」= 在场（出战 + 待命）且未被派遣的那批，
## 由 [method PBRunState.bonded_units] 挑出来，本类只负责拿到名单之后算。
##
## ## 加成是各组相加，不是相乘
##
## §09 说「同一角色可同时属于多个羁绊」。相乘的话，多组羁绊的收益会指数叠加，
## 「把能凑羁绊的卡全塞进去」立刻变成唯一解 —— 那正是 §05 记着的**原版漏洞**。
## 相加时每一组的边际收益恒定，凑第三组和凑第一组一样值钱，
## 玩家才会去比较「这一组值不值得为它换掉一个高战力位」。


## 一份名单激活了多少总战力加成。返回的是**加成本身**（0.0 = 没有羁绊），
## 不是倍率 —— 倍率由 [method PBRunState.bond_mult] 加 1.0。
static func power_bonus(units: Array[PBUnit], table: PBBondTable) -> float:
	if table == null:
		return 0.0
	var total: float = 0.0
	for bond: PBBond in table.all():
		total += bond.bonus_at(active_count(bond, units))
	return total


## 这份名单里有几个人算 [param bond] 的成员。
static func active_count(bond: PBBond, units: Array[PBUnit]) -> int:
	var count: int = 0
	for unit: PBUnit in units:
		if bond.counts(unit):
			count += 1
	return count


## 每组羁绊现在是第几档。**给准备阶段的界面用。**
##
## 返回 `{ 羁绊 id: 档数 }`，只含已激活的（档数 ≥ 1）。
## §09 的验收「每个羁绊的功能档在实战中可被玩家明确感知」先从这里落地：
## 玩家要看得见自己现在吃到几档、离下一档差几个人。
static func active_tiers(units: Array[PBUnit], table: PBBondTable) -> Dictionary:
	var out := {}
	if table == null:
		return out
	for bond: PBBond in table.all():
		var tier: int = bond.tier_at(active_count(bond, units))
		if tier > 0:
			out[bond.id] = tier
	return out


## 离 [param bond] 的下一档还差几个人。已满档返回 0。
##
## 这是「换一个人上场值不值」里最要紧的一格信息：差 1 个人的时候，
## 换上一张战力低但能补档的卡往往是赚的，而那笔账玩家自己算不出来。
static func to_next_tier(bond: PBBond, units: Array[PBUnit]) -> int:
	var active: int = active_count(bond, units)
	for count: int in bond.tier_counts:
		if active < count:
			return count - active
	return 0
