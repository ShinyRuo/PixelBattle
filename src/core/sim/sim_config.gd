class_name PBSimConfig
extends RefCounted
## 模拟的全部可调参数。默认值取自施工策划案 §03 / §04。
##
## 不做成 Resource：配置的用法是**批量扫描**（一次几千局，每局一份改了参数的副本），
## 纯 RefCounted 加 [method clone] 比 Resource 的加载/复制轻得多。
## 不进扫描的规则常数放在各自的规则类上当 const（[PBCritRules]、[PBTechRules] 等）。

# ── §03 属性伤害系数 ────────────────────────────────────────────
## 克制倍率。环距 1。
var mult_counter: float = 2.00

## 被克倍率。**环距 4「它克我」与环距 0「同系」共用这一档** ——
## 原版矩阵里那两格是同一个数，理由见 [enum PBElement.Relation]。
var mult_weak: float = 0.50

## 无关属性倍率。环距 3，隔两个。§03 标为固定值，列出来只为公式完整。
var mult_neutral: float = 1.00

## 环距 2「隔一个」的倍率（原版五档矩阵的第五档）。
var mult_distant: float = 0.75

## 物理倍率。**全局最敏感的一个旋钮。**
##
## §03 警告：调到 1.15 以上，堆物理躺赢就成了最优解，属性系统当场作废。改它必须跑回归。
## 取原版的 1.00：物理买的是**永远不会选错**（对每一系都恰好 1.00），而同系是 0.50 ——
## 这两个数要一起看，只改一半的话物理要么白白变弱，要么在同系惩罚下强得离谱。
var mult_physical: float = 1.00

## 仙打仙的倍率。原版 `DamageBonusChaos` 对英雄护甲那一格是 1.50。
##
## **它在今天的名册里一次都不会发生** —— 攻仙的两个（佩恩、兜）都是防物理，
## 防仙的那个（重吾）是攻物理，怪物没有仙系。照原版填而不是随便填，
## 是因为「一个永远走不到的分支填错了」没有任何地方会报错：
## 哪天加进一个攻防都是仙的单位（原版的 USR 神卡就是），
## 错的那个数会当场生效，而排查会从别处开始。
var mult_sage_mirror: float = 1.50

# ── §04 成长曲线 ────────────────────────────────────────────────
## 1 波普通怪血量。
var hp_base: float = 120.0

## 1 波普通怪攻击。
var atk_base: float = 10.0

## **整条难度曲线的主控。** §04 给的范围是 1.10–1.15。
##
## 1.10 是**暂定锚点**，落在 §01 熟练档 40–60 波带的底部 —— 刻意选底部，
## 后续内容（羁绊功能档、真武、尾兽、顶档机制）会把所有玩家一起往上推。
## 它控制曲线的**位置**；三档之间的离散度取决于核心玩家拿到多少倍战力。
## 判据：核心档比熟练档相差 40–60 波，在 1.10 上等于 45–300 倍战力，对不上就调这里。
var growth: float = 1.10

## 1 波怪物数。
var count_base: float = 8.0

## 每波数量增量。波型倍率在此之后叠加。
var count_rate: float = 0.5

## 同屏单位上限。**待决策**，§04 建议 48。
## 绝不按平台分档（铁律 6）—— 双端跑同一份模拟，否则难度不同、排行榜没意义。
var count_cap: int = 48

## 波次基础奖金与每波增量。线性，见 [member PBWave.reward_gold]。
var gold_base: int = 45
var gold_rate: int = 6

# ── §04 波型 ────────────────────────────────────────────────────
## 三种非 BOSS 波型的刷新权重。不必凑成 100，按总和归一。
var shape_weight_normal: int = 60
var shape_weight_swarm: int = 25
var shape_weight_elite: int = 15

## 波型对数量 / 单体血量的倍率。
var swarm_count_mult: float = 2.2
var swarm_hp_mult: float = 0.45
var elite_count_mult: float = 0.3
var elite_hp_mult: float = 4.0
var boss_hp_mult: float = 8.0
var mega_boss_hp_mult: float = 20.0

## BOSS 数量。§04 给的是 1–3 的区间，这里取定值而不是掷骰 ——
## BOSS 波是存档点也是验收项（「刚好达标的阵容能击败，误差 ±15%」），
## 掷骰会把这条验收标准本身变成随机的，没法回归。
var boss_count: int = 2
var mega_boss_count: int = 1

