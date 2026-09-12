class_name PBCharacter
extends Resource
## 一个角色的静态定义。§09 的数据结构，M2-a。
##
## ## 为什么它是 Resource 而不是 RefCounted
##
## 因为角色表要存成 `data/` 下的 `.tres`：检查器里可视化编辑、git diff 可读、
## **换皮时只改 `data/` 与语言表，`src/core/` 一行不动**（§14 铁律 5）。
## 只有 Resource 能被序列化成 `.tres`。
##
## `extends Resource` 不违反「core 零引擎依赖」—— 它不是 Node、不碰场景树、
## 不读 delta。真正被 core 纯度检查挡住的是 `ResourceLoader`，
## **所以「加载 .tres」这件事必须发生在 core 外面**，core 只认这个类型。
## 那正是想要的分工：core 不知道文件从哪来，测试可以直接造表。
##
## ## 和 [PBUnit] 的区别
##
## 本类是**角色本身**（不可变，全局唯一一份）；[PBUnit] 是**玩家手上的那张卡**
## （有张数、有星级，一局一份）。两者一对多。
##
## ## 已知的省略
##
## - ~~`skill_ids`~~ **M7-g 兑现了**，见 [member skill_ids]。
##   大招仍然由 [PBSkill] 按统一规则生成（全场共用一套数值），
##   角色只能覆盖它的属性（[member ultimate_element_override]）；
##   而 `skill_ids` 点的是 `data/skills/` 里逐角色独有的那几个
##
## §09 那行 `base_stats: PBStats` 从 M2-a 起一直空着（那时战力只有一条
## `rarity_power` 阶梯），**M3.5-a 把它兑现了** —— 见下面那一批二级属性字段。

## 射程档。M3-a 新增，配合 §02 的前中后三列。
##
## 做成**档位**而不是一个裸浮点，有两个理由：
##
## 1. 三个档正好对上 §02 的三列，站位因此是射程的派生量而不是第二份数据
## 2. 具体距离是要扫的参数，写在 [PBSimConfig] 里才扫得动；
##    写进 30 个 `.tres` 等于把可调参数散进数据文件
enum Reach {
	AUTO,  ## 按属性取默认：物理近战，五系远程。**`.tres` 不写就是这一档**
	MELEE,  ## 近战，站前排
	RANGED,  ## 远程，站中排
	LONG,  ## 超远程，站后排
}

## 主属性（§03A）。**攻击力只由这一项决定**，另外两项各管自己那条线
## （力量 → 血，敏捷 → 防与攻速，智力 → 蓝）。
##
## 原作是 War3 的 RPG 地图，这套「三属性 + 一个主属性吃攻击」的骨架直接沿用 ——
## 它已经被验证过几十年，而且玩家一眼就懂。
enum Primary { STRENGTH, AGILITY, INTELLECT }

## 一个角色最多配几个技能（决策 6）。见 [member skill_ids]。
const MAX_SKILLS: int = 2

## 全局唯一 id。**代码里不出现角色名，一律走 id**（§14 铁律 5）。
##
## 它同时是 [method PBUnit.key] 的返回值，也就是仓库字典的键，
## 以及 §12 存档里记录「我有哪些卡」的那个值。改 id 等于让老存档认不出卡。
@export var id: StringName = &""

## 查语言表用的键。显示名只在这一层出现，`src/` 其余地方一个字都不该有。
@export var name_key: String = ""

## 查**头像**图集用的键（卡面、信息栏那一套 UI）。白模阶段先留着不用。
@export var icon_key: String = ""

## 查**战场形象**用的键，对上 [member PBActorSkin.key]（M6-b）。
##
## ## 为什么不和 [member icon_key] 合并
##
## 头像是一张静态图、正面、要在 20 像素见方的格子里认得出来；
## 战场形象是一整套侧面动画、脚底要对齐、有 idle/run/attack 三段。
## 两者的素材尺寸、张数、朝向、命名规则没有一条相同 ——
## 合成一个键的话，「这个角色只画了战场形象、头像还没排期」
## 就没有地方表达，而那正是眼下的实际状态。
##
## **空着 = 用白模**（[PBWhiteModel]），见 [PBActorLibrary]。
@export var actor_key: StringName = &""

