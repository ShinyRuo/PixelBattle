class_name PBAttacker
extends RefCounted
## 战场上的**一个己方攻击者**。M3-a 起，战斗从「整队一个标量 DPS」换成一组攻击者。
##
## ## 为什么必须把标量拆开
##
## M0 已经证明：**单目标集火在数学上不存在「场上稳定有几个人」的中间态** ——
## 清得比出得快就是空场，慢就是雪崩。三条设计缺口（战场长期没有敌人 /
## 单波只有 12 秒 / BOSS 波比精英波还轻松）是同一个根因的三种表现。
##
## 真塔防看得见一群敌人，是因为多个单位**按各自的射程各打各的**，
## 敌人在整段行军里被慢慢磨。而「谁打谁」需要一个承载体 ——
## 标量 DPS 里既没有位置也没有射程，那件事无处可写。
##
## ## 站位是射程的派生量，不是独立字段
##
## §02 的前中后三列映射到屏幕的右中左，与敌人推进方向一致：
## 射程短的必须站前排才够得着，射程长的站后排照样打得到。
## 两者本来就是同一件事的两种说法，**存两份迟早对不上**。
## 玩家手动排阵型是后续的 UI 步骤，那时站位才成为一个独立决策。
##
## ## 与 [PBUnit] 的分工
##
## [PBUnit] 是玩家手上的那张卡（跨波存在，进存档）；本类是**这一波战斗里
## 那张卡在场上的样子**（一波一份，倍率已经乘死）。战斗结束就扔掉。

## 攻击型。§02 那条乘法关系 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`
## 里的中间那个因子，就是靠这个枚举存在的。
##
## §04 用波型把两者的价值分开（潮水波是 AOE 的高光，精英波是单体的高光），
## 所以这两种不能只是数值差异，必须是**结算方式**的差异。
enum Shape {
	SINGLE,  ## 单体：全部伤害砸在一个目标上，打死了溢出接着打下一个
	AOE,  ## 范围：对射程内最多 [member max_targets] 个目标各打一份，不结算溢出
}

## 走过去的时候停在射程的**九成**上，不是踩着边界停（M6-q）。
##
## ## 为什么不能停在射程本身上
##
## 停在正好 `reach` 处之后，[method can_reach] 量回来的那个距离
## 是浮点算出来的 —— 实测经常是 `0.020000000000000018 > 0.02`，
## 于是**他站在自己的射程边上却判定够不着，一枪不放**。
##
## 表现是「离怪一点点距离原地跑」：够不着 → 每 tick 重走
## [method PBMoveRules.close_in] → 目标被防挤推得一直在动 → 落脚点跟着抖，
## 而净位移是零。实测第 20 波那个近战 **125/271 tick 卡在这个边界上**。
##
## **敌人那一侧 M5-10 就修过同一个 bug**（[constant PBCrowdRules.SIEGE_RING]），
## 当时只改了敌人那半边 —— 又一次「同一件事两把尺子」。
const STOP_RING: float = 0.9

## 每秒伤害。属性克制、攻击科技、羁绊、装备**全部已经乘进来了** ——
## 战斗层不认识那些系统，它只认这个数。
var dps: float = 0.0

## 战场坐标（M4-a 起是二维）。x 与 [member PBEnemy.distance] **同一根轴、
## 同一个单位**：0 是基地，[member PBSimConfig.field_length] 是敌人的出生点；
## y 是泳道，0 到 [member PBSimConfig.field_height]。
##
## M4-a 之前这是一个 float，纵向只存在于渲染层 —— 见 [member PBEnemy.lane]。
var pos: Vector2 = Vector2.ZERO

## 射程，**以 [member pos] 为圆心的一个真圆**（M4-a 起）。
##
## 之前是一段区间 `[position - reach, position + reach]`。对称而不是只朝
## 出生点那侧，是因为敌人会**走过头** —— 一个已经越过前排的敌人仍然在
## 前排的攻击范围里，直到它走出射程。升成圆之后这条性质原样保留。
var reach: float = 0.0

var shape: Shape = Shape.SINGLE

# ── 挨打这一半（§03A，M3.5-b）─────────────────────────────────

