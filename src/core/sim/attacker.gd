class_name PBAttacker
extends RefCounted
## 战场上的**一个己方攻击者**：这一波战斗里那张卡在场上的样子（一波一份，打完就扔）。
##
## 整队一个标量 DPS 集火最前面那个的话，数学上不存在「场上稳定有几个人」的中间态 ——
## 清得比出得快就是空场，慢就是雪崩。多个单位**按各自的射程各打各的**，敌人才会在行军里被慢慢磨。
##
## **站位是射程的派生量，不是独立字段**：射程短的站前排才够得着，射程长的站后排照样打得到。
## 玩家拖动过的由 [PBFormationRules] 覆盖。[PBUnit] 是跨波存在、进存档的那张卡。

## 攻击型。§02 那条乘法关系 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`
## 里的中间那个因子，就是靠这个枚举存在的。
##
## §04 用波型把两者的价值分开（潮水波是 AOE 的高光，精英波是单体的高光），
## 所以这两种不能只是数值差异，必须是**结算方式**的差异。
enum Shape {
	SINGLE,  ## 单体：全部伤害砸在一个目标上，打死了溢出接着打下一个
	AOE,  ## 范围：对射程内最多 [member max_targets] 个目标各打一份，不结算溢出
}

## 走过去的时候停在射程的**九成**上，不是踩着边界停。
##
## 停在正好 `reach` 处的话，[method can_reach] 量回来的浮点距离经常略大于 `reach`，
## 他站在射程边上却判定够不着 —— 表现是「离怪一点点距离原地跑」。
## 敌人那一侧（[constant PBCrowdRules.SIEGE_RING]）引用的是同一个数。
const STOP_RING: float = 0.9

## 出手最快几次每秒（玩家定的）。
##
## **结构性的墙，不是配平**：攻速加成叠起来会把间隔压到 1 tick（每秒 20 下）。
## **封在间隔上而不是攻速上**：间隔是整数 tick，只压攻速的话 3.4 次/秒会 round 成 6 tick = 3.33 次/秒，
## 仍然破了上限。名册里最快的是 0.919 次/秒，所以今天只会被加成顶到。
const ATTACK_SPEED_CAP: float = 3.0

## 重生之后剩几成血（[member revives]）。原版只说「保留部分血量」。
## 满血的话等于多一条命；太低会在同一 tick 被下一发打死，玩家看不见发生过什么。
const REVIVE_FRACTION: float = 0.4

## **一发普攻打多少**。属性克制、羁绊、尾兽光环、装备与训练的词条全部已经算进来了，战斗层只认这个数。
##
## 玩家定的口径：**每次攻击实时结算**，一发就是他的攻击力，出手多快由 [member attack_speed] 单独决定，
## 两者的乘积 [member dps] 只是统计量。
##
## **0 表示「没填」**，那时 [method prime] 退回由 dps 反推，只服务于只关心节奏的测试夹具。
## 生产代码的构造点全部填了，`tests/test_attack_speed.gd` 钉着「真名册建出来的每个人 `attack` > 0」。
var attack: float = 0.0

## 每秒伤害。**统计量，不是战斗的输入**（面板、估值读它）。
##
## 它还是**退化路径的输入**：[method whole_field] 造的攻击者攻速为 0，要与 [PBCombatRules] 的
## 解析式排队模型逐位相同，而那个模型里没有「一发」这个概念 —— [method prime] 在攻速为 0 时从这个数算每 tick 的伤害。
var dps: float = 0.0

## 战场坐标。x 与 [member PBEnemy.distance] 同一根轴、同一个单位（0 是基地，
## [member PBSimConfig.field_length] 是敌人的出生点）；y 是泳道，0 到 [member PBSimConfig.field_height]。
var pos: Vector2 = Vector2.ZERO

## 射程，**以 [member pos] 为圆心的一个真圆**。对称而不是只朝出生点那侧：
## 敌人会走过头，越过前排的敌人仍然在前排的攻击范围里。
var reach: float = 0.0

var shape: Shape = Shape.SINGLE

# ── 挨打这一半（§03A）──────────────────────────────────────────