## **攻元素**：这个角色打出去的伤害算哪一系（§03 / §03A）。
##
## **注意 §03 的铁律：真正的 `element` 是挂在伤害事件上的，不是挂在单位上。**
## 大招可以另配一系，见 [member ultimate_element_override]。
##
## M3.5 起攻防拆成两个元素，本字段收窄成「它打什么系」，
## 名字没改是因为它同时是**羁绊的属性型兜底档的匹配依据**（§03A）——
## 那是 §03「每波换克制系上场」时玩家看的那个数，
## 而且现有六组属性羁绊与它们的全部测试都建在这个字段上。
@export var element: PBElement.Type = PBElement.Type.PHYSICAL

## **防元素**：别人打它时按哪一系算克制（§03A，M3.5-a）。
##
## ## 为什么要和攻元素分开
##
## 合成一个的话，一张卡在「它打谁」和「它扛谁」两条线上永远指向同一波 ——
## 攻防两轴同进同退，拆开就没有意义了。分开之后玩家要同时问两个问题：
## 攻元素克不克得动这一波、防元素扛不扛得住这一波。
##
## **敌人两个元素都用波次元素**（§04 的轮转表一行不改），
## 所以一波之内两个问题指向同一个敌人元素，学得会、算得清。
@export var def_element: PBElement.Type = PBElement.Type.PHYSICAL

# ── 二级属性与系数（§03A，M3.5-a）───────────────────────────────
#
# **这一批数是占位值**，由生成脚本按稀有度 + 射程档 + 主属性铺出来，
# 没有扫描依据。它们的形状（哪些字段、谁影响谁）是设计，数字不是。

## 主属性。攻击力由它决定 —— 原作是 War3 的 RPG 地图，沿用那套骨架。
@export var primary: Primary = Primary.STRENGTH

## 1 级时的二级属性。
@export var strength: float = 18.0
@export var agility: float = 12.0
@export var intellect: float = 12.0

## 每升一级二级属性各涨多少。**逐角色不同，这是「定位」的数据来源** ——
## 主属性涨得快的那一项决定了这张卡往哪个方向成长。
@export var strength_growth: float = 2.6
@export var agility_growth: float = 1.4
@export var intellect_growth: float = 1.4

## 基础属性的固定部分（二级属性还没加成时的值）。
@export var hp_base: float = 200.0
@export var mp_base: float = 60.0
@export var atk_base: float = 60.0
@export var def_base: float = 1.0

## 基础攻速（每秒攻击几次）。
@export var attack_speed_base: float = 1.0

## 二级属性 → 基础属性的转化系数。**逐角色不同**：
## 高 [member hp_per_strength] 的是坦克，高 [member atk_per_primary] 的是输出，
## 这和稀有度是两条独立的轴（§08 的稀有度阶梯只管「整体强多少」）。
@export var hp_per_strength: float = 16.0
@export var mp_per_intellect: float = 8.0
@export var atk_per_primary: float = 1.0
@export var def_per_agility: float = 0.22
@export var attack_speed_per_agility: float = 0.008

## 稀有度（§08）。
##
## 类型借用 [enum PBUnit.Rarity]。§09 的规格里叫 `PBRarity.Type`，
## 改名是纯粹的调用点搬迁、零行为变化，等有必要时再做。
@export var rarity: PBUnit.Rarity = PBUnit.Rarity.R

## 射程档（§02，M3-a）。默认 [constant Reach.AUTO] —— 见 [method reach_tier]。
@export var reach: Reach = Reach.AUTO

## 单体还是范围（§04 靠它把潮水波与精英波的价值分开）。
##
## 枚举借用 [enum PBAttacker.Shape]，与 [member rarity] 借用
## [enum PBUnit.Rarity] 是同一个理由：调用点都写在战斗层，
## 让数据层再定义一个同义枚举只会多一处要同步的地方。
##
## **M3-a 全表都是单体**，一个都没分配出去。不是忘了：
## 谁该是 AOE 要么由技能表决定（M3 的大招那一步），要么得有扫描依据，
## 现在拍十几个角色成 AOE 会污染 M3-a 正在量的三条缺口。
@export var attack_shape: PBAttacker.Shape = PBAttacker.Shape.SINGLE


