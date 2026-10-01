class_name PBSkill
extends Resource
## 一个技能的**定义**：伤害、半径、冷却、耗蓝、位置操纵……不含这一波的状态
## （状态在 [PBSkillCast]，所以本类永远不会有状态可漏）。
##
## **大招是每个角色的 0 号技能**，由 [method PBCombatRules._build_skill] 按 [PBSimConfig] 生成
## （具体数值是要扫的参数）；角色自己的技能来自 `data/skills/*.tres`，同一个类。
##
## 是 Resource：`extends Resource` 不违反 core 纯度，加载在 `src/data/`。
##
## ## 地面技能必须有施法延迟
##
## §02 的吸怪分层（自动落点够用、手动有赚头）要求**落点先于结算确定**：当场结算的话，
## 当前帧最密的点永远等于结算时最密的点，自动和手动必然同分，那两条验收什么都没测。
## 所以落点在下达时定死（[method PBSkillCast.cast]），[member delay_ticks] 之后才落地
## （[method PBSkillCast.land]）—— 这段窗口也是渲染层画落点预示圈的时间。
##
## 和 [PBAttacker] 分工：那边管普攻（按射程选最靠近基地的），这边管技能（按密度选落点）。

## 玩家要**点什么**。和 [enum Party] 是两根独立的轴，见 [member target]。
enum Target {
	NONE,  ## 什么都不用点，按下去就放（自增益、自身周围 / 全场打击）
	ALLY,  ## 等他点一个**己方单位**（医疗忍术）
	ENEMY,  ## 等他点一个敌人；可以单体结算，也可以围绕主目标结算范围效果。
	GROUND,  ## 等他点一块**地**，走落点 + 施法延迟那一套（现在的大招）
}

## 结算**落在哪一边**。
enum Party {
	ALLIES,
	ENEMIES,
}

## 玩家要点什么。**默认 [constant Target.GROUND]**。
##
## 「点什么」和「落在谁」是两根轴 —— 合成一个的话「地面范围治疗」表达不出来：
##
## [codeblock]
## NONE   + ALLIES   自增益，点一下就放
## NONE   + ENEMIES  radius > 0 自身周围，否则全场打击
## ALLY   + ALLIES   医疗忍术
## ENEMY  + ENEMIES  单体爆发、单体控
## GROUND + ENEMIES  大招
## GROUND + ALLIES   团队治疗圈
## [/codeblock]
##
## **没有 `SELF` 这一档**：自增益就是 `NONE` + [member on_self]，两种写法就是两把尺子。
@export var target: Target = Target.GROUND

## 这份技能是谁。`data/skills/<id>.tres` 的文件名就是它。
## **大招不填这一项**：它由 [PBSimConfig] 现造，全场共用一套数值，不是 `data/` 里的一条。
@export var id: StringName = &""

## 这一发飞出去的东西长什么样（[PBShotSkin] 的键）。空着退回白模（[method PBWhiteModel.shot]）。
## **配在技能上而不是人身上**（[member PBActorSkin.shot_key] 管普攻）：火球术换个人放还是火球。
@export var shot_key: StringName = &""

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

## 命中时挂给**目标**的效果。
## 存**直接引用**而不是 id：`ext_resource` 指向 `data/buffs/*.tres` 就是 Godot 原生的外键。
@export var on_hit: Array[PBBuff] = []
## 普攻起手触发的连续圆形爆发：每圈独立命中，重叠允许重复；主目标效果另结算一次。
@export var attack_chain_count: int = 0
## 攻击起手额外普攻；独立于技能伤害公式，沿用普攻两轴、暴击与命中效果。
@export var attack_repeat_count: int = 0
## 常驻治疗光环：按秒写回复量，按全局周期结算；半径 0 只治疗自身。
@export var heal_aura_flat: float = 0.0
@export var heal_aura_growth: float = 0.0
@export var heal_aura_max: float = 0.0
@export var heal_aura_period_ticks: int = 1
@export var heal_aura_hit_chance: float = 0.0
@export var heal_aura_lost: float = 0.0
@export var attack_chain_step: float = 0.0
@export var self_attack_bonus: float = 0.0
@export var self_attack_bonus_growth: float = 0.0
@export var on_primary: Array[PBBuff] = []
@export var attack_trigger_chance: float = 0.0
## 弹道命中后只对主目标周围的其他敌人附加禁锢，不复制主目标伤害或效果。
@export var impact_hold_radius: float = 0.0
@export var impact_hold_seconds: float = 0.0
@export var channel_control: bool = false
@export var mind_control: bool = false
@export var extra_control_scale: float = 1.0
@export var ranged_attack_aura: float = 0.0
@export var enemy_aura_radius: float = 0.0
@export var enemy_aura_effects: Array[PBBuff] = []
@export var attack_speed_aura: float = 0.0
@export var attack_speed_aura_growth: float = 0.0
@export var move_speed_aura: float = 0.0
@export var followup_id: StringName = &""
@export var followup_enabled: bool = false
@export var variant_id: StringName = &""
@export var variant_enabled: bool = false
@export var variant_first: bool = false
@export var sacrifice_transfer: bool = false
@export var transfer_scale: float = 1.0
@export var transfer_buff: PBBuff = null
@export var on_target: Array[PBBuff] = []
@export var target_effect_area: bool = false

