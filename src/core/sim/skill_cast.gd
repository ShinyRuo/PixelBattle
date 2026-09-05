class_name PBSkillCast
extends RefCounted
## 一份技能**这一波的状态**：冷却转好没有、有没有待落地的落点。M7-b。
##
## [PBSkill] 是定义（不可变、逐人一份）；本类是「这一份挂在这个攻击者身上，
## 这一波它进行到哪了」。拆开之后 [method PBSkill.clone] 只带设定、
## 本类的默认字段就是「一波刚开始、什么都没放过」的状态 ——
## 两边各自只有一件事要记，[method reset] 因此不必再记「清哪几个字段」。
##
## ## 这个类会被跨波、跨探测复用
##
## 悬崖二分一次要建几十场战斗，[PBBattleSim] 在构造时对每个攻击者的
## [member PBAttacker.ultimate] 调一次 [method reset]。不清的话上一场剩下的
## 冷却会漏进下一场，表现为「有几波技能莫名其妙放不出来」，且不报任何错。

## 「没有落点」的哨兵。[member spot] 与 [method PBAimRules.pick_spot] 共用它。
##
## 合法落点的 x 必然 ≥ 0（0 就是基地），所以负 x 可以当哨兵用，
## 不必再多一个 `pending: bool` —— 多一个字段就是多一份真相，
## 而漏同步一次的表现是「技能卡在手上再也放不出来」。
##
## 定义在这里而不是 [PBAimRules]：**字段在谁身上，哨兵就归谁**。
## 反过来的话本类要引用 `PBAimRules`，而后者本来就依赖本类。
const NO_SPOT: Vector2 = Vector2(-1.0, -1.0)

## 这份设定。**永远不为 null**——本类不管理它的生命周期，
## 只借用它的数值；由谁建、建几份，是调用方的事（见 [method PBSkill.clone]）。
var skill: PBSkill = null

## 第几 tick 起冷却转好。
var ready_at: int = 0

## 已下达但还没落地的落点（M4-a 起是二维，见 [PBAimRules]）。
##
## **x 为负表示当前没有待落地的技能**，而合法落点的 x 必然 ≥ 0（0 就是基地）。
var spot: Vector2 = NO_SPOT

## 待落地的技能在第几 tick 结算。
var lands_at: int = -1


func _init(from_skill: PBSkill) -> void:
	skill = from_skill


## 这是不是一个真落点（而不是 [constant NO_SPOT]）。
static func is_spot(at: Vector2) -> bool:
	return at.x >= 0.0


## 把冷却与待落地状态清回开波状态。
##
## [member PBSkill.carry_over_ticks] 不为 0 时，这一波开局就欠着那么多冷却 ——
## 尾兽的底牌因此跨波稀缺，见那个字段的说明。
func reset() -> void:
	ready_at = skill.carry_over_ticks
	spot = NO_SPOT
	lands_at = -1


## 这一波打完之后还欠多少冷却。[param ticks] 是本波的总 tick 数。
##
## 结算在这里而不是让调用方自己减，是因为「冷却还剩多久」这件事
## 只有本类知道它的表示方式 —— 存两处迟早对不上。
func cooldown_left(ticks: int) -> int:
	return maxi(ready_at - ticks, 0)


## 冷却转好、且手上没有待落地的技能 —— 也就是「现在可以下达」。
func is_ready(tick: int) -> bool:
	return not is_spot(spot) and tick >= ready_at


## 已下达、还没落地。渲染层要画预示圈的就是这个状态。
func is_pending() -> bool:
	return is_spot(spot)


## 下达：把落点定死，开始走施法延迟。**落点此后不再改** —— 那正是预判的代价。
func cast(at_spot: Vector2, tick: int) -> void:
	spot = Vector2(maxf(at_spot.x, 0.0), at_spot.y)
	lands_at = tick + skill.delay_ticks


## 结算完毕，转入冷却。
##
## 冷却从**落地**算起而不是从下达算起：下达到落地之间技能还在飞，
## 从下达算等于把施法延迟白送成冷却的一部分，延迟越长反而越强。
func land(tick: int) -> void:
	spot = NO_SPOT
	lands_at = -1
	ready_at = tick + skill.cooldown_ticks
