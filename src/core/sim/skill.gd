class_name PBSkill
extends Resource
## 一个技能的**定义**：伤害、半径、冷却、耗蓝、位置操纵……不含这一波的状态。M7-b。
##
## ## 为什么要把「定义」从「大招」里拆出来
##
## M3-b 造出来的 `PBUltimate` 把「设定」和「这一波的冷却/落点状态」揉在一个类里 ——
## 它的 `clone()` 因此必须记得「只带设定不带状态」，`reset()` 必须记得清哪几个字段，
## 漏一个的表现都是「上一波剩下的东西漏进下一波」，不报任何错
## （实测：不清冷却时九只尾兽整局各放 28–33 发，该是 7 发左右）。
##
## 拆开之后这两样税自动消失：本类只有设定，**永远不会有状态可漏**；
## 这一波的冷却/落点状态搬进了 [PBSkillCast]。
##
## ## 大招是**每个角色的 0 号技能**
##
## [method PBCombatRules._build_skill] 仍然按 [PBSimConfig] 生成它，一个数不动 ——
## 具体数值是要扫的参数，写进 30 个 `.tres` 等于把可调参数散进数据文件
## （[member PBCharacter.reach] 顶上已经讲过这件事）。玩家自己的技能
## （`data/skills/*.tres`）走的是同一个类，只是来路不同：
## 一份来自代码生成，一份来自资源加载。
##
## ## 为什么是 Resource
##
## 和 [PBCharacter] 一样：以后要存成 `data/skills/*.tres` —— 检查器里可视化编辑、
## git diff 可读。`extends Resource` 不违反「core 零引擎依赖」——它不是 Node、
## 不碰场景树、不读 delta；被 core 纯度检查挡住的是 `ResourceLoader`，
## 「加载 `.tres`」这件事发生在 `src/data/`。
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
## 所以落点在**下达时**定死（[method PBSkillCast.cast]），伤害在
## [member delay_ticks] 之后才落地（[method PBSkillCast.land]）。
## 这中间的窗口就是敌人走动的距离，也就是预判能赚到的那部分 ——
## 顺带它正是渲染层要画的**落点预示圈**。
##
## ## 与 [PBAttacker] 的分工
##
## [PBAttacker] 管普攻（每 tick 恒定输出、按射程分配目标）；
## 本类管技能（长冷却、一次性、有落点）。两者的目标选择规则完全不同，
## 合在一起写会让「按射程选最靠近基地的」和「按密度选一个落点」
## 这两套逻辑互相纠缠。

## 玩家要**点什么**（M7-c）。和 [enum Party] 是两根独立的轴，见 [member target]。
enum Target {
	NONE,  ## 什么都不用点，按下去就放（自增益、全场打击）
	ALLY,  ## 等他点一个**己方单位**（医疗忍术）
	ENEMY,  ## 等他点一个**敌人**（单体爆发、单体控）。**M7-c 还没接进 sim**
	GROUND,  ## 等他点一块**地**，走落点 + 施法延迟那一套（现在的大招）
}

## 结算**落在哪一边**（M7-c）。
enum Party {
	ALLIES,
	ENEMIES,
}

## 玩家要点什么。**默认 [constant Target.GROUND]** —— M7-b 之前的每一发大招
## 都是「点一块地」，默认取它，既有的技能一个字不用改就还是原来的行为。
##
## ## 为什么「点什么」和「落在谁」是两根轴，不是一个枚举
##
## 合成一个的话「地面范围治疗」表达不出来，而那是治疗系角色第二个技能的
## 自然形态。六种组合各有名字：
##
## [codeblock]
## NONE   + ALLIES   自增益，点一下就放
## NONE   + ENEMIES  全场打击
## ALLY   + ALLIES   医疗忍术
## ENEMY  + ENEMIES  单体爆发、单体控
## GROUND + ENEMIES  现在的大招
## GROUND + ALLIES   团队治疗圈
## [/codeblock]
##
## **没有 `SELF` 这一档**：自增益就是 `NONE` + [member on_self]。
## 两种写法表达同一件事就是两把尺子。
@export var target: Target = Target.GROUND

## 这份技能是谁（M7-e）。`data/skills/<id>.tres` 的文件名就是它。
##
## **大招不填这一项**：它由 [method PBCombatRules._build_skill] 按
## [PBSimConfig] 现造，全场共用一套数值，不是 `data/` 里的一条 —— 理由
## 同 [method PBBuffRules.team_damage] 顶上那段（全场共用的走配置，
## 逐角色独有的走 `data/`）。
@export var id: StringName = &""