## 血量上限。**0 表示「这不是一个真单位，只是一个标量」——敌人看不见它。**
##
## ## 这条约定守着一个对拍锚点
##
## [method whole_field] 造出来的退化攻击者就是 0：它是 M3-a 之前那个
## 整队标量 DPS 的等价物，而那条退化路径要与 [PBCombatRules] 的解析式
## 排队模型**逐字段一致**（「敌人不还手」是那个模型的前提之一）。
##
## 用「血是不是 0」而不是加一个 `cfg.enemies_fight_back` 开关，
## 是因为开关会有人忘了设：一个没血的东西挨不了打，这件事不需要配置，
## 它就是那个对象的性质。
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

## 蓝量上限（§03A，M3.5-d）。智力抬的就是这一项。**0 表示不用蓝**——
## 尾兽的大招攻击者就是 0，它的稀缺性靠跨波冷却而不是蓝。
var max_mp: float = 0.0

var mp: float = 0.0

## 每 tick 回多少蓝。按蓝上限的固定比例算，所以**智力同时抬池子和回速** ——
## 只抬池子的话，高智力只意味着「能存更多发」，攒满的速度一样，
## 那个属性就只在连放时有意义，平时等于没有。
var mp_regen: float = 0.0

# ── 跑动（§02 / §03A，M3.5-c）─────────────────────────────────

## 出生站位。x 由射程档派生（§02），y 是泳道。
## **跑动是围着它做的，不是取代它。**
var home: Vector2 = Vector2.ZERO

## 每 tick 能挪多远。**0 表示这东西不动** —— [method whole_field] 造的
## 退化标量就是 0，所以 M3-a 那条对拍路径不受跑动影响。
var move_speed: float = 0.0

## 最多能离开 [member home] 多远（往敌人那侧）。
##
## ## 为什么必须有这根皮带绳
##
## 「自由跑向敌人」会**推翻 §02 的射程梯度**：所有人都跑到最前面接敌，
## 战斗退回成 M3-a 之前的单点集火，而那条梯度正是「场上稳定有人」的
## 唯一来源（实测场上平均人数 1.7 → 6.0）。
##
## 拴住之后跑动是**围着自己那一列的小幅前压**：射程内没目标就往前挪，
## 有目标就站住开火，清干净了慢慢退回原位。看得见在跑，结构不变。
var leash: float = 0.0

## AOE 一次能命中几个。单体型不读这个字段。
var max_targets: int = 1

# ── 出手节奏与子弹（§02，M4-b）────────────────────────────────

## 每秒出手几次。角色表里那个「攻速」第一次被战斗读到（M4-b）。
##
## ## 0 表示「不分次，每 tick 连续输出」
##
## 那正是 M3-a 之前那个标量 DPS 的语义，也是 [method whole_field]
## 造出来的退化攻击者走的路 —— [PBCombatRules] 的解析式排队模型
## 假设的就是一条没有边界的连续伤害流，**对拍锚点靠这一档活着**。
##
## ## 离散化之后溢出伤害没有了
##
## 连续模型里一 tick 打死几个、剩下的伤害接着打下一个，那是「连续」的直接后果。
## 一发子弹打死了目标，多出来的伤害没有地方去 —— 那是离散唯一的真实损耗，
## 也是「命中才结算」这件事的代价。**这一条会明显拉长单波时长**，归数值回归。
var attack_speed: float = 0.0

## 子弹每 tick 飞多远。**0 表示不发子弹**（近战：接触即伤）。
##
## 挂在攻击者身上而不是查射程档，和 [member move_speed] 用 0 表示「不动」
## 是同一条规矩：一个不发子弹的东西不需要配置开关，那就是它的性质。
var shot_speed: float = 0.0

## 第几 tick 起可以出下一手。和 [member PBSkillCast.ready_at] 同一套写法。
var next_shot_at: int = 0

## 玩家在战斗中点名要打的敌人下标。**-1 表示照常自动选目标**（§02，M4-e）。
##
## ## 为什么点名只是一个偏好，不是一条命令
##
## 点名的那个敌人可能被别人打死、可能走出射程、可能压根还没进射程。
## 这三种情况下**自动规则接管**，不是站着不打 —— 「我点了他，
## 结果这个忍者整场发呆」是玩家最不能接受的一种听话。
##
## 点名也**不会自动清掉**：目标死了下一波换新敌人，下标还在。
## 所以每波开波要重置（[method revive]），而不是靠「目标死了就清」——
## 那样一个隔着射程点名的目标会在他走进来之前就被清掉，
## 而玩家看到的是「点了没用」。
var forced_target: int = -1

