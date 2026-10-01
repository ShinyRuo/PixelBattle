class_name PBBuffState
extends RefCounted
## **一份正在生效的效果**。对应 UE GAS 的 `ActiveGameplayEffect`。
##
## [PBBuff] 是定义，本类是「挂在这个单位身上、什么时候到期、谁给的、算完是多少」。
##
## **由 [PBBuffBag] 复用**，入口是 [method take]。普通槽预分配，独立叠层槽仅在池不足时扩容。
##
## **数值在挂上来之前就算完了**：[member mods] 存的是这个施法者、这个等级下的实际数值，
## 战斗层不认识等级 —— 现算的话 [PBAttacker] 就得带上一个 `level` 字段。

## 这份是哪个效果。**null 表示这个槽位是空的** —— 不另开一个 `alive` 布尔：
## 多一个字段就是多一份真相，而漏同步一次的表现是「一个空槽位在参与合计」。
var buff: PBBuff = null

## 各个效果键这一份实际是多少（等级已经算进去，见 [method PBBuffRules.resolve]）。
var mods: Dictionary = {}

## 第几 tick 之后失效。**判据是 `at_tick <= until_tick`（含）**。
var until_tick: int = -1
var applied_at: int = -1

## 每隔几 tick 触发一次。0 = 不是周期型。
var period_ticks: int = 0

## 下一次触发在第几 tick。
var next_tick_at: int = -1

## 谁给的（[member PBAttacker.slot]）。战斗结算不读它，它只喂日志与界面 ——
## 和 [member PBProjectile.source] 同一条理由：落地那一刻「谁离得最近」
## 和「谁给的」可以是两个人，而猜错不报错。
var source_slot: int = -1

var harm_context: PBHarmContext = null
var channel: PBSkillChannel = null


## 把这个实例重置成一份刚挂上的效果。**复用走这里，不要 `.new()`。**
func take(
	from: PBBuff, values: Dictionary, at_tick: int, ticks: int, period: int, from_slot: int
) -> void:
	buff = from
	mods = values
	until_tick = at_tick + ticks
	applied_at = at_tick
	period_ticks = period
	# 第一次触发在**一个周期之后**，不是挂上的当场 —— 当场那一下属于
	# 技能自己的瞬间载荷（`on_hit` 里另配一个 INSTANT），
	# 两者合在一起的话「持续 5 秒每秒回 20」会回 6 次而不是 5 次。
	next_tick_at = at_tick + period if period > 0 else -1
	source_slot = from_slot
	harm_context = null
	channel = null


## 腾空这个槽位。
func clear() -> void:
	buff = null
	mods = {}
	until_tick = -1
	applied_at = -1
	period_ticks = 0
	next_tick_at = -1
	source_slot = -1
	harm_context = null
	channel = null


## 这一 tick 它还算不算数。
func is_live(at_tick: int) -> bool:
	return (
		buff != null
		and (buff.until_wave_end or at_tick <= until_tick)
		and (channel == null or channel.is_live(at_tick))
	)


## 还剩几 tick 到期。已经空了或过期了都返回 0。[PBBuffBag] 满了顶掉剩余最短的那一个。
func left(at_tick: int) -> int:
	if not is_live(at_tick):
		return 0
	if buff.until_wave_end:
		return 2147483647
	return until_tick - at_tick + 1


## 这一 tick 该不该触发一次周期载荷。
func is_due(at_tick: int) -> bool:
	return is_live(at_tick) and period_ticks > 0 and at_tick >= next_tick_at


## 触发过了，排下一次。
func on_fired(at_tick: int) -> void:
	next_tick_at = at_tick + maxi(period_ticks, 1)
