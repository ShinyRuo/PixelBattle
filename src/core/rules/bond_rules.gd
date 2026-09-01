class_name PBBondRules
extends RefCounted
## 羁绊结算（§09）。全部 static，无状态，零引擎依赖。
##
## ## 谁算数
##
## §09 的生效规则：**在场的人全额生效、无衰减**，
## 但**派遣出去做任务的人羁绊暂时失效**（§06 新增）。
## 所以「算数的人」= 在场且未被派遣的那批，
## 由 [method PBRunState.bonded_units] 挑出来，本类只负责拿到名单之后算。
##
## M3.5-i 删掉待命台之后「在场」就是出战席（[member PBRunState.field]），
## 于是这批人只比真上场的少了派出去做任务的那几个。
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
	# **按角色数，不按卡数**（M5-9）。重复抽到的忍者现在是另一个人
	# （[method PBUnit.key]），照卡数算的话带三个鸣人就能凑满一组羁绊 ——
	# 而 §09 要的是「凑齐**不同**的成员」，那才是它的全部难度。
	var seen: Dictionary = {}
	for unit: PBUnit in units:
		if bond.counts(unit):
			seen[unit.character.id] = true
	return seen.size()


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


## 现在解锁了哪些功能档，`{ 载体角色 id: [功能键…] }`。§09 / M3-f。
##
## ## 两份名单，各管一半
##
## [param bonded] 是**算档位的人**（在场，减去派遣出去的，§06/§09）；
## [param deployed] 是**真上场的人**。档位按前者数，功能按后者兑现 ——
## 不在场上的人没有大招，功能挂不上去。理由写在
## [member PBBond.tier_function_carriers]。
##
## **M3.5-i 删掉待命台之后这两份名单几乎重合**：差的只剩派出去做任务的人。
## 那条门槛因此从「腾一个出战位给载体」缩成「别把载体派去做任务」——
## 弱了一截，但方向没变，要不要补回来归数值回归。
##
## ## 为什么值是数组而不是一个键
##
## §09 说「同一角色可同时属于多个羁绊」。现在 5 组的载体互不相同，
## 但 M5 要扩到 12–15 组（晓、五影、日向、人柱力…），一个角色同时是
## 两组的载体只是时间问题。那时用单值字典会**静默丢掉一个功能** ——
## 后写的那组覆盖先写的，不报错，玩家只会觉得「这组羁绊好像没生效」。
static func active_functions(
	bonded: Array[PBUnit], deployed: Array[PBUnit], table: PBBondTable
) -> Dictionary:
	var out: Dictionary = {}
	if table == null:
		return out
	var on_field: Dictionary = {}
	for unit: PBUnit in deployed:
		on_field[unit.character.id] = true
	for bond: PBBond in table.all():
		var active: int = active_count(bond, bonded)
		var key: StringName = bond.function_at(active)
		if key == &"":
			continue
		var carrier: StringName = bond.function_carrier_at(active)
		if carrier == &"" or not on_field.has(carrier):
			continue
		if not out.has(carrier):
			out[carrier] = [] as Array[StringName]
		var keys: Array = out[carrier]
		if not keys.has(key):
			keys.append(key)
	return out


## 每组羁绊现在到场几个成员，`{ 羁绊 id: 人数 }`。
##
## 给估值用：**「再抽一张值多少」要对整个卡池问一遍**，
## 每问一次都重新数一遍到场人数是 O(卡池 × 羁绊 × 在场)，
## 而这个函数把「在场」那一维提出来只算一次。
static func counts_of(units: Array[PBUnit], table: PBBondTable) -> Dictionary:
	var out := {}
	if table == null:
		return out
	for bond: PBBond in table.all():
		out[bond.id] = active_count(bond, units)
	return out


