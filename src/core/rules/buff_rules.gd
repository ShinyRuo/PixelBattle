class_name PBBuffRules
extends RefCounted
## 效果的词汇表、合并规则与数值解析。全部 static，无状态，零引擎依赖。
##
## 「一个 buff 到底改了什么」的唯一真相。**拼错的键加载时当场报错**。
##
## ## [constant ALL] 里的键 = 已经接上读点的键
##
## 拼错的键有报错拦着，**拼对了却没人读**的键什么都不会说 —— 数据、界面、日志
## 全都正常，只有伤害数字不对。所以键跟着读点一起进来，不预留。
##
## 敌方那张词汇表**不是己方那张照搬**：[PBEnemy] 没有 `defence`、没有蓝、没有射程档，
## 照搬过去的键就是「拼对了却没人读」。
##
## ## 两类键，合并方式不同
##
## **率型**（`*_scale`、[constant HURT]）无量纲，多份**连乘**，空的时候是 1.0；
## **量型**（血、蓝、盾、[constant HARM]）有量纲，多份**累加**，空的时候是 0.0。
## 这条区分同时决定了数值怎么随等级长，见 [method resolve]。
##
## 每 tick 推进（[method advance_ally] / [method advance_enemy]）也在这一层，
## [PBBattleSim] 只管什么时候调。

## 出手伤害倍率。读点在 [method PBAttacker.strike_for]。
## 「全队短时增伤」就是给每个人各挂一份这个键。
const DAMAGE_SCALE: StringName = &"damage_scale"
const BASE_ATTACK_BONUS: StringName = &"base_attack_bonus"
const STRENGTH: StringName = &"strength"
const AGILITY: StringName = &"agility"
const INTELLECT: StringName = &"intellect"
const STRENGTH_BONUS: StringName = &"strength_bonus"
const ALL_STATS_BONUS: StringName = &"all_stats_bonus"
const REACH_BONUS: StringName = &"reach_bonus"

## 立刻回血。读点在 [method PBAttacker.heal]。
const HEAL: StringName = &"heal"

## 立刻回蓝。读点在 [method PBAttacker.restore_mana]。
const MANA: StringName = &"mana"

## 易伤：这个敌人挨的每一下乘多少。
##
## **读点在 [method PBEnemy.take_damage] 里面，不在调用方** —— 调用方有六处，
## 漏乘一处的表现是「某一种攻击方式吃不到易伤」。
const HURT: StringName = &"hurt"

## 个体减速：这个敌人自己走多快。0 = 定身。
##
## **和 [PBBattleSim] 的全场减速是两个东西，两者相乘**：那一份是场的属性
## （新出场的敌人也吃得到），这一份挂在单位上。读点在
## [method PBEnemy.advance] / [method PBEnemy.march_to] 里面，理由同 [constant HURT]。
const ENEMY_SPEED_SCALE: StringName = &"enemy_speed_scale"

## 晕眩：这个敌人这一 tick 不许出手。大于 0 就是定住了。
##
## 「禁锢」型效果要同时配它和 [constant ENEMY_SPEED_SCALE] —— 后者只停走位，
## 敌人站在原地照样出手。
##
## **读点在 [method PBEnemy.ready_to_fire] 里面**：近战与远程在那一句之后才分岔，
## 各判一次的表现是「定住了还会放箭」。
const STUN: StringName = &"stun"
const DOMINATED: StringName = &"dominated"

## 致盲：这个敌人出手打得中的概率。0.5 = 一半打空。
##
## **写命中率不写丢失率**：要当率型用（多份连乘、空的时候 1.0）。
## 写成丢失率的话两份 50% 相加就是 100% 全空。
##
## 读点在 [method misses] 里，**排在近战/远程分岔之前**。
const ENEMY_HIT_SCALE: StringName = &"enemy_hit_scale"

## 掉血：中毒、灼烧那一类。读点在 [method advance_enemy] 与
## [method PBSkillRules.apply_one_enemy]，都最终走 [method PBEnemy.take_damage]（记账的门）。
##
## 己方用的是 [constant DRAIN_MAX]，不是这一个：忍者掉血按最大生命的几成算（原版的写法），
## 而且要走 [method PBStrikeRules.wound_ally] 那一整套（阵亡记账、重生、`allies_lost`）。
const HARM: StringName = &"harm"

## 己方**每一跳**回复最大生命的几成（百豪之术「5 秒内恢复 50% 最大生命」）。读点在 [method advance_ally]。
##
## 和 [constant HEAL] 分开：那一个是点数、随施法者等级长；这一个跟着**挨治疗那个人**的血量走，
## 装备、羁绊把血抬高之后比例照样对。
const HEAL_MAX: StringName = &"heal_max"