# ── 战场时空 ────────────────────────────────────────────────────
## 逻辑帧率。铁律 2：定帧 20 tick/s，倍速只改每渲染帧步进的 tick 数。
var tick_rate: int = 20

## 敌人从出生点走到基地要多久（秒）。它决定「反应窗口」有多宽。
var march_seconds: float = 12.0

## 战场长度，归一化值。敌人从 `field_length` 走到 0（基地）。
##
## 取 1.0 是刻意的：**sim 层不知道屏幕有多宽。** 渲染层拿
## [method PBEnemy.progress] 得到 0–1 的进度，自己乘上像素宽度。
## 这样 `640×360` 换成别的分辨率、或者以后改横向布局，sim 一行不用动。
var field_length: float = 1.0

## 战场**纵深**，和 [member field_length] 同一个单位。
##
## 它 = 屏幕上战场那条道的高宽比：两轴共用同一个「像素 / 单位」比例（[method PBLayout.px_per_unit]），
## 所以 sim 里的圆在屏幕上是圆（再经 Y_SCALE 压成椭圆）。**它和 [PBLayout] 里那几个战场常量是一组**，
## 改一边不改另一边的表现是「打得到的敌人画在道外面」。`34 + 0.44 × 500 = 254`。
##
## 纵深决定纵向站位要不要紧（近战射程覆盖纵深的比例），也决定大招圈占战场面积的比例 ——
## 两个都是数值回归的头号旋钮。
##
## **设成 0 就退回一维**（所有 lane 都是 0，欧氏距离等于 |Δx|），升维的对拍锚点见 `test_field_2d.gd`。
var field_height: float = 0.44

## 一波敌人分散出场的总时长（秒）。出怪间隔 = 本值 / 数量。
##
## **默认 0：整波在 [member spawn_rows] 行的阵型里同时出生**。调大能拉长单波时长，但变长的全是空场。
## 留着这个参数是因为解析式排队模型（[PBCombatRules]）还在读它，那是对拍参照物。
var spawn_window: float = 0.0

## 整波敌人排成几行出生。同时出生在同一点的话画出来是一个单位；
## 8 行 6 列是一个看得出规模的方阵（道高 140 像素，八行间隔 17 像素，敌人直径 10）。
var spawn_rows: int = 8

## 阵型里前后两列隔多远，与 [member field_length] 同轴。
## 后面几列**出生在战场之外**，走进来才看得见 —— 行军距离就是 §01 的「反应窗口」。
var spawn_column_gap: float = 0.03

# ── §02 阵型与射程 ──────────────────────────────────────────────
## 前中后三列距基地多远，与 [member PBEnemy.distance] 同一根轴。
## 数值越大越靠出生点、越先接敌；三列都挤在基地旁边，敌人要走完大半个战场才进入交战区。
var column_front: float = 0.30
var column_mid: float = 0.20
var column_back: float = 0.10

## 玩家最远能把忍者摆到哪（§02 的开战位置）。与 [member field_length] 同轴。
##
## 没有这条界限的话最优解永远是「全队顶到出生点」，行军距离等于 0，三档射程也就没有区别。
## 取屏幕中线：玩家一眼看得出规则，准备阶段战场上那条竖线（`Limit`）就是它。只作用于摆位，不管战斗中的跑动。
var deploy_limit_x: float = 0.5

## 原版多少码算我们的 1 个战场长度（[member field_length]）。**射程和技能范围共用这一把尺子**：
## 原版射程 600 = 0.30，技能范围 600 也是 0.30，两者之间的比例和原版一样（玩家定的：射程按原版比例套）。
##
## 这个数不是量原版战场量出来的（地图文件不在手边），是技能表一直在用的换算（`data/skills.tsv` 的「范围」列逐条对过）。
## 改它等于同时改所有忍者的射程，而技能表的「范围」是写死的战场坐标、不跟着变 —— 两边会脱节。
var war3_units_per_field: float = 2000.0

## 三档射程的**默认**距离，只给没配 [member PBCharacter.attack_range] 的角色用（代码现造的测试角色、合成名册）。
## 真名册每个人都有自己的原版射程（[method reach_of]）。取的是原版三档的代表值：近战 125、远程 600、超远程 800 码。
##
## 下限是防挤间距 [member unit_min_gap]（0.012）：射程比它还短的话近战会「走进射程 → 被推开 → 又够不着」来回抖。
var reach_melee: float = 0.0625
var reach_ranged: float = 0.30
var reach_long: float = 0.40

