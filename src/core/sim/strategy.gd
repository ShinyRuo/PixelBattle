class_name PBStrategy
extends RefCounted
## 玩家决策的接口。脚本玩家实现它，跑出不同玩法流派的极限波次。
##
## 这是一个「端口」：[PBRunSim] 每波向它要三个答案 —— **钱怎么花、谁上场、接不接任务**。
## 接口在 `src/core/`，具体流派在 `src/tools/strategies/`，**方向不能反**。
##
## `deploy` 默认按有效战力（含克制）取前 N：§03 的克制加成只有每波真的换上克制系才吃得到，
## 这是模型下的最优打法。想测「不换人会怎样」的流派去覆盖它。

## 派遣策略。§06 的「这一波我要羁绊，还是要钱」。
enum Dispatch {
	NEVER,  ## 从不派遣，永远保满羁绊
	ALWAYS,  ## 有任务就接，钱最大化
	SMART,  ## BOSS 波前一波收手，其余照接
}

## 带谁上场。**技能阶梯的主要来源**：羁绊是乘法级杠杆，只有「带谁」是个真决策时才提供杠杆。
enum Field {
	## 只按裸战力带人。**不会凑羁绊的玩家** —— 羁绊全靠撞上。
	RAW_POWER,
	## 按「战力 × 羁绊」带人。**会凑羁绊的玩家**，见 [method PBBondRules.choose_field]。
	BOND_AWARE,
}

## 流派名，进 CSV 的 `strategy` 列。
var id: StringName = &"base"

var dispatch_policy: Dispatch = Dispatch.SMART

## 开局选哪只尾兽（§11）。**空 = 不带**，那是对照组。
##
## 为什么默认不带：接上尾兽这一步不该顺手改动所有既有的配平数字 ——
## 那样「尾兽值多少」和「配平漂了多少」就分不开了。
## 扫描用 `batch_sim --beast <id>` 逐只跑一遍，
## 而 §11 要的那条判据（**机制型不能被数值型挤掉**）就是这九次的排序。
##
## 正式上架时这里要翻成一个真 id，见路线图的待决策表。
var beast_id: StringName = &""

## 尾兽升到几级就停（§11：`400 × 1.6^Lv`，上限 10）。**0 = 不升级。**
##
## 做成一个目标等级而不是让 [PBValuation] 给尾兽定价，是有意的：
## 给机制型尾兽定价要先知道「一次聚拢值多少波次」，
## **而那正是这一步要量的东西** —— 先定价等于拿一个还不知道的数去决定买不买，
## 而且那个价必然偏向数值型（光环是现成的 DPS 倍率，聚拢不是），
## 正好是 §11 警告的那种挤压。
##
## 固定目标等级则对九只一视同仁，横向比较因此干净。
var beast_level_target: int = 0

## 默认不会凑羁绊 —— 大多数流派是「某种打法」的对照组，不是「会玩的玩家」。
##
## **界面上没有入口，这是有意的**：一键换半支队伍而屏幕上什么都不解释。
## **字段本身是批量扫描的仪器**：`bond_blind` 和 `rational` 只差这一个字段，
## 两者的比值就是羁绊贡献的技能阶梯（§09 验收），删了等于把验收删了。
var field_policy: Field = Field.RAW_POWER


## 准备阶段花钱。抽卡、升科技、上经济位都在这里做。
##
## 子类必须覆盖。基类什么都不做 —— 一个不花钱的玩家也是合法的对照组。
func prepare(_state: PBRunState, _wave: PBWave, _cfg: PBSimConfig, _rng: PBRngStreams) -> void:
	pass


## 开局带哪只尾兽。**整局只问一次**（§11：开局选定、全程不变）。
##
## 表里没有这个 id 就当没带 —— 命令行敲错了名字时，
## 静默按「不带」跑总好过静默按「随便哪只」跑：前者跑出来的是对照组，
## 数字明显偏低，一眼看得出不对；后者混在九次扫描里认不出来。
func choose_beast(cfg: PBSimConfig) -> StringName:
	if beast_id == &"" or cfg.beasts == null or cfg.beasts.by_id(beast_id) == null:
		return &""
	return beast_id


## 升尾兽等级，一直升到 [member beast_level_target] 或者钱不够为止。
##
## **每波准备阶段调一次**，由 [method PBRunSim.plan_wave] 统一调用而不是
## 让每个流派各自记得调 —— 漏调一个流派不会报错，只会让那一格的扫描
## 悄悄跑的是 Lv1，而九只尾兽横向比较正是靠这一格对齐。
func upgrade_beast(state: PBRunState, cfg: PBSimConfig) -> void:
	if state.beast_id == &"":
		return
	while state.beast_level < mini(beast_level_target, cfg.beast_level_max):
		var cost := PBBeastRules.upgrade_cost(state.beast_level, cfg)
		if cost < 0 or not state.spend(cost):
			return
		state.beast_level += 1


