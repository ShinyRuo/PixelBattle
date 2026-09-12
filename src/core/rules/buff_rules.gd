class_name PBBuffRules
extends RefCounted
## 效果的词汇表、合并规则与数值解析（M7-a）。全部 static，无状态，零引擎依赖。
##
## ## 这一层是「一个 buff 到底改了什么」的唯一真相
##
## 和 [PBBondFunctionRules] 同一套写法：一份 const 键表，加载时校验，
## **拼错的键当场报错**。静默什么都不发生的话，从现象反推不出来 ——
## 玩家看到的只是「这个技能好像没用」。
##
## ## [constant ALL] 里的键 = **已经接上读点的键**
##
## 这条比「先把词汇表铺满，读点以后再接」重要得多。一个**拼错**的键有报错拦着，
## 而一个**拼对了却没人读**的键什么都不会说 —— 它比拼错更难查，
## 因为数据、界面、日志全都正常，只有伤害数字不对。
##
## 所以键是跟着读点一起进来的：M7-a 只有三个（[constant DAMAGE_SCALE] /
## [constant HEAL] / [constant MANA]），M7-d 连同 [PBEnemy] 的效果袋
## 一起加了敌方那三个（[constant HURT] / [constant ENEMY_SPEED_SCALE] /
## [constant HARM]）。护盾那几个还没进来。
##
## ## 敌方那张词汇表**不是己方那张照搬**
##
## [PBEnemy] 压根没有 `defence` 字段（[method PBEnemy.take_damage] 直接扣血），
## 也没有蓝、没有射程档 —— 照搬过去的键会是「拼对了却没人读」的那一种，
## 而那正是上面这条规矩要挡的东西。
##
## ## 两类键，合并方式不同
##
## **率型**（`*_scale`、[constant HURT]）无量纲，多份**连乘**，空的时候是 1.0；
## **量型**（血、蓝、盾、[constant HARM]）有量纲，多份**累加**，空的时候是 0.0。
## 这条区分同时决定了「数值怎么随等级长」，见 [method resolve]。
##
## ## 每 tick 推进也在这一层
##
## [method advance_ally] / [method advance_enemy] 是「一个单位身上挂着的东西
## 过了一个 tick」——周期载荷该触发的触发、过期的槽位腾出来。
## 它和 [PBSkillRules]（一发技能落地时发生什么）、[PBMoveRules]（该往哪儿走）
## 一样是纯规则：[PBBattleSim] 只留「什么时候调它」。

## 出手伤害倍率。读点在 [method PBAttacker.strike_for]。
##
## M3-d 的「全队短时增伤」（§11 二尾、§09 定身档的控制期增伤）
## **M7-a 起就是这个键** —— 在那之前它是 [PBBattleSim] 上的一对
## `_buff_scale` / `_buff_until`，一份、全场、后来者覆盖前者。
const DAMAGE_SCALE: StringName = &"damage_scale"

## 立刻回血。读点在 [method PBAttacker.heal]。
const HEAL: StringName = &"heal"

## 立刻回蓝。读点在 [method PBAttacker.restore_mana]。
const MANA: StringName = &"mana"

## 易伤：这个敌人挨的每一下乘多少（M7-d）。
##
## **读点在 [method PBEnemy.take_damage] 里面，不在调用方。**
## 调用方有六处（单体、连续输出、范围、子弹命中、技能落地、周期载荷），
## 而漏乘一处的表现是「某一种攻击方式吃不到易伤」——
## 要盯着日志看很久才发现。放进类里就只有一个读点，
## 和 [method PBAttacker.strike_for] 顶上那条是同一条理由。
const HURT: StringName = &"hurt"

## 个体减速：这个敌人自己走多快（M7-d）。0 = 定身。
##
## **和 [PBBattleSim] 那份「全场减速」是两个东西，两者相乘。**
## 那一份是**场**的属性（新出场的敌人也吃得到），这一份挂在单位上。
## 读点在 [method PBEnemy.advance] / [method PBEnemy.march_to] 里面，
## 理由同 [constant HURT]。
const ENEMY_SPEED_SCALE: StringName = &"enemy_speed_scale"

