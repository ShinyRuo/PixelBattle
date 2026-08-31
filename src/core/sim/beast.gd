class_name PBBeast
extends Resource
## 一只尾兽的静态定义。§11 的数据结构，M3-d。
##
## 开局从 9 只里选 1，**全程只有这一只**：一个常驻光环 + 一个手动大招。
## §11 原话是「这是复刻版最重要的手动干预点 —— 它承接了原版吸怪留下的技巧位」。
##
## ## 为什么它是 Resource
##
## 和 [PBCharacter] / [PBBond] / [PBEquipItem] 同一个理由：要存成 `data/` 下的
## `.tres`，检查器可视化编辑、git diff 可读、换皮只改数据（§14 铁律 5）。
## 加载发生在 core 外面（`ResourceLoader` 在 core 里禁用）。
##
## ## 光环和大招是两种不同的东西，不能只靠数值区分
##
## §11 点名警告过：**七尾（纯聚拢）和六尾（重置全体大招 CD）是机制型尾兽，
## 不能被数值型挤掉。** 七尾给的是「不依赖特定羁绊的聚怪路径」——
## 抽不到聚拢角色的局靠它救命；六尾是连招流的开关。
##
## 所以本类的大招字段里，**伤害只是其中一项**，
## 聚拢 / 击退 / 减速 / 重置 CD / 全队增伤各占一个字段，
## 一只尾兽可以伤害为 0 而依然很强。数值型和机制型因此在数据层就是可分辨的，
## 不必靠「把机制折算成伤害」来比较 —— 那种折算正是 §11 担心的那种挤压。
##
## ## 有两处效果在当前战斗模型下诚实地等于 0
##
## - 一尾的光环「全体防御 +12%」—— **己方单位不会死**，减伤没有去处
## - 八尾的大招「召唤分身承伤」—— **敌人不还手**，没有伤害可承
##
## 数据里照实填 0，**不把防御效果折算成伤害**（§10 在装备上定下的规矩，
## 见 [member PBEquipItem.power]）。折算了就等于凭空发明一份收益，
## 而调参的人会拿着那份收益去定价。等 [PBBattleSim] 有了「敌人还手」，
## 改的是 `.tres` 里的数，代码一行不动。
##
## **这两只尾兽都不因此变成废物** —— 一尾靠大招的全屏减速，
## 八尾靠光环的全体攻击 +12%。每一只都至少有一半是活的。

## 光环和大招都不限定属性时用的哨兵。
##
## 和 [member PBCharacter.ultimate_element_override] 用同一套路，理由也一样：
## [enum PBElement.Type] 是 §03 的克制环本身，往里塞一个不参与克制的值，
## 会让每一处遍历五系的代码都要多记一条例外。
const ANY_ELEMENT: int = -1

## 全局唯一 id。**代码里不出现尾兽名，一律走 id**（§14 铁律 5）。
@export var id: StringName = &""

## 查语言表用的键。
@export var name_key: String = ""

# ── 光环：全程生效，不需要任何操作 ──────────────────────────────
## 给受影响单位的伤害加成（乘算，0.12 = +12%）。
##
## 三个筛选字段（[member aura_element] / [member aura_member_ids]）都为空时
## 就是「全体」。八尾的全体攻击 +12% 走这一条。
@export var aura_power: float = 0.0

## 光环只对这个属性的角色生效。[constant ANY_ELEMENT] 表示不限。
##
## 三尾的水系 +15%、五尾的土系 +15% 走这一条。**它把尾兽和 §03 的属性系统
## 挂上钩**：选了三尾就更想凑水系，而水系只在五波轮转里的一波吃到克制 ——
## 于是「选哪只尾兽」和「带哪些卡」不是两个独立决策。
@export var aura_element: int = ANY_ELEMENT

## 光环只对点名的角色生效。空表示不限。
##
## 九尾的「专属强化（鸣人系角色）」走这一条。名单存 [member PBCharacter.id]，
## 和 [member PBBond.member_ids] 同一个口径 —— 代码里仍然不出现名字。
@export var aura_member_ids: Array[StringName] = []

## 角色大招冷却的倍率（0.8 = 冷却缩短两成）。
##
## 六尾的「团队回蓝速度 +25%」走这一条：1 ÷ 1.25 = 0.8。
## **回蓝在当前模型里没有独立的资源条**，唯一能观测到的后果就是大招放得更勤，
## 所以直接折成冷却倍率 —— 这不是「把机制折算成数值」，
## 是同一件事在没有蓝条的模型里的等价表达。
@export var aura_ultimate_cd_scale: float = 1.0

## 光环给基地的额外减伤（0.12 = 再减 12%）。
##
## 一尾的「全体防御 +12%」写在这里。**当前恒为 0**，理由见本类顶部：
## 己方单位不会死，「全体防御」没有作用对象。填在这儿而不是删掉，
## 是因为等敌人会还手之后它就有值了，那时改数据不改代码。
@export var aura_def_reduction: float = 0.0