## 选出本波上场的单位。
##
## 玩家钦定了名单（[member PBRunState.lineup]）就照那份来，
## 否则取对本波有效战力最高的前 N 个 —— 那是脚本玩家和自动模式走的路。
func deploy(state: PBRunState, wave: PBWave, cfg: PBSimConfig) -> Array[PBUnit]:
	# 判据是 [member PBRunState.lineup_manual] 而不是「名单空不空」——
	# 玩家可以把人全拖下场，那时名单是空的但仍然是手排的。
	if not state.lineup_manual:
		return pick_by_effect(state, wave, cfg, open_slots(state, cfg))
	# 仍然要过一遍 `bring_to_field`：在场名单（羁绊按它算）必须包含钦定的人，
	# 漏了就会出现「点上场了但羁绊不算他」——不报错，只是数字不对。
	bring_to_field(state, cfg)
	return lineup_units(state, cfg)


## 手动名单对应的卡。名单里已经卖掉/不存在的 id 会被跳过。
##
## 超出出战席容量的部分**截掉而不是报错**：人口科技可以降级吗？不能，
## 但 `open_slots` 会随经济位增加而变小 —— 玩家上了一个经济位之后，
## 上一波钦定的六人名单就装不下了。截掉是唯一不会静默出错的做法。
func lineup_units(state: PBRunState, cfg: PBSimConfig) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	# 上限是 [method PBRunState.field_slots]（出任务的人不占人口）。用 `open_slots` 的话，
	# 派两个人出去之后钦定名单会被截掉两个，而被截掉的不一定是出任务的那两个。
	var slots: int = state.field_slots(cfg)
	for key: StringName in state.lineup:
		if out.size() >= slots:
			break
		var unit := state.roster.get(key, null) as PBUnit
		if unit != null:
			out.append(unit)
	return out


## 玩家改了出战席。[param manual] 传 false 就是**交回自动排**。
##
## ## 为什么「交回自动」不能用空数组表示
##
## 玩家可以把人**全部拖下场** —— 那是一个合法的手排结果（空出战席），
## 和「不排了，你按战力挑吧」是两回事。两者混用的话，
## 拖空之后下一次刷新会把整队自动填回来，看起来像编队页在跟人作对。
##
## 走这里而不是让界面直接写 [member PBRunState.lineup]，理由和花钱一样
## （见 [PBBattleView] 的 `_on_purchase`）：状态只由这一层的原语改，
## 界面自己动字段迟早会漏掉配套的清理，而那种不同步不报错。
## [param by_hand] 默认 true —— **调用方是玩家的操作**（拖放、指令卡）。
## 界面那条「替玩家维护名单」的路要传 false，见 [member PBRunState.lineup_by_hand]。
func set_lineup(
	state: PBRunState, units: Array[PBUnit], manual: bool = true, by_hand: bool = true
) -> void:
	state.lineup_manual = manual
	if by_hand:
		state.lineup_by_hand = true
	state.lineup.clear()
	if not manual:
		return
	for unit: PBUnit in units:
		state.lineup.append(unit.key())


## 接不接这个任务。[param grade] 是 [constant PBEconomyRules.QUEST_TABLE] 的行号。
func accept_quest(state: PBRunState, wave: PBWave, grade: int, cfg: PBSimConfig) -> bool:
	if dispatch_policy == Dispatch.NEVER:
		return false
	if PBEconomyRules.quest_cost_units(grade) > dispatch_available(state, cfg):
		return false
	if dispatch_policy == Dispatch.ALWAYS:
		return true
	# SMART：BOSS 波前一波收手，把羁绊留满。§06 说这会让节奏自然产生起伏。
	return (wave.index + 1) % PBWaveRules.BOSS_EVERY != 0


## 出战席里还剩几个位置能放输出。实现在 [method PBRunState.open_slots] ——
## 界面层也要问同一个问题，公式只能有一份。
func open_slots(state: PBRunState, cfg: PBSimConfig) -> int:
	return state.open_slots(cfg)


## 现在有几个人派得出去做任务。实现在 [method PBRunState.dispatch_available] ——
## 界面层也要问同一个问题，公式只能有一份。
func dispatch_available(state: PBRunState, cfg: PBSimConfig) -> int:
	return state.dispatch_available(cfg)


