class_name PBStratRational
extends PBStrategy
## 会算账的玩家：每一笔钱都买「每金币战力增幅最大」的那一项。
##
## ## 为什么需要它
##
## 其余流派的花钱逻辑是**写死的优先级**：先升几级金币科技、卡池不满就抽卡、
## 抽满了转装备。里面唯一一处比价是「攻击科技比单抽便宜就先买」，
## 而**装备的价格从头到尾没被任何判断读过** —— `gacha_still_pays()`
## 看的是板凳坐没坐满，跟 `equip_part_cost` 无关。
##
## 于是出现一个死结：§10 的待决策是「装备该定多少钱」，
## 但拿现有流派去扫价格，扫出来的差异只是「剩下的钱能多买几个配件」，
## **不是「玩家会不会改买装备」**。用一个不看价格的玩家去校准价格，
## 问出来的答案没有意义。
##
## 这个流派把决策换成统一的口径：**每一笔支出都折算成「队伍 DPS 涨了百分之几」，
## 除以花掉的金币，取最高的那个买。** 价格一变，选择自己就变了。
##
## ## 三条口径上的讲究
##
## 1. **按一个轮转周期估值，不按当前这一波。** 敌方属性五波一轮（§04），
##    一张火系卡只在其中一波吃到 2.0 倍。只看当前波会系统性低估抽卡、
##    高估装备（装备是无属性加成）—— 而那正好是本流派要回答的问题，
##    偏差会直接污染结论。所以所有候选都按五波均值比。
## 2. **确定性支出用「改一下、量一次、改回来」**，不推公式。
##    科技、人口、装备的效果直接调 [PBCombatRules.team_dps] 量出来，
##    模型和真实结算永远一致；推公式则会随着结算逻辑演化而悄悄失准。
## 3. **抽卡是随机的，量不了，只能求期望** —— 见 [method _gacha_gain]。
##
## ## 金币科技为什么不参加比价
##
## 它买的是「未来的金币」，不是战力，跟其余四项不同币种。
## 用 §07 自己的口径判断：**回本波数**。价格曲线 `120 × 1.35^Lv`，
## 收益是每波固定的被动收入，所以回本波数随等级单调变长，
## 卡在阈值上自然就停了 —— 不需要像 `balanced` 那样写死一个目标等级。

## 候选项的编号。
enum Buy { NONE, GACHA, TECH_ATK, TECH_POP, EQUIP }

## 一次 `prepare` 最多买多少笔。纯安全阀 —— 每一笔都在花钱、金币有限，
## 正常情况下会自己停下来。
const MAX_PURCHASES: int = 400

## 金币科技的回本阈值（波）。§07 要求「第一个金币科技 3–4 波回本」，
## 放宽到 6 波给后面几级留出空间。超过这个数就不升了。
var gold_payback_waves: float = 6.0


func _init() -> void:
	id = &"rational"
	dispatch_policy = Dispatch.SMART