# ── §02 大招与落点 ──────────────────────────────────────────────
## 大招冷却（秒）。§02 给的是 15–30。取 20：单波约 16 秒，大部分波次每人只放得出一发，
## 落点选得准不准因此很要紧。
var ultimate_cooldown_seconds: float = 20.0

## 下达到落地之间隔多久（秒）。**这个数就是预判的赚头有多大。**
##
## 取 0 的话自动和手动必然同分，§02 的分层验收量出来恒等于 100%，
## 看着达标其实什么都没测（理由见 [PBSkill] 顶部）。
## 0.5 秒是 §02 原话「PC 玩家提前半秒把落点压在敌人行进路线前方」。
##
## 它同时是渲染层**落点预示圈**亮着的时长。
var ultimate_delay_seconds: float = 0.5

## 大招杀伤半径，与 [member field_length] 同一根轴。
var ultimate_radius: float = 0.12

## 一发大招 = 角色基础战力的多少倍。
##
## 占位值。校它的判据不是「大招够不够爽」，而是 §02 那对上下夹：
## 太弱则落点选得准不准无所谓（手动提升掉到 15% 以下），
## 太强则一发定生死（自动跟不上手动的 78%）。
var ultimate_power_mult: float = 6.0

## 落点上至少要罩住几个敌人才值得放。低于这个数就攒着。
## 这是**自动档**（手机端）的门槛 —— 它只求不浪费，不求最优。
var ultimate_min_targets: int = 2

## **手动档**（PC 端）等到罩得住几个才放。
## 会玩的玩家攒着等一堆值得的目标 —— **这个数与 [member ultimate_min_targets] 的差就是「什么时候放」
## 这一维的技巧空间**，也是技巧真正所在（「往哪儿放」那一维几乎不值钱，见 [method PBAimRules.pick_spot]）。
var ultimate_hold_targets: int = 5

## 手动档最多攒多久（秒）。等不到就放。
##
## 没有这个死线的话，稀疏的波次里大招会被一直捏到战斗结束 ——
## 一发没放比手机端还差，而那会让验收得出「手动是负收益」的假结论。
var ultimate_max_hold_seconds: float = 5.0

## 落点策略（§02 的双端差异）。**游戏默认走自动**，
## 因为 §02 要求「自动模式必须能通关到合理波次，不能让手机端变成残废版」。
## PC 手动是玩家主动接管，不是默认态。
var aim_policy: PBAimRules.Policy = PBAimRules.Policy.AUTO

## 多大比例的出战单位带**聚拢**大招（§02 的拉拽）。
##
## 做成比例而不是写进角色表，是因为**现在没有依据决定谁该带**。
## §02 只说了「约 4–6 名、且必须分散在多个不同羁绊里」。
## 这个开关让「聚拢值多少」先量出来，量完再回头分配 —— 顺序反了
## 就是拿一份拍脑袋的分配去校准一个还不知道值多少的机制。
var ultimate_gather_share: float = 0.0

## 一次范围攻击最多命中几个（[constant PBAttacker.Shape.AOE]）。管的是**自动普攻**那一份。
var aoe_max_targets: int = 4

# 羁绊功能档的量在 [PBBondFunctionRules] 上（不进扫描）。搬回来的那天**别搬成嵌套对象**。

# ── 基地 ────────────────────────────────────────────────────────
## 基地初始血量。漏怪按敌人 ATK 扣，而 ATK 走指数曲线 —— 前期能扛几十个漏怪，后期漏两个就没了。
var base_hp: float = 1000.0

## BOSS 漏掉的额外倍率。
var boss_leak_mult: float = 3.0

# ── §05 人口 ────────────────────────────────────────────────────
## 出战席初始几个位置，人口科技每级 +1，上限 [member deploy_slots_max]。
var deploy_slots_base: int = 4
var deploy_slots_max: int = 10

# ── 合成表的战力阶梯 ────────────────────────────────────────────
## 各稀有度的基础每秒伤害。R / SR / SSR，**每档 ×1.30**。
##
## **只描述合成表**（[method PBCharacterTable.synthetic] / [method PBStatRules.fill_placeholder]），
## 不描述真名册 —— 真名册用原版三围。
##
## 斜率必须**显著低于**克制倍率（×2.0），否则「升一档稀有度」和「换上克制系」变成同一种货币，
## 属性策略被稀有度吃掉。稀有度剩下的价值走技能数，不走数值。
var rarity_power: Array[float] = [100.0, 130.0, 169.0]