## 血量上限。**0 表示「这不是一个真单位，只是一个标量」—— 敌人看不见它。**
##
## [method whole_field] 造的退化攻击者就是 0，那条路要与排队模型（前提之一是敌人不还手）逐位一致。
## 用「血是不是 0」而不是配置开关：一个没血的东西挨不了打，这是对象的性质，不需要有人记得去设。
var max_hp: float = 0.0

var hp: float = 0.0

## 防御。经 [method PBStatRules.damage_reduction] 折成减伤。
##
## 名字不叫 `def` 是怕和别的语言的关键字混淆，读代码的人会卡一下。
var defence: float = 0.0

## **防元素**（§03A）：敌人打它时按哪一系算克制。
##
## 和 [member dps] 里已经乘死的那个「攻元素克制」是**两个方向**：
## 那一份是「我打得动谁」，这一份是「我扛得住谁」。
## 拆开之后一张卡在两条线上指向不同的波次，攻防两轴才不会同进同退。
var def_element: PBElement.Type = PBElement.Type.PHYSICAL

## 还活着。死了就不再输出、也不再被选为目标；**每波开波满血复活**
## （[method revive]），一波之内的失误有真实代价但不会毁掉整局。
var alive: bool = true

## 蓝量上限（§03A），智力抬的就是这一项。**0 表示不用蓝**（尾兽的大招攻击者就是 0）。
var max_mp: float = 0.0

var mp: float = 0.0

## 每 tick 回多少蓝。按蓝上限的固定比例算，所以**智力同时抬池子和回速** ——
## 只抬池子的话，高智力只意味着「能存更多发」，攒满的速度一样，
## 那个属性就只在连放时有意义，平时等于没有。
var mp_regen: float = 0.0

# ── 跑动（§02 / §03A）───────────────────────────────────────────

## 出生站位。x 由射程档派生（§02），y 是泳道。
## **跑动是围着它做的，不是取代它。**
var home: Vector2 = Vector2.ZERO

## 每 tick 能挪多远。**0 表示这东西不动**（退化标量就是 0，对拍路径不受跑动影响）。
var move_speed: float = 0.0

## 最多能离开 [member home] 多远（往敌人那侧）。
## 「自由跑向敌人」会让所有人挤到最前面，§02 的射程梯度就没了；拴住之后是围着自己那一列的小幅前压。
var leash: float = 0.0

## AOE 一次能命中几个。单体型不读这个字段。
var max_targets: int = 1

## **整波常驻**的暴击率（羁绊光环、被动、尾兽光环）。
##
## 不放进 [member buffs]：袋子同 id 整份覆盖，两份光环会静默吃掉一份；而且袋子有槽位上限、有时长、有清扫，
## 对「整波不变、没有施法者」的东西全是错的。临时那一份走袋子，两者在 [method PBCritRules.chance_of] 相加。
## **0 = 从不暴击，而且一次骰子都不掷**（见 [PBCritRules] 顶部）。
var crit_chance: float = 0.0

## **整波常驻**的暴击伤害加成，「额外多打几成」。理由同 [member crit_chance]，中性值是 0.0。
var crit_bonus: float = 0.0

# ── 触发型 ──────────────────────────────────────────────────────
#
# 和上面两个暴击字段同一档：开波就装好、整波不变。全部默认 0 = 什么都不发生，没人配时一位都不动。

## 命中之后给自己挂多久的暴击率加成（B10 绝牛雷犁热刀）。0 = 不挂。
##
## 它写进 [PBBuffBag]（[constant PBBuffRules.CRIT_CHANCE]）而不是直接改
## [member crit_chance] —— 那一份是**常驻**的，改了就再也退不回去。
var crit_on_hit: float = 0.0

## 命中时对目标周围的其他敌人各打这一下伤害的几成（B15 神赐予的伤痛）。0 = 不溅射。
var splash_damage: float = 0.0

## 打**血还很多**的敌人时额外多打几成（B05 日向兄妹）。0 = 没有。
##
## §7 的原话是「柔拳百分比伤害对高血量敌人必定触发」。做成一笔追加伤害
## 而不是「按当前血量的百分比」，是因为后者对 BOSS 是一条指数曲线 ——
## §04 的 BOSS 血量按波次指数长，百分比伤害会让这一组羁绊在后期独占全场。
var heavy_bonus: float = 0.0

