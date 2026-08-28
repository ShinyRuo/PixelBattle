class_name PBValuation
extends RefCounted
## 「这一笔钱值多少战力」—— 花钱决策的估值。全部 static，无状态，零引擎依赖。
##
## ## 为什么它在 core/ 而不是在流派里
##
## 它有两个调用方，而且**两边必须给出同一个数**：
##
## - [PBStratRational]（模拟玩家）拿它比价，决定这一笔买什么
## - 准备阶段界面拿它告诉真人玩家「这一笔买下去战力涨多少」
##
## 抄成两份的话，界面上显示的数字会和批量扫描得出结论时用的口径慢慢分叉 ——
## 玩家按界面上的数做决定，而策划按扫描结论调参，两边越走越远且不报任何错。
##
## ## 口径上的两处讲究
##
## 1. **按一个轮转周期估值，不按当前这一波。** 敌方属性五波一轮（§04），
##    一张火系卡只在其中一波吃到 2.0 倍。只看当前波会系统性低估抽卡、
##    高估装备（装备是无属性加成）。
## 2. **确定性支出用「改一下、量一次、改回来」**，不推公式。
##    人口科技会同时影响上场人数、待命台格数和羁绊，手推的公式漏掉任何一项
##    都不会报错，只会让估值悄悄失准。


## 队伍 DPS，按五波轮转取均值。**所有估值都以它为基准。**
static func mean_dps(state: PBRunState, cfg: PBSimConfig) -> float:
	var total: float = 0.0
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		total += PBCombatRules.team_dps(
			deployed_for(state, element, cfg),
			element,
			state.atk_mult(cfg),
			state.bond_mult(cfg),
			state.equip_mult(cfg),
			cfg
		)
	return total / float(PBWaveRules.WAVE_ELEMENTS.size())


## 面对 [param element] 这一波会派谁上场。与 [method PBStrategy.pick_by_effect] 同义，
## 只是不需要为了取属性而造一个 [PBWave]。
static func deployed_for(
	state: PBRunState, element: PBElement.Type, cfg: PBSimConfig
) -> Array[PBUnit]:
	var pool := state.all_units()
	pool.sort_custom(
		func(a: PBUnit, b: PBUnit) -> bool:
			return a.effective_power(element, cfg) > b.effective_power(element, cfg)
	)
	return pool.slice(0, state.open_slots(cfg))


## 面对 [param element] 这一波，**不换人**会派谁上场 —— 按裸战力排，完全不看属性。
##
## 它和 [method deployed_for] 的差值就是 §03 整套属性系统在数值上真正值多少。
## M-1 扫描出来是 1.41 倍（`GROWTH` = 1.10），而那个数字以前只存在于扫描报告里，
## 玩家看不到。阵容面板把两条并排显示，是为了让「每波换克制系」这件事
## **在玩的时候就能感觉到**，而不是只能从策划那儿听说。
static func deployed_by_raw_power(state: PBRunState, cfg: PBSimConfig) -> Array[PBUnit]:
	return state.sorted_by_power(cfg).slice(0, state.open_slots(cfg))


## 一份名单对 [param element] 这一波打出多少 DPS。科技、羁绊、装备都计入。
static func dps_of(
	units: Array[PBUnit], element: PBElement.Type, state: PBRunState, cfg: PBSimConfig
) -> float:
	return PBCombatRules.team_dps(
		units, element, state.atk_mult(cfg), state.bond_mult(cfg), state.equip_mult(cfg), cfg
	)


## 升一级 [param branch] 科技能让队伍 DPS 涨百分之几。
##
## [param base] 传当前的 [method mean_dps]，避免同一轮比价里重复算。
static func tech_gain(
	state: PBRunState, cfg: PBSimConfig, branch: StringName, base: float
) -> float:
	if base <= 0.0:
		return 0.0
	# 只有攻击和人口影响 DPS；金币和防御要另外的口径（见 [PBStratRational]）。
	if branch == &"atk":
		state.tech_atk += 1
		var after: float = mean_dps(state, cfg)
		state.tech_atk -= 1
		return after / base - 1.0
	if branch == &"pop":
		state.tech_pop += 1
		var after_pop: float = mean_dps(state, cfg)
		state.tech_pop -= 1
		return after_pop / base - 1.0
	return 0.0


## 买一件成品装备（[member PBSimConfig.equip_parts_per_item] 个配件）
## 能让队伍 DPS 涨百分之几。
static func equip_item_gain(state: PBRunState, cfg: PBSimConfig, base: float) -> float:
	if base <= 0.0:
		return 0.0
	state.equip_parts += cfg.equip_parts_per_item
	var after: float = mean_dps(state, cfg)
	state.equip_parts -= cfg.equip_parts_per_item
	return after / base - 1.0


