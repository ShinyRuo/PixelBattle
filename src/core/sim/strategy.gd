class_name PBStrategy
extends RefCounted
## 玩家决策的接口。M-1 用写死的脚本代替真人，跑出不同玩法流派的极限波次。
##
## ## 这是一个「端口」，不是游戏逻辑
##
## 真实游戏里这些决策由玩家在准备阶段做出。[PBRunSim] 每波会向本接口
## 要三个答案：**钱怎么花、谁上场、接不接任务**。
##
## 接口定义在 `src/core/`，具体流派实现在 `src/tools/strategies/`。
## 方向不能反 —— core 引用 tools 就等于把模拟脚手架焊进了游戏逻辑，
## M0 接真 UI 时会拆不掉。
##
## ## 为什么 deploy 默认按克制排序
##
## §03 的 2.0 倍克制加成，**只有玩家每波真的换上克制系单位才吃得到**。
## 全员固定上场的五系阵容平均倍率只有 1.10，和纯物理的 1.05 几乎没差别。
## 所以「按有效战力排序取前 N」就是这个模型下的最优打法，作为基类默认值；
## 想测「不换人会怎样」的流派去覆盖它（见 tools/strategies 里的 no_rotation）。

## 派遣策略。§06 的「这一波我要羁绊，还是要钱」。
enum Dispatch {
	NEVER,  ## 从不派遣，永远保满羁绊
	ALWAYS,  ## 有任务就接，钱最大化
	SMART,  ## BOSS 波前一波收手，其余照接
}

## 流派名，进 CSV 的 `strategy` 列。
var id: StringName = &"base"

var dispatch_policy: Dispatch = Dispatch.SMART


## 准备阶段花钱。抽卡、升科技、上角都都在这里做。
##
## 子类必须覆盖。基类什么都不做 —— 一个不花钱的玩家也是合法的对照组。
func prepare(_state: PBRunState, _wave: PBWave, _cfg: PBSimConfig, _rng: PBRngStreams) -> void:
	pass


## 选出本波上场的单位。默认取对本波有效战力最高的前 N 个。
func deploy(state: PBRunState, wave: PBWave, cfg: PBSimConfig) -> Array[PBUnit]:
	return pick_by_effect(state, wave, cfg, open_slots(state, cfg))


## 接不接这个任务。[param grade] 是 [constant PBEconomyRules.QUEST_TABLE] 的行号。
func accept_quest(state: PBRunState, wave: PBWave, grade: int, cfg: PBSimConfig) -> bool:
	if dispatch_policy == Dispatch.NEVER:
		return false
	if PBEconomyRules.quest_cost_units(grade) > standby_available(state, cfg):
		return false
	if dispatch_policy == Dispatch.ALWAYS:
		return true
	# SMART：BOSS 波前一波收手，把羁绊留满。§06 说这会让节奏自然产生起伏。
	return (wave.index + 1) % PBWaveRules.BOSS_EVERY != 0


## 出战席里还剩几个位置能放输出 —— 角都占着位却不产出任何伤害（§07）。
func open_slots(state: PBRunState, cfg: PBSimConfig) -> int:
	return maxi(state.deploy_capacity(cfg) - state.kakuzu_count, 0)


## 待命台上现在有几个人可以被派出去。
func standby_available(state: PBRunState, cfg: PBSimConfig) -> int:
	var spare: int = state.roster.size() - open_slots(state, cfg)
	return clampi(spare, 0, state.standby_capacity(cfg))


## 按「对本波的有效战力」取前 [param slots] 个 —— 即每波换上克制系。
func pick_by_effect(state: PBRunState, wave: PBWave, cfg: PBSimConfig, slots: int) -> Array[PBUnit]:
	var pool := state.all_units()
	pool.sort_custom(
		func(a: PBUnit, b: PBUnit) -> bool:
			return a.effective_power(wave.element, cfg) > b.effective_power(wave.element, cfg)
	)
	return pool.slice(0, maxi(slots, 0))


## 按「裸战力」取前 [param slots] 个，完全不看属性。
## 这是隔离「换人」效应的对照组：它和 [method pick_by_effect] 的差值，
## 就是 §03 整套属性系统在数值上真正值多少。
func pick_by_raw_power(state: PBRunState, cfg: PBSimConfig, slots: int) -> Array[PBUnit]:
	return state.sorted_by_power(cfg).slice(0, maxi(slots, 0))