## 一波之内还能重生几次（B02 不死二人组）。**工作计数器，[method revive] 会把它
## 重填回 [member revives_max]。**
var revives: int = 0

## 一波给几次重生。**必须和 [member revives] 分开** —— 攻击者对象会跨波、
## 跨探测复用（见 [method revive] 顶上那条），只有一个字段的话
## 「上一波已经用掉了」会漏进下一波，表现是「第二次凑满就不复活了」。
## 同 [member max_hp] / [member hp] 那一对。
var revives_max: int = 0

## 挨一下普攻时有多大机会一点血都不掉。0 = 从不闪避，而且**一次骰子都不掷**。
## 判据在 [method take_damage] **里面**（[method PBPassiveRules.dodges]）—— 己方挨打有两个落点，
## 各判一次的表现是「被子弹打就闪不掉」。
var dodge: float = 0.0

## 打出要害那一下额外按目标**当前**生命的几成再打一笔。0 = 没有。上限见 [constant PBStrikeRules.BITE_CAP]。
## **骑在暴击那个掷点上，不另掷一次**（代价：暴击光环会同时提高它的触发率）。
var bite_current: float = 0.0

## 同 [member bite_current]，但按目标**已经损失**的生命算（长十郎的骨拔）。
## 两个是互补的：一个越打越弱，一个越打越强。
var bite_lost: float = 0.0

## 挨一下就把这一下伤害的几成还给打他的那个敌人。0 = 不反弹。读点在 [method PBStrikeRules.hurt_ally]。
##
## **降级**：原版是「免疫了的那一下才反弹」，这里是挨每一下都反弹 —— 绑在 [member dodge] 上的话，
## 一个没配闪避的角色配上反弹会永远不生效。原版「每隔 5 秒必定触发一次」缺内置 CD 读点。
var reflect: float = 0.0

## 常驻增伤：这个人的**普攻**多打几成。0 = 不多打。
##
## **存「额外」不存倍数**：两份 +40% 相加是 +80%，不是被连乘成 +96%。
## 和效果袋里临时的 [constant PBBuffRules.DAMAGE_SCALE] 是一对，两者在 [method strike_for] 相乘。
##
## **降级**：只作用在普攻上，原版写的是「所有伤害」—— 技能伤害在建人那一刻就算死了，
## 而这一份是建人之后才装上去的（羁绊要先知道谁在场）。
var damage_bonus: float = 0.0


## 常驻加速：移动速度多几成。中性 0.0。
## 移速不是角色属性（全队一个数，由 [member PBSimConfig.unit_move_seconds] 派生），所以留在行为层、
## 折算在 [method PBPassiveRules.equip] 末尾。
var move_speed_bonus: float = 0.0


## 打出要害那一下顺带挂在目标身上的效果。读点在 [method PBStrikeRules.land]。
## 被动那条通道带得了一份效果靠它（名册 `on_hit=<效果键>`）。**骑在暴击那个掷点上。**
var on_hit_buffs: Array[PBBuff] = []

## 这个位子是给召唤物留的，不是一张卡。**一辈子不会变**，跑动中只在「空着」和「站着人」之间切。
## 为什么预留而不是跑动中往数组里塞人，见 [PBSummonRules] 顶部。
var summoned: bool = false

## 召唤物散场的 tick。**负数 = 这个位子现在空着**（或者他不是召唤物）。
var expires_at: int = -1

# ── 出手节奏与子弹（§02）─────────────────────────────────────────

## 每秒出手几次（已算完攻速加成）。
##
## **0 表示「不分次，每 tick 连续输出」**：[method whole_field] 那条退化路径，排队模型假设的就是
## 一条没有边界的连续伤害流，对拍锚点靠这一档活着。离散出手没有溢出伤害（一发打死了目标，多出来的没处去）。
var attack_speed: float = 0.0

## 子弹每 tick 飞多远。**0 表示不发子弹**（近战：接触即伤）。
##
## 挂在攻击者身上而不是查射程档，和 [member move_speed] 用 0 表示「不动」
## 是同一条规矩：一个不发子弹的东西不需要配置开关，那就是它的性质。
var shot_speed: float = 0.0

