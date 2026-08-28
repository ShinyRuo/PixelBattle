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
## 3. **抽卡是随机的，量不了，只能求期望** —— 见 [method PBValuation.gacha_gain]。
##
## ## 金币科技为什么不参加比价
##
## 它买的是「未来的金币」，不是战力，跟其余四项不同币种。
## 用 §07 自己的口径判断：**回本波数**。价格曲线 `120 × 1.35^Lv`，
## 收益是每波固定的被动收入，所以回本波数随等级单调变长，
## 卡在阈值上自然就停了 —— 不需要像 `balanced` 那样写死一个目标等级。

## 候选项的编号。
enum Buy { NONE, GACHA, TECH_ATK, TECH_POP, EQUIP, KAKUZU }

## 一次 `prepare` 最多买多少笔。纯安全阀 —— 每一笔都在花钱、金币有限，
## 正常情况下会自己停下来。
const MAX_PURCHASES: int = 400

## 金币科技的回本阈值（波）。§07 要求「第一个金币科技 3–4 波回本」，
## 放宽到 6 波给后面几级留出空间。超过这个数就不升了。
var gold_payback_waves: float = 6.0

## 估值角都时往后看多少波。
##
## 角都买的是「未来每一波的金币」，值多少取决于**还能活多久** ——
## 而那是玩家不知道的。取 12 波是个中庸假设：比金币科技的回本阈值宽
## （角都的代价是出战位，回本本来就慢），又不至于假设自己能活到天荒地老。
##
## **这个数直接决定角都的估值，是本流派里最像「拍的」的一处。**
## 它偏大会让角都被高估、偏小会让它永远不被选中，改动前先跑一遍扫描。
var kakuzu_horizon_waves: float = 12.0


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
	var base: float = PBValuation.mean_dps(state, cfg)
	var best := Buy.NONE
	var best_rate: float = 0.0

	var atk_cost := PBEconomyRules.tech_cost(&"atk", state.tech_atk, cfg)
	if atk_cost > 0 and atk_cost <= state.gold:
		best_rate = _rate(PBValuation.tech_gain(state, cfg, &"atk", base), atk_cost)
		if best_rate > 0.0:
			best = Buy.TECH_ATK

	var pop_cost := PBEconomyRules.tech_cost(&"pop", state.tech_pop, cfg)
	if pop_cost > 0 and pop_cost <= state.gold:
		var rate := _rate(PBValuation.tech_gain(state, cfg, &"pop", base), pop_cost)
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
		var per_part: float = (
			PBValuation.equip_item_gain(state, cfg, base) / float(cfg.equip_parts_per_item)
		)
		var rate := _rate(per_part, cfg.equip_part_cost)
		if rate > best_rate:
			best_rate = rate
			best = Buy.EQUIP

	if cfg.gacha_cost <= state.gold:
		var rate := _rate(PBValuation.gacha_gain(state, cfg), cfg.gacha_cost)
		if rate > best_rate:
			best_rate = rate
			best = Buy.GACHA

	# 角都放在最后，因为它要用**上面几项里最好的那个汇率**做换算 —— 见下。
	if cfg.gacha_cost <= state.gold and best_rate > 0.0:
		var rate := _rate(_kakuzu_gain(state, wave, cfg, base, best_rate), cfg.gacha_cost)
		if rate > best_rate:
			best = Buy.KAKUZU

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
		Buy.KAKUZU:
			return _buy_kakuzu(state, cfg)
	return false


## 上一个角都。角都是抽来的角色不是商店货，代价折成一次单抽 ——
## 与 `pure_economy` 同口径。真正的代价是它占掉的那个出战位，那一份照实算。
func _buy_kakuzu(state: PBRunState, cfg: PBSimConfig) -> bool:
	if not state.spend(cfg.gacha_cost):
		return false
	state.kakuzu_count += 1
	return true


# ── 估值 ────────────────────────────────────────────────────────
#
# 具体计算全在 [PBValuation]（`src/core/rules/`）。放在那里而不是这里，
# 是因为**准备阶段的界面要显示同一组数字** —— 抄两份的话，
# 玩家看到的「这一笔涨多少战力」会和扫描定参时用的口径慢慢分叉，且不报错。


## 上一个角都值不值 —— 返回净的 DPS 增幅（可以是负数）。
##
## **这是本流派里唯一一处要换算币种的地方。** 角都收的是未来的金币，
## 付的却是一个出战位（DPS），两边不同币。
##
## 汇率不另外拍一个数：**用本轮比价里最好的那个「每金币 DPS 增幅」** ——
## 那正是这个玩家此刻把钱换成战力的真实效率。§10 降价之后这个汇率变了，
## 角都的估值就会跟着自动变，不用手工同步两处。
##
## 净值 = 未来 [member kakuzu_horizon_waves] 波的金币 × 汇率 − 让出一个出战位的损失。
func _kakuzu_gain(
	state: PBRunState, wave: PBWave, cfg: PBSimConfig, base: float, gold_rate: float
) -> float:
	if base <= 0.0 or open_slots(state, cfg) <= 1:
		return 0.0
	var before: int = PBEconomyRules.kakuzu_income(state.kakuzu_count, wave.index, cfg)
	var after: int = PBEconomyRules.kakuzu_income(state.kakuzu_count + 1, wave.index, cfg)
	var gold: float = float(after - before) * kakuzu_horizon_waves
	return gold * gold_rate - PBValuation.kakuzu_slot_loss(state, cfg, base)