## 己方**每一跳**损失最大生命的几成（地之咒印「每秒损失 2% 的生命值」）。
##
## [method advance_ally] 只算出该掉多少、**不当场扣**，扣血交给 [method PBStrikeRules.wound_ally]
## （同 [method advance_enemy] 返回伤害的理由：掉死了要记账，账在 [PBBattleSim] 手上）。
## 它**照样吃无敌和护盾**（走的是 [method PBAttacker.take_damage]），被
## [member PBAttacker.drain_cut] 按比例抵掉。
const DRAIN_MAX: StringName = &"drain_max"

## 防御临时加多少（尾兽外衣「提升 4-40 点防御」）。量型，和 [member PBAttacker.defence] 相加。
## 读点在 [method PBStrikeRules.hurt_ally] 算护甲那一句 —— 敌人伤害落到忍者身上只有那一处。
const DEFENCE: StringName = &"defence"

## 不死：大于 0 时这一下打不死他，血停在 1（死司凭血「受致命伤害时 N 秒内不会死亡」）。
## 读点在 [method PBAttacker.take_damage] **里面**，排在重生之前 —— 同闪避、同减伤，调用方不判。
const UNDYING: StringName = &"undying"

## 敌我**临时**普攻闪避率加多少。量型，与各自的基础闪避相加。
## 己方在 [method PBPassiveRules.dodges] 判，敌方在 [method PBEnemy.take_damage] 判。
const DODGE: StringName = &"dodge"

## 敌人的攻速倍率（妩媚「降低其 65% 的攻击速度」= 0.35）。率型，读点在 [method PBEnemy.on_fired]：
## 下一次出手的间隔除以它。**判在排间隔那一句，不在出手判定里** —— 同晕眩那条「冷却不偷跑」。
const ENEMY_ATTACK_SPEED_SCALE: StringName = &"enemy_attack_speed_scale"

## 敌人护甲**临时**加减几点（溶解爆酸「降低 3-30 点护甲」= −15）。量型，读点在 [method PBStrikeRules.armoured]。
## 本身那一份在 [member PBEnemy.armor]。
const ENEMY_DEFENCE: StringName = &"enemy_defence"

## 敌人忍术抗性**临时**加减几成（负数 = 降魔抗）。量型，读点在 [method PBStrikeRules.mitigated]。
## 本身那一份在 [member PBEnemy.ninjutsu_resist]。
const ENEMY_RESIST: StringName = &"enemy_resist"

## 忍者临时忍术抗性，按成数相加。
const NINJUTSU_RESIST: StringName = &"ninjutsu_resist"

## 临时反弹比例，与常驻反弹相加；读点在 hurt_ally，按命中时的窗口取值。
const REFLECT: StringName = &"reflect"

## 忍术免疫独立于抗性，不能被忍术穿透抵消。读点在 hurt_ally。
const NINJUTSU_IMMUNE: StringName = &"ninjutsu_immune"

## 原地持续施放期间禁止移动、普攻与新技能；不代表免疫敌方控制。
const CHANNEL: StringName = &"channel"

## 沉默仅拦敌方主动施法；普通攻击不按伤害类型判沉默。
const SILENCE: StringName = &"silence"
## 只禁止普通攻击，主动施法由 silence / stun 独立控制。
const DISARM: StringName = &"disarm"
## 仙属性伤害在通用易伤之外再乘的倍率；伤害类型不参与此判定。
const SAGE_HURT_SCALE: StringName = &"sage_hurt_scale"
## 击飞阶段的视觉标记；合法配置必须同时含眩晕与定身，地面位置不变。
const AIRBORNE: StringName = &"airborne"

## 暴击率**临时**加多少。己方读点在 [method PBCritRules.chance_of]，敌方在 enemy_strike。
##
## **量型不是率型**：概率是加法量，+15% 和 +10% 摞起来是 +25%；
## 塞进率型的话两份 +15% 会算成 +32%，而它不报错。
##
## 常驻那一份（羁绊光环）在 [member PBAttacker.crit_chance] 上，两者在
## [method PBCritRules.chance_of] 相加。
const CRIT_CHANCE: StringName = &"crit_chance"

