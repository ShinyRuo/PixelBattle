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
		# 门槛是 [method PBRunState.field_slots] 不是 `open_slots` ——
		# **出任务的那几个不占人口**（M5-9），他们这一波不在场上。
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
	# 任务栏一共 4 个槽，**和「本波要几个」不是一个数**（M5-7）——
	# 塞多了才可能「人数不符」，见 [constant PBEconomyRules.QUEST_SLOTS]。
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


## 指令卡上的「派任务 / 取消派任务」。**和拖进任务栏是同一条路。**
##
## M5-13 之前这一格在 [PBBattleView] 里直接调 [method PBShopRules.toggle_dispatch]，
## 也就是说 CLAUDE.md 里那句「指令卡走的是同一批函数」对这一格**不成立** ——
## 而它是三格里唯一需要维护「派出去的人也得在 `field` 名单里」那条不变量的。
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
## ## 顺序反过来了：先记派遣，再安排座位
##
## 直觉的顺序是「先站上出战席，再标成出任务」，而它**结构上做不到**：
## 座位数 [method PBRunState.field_slots] 等于人口加上**已经派出去几个人**，
## 所以在这一笔派遣被记下来之前，多出来的那一格还不存在 ——
## [method PBStrategy.lineup_units] 会当场把他截掉，
## 而 `field` 里没有他，[method PBShopRules.toggle_dispatch] 又要在那里找他。
## 一个先有鸡还是先有蛋的死结，表现是**拖过去没反应**。
##
## 记完派遣，那一格就有了，他才坐得下。**这个顺序是这段代码存在的全部理由**。
##
## ## 两处状态要一起改，所以只能有一个入口
##
## [method PBRunState.dispatch_picks] 要在 [method PBRunState.field_units]
## 里找得到这个人，找不到就**整份名单作废、退回末尾规则**（不报错，
## 只表现为「我选的人怎么没去」）。也就是说「记派遣」和「进 `field`」
## 是同一件事的两半，各写一份迟早分叉。
##
## 中间那次 [method PBStrategy.deploy] 不是多余的：`field` 只有
## [method PBStrategy.bring_to_field] 会重写，而上面改的是
## [member PBRunState.lineup] —— 不再问一次，`field` 就还是旧的那一份。
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