func prepare(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> void:
	_buy_gold_tech(state, wave, cfg)
	for _i: int in MAX_PURCHASES:
		if not _buy_best(state, wave, cfg, rng):
			return


# ── 金币科技：按回本波数，不参加战力比价 ────────────────────────


func _buy_gold_tech(state: PBRunState, wave: PBWave, cfg: PBSimConfig) -> void:
	while true:
		var cost := PBEconomyRules.tech_cost(&"gold", state.tech_gold, cfg)
		if cost <= 0 or cost > state.gold:
			return
		# 每波多赚多少：被动收入按战斗秒数计时，这里用上一波的实际时长估。
		var per_wave: int = (
			PBEconomyRules.passive_income(
				_battle_seconds_estimate(state, wave), state.tech_gold + 1, cfg
			)
			- PBEconomyRules.passive_income(
				_battle_seconds_estimate(state, wave), state.tech_gold, cfg
			)
		)
		if per_wave <= 0 or float(cost) / float(per_wave) > gold_payback_waves:
			return
		if not buy_tech(state, &"gold", cfg):
			return


## 估一波要打多久。开局还没有战绩，用出怪窗口兜底。
func _battle_seconds_estimate(state: PBRunState, wave: PBWave) -> float:
	if wave.index <= 1 or state.elapsed_seconds <= 0.0:
		return 10.0
	return state.elapsed_seconds / float(wave.index - 1)


# ── 战力支出：统一按「每金币的 DPS 增幅」比价 ────────────────────


## 买一笔当前性价比最高的。买不动了返回 false。
func _buy_best(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> bool:
	var base: float = _mean_dps(state, cfg)
	var best := Buy.NONE
	var best_rate: float = 0.0

	var atk_cost := PBEconomyRules.tech_cost(&"atk", state.tech_atk, cfg)
	if atk_cost > 0 and atk_cost <= state.gold:
		best_rate = _rate(_gain_from_tech(state, cfg, &"atk", base), atk_cost)
		if best_rate > 0.0:
			best = Buy.TECH_ATK

	var pop_cost := PBEconomyRules.tech_cost(&"pop", state.tech_pop, cfg)
	if pop_cost > 0 and pop_cost <= state.gold:
		var rate := _rate(_gain_from_tech(state, cfg, &"pop", base), pop_cost)
		if rate > best_rate:
			best_rate = rate
			best = Buy.TECH_POP

	# 装备的收益要按「一件成品」量，因为配件凑不满 3 个不产生任何加成 ——
	# 只量一个配件会算出 0 收益，装备永远不会被选中。
	#
	# 但**比价要摊回到单个配件**。按整件比会引入一个纯粹的模型假象：
	# 一件成品要 3 倍配件价一次性拿出，而这个循环每有 150 金就会拿去抽卡，
	# 于是钱永远攒不到那一笔，装备连参加比价的资格都没有 ——
	# 表现为「怎么加强装备都没人买」，看上去像经济学结论，其实是攒钱行为没建模。
	# 摊薄之后收益率完全不变（三个配件的边际收益相同），可负担性却正常了。
	if cfg.equip_part_cost <= state.gold and not equipment_is_full(state, cfg):
		var per_part: float = _gain_from_equip(state, cfg, base) / float(cfg.equip_parts_per_item)
		var rate := _rate(per_part, cfg.equip_part_cost)
		if rate > best_rate:
			best_rate = rate
			best = Buy.EQUIP

	if cfg.gacha_cost <= state.gold:
		var rate := _rate(_gacha_gain(state, cfg), cfg.gacha_cost)
		if rate > best_rate:
			best_rate = rate
			best = Buy.GACHA

	return _execute(best, state, wave, cfg, rng)


func _rate(gain: float, cost: int) -> float:
	if cost <= 0 or gain <= 0.0:
		return 0.0
	return gain / float(cost)


func _execute(
	choice: Buy, state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams
) -> bool:
	match choice:
		Buy.TECH_ATK:
			return buy_tech(state, &"atk", cfg)
		Buy.TECH_POP:
			return buy_tech(state, &"pop", cfg)
		Buy.EQUIP:
			return buy_equip_part(state, cfg)
		Buy.GACHA:
			return pull_once(state, wave, cfg, rng)
		_:
			return false


# ── 估值 ────────────────────────────────────────────────────────


## 队伍 DPS，按五波轮转取均值。**所有比价都用这个口径。**
##
## 用当前这一波的属性去比会失真：装备是无属性的固定加成，
## 抽到的卡却只在轮转里的某一波吃到克制。只看一波会让装备显得更划算，
## 而「装备到底划不划算」正是这个流派要回答的问题。
func _mean_dps(state: PBRunState, cfg: PBSimConfig) -> float:
	var total: float = 0.0
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		total += PBCombatRules.team_dps(
			_deployed_for(state, element, cfg),
			element,
			state.atk_mult(cfg),
			state.bond_mult(cfg),
			state.equip_mult(cfg),
			cfg
		)
	return total / float(PBWaveRules.WAVE_ELEMENTS.size())


## 面对 [param element] 这一波会派谁上场。等价于 [method pick_by_effect]，
## 只是不需要为了取属性而造一个 [PBWave]。
func _deployed_for(state: PBRunState, element: PBElement.Type, cfg: PBSimConfig) -> Array[PBUnit]:
	var pool := state.all_units()
	pool.sort_custom(
		func(a: PBUnit, b: PBUnit) -> bool:
			return a.effective_power(element, cfg) > b.effective_power(element, cfg)
	)
	return pool.slice(0, maxi(open_slots(state, cfg), 0))


## 升一级科技能让队伍 DPS 涨百分之几。**改一下、量一次、改回来。**
##
## 不推公式是有意的：人口科技会同时影响上场人数、待命台格数和羁绊，
## 手推的公式漏掉任何一项都不会报错，只会让模拟玩家轻微地不理性。
func _gain_from_tech(state: PBRunState, cfg: PBSimConfig, branch: StringName, base: float) -> float:
	if base <= 0.0:
		return 0.0
	if branch == &"atk":
		state.tech_atk += 1
		var after: float = _mean_dps(state, cfg)
		state.tech_atk -= 1
		return after / base - 1.0
	state.tech_pop += 1
	var after_pop: float = _mean_dps(state, cfg)
	state.tech_pop -= 1
	return after_pop / base - 1.0


## 买一件成品装备能让队伍 DPS 涨百分之几。
func _gain_from_equip(state: PBRunState, cfg: PBSimConfig, base: float) -> float:
	if base <= 0.0:
		return 0.0
	state.equip_parts += cfg.equip_parts_per_item
	var after: float = _mean_dps(state, cfg)
	state.equip_parts -= cfg.equip_parts_per_item
	return after / base - 1.0


## 抽一张卡的**期望**增幅。抽卡是随机的，量不出来，只能算。
##
## 拆成两项相乘：
##
## - **输出**：新卡只有挤掉当前上场阵容里最弱的那个才有价值。
##   对轮转里的每一波各算一次门槛，再对（稀有度 × 属性）24 种结果求期望。
##   `max(新卡 − 门槛, 0)` 这个形式是精确的 —— 上场名单就是按有效战力取前 N，
##   加一张卡要么挤掉最弱的那个，要么完全不上场。
## - **羁绊**：板凳没坐满时，多一张卡本身就是加成（§09 的替身曲线）。
##
## 已知的一处简化：**不算保底**。快到保底时抽卡的真实期望比这里高一点。
##
## 重复卡是算的，而且必须算 —— 卡池只有 48 张（§08），后期手上已有三十几张，
## **四分之三的抽卡都是重复卡**，只能加星（同卡 3 张升 1 星），
## 收益比新卡低一个数量级。把每一抽都当新卡会系统性高估后期抽卡，
## 而后期正是「该继续抽还是该转装备」的分界区 —— 偏差刚好落在结论上。
func _gacha_gain(state: PBRunState, cfg: PBSimConfig) -> float:
	var slots: int = open_slots(state, cfg)
	if slots <= 0:
		return 0.0

	var power_gain: float = 0.0
	var counted: int = 0
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		var deployed := _deployed_for(state, element, cfg)
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
		power_gain += _expected_surplus(element, cutoff, state, cfg) / total
		counted += 1
	power_gain /= float(maxi(counted, 1))

	var bond_before: float = state.bond_mult(cfg)
	var bond_gain: float = 0.0
	if bond_before > 0.0:
		bond_gain = state.bond_mult_for(state.roster.size() + 1, cfg) / bond_before - 1.0
	return (1.0 + power_gain) * (1.0 + bond_gain) - 1.0


## 面对 [param wave_element] 这一波，抽一张卡能给上场阵容多加多少输出（期望值）。
##
## 上场名单是「按有效战力取前 N」，所以一张卡的贡献恰好是
## `max(它 − 门槛, 0)` 的增量 —— 打不过门槛就完全不上场，打得过就顶掉最弱的那个。
## 这个形式对新卡和重复卡都成立，两者只差「它之前值多少」。
##
## 算法分两步，避开逐格枚举 48 张卡：
##
## 1. 先按「全是新卡」把 4 稀有度 × 6 属性 的期望算出来
## 2. 再遍历已有的卡，把它们那一格从「新卡」换成「重复卡」
func _expected_surplus(
	wave_element: PBElement.Type, cutoff: float, state: PBRunState, cfg: PBSimConfig
) -> float:
	var row: Array = _gacha_row(state.wave_index)
	var surplus: float = 0.0
	for rarity: int in cfg.rarity_power.size():
		var chance: float = float(row[rarity + 1]) / 100.0
		if chance <= 0.0:
			continue
		for element: int in PBElement.Type.size():
			var fresh: float = cfg.rarity_power[rarity] * _multiplier(element, wave_element, cfg)
			surplus += chance / 6.0 * maxf(fresh - cutoff, 0.0)

	var bucket: float = float(maxi(cfg.characters_per_bucket, 1))
	for unit: PBUnit in state.roster.values():
		var chance: float = float(row[int(unit.rarity) + 1]) / 100.0
		if chance <= 0.0:
			continue
		# 落到这一格的概率：稀有度 × 属性六选一 × 同格几号角色。
		var p_cell: float = chance / 6.0 / bucket
		var mult: float = _multiplier(int(unit.element), wave_element, cfg)
		# 撤掉上一段里把这一格当新卡算的那份。
		surplus -= p_cell * maxf(cfg.rarity_power[int(unit.rarity)] * mult - cutoff, 0.0)
		# 换成重复卡该给的：只有凑够 3 张跨过星级边界的那一抽才涨战力。
		var before: float = unit.effective_power(wave_element, cfg)
		var step: float = 0.0
		if unit.copies % 3 == 0:
			step = cfg.rarity_power[int(unit.rarity)] * cfg.star_power_mult * mult
		surplus += p_cell * (maxf(before + step - cutoff, 0.0) - maxf(before - cutoff, 0.0))
	return surplus


func _multiplier(element: int, wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	return cfg.damage_multiplier(PBElement.relation(element as PBElement.Type, wave_element))


## §08 概率表在当前波次的那一行。表在 [PBEconomyRules]，这里只是查。
func _gacha_row(wave_index: int) -> Array:
	for row: Array in PBEconomyRules.GACHA_TABLE:
		if wave_index <= int(row[0]):
			return row
	return PBEconomyRules.GACHA_TABLE[PBEconomyRules.GACHA_TABLE.size() - 1]