## 每星级的战力加成。§08：同卡 3 张升 1 星。
##
## §03A 起它乘在**基础属性**（血与攻）上，不乘二级属性 ——
## 星级是「整体变强」，等级才是「顺着定位长」，两条轴分开。
var star_power_mult: float = 0.25

## 防御的换算系数（§03A）。`减伤 = 防×k / (1 + 防×k)`。
##
## 取 0.02：50 点防减伤 50%，100 点减伤 67%，200 点减伤 80% —— 永远到不了 100%。
## **递减是必须的，不是为了好看**：§04 的敌人 ATK 按 `GROWTH^n` 指数涨，
## 而玩家的防御是加法涨的。线性减免下这两条曲线必然在某一波交叉，
## 交叉前无敌、交叉后裸奔，中间没有过渡。
var armor_scale: float = 0.02

# ── 敌人还手（§03A）─────────────────────────────────────────────

## 敌人每秒攻击几次。`atk × 本值` = 它对己方单位的每秒输出。
##
## 比 1 小是有意的：漏一个敌人扣的是整份 `atk`（§04 的曲线按那个数校过），
## 而打人是持续输出 —— 打人比漏进去更划算的话，敌人就没有理由继续推进了。
var enemy_attack_speed: float = 0.8

## 子弹飞完全场要几秒。**0 表示子弹瞬时命中**。
## 短到不会觉得「打了没反应」，长到看得出是一发飞过去的东西。
## 飞行时间也是离散出手唯一的损耗来源：目标在这几 tick 里死了，那一发就白放。
var projectile_cross_seconds: float = 0.8

## **近战**敌人打得到多远，与 [member field_length] 同轴。
##
## **不能比任何一个近战忍者的射程长**：敌人一走进射程就站住，这个数就是它停在离忍者多远的地方。
## 比忍者的近战射程长的话，那个近战忍者结构上永远够不着他，站在怪堆里整场一发打不出去，而测试全绿。
## 取原版 100 码（玩家定的；原版怪物的射程文档里没有），等于己方最短的近战射程。`tests/test_attack_range.gd` 钉着。
var enemy_reach: float = 0.05

## 一段动画有几帧。四段（idle / run / attack / dead）都是这个数，出图那一侧是六格图集。
##
## 它在 sim 里的唯一用处是把「第几帧出手」换成「第几 tick 出手」（[method windup_ticks]）——
## 不是让 sim 去读 [SpriteFrames]，那是渲染层的东西（铁律 1）。
var anim_frames: int = 6

## 出手落在攻击动画的**第几帧**（1 起，玩家定的）：远程在这一帧打出子弹，近战在这一帧结算伤害。
##
## 冷却好的那一刻只是**起手**，伤害要等到这一帧才落地，渲染层因此有一段真正的前摇（[method windup_ticks]）。
## 填 1 就是「一冷却好就出手」—— 子弹会在动画第一帧凭空射出来。
var attack_hit_frame: int = 4

## **远程**敌人打得到多远（§02）。停在这条线上放子弹，于是「前排挡住了」不再等于「全场安全」。
##
## **必须明显短于 [member reach_ranged]**：敌人停在离**最靠前**那个忍者这么远处，而远程忍者站在中排，
## 比前排靠后 [member column_front] − [member column_mid]。两边射程一样长的话远程忍者恒定差这一截够不着，
## 敌人单方面输出。它买的是「越过前排打后排」，不是「站在忍者射程之外」。
var enemy_reach_ranged: float = 0.15

## **BOSS** 打得到多远。**BOSS 一律远程**（玩家定的），不看 [member enemy_ranged_share] 那条槽位取模。
##
## 取 600 码（0.30，玩家定的），和远程忍者的原版射程一样长 —— 比普通远程怪远一倍，BOSS 波的打法因此和普通波分得开：
## 它停在离最前面那个忍者 0.30 处，中排远程忍者得往前走一截才够得着，前排近战得追过去。
## 原版解包数据里没有 BOSS 射程（BOSS 是再不斩、君麻吕这些英雄单位）。
var enemy_reach_boss: float = 0.30

## 一波里有几成敌人是远程（§02）。
## **按槽位定，不掷骰**：掷骰要占一条 RNG 流并移动它后面全部结果；同种子两次回放必须一样（§13）。
var enemy_ranged_share: float = 0.3

# ── 跑动与防挤（§02 / §03A）─────────────────────────────────────

## 己方单位走完全场要几秒。比敌人（[member march_seconds] 12 秒）快一倍：
## 跑得比敌人慢的话，前压永远追不上，那条跑动就只是一段没用的动画。
var unit_move_seconds: float = 6.0