## 渲染层用来认人的槽位号，等于它在出战席里的下标。
var slot: int = 0

## **他这一刻的攻击目标**（敌人下标，-1 = 场上没有目标）。M5-11 加，M5-12 改语义。
##
## ## 「即将打谁」，不是「刚才打了谁」
##
## M5-11 记的是上一发打中的那个，于是三种很常见的情形下它是空的：
## 冷却没转好、射程内暂时没人、**玩家点了一个还没走到的目标**。
## 而玩家点名的那一下，意思恰恰是「去打他」——
## 线在那一刻断掉，等于告诉他这条命令没生效。
##
## 所以它现在每 tick 由 [method PBBattleSim._aim_targets] 算一遍，
## 三档取第一个有的：**有效点名 → 射程内最靠近基地的 → 全场最近的**。
## 后两档就是自动规则本身；第一档**不问射程** —— 够不着就走过去，
## 那正是 [method PBBattleSim._nearest_enemy] 一直在做的事。
##
## ## 为什么必须由 sim 记下来
##
## 渲染层要画那根线（[PBAimLines]），只有两条路：**照着同一套规则再算一遍**，
## 或者把 sim 算出来的那一个记下来。再算一遍就是第二把尺子 ——
## 点名、射程、出场时刻、死活四个条件里漏抄一个，线就指着一个他其实
## 没在打的敌人，**而且不报错**。这个项目为这种形状的 bug 付过四次代价。
##
## 和 [member forced_target] 仍是两件事：那一个是玩家写下的意图，一波之内不变；
## 这一个是**这一 tick 的结论**，点名的那个死了它立刻改口。
var aim_at: int = -1

## 这个单位的大招（§02，M3-b；M7-b 起是「0 号技能」的 [PBSkillCast]）。
## **`null` 表示没有** —— [method whole_field] 造出来的那个退化攻击者就没有，
## 所以 M3-a 那条对拍不受技能系统影响。
var ultimate: PBSkillCast = null

## 这个角色**自己表里**的技能（M7-e）。**最多两个**（决策 6）。
##
## ## 为什么和 [member ultimate] 分成两个字段
##
## 它们的来源不同：大招由 [method PBCombatRules._build_skill] 按
## [PBSimConfig] 现造（全场共用一套数值），而这几个来自
## `PBCharacter.skill_ids` → `data/skills/*.tres`（逐角色）。
## 合成一个数组的话「第 0 个是不是大招」就成了一条要靠约定维持的规矩，
## 而 [member PBSkill.carry_over_ticks]（尾兽的跨波冷却）恰恰只对大招成立。
##
## 统一的下标访问走 [method PBSkillRules.cast_at]（0 = 大招，1.. = 这里），
## 指令卡与 [PBBattleSim] 的入口都只认那个下标 —— **两个字段，一把尺子。**
##
## **v1 是空的**：没有任何角色配了 `skill_ids`，所以全部既有配平数字一个不动，
## 和 M3.5-f 装备那条「空着 = 一字不差」同形。
var skills: Array[PBSkillCast] = []

## 他身上现在挂着的效果（§03A，M7-a）。**永远不为 null** ——
## 空 bag 的合计值是不折不扣的中性值（率型 1.0、量型 0.0），
## 所以「没有 buff」和「有一个什么都不改的 buff」在数值上不可区分，
## 调用方因此不需要到处判空。
##
## **[method revive] 会清空它**：效果是**波内作用域**的，不跨波、不进 §12 的存档。
## 跨波的东西已经有自己的字段（[member PBSkill.carry_over_ticks]），
## 把 buff 也做成跨波的会让「这一波我身上有什么」变成一个存档问题。
var buffs: PBBuffBag = PBBuffBag.new()

## 一发打多少、隔几 tick 一发。由 [method prime] 从 [member dps] 与
## [member attack_speed] 换算，不要手写。
##
## 缓存而不是每 tick 现算：一波几百 tick × 十个攻击者，
## 而它们的输入在一波之内都不变。
var _damage_per_shot: float = 0.0
var _interval_ticks: int = 1


