class_name PBCritRules
extends RefCounted
## 暴击：掷不掷、掷中了打多少。全部 static，无状态，零引擎依赖。
##
## ## 只有一个掷点
##
## 出手有单体 / 连续输出 / 范围三条路，加上子弹是四处。各自掷骰的话，
## 漏一处的表现是「某一种攻击方式不会暴击」，而它不报错 —— 所以四处都只调 [method strike]。
##
## ## 暴击率为 0 时一次都不掷
##
## 这是正确性规则，不是优化：连续输出那一档（[method PBAttacker.whole_field]）
## 要与 [PBCombatRules] 的解析式排队模型逐位相同，而**掷了就算不暴击也拨动了那条流**。
## 由此还有一条性质：没有任何来源给暴击率时，整局一位都不动。
##
## ## 体术和忍术各有一套（[PBDamageKind]，玩家定的）
##
## 普攻走 [method strike]，暴击率、倍数、增伤按**这个人普攻的类型**取（[method attack_kind]）；
## 技能走 [method hit]，按**技能自己的类型**取。忍术暴击率基础为 0，只从装备、被动来。
## **一发技能只掷一次**：范围技能圈到的每个敌人吃同一个结果 —— 一发 AOE 各掷各的，
## 屏幕上一片黄一片白，玩家读不出「这一下暴没暴」。
##
## ## 两个来源相加
##
## 常驻那一份在 [member PBAttacker.crit_chance] 上（不走 [PBBuffBag]：袋子同 id
## 整份覆盖，两组羁绊各挂一份会静默吃掉一份）；临时那一份在袋子里
## （[constant PBBuffRules.CRIT_CHANCE]）。两者在这里相加。

## 掷出来的一手：打多少、是不是暴击。
##
## 用字典而不是两个返回值，是因为调用方**两样都要**：伤害要打出去，
## 「是不是暴击」要进播报（渲染层靠它决定飘不飘黄字）。
## 分成两次调用的话第二次会再掷一遍骰子，那就是另一个答案。
const DAMAGE: StringName = &"damage"
const CRIT: StringName = &"crit"

## 体术暴击时**额外**多打几成。1.0 = 打 200%（原版「英雄的普攻暴击默认是 2 倍暴击」）。
## 七刀流「暴击伤害只有 150%」就在名册里配 `crit_damage=-0.5`。
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
const CRIT_DAMAGE_BASE: float = 1.0

## 忍术暴击时额外多打几成。1.0 = 200%（原版「忍术暴击倍数 +1.0（初始 2.0）」）。
const NINJUTSU_CRIT_BASE: float = 1.0

## 一次命中的类型，见 [method strike] / [method hit] 的返回。
const KIND: StringName = &"kind"

## [constant PBBondFunctionRules.CRIT_CHANCE] 给全队多少暴击率。
##
## **基础暴击率恒为 0，那不是一个参数** —— 暴击只从羁绊光环和技能来。
## 给一个全场基础值的话全部既有配平数字当场全变，而 §7 那份文档里没有这一项。
const BOND_CRIT_CHANCE: float = 0.15

## [constant PBBondFunctionRules.CRIT_DAMAGE] 给全队多少暴击伤害加成。
const BOND_CRIT_DAMAGE: float = 0.5


## 这个人的普攻算哪一类。**判据只在这里**：普攻暴击、增伤、减伤都问它。
static func attack_kind(unit: PBAttacker) -> PBDamageKind.Type:
	if unit != null and unit.attack_ninjutsu > 0.0:
		return PBDamageKind.Type.NINJUTSU
	return PBDamageKind.Type.TAIJUTSU


## 这个单位这一刻 [param kind] 那一类的暴击率。常驻 + 临时（临时那一份只有体术），钳在 0~1。
##
## 钳上限是必须的：两组羁绊光环 + 一个技能窗口摞起来能超过 1，
## 而 `randf() < 1.2` 恒为真 —— 那时暴击率这个数就没有意义了，
## 而屏幕上只表现为「怎么每一下都是黄的」。
static func chance_of(
	unit: PBAttacker, at_tick: int, kind: PBDamageKind.Type = PBDamageKind.Type.TAIJUTSU
) -> float:
	if unit == null:
		return 0.0
	if kind == PBDamageKind.Type.NINJUTSU:
		return clampf(unit.ninjutsu_crit_chance, 0.0, 1.0)
	var temp: float = unit.buffs.amount(PBBuffRules.CRIT_CHANCE, at_tick)
	return clampf(unit.crit_chance + temp, 0.0, 1.0)


