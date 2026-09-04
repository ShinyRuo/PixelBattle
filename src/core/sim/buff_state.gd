class_name PBBuffState
extends RefCounted
## **一份正在生效的效果**（M7-a）。对应 UE GAS 的 `ActiveGameplayEffect`。
##
## [PBBuff] 是定义（不可变、全局一份），本类是「这一份挂在这个单位身上，
## 什么时候到期、是谁给的、数值算完之后是多少」。
##
## ## 这个类会被 [PBBuffBag] 复用，不要在战斗中 `.new()`
##
## 和 [PBEnemy]、[PBProjectile] 同一条规矩（§14）：GDScript 每 tick 创建
## 大量临时对象会触发频繁的引用计数开销。复用的入口是 [method take]。
##
## ## 数值在挂上来之前就算完了
##
## [member mods] 存的是**这个施法者、这个等级下的实际数值**，
## 不是 [member PBBuff.mods] 那份基数。理由和 [member PBAttacker.dps]
## 顶上那句一样：战斗层不认识等级、稀有度、装备这些系统，它只认这个数。
## 现算的话，[PBAttacker] 就得带上一个 `level` 字段，而那是把
## 「已经乘死的倍率」这条约定撕开一个口子。

## 这份是哪个效果。**null 表示这个槽位是空的** —— 不另开一个 `alive` 布尔：
## 多一个字段就是多一份真相，而漏同步一次的表现是「一个空槽位在参与合计」。
var buff: PBBuff = null

## 各个效果键这一份实际是多少（等级已经算进去，见 [method PBBuffRules.resolve]）。
var mods: Dictionary = {}

## 第几 tick 之后失效。**判据是 `at_tick <= until_tick`（含）** ——
## 和 [PBBattleSim] 原来那对 `_buff_scale` / `_buff_until` 逐字一致，
## M7-a 的迁移靠这个等号保持逐位相同。
var until_tick: int = -1

## 每隔几 tick 触发一次。0 = 不是周期型。
var period_ticks: int = 0

## 下一次触发在第几 tick。
var next_tick_at: int = -1

## 谁给的（[member PBAttacker.slot]）。战斗结算不读它，它只喂日志与界面 ——
## 和 [member PBProjectile.source] 同一条理由：落地那一刻「谁离得最近」
## 和「谁给的」可以是两个人，而猜错不报错。
var source_slot: int = -1


## 把这个实例重置成一份刚挂上的效果。**复用走这里，不要 `.new()`。**
func take(
	from: PBBuff,
	values: Dictionary,
	at_tick: int,
	ticks: int,
	period: int,
	from_slot: int
) -> void:
	buff = from
	mods = values
	until_tick = at_tick + ticks
	period_ticks = period
	# 第一次触发在**一个周期之后**，不是挂上的当场 —— 当场那一下属于
	# 技能自己的瞬间载荷（`on_hit` 里另配一个 INSTANT），
	# 两者合在一起的话「持续 5 秒每秒回 20」会回 6 次而不是 5 次。
	next_tick_at = at_tick + period if period > 0 else -1
	source_slot = from_slot


## 腾空这个槽位。
func clear() -> void:
	buff = null
	mods = {}
	until_tick = -1
	period_ticks = 0
	next_tick_at = -1
	source_slot = -1


## 这一 tick 它还算不算数。
func is_live(at_tick: int) -> bool:
	return buff != null and at_tick <= until_tick


## 还剩几 tick 到期。已经空了或过期了都返回 0。
##
## [PBBuffBag] 满了要顶掉**剩余时间最短**的那一个，量的就是这个数。
func left(at_tick: int) -> int:
	if not is_live(at_tick):
		return 0
	return until_tick - at_tick + 1


## 这一 tick 该不该触发一次周期载荷。
func is_due(at_tick: int) -> bool:
	return is_live(at_tick) and period_ticks > 0 and at_tick >= next_tick_at


## 触发过了，排下一次。
func on_fired(at_tick: int) -> void:
	next_tick_at = at_tick + maxi(period_ticks, 1)