## 造一个覆盖整个战场的单体攻击者 —— **M3-a 之前那个标量 DPS 的等价物**。
##
## 保留它不是为了兼容旧调用点，是为了留住**对拍能力**：
## 整队折成这么一个攻击者时，逐 tick 模型必须与 [PBCombatRules] 的
## 解析式排队模型逐字段一致。那条断言是「射程改造有没有改坏原有语义」的
## 唯一判据 —— 拆掉它，以后任何一次目标分配的改动都没有参照物了。
## [param field_diagonal] 必须是战场的**对角**长度
## （[method PBSimConfig.field_diagonal]），不是 `field_length`。
## 升成二维之后最远的敌人在**角落**上，用长度的话它够不着，
## 而现象是「解析式排队模型的对拍突然差了几个 tick」。
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
	out.pos = pos
	out.reach = reach
	out.shape = shape
	out.max_targets = max_targets
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
	# 角色自己那几个走同一条规矩（M7-e）。**等级要跟过来** ——
	# 效果数值是按它现算的（决策 7），漏掉的话复制品的治疗量恒等于 1 级。
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
	pos = home if move_speed > 0.0 else pos
	# **按槽位错开第一发**（M4-b）。全队同时开火的话，十个人的子弹
	# 每隔一个间隔叠成一道，画面上像一发；错开之后才看得出是一队人在射击。
	# 用槽位而不是掷骰 —— 同一个种子的两次回放必须长得一样（§13）。
	next_shot_at = posmod(slot, _interval_ticks)
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


## 挨一下打。返回这次是否把它打死了。
func take_damage(amount: float) -> bool:
	if not is_targetable():
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false


## 这个单位一发大招打多少。没有大招就是 0。
##
## 缩放探测要按「普攻 + 大招」的**总产出**等比例缩，只缩普攻的话，
## 队伍越弱大招占比越高，缩到最后大招一发定生死 —— 那量出来的悬崖
## 是另一支队伍的悬崖。
func ultimate_damage() -> float:
	return 0.0 if ultimate == null else ultimate.skill.damage


## 把 [member dps] 与 [member attack_speed] 换算成「隔几 tick 打多少」。
## 战斗开始前调一次。
##
## **一发的伤害由间隔反推，不是 `dps ÷ 攻速`。** 间隔取整之后两者会差一点点，
## 而按间隔算的那份能保证**平均 DPS 分毫不差** —— 那是离散化敢做的前提：
## 它改的是节奏，不是总量。
func prime(tick_rate: int) -> void:
	var rate: int = maxi(tick_rate, 1)
	# 攻速为 0 = 连续输出那条退化路径，间隔就是 1 tick（见 [member attack_speed]）。
	_interval_ticks = 1
	if attack_speed > 0.0:
		_interval_ticks = maxi(int(round(float(rate) / attack_speed)), 1)
	_damage_per_shot = maxf(dps, 0.0) * float(_interval_ticks) / float(rate)


## 一发打多少，**不算身上挂着的效果**。想要真伤害走 [method strike_for]。
func damage_per_shot() -> float:
	return _damage_per_shot


## 这一 tick 他一发真打多少 —— 基数乘上身上的
## [constant PBBuffRules.DAMAGE_SCALE]（M7-a）。
##
## ## 为什么读点在这里，不在 [PBBattleSim] 的三个调用处
##
## 出手在那边有三条路（单体、连续输出、范围），**漏乘一处的表现是
## 「某一种攻击方式吃不到增伤」** —— 而那要盯着数字看很久才发现。
## 放进类里就只有一个读点，和 §2.4 里 `hurt` 必须写进
## [method PBEnemy.take_damage] 是同一条理由。
##
## M7-a 之前这件事是 [PBBattleSim] 上的一对 `_buff_scale` / `_buff_until`：
## 一份、全场、后来者覆盖前者。搬进 bag 之后**每个人身上各一份**，
## 而全场增伤只是「给每个人都挂一份」的那种特例。
func strike_for(at_tick: int) -> float:
	return _damage_per_shot * buffs.amount(PBBuffRules.DAMAGE_SCALE, at_tick)


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
func on_fired(tick: int) -> void:
	next_shot_at = tick + _interval_ticks


## 这个点上的敌人打不打得到。[param at] 走 [method PBEnemy.pos]。
##
## M4-a 起是**欧氏距离**，不再是「x 差多少」——「射程圈」这四个字
## 从此说的是真的。副作用是每个人的有效射程都略微缩水
## （斜着量总比横着量长），归数值回归。
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
