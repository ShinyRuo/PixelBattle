class_name PBBondRules
extends RefCounted
## 羁绊结算（§09）。全部 static，无状态，零引擎依赖。
##
## **谁算数**：在场且没被派去做任务的人（§06），由 [method PBRunState.bonded_units]
## 挑出来，本类只负责拿到名单之后算。
##
## **各组相加，不相乘**：相乘的话多组收益指数叠加，「把能凑羁绊的卡全塞进去」
## 立刻变成唯一解。相加时每一组的边际收益恒定，玩家才会比较「这一组值不值得
## 为它换掉一个高战力位」。


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
	# **按角色数，不按卡数**：重复抽到的忍者是另一张卡（[method PBUnit.key]），
	# 照卡数算的话带三个同名忍者就凑满一组，而 §09 要的是凑齐**不同**的成员。
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


## 现在解锁了哪些功能档，`{ 载体角色 id: [功能键…] }`（§09）。
##
## [param bonded] 是**算档位的人**（在场减去派遣），[param deployed] 是**真上场的人**。
## 档位按前者数，功能按后者兑现 —— 不在场上的人没有大招，功能挂不上去。
##
## **值是数组**：一个角色同时是两组的载体时，单值字典会让后写的静默盖掉先写的。
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


## 满档的羁绊给**每个在场成员**各发了什么。
## 返回 `{角色 id: {被动键: 量}}`，词汇表见 [PBPassiveRules]。
##
## **两组给同一个人同一个键时量相加**，不是后一组盖前一组 ——
## 盖的话凑满两组只拿到一组的量，而它不报错。
## 两份名单的分工同 [method active_functions]。
static func active_passives(
	bonded: Array[PBUnit], deployed: Array[PBUnit], table: PBBondTable
) -> Dictionary:
	var out: Dictionary = {}
	if table == null:
		return out
	var on_field: Dictionary = {}
	for unit: PBUnit in deployed:
		on_field[unit.character.id] = true
	for bond: PBBond in table.all():
		if bond.member_functions.is_empty():
			continue
		if active_count(bond, bonded) < bond.full_tier_count():
			continue
		for who: StringName in bond.member_functions:
			if not on_field.has(who):
				continue
			var mine: Dictionary = out.get(who, {})
			for key: StringName in bond.member_functions[who]:
				var more: float = float(bond.member_functions[who][key])
				mine[key] = float(mine.get(key, 0.0)) + more
			out[who] = mine
	return out


## 满档的羁绊给**每个在场成员**打了哪些技能补丁。
## 返回 `{角色 id: {技能 id: {补丁键: 量}}}`，词汇表见 [PBSkillPatchRules]。
##
## 和 [method active_passives] 同构，但**同一个键按后来的那一份覆盖**：
## 补丁里有 `*_set` 这种「设成多少」的语义，相加说不通。
## 两组抢同一个技能同一个字段是设计上该避免的，真出现时按表顺序确定。
static func active_skill_patches(
	bonded: Array[PBUnit], deployed: Array[PBUnit], table: PBBondTable
) -> Dictionary:
	var out: Dictionary = {}
	if table == null:
		return out
	var on_field: Dictionary = {}
	for unit: PBUnit in deployed:
		on_field[unit.character.id] = true
	for bond: PBBond in table.all():
		if bond.member_skill_patches.is_empty():
			continue
		if active_count(bond, bonded) < bond.full_tier_count():
			continue
		for who: StringName in bond.member_skill_patches:
			if not on_field.has(who):
				continue
			var mine: Dictionary = out.get(who, {})
			for skill_id: StringName in bond.member_skill_patches[who]:
				var theirs: Dictionary = mine.get(skill_id, {})
				theirs.merge(bond.member_skill_patches[who][skill_id], true)
				mine[skill_id] = theirs
			out[who] = mine
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


## 挑出**带上场的那批卡**，按「战力 × 羁绊」贪心。
##
## 目标函数：`前 deploy_slots 个人的裸战力之和 × (1 + 羁绊加成)`。
## **用裸战力而不是对某一波的有效战力**：这是整局带着的队伍，
## 每波再在这批人里换克制系（[method PBStrategy.pick_by_effect]）。
##
## **贪心不是最优**：30 挑 16 是上亿种组合，贪心是几千次运算。
## 它会错过「单看每一步都不划算、凑齐才跳档」的组合 ——
## 那正是真人玩家要自己发现的东西，模拟玩家略笨在这里是合适的。
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