## 己方单位最多离开自己的站位多远（[member PBAttacker.leash]）。
## **0 = 不拴**（玩家定的），落成覆盖全场（见 [method leash_distance]）。
##
## 实测不拴不会让漏怪变多（敌人主动扑向最近的活忍者，墙不靠站位挡），链子 0.6 以上就饱和
## （忍者最远只跑到离家 0.6 左右），而且松开之后近战更能打（不再卡在够不着的地方）。
##
## 机制还在（[PBMoveRules] 那套钳位没删），填回正数就恢复，`tests/test_unit_ai.gd` 显式设值在测。
## 填正数时两条约束：`leash_distance() + reach_melee ≥ enemy_reach_ranged`（否则一队全近战站着被点名到死）、
## `column_front + leash_distance() ≥ deploy_limit_x`（开打后能越过中线）。
var unit_leash: float = 0.0

## 两个单位之间至少留多远。**两边共用一个数** —— 己方和敌人挤在一起时，
## 玩家看到的是同一件事，没有理由分两档。
##
## 防挤顺带解决一个观感问题：聚拢（§02 的拉拽、§11 的七尾、§09 的功能档）
## 会把一群敌人拖到**同一个点**上，画出来是一个单位。
## 展开成队列之后聚拢仍然有效（间距 0.012 远小于大招半径 0.12），
## 但看得出来是「一堆人」而不是「一个人」。
var unit_min_gap: float = 0.012

# ── 蓝量（§03A）─────────────────────────────────────────────────

## 一发角色大招耗多少蓝。**写死一个数，不按蓝上限取比例** ——
## 取比例的话智力抬池子的同时也抬了消耗，那个属性就完全没用了。
var ultimate_mp_cost: float = 60.0

## 每秒回蓝多少（按蓝上限的比例）。0.06 = 每秒回 6%，约 17 秒回满。
##
## 按比例而不是写死一个数：**智力因此同时抬池子和回速**。
## 只抬池子的话，高智力只意味着「能存更多发」，攒满的速度一样 ——
## 那个属性就只在连放时有意义，平时等于没有。
var mp_regen_rate: float = 0.06

# ── 三选一抽卡 · 任务重刷 · 忍者升级（§08 / §06 / §03A）──────────

## 一次抽卡摆出几张让玩家挑（§08）。**改这个数会改 `gacha` 流的消耗次数**，
## 也就是说它是存档兼容性的一部分，不是一个能随便扫的旋钮。
var gacha_offer_size: int = 3

## 重刷任务的价格 `quest_reroll_base + quest_reroll_rate × 波次`（§06 给的是 `50 + 5n`）。
var quest_reroll_base: float = 50.0
var quest_reroll_rate: float = 5.0

## 忍者等级上限与价格曲线（§03A）。**占位值** ——
## 形状抄 §07 的科技树（`base × mult^Lv`），因为它和科技抢同一笔钱，
## 同形状才比得出来该先买哪个。
var unit_level_max: int = 20
var unit_level_cost: float = 120.0
var unit_level_mult: float = 1.35

## 合成表每个（稀有度, 属性）格子里有几号角色。
## **只在构造时读一次**，用来造 [member characters] 那张合成表 —— 改完要重新造表，光改数字不生效。
var characters_per_bucket: int = 2

## 全部角色（§09）。抽卡从这里出牌，估值按它算概率，羁绊按它认成员。
## 默认是 [method PBCharacterTable.synthetic] 造的合成表；真表由 core 外的加载器从 `data/characters/*.tres` 装进来。
var characters: PBCharacterTable = null

## 合成羁绊表的替身曲线：每个「在场且未被派遣」的单位提供的战力加成。
## **只在构造时读一次**，用来造 [member bonds] 那张合成表，真羁绊表装进来之后不生效。
var bond_power_per_unit: float = 0.06

## 羁绊加成的计数上限，防止后期堆卡无限叠。
var bond_unit_cap: int = 12

## 全部羁绊（§09）。战力结算按它算加成，界面按它显示。
## 默认是 [method PBBondTable.synthetic] 造的合成表；真表由 core 外的加载器从 `data/bonds/*.tres` 装进来。
var bonds: PBBondTable = null

# ── 装备（§10）──────────────────────────────────────────────────
## 一个配件多少钱。**后期金币的主要去处**：抽卡有天花板（卡池抽满后只剩重复卡），装备按人头加成，没有天花板。
##
## 300 是扫描定的：价格高到会算账的玩家整局一个都不买时，金币坑就不存在了；
## 太低（150）会饱和，后期金币又没处去。**降价容易涨价难**，所以取区间上沿。归数值回归。
var equip_part_cost: int = 300

