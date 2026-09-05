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
## 只有 [constant PBSkill.Target.GROUND] 档用得上它。
##
## **M7-c 起它不再是「有没有待落地」的判据** —— 那个判据搬到了
## [member lands_at]，见 [method is_pending]。
var spot: Vector2 = NO_SPOT

## 锁定的那一个己方单位（[member PBAttacker.slot]），
## [constant PBSkill.Target.ALLY] 档用（M7-c）。**-1 表示没锁定谁。**
##
## 存**槽位号**不存引用：§12 的存档要序列化它，而引用序列化不了 ——
## 和 [member PBProjectile.target] 同一条规矩。
var target_slot: int = -1

## 待落地的技能在第几 tick 结算。**-1 表示手上没有待落地的技能。**
var lands_at: int = -1

## 施法者的等级，**只用来算效果数值**（决策 7，M7-c）。
##
## ## 为什么记等级，而不是把算完的数值记下来
##
## [PBAttacker] 身上没有 `level` 这个字段，也不该有 —— 它顶上写着
## 「属性克制、科技、羁绊、装备**全部已经乘进来了**」，等级和它们是同一类东西。
## 所以这个数必须在**建攻击者那一刻**存进来，落地时 sim 才问得到。
##
## 但**算完的数值不能提前存**：[PBSkill] 在建好之后还会被改
## （[method PBBondFunctionRules.apply_to_skill] 就是这么干的），
## 预先算好一份的话，后改的那一下不会跟着更新，而它不报错 ——
## 表现是「这个羁绊功能好像没生效」。存等级、用的时候现算，就没有第二份真相。
##
## 默认 1 —— 尾兽、敌人、以及不关心等级的技能走的就是这一档，
## 成长项贡献 0，取到的就是基数。
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
##
## ## 判据是 [member lands_at]，不是「有没有落点」（M7-c 改的）
##
## M7-b 之前只有 [constant PBSkill.Target.GROUND] 一种技能，
## 「有落点」和「有一发在路上」永远同时成立，所以拿 `spot` 当哨兵是够用的。
## [constant PBSkill.Target.NONE] 档进来之后那条等价关系断了 ——
## 它既没有落点也没有锁定目标，但**照样有一发在路上**。
##
## 换成 `lands_at` 对 GROUND 档是**逐位等价**的：`spot` 和 `lands_at`
## 在 [method cast] / [method land] / [method reset] 里从来都是一起设、一起清。
func is_pending() -> bool:
	return lands_at >= 0


## 下达一发**地面**技能：把落点定死，开始走施法延迟。
## **落点此后不再改** —— 那正是预判的代价。
func cast(at_spot: Vector2, tick: int) -> void:
	spot = Vector2(maxf(at_spot.x, 0.0), at_spot.y)
	lands_at = tick + skill.delay_ticks


## 下达一发**锁定己方单位**的技能（[constant PBSkill.Target.ALLY]，M7-c）。
##
## 锁的是槽位不是位置：目标会跑，而「治谁」这件事不该跟着他的坐标走。
func cast_on(slot: int, tick: int) -> void:
	target_slot = slot
	lands_at = tick + skill.delay_ticks


## 下达一发**不需要目标**的技能（[constant PBSkill.Target.NONE]，M7-c）。
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