## 第几 tick 起可以出下一手。和 [member PBSkillCast.ready_at] 同一套写法。
var next_shot_at: int = 0

## **正在起手**：手已经抬起来了，伤害还没落地。
##
## 必须是一个状态，不能只把出手时刻推后：射程内没人时冷却照转、`next_shot_at` 停在过去，
## 敌人一踏进射程当 tick 就开火，第 1 发根本没有起手。所以「冷却转好 + 射程内有人 → 抬手，
## [member windup_ticks] 之后才结算」。渲染层读它决定攻击段什么时候起跑。
var swinging: bool = false

## 起手要几 tick —— 从抬手到伤害落地。[method prime] 按
## [method PBSimConfig.windup_ticks] 填。
##
## **渲染层读它来决定攻击段什么时候起跑**（`next_shot_at - windup_ticks`），
## 所以它必须是 sim 这边的数：各算各的话，画面上的命中帧和真正出手的那一 tick
## 会差几帧，而那正是这一步要修的东西。
var windup_ticks: int = 0

## 玩家在战斗中点名要打的敌人下标。**-1 表示照常自动选目标**（§02）。
##
## **点名是偏好，不是命令**：目标死了、走出射程、还没进射程时自动规则接管，而不是站着不打。
## **也不会自动清掉**（「目标死了就清」会把隔着射程点名的目标在他走进来之前就清掉），
## 每波开波由 [method revive] 重置。
var forced_target: int = -1

## 渲染层用来认人的槽位号，等于它在出战席里的下标。
var slot: int = 0

## **他这一刻的攻击目标**（敌人下标，-1 = 场上没有目标）。**「即将打谁」，不是「刚才打了谁」。**
##
## 每 tick 由 [method PBBattleSim._aim_targets] 算一遍：有效点名 → 射程内最靠近基地的 → 全场最近的。
## 记「刚才打了谁」的话，冷却没转好、射程内暂时没人、点了一个还没走到的目标时它都是空的 ——
## 玩家点名那一下线就断了。
##
## **由 sim 记下来**，渲染层（[PBAimLines]）不照着规则再算一遍 —— 那是第二把尺子。
## 和 [member forced_target] 是两件事：那个是玩家写下的意图，这个是这一 tick 的结论。
var aim_at: int = -1

## 这个单位的大招（0 号技能）。**`null` 表示没有** —— [method whole_field] 造的退化攻击者就没有。
var ultimate: PBSkillCast = null

## 这个角色**自己表里**的技能。**最多两个。**
##
## 和 [member ultimate] 分成两个字段：来源不同（大招由 [PBSimConfig] 现造，这几个来自 `data/skills/`），
## 而且 [member PBSkill.carry_over_ticks] 只对大招成立。统一的下标访问走 [method PBSkillRules.cast_at]
## （0 = 大招，1.. = 这里）—— 两个字段，一把尺子。
var skills: Array[PBSkillCast] = []

## 他身上现在挂着的效果。**永远不为 null**：空 bag 的合计值是精确的中性值，调用方不必判空。
## **[method revive] 会清空它**：效果是波内作用域的，不跨波、不进存档。
var buffs: PBBuffBag = PBBuffBag.new()

## 一发打多少、隔几 tick 一发。由 [method prime] 从 [member dps] 与
## [member attack_speed] 换算，不要手写。
##
## 缓存而不是每 tick 现算：一波几百 tick × 十个攻击者，
## 而它们的输入在一波之内都不变。
var _damage_per_shot: float = 0.0
var _interval_ticks: int = 1


## 造一个覆盖整个战场的单体攻击者 —— **整队标量 DPS 的等价物**。
##
## 留着是为了**对拍**：整队折成这么一个攻击者时，逐 tick 模型必须与 [PBCombatRules] 的解析式排队模型
## 逐字段一致，那是「目标分配的改动有没有改坏原有语义」的唯一参照物。
## [param field_diagonal] 必须是战场**对角**长度（[method PBSimConfig.field_diagonal]）：最远的敌人在角落上。
static func whole_field(team_dps: float, field_diagonal: float) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = maxf(team_dps, 0.0)
	out.pos = Vector2.ZERO
	out.reach = field_diagonal
	out.shape = Shape.SINGLE
	return out


