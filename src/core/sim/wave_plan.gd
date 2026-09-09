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

## 本波的己方攻击者，每人一个（M3-a）。战斗按各自的射程分配目标。
##
## M3-a 之前这里只有上面那个标量：整队每 tick 全砸在最前面那个敌人身上。
## 那是单服务台排队，而 M0 已经证明它在数学上不存在「场上稳定有几个人」
## 的中间态 —— 三条设计缺口同出于此。见 [PBAttacker]。
var attackers: Array[PBAttacker] = []

## 本波解锁的羁绊功能档，`{ 载体角色 id: [功能键…] }`（§09，M3-f）。
##
## 存在计划里而不是让战斗和结算各算一遍，是因为它同时被两条路消费：
## 战斗那条装在大招上，结算那条决定击杀掉落扣不扣钱。
## 而它依赖 `state.dispatched`（派遣出去的人羁绊失效，§06），
## **各算一遍的话，在 `dispatched` 被清零之后再算就会多算一档**，且不报错。
var bond_functions: Dictionary = {}

## 本波战斗内部的掷骰流（暴击，M10-c）。**null = 从不暴击。**
##
## ## 为什么它挂在计划上，而不是当 [method PBRunSim.resolve_battle] 的参数
##
## 这个类顶上那句话就是理由：批量模拟和渲染层要走**同一条准备流程**。
## 当参数的话两边各自去取一次，而「取的时候用的是哪个波次号」
## 迟早分叉 —— 那时同种子的两条路会打出不同的暴击序列，且不报错。
##
## 它不是 [member PBRngStreams.combat]：那一条是顺序流，而估值那一路
## （[method PBValuation._leaks_at]）每波要凭空跑几十场战斗。
## 见 [method PBRngStreams.battle_rng]。
##
## > **估值探测拿不到它，所以探出来的悬崖是「不会暴击的那支队伍」的悬崖。**
## > 那条偏差是系统性的、方向固定的（偏保守），归数值回归。
var crit_rng: RandomNumberGenerator = null

## 本波刷出的任务在 [constant PBEconomyRules.QUEST_TABLE] 里的行号。
var quest_grade: int = 0

## 玩家接没接这个任务。接了就有金币，但派出去的人羁绊失效（§06）。
var quest_accepted: bool = false