## 延迟锁定技能先给主目标的非伤害效果，落地伤害与 on_target 仍在延迟结束后结算。
@export var on_start_target: Array[PBBuff] = []
## 地面连击建立时仅向当时圈内目标施加；后进入者不补挂。
@export var on_start_area: Array[PBBuff] = []

## **下达那一刻**挂给施法者自己的效果，不问 [member target] 是什么。
## 在下达时挂：施法延迟里人已经把技能交出去了，自增益等半秒才生效的话看起来像「按下去没反应」。
@export var on_self: Array[PBBuff] = []

## 伤害属性。**铁律 4：element 挂在伤害事件上，不挂在单位上** —— 本体土属性、技能火系的角色靠它。
@export var element: PBElement.Type = PBElement.Type.PHYSICAL

## 伤害类型由施法者攻击属性决定；和技能自身的七种克制属性独立。
## 决定这一发吃护甲还是忍术抗性、掷哪一种暴击、吃哪一种增伤，见 [PBDamageKind]。
@export var kind: PBDamageKind.Type = PBDamageKind.Type.NINJUTSU

## 属性系数。默认体术取总攻击力、忍术取智力；特殊技能由 damage_stat 指定。
## 单次伤害不含攻速。历史字段名保留，避免资源和羁绊补丁失联。
##
## **伤害必须是派生量**（走 [method PBCombatRules.skill_damage]）：写成绝对值的话，属性克制与队伍倍率
## 对技能一律不生效，而且第 1 波很强、第 50 波等于 0（敌人血量按波次指数长）—— 全部不报错。
@export var power_mult: float = 0.0

## 按技能等级线性成长的固定部分：base + growth × (等级 - 1)。
@export var damage_base: float = 0.0
@export var damage_growth: float = 0.0

## 空表示按伤害类型取默认属性；例外可用 attack / intellect / agility / strength / max_hp。
@export var damage_stat: StringName = &""
## 原脚本读取整数属性的技能先取整，再乘系数；不改变属性面板本身。
@export var damage_stat_floor: bool = false

## 部分技能在属性项之外再附加自身最大生命的一定比例。
@export var damage_hp: float = 0.0

## 地面范围伤害：目标最大生命附加、中心倍率与原始公式上限。
## 当前限定固定等级基数，比例换算沿用已经折算的克制、增伤与本次暴击。
@export var target_hp: float = 0.0
@export var target_current_hp: float = 0.0
@export var target_nonhero_only: bool = false
@export var center_scale: float = 1.0
## 外圈单独衰减；0 表示整圈同伤。内圈边界包含在全额伤害内。
@export var full_damage_radius: float = 0.0
@export var outer_damage_scale: float = 1.0
@export var damage_cap: float = 0.0

## 每波首次施放的额外总攻击力系数；当前用于单段非弹道直伤。
@export var first_cast_attack: float = 0.0

## 阵亡技能在施放前向致命来源位置移动的 tick 数；0 保持即时触发。
@export var death_move_ticks: int = 0

## 一发打多少。属性克制、科技、羁绊、装备**全部已经乘进来了**，
## 和 [member PBAttacker.dps] 一样，战斗层只认这个数。
##
## **`.tres` 里不许写它**（[method PBSkillLoader.check] 拦着）：它在建人那一刻
## 由 [member power_mult] 算出来并覆盖，写了也不生效 ——
## 而「配了不生效」比「配不了」难查得多。要配的是上面那个倍率。
@export var damage: float = 0.0