## 复制一份。**用于「把整队按比例缩放，看它在哪一档开始漏怪」那类探测** ——
## 探测要反复改 [member dps]，直接改真正上场的那批攻击者会污染本波的计划。
func clone() -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = dps
	out.attack = attack
	out.pos = pos
	out.reach = reach
	out.shape = shape
	out.max_targets = max_targets
	# 暴击也要跟过来，否则悬崖二分探的是一支不会暴击的队伍，探出来的悬崖系统性偏保守。
	out.crit_chance = crit_chance
	out.crit_bonus = crit_bonus
	# **`revives` 不拷贝，`revives_max` 才拷贝**：复制品是「一个刚站起来的他」，同 `hp` 取 `max_hp`。
	out.crit_on_hit = crit_on_hit
	out.splash_damage = splash_damage
	out.heavy_bonus = heavy_bonus
	out.revives_max = revives_max
	# 闪避、按生命百分比那一笔、反弹、增伤同理，漏掉的话探出来的悬崖偏保守。
	out.dodge = dodge
	out.bite_current = bite_current
	out.bite_lost = bite_lost
	out.reflect = reflect
	out.damage_bonus = damage_bonus
	# 累加器也拷贝：已经折进 `move_speed` 了，拷贝只是让复制品在字段上逐个相同；
	# 折算只发生在 [method PBPassiveRules.equip]，复制品不走建人那条路。
	out.move_speed_bonus = move_speed_bonus
	out.on_hit_buffs = on_hit_buffs
	out.summoned = summoned
	out.expires_at = expires_at
	out.attack_speed = attack_speed
	out.shot_speed = shot_speed
	out.slot = slot
	out.max_hp = max_hp
	out.hp = max_hp
	out.defence = defence
	out.def_element = def_element
	out.home = home
	out.move_speed = move_speed
	out.leash = leash
	out.max_mp = max_mp
	out.mp = max_mp
	out.mp_regen = mp_regen
	if ultimate != null:
		# **技能定义要真复制，不能共享同一份**：探测要能独立改动伤害
		# （见 [method PBValuation._leaks_at]），共享的话那一下改动会
		# 污染真正在战斗的那一份，而它不报错。冷却/落点状态不带 ——
		# 复制品对应「这一波都还没放过的它」。见 [method PBSkill.clone]。
		out.ultimate = PBSkillCast.new(ultimate.skill.clone(), ultimate.caster_level)
	# 角色自己那几个技能同理。**等级要跟过来**：效果数值按它现算，漏掉的话复制品的治疗量恒等于 1 级。
	for cast: PBSkillCast in skills:
		out.skills.append(PBSkillCast.new(cast.skill.clone(), cast.caster_level))
	# **不复制身上挂着的效果**，给一个空的 —— 和 `hp` 取 `max_hp` 同一条：
	# 复制品是「一个刚站起来的他」，不是「他现在这个样子」。
	out.buffs = PBBuffBag.new()
	return out


## 开波：满血站起来。[PBBattleSim] 在构造时对每个攻击者调一次。
##
## §03A 定的是「每波开始时全员满血满蓝复活」—— 一波之内的失误有真实代价，
## 但不会毁掉整局。**必须显式做**，不能靠「攻击者是每波新建的」：
## 悬崖二分那类探测会 [method clone] 出几十份反复跑，
## 不重置的话上一场剩下的残血会漏进下一场，表现为「同一支队伍越探越弱」。
func revive() -> void:
	alive = true
	hp = max_hp
	mp = max_mp
	# 重生次数一波一份，不重填的话上一波用掉的那一次会漏进这一波。
	revives = revives_max
	pos = home if move_speed > 0.0 else pos
	# **按槽位错开第一发**：全队同时开火的话子弹叠成一道。用槽位不掷骰 —— 同种子两次回放必须一样（§13）。
	next_shot_at = posmod(slot, _interval_ticks)
	# 起手是一个状态，开波要清 —— 上一波抬到一半的手不该带进这一波。
	swinging = false
	# 点名是一波一份（见 [member forced_target]）。
	forced_target = -1
	aim_at = -1
	# 效果也是一波一份（见 [member buffs]）。**必须显式清** ——
	# 攻击者对象会跨波、跨探测复用，不清的话上一场剩下的增伤会漏进这一场，
	# 而那和这个函数顶上说的残血漏进下一场是同一个形状。
	buffs.clear()