## 挑出这一波**带上场**的卡，并记进 [member PBRunState.field]。
##
## 全部 `pick_by_*` 都从这里取候选。玩家钦定的人**优先占位**，剩下的格子才按策略补 ——
## 否则会出现「点上场了但羁绊不算他」。
##
## [param wave_element] 传负数表示「按裸战力排」（对照组）。**必须看本波属性**：
## 在场就是出战席，这一步不看属性的话「每波换上克制系」就没有发生的余地，
## 属性系统在扫描里一分钱都不值，而它不报错。
func bring_to_field(
	state: PBRunState, cfg: PBSimConfig, wave_element: int = -1
) -> Array[PBUnit]:
	# 同 [method lineup_units]：出任务的那几个不占人口。
	var capacity: int = state.field_slots(cfg)
	var chosen: Array[PBUnit] = lineup_units(state, cfg)
	# **玩家亲手排过之后就不再往空位里补人**：补进来的只进 `field`、进不了 [method deploy]
	# 返回的名单，羁绊会算上一个根本不上场的人。空位是他自己留的。
	# 新抽到的卡另有一条路（[method PBCardMoves.set_on_field]），只填空位。
	if state.lineup_by_hand:
		state.set_field(chosen)
		return chosen
	var taken: Dictionary = {}
	for unit: PBUnit in chosen:
		taken[unit.key()] = true

	var rest: Array[PBUnit]
	if field_policy == Field.BOND_AWARE:
		# 这一支不看本波属性（在场名单是整局带着的队伍），所以凑羁绊的玩家等于放弃了换克制系 ——
		# §03 换人与 §09 凑羁绊抢同一批位子，归数值回归。
		rest = PBBondRules.choose_field(state.all_units(), capacity, capacity, cfg)
	elif wave_element >= 0:
		rest = state.all_units()
		var element := wave_element as PBElement.Type
		rest.sort_custom(
			func(a: PBUnit, b: PBUnit) -> bool:
				return a.effective_power(element, cfg) > b.effective_power(element, cfg)
		)
	else:
		rest = state.sorted_by_power(cfg)
	for unit: PBUnit in rest:
		if chosen.size() >= capacity:
			break
		if not taken.has(unit.key()):
			chosen.append(unit)
	state.set_field(chosen)
	return chosen


## 按「对本波的有效战力」取前 [param slots] 个 —— 即每波换上克制系。
func pick_by_effect(state: PBRunState, wave: PBWave, cfg: PBSimConfig, slots: int) -> Array[PBUnit]:
	var pool := bring_to_field(state, cfg, int(wave.element))
	pool.sort_custom(
		func(a: PBUnit, b: PBUnit) -> bool:
			return a.effective_power(wave.element, cfg) > b.effective_power(wave.element, cfg)
	)
	return pool.slice(0, maxi(slots, 0))


## 按「裸战力」取前 [param slots] 个，完全不看属性。
## 这是隔离「换人」效应的对照组：它和 [method pick_by_effect] 的差值，
## 就是 §03 整套属性系统在数值上真正值多少。
func pick_by_raw_power(state: PBRunState, cfg: PBSimConfig, slots: int) -> Array[PBUnit]:
	var pool := bring_to_field(state, cfg)
	pool.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))
	return pool.slice(0, maxi(slots, 0))


## 只从指定属性里取前 [param slots] 个。凑不满就有几个上几个。
func pick_by_element(
	state: PBRunState, element: PBElement.Type, cfg: PBSimConfig, slots: int
) -> Array[PBUnit]:
	var pool: Array[PBUnit] = []
	for unit: PBUnit in bring_to_field(state, cfg):
		if unit.element == element:
			pool.append(unit)
	pool.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))
	return pool.slice(0, maxi(slots, 0))


