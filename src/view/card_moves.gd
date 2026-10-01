class_name PBCardMoves
extends RefCounted
## 把一张卡从一个区搬到另一个区（§02 的拖放三区）。全部 static。
##
## 三个区：**战场**（在打）、**仓库**（存着）、**任务栏**（出去做任务，羁绊不算他）。一个忍者只在一处。
##
## 同一次搬运有两个入口（拖过去、指令卡上的「派上场 / 下场 / 派任务」），**都走这里** ——
## 否则「拖过去能做但按按钮做不到」迟早出现。
## **不自己写状态字段**：名单走 [method PBStrategy.set_lineup]、派遣走 [method PBShopRules.toggle_dispatch]、
## 摆位走 [method PBFormationRules.place]。

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
	state: PBRunState,
	strategy: PBStrategy,
	plan: PBWavePlan,
	unit: PBUnit,
	on_field: bool,
	cfg: PBSimConfig
) -> void:
	if unit == null:
		return
	var roster: Array[PBUnit] = strategy.deploy(state, plan.wave, cfg)
	if on_field:
		# 门槛是 [method PBRunState.field_slots] 不是 `open_slots`：出任务的人不占人口。
		if roster.has(unit) or roster.size() >= state.field_slots(cfg):
			return
		roster.append(unit)
	else:
		roster.erase(unit)
	strategy.set_lineup(state, roster)


## 一张卡被拖到了 [param to_zone]。[param at] 是战场坐标，只有落在战场上才用得着。
##
## ## 拖进任务栏走 [method _send_to_quest]，那里有一条顺序上的死结
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
	# 任务栏的槽数和「本波要几个」不是一个数，见 [constant PBEconomyRules.QUEST_SLOTS]。
	var slots: int = PBEconomyRules.QUEST_SLOTS
	# 从任务栏拖出来：先撤回派遣，他才重新是一个能安排的人。
	if from_zone == PBUnitTile.ZONE_QUEST and to_zone != PBUnitTile.ZONE_QUEST:
		PBShopRules.toggle_dispatch(state, unit, slots, cfg)
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
			_send_to_quest(state, strategy, plan, unit, slots, cfg)


## 指令卡上的「派任务 / 取消派任务」。**和拖进任务栏是同一条路**：
## 这一格要维护「派出去的人也得在 `field` 名单里」那条不变量，不能绕过这里直接调 `toggle_dispatch`。
static func toggle_quest(
	state: PBRunState, strategy: PBStrategy, plan: PBWavePlan, unit: PBUnit, cfg: PBSimConfig
) -> void:
	if unit == null:
		return
	if state.dispatch_manual.has(unit.key()):
		PBShopRules.toggle_dispatch(state, unit, PBEconomyRules.QUEST_SLOTS, cfg)
		return
	_send_to_quest(state, strategy, plan, unit, PBEconomyRules.QUEST_SLOTS, cfg)


## 直接拖进任务栏。**从仓库拖也行，人口满了也行。**
##
## **顺序：先记派遣，再安排座位**。座位数 [method PBRunState.field_slots] 等于人口加上已经派出去几个，
## 在这一笔派遣记下来之前多出来的那一格还不存在 —— 反过来的话他会被 [method PBStrategy.lineup_units] 截掉，
## 而 [method PBShopRules.toggle_dispatch] 又要在 `field` 里找他，表现是拖过去没反应。
##
## 「记派遣」和「进 `field`」是同一件事的两半（[method PBRunState.dispatch_picks] 找不到人就整份名单作废），
## 所以只能有一个入口。中间那次 [method PBStrategy.deploy] 不多余：只有它会重写 `field`。
static func _send_to_quest(
	state: PBRunState,
	strategy: PBStrategy,
	plan: PBWavePlan,
	unit: PBUnit,
	slots: int,
	cfg: PBSimConfig
) -> void:
	if not PBShopRules.toggle_dispatch(state, unit, slots, cfg):
		return
	var roster: Array[PBUnit] = strategy.deploy(state, plan.wave, cfg)
	if roster.has(unit):
		return
	roster.append(unit)
	strategy.set_lineup(state, roster)
	strategy.deploy(state, plan.wave, cfg)
