class_name PBUltimate
extends RefCounted
## 一个出战单位的大招，**以及它这一波的冷却/待落地状态**。M3-b。
##
## ## 为什么大招必须有施法延迟
##
## §02 把吸怪技巧做成分层的：手机端点一下自动选落点，PC 端手动指定、
## **可以预判走位**。那条分层是整个 M3-b 的验收对象
## （「自动落点达到手动的 78%」「手动带来 15–25% 提升」）。
##
## 而**预判只有在落点先于结算确定时才存在**。大招要是当场结算，
## 「提前半秒把落点压在敌人行进路线前方」在模型里就是一句空话 ——
## 当前帧最密的点永远等于结算时最密的点，自动和手动必然同分，
## 那两条验收量出来恒等于 100%，看着达标其实什么都没测。
##
## 所以落点在**下达时**定死（[method cast]），伤害在 `delay_ticks` 之后
## 才落地（[method land]）。这中间的窗口就是敌人走动的距离，也就是
## 预判能赚到的那部分 —— 顺带它正是渲染层要画的**落点预示圈**。
##
## ## 与 [PBAttacker] 的分工
##
## [PBAttacker] 管普攻（每 tick 恒定输出、按射程分配目标）；
## 本类管大招（长冷却、一次性、有落点）。两者的目标选择规则完全不同，
## 合在一起写会让「按射程选最靠近基地的」和「按密度选一个落点」
## 这两套逻辑互相纠缠。

## 「没有落点」的哨兵。[member spot] 与 [method PBAimRules.pick_spot] 共用它。
##
## 合法落点的 x 必然 ≥ 0（0 就是基地），所以负 x 可以当哨兵用，
## 不必再多一个 `pending: bool` —— 多一个字段就是多一份真相，
## 而漏同步一次的表现是「大招卡在手上再也放不出来」。
##
## 定义在这里而不是 [PBAimRules]：**字段在谁身上，哨兵就归谁**。
## 反过来的话 `PBUltimate` 要引用 `PBAimRules`，而后者本来就依赖前者。
const NO_SPOT: Vector2 = Vector2(-1.0, -1.0)

## 伤害属性。**§03 铁律：element 挂在伤害事件上，不挂在单位上。**
##
## 大招是这条铁律第一次真正用上的地方 —— 在此之前一个角色只有一个输出来源，
## 单位属性和伤害属性恰好重合，铁律看起来像句空话。
## 现在「迪达拉本体土属性但大招是火系」这种角色做得出来了。
var element: PBElement.Type = PBElement.Type.PHYSICAL

## 一发打多少。属性克制、科技、羁绊、装备**全部已经乘进来了**，
## 和 [member PBAttacker.dps] 一样，战斗层只认这个数。
var damage: float = 0.0

## 杀伤半径。**M4-a 起是以 [member spot] 为圆心的一个真圆。**
##
## 在那之前战场是一维的，它只作用在推进轴上（覆盖
## `[spot - radius, spot + radius]`，纵向全覆盖）—— 渲染层因此把落点
## **画成一条竖带而不是圈**，理由写在 [PBTelegraphPool] 顶部：
## 画成圆会让玩家去躲一个根本不存在的纵向判定。
##
## 纵向开始算数之后那条理由反过来了：现在圆才是真相，带子才是谎话。
## **一发大招因此比以前弱**（圆的面积小于横贯全场的带子），归数值回归。
var radius: float = 0.0

## 冷却多少 tick。§02 给的是 15–30 秒。
var cooldown_ticks: int = 0

## 下达到落地之间隔多少 tick。见本类顶部「为什么大招必须有施法延迟」。
var delay_ticks: int = 0

## 一发最多命中几个。**0 表示不限**（半径内全中）。
##
## M3-d 加的，为了让「超大单体爆发」这种大招表达得出来 ——
## 单体和范围的区别在 §04 里是**波型价值分化**的支点（潮水波偏 AOE、
## 精英波偏单体），只有伤害数字的话那条分化不成立。
var max_targets: int = 0

