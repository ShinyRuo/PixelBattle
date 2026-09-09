class_name PBCritRules
extends RefCounted
## 暴击：掷不掷、掷中了打多少（M10-c）。全部 static，无状态，零引擎依赖。
##
## 和 [PBTargetRules]（敌人该打谁）、[PBMoveRules]（我方该往哪儿走）、
## [PBSkillRules]（一发技能落地时发生什么）、[PBShotRules]（子弹落地）对称。
##
## ## 只有一个掷点，因为出手有三条路
##
## [PBBattleSim] 里出手分单体 / 连续输出 / 范围三条，加上子弹是四处；
## 各自掷骰的话，漏一处的表现是「**某一种攻击方式不会暴击**」——
## 而它不报错，要盯着一屏数字看很久才发现。这个项目为「同一件事两把尺子」
## 付过四次代价，所以三条路都只调 [method strike]。
##
## ## 暴击率为 0 时**一次都不掷**
##
## 这不是优化，是对拍锚点的保命符。连续输出那一档
## （[method PBAttacker.whole_field]）必须与 [PBCombatRules] 的解析式
## 排队模型逐位相同，而**掷了就算不暴击也已经拨动了那条流** ——
## 后面每一次掷骰的结果都跟着挪一位。所以早退是一条正确性规则。
##
## 由此还得到一条更强的性质：**没有任何来源给暴击率时，
## 整局一位都不动**（同 M3.5-f 装备那条「空着 = 一字不差」）。
##
## ## 只作用于「一个攻击者出的手」，忍术不吃（玩家定的）
##
## 一发 AOE 同时打十几个，一次掷骰决定整波的伤害 —— 玩家读到的会是
## 「这一波运气好」而不是「这一下打得重」，而后者才是暴击要表达的东西。
## §7 文档里 B13 / B21 也把「忍术伤害」和「暴击概率」并列写成两件事。
##
## ## 两个来源相加，不是两套机制
##
## 常驻那一份（羁绊光环）在 [member PBAttacker.crit_chance] 上 ——
## 它整波不变、没有施法者、不该占 [PBBuffBag] 那六个槽，而且袋子是
## **同 id 整份覆盖**的，两组羁绊各挂一份会静默吃掉一份。
## 临时那一份（命中后提暴击、技能窗口）在袋子里
## （[constant PBBuffRules.CRIT_CHANCE]）。两者在这里相加。

## 掷出来的一手：打多少、是不是暴击。
##
## 用字典而不是两个返回值，是因为调用方**两样都要**：伤害要打出去，
## 「是不是暴击」要进播报（渲染层靠它决定飘不飘黄字）。
## 分成两次调用的话第二次会再掷一遍骰子，那就是另一个答案。
const DAMAGE: StringName = &"damage"
const CRIT: StringName = &"crit"

## 暴击时**额外**多打几成。0.5 = 打 150%。
##
## ## 为什么这三个数不在 [PBSimConfig] 里
##
## 那个文件落地这一步时已经停在 gdlint 的 1000 行上限上，而它顶上写着
## 自己是干什么的：「批量扫描一次跑几千局，每局一份改了 `growth` 的副本」——
## 也就是**要扫的那些参数**。暴击这三个今天一个都不进扫描，
## 和 [constant PBAttacker.STOP_RING]、[constant PBDamageWatch.MIN_FRACTION]
## 一样贴着自己唯一的读点放。
##
## 要扫它们的那一天，先把 [PBSimConfig] 里那一整段羁绊功能档搬出去 ——
## **别搬成一个嵌套对象**：[method PBSimConfig.clone] 是反射逐字段拷贝的，
## 嵌套那一份会按引用共享，于是扫描的几千个副本改的是同一份数，而它不报错。
const CRIT_DAMAGE_BASE: float = 0.5

## [constant PBBondFunctionRules.CRIT_CHANCE] 给全队多少暴击率。
##
## **基础暴击率恒为 0，那不是一个参数** —— 暴击只从羁绊光环和技能来。
## 给一个全场基础值的话全部既有配平数字当场全变，而 §7 那份文档里没有这一项。
const BOND_CRIT_CHANCE: float = 0.15

## [constant PBBondFunctionRules.CRIT_DAMAGE] 给全队多少暴击伤害加成。
const BOND_CRIT_DAMAGE: float = 0.5


## 这个单位这一刻的暴击率。常驻 + 临时，钳在 0~1。
##
## 钳上限是必须的：两组羁绊光环 + 一个技能窗口摞起来能超过 1，
## 而 `randf() < 1.2` 恒为真 —— 那时暴击率这个数就没有意义了，
## 而屏幕上只表现为「怎么每一下都是黄的」。
static func chance_of(unit: PBAttacker, at_tick: int) -> float:
	if unit == null:
		return 0.0
	var temp: float = unit.buffs.amount(PBBuffRules.CRIT_CHANCE, at_tick)
	return clampf(unit.crit_chance + temp, 0.0, 1.0)


## 暴击时打几倍。基础 + 常驻加成 + 临时加成，**三份全是加法**。
static func multiplier_of(unit: PBAttacker, at_tick: int) -> float:
	if unit == null:
		return 1.0 + CRIT_DAMAGE_BASE
	var temp: float = unit.buffs.amount(PBBuffRules.CRIT_DAMAGE, at_tick)
	return 1.0 + maxf(CRIT_DAMAGE_BASE + unit.crit_bonus + temp, 0.0)


## 这一发打多少、暴没暴。**出手的唯一入口。**
##
## [param rng] 为 null 时（批量扫描、探测、老的构造点）恒不暴击且**不掷骰**。
## 暴击率为 0 时同理 —— 见本类顶部那条「一次都不掷」。
static func strike(
	unit: PBAttacker, at_tick: int, rng: RandomNumberGenerator = null
) -> Dictionary:
	var damage: float = unit.strike_for(at_tick)
	var chance: float = chance_of(unit, at_tick)
	if rng == null or chance <= 0.0:
		return {DAMAGE: damage, CRIT: false}
	if rng.randf() >= chance:
		return {DAMAGE: damage, CRIT: false}
	return {DAMAGE: damage * multiplier_of(unit, at_tick), CRIT: true}