## 暴击时**额外**多打几成，临时那一份。读点在 [method PBCritRules.bonus_of]。
## **存「额外」不存「倍数」**，中性值 0.0，和量型规矩天然对得上。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 护盾：还能替他挡下多少伤害。敌我均在自己的 take_damage 中、倍率折算后扣盾。
##
## 它是**会被消耗**的那一份，走 [method PBBuffBag.absorb]：账记在挂着的那一份上
## （[member PBBuffState.mods]），扣减只有一个入口，否则同一发伤害会被两处各扣一次。
## **量型**，而且有时限 —— 「一段时间内吸收 N 点」正好是一份 buff 的形状。
const SHIELD: StringName = &"shield"
const NINJUTSU_SHIELD: StringName = &"ninjutsu_shield"
const NINJUTSU_SHIELD_MAX: StringName = &"ninjutsu_shield_max"

## 挨打的倍率：这个人受到的每一下乘多少。**0 = 无敌。**
##
## 敌我均在自己的 take_damage **里面**乘，先于护盾；敌人的 damage_to_kill 同步折算。
##
## 敌人身上与易伤 [constant HURT] 相乘；两个键保留各自身份，净倍率为 0 时无敌。
const DAMAGE_TAKEN: StringName = &"damage_taken"

## 全部**已经接上读点**的键。见本类顶部。
const ALL: Array[StringName] = [
	DAMAGE_SCALE,
	BASE_ATTACK_BONUS,
	STRENGTH,
	AGILITY,
	INTELLECT,
	STRENGTH_BONUS,
	ALL_STATS_BONUS,
	REACH_BONUS,
	HEAL,
	MANA,
	HURT,
	ENEMY_SPEED_SCALE,
	STUN,
	DOMINATED,
	ENEMY_HIT_SCALE,
	HARM,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	SHIELD,
	NINJUTSU_SHIELD,
	NINJUTSU_SHIELD_MAX,
	DAMAGE_TAKEN,
	HEAL_MAX,
	DRAIN_MAX,
	DEFENCE,
	UNDYING,
	DODGE,
	ENEMY_ATTACK_SPEED_SCALE,
	ENEMY_DEFENCE,
	ENEMY_RESIST,
	NINJUTSU_RESIST,
	REFLECT,
	NINJUTSU_IMMUNE,
	CHANNEL,
	SILENCE,
	DISARM,
	SAGE_HURT_SCALE,
	AIRBORNE,
]

## 多份**连乘**的那几个（率型）。其余一律**累加**（量型）。
const SCALES: Array[StringName] = [
	DAMAGE_SCALE,
	HURT,
	ENEMY_SPEED_SCALE,
	ENEMY_HIT_SCALE,
	DAMAGE_TAKEN,
	ENEMY_ATTACK_SPEED_SCALE,
	SAGE_HURT_SCALE
]

## 「全队短时增伤」那一份的定义。见 [method team_damage]。
static var _team_damage: PBBuff = null


## 「全队短时增伤」的效果定义（§11 二尾、§09 定身档的控制期增伤）。
##
## ## 为什么它在代码里而不在 `data/buffs/`
##
## 它的窗口和倍率来自**大招**（[member PBSkill.buff_ticks] /
## [member PBSkill.team_damage_scale]），而那两个数一个来自尾兽表、
## 一个来自 [constant PBBondFunctionRules.ROOT_DAMAGE_SCALE]。
## 再抄一份进 `.tres` 就是第二处真相，而 [member PBCharacter.reach] 顶上
## 那条已经讲过这件事：**全场共用的那一份走配置，逐角色独有的走 `data/`。**
##
## 所以这份定义只提供**身份**（id、名字、增益/减益），数值每次施放另给。
static func team_damage() -> PBBuff:
	if _team_damage == null:
		_team_damage = PBBuff.new()
		_team_damage.id = &"team_damage"
		_team_damage.name_key = "buff.team_damage"
		_team_damage.icon_key = "buff.team_damage"
		_team_damage.kind = PBBuff.Kind.DURATION
		_team_damage.friendly = true
	return _team_damage


## 这一下打空了吗（[constant ENEMY_HIT_SCALE]）。
##
## **排在近战/远程分岔之前调**。没被致盲时（命中率恰好 1.0）一次骰子都不掷。
## [param rng] 为 null 时（批量扫描、探测）恒不打空且不掷骰。
static func misses(enemy: PBEnemy, at_tick: int, rng: RandomNumberGenerator) -> bool:
	if enemy == null or rng == null:
		return false
	var hit: float = enemy.buffs.amount(ENEMY_HIT_SCALE, at_tick)
	if hit >= 1.0:
		return false
	return rng.randf() >= hit