## 晕眩：这个敌人这一 tick 不许出手（M12-c2）。大于 0 就是定住了。
##
## **它是 [constant ENEMY_SPEED_SCALE] 差的那一半。** 在它之前，
## 六份「禁锢」型效果（心转束缚、影子禁锢、追牙束缚、水龙禁锢、
## 森罗万象缠绕、月读囚）全都只写 `enemy_speed_scale=0`，
## 而 `data/buffs.tsv` 里就记着那条降级：
## 「停的是走位，敌人站在原地照样出手」—— 原版那几个写的是
## 「无法移动**攻击和施法**」。
##
## **读点在 [method PBEnemy.ready_to_fire] 里面，不在调用方** ——
## 近战与远程在那一句之后才分岔，各判一次的表现是
## 「定住了还会放箭」。同 [constant HURT] 顶上那条。
const STUN: StringName = &"stun"

## 致盲：这个敌人出手打得中的概率（M12-c2）。0.5 = 一半打空。
##
## **写命中率不写丢失率**，因为它要跟
## [constant ENEMY_SPEED_SCALE] 一样当率型用：多份**连乘**、空的时候是 1.0。
## 写成丢失率的话两份 50% 相加就是 100%，而那不是人会预期的叠加方式。
##
## 读点在 [method misses] 里面，**排在近战/远程分岔之前** ——
## 分岔之后各判一次的表现是「只有近战会打空」。
const ENEMY_HIT_SCALE: StringName = &"enemy_hit_scale"

## 掉血：中毒、灼烧那一类（M7-d）。读点在 [method advance_enemy] 与
## [method PBSkillRules.apply_one_enemy]，两条都最终走
## [method PBEnemy.take_damage] —— 它才是记账（击杀数）的那道门。
##
## 己方那一侧**故意没有对应的键**：忍者掉血要走
## [method PBAttacker.take_damage] 那一整套（阵亡记账、日志、`allies_lost`），
## 而 v1 没有任何一个技能要给自己人上 DoT。
const HARM: StringName = &"harm"

## 暴击率**临时**加多少（M10-c）。读点在 [method PBCritRules.chance_of]。
##
## ## 为什么它是量型（累加、空 = 0.0）而不是率型
##
## 「+15% 暴击」和「+10% 暴击」摞在一起要得到 +25%，不是 ×1.15×1.10。
## 概率本来就是加法量，把它塞进率型的话两份 +15% 会算成 +32%，
## **而它不报错** —— 只表现为「凑得越多暴得越离谱」。
##
## ## 常驻的那一份不在这里
##
## 羁绊的暴击光环整波常驻、没有施法者、也不该占袋子的槽位，
## 它落在 [member PBAttacker.crit_chance] 上（同「装备、羁绊已经乘死」那一档）。
## 这个键是**临时**那一份：命中后短时提暴击、技能给的暴击窗口。
## 两者在 [method PBCritRules.chance_of] 相加 —— 一个读点。
const CRIT_CHANCE: StringName = &"crit_chance"

## 暴击时**额外**多打几成，临时那一份（M10-c）。读点在 [method PBCritRules.bonus_of]。
##
## **存的是「额外」不是「倍数」**，所以中性值 0.0 就是「不额外多打」，
## 和量型那条规矩天然对得上。存倍数的话中性值得是 1.0，
## 而那要么把它挪进 [constant SCALES] 变成连乘（两份 +50% 算成 +125%），
## 要么给量型开一个例外 —— 两条都比换一个语义贵。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 护盾：还能替他挡下多少伤害（M11-b）。读点在 [method PBAttacker.take_damage]。
##
## ## 它是**会被消耗**的那一份，所以走 [method PBBuffBag.absorb]
##
## 别的键都是「查一下现在是多少」，护盾是「花掉一点就少一点」——
## 那笔账只能记在挂着的那一份上（[member PBBuffState.mods]），
## 而扣减必须只有一个入口，否则「同一发伤害被两处各扣一次护盾」不报错。
##
## **量型（累加）**：两份护盾摞起来是两份都能挡。而它有时限 ——
## 「一段时间内吸收 N 点伤害」这两个维度正好是一份 buff 的形状，
## 挂在 [PBAttacker] 上一个裸字段的话，到期该减多少没有地方记。
const SHIELD: StringName = &"shield"