## 显示名的翻译键（铁律 5：`src/` 里一个技能名都不出现）。
##
## 指令卡那一格写的就是它查出来的字（[method PBLocale.of_skill]）。
## 空着时那一格会退回 [member id] —— 少一条翻译不该让按钮变成空白，
## 那样玩家会以为是格子坏了。
@export var name_key: String = ""

## 结算落在哪一边。**默认 [constant Party.ENEMIES]**，理由同 [member target]。
##
## 两条约束由 [method PBSkillRules.validate] 拦着：
## `ALLY` 必然 `ALLIES`、`ENEMY` 必然 `ENEMIES` ——
## 点谁和打谁在这两档上不可能是两个方向。
@export var affects: Party = Party.ENEMIES

## 命中时挂给**目标**的效果（M7-c）。
##
## `ALLY` 档挂给锁定的那一个；`GROUND` / `NONE`+`ENEMIES` 要挂给敌人，
## 而 [PBEnemy] 的效果袋是 M7-d 的事 —— **在那之前这两档只走
## [member damage]，不挂 buff**。
##
## 存**直接引用**而不是 id 字符串：`.tres` 里 `ext_resource` 指向
## `data/buffs/*.tres` 就是 Godot 原生的外键，再套一层 id 查表
## 等于自己发明一遍资源系统。
@export var on_hit: Array[PBBuff] = []

## **下达那一刻**挂给施法者自己的效果（M7-c）。不问 [member target] 是什么。
##
## 在下达时挂而不是落地时：`GROUND` 档那段施法延迟里人已经把技能交出去了，
## 自增益却要等半秒才生效的话，玩家看到的是「按下去没反应」。
## 非 `GROUND` 档的延迟恒为 0（[method PBSkillRules.validate] 拦着），
## 两者因此没有分叉。
@export var on_self: Array[PBBuff] = []

## 伤害属性。**§03 铁律：element 挂在伤害事件上，不挂在单位上。**
##
## 大招是这条铁律第一次真正用上的地方 —— 在此之前一个角色只有一个输出来源，
## 单位属性和伤害属性恰好重合，铁律看起来像句空话。
## 现在「本体土属性但大招是火系」这种角色做得出来了。
@export var element: PBElement.Type = PBElement.Type.PHYSICAL

## 一发打多少。属性克制、科技、羁绊、装备**全部已经乘进来了**，
## 和 [member PBAttacker.dps] 一样，战斗层只认这个数。
@export var damage: float = 0.0

## 杀伤半径。**以落点为圆心的一个真圆**（M4-a）。
##
## 在那之前战场是一维的，它只作用在推进轴上 —— 渲染层因此把落点
## **画成一条竖带而不是圈**，理由写在 [PBTelegraphPool] 顶部：
## 画成圆会让玩家去躲一个根本不存在的纵向判定。
##
## 纵向开始算数之后那条理由反过来了：现在圆才是真相，带子才是谎话。
## **一发大招因此比以前弱**（圆的面积小于横贯全场的带子），归数值回归。
@export var radius: float = 0.0

## 冷却多少 tick。§02 给的是 15–30 秒。
@export var cooldown_ticks: int = 0

## 下达到落地之间隔多少 tick。见本类顶部「为什么大招必须有施法延迟」。
##
## **`target != GROUND` 的技能这里必须是 0**（§3.3，M7-c 起数据校验拦着）：
## 锁定单体的技能没有预判可言 —— 目标跟着走，落点也跟着走。
@export var delay_ticks: int = 0

## 一发最多命中几个。**0 表示不限**（半径内全中）。
##
## M3-d 加的，为了让「超大单体爆发」这种大招表达得出来 ——
## 单体和范围的区别在 §04 里是**波型价值分化**的支点（潮水波偏 AOE、
## 精英波偏单体），只有伤害数字的话那条分化不成立。
@export var max_targets: int = 0

## 落地时是否把范围内的敌人拖到落点（§02 的「拉拽」）。
##
## §02 要求约 4–6 名角色带这个，且**必须分散在多个不同羁绊里** ——
## 否则抽不到聚拢手段的局直接废了，这在无限流里是致命的。
## **M3-b 全表都是 false**，一个都没分配：谁该带拉拽要么由技能表决定，
## 要么得有扫描依据，现在拍几个角色会污染正在量的那两条验收。
##
## M3-d 起七尾的大招也走这个字段 —— §11 要的「不依赖特定羁绊的聚怪路径」
## 因此和角色的拉拽是同一套机制，不是平行的第二份实现。
@export var gather: bool = false

