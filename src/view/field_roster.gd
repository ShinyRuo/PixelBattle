class_name PBFieldRoster
extends RefCounted
## 「屏幕上这几档各是谁」—— 在场 / 出任务 / 名单转卡。全部 static，不碰画面，是 state + plan 的派生量。
## 三档和 [PBCardMoves] 的三个区是同一套；仓库那一档在 [method PBRosterBay.idle_units]（前两档的补集）。

## 这一波谁去做任务：锁过了照 `dispatched_ids` 念，准备阶段就是任务栏里站着的那几个。
## 脚本玩家的末尾规则在 `lock_plan` 里，不经过这里。
static func dispatch_preview(state: PBRunState) -> Array[PBUnit]:
	if not state.dispatched_ids.is_empty():
		return units_of(state, state.dispatched_ids)
	return units_of(state, state.dispatch_manual)


## 这一波**真会打**的人。派出去做任务的不在里面（§06）。
##
## 战斗与结算阶段照 [member PBWavePlan.deployed] 念 ——
## [method PBRunSim.lock_plan] 已经把派出去的滤掉了，所以那两个阶段
## 调用方直接传 `plan.deployed`，走不到这里。
##
## 准备阶段按「现在开打会是谁」预览一份，**同样要减掉派遣**：
## 不减的话被派出去的人会**同时出现在战场和任务栏**，而他只可能在一处。
static func fighting_now(
	state: PBRunState, strategy: PBStrategy, plan: PBWavePlan, away: Array[PBUnit],
	cfg: PBSimConfig
) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for unit: PBUnit in strategy.deploy(state, plan.wave, cfg):
		if not away.has(unit):
			out.append(unit)
	return out


## 一份 id 名单对应的卡。**卖掉/不存在的静默跳过** ——
## 名单是跨波留着的（[member PBRunState.dispatch_manual]），
## 里面出现一个已经不在卡池里的人是正常状态，不是错误。
static func units_of(state: PBRunState, keys: Array[StringName]) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for key: StringName in keys:
		var unit := state.roster.get(key, null) as PBUnit
		if unit != null:
			out.append(unit)
	return out