## 落地时是否把范围内的敌人拖到落点（§02 的「拉拽」）。
##
## §02 要求约 4–6 名角色带这个，且**必须分散在多个不同羁绊里** ——
## 否则抽不到聚拢手段的局直接废了，这在无限流里是致命的。
## **M3-b 全表都是 false**，一个都没分配：谁该带拉拽要么由技能表决定，
## 要么得有扫描依据，现在拍几个角色会污染正在量的那两条验收。
## 机制本身已经实现并测过，`--gather-share` 可以在不改角色表的前提下量它值多少。
##
## M3-d 起七尾的大招也走这个字段 —— §11 要的「不依赖特定羁绊的聚怪路径」
## 因此和角色的拉拽是同一套机制，不是平行的第二份实现。
var gather: bool = false

# ── 位置与状态操纵（M3-d）──────────────────────────────────────
#
# 下面这五个字段是 §11 的机制型尾兽（七尾聚拢、六尾重置 CD、一尾减速、
# 三尾击退、二尾增伤）在战斗层的全部落点，**同时也是 §09 功能档
# （聚拢 / 吸附 / 定身 / 减速）要的那套词汇**。
#
# 写在 [PBUltimate] 而不是单开一个「尾兽大招」类，是因为两者的结算规则
# 逐条相同（有冷却、有落点、有施法延迟、按半径圈人）。分成两份的话，
# §09 的功能档落地时会再抄第三份，而三份的落点判定迟早对不上。

## 落地时把范围内的敌人往出生点方向推多远。与 [member PBEnemy.distance] 同轴。
##
## 和 [member gather] 是相反方向的两种位置操纵。两者都不产生伤害，
## 价值全在「敌人晚到基地多久」上 —— 那正是塔防里位置操纵的定价方式。
var knockback: float = 0.0

## 落地后敌人的速度倍率（0 = 定身，0.5 = 减速一半，1.0 = 不减速）。
##
## **减速是全场的，不按半径圈人。** 一尾的「全屏减速力场」和五尾的
## 「地形阻挡」在 §11 里都写着「全屏 / 延缓推进」，圈人反而不合规格；
## 而 §09 的功能档要按半径减速时，加一个「减速也吃半径」的开关即可，
## 那时才有依据决定它该不该吃。
var slow_scale: float = 1.0

## 减速持续多少 tick。
var slow_ticks: int = 0

## 落地后全队普攻伤害的倍率（1.15 = 短时全队 +15%）。
var team_damage_scale: float = 1.0

## 全队增伤持续多少 tick。
var buff_ticks: int = 0

## 落地时把**其他**大招的冷却清零（六尾）。
##
## 清的是别人不是自己 —— 自己也清的话它会在同一 tick 无限自我重置。
## 这一条的强度与队伍里大招的总量成正比，而不是和它自己的数值成正比，
## §11 说的「机制型尾兽」指的就是这种依赖关系。
var reset_cooldowns: bool = false

## 放一发要花多少蓝（§03A，M3.5-d）。**0 表示不耗蓝。**
##
## ## 为什么冷却和蓝两道门槛都要
##
## 冷却管的是「这一发多久来一次」，蓝管的是「连着放几发」。只有冷却时，
## 智力没有任何用途，而 §03A 的信息栏要显示蓝条 —— 显示一个不参与战斗的数字
## 比不显示更糟。只有蓝时，§11 尾兽的跨波冷却（「在哪一波交底牌」的全部机制）
## 和 §09 六尾的「重置全体 CD」功能档会一起废掉，所以冷却那一套一条都没动。
##
## 两道门槛还产生了一个没预料到但很对的互动：**六尾的「重置全体冷却」
## 不再是免费的连放** —— 冷却清零了，蓝还得攒。
##
## **尾兽大招恒为 0。** 它的稀缺性靠 75 秒的跨波冷却（§11），
## 再加一道蓝门槛等于把同一件事收两次费，而尾兽本来也不是「一个有蓝条的人」。
var mp_cost: float = 0.0

## 第几 tick 起冷却转好。
var ready_at: int = 0

