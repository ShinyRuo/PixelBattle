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
##
## **它是 [member attackers] 的和，不是另算的一份。** 界面上报的战力
## 和战场上真打出来的伤害必须是同一个数 —— 各算一遍的话两者会慢慢分叉，
## 而且不报任何错。见 [method PBCombatRules.build_attackers]。
var dps: float = 0.0

## 本波的己方攻击者，每人一个。战斗按各自的射程分配目标，见 [PBAttacker]。
var attackers: Array[PBAttacker] = []

## 本波解锁的羁绊功能档，`{ 载体角色 id: [功能键…] }`（§09）。
##
## 存在计划里，因为战斗（装在大招上）和结算（击杀掉落扣不扣钱）两条路都消费它；
## 它依赖 `state.dispatched`，各算一遍的话 `dispatched` 清零之后再算会多算一档。
var bond_functions: Dictionary = {}

## 满档的羁绊给每个在场成员各发了什么。见 [method PBBondRules.active_passives]。
var bond_passives: Dictionary = {}

## 满档的羁绊给每个在场成员打了哪些技能补丁。见 [method PBBondRules.active_skill_patches]。
var bond_skill_patches: Dictionary = {}

## 本波战斗内部的掷骰流。**null = 从不掷骰**（不暴击、不闪避）。
##
## 挂在计划上而不是当 [method PBRunSim.resolve_battle] 的参数：批量模拟和渲染层走同一条准备流程，
## 两边各自去取的话「用的是哪个波次号」迟早分叉。见 [method PBRngStreams.battle_rng]。
##
## > 估值探测拿不到它，所以探出来的悬崖是「不会暴击的那支队伍」的悬崖（偏保守），归数值回归。
var crit_rng: RandomNumberGenerator = null

## 本波刷出的任务在 [constant PBEconomyRules.QUEST_TABLE] 里的行号。
var quest_grade: int = 0

## 玩家接没接这个任务。接了就有金币，但派出去的人羁绊失效（§06）。
var quest_accepted: bool = false