## 假如再多一个 [param character]，羁绊加成会涨多少。
##
## [param counts] 是 [method counts_of] 的结果 —— 传进来而不是现算，
## 因为调用方要拿整个卡池各问一遍。
##
## **注意它算的是「多一个成员」，不是「多一张卡」。** 重复卡不增加成员数，
## 对羁绊没有贡献；上不了场的卡同样没有。两者都由调用方判断。
static func marginal_bonus(counts: Dictionary, table: PBBondTable, character: PBCharacter) -> float:
	if table == null or character == null:
		return 0.0
	# 变量别叫 delta —— core 纯度检查按词拦 `delta`（铁律 2：不读帧间隔），
	# 局部变量重名也会被拦下。这是有意的宁枉勿纵。
	var gained: float = 0.0
	for bond: PBBond in table.all():
		if not bond.counts_character(character):
			continue
		var active: int = int(counts.get(bond.id, 0))
		gained += bond.bonus_at(active + 1) - bond.bonus_at(active)
	return gained


## 挑出**带上场的那批卡**（出战席 + 待命台），按「战力 × 羁绊」贪心。M2-c。
##
## ## 为什么这是 M2 的正题
##
## M2-b 装上真羁绊表之后，「谁在场」第一次成了有内容的决策 ——
## 而在那之前它根本不是决策：[method PBRunState.bonded_units] 按**仓库顺序**
## 取前 N，也就是「你先抽到谁就带谁」。羁绊表再精致，选人是随机的，
## 会玩的和不会玩的拿到的加成就一样，§01 那条技能阶梯永远量不出来。
##
## ## 目标函数
##
## `前 deploy_slots 个人的裸战力之和 × (1 + 羁绊加成)`。
##
## 两处刻意的简化，都记在这里：
##
## 1. **用裸战力而不是对某一波的有效战力。** 在场名单是整局带着的队伍，
##    每波在这批人里换克制系上场（[method PBStrategy.pick_by_effect]），
##    所以选谁在场不该跟着某一波的属性走。
## 2. **第 deploy_slots 个之后的人只算羁绊、不算输出。** 那正是 §05 说的
##    「待命台不参战但羁绊全额生效」—— 板凳的唯一价值就是羁绊。
##
## ## 为什么是贪心而不是最优
##
## 30 张卡挑 16 张是 C(30,16) ≈ 1.45 亿种组合，每波都要算一次。
## 贪心是 `容量 × 候选 × 羁绊组数` ≈ 5000 次运算，差着五个数量级。
## 贪心会错过「单看每一步都不划算、凑齐才跳档」的组合 ——
## **那正是真人玩家要自己发现的东西**，模拟玩家比人略笨在这里是合适的。
static func choose_field(
	candidates: Array[PBUnit], capacity: int, deploy_slots: int, cfg: PBSimConfig
) -> Array[PBUnit]:
	var pool := candidates.duplicate()
	pool.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))

	var chosen: Array[PBUnit] = []
	var counts := counts_of([] as Array[PBUnit], cfg.bonds)
	var bonus: float = 0.0
	var power_sum: float = 0.0
	var taken := {}

	while chosen.size() < capacity and chosen.size() < pool.size():
		var best_index: int = -1
		var best_score: float = -1.0
		var best_bond: float = 0.0
		for i: int in pool.size():
			if taken.has(i):
				continue
			var unit: PBUnit = pool[i]
			var bond_gain: float = marginal_bonus(counts, cfg.bonds, unit.character)
			var power_after: float = power_sum
			if chosen.size() < deploy_slots:
				power_after += unit.power(cfg)
			var score: float = power_after * (1.0 + bonus + bond_gain)
			if score > best_score:
				best_score = score
				best_index = i
				best_bond = bond_gain
		if best_index < 0:
			break

		taken[best_index] = true
		var picked: PBUnit = pool[best_index]
		if chosen.size() < deploy_slots:
			power_sum += picked.power(cfg)
		chosen.append(picked)
		bonus += best_bond
		if cfg.bonds != null:
			for bond: PBBond in cfg.bonds.all():
				if bond.counts(picked):
					counts[bond.id] = int(counts.get(bond.id, 0)) + 1
	return chosen


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