## 上一个经济位会让队伍 DPS 掉百分之几 —— 它占掉一个出战位（§07）。
##
## 返回的是**纯代价**，正数表示损失。收益那一半是金币，币种不同，
## 换算由调用方做：模拟玩家用「当前每金币战力增幅」当汇率，界面直接把两个数并列显示。
static func economy_slot_loss(state: PBRunState, cfg: PBSimConfig, base: float) -> float:
	if base <= 0.0 or state.open_slots(cfg) <= 1:
		return 1.0
	state.economy_slot_count += 1
	var after: float = mean_dps(state, cfg)
	state.economy_slot_count -= 1
	return 1.0 - after / base


## 派 [param units] 个人出去做任务，队伍 DPS 掉百分之几（§06）。
##
## 派出去的人羁绊失效，所以代价是**整队一起降**，不是少了那几个人的输出 ——
## 被派的是待命台上本来就不上场的人。这一点手推很容易推反。
##
## 返回的是**纯代价**，正数表示损失。收益那一半是金币，币种不同 ——
## 换算不在这里做，见 [PBQuestCard] 为什么它把两边并排显示而不合成一个数。
static func dispatch_loss(state: PBRunState, cfg: PBSimConfig, base: float, units: int) -> float:
	if base <= 0.0 or units <= 0:
		return 0.0
	var before: int = state.dispatched
	state.dispatched = before + units
	var after: float = mean_dps(state, cfg)
	state.dispatched = before
	return 1.0 - after / base


## 派 [param units] 个人出去之后，这一波还剩多少 DPS。零副作用。
static func dps_if_dispatched(
	state: PBRunState, wave: PBWave, deployed: Array[PBUnit], units: int, cfg: PBSimConfig
) -> float:
	var before: int = state.dispatched
	state.dispatched = units
	var dps: float = dps_of(deployed, wave.element, state, cfg)
	state.dispatched = before
	return dps


## 这一波的**悬崖**：DPS 低到多少就开始漏怪。
##
## ## 为什么代价要用「离悬崖多远」度量，而不是「基地掉多少血」
##
## 任务卡最初写的是「不接 基地 −0 / 接了 基地 −128」——
## **实测下来那一行在几乎每一波都读作两个相同的 0**：
## 种子 20260827 那局打到第 40 波（最后一波活着的）两边仍然都是 0，
## 第 41 波直接团灭。
##
## 根因是 M0 已经查明的：这是个**单服务器排队**，ρ<1 一个不漏、ρ>1 全线崩，
## 中间没有稳定段（路线图 §01 那条缺口，要等 M3 的射程与多目标分配）。
## 所以基地伤害这个量在悬崖前恒为 0、悬崖后一步到底，**没有分辨率**。
##
## 富余倍数有分辨率，而且它正是玩家看不见的那个东西 ——
## 不给的话整局读起来是「好好好、死」。
##
## 二分靠的是 [method PBCombatRules.resolve] 对 dps 单调，
## 那条性质由 `test_more_dps_never_produces_more_leaks` 锁着。
static func leak_threshold_dps(wave: PBWave, def_reduction: float, cfg: PBSimConfig) -> float:
	var high: float = maxf(wave.hp_each, 1.0)
	var guard: int = 0
	while guard < 64 and PBCombatRules.resolve(wave, high, def_reduction, cfg).leaked > 0:
		high *= 2.0
		guard += 1
	if guard >= 64:
		return high
	var low: float = 0.0
	for _i: int in 32:
		var mid: float = (low + high) * 0.5
		if PBCombatRules.resolve(wave, mid, def_reduction, cfg).leaked > 0:
			low = mid
		else:
			high = mid
	return high