## 只从指定属性里取前 [param slots] 个。凑不满就有几个上几个。
func pick_by_element(
	state: PBRunState, element: PBElement.Type, cfg: PBSimConfig, slots: int
) -> Array[PBUnit]:
	var pool: Array[PBUnit] = []
	for unit: PBUnit in state.all_units():
		if unit.element == element:
			pool.append(unit)
	pool.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))
	return pool.slice(0, maxi(slots, 0))


## 抽一张卡并入库，同时维护 §08 的保底计数。买不起返回 false。
func pull_once(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> bool:
	if not state.spend(cfg.gacha_cost):
		return false
	var unit := PBEconomyRules.roll_gacha(wave.index, state.gacha_pity, cfg, rng.gacha)
	state.add_unit(unit)
	state.gacha_pulls += 1
	if int(unit.rarity) >= int(PBUnit.Rarity.SSR):
		state.gacha_pity = 0
	else:
		state.gacha_pity += 1
	return true


## 把剩下的钱换成战力，一直花到买不动为止。`balanced` 与 `pure_power` 共用，
## 这样两者的差别只剩「升不升金币科技」这一个变量，差值才读得出意义。
##
## 优先级是有依据的，不是随手排的：
##
## 1. **攻击科技比单抽便宜时先买** —— 确定的 +6% 好过一发方差极大的抽卡
## 2. **卡池没抽满就抽卡** —— 新卡是全新战力，重复卡只加星级，差一个数量级
## 3. **抽满了转装备** —— 抽卡的边际收益此时已趋近于零，而装备在装满整队前
##    每一件都实打实。这个拐点就是 §10 存在的经济学意义
## 4. **装备也满了再回去抽卡刷星级** —— 边际收益低，但总比钱烂在手里强
func spend_on_power(
	state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams, atk_target: int
) -> void:
	while true:
		var atk_cost := PBEconomyRules.tech_cost(&"atk", state.tech_atk, cfg)
		var tech_first: bool = (
			atk_cost >= 0 and atk_cost <= cfg.gacha_cost and state.tech_atk < atk_target
		)
		if tech_first:
			if not buy_tech(state, &"atk", cfg):
				return
		elif gacha_still_pays(state, cfg) or equipment_is_full(state, cfg):
			if not pull_once(state, wave, cfg, rng):
				return
		elif not buy_equip_part(state, cfg):
			return


## 抽卡是否仍然比装备划算。
##
## 判据是**板凳坐不坐得满**，不是卡池抽没抽完 —— 两者差很远。
## 出战席最多 10 人，多出来的卡只在「换克制系」时轮换用，
## 手上有两倍板凳容量的卡之后，再多一张几乎不可能挤进当前的上场名单，
## 边际收益断崖式下跌。而装备是按人头加成的，只要板凳没装满就一直有效。
##
## 早先这里写的是「卡池抽到 80% 才转装备」，结果玩家到死卡池才 36/48，
## 门槛从来没打开过，装备平均只买到 0.5 个（满装要 90 个）——
## 于是金币坑形同虚设，经济系统被误判成「不重要」。
func gacha_still_pays(state: PBRunState, cfg: PBSimConfig) -> bool:
	var bench: int = state.deploy_capacity(cfg) + state.standby_capacity(cfg)
	return state.roster.size() < bench * 2


## 买一个装备配件（§10 的替身曲线）。买不起返回 false。
##
## 这是后期金币的主要去处。抽卡在卡池抽满后边际收益趋近于零，
## 而装备在装满整队之前每一件都实打实 —— 两者的边际曲线正好相反，
## 所以「该抽卡还是该买装备」在中后期是个真决策。
func buy_equip_part(state: PBRunState, cfg: PBSimConfig) -> bool:
	if not state.spend(cfg.equip_part_cost):
		return false
	state.equip_parts += 1
	return true


## 出战席是否已经装备到满，再买就溢出了。
func equipment_is_full(state: PBRunState, cfg: PBSimConfig) -> bool:
	var slots: int = maxi(state.deploy_capacity(cfg) - state.kakuzu_count, 0)
	var items: int = state.equip_parts / cfg.equip_parts_per_item
	return items >= slots * cfg.equip_items_per_unit


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
		&"atk":
			state.tech_atk += 1
		&"def":
			state.tech_def += 1
	return true


func _tech_level(state: PBRunState, branch: StringName) -> int:
	match branch:
		&"gold":
			return state.tech_gold
		&"pop":
			return state.tech_pop
		&"atk":
			return state.tech_atk
		&"def":
			return state.tech_def
		_:
			return 0
