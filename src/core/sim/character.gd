class_name PBCharacter
extends Resource
## 一个角色的静态定义（§09）。
##
## 是 Resource：存成 `data/` 下的 `.tres`，**换皮只改 `data/` 与语言表**（铁律 5）。
## `extends Resource` 不违反 core 纯度 —— 被挡住的是 `ResourceLoader`，加载在 core 外面，
## core 不知道文件从哪来，测试可以直接造表。
##
## 本类是**角色本身**（不可变，全局一份）；[PBUnit] 是**玩家手上的那张卡**（一局一份），一对多。
##
## 大招由统一规则生成（全场一套数值），角色只能覆盖它的属性（[member ultimate_element_override]）；
## [member skill_ids] 点的是 `data/skills/` 里逐角色独有的技能。

## 射程档，配合 §02 的前中后三列。
##
## 做成**档位**而不是浮点：站位因此是射程的派生量而不是第二份数据；
## 具体距离是要扫的参数，写在 [PBSimConfig] 里才扫得动。
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

## 查**战场形象**用的键，对上 [member PBActorSkin.key]。**空着 = 用白模**（见 [PBActorLibrary]）。
##
## **不和 [member icon_key] 合并**：头像和战场形象的尺寸、张数、朝向、命名规则没有一条相同，
## 合成一个键的话「只画了一样」就没有地方表达。
@export var actor_key: StringName = &""

## 普攻子弹用哪一份，对上 [member PBShotSkin.key]。**空着 = 白模子弹。** 来自名册的「普攻子弹」列。
##
## **挂在角色上，不挂在形象上，也不按属性推**：同一张形象换一颗子弹、同是火系一个吐火球一个扔苦无，
## 都是逐个配的事。技能的子弹另配（[member PBSkill.shot_key]）。
@export var shot_key: StringName = &""

## **攻元素**：这个角色打出去的伤害算哪一系（§03 / §03A）。
## 真正的 `element` 挂在伤害事件上（铁律 4），大招可以另配一系（[member ultimate_element_override]）。
@export var element: PBElement.Type = PBElement.Type.PHYSICAL

## **防元素**：别人打它时按哪一系算克制（§03A）。
##
## 和攻元素分开：合成一个的话「它打谁」和「它扛谁」永远指向同一波。
## 敌人两个元素都用波次元素，所以一波之内两个问题指向同一个敌人元素，学得会、算得清。
@export var def_element: PBElement.Type = PBElement.Type.PHYSICAL

# ── 二级属性与系数（§03A）──────────────────────────────────────

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

## 射程档（§02）。默认 [constant Reach.AUTO] —— 见 [method reach_tier]。
## **只决定站前排、中排还是后排**；打多远看 [member attack_range]。
@export var reach: Reach = Reach.AUTO

## 攻击距离，**原版码数**（125 / 600 / 245 …，照抄原版物编）。换算成战场坐标走
## [method PBSimConfig.reach_of]，那里是唯一的换算点。**0 = 没配**，按 [member reach] 那一档的默认距离。
##
## 存码数不存战场坐标：改战场尺寸或换算比例时表里一个数都不用动，而且和原版文档逐个对得上。
@export var attack_range: float = 0.0

## 单体还是范围（§04 靠它把潮水波与精英波的价值分开）。
## 枚举借用 [enum PBAttacker.Shape]：调用点都在战斗层，数据层再定义一个同义枚举只会多一处要同步。
@export var attack_shape: PBAttacker.Shape = PBAttacker.Shape.SINGLE


## 大招的伤害属性，**-1 表示与 [member element] 相同**（铁律 4：本体土属性、大招火系这种角色靠它）。
## 用 -1 当哨兵而不是给 [enum PBElement.Type] 加 `AUTO`：那个枚举是克制环本身，塞一个不参与克制的值
## 会让每一处遍历都多记一条例外。
@export var ultimate_element_override: int = -1

## 大招之外，这个角色还会哪几个技能。每一项是 `data/skills/<id>.tres` 的 id。
## **最多两个**（指令卡只画得下两格），数据测试钉着。
##
## **填上了也不改变任何自动跑出来的数字**：技能只有玩家手动放得出（自动档只挑地面落点），
## 批量扫描、悬崖二分、配平回归都碰不到它。
@export var skill_ids: Array[StringName] = []


## 他自带的常驻被动：键 → 量。词汇表与落点见 [PBPassiveRules]。
##
## **被动不是技能**：「攻击时 X% 触发 Y」没有施法、冷却、蓝，玩家按不出来，塞进技能表只能降格成按钮。
## **填上了会改变自动模拟的输出**（和 [member skill_ids] 相反）：他站着就一直在发生。
@export var passives: Dictionary = {}

## 被动里那份「打出要害就给目标挂上」的效果。
## **和 [member passives] 是名册同一列的两半**（`键=量` / `on_hit=<效果键>`）：一个存数、一个存引用，
## 混进同一个 Dictionary 的话读的人得先知道哪些键是引用。
@export var on_hit_buffs: Array[PBBuff] = []

## 被动里「血量掉到阈值那一刻给自己挂上」的效果（名册同一列的 `on_low_hp=<效果键>`）。
## 阈值是 [member passives] 里的 `low_hp`：一个存数、一个存引用，理由同 [member on_hit_buffs]。
@export var low_hp_buffs: Array[PBBuff] = []

## 被动里「受致命伤那一下挡住、给自己挂上」的效果（名册同一列的 `on_lethal=<效果键>`）。一波一次。
@export var lethal_buffs: Array[PBBuff] = []

## 被动里「挨敌人一下时挂出去」的效果（名册同一列的 `on_struck=<效果键>`）。增益挂自己，减益挂打他的敌人。
@export var struck_buffs: Array[PBBuff] = []

## 被动里「每一下普攻打中都给目标挂上」的效果（名册同一列的 `on_attack=<效果键>`）。
## 和 [member on_hit_buffs] 的区别只在**不骑暴击**：那一份只在打出要害时挂。
@export var attack_buffs: Array[PBBuff] = []


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