## 把一份已经按等级算好的效果里的**回血量**乘上 [param scale]（〔百豪之印〕「医疗量提升 50%」）。
## 返回新的一份，不改传进来的那份（它可能是挂在别人身上那一份的 `mods`）。
##
## 只乘 [constant HEAL] 与 [constant HEAL_MAX]：护盾、回蓝不是「治疗量」。
## **放大只在这里做**，技能那一路（[method PBSkillRules._apply_all]）和被动挂给自己那一路
## （[method PBStrikeRules._hang_self]）都调它 —— 各乘各的话迟早一个乘了一个没乘。
static func scale_heal(mods: Dictionary, scale: float) -> Dictionary:
	if is_equal_approx(scale, 1.0) or not (mods.has(HEAL) or mods.has(HEAL_MAX)):
		return mods
	var out: Dictionary = mods.duplicate()
	for key: StringName in [HEAL, HEAL_MAX]:
		if out.has(key):
			out[key] = float(out[key]) * scale
	return out


## 把一份效果里的**量型**数值乘上 [param scale]（〔沙忍三巨头〕「沙之守护增加数值提升 50%」）。
## **率型不乘**：攻速 ×0.35 乘 1.5 成了 ×0.525，是变弱不是变强。返回新的一份，不改传进来的那份。
static func scale_amounts(mods: Dictionary, scale: float) -> Dictionary:
	if is_equal_approx(scale, 1.0):
		return mods
	var out: Dictionary = mods.duplicate()
	for key: StringName in out:
		if not is_scale(key):
			out[key] = float(out[key]) * scale
	return out


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 这个键是率型（连乘）还是量型（累加）。
static func is_scale(key: StringName) -> bool:
	return SCALES.has(key)


## 一个键**没有任何一份**时该是多少 —— 率型 1.0、量型 0.0。
##
## 单独给一个函数而不是让调用方写 `1.0 if is_scale(key) else 0.0`，
## 是因为那句话一旦出现两处，加第四个率型键时就有一处会漏掉，
## **而漏掉的表现是「没有 buff 的时候伤害变成 0」** —— 那倒是会立刻发现；
## 反过来漏成 1.0 的量型键则是「凭空多回一点血」，那个不会。
static func neutral(key: StringName) -> float:
	return 1.0 if is_scale(key) else 0.0


## 把 [param add] 并进 [param into]。率型连乘、量型累加。
static func fold(key: StringName, into: float, add: float) -> float:
	return into * add if is_scale(key) else into + add


## 一份 buff 由 [param level] 级的人放出来，各键实际是多少（§2.4，决策 7）。
##
## ## 为什么按等级而不是按战力
##
## **固定载荷按等级成长。** 技能与效果可另配属性项，伤害要和
## 敌人血量可比；而治疗要和**己方**血量可比，
## 而己方血量 `hp_base + strength × hp_per_strength` 本来就是按等级线性长的
## （[method PBStatRules.of]）。按战力缩放的治疗会跟着稀有度、星级、装备一起飘 ——
## 那几样抬的是输出，不是血。
##
## 表的形状**照抄 [PBCharacter] 的二级属性**（`strength` / `strength_growth`），
## 不是新发明的：[member PBBuff.mods] 给 1 级时的值，
## [member PBBuff.mods_growth] 给每级加多少。
##
## 没有等级的施法者（尾兽、敌人）传 1 —— 成长项贡献 0，取到的就是基数，
## 不需要为它们分一条支路。
static func resolve(buff: PBBuff, level: int) -> Dictionary:
	var out: Dictionary = {}
	if buff == null:
		return out
	var steps: float = float(maxi(level, 1) - 1)
	for key: StringName in buff.mods:
		var grow: float = float(buff.mods_growth.get(key, 0.0))
		out[key] = float(buff.mods[key]) + grow * steps
		if buff.mods_levels.has(key):
			var values: PackedFloat32Array = buff.mods_levels[key]
			out[key] = values[clampi(level - 1, 0, values.size() - 1)]
	return out


## 这份 buff 的数据合不合法。返回空串表示没问题，否则是给人看的原因。
##
## 两条都是**静默生效**的错，所以必须在装表那一刻拦下来：
##
## - **键不认识** —— 拼错了不会报错，只是什么都不发生
## - **只写成长不写基数** —— `mods_growth` 里有、`mods` 里没有的键，
##   会静默生效成「1 级时是 0」，而写的人本意是「1 级时就有」
##
## 反过来（`mods` 里有、`mods_growth` 里没有）是**合法**的：
## 那就是「这一项不随等级长」，率型键通常都这样。
static func validate(buff: PBBuff) -> String:
	if buff == null:
		return "buff 是空的"
	if buff.id == &"":
		return "buff 没有 id"
	for key: StringName in buff.mods:
		if not is_known(key):
			return "不认识的效果键：%s" % key
	for key: StringName in buff.mods_growth:
		if not is_known(key):
			return "不认识的效果键：%s" % key
		if not buff.mods.has(key):
			return "%s 只写了成长没写基数 —— 那会静默变成「1 级时是 0」" % key
	if (
		buff.kind != PBBuff.Kind.INSTANT
		and buff.duration_seconds <= 0.0
		and not buff.until_wave_end
	):
		return "持续型 buff 没有时长"
	if buff.kind == PBBuff.Kind.PERIODIC and buff.period_seconds <= 0.0:
		return "周期型 buff 没有周期"
	return PBBuffFormula.validate(buff)