## 大招的伤害属性，**-1 表示与 [member element] 相同**。
##
## §03 的铁律是「element 挂在伤害事件上，不挂在单位上」。M2 之前
## 一个角色只有一个输出来源，两者恰好重合，铁律看起来像句空话 ——
## **大招是它第一次真正用上的地方**：本体土属性、大招火系这种角色
## （§09 点名的迪达拉）没有这一行就做不出来。
##
## 用 -1 当哨兵而不是给 [enum PBElement.Type] 加一个 `AUTO` ——
## 那个枚举是 §03 的克制环本身，往里塞一个不参与克制的值，
## 会让每一处遍历五系的代码都要多记一条例外。
@export var ultimate_element_override: int = -1

## 大招之外，这个角色还会哪几个技能（决策 6，M7-g）。
## 每一项是 `data/skills/<id>.tres` 的 id。**最多两个**，数据测试钉着。
##
## ## 为什么上限是 2
##
## 把大招数进去之后它和 §08 那张稀有度表严丝合缝：
## R 一个（大招）、SR 两个、SSR 三个 + 专属机制。
## §08 那句「稀有度剩下的价值走技能数，不走数值」本来就要一个技能表来承接，
## 而它从 M2-a 起一直空着（本类顶上「已知的省略」第一条）。
##
## ## 空着 = 一字不差
##
## 技能**只有玩家手动放得出**（自动档只挑地面落点，`PBAimRules` 不知道
## 该治谁；§6 那条「批量扫描不吃技能」就是这个意思）。所以给一个角色
## 填上这一项**不改变任何自动跑出来的数字** —— 批量扫描、悬崖二分、
## 配平回归全都碰不到它，和 M3.5-f 装备那条「空着 = 一字不差」同形，
## 只是这一次连「填上了」也一字不差。
@export var skill_ids: Array[StringName] = []


## 他自带的常驻被动：键 → 量（M12-c2）。词汇表与落点见 [PBPassiveRules]。
##
## ## 被动不是技能，所以它不在 [member skill_ids] 里
##
## 原版 56 张卡里有 10 个是「攻击时 X% 触发 Y」这种东西 ——
## **没有施法、没有冷却、没有蓝，玩家按不出来**。塞进技能表的话只能
## 降格成一个要手动按的自增益（M12-c1 的佩恩轮回眼就是那么落的，
## 一个纯被动变成了 30 秒 CD 的按钮），而那改的是玩法不是数值。
##
## ## 填上了**不是**一字不差，和 [member skill_ids] 正相反
##
## 那一项空着满着都不动任何自动跑出来的数（技能只有玩家放得出），
## 而被动**他站着就一直在发生** —— 批量扫描、悬崖二分、配平回归全都吃得到。
## 这是 M12 头一步真的动了自动模拟的输出，归数值回归。
@export var passives: Dictionary = {}


## 大招实际打什么属性。见 [member ultimate_element_override]。
func ultimate_element() -> PBElement.Type:
	if ultimate_element_override < 0:
		return element
	return ultimate_element_override as PBElement.Type


## 实际射程档。[constant Reach.AUTO] 在这里落成具体档位。
##
## 默认规则只有一条：**物理近战，五系远程。**
## §03 把物理定位成「这波我没配对」的保底补丁，恒定 1.05 不吃克制；
## 让它换取的是站位 —— 站前排先接敌、覆盖面窄。
## 这样物理位的存在价值不只是一个数字，也是一个空间位置。
func reach_tier() -> Reach:
	if reach != Reach.AUTO:
		return reach
	if element == PBElement.Type.PHYSICAL:
		return Reach.MELEE
	return Reach.RANGED


## 造一个角色。字段全部只读语义 —— 造完不要再改。
static func make(
	character_id: StringName,
	character_element: PBElement.Type,
	character_rarity: PBUnit.Rarity,
	character_name_key: String = ""
) -> PBCharacter:
	var out := PBCharacter.new()
	out.id = character_id
	out.element = character_element
	out.rarity = character_rarity
	out.name_key = character_name_key if character_name_key != "" else String(character_id)
	# §03A：代码造出来的角色也得有属性表，否则每个人都吃默认值 ——
	# **R 和顶档的战力会一模一样**，而那不会让任何断言变红。
	# 真角色表的同一套数字由生成脚本写进 `.tres`，规则见 [method PBStatRules.fill_placeholder]。
	PBStatRules.fill_placeholder(out)
	return out