## 几个配件合一件成品（§10：配件 → 成品需要 3 个）。
var equip_parts_per_item: int = 3

## 每个上场角色能带几件成品（§10：3 件）。
var equip_items_per_unit: int = 3

## 全部配件与成品（§10 的三级树）。合成看它、估值按它算、忍具箱从它出货。
## 默认是 [method PBEquipTable.synthetic] 造的合成表；真表由 core 外的加载器从 `data/equipment/*.tres` 装进来。
var equipment: PBEquipTable = null

## 逐角色的技能表。[member PBCharacter.skill_ids] 按 id 查它。
## **默认 null，null 就是「一个技能都没有」**（没有合成表，理由见 [PBSkillTable] 顶上）。真表由 [PBSkillLoader] 装进来。
var skills: PBSkillTable = null

## 合成装备表里每件成品给持有者的战力加成。**只给合成表用**，真装备表写的是词条（[member PBEquipItem.mods]）。
var equip_power_per_item: float = 0.20

# ── §11 尾兽 ────────────────────────────────────────────────────
## 全部尾兽。**默认是一张空表**：不带尾兽是真实局面（扫描的对照组），不需要替身。
## 真表由 core 外的加载器从 `data/beasts/*.tres` 装进来。
var beasts: PBBeastTable = null

## 尾兽大招的默认冷却（秒）。§11 给的是 60–90，默认 75。
##
## **75 秒 ≈ 每 2 波一次**，§11 原话：「这个节奏让玩家必须选择在哪一波
## 交底牌 —— BOSS 波前存着，还是这波就要顶不住了。」
##
## 它比角色大招（[member ultimate_cooldown_seconds]，20 秒）长一个量级，
## 这个比例本身就是设计：角色大招是节奏，尾兽大招是底牌。
## 两者一样长的话，「什么时候交底牌」这个决策就不存在了。
var beast_ultimate_cooldown_seconds: float = 75.0

## 尾兽每升一级，效果放大多少（0.25 = 每级 +25%，Lv10 = 3.25 倍）。
##
## **占位值。** §11 只给了升级价格和等级上限，没说一级值多少。
## 校它的判据不是「升级够不够爽」，而是 §11 那条硬要求：
## **机制型尾兽（六尾、七尾）不能被数值型挤掉。**
## 这个数越大，光环那一份（纯数值）涨得越猛，机制型就越吃亏 ——
## 所以它得等「一次聚拢值多少波次」量出来之后才定得了。
var beast_level_gain: float = 0.25

## 尾兽等级上限。§11 给的是 8–12。
var beast_level_max: int = 10

## 升级价格曲线 `cost × mult^Lv`。§11 明写 `400 × 1.6^Lv`。
var beast_level_cost: float = 400.0
var beast_level_mult: float = 1.6

# ── §07 经济 ────────────────────────────────────────────────────
## 金币科技：每 0.5 秒产出 `gold_tick_base × (1 + gold_tick_rate × Lv)`。
## 只在战斗阶段计时 —— 准备阶段不限时，让它在准备阶段产出等于无限金币。
var gold_tick_base: float = 5.0
var gold_tick_rate: float = 0.35

## 击杀掉落（击杀流）：50% → +35，30% → −15，20% → 0，期望 +13/击杀。
## §07 明确「原版保留不动，别去修」—— 它稳赚却包装成会看到扣钱的老虎机。
var kill_drop_gain: int = 35
var kill_drop_loss: int = -15

## 经济位（回合流）：第 k 个的收益 = `(economy_slot_base + economy_slot_rate × 波次) × k^−1.5`。
## 纯经济卡，无输出，占一个出战位。
##
## **收益必须随波次走**：常数版本下它几乎精确地不赚不赔，而收益分期到账、战力损失立即发生，
## 所以恒为微亏，没有流派会选 —— 一个恒定中性的选项没有决策内容。
##
## | 设定 | 结果 |
## |---|---|
## | 常数 85 | 选了反而更差，是个陷阱 |
## | 45 + 6n | 中性 |
## | **45 + 12n** | 略微有利，不支配 |
## | 45 + 24n | 支配 —— §07 警告的「无脑铺经济」 |
var economy_slot_base: float = 45.0
var economy_slot_rate: float = 12.0
var economy_slot_falloff: float = -1.5