## 暴击时打几倍。基础 + 常驻加成 + 临时加成（临时那一份只有体术），**全是加法**。
static func multiplier_of(
	unit: PBAttacker, at_tick: int, kind: PBDamageKind.Type = PBDamageKind.Type.TAIJUTSU
) -> float:
	if kind == PBDamageKind.Type.NINJUTSU:
		var extra: float = 0.0 if unit == null else unit.ninjutsu_crit_bonus
		return 1.0 + maxf(NINJUTSU_CRIT_BASE + extra, 0.0)
	if unit == null:
		return 1.0 + CRIT_DAMAGE_BASE
	var temp: float = unit.buffs.amount(PBBuffRules.CRIT_DAMAGE, at_tick)
	return 1.0 + maxf(CRIT_DAMAGE_BASE + unit.crit_bonus + temp, 0.0)


## 这一发普攻打多少、暴没暴、算哪一类。**出手的唯一入口。**
##
## [param rng] 为 null 时（批量扫描、探测、老的构造点）恒不暴击且**不掷骰**。
## 暴击率为 0 时同理 —— 见本类顶部那条「一次都不掷」。
## 先取相应属性基数与普攻专用加成，再乘通用与对应类型的增伤。
## `damage_bonus` 仅表示普攻增伤，不能当作体术增伤。
static func strike(unit: PBAttacker, at_tick: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var kind := attack_kind(unit)
	var damage: float = unit.strike_for(at_tick)
	damage *= bonus_scale(unit, kind)
	return _roll(unit, damage, kind, at_tick, rng)


## 一发**技能**打多少、暴没暴：乘上 [param kind] 那一类的增伤，再掷那一类的暴击。**技能伤害的唯一入口。**
## 体术技能不吃 `damage_bonus`（那一份只作用普攻）。[param unit] 为 null（没有出手的人）时原样返回。
static func hit(
	unit: PBAttacker,
	raw: float,
	kind: PBDamageKind.Type,
	at_tick: int,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var damage: float = raw
	damage *= bonus_scale(unit, kind)
	return _roll(unit, damage, kind, at_tick, rng)


## 敌人普攻在近战 / 子弹分岔前只掷一次；子弹保存结果，飞行途中不重新读取暴击 BUFF。
static func enemy_strike(
	unit: PBEnemy, at_tick: int, rng: RandomNumberGenerator = null
) -> Dictionary:
	var kind: PBDamageKind.Type = unit.damage_kind
	var raw: float = unit.damage_per_shot
	if kind == PBDamageKind.Type.NINJUTSU:
		raw = maxf(unit.intellect, 0.0) * maxf(unit.ninjutsu_coefficient, 0.0)
	return enemy_hit(unit, raw, kind, at_tick, rng)


## 敌方技能与普攻共用分型增伤、暴击；主动技能显式传入自己的基数和类型。
static func enemy_hit(
	unit: PBEnemy,
	raw: float,
	kind: PBDamageKind.Type,
	at_tick: int,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var chance: float = unit.ninjutsu_crit_chance
	var bonus: float = unit.ninjutsu_crit_bonus
	var scale: float = unit.ninjutsu_bonus
	if kind == PBDamageKind.Type.TAIJUTSU:
		chance = unit.crit_chance + unit.buffs.amount(PBBuffRules.CRIT_CHANCE, at_tick)
		bonus = unit.crit_bonus + unit.buffs.amount(PBBuffRules.CRIT_DAMAGE, at_tick)
		scale = unit.taijutsu_bonus
	var crit: bool = rng != null and chance > 0.0 and rng.randf() < clampf(chance, 0.0, 1.0)
	var damage: float = raw * maxf(1.0 + scale, 0.0)
	damage *= maxf(1.0 + unit.all_damage_bonus, 0.0)
	if crit:
		var extra: float = (
			NINJUTSU_CRIT_BASE if kind == PBDamageKind.Type.NINJUTSU else CRIT_DAMAGE_BASE
		)
		damage *= 1.0 + maxf(extra + bonus, 0.0)
	return {DAMAGE: damage, CRIT: crit, KIND: kind}


static func bonus_scale(unit: PBAttacker, kind: PBDamageKind.Type) -> float:
	if unit == null:
		return 1.0
	var typed: float = (
		unit.ninjutsu_bonus if kind == PBDamageKind.Type.NINJUTSU else unit.taijutsu_bonus
	)
	return maxf(1.0 + unit.all_damage_bonus, 0.0) * maxf(1.0 + typed, 0.0)


static func _roll(
	unit: PBAttacker,
	damage: float,
	kind: PBDamageKind.Type,
	at_tick: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var chance: float = chance_of(unit, at_tick, kind)
	if damage <= 0.0 or rng == null or chance <= 0.0 or rng.randf() >= chance:
		return {DAMAGE: damage, CRIT: false, KIND: kind}
	return {DAMAGE: damage * multiplier_of(unit, at_tick, kind), CRIT: true, KIND: kind}