## 开波时**还欠多少 tick 的冷却**。[method reset] 把 [member ready_at] 设成它。
##
## ## 为什么需要跨波的冷却，而角色大招不需要
##
## 冷却本来是每波清零的（见 [method reset]），因为角色大招 20 秒、单波约 16 秒 ——
## 「大部分波次每人放得出一发」正是 §02 想要的决策密度，清不清零结果一样。
##
## **尾兽不是这样。** §11 给的是 75 秒 ≈ 每 2 波一次，原话是
## 「这个节奏让玩家必须选择在哪一波交底牌 —— BOSS 波前存着，
## 还是这波就要顶不住了」。每波清零的话它**每波都放得出**，
## 那个决策在模型里根本不存在 —— 而它是 §11 整节的核心。
##
## 实测过代价：清零时九只尾兽整局各放 28–33 发（等于波数），
## 而按 75 秒算只该有 7 发左右。差了四五倍，排序因此完全不可信。
var carry_over_ticks: int = 0

## 已下达但还没落地的落点（M4-a 起是二维，见 [PBAimRules]）。
##
## **x 为负表示当前没有待落地的大招**，而合法落点的 x 必然 ≥ 0
## （0 就是基地）。哨兵仍然只看 x：加一个 `pending: bool` 就有两份真相，
## 而漏同步一次的表现是「大招卡在手上再也放不出来」。
var spot: Vector2 = NO_SPOT

## 待落地的大招在第几 tick 结算。
var lands_at: int = -1


## 复制一份，**只带设定不带这一波的冷却状态**（见 [method reset]）。
func clone() -> PBUltimate:
	var out := PBUltimate.new()
	out.element = element
	out.damage = damage
	out.radius = radius
	out.cooldown_ticks = cooldown_ticks
	out.delay_ticks = delay_ticks
	out.max_targets = max_targets
	out.carry_over_ticks = carry_over_ticks
	out.mp_cost = mp_cost
	out.gather = gather
	out.knockback = knockback
	out.slow_scale = slow_scale
	out.slow_ticks = slow_ticks
	out.team_damage_scale = team_damage_scale
	out.buff_ticks = buff_ticks
	out.reset_cooldowns = reset_cooldowns
	return out


## 把冷却与待落地状态清回开波状态。
##
## [PBBattleSim] 在构造时对每个大招调一次。**大招对象会被跨波、跨探测复用**
## （悬崖二分一次要建几十场战斗），不清的话上一场剩下的冷却会漏进下一场，
## 表现为「有几波大招莫名其妙放不出来」，而且不报任何错。
## [member carry_over_ticks] 不为 0 时，这一波开局就欠着那么多冷却 ——
## 尾兽的底牌因此跨波稀缺，见那个字段的说明。
func reset() -> void:
	ready_at = carry_over_ticks
	spot = NO_SPOT
	lands_at = -1


## 这是不是一个真落点（而不是 [constant NO_SPOT]）。
static func is_spot(at: Vector2) -> bool:
	return at.x >= 0.0


## 这一波打完之后还欠多少冷却。[param ticks] 是本波的总 tick 数。
##
## 结算在这里而不是让调用方自己减，是因为「冷却还剩多久」这件事
## 只有本类知道它的表示方式 —— 存两处迟早对不上。
func cooldown_left(ticks: int) -> int:
	return maxi(ready_at - ticks, 0)


## 冷却转好、且手上没有待落地的大招 —— 也就是「现在可以下达」。
func is_ready(tick: int) -> bool:
	return not is_spot(spot) and tick >= ready_at


## 已下达、还没落地。渲染层要画预示圈的就是这个状态。
func is_pending() -> bool:
	return is_spot(spot)


## 下达：把落点定死，开始走施法延迟。**落点此后不再改** —— 那正是预判的代价。
func cast(at_spot: Vector2, tick: int) -> void:
	spot = Vector2(maxf(at_spot.x, 0.0), at_spot.y)
	lands_at = tick + delay_ticks


## 结算完毕，转入冷却。
##
## 冷却从**落地**算起而不是从下达算起：下达到落地之间大招还在飞，
## 从下达算等于把施法延迟白送成冷却的一部分，延迟越长反而越强。
func land(tick: int) -> void:
	spot = NO_SPOT
	lands_at = -1
	ready_at = tick + cooldown_ticks