## 科技价格曲线 `base × mult^Lv`，与等级上限。
var tech_gold_cost: float = 120.0
var tech_gold_mult: float = 1.35
var tech_gold_max: int = 20
var tech_pop_cost: float = 300.0
var tech_pop_mult: float = 1.8
var tech_pop_max: int = 6
var tech_def_cost: float = 180.0
var tech_def_mult: float = 1.45
var tech_def_max: int = 10
var tech_def_per_level: float = 0.04

# ── §08 抽卡 ────────────────────────────────────────────────────
## 单抽价格。§08 特意固定而非随波次上涨：后期收入指数增长，
## 固定价格意味着后期抽卡近乎免费，配合概率跃升形成「30 波后爆种」的体感。
var gacha_cost: int = 150

## 开局给多少金币。取 0 的话开局一张卡都没有，第 1 波必定全漏。
## 450（3 抽）：1–2 张卡足够过第 1 波，第 3 张留余量；又买不起同时升金币科技，开局第一个决策是真取舍。
var starting_gold: int = 450

## 保底：连续这么多抽没出 SSR 及以上，下一抽必出。
var gacha_pity: int = 20

# ── 模拟边界 ────────────────────────────────────────────────────
## 单局最多跑到第几波。到顶算「未卡波」，统计时要单独标出来，
## 否则会把「打穿上限」误读成「卡在这一波」。
var max_wave: int = 200

## 战斗用逐 tick 模型（[PBBattleSim]）还是解析式排队模型（[PBCombatRules]）。**默认 true，不该再改回去。**
##
## 解析式模型结构上装不下射程，给出的是另一套战斗规则。留着 false 这条路只为对拍
## （`test_attacker.gd`，满射程 · 单体 · 集火下两者必须逐字段相同）。拿它跑扫描等于在校一个玩家永远不会遇到的模型。
var use_tick_battle: bool = true


## 克制关系对应的伤害倍率。
func damage_multiplier(rel: PBElement.Relation) -> float:
	match rel:
		PBElement.Relation.COUNTER:
			return mult_counter
		PBElement.Relation.WEAK:
			return mult_weak
		PBElement.Relation.PHYSICAL:
			return mult_physical
		PBElement.Relation.DISTANT:
			return mult_distant
		PBElement.Relation.SAGE_MIRROR:
			return mult_sage_mirror
		_:
			return mult_neutral


## 波型对单体血量的倍率。
func shape_hp_mult(shape: PBWave.Shape) -> float:
	match shape:
		PBWave.Shape.SWARM:
			return swarm_hp_mult
		PBWave.Shape.ELITE:
			return elite_hp_mult
		PBWave.Shape.BOSS:
			return boss_hp_mult
		PBWave.Shape.MEGA_BOSS:
			return mega_boss_hp_mult
		_:
			return 1.0


## 原版 [param units] 码换成战场坐标。**全项目只有这一处换算**，见 [member war3_units_per_field]。
func units_to_field(units: float) -> float:
	return units / maxf(war3_units_per_field, 1.0)


## 这个角色打得多远（战场坐标）。配了原版射程就按它换算，没配就按射程档的默认距离。
## **战斗和画射程圈都走这里**，各算各的话「圈画到了、人却打不到」。
func reach_of(character: PBCharacter) -> float:
	if character != null and character.attack_range > 0.0:
		return units_to_field(character.attack_range)
	return reach_distance(PBCharacter.Reach.AUTO if character == null else character.reach_tier())


## 某个射程档的默认距离（没配原版射程的角色用，见 [method reach_of]）。
func reach_distance(tier: PBCharacter.Reach) -> float:
	match tier:
		PBCharacter.Reach.LONG:
			return reach_long
		PBCharacter.Reach.MELEE:
			return reach_melee
		_:
			return reach_ranged


## 「覆盖全场」的射程：从基地到最远那个角，**含场外集结区**。[method PBAttacker.whole_field] 靠它守住对拍锚点。
##
## 用 [member field_length] 的话够不着最远的角落；只算战场本身的话，场外方阵的最后一列不在射程里 ——
## 两种错的现象都是「对拍突然差了几个 tick」。
func field_diagonal() -> float:
	var staging: float = spawn_column_gap * ceilf(float(count_cap) / float(maxi(spawn_rows, 1)))
	return Vector2(field_length + staging, field_height).length()


