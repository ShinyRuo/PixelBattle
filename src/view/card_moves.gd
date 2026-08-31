class_name PBCardMoves
extends RefCounted
## 把一张卡从一个区搬到另一个区。§02 的拖放三区，M5-4。全部 static。
##
## ## 三个区就是屏幕上的三块地方
##
## **战场**（在打，吃装备吃站位算羁绊）、**仓库**（存着，什么都不算）、
## **任务栏**（这一波出去做任务，羁绊也不算他，§06）。
## 一个忍者**只在一处出现** —— 拖放就是在这三者之间搬。
##
## ## 为什么单独一个类
##
## 同一次搬运在界面上有两个入口：**拖过去**，和指令卡上的
## 「派上场 / 下场 / 派任务」。两处各写一份的话，
## 「拖过去能做但按按钮做不到」这种不一致迟早出现，
## 而它不报错 —— 玩家只会以为某个按钮坏了。
##
## ## 它不自己写状态字段
##
## 名单走 [method PBStrategy.set_lineup]、派遣走 [method PBShopRules.toggle_dispatch]、
## 摆位走 [method PBFormationRules.place]。界面自己动 `state.lineup` 之类的话，
## 迟早漏掉配套的刷新，而那种不同步不报错（和花钱那条是同一个理由）。

## 「这一下没有指定位置」——指令卡上的「派上场」就是这种。
##
## 摆位是夹取过的（[method PBFormationRules.clamp_spot]），合法坐标一律非负，
## 所以负数不会和真落点撞车。**不能拿 `Vector2.ZERO` 当哨兵**：
## 那是战场左上角，一个完全合法的落点 —— 拖到那儿会被当成「没给位置」。
const NO_SPOT := Vector2(-1.0, -1.0)


## 把一个忍者放上出战席或收回仓库。
##
## 出战席满了就**什么都不做** —— 挤掉一个已经在场的人是玩家没要求过的事，
## 而他不会知道被挤掉的是谁。
static func set_on_field(
	state: PBRunState, strategy: PBStrategy, plan: PBWavePlan, unit: PBUnit,
	on_field: bool, cfg: PBSimConfig
) -> void:
	if unit == null:
		return
	var roster: Array[PBUnit] = strategy.deploy(state, plan.wave, cfg)
	if on_field:
		if roster.has(unit) or roster.size() >= state.open_slots(cfg):
			return
		roster.append(unit)
	else:
		roster.erase(unit)
	strategy.set_lineup(state, roster)


## 一张卡被拖到了 [param to_zone]。[param at] 是战场坐标，只有落在战场上才用得着。
##
## ## 派任务的前提是他在场（M3.5-i）
##
## 待命台删掉之后「在场 = 出战席」，[method PBShopRules.toggle_dispatch]
## 只放行在场的人。所以从仓库直接拖到任务栏要**先把他放上场**，
## 否则那一下会静默失败 —— 玩家拖过去，卡弹回来，没有任何解释。
static func move(
	state: PBRunState,
	strategy: PBStrategy,
	plan: PBWavePlan,
	unit: PBUnit,
	from_zone: StringName,
	to_zone: StringName,
	at: Vector2,
	cfg: PBSimConfig
) -> void:
	if unit == null or from_zone == to_zone and to_zone != PBUnitTile.ZONE_FIELD:
		return
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	# 从任务栏拖出来：先撤回派遣，他才重新是一个能安排的人。
	if from_zone == PBUnitTile.ZONE_QUEST and to_zone != PBUnitTile.ZONE_QUEST:
		PBShopRules.toggle_dispatch(state, unit, need, cfg)
	match to_zone:
		PBUnitTile.ZONE_FIELD:
			set_on_field(state, strategy, plan, unit, true, cfg)
			# **摆位和上场是同一个动作。** 分成两步的话玩家要先派上场、
			# 再去战场上把他拖到想要的位置，而他刚才那一下就是在说位置。
			if at != NO_SPOT:
				PBFormationRules.place(state, unit, at, cfg)
		PBUnitTile.ZONE_STASH:
			set_on_field(state, strategy, plan, unit, false, cfg)
			PBFormationRules.reset(state, unit)
		PBUnitTile.ZONE_QUEST:
			set_on_field(state, strategy, plan, unit, true, cfg)
			PBShopRules.toggle_dispatch(state, unit, need, cfg)