## 秒换成 tick。**至少 1** —— 0 tick 的窗口等于没有这个 buff，
## 而写数据的人写 0.01 秒时想要的是「很短」，不是「没有」。
static func to_ticks(seconds: float, cfg: PBSimConfig) -> int:
	return maxi(int(round(seconds * float(cfg.tick_rate))), 1)


## 一个己方单位身上的效果过了一个 tick：周期载荷该触发的触发，过期的腾出来。
##
## 清扫和触发合在一个循环里是安全的：过期是**每次查询时比 tick**
## （[method PBBuffState.is_live]），[method PBBuffBag.sweep] 只回收槽位，
## 漏跑、早跑、晚跑都不改变结算结果。
##
## 回复当场加上；**掉血只返回、不扣**（见 [constant DRAIN_MAX]），调用方交给
## [method PBStrikeRules.wound_ally]。返回的是抵扣（[member PBAttacker.drain_cut]）之后的数。
##
## 常驻回血（[member PBAttacker.regen_max]）也在这里，按 [param tick_rate] 每 tick 均摊 ——
## 放在效果之外另找一处推进的话，两处都要记得「死人不回」。
static func advance_ally(unit: PBAttacker, at_tick: int, tick_rate: int) -> float:
	if unit.regen_max > 0.0:
		unit.heal(unit.max_hp * unit.regen_max / float(maxi(tick_rate, 1)))
	var drain: float = 0.0
	for state: PBBuffState in unit.buffs.states():
		# **刚过期、还没清掉的那一份**：不死到期回血（[member PBAttacker.undying_end_heal]）判在这里 ——
		# 下面那句 `sweep` 同一 tick 就把它清了，所以一份只会触发一次。
		if state.buff != null and not state.is_live(at_tick):
			if state.mods.has(UNDYING) and unit.undying_end_heal > 0.0:
				unit.heal(unit.max_hp * unit.undying_end_heal)
			continue
		if not state.is_due(at_tick):
			continue
		state.on_fired(at_tick)
		unit.heal(float(state.mods.get(HEAL, 0.0)))
		unit.heal(unit.max_hp * float(state.mods.get(HEAL_MAX, 0.0)))
		unit.restore_mana(float(state.mods.get(MANA, 0.0)))
		drain += unit.max_hp * float(state.mods.get(DRAIN_MAX, 0.0))
	unit.buffs.sweep(at_tick)
	return drain * (1.0 - clampf(unit.drain_cut, 0.0, 1.0))


## 一个敌人身上的效果过了一个 tick。返回这一 tick 它**该掉多少血**。
##
## ## 为什么返回伤害而不是当场扣掉
##
## 扣血会打死人，而「打死了几个」是 [PBCombatOutcome] 的记账，
## 那份账在 [PBBattleSim] 手上。这里当场扣的话，杀敌数就有了第二个来源 ——
## 而漏记一处的表现是「波次结算的击杀数对不上」，不报错。
##
## 易伤（[constant HURT]）**不在这里乘**：它的读点是
## [method PBEnemy.take_damage]，调用方一律不乘（见 [constant HURT]）。
static func advance_enemy(enemy: PBEnemy, at_tick: int, cfg: PBSimConfig = null) -> float:
	var harm: float = 0.0
	for state: PBBuffState in enemy.buffs.states():
		if not state.is_due(at_tick):
			continue
		state.on_fired(at_tick)
		var raw: float = float(state.mods.get(HARM, 0.0))
		if cfg == null and state.harm_context != null and state.harm_context.has_element:
			raw *= enemy.element_hurt_scale(state.harm_context.element, at_tick)
		harm += (
			raw
			if cfg == null
			else PBHarmContext.damage(raw, state.harm_context, enemy, cfg, at_tick)
		)
		if state.buff.independent_stacks and state.next_tick_at > state.until_tick:
			state.until_tick = at_tick - 1
	enemy.buffs.sweep(at_tick)
	return harm