## 这一局的皮带绳实际有多长。**[member unit_leash] 填 0 就是「不拴」**，在这里落成 [method field_diagonal]。
##
## 用 0 表示「不拴」而不是一个大数：「不拴」是一个状态，写成 99 的话读的人分不出「要放开」和「拍了个大数」
## （同 `formation` 空 = 自动站位的约定）。落成一个够大的距离之后，[PBMoveRules] 与
## [method PBBattleSim._nearest_enemy] 那四处读点的算术恒真且一字不改，不必各加一个「没拴就跳过」的分支。
func leash_distance() -> float:
	return unit_leash if unit_leash > 0.0 else field_diagonal()


## 第 [param slot] 个敌人出生在哪条泳道上。**不掷骰** —— 同一个种子的两次回放必须长得一样（§13）。
## 按方阵的行号排开，奇数列错开半行（整齐的网格读起来像队列，不像一群人）。
func enemy_lane(slot: int) -> float:
	var rows: int = maxi(spawn_rows, 1)
	var offset: float = 0.5 if posmod(slot / rows, 2) == 1 else 0.0
	return field_height * (float(posmod(slot, rows)) + 0.5 + offset) / float(rows + 1)


## 第 [param slot] 个敌人出生在多远处。
##
## 第一列正好在战场边缘，后面几列**排在战场之外**（见 [member spawn_column_gap]）。
func enemy_start_x(slot: int) -> float:
	return field_length + float(slot / maxi(spawn_rows, 1)) * spawn_column_gap


## 起手要几 tick：一段动画摊在一个攻击间隔上，出手前那几帧就是这么多。
## **钳在 `interval - 1` 以内**：等于间隔的话 `next_shot_at` 会追不上自己，这个人再也打不出第二发。
func windup_ticks(interval_ticks: int) -> int:
	var frames: int = maxi(anim_frames, 1)
	var hit: int = clampi(attack_hit_frame, 1, frames)
	var interval: int = maxi(interval_ticks, 1)
	return clampi(
		roundi(float(interval) * float(hit - 1) / float(frames)), 0, maxi(interval - 1, 0)
	)


## 每十个里固定前几个是远程，理由见 [member enemy_ranged_share]。
## 取模而不是比例乘法，是为了让**任何波次数量**下的比例都稳定 ——
## 按 `slot < count × share` 分的话，潮水波的远程全挤在队头，
## 精英波可能一个都没有。
## 第 [param slot] 个敌人是不是远程（§02）。按槽位取模，见 [member enemy_ranged_share]。
func enemy_is_ranged(slot: int) -> bool:
	return float(posmod(slot, 10)) < clampf(enemy_ranged_share, 0.0, 1.0) * 10.0


## 出战席第 [param index] 个人（共 [param count] 个）默认站哪条泳道。均分，不用黄金比散布
## （同一列的人 x 完全相同，散布会让他们叠在一起）。**这是默认值**，玩家拖动过的由 [PBFormationRules] 覆盖。
func ally_lane(index: int, count: int) -> float:
	return field_height * (float(index) + 0.5) / float(maxi(count, 1))


## 某个射程档站在哪一列。**站位是射程的派生量**，见 [PBAttacker] 的说明。
func reach_column(tier: PBCharacter.Reach) -> float:
	match tier:
		PBCharacter.Reach.LONG:
			return column_back
		PBCharacter.Reach.MELEE:
			return column_front
		_:
			return column_mid


## 波型对数量的倍率。BOSS 波不走倍率，直接用定值数量，故不在此列。
func shape_count_mult(shape: PBWave.Shape) -> float:
	match shape:
		PBWave.Shape.SWARM:
			return swarm_count_mult
		PBWave.Shape.ELITE:
			return elite_count_mult
		_:
			return 1.0


func _init() -> void:
	# 字段初始化跑完才轮到 _init，所以这里读得到上面那几个字段。
	characters = PBCharacterTable.synthetic(characters_per_bucket)
	bonds = PBBondTable.synthetic(bond_power_per_unit, bond_unit_cap)
	equipment = PBEquipTable.synthetic(equip_parts_per_item, equip_power_per_item)
	# 尾兽默认是空表 —— 那是对照组，不是替身曲线，见 [member beasts]。
	beasts = PBBeastTable.new()


## 复制一份。批量扫描时每个参数组合克隆一份再改，避免共享可变状态。
##
## [member characters] 与 [member bonds] 是**共享引用而不是深拷贝** ——
## 两张表造完只读，几千个格子各拷一份几十个 Resource 纯属浪费。
func clone() -> PBSimConfig:
	var copy := PBSimConfig.new()
	for prop: Dictionary in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(prop["name"], get(prop["name"]))
	return copy
