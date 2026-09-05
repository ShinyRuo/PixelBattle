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
## [constant HEAL] / [constant MANA]），护盾、易伤、个体减速那几个
## 在 M7-c / M7-d 连同它们的读点一起加。
##
## ## 两类键，合并方式不同
##
## **率型**（`*_scale`）无量纲，多份**连乘**，空的时候是 1.0；
## **量型**（血、蓝、盾）有量纲，多份**累加**，空的时候是 0.0。
## 这条区分同时决定了「数值怎么随等级长」，见 [method resolve]。

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

## 全部**已经接上读点**的键。见本类顶部。
const ALL: Array[StringName] = [DAMAGE_SCALE, HEAL, MANA]

## 多份**连乘**的那几个（率型）。其余一律**累加**（量型）。
const SCALES: Array[StringName] = [DAMAGE_SCALE]

## 「全队短时增伤」那一份的定义。见 [method team_damage]。
static var _team_damage: PBBuff = null


## 「全队短时增伤」的效果定义（§11 二尾、§09 定身档的控制期增伤）。
##
## ## 为什么它在代码里而不在 `data/buffs/`
##
## 它的窗口和倍率来自**大招**（[member PBSkill.buff_ticks] /
## [member PBSkill.team_damage_scale]），而那两个数一个来自尾兽表、
## 一个来自 [member PBSimConfig.bond_root_damage_scale] —— 都是要扫的参数。
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
