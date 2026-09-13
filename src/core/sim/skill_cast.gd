class_name PBSkillCast
extends RefCounted
## 一份技能**这一波的状态**：冷却转好没有、有没有待落地的落点。
##
## [PBSkill] 是定义，本类是「这一份在这个攻击者身上进行到哪了」，默认字段就是「一波刚开始」。
##
## **跨波、跨探测复用**：[PBBattleSim] 构造时对每一格调 [method reset]，
## 不清的话上一场的冷却漏进下一场，表现为「有几波技能莫名其妙放不出来」。

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

## 已下达但还没落地的落点。只有 [constant PBSkill.Target.GROUND] 档用得上它。
## 「有没有待落地」的判据是 [member lands_at]，见 [method is_pending]。
var spot: Vector2 = NO_SPOT

## 锁定的那一个单位的槽位。**-1 表示没锁定谁。**
##
## **指向哪个数组由 [member PBSkill.target] 说**：`ALLY` 档是 [member PBAttacker.slot]，
## `ENEMY` 档是 [member PBEnemy.slot]。一个字段，否则「这一发锁的是谁」有两个答案。
## 存槽位号不存引用：存档要序列化它。
var target_slot: int = -1

## 待落地的技能在第几 tick 结算。**-1 表示手上没有待落地的技能。**
var lands_at: int = -1

## 施法者的等级，**只用来算效果数值**。
##
## [PBAttacker] 身上没有 `level`，所以建攻击者那一刻存进来。**存等级不存算完的数值**：
## [PBSkill] 建好之后还会被改（[method PBBondFunctionRules.apply_to_skill]），
## 预先算好的那份不会跟着更新。默认 1（尾兽、敌人、不关心等级的技能）。
var caster_level: int = 1


## [param level] 见 [member caster_level]。
func _init(from_skill: PBSkill, level: int = 1) -> void:
	skill = from_skill
	caster_level = maxi(level, 1)


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
	target_slot = -1
	lands_at = -1


## 这一波打完之后还欠多少冷却。[param ticks] 是本波的总 tick 数。
##
## 结算在这里而不是让调用方自己减，是因为「冷却还剩多久」这件事
## 只有本类知道它的表示方式 —— 存两处迟早对不上。
func cooldown_left(ticks: int) -> int:
	return maxi(ready_at - ticks, 0)


## 冷却转好、且手上没有待落地的技能 —— 也就是「现在可以下达」。
func is_ready(tick: int) -> bool:
	return not is_pending() and tick >= ready_at


## 已下达、还没落地。渲染层要画预示圈的就是这个状态。
## 判据是 [member lands_at] 而不是「有没有落点」：[constant PBSkill.Target.NONE] 档没有落点，但照样有一发在路上。
func is_pending() -> bool:
	return lands_at >= 0


## 下达一发**地面**技能：把落点定死，开始走施法延迟。
## **落点此后不再改** —— 那正是预判的代价。
func cast(at_spot: Vector2, tick: int) -> void:
	spot = Vector2(maxf(at_spot.x, 0.0), at_spot.y)
	lands_at = tick + skill.delay_ticks


## 下达一发**锁定单个单位**的技能（`ALLY` / `ENEMY` 两档）。
## 锁槽位不锁位置：目标会跑。
func cast_on(slot: int, tick: int) -> void:
	target_slot = slot
	lands_at = tick + skill.delay_ticks


## 下达一发**不需要目标**的技能（[constant PBSkill.Target.NONE]）。
func cast_now(tick: int) -> void:
	lands_at = tick + skill.delay_ticks


## 结算完毕，转入冷却。
##
## 冷却从**落地**算起而不是从下达算起：下达到落地之间技能还在飞，
## 从下达算等于把施法延迟白送成冷却的一部分，延迟越长反而越强。
func land(tick: int) -> void:
	spot = NO_SPOT
	target_slot = -1
	lands_at = -1
	ready_at = tick + skill.cooldown_ticks