## 回一 tick 的蓝。上限封顶。
func regen_mana() -> void:
	if max_mp <= 0.0 or not alive:
		return
	mp = minf(mp + mp_regen, max_mp)


## 蓝够不够放这一发。**没有蓝条的单位（[member max_mp] 为 0）永远够** ——
## 尾兽和退化标量走的就是这条，它们不参与蓝这套账。
func can_pay(cost: float) -> bool:
	if max_mp <= 0.0 or cost <= 0.0:
		return true
	return mp >= cost


## 扣蓝。调用前先问 [method can_pay]。
func pay(cost: float) -> void:
	if max_mp <= 0.0:
		return
	mp = maxf(mp - cost, 0.0)


## 敌人挑不挑得中它。见 [member max_hp] —— 没血的东西是个标量，不是单位。
func is_targetable() -> bool:
	return alive and max_hp > 0.0


## 挨一下打。返回这次是否把它**真的**打死了 —— 还有重生次数时返回 false。
##
## **挨打这一路上的每一样东西都在这个函数里面**（减伤、护盾、闪避、重生），调用方一律不判 ——
## 己方挨打有两个落点，各判一次的话漏掉的那一处就是「被子弹打就吃不到减伤 / 用不完护盾 / 复活不了」。
##
## **顺序：先减伤，再护盾，最后扣血** —— 护盾吃的是减完之后那个数。
## [param at_tick] **没有默认值**：同 [method PBEnemy.take_damage]。
func take_damage(
	amount: float, at_tick: int, rng: RandomNumberGenerator = null
) -> bool:
	if not is_targetable():
		return false
	if PBPassiveRules.dodges(self, rng):
		return false
	var hurt: float = amount * buffs.amount(PBBuffRules.DAMAGE_TAKEN, at_tick)
	hurt = buffs.absorb(hurt, at_tick)
	hp -= hurt
	if hp > 0.0:
		return false
	if revives > 0:
		revives -= 1
		hp = max_hp * REVIVE_FRACTION
		return false
	hp = 0.0
	alive = false
	return true


## 这个单位一发大招打多少。没有大招就是 0。
##
## 缩放探测要按「普攻 + 大招」的**总产出**等比例缩，只缩普攻的话，
## 队伍越弱大招占比越高，缩到最后大招一发定生死 —— 那量出来的悬崖
## 是另一支队伍的悬崖。
func ultimate_damage() -> float:
	return 0.0 if ultimate == null else ultimate.skill.damage


## 把 [member attack] 与 [member attack_speed] 换算成「隔几 tick 打多少」。战斗开始前调一次。
##
## 间隔由攻速定、压在 [constant ATTACK_SPEED_CAP] 之内；攻速为 0 时走退化路径（从 [member dps] 算每 tick 的伤害）。
## [param cfg] 只用来问起手几 tick（[method PBSimConfig.windup_ticks]）—— 那个数依赖这里算出的间隔，
## 所以必须在这里问。给 null 就是不起手。
func prime(tick_rate: int, cfg: PBSimConfig = null) -> void:
	var rate: int = maxi(tick_rate, 1)
	if attack_speed <= 0.0:
		# **连续输出那条退化路径**：每 tick 打 `dps / tick_rate`，溢出无损转移。
		# [method whole_field] 造的就是它，而它要与解析式排队模型逐位相同。
		_interval_ticks = 1
		_damage_per_shot = maxf(dps, 0.0) / float(rate)
		windup_ticks = 0
		return
	# 真单位那一档：**一发就是他的攻击力**。攻速加成在 [member attack_speed] 里已经算完了。
	_interval_ticks = maxi(int(round(float(rate) / attack_speed)), fastest_ticks(rate))
	_damage_per_shot = maxf(attack, 0.0)
	if attack <= 0.0:
		# 没填攻击力的老构造点（测试夹具）退回旧口径：由 dps 与**基础**攻速反推。
		# 生产代码不走这条 —— 见 [member attack]。
		var base_ticks: int = maxi(int(round(float(rate) / attack_speed)), 1)
		_damage_per_shot = maxf(dps, 0.0) * float(base_ticks) / float(rate)
	windup_ticks = cfg.windup_ticks(_interval_ticks) if cfg != null else 0