## 杀伤半径。**以落点为圆心的一个真圆**（屏幕上画成椭圆，见 [PBLayout]）。
@export var radius: float = 0.0
## 非零时改为从施法位置发出的矩形直线，radius 为半宽，地面落点决定方向。
@export var line_length: float = 0.0

## 地面连击：首段在施法延迟结束时落地，其余按间隔逐段结算。
@export var hit_count: int = 1
## 固定地面技能的附带控制半径；0沿用伤害范围。
@export var control_radius: float = 0.0
## 受伤救援光环，只有羁绊补丁启用半径后生效。
@export var rescue_radius: float = 0.0
@export var on_rescue: Array[PBBuff] = []
## 非零时每轮跟随施法者当前位置，在 radius 内等距分档随机取半径。
## 每轮 volley_size 道同时结算；首轮等待一个间隔，源死亡不撤回。
@export var scatter_steps: int = 0
@export var volley_size: int = 1
@export var hit_interval_ticks: int = 0
@export var pulse_delay_ticks: int = 0
## 起手范围控制的重复时刻（相对释放），不造成额外伤害。
@export var area_refresh_ticks: PackedInt32Array = PackedInt32Array()
@export var hit_count_levels: PackedInt32Array = PackedInt32Array()
## 从内向外扩圈，每段只选一个尚未命中的目标；半径为最后一段的搜索半径。
@export var pulse_radius_step: float = 0.0
@export var radius_growth: float = 0.0
@export var travel_step: float = 0.0
@export var wave_count: int = 0
@export var wave_interval_ticks: int = 0
@export var fan_spread_degrees: float = 0.0
@export var fan_steps: int = 1
@export var pulse_damage_step: float = 0.0
## 扩圈命中远程敌人时，每个目标生成的幻影数；继承比例 / 时长共用召唤参数。
@export var phantom_count: int = 0
@export var phantom_element: PBElement.Type = PBElement.Type.PHYSICAL

## 0 = 每段覆盖原落点的 radius；大于 0 = 在 radius 内分散落点，每段用此杀伤半径。
@export var hit_radius: float = 0.0
## 非零时从施法位置朝敌方（+X）逐段蔓延；出手后独立于施法者移动和存亡。
@export var hit_step: float = 0.0

## 从施放时刻计时，在原落点追加一次纯伤害，不重复扣蓝、控制与自增益。
@export var echo_delay_ticks: int = 0
@export var echo_radius_scale: float = 1.0

## 冷却多少 tick。§02 给的是 15–30 秒。
@export var cooldown_ticks: int = 0

## 下达到落地之间隔多少 tick。见本类顶部「地面技能必须有施法延迟」。
## 地面预判、自身周围连击及带起手效果的锁定技能可配置；其余必须为 0。
@export var delay_ticks: int = 0

## 这一发要**飞过去**的话，飞完全场要几秒。**0 = 瞬发。**
##
## 锁定档分两种（玩家定的）：医疗忍术是瞬发，火球术是子弹技能 —— 下达 → 发一发 [PBProjectile]
## → **飞到才结算** [member damage] 与 [member on_hit]。目标半路死了那一发就消失。
##
## **不复用 [member delay_ticks]**：那个是地面档的预判窗口（落点定死，时间与距离无关），
## 子弹追着会动的目标，飞多久由距离决定。[method PBSkillRules.validate] 两头都拦。
## 口径是「飞完全场几秒」不是「每 tick 飞多远」—— 后者改一次战场尺寸就要重配全部技能。
@export var shot_cross_seconds: float = 0.0

## 一发最多命中几个。范围技能 0 表示不限；零半径锁定技能 0 等价于基础单体 1 人。
## 单体与范围的区别是 §04 波型价值分化的支点（潮水波偏 AOE、精英波偏单体）。
@export var max_targets: int = 0
## 锁定多目标技能在主目标周围搜索的半径，独立于杀伤半径；主目标以外按距离选择。
@export var extra_target_radius: float = 0.0
## 追加目标以出手位置为圆心；否则以主目标为圆心。
@export var extra_target_from_caster: bool = false

