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
