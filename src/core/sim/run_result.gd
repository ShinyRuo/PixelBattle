class_name PBRunResult
extends RefCounted
## 一整局模拟的结果。[PBRunSim.run] 的输出，也是 CSV 的一行。

## 玩家卡住的波次 —— 无限流里这就是玩家的成绩（§01）。
var wave_reached: int = 0

## 是否打到了 `max_wave` 上限还没死。
##
## **统计时必须把这些局单独挑出来。** 混进分位数会把「打穿了上限」
## 误读成「卡在第 200 波」，`GROWTH` 会被校准得偏低。
var hit_wave_cap: bool = false

var strategy_id: StringName = &""
var growth: float = 0.0
var run_seed: int = 0

# ── 过程统计 ────────────────────────────────────────────────────
var total_kills: int = 0
var total_leaked: int = 0
var gold_earned: int = 0
var gacha_pulls: int = 0
var quests_taken: int = 0

## 全部波次的战斗时长（秒）之和与波数，用来算均值。
var battle_seconds_sum: float = 0.0

## 战斗时长落在 §01 目标区间 30–45 秒内的波数。
var waves_in_target_duration: int = 0

## 终局的科技等级快照，用来看不同策略把钱花到哪去了。
var final_tech_gold: int = 0
var final_tech_pop: int = 0
var final_tech_atk: int = 0
var final_tech_def: int = 0
var final_roster_size: int = 0

## 终局买到的装备配件数（§10 的替身曲线）。
## **诊断金币去向时最要紧的一列** —— 抽卡有天花板，装备没有，
## 这个数偏低就说明金币坑根本没被够到，经济系统的结论要重新审。
var final_equip_parts: int = 0

var gold_spent: int = 0

## 五条收入流各自赚了多少（§07）。键见 [constant PBEconomyRules.GOLD_SOURCES]。
##
## §07 的验收「纯战力开局在 20 波左右因缺钱停滞」实测跑到 96%，
## 也就是不投经济几乎没有代价。这一列是诊断那件事的入口 ——
## 光看 [member gold_earned] 分不出「金币科技没用」和「它被别的流盖过」。
var gold_by_source: Dictionary = {}


## 某条收入流占总收入的比例。
func gold_share(source: StringName) -> float:
	if gold_earned <= 0:
		return 0.0
	return float(int(gold_by_source.get(source, 0))) / float(gold_earned)


## 单波平均战斗时长。§01 要求落在 30–45 秒。
func mean_battle_seconds() -> float:
	if wave_reached <= 0:
		return 0.0
	return battle_seconds_sum / float(wave_reached)


## 战斗时长达标的波次占比。
func duration_hit_rate() -> float:
	if wave_reached <= 0:
		return 0.0
	return float(waves_in_target_duration) / float(wave_reached)