## 落地时是否把范围内的敌人拖到落点（§02 的「拉拽」）。
## 七尾的大招和羁绊功能档走的是这同一个字段，不是平行的第二份实现。
@export var gather: bool = false

# ── 位置与状态操纵 ──────────────────────────────────────────────
#
# 机制型尾兽（七尾聚拢、六尾重置 CD、一尾减速、三尾击退、二尾增伤）的全部落点，
# 同时也是 §09 功能档（聚拢 / 吸附 / 定身 / 减速）的词汇。写在 [PBSkill] 而不是单开
# 「尾兽大招」类：结算规则逐条相同，分开的话落点判定迟早对不上。

## 落地时把范围内的敌人往出生点方向推多远。与 [member PBEnemy.distance] 同轴。
##
## 和 [member gather] 是相反方向的两种位置操纵。两者都不产生伤害，
## 价值全在「敌人晚到基地多久」上 —— 那正是塔防里位置操纵的定价方式。
@export var knockback: float = 0.0

## 锁定直伤落地前闪到目标后侧，距离取施法者近战停步距离；不移动尸体或失效目标。
@export var blink_to_target: bool = false

## 落地后敌人的速度倍率（0 = 定身，0.5 = 减速一半，1.0 = 不减速）。
##
## **减速是全场的，不按半径圈人。** 一尾的「全屏减速力场」和五尾的
## 「地形阻挡」在 §11 里都写着「全屏 / 延缓推进」，圈人反而不合规格；
## 而 §09 的功能档要按半径减速时，加一个「减速也吃半径」的开关即可，
## 那时才有依据决定它该不该吃。
@export var slow_scale: float = 1.0

## 减速持续多少 tick。
@export var slow_ticks: int = 0

## 落地后全队普攻伤害的倍率（1.15 = 短时全队 +15%）。走 [PBBuffBag]（[method PBBuffRules.team_damage]）。
@export var team_damage_scale: float = 1.0

## 全队增伤持续多少 tick。
@export var buff_ticks: int = 0

## 落地时把**其他**技能的冷却清零（六尾）。
##
## 清的是别人不是自己 —— 自己也清的话它会在同一 tick 无限自我重置。
## 这一条的强度与队伍里大招的总量成正比，而不是和它自己的数值成正比，
## §11 说的「机制型尾兽」指的就是这种依赖关系。
@export var reset_cooldowns: bool = false

## 放一发要花多少蓝（§03A）。**0 表示不耗蓝。**
##
## 冷却和蓝两道门槛都要：冷却管「多久来一次」，蓝管「连着放几发」。只有冷却时智力没用，
## 只有蓝时尾兽的跨波冷却和六尾的「重置全体 CD」一起废掉。副作用正好是对的：重置冷却不等于免费连放。
##
## **尾兽大招恒为 0**：它的稀缺性靠 75 秒的跨波冷却，再加一道蓝等于收两次费。
@export var mp_cost: float = 0.0
## 固定地面区域的独立减益光环；伤害由连击排期负责。
@export var zone_seconds: float = 0.0
@export var zone_radius: float = 0.0
@export var zone_ring_radius: float = 0.0
@export var zone_ring_count: int = 0
@export var zone_outer_radius: float = 0.0
@export var zone_outer_count: int = 0
@export var zone_effects: Array[PBBuff] = []
@export var zone_ring_effects: Array[PBBuff] = []
## 显式逐级耗蓝；为空沿用固定耗蓝，超出表尾沿用末级。
@export var mp_cost_levels: PackedFloat32Array = PackedFloat32Array()
## 落地后延迟返蓝并设置剩余冷却；三项由同一羁绊补丁同时开启。
@export var rebate_delay_ticks: int = 0
@export var rebate_mana_scale: float = 0.0
@export var rebate_cooldown_ticks: int = 0

## 开波时**还欠多少 tick 的冷却**。[method PBSkillCast.reset] 把 [member PBSkillCast.ready_at] 设成它。
##
## 角色大招 20 秒、单波约 16 秒，每波清零和不清零结果一样。**尾兽不是**：75 秒 ≈ 每 2 波一次，
## §11 要玩家选择「在哪一波交底牌」，每波清零的话它每波都放得出，那个决策就不存在。
@export var carry_over_ticks: int = 0