## 一发打多少，**不算身上挂着的效果**。想要真伤害走 [method strike_for]。
func damage_per_shot() -> float:
	return _damage_per_shot


## 这一 tick 他一发真打多少 —— 基数乘上身上的 [constant PBBuffRules.DAMAGE_SCALE] 与常驻增伤。
## 读点在这里而不是出手的三个调用处：漏乘一处就是「某一种攻击方式吃不到增伤」。
func strike_for(at_tick: int) -> float:
	var lasting: float = 1.0 + maxf(damage_bonus, -1.0)
	return _damage_per_shot * lasting * buffs.amount(PBBuffRules.DAMAGE_SCALE, at_tick)


## 回血，上限封顶。**死人回不了** —— 复活是另一件事（[method revive]），
## 而「回血能把倒下的人拉起来」会让 §03A 那条「一波之内的失误有真实代价」
## 变成一句空话。
func heal(amount: float) -> void:
	if not is_targetable() or amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)


## 回蓝，上限封顶。没有蓝条的单位（[member max_mp] 为 0）什么都不发生。
func restore_mana(amount: float) -> void:
	if max_mp <= 0.0 or not alive or amount <= 0.0:
		return
	mp = minf(mp + amount, max_mp)


## 隔几 tick 出一手。1 = 每 tick（连续输出那条退化路径）。
func attack_interval() -> int:
	return _interval_ticks


## 这一 tick 出不出得了手。
func ready_to_fire(tick: int) -> bool:
	return alive and tick >= next_shot_at


## 出了一手，转入下一次的间隔。
## **下一次抬手排在 `interval - windup` 之后**：抬手之后还要等 [member windup_ticks] 才落地，两段正好一个间隔。
func on_fired(tick: int) -> void:
	swinging = false
	next_shot_at = tick + maxi(_interval_ticks - windup_ticks, 1)


## 抬手。返回 true = **这一 tick 只是抬手，别结算**。
##
## 调用方必须先确认射程内真有人（见 [member swinging]）——
## 对着空气抬手的话，抬完那一刻敌人正好走进来，伤害就会在没有起手的情况下落地。
func begin_swing(tick: int) -> bool:
	if windup_ticks <= 0 or swinging:
		return false
	swinging = true
	next_shot_at = tick + windup_ticks
	return true


## 这个点上的敌人打不打得到（欧氏距离）。[param at] 走 [method PBEnemy.pos]。
func can_reach(at: Vector2) -> bool:
	return pos.distance_to(at) <= reach


## 走过去要停在离目标多远。见 [constant STOP_RING]。
func stop_gap() -> float:
	return reach * STOP_RING


## 想够到 [param at] 的话，x 最远能停在哪。
##
## 二维之后「往前压到刚好够得着」不再是 `目标 − 射程`：
## 纵向差掉的那一截要从射程里先扣掉，剩下的才是 x 上的余量。
## 纵向就已经超出射程时返回 [param at] 的 x —— 也就是「只能贴上去」，
## 由皮带绳（[member leash]）去拦。
func reach_stop_x(at: Vector2) -> float:
	# 用 [method stop_gap] 不用 `reach`：压到正好够得着那一点上，
	# 浮点会让 [method can_reach] 判成够不着，见 [constant STOP_RING]。
	var gap: float = stop_gap()
	var budget: float = gap * gap - (at.y - pos.y) * (at.y - pos.y)
	return at.x - (sqrt(budget) if budget > 0.0 else 0.0)


## 上限（[constant ATTACK_SPEED_CAP]）折成最少隔几 tick 出一手。
##
## **取上取整**：向下取整或者四舍五入都可能算出一个「略快于上限」的间隔，
## 而那正是这道墙要挡的东西。
static func fastest_ticks(tick_rate: int) -> int:
	return maxi(ceili(float(maxi(tick_rate, 1)) / ATTACK_SPEED_CAP), 1)
