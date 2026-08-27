class_name PBWavePlan
extends RefCounted
## 「这一波怎么打」的完整计划：敌人参数、上场名单、有效 DPS、任务决定。
##
## 由 [method PBRunSim.plan_wave] 产出，[method PBRunSim.settle_wave] 消费。
##
## 抽出这个类是为了让**批量模拟和游戏画面走同一条准备流程**。
## 批量模拟拿到 plan 之后一口气把战斗算完；渲染层拿到同一个 plan，
## 交给 [PBBattleSim] 一 tick 一 tick 地推，好把过程画出来。
## 两边要是各写一份准备逻辑，RNG 的调用次序迟早分叉 ——
## 那时候「批量校出来的数值」和「实际玩到的手感」会对不上，且不会报任何错。

var wave: PBWave

## 本波上场的单位。已按「对本波的有效战力」排过序（即换上克制系）。
var deployed: Array[PBUnit] = []

## 己方对本波的有效每秒伤害，属性克制、攻击科技、羁绊、装备全部计入。
var dps: float = 0.0

## 本波刷出的任务在 [constant PBEconomyRules.QUEST_TABLE] 里的行号。
var quest_grade: int = 0

## 玩家接没接这个任务。接了就有金币，但派出去的人羁绊失效（§06）。
var quest_accepted: bool = false