# ── 召唤物 ──────────────────────────────────────────────────────

## 这一发召几个出来。0 = 不是召唤技能。
##
## **召唤物是真会挨打会死的单位**（玩家定的）—— 原版那句
## 「影分身承受 600% 的伤害」就是说它们在场上、敌人会打它们。
## 降格成「本体增伤 N 秒」零结构代价，但那正是 §09 明令禁止的
## 「只是更大的百分比」。
@export var summon_count: int = 0

## 召唤物的输出是本体的几成。
@export var summon_power: float = 0.0

## 每升一级增加的本体攻击继承比例，羁绊与基础比例一起缩放。
@export var summon_power_growth: float = 0.0

## 召唤物优先追击本次施法锁定的敌人；该目标失效后恢复普通索敌。
@export var summon_focus: bool = false

## 召唤物的血是本体的几成。
##
## **原版写的是「承受 600% 伤害」，这里换算成一六的血。**
## 两者对结果等价，而后者不要新机制 —— 另加一个「受伤倍率」字段的话，
## 它会和 [constant PBBuffRules.DAMAGE_TAKEN] 成为同一件事的两把尺子。
@export var summon_hp_share: float = 0.0

## 召唤物在场上待多久。0 = 不散（今天没有这种）。
@export var summon_seconds: float = 0.0

## 召唤物的普攻吸血（吸血虫「将 20% 的伤害值转换为生命给自己」）。召出来那一刻装上，见 [member PBAttacker.lifesteal]。
@export var summon_lifesteal: float = 0.0

## 这一份**不进指令卡**，在施法者倒下那一刻以尸体为落点放出去（〔地之咒印〕「在死亡时释放【早蕨之舞】」）。
##
## 只由羁绊的技能补丁打开（[constant PBSkillPatchRules.ON_DEATH]），不写在技能表里：
## 同一个技能「谁在什么羁绊下死了会放」是羁绊的事，表里写死的话没有羁绊也会放。
## 放的路径和手动施法同一条（[method PBBattleSim._land_skill]），落点档照 [member target] 走。
var fires_on_death: bool = false

## 运行时变体独立表现键；按钮 id 仍保留原技能，避免换招影响指令。
var variant_art_id: StringName = &""

## 这一份放出去的回血乘几（施法者的 [member PBAttacker.heal_power]）。**建人时写在复制品上**，表里那一份恒为 1。
## 读点在 [method PBSkillRules._apply_all]。
var heal_scale: float = 1.0
var followup: PBSkill = null
var recast: PBSkill = null
var first_cast_damage: float = 0.0
## 建人时按技能属性克制与队伍倍率折算；临时基础攻击变化通过它进入攻击公式。
var attack_formula_scale: float = 0.0


## 当前技能等级对应的本体攻击继承比例。
func summon_power_at(level: int) -> float:
	return maxf(summon_power + summon_power_growth * float(maxi(level - 1, 0)), 0.0)


func hits_at(level: int) -> int:
	if hit_count_levels.is_empty():
		return hit_count
	return hit_count_levels[clampi(level - 1, 0, hit_count_levels.size() - 1)]


## 复制一份**设定**。[PBSkillCast] 不跟着复制 —— 复制品是「这一波都还没放过的它」。
##
## 要复制不共享：[method PBAttacker.clone] 造探测用的攻击者时要能独立改伤害
## （[method PBValuation._leaks_at]），共享的话探测会污染正在打的那一份。
##
## **逐字段反射，不手抄**（`PROPERTY_USAGE_SCRIPT_VARIABLE`，同 [method PBSimConfig.clone]）：
## 加一个字段忘了抄一行不报错。
##
## [member on_hit] / [member on_self] 里的 [PBBuff] 共享引用（不可变的定义），**但数组必须是新的** ——
## 羁绊的技能补丁会往 `on_hit` 里追加效果，追加到共享数组上等于改写 `.tres` 那一份。
func clone() -> PBSkill:
	var out := PBSkill.new()
	for prop: Dictionary in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = get(prop["name"])
			if value is PBSkill:
				value = value.clone()
			out.set(
				prop["name"],
				(
					value.duplicate()
					if value is Array or value is PackedFloat32Array or value is PackedInt32Array
					else value
				)
			)
	return out