## 抽一张卡的**期望**增幅。抽卡是随机的，量不出来，只能算。
##
## 拆成两项相乘：
##
## - **输出**：新卡只有挤掉当前上场阵容里最弱的那个才有价值。
##   对轮转里的每一波各算一次门槛，再对（稀有度 × 属性）求期望。
##   `max(新卡 − 门槛, 0)` 这个形式是精确的 —— 上场名单就是按有效战力取前 N，
##   加一张卡要么挤掉最弱的那个，要么完全不上场。
## - **羁绊**：板凳没坐满时，多一张卡本身就是加成（§09 的替身曲线）。
##
## 已知的一处简化：**不算保底**。快到保底时抽卡的真实期望比这里高一点。
static func gacha_gain(state: PBRunState, cfg: PBSimConfig) -> float:
	var slots: int = state.open_slots(cfg)
	if slots <= 0:
		return 0.0

	var power_gain: float = 0.0
	var counted: int = 0
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		var deployed := deployed_for(state, element, cfg)
		var total: float = 0.0
		for unit: PBUnit in deployed:
			total += unit.effective_power(element, cfg)
		if total <= 0.0:
			# 一张卡都没有：第一张的相对增幅是无穷大，直接判定抽卡最优。
			return 1.0
		# 名单没坐满时门槛是 0 —— 新卡直接填空位，不用挤谁。
		var cutoff: float = 0.0
		if deployed.size() >= slots:
			cutoff = deployed[deployed.size() - 1].effective_power(element, cfg)
		power_gain += expected_surplus(element, cutoff, state, cfg) / total
		counted += 1
	power_gain /= float(maxi(counted, 1))

	var bond_before: float = state.bond_mult(cfg)
	var bond_gain: float = 0.0
	if bond_before > 0.0:
		bond_gain = state.bond_mult_for(state.roster.size() + 1, cfg) / bond_before - 1.0
	return (1.0 + power_gain) * (1.0 + bond_gain) - 1.0


## 面对 [param wave_element] 这一波，抽一张卡能给上场阵容多加多少输出（期望值）。
##
## **重复卡必须单独算。** 卡池只有 48 张（§08），后期手上三十几张，
## 四分之三的抽卡都是重复卡，只能加星（同卡 3 张升 1 星），收益低一个数量级。
## 把每一抽都当新卡会系统性高估后期抽卡 —— 而后期正是「该继续抽还是该转装备」
## 的分界区，偏差刚好落在结论上。
##
## 算法分两步：
##
## 1. 先按「全是新卡」把整个卡池的期望算出来
## 2. 再遍历已有的卡，把它们那一格从「新卡」换成「重复卡」
##
## **概率口径按角色表算，不按「六个属性等概率」硬编码**（M2-a）。
## 合成表上两者恒等（每个稀有度下六系均分），但真角色表的属性分布是不均匀的 ——
## 硬编码 1/6 会让估值和抽卡的实际分布悄悄对不上，且不报错。
static func expected_surplus(
	wave_element: PBElement.Type, cutoff: float, state: PBRunState, cfg: PBSimConfig
) -> float:
	var row: Array = gacha_row(state.wave_index)
	var surplus: float = 0.0
	for rarity: int in cfg.rarity_power.size():
		var chance: float = float(row[rarity + 1]) / 100.0
		var pool := cfg.characters.of_rarity(rarity as PBUnit.Rarity)
		if chance <= 0.0 or pool.is_empty():
			continue
		var per_card: float = chance / float(pool.size())
		for character: PBCharacter in pool:
			var fresh: float = (
				cfg.rarity_power[rarity] * _multiplier(int(character.element), wave_element, cfg)
			)
			surplus += per_card * maxf(fresh - cutoff, 0.0)

	for unit: PBUnit in state.roster.values():
		var chance: float = float(row[int(unit.rarity) + 1]) / 100.0
		var pool := cfg.characters.of_rarity(unit.rarity)
		if chance <= 0.0 or pool.is_empty():
			continue
		# 抽到**这一个角色**的概率：稀有度概率 ÷ 该稀有度下的角色数。
		var p_cell: float = chance / float(pool.size())
		var mult: float = _multiplier(int(unit.element), wave_element, cfg)
		# 撤掉上一段里把这张卡当新卡算的那份。
		surplus -= p_cell * maxf(cfg.rarity_power[int(unit.rarity)] * mult - cutoff, 0.0)
		# 换成重复卡该给的：只有凑够 3 张跨过星级边界的那一抽才涨战力。
		var before: float = unit.effective_power(wave_element, cfg)
		var step: float = 0.0
		if unit.copies % 3 == 0:
			step = cfg.rarity_power[int(unit.rarity)] * cfg.star_power_mult * mult
		surplus += p_cell * (maxf(before + step - cutoff, 0.0) - maxf(before - cutoff, 0.0))
	return surplus


## §08 概率表在当前波次的那一行。表在 [PBEconomyRules]，这里只是查。
static func gacha_row(wave_index: int) -> Array:
	for row: Array in PBEconomyRules.GACHA_TABLE:
		if wave_index <= int(row[0]):
			return row
	return PBEconomyRules.GACHA_TABLE[PBEconomyRules.GACHA_TABLE.size() - 1]


static func _multiplier(element: int, wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	return cfg.damage_multiplier(PBElement.relation(element as PBElement.Type, wave_element))