# ── 大招：手动交的底牌，一局能放几次由 CD 决定 ──────────────────
## 冷却（秒）。0 表示用 [member PBSimConfig.beast_ultimate_cooldown_seconds]。
##
## §11 默认 75 秒 ≈ 每 2 波一次，「这个节奏让玩家必须选择在哪一波交底牌 ——
## BOSS 波前存着，还是这波就要顶不住了」。
@export var ultimate_cooldown_seconds: float = 0.0

## 一发大招 = **全队几秒的输出**。
##
## ## 为什么用「秒」而不是一个倍率
##
## 尾兽不是队伍里的一张卡，它没有自己的战力，所以「角色基础战力的 N 倍」
## （角色大招那套，见 [member PBSimConfig.ultimate_power_mult]）在这里没有分母。
##
## 拿全队 DPS 当分母有两个好处：**它自动跟着指数曲线走**（尾兽不会前期无敌、
## 后期作废），而且这个数**读得懂** —— 「一发等于全队 8 秒输出」
## 直接就能和 75 秒的冷却比，一眼看出它占总输出的一成。
@export var ultimate_damage_seconds: float = 0.0

## 大招的伤害属性。[constant ANY_ELEMENT] 表示不吃克制（中性 1.0）。
##
## 尾兽不属于 §03 的五系轮转，所以默认中性；点了属性的那几只
## （三尾水、五尾土）连大招一起吃克制，与光环同向 —— 这让「选尾兽」
## 这个决策在属性维度上是有方向的，而不是一个纯数值的加成。
@export var ultimate_element: int = ANY_ELEMENT

## 杀伤半径。**0 或负数表示全屏**（§11 里「全屏点燃」「全屏减速力场」那几只）。
@export var ultimate_radius: float = 0.0

## 一发最多命中几个。**0 表示不限**（范围内全中）。
##
## 九尾的「超大单体爆发」填 1 —— 那正是它作为 BOSS 特化的全部意义：
## 伤害集中在一个目标上，潮水波里几乎没用，BOSS 波里一发抵一整波普攻。
@export var ultimate_max_targets: int = 0

## 落地时把范围内的敌人拖到落点（§02 的拉拽 / §11 七尾的「大范围聚拢」）。
##
## **七尾必须有这一条。** §11 原话：「它的大招是纯聚拢，等于给玩家一条
## 不依赖特定羁绊的聚怪路径。没有它，聚拢就被锁死在少数几个角色身上，
## 抽不到就没法玩 —— 这在无限流里是致命的。」
@export var ultimate_gather: bool = false

## 落地时把范围内的敌人往出生点方向推多远（三尾的「范围击退」）。
##
## 与 [member PBEnemy.distance] 同一根轴。和 [member ultimate_gather]
## 是相反方向的两种位置操纵：聚拢把人拉到一起，击退把人推远。
## 两者都不产生伤害，价值全在「敌人晚到基地多久」上。
@export var ultimate_knockback: float = 0.0

## 落地后敌人的速度倍率（0 = 定身，0.5 = 减速一半，1.0 = 不减速）。
##
## 一尾的「全屏减速力场」、五尾的「地形阻挡，延缓推进」走这一条。
@export var ultimate_slow_scale: float = 1.0

## 减速持续多少秒。
@export var ultimate_slow_seconds: float = 0.0

## 落地后全队伤害的倍率（1.15 = 短时全队 +15%）。
##
## 二尾的「短时全体暴击必中」走这一条 —— 暴击在当前模型里没有独立的掷骰，
## 「必中」唯一能观测到的后果就是这段时间内伤害更高。
@export var ultimate_team_damage_scale: float = 1.0

## 全队增伤持续多少秒。
@export var ultimate_buff_seconds: float = 0.0

## 落地时把全体**角色**大招的冷却清零。
##
## **六尾的开关，§11 点名不能被挤掉的两只之一。** 它自己一点伤害都不打，
## 价值完全来自「让别人多放一轮」—— 所以它的强度与队伍里大招的总量成正比，
## 而不是和自己的数值成正比。这正是 §11 说的「机制型」。
@export var ultimate_reset_cooldowns: bool = false


## 这个角色吃不吃得到本尾兽的光环。
##
## 两个筛选条件是**与**的关系：点了属性又点了名单，两条都得满足。
## 现在没有哪只尾兽同时用两条，但把语义定死总好过让它含糊。
func aura_applies_to(character: PBCharacter) -> bool:
	if character == null:
		return false
	if aura_element != ANY_ELEMENT and int(character.element) != aura_element:
		return false
	if not aura_member_ids.is_empty() and not aura_member_ids.has(character.id):
		return false
	return true


## 这只尾兽的大招会不会产生**任何**可观测的后果。
##
## 全 0 的大招不该占用 [PBBattleSim] 的一个攻击者槽位 ——
## 它每 tick 都会去挑落点、每次冷却好都会「放」一发什么也不发生的大招，
## 纯属浪费，而且会让「尾兽值多少」的对照组里混进一份噪声。
func has_ultimate() -> bool:
	if ultimate_damage_seconds > 0.0 or ultimate_gather or ultimate_reset_cooldowns:
		return true
	if ultimate_knockback > 0.0:
		return true
	if ultimate_slow_seconds > 0.0 and ultimate_slow_scale < 1.0:
		return true
	return ultimate_buff_seconds > 0.0 and ultimate_team_damage_scale > 1.0