# ── 位置与状态操纵（M3-d）──────────────────────────────────────
#
# 下面这五个字段是 §11 的机制型尾兽（七尾聚拢、六尾重置 CD、一尾减速、
# 三尾击退、二尾增伤）在战斗层的全部落点，**同时也是 §09 功能档
# （聚拢 / 吸附 / 定身 / 减速）要的那套词汇**。
#
# 写在 [PBSkill] 而不是单开一个「尾兽大招」类，是因为两者的结算规则
# 逐条相同（有冷却、有落点、有施法延迟、按半径圈人）。分成两份的话，
# §09 的功能档落地时会再抄第三份，而三份的落点判定迟早对不上。

## 落地时把范围内的敌人往出生点方向推多远。与 [member PBEnemy.distance] 同轴。
##
## 和 [member gather] 是相反方向的两种位置操纵。两者都不产生伤害，
## 价值全在「敌人晚到基地多久」上 —— 那正是塔防里位置操纵的定价方式。
@export var knockback: float = 0.0

## 落地后敌人的速度倍率（0 = 定身，0.5 = 减速一半，1.0 = 不减速）。
##
## **减速是全场的，不按半径圈人。** 一尾的「全屏减速力场」和五尾的
## 「地形阻挡」在 §11 里都写着「全屏 / 延缓推进」，圈人反而不合规格；
## 而 §09 的功能档要按半径减速时，加一个「减速也吃半径」的开关即可，
## 那时才有依据决定它该不该吃。
@export var slow_scale: float = 1.0

## 减速持续多少 tick。
@export var slow_ticks: int = 0

## 落地后全队普攻伤害的倍率（1.15 = 短时全队 +15%）。M7-a 起走
## [PBBuffBag]（[method PBBuffRules.team_damage]），不再是场的一份标量。
@export var team_damage_scale: float = 1.0

## 全队增伤持续多少 tick。
@export var buff_ticks: int = 0

## 落地时把**其他**技能的冷却清零（六尾）。
##
## 清的是别人不是自己 —— 自己也清的话它会在同一 tick 无限自我重置。
## 这一条的强度与队伍里大招的总量成正比，而不是和它自己的数值成正比，
## §11 说的「机制型尾兽」指的就是这种依赖关系。
@export var reset_cooldowns: bool = false

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
@export var mp_cost: float = 0.0

## 开波时**还欠多少 tick 的冷却**。[method PBSkillCast.reset] 把
## [member PBSkillCast.ready_at] 设成它。
##
## ## 为什么需要跨波的冷却，而角色大招不需要
##
## 冷却本来是每波清零的，因为角色大招 20 秒、单波约 16 秒 ——
## 「大部分波次每人放得出一发」正是 §02 想要的决策密度，清不清零结果一样。
##
## **尾兽不是这样。** §11 给的是 75 秒 ≈ 每 2 波一次，原话是
## 「这个节奏让玩家必须选择在哪一波交底牌 —— BOSS 波前存着，
## 还是这波就要顶不住了」。每波清零的话它**每波都放得出**，
## 那个决策在模型里根本不存在 —— 而它是 §11 整节的核心。
##
## 实测过代价：清零时九只尾兽整局各放 28–33 发（等于波数），
## 而按 75 秒算只该有 7 发左右。差了四五倍，排序因此完全不可信。
@export var carry_over_ticks: int = 0


## 复制一份**设定**。[PBSkillCast] 不会跟着复制 ——
## 复制品对应「这一波都还没放过的它」，不是「它现在这个样子」。
##
## ## 为什么需要复制而不是共享同一份
##
## [method PBAttacker.clone] 造探测用的攻击者时要能**独立改动**伤害
## （见 [method PBValuation._leaks_at]），共享同一份 [PBSkill] 的话，
## 探测那一下改动会污染正在真正战斗的那一份 —— 而它不报错，
## 只表现为「悬崖二分跑着跑着，真实队伍的大招变了」。
func clone() -> PBSkill:
	var out := PBSkill.new()
	out.id = id
	out.name_key = name_key
	out.target = target
	out.affects = affects
	# 两张效果表**共享同一份引用**，不逐个复制：[PBBuff] 是不可变的定义
	# （谁都不改它的字段），而 [member damage] 那种会被探测就地改写的标量
	# 才需要真复制。
	out.on_hit = on_hit
	out.on_self = on_self
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