## 抽一张卡并入库 —— **掏钱摆出三张，再自己挑一张**（§08）。
## 规则那一半在 [PBShopRules]，这里只剩决定：挑第几张。
func pull_once(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> bool:
	if not PBShopRules.open_offer(state, wave, cfg, rng):
		return false
	return PBShopRules.take_offer(state, _choose_from_offer(state.pending_offer, cfg))


## 三张里挑哪一张。**默认按裸战力挑**，够用但不聪明 ——
## 会算账的玩家该同时看羁绊和克制覆盖，那是 `rational` 该覆盖的事。
##
## 名字带下划线是因为它是一个**给子类覆盖的钩子**，不是给外面调的：
## 界面走的是 [PBShopRules] 那两条，玩家自己就是那个 `_choose_from_offer`。
func _choose_from_offer(offer: Array[PBUnit], cfg: PBSimConfig) -> int:
	var best: int = 0
	for i: int in offer.size():
		if offer[i].power(cfg) > offer[best].power(cfg):
			best = i
	return best


## 把剩下的钱换成战力，一直花到买不动为止。`balanced` 与 `pure_power` 共用，
## 这样两者的差别只剩「升不升金币科技」这一个变量，差值才读得出意义。
##
## 优先级是有依据的，不是随手排的：
##
## 1. **训练科技比单抽便宜时先买**（挑最便宜的那一条）—— 确定的词条好过一发方差极大的抽卡
## 2. **卡池没抽满就抽卡** —— 新卡是全新战力，重复卡只加星级，差一个数量级
## 3. **抽满了转装备** —— 抽卡的边际收益此时已趋近于零，而装备在装满整队前
##    每一件都实打实。这个拐点就是 §10 存在的经济学意义
## 4. **装备也满了再回去抽卡刷星级** —— 边际收益低，但总比钱烂在手里强
func spend_on_power(
	state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams, training_target: int
) -> void:
	while true:
		var branch := _cheapest_training(state, cfg, training_target)
		var tech_first: bool = (
			branch != &""
			and PBEconomyRules.tech_cost(branch, state.training_level(branch), cfg) <= cfg.gacha_cost
		)
		if tech_first:
			if not buy_tech(state, branch, cfg):
				return
		elif gacha_still_pays(state, cfg) or equipment_is_full(state, cfg):
			if not pull_once(state, wave, cfg, rng):
				return
		elif not buy_equip_part(state, cfg, rng):
			return


## 抽卡是否仍然比装备划算。
##
## 判据是**位置坐不坐得满**，不是卡池抽没抽完：手上有两倍席位容量的卡之后，
## 再多一张几乎挤不进上场名单，边际收益断崖式下跌；而装备只要席位没装满就一直有效。
func gacha_still_pays(state: PBRunState, cfg: PBSimConfig) -> bool:
	return state.roster.size() < state.deploy_capacity(cfg) * 2


## 开一个忍具箱（§10）。买不起返回 false。
##
## 后期金币的主要去处：抽卡在卡池抽满后边际收益趋近于零，装备在装满整队前每件都实打实。
## **出货走 `gacha` 流**（铁律 3：花钱买的随机归它）。
func buy_equip_part(state: PBRunState, cfg: PBSimConfig, rng: PBRngStreams) -> bool:
	var pool: Array[StringName] = cfg.equipment.parts
	if pool.is_empty():
		return false
	if not state.spend(cfg.equip_part_cost):
		return false
	PBEquipRules.add_part(state.equip_parts, pool[rng.gacha.randi_range(0, pool.size() - 1)])
	return true


## 出战席是否已经装备到满，再买就溢出了。
##
## 数的是**合得出来**的成品件数，不是「配件总数 ÷ 配方大小」——
## 真配方点名要哪几种，囤着一堆用不上的配件也合不出东西来。
##
## 已知的一处宽松：合出来但没人吃得下的成品也算进去了。
## 那只会让玩家**更早**停手，而 [PBStratRational] 另有一道估值闸
## （吃不下时 [method PBValuation.equip_box_gain] 直接返回 0），
## 所以这个近似不会把钱花到没用的地方去。写死数的话反而要复制一遍分配逻辑，
## 而这个函数在批量扫描里一波要被调几十次。
func equipment_is_full(state: PBRunState, cfg: PBSimConfig) -> bool:
	var deployed := PBValuation.deployed_by_raw_power(state, cfg)
	if deployed.is_empty():
		return true
	var owned := PBEquipRules.craftable(state.equip_parts, cfg.equipment)
	var total: int = 0
	for item_id: StringName in owned:
		total += int(owned[item_id])
	return total >= PBEquipRules.open_item_slots(deployed, cfg)


## 升一级科技。买不起或已满级返回 false。
func buy_tech(state: PBRunState, branch: StringName, cfg: PBSimConfig) -> bool:
	var level: int = _tech_level(state, branch)
	var cost := PBEconomyRules.tech_cost(branch, level, cfg)
	if cost < 0 or not state.spend(cost):
		return false
	match branch:
		&"gold":
			state.tech_gold += 1
		&"pop":
			state.tech_pop += 1
		&"def":
			state.tech_def += 1
		_:
			state.training[branch] = level + 1
	return true


## 还没升到 [param target] 级的训练科技里最便宜的那一条。都满了返回空。
##
## **不看这一条对谁生效** —— 一队全远程也会买训练攻击。这是脚本玩家的粗糙之处，
## 会算账的那一个（[PBStratRational]）按估值挑，归数值回归。
func _cheapest_training(state: PBRunState, cfg: PBSimConfig, target: int) -> StringName:
	var best: StringName = &""
	var best_cost: int = -1
	for branch: StringName in PBTechRules.BRANCHES:
		var level: int = state.training_level(branch)
		var cost := PBEconomyRules.tech_cost(branch, level, cfg)
		if level >= target or cost < 0:
			continue
		if best_cost < 0 or cost < best_cost:
			best = branch
			best_cost = cost
	return best


func _tech_level(state: PBRunState, branch: StringName) -> int:
	match branch:
		&"gold":
			return state.tech_gold
		&"pop":
			return state.tech_pop
		&"def":
			return state.tech_def
		_:
			return state.training_level(branch)