## 挨打的倍率：这个人受到的每一下乘多少（M11-b）。**0 = 无敌。**
##
## 读点在 [method PBAttacker.take_damage] **里面**，不在调用方 ——
## 己方挨打有两条路（敌人近战、敌人的子弹），漏乘一处的表现是
## 「被子弹打就吃不到减伤」，而它不报错。同 [constant HURT] 顶上那条。
##
## **和敌方那边的 [constant HURT] 是相反方向的同一件事**，但故意是两个键：
## 一个挂在忍者身上（我扛得住多少），一个挂在怪身上（他挨得更疼），
## 合成一个键的话「给敌人上易伤」和「给自己上减伤」会共用一份数值，
## 而那两件事的合理取值范围完全不同。
const DAMAGE_TAKEN: StringName = &"damage_taken"

## 全部**已经接上读点**的键。见本类顶部。
const ALL: Array[StringName] = [
	DAMAGE_SCALE,
	HEAL,
	MANA,
	HURT,
	ENEMY_SPEED_SCALE,
	STUN,
	ENEMY_HIT_SCALE,
	HARM,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	SHIELD,
	DAMAGE_TAKEN,
]

## 多份**连乘**的那几个（率型）。其余一律**累加**（量型）。
const SCALES: Array[StringName] = [
	DAMAGE_SCALE, HURT, ENEMY_SPEED_SCALE, ENEMY_HIT_SCALE, DAMAGE_TAKEN
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


## 这一下打空了吗（[constant ENEMY_HIT_SCALE]，M12-c2）。
##
## **排在近战/远程分岔之前调** —— 分岔之后各判一次的表现是
## 「只有近战会打空」，而它不报错。同 [constant HURT] 顶上那条。
##
## **没被致盲时一次骰子都不掷**（命中率恰好是 1.0）——
## 同 [method PBCritRules.strike] 顶上那条：掷了就算打中也已经拨动了那条流。
##
## [param rng] 为 null 时（批量扫描、探测）恒不打空且不掷骰。
static func misses(enemy: PBEnemy, at_tick: int, rng: RandomNumberGenerator) -> bool:
	if enemy == null or rng == null:
		return false
	var hit: float = enemy.buffs.amount(ENEMY_HIT_SCALE, at_tick)
	if hit >= 1.0:
		return false
	return rng.randf() >= hit


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
## **它对的是另一条曲线。** 技能的直接伤害走 `power_mult × 战力`，因为它要和
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
	if buff.kind != PBBuff.Kind.INSTANT and buff.duration_seconds <= 0.0:
		return "持续型 buff 没有时长"
	if buff.kind == PBBuff.Kind.PERIODIC and buff.period_seconds <= 0.0:
		return "周期型 buff 没有周期"
	return ""


## 秒换成 tick。**至少 1** —— 0 tick 的窗口等于没有这个 buff，
## 而写数据的人写 0.01 秒时想要的是「很短」，不是「没有」。
static func to_ticks(seconds: float, cfg: PBSimConfig) -> int:
	return maxi(int(round(seconds * float(cfg.tick_rate))), 1)


## 一个己方单位身上的效果过了一个 tick：周期载荷该触发的触发，过期的腾出来。
##
## ## 清扫和触发合在一个循环里是安全的
##
## 过期的判据是 [method PBBuffState.is_live] **每次查询时比 tick**，
## [method PBBuffBag.sweep] 只是回收槽位 —— 漏跑、早跑、晚跑都不可能
## 改变任何结算结果（见 [PBBuffBag] 顶部）。所以它不必单独占一趟遍历。
##
## ## 这一支只做回复，不做伤害
##
## 回血回蓝改的是自己的量，结算完就完了；而忍者**掉血**要走
## [method PBAttacker.take_damage] 那一整套（阵亡记账、日志、`allies_lost`），
## 而 v1 没有任何一个技能要给自己人上 DoT（见 [constant HARM]）。
static func advance_ally(unit: PBAttacker, at_tick: int) -> void:
	for state: PBBuffState in unit.buffs.states():
		if not state.is_due(at_tick):
			continue
		state.on_fired(at_tick)
		unit.heal(float(state.mods.get(HEAL, 0.0)))
		unit.restore_mana(float(state.mods.get(MANA, 0.0)))
	unit.buffs.sweep(at_tick)


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
static func advance_enemy(enemy: PBEnemy, at_tick: int) -> float:
	var harm: float = 0.0
	for state: PBBuffState in enemy.buffs.states():
		if not state.is_due(at_tick):
			continue
		state.on_fired(at_tick)
		harm += float(state.mods.get(HARM, 0.0))
	enemy.buffs.sweep(at_tick)
	return harm
