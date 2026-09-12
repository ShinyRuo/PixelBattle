class_name PBPassiveRules
extends RefCounted
## 一个**常驻效果**怎么装到一个人身上。全部 static，无状态，零引擎依赖。
##
## 和 [PBBuffRules]（一份会过期的效果）对着看：那一层管的是「这一波暂时怎么样」，
## 这一层管的是「他站在场上就一直是这样」——
## 后者不进效果袋，直接乘死在 [PBAttacker] 的字段上。
##
## ## 为什么它从羁绊里抽出来
##
## M10-d 的 `Landing.CARRIER` 档（重生 / 溅射 / 打高血量多打一笔 / 命中后提暴击）
## 当时只有羁绊一个来源，所以那套映射写在 [PBBondFunctionRules] 里。
## M12-c2 来了第二个来源：**角色自带的被动**（原版 56 张卡里有 10 个是
## 「攻击时 X% 触发 Y」这种没有施法、没有冷却、没有蓝的东西 ——
## 玩家按不出来，它不是技能）。
##
## 两处各写一份映射的话，「羁绊给的溅射」和「角色自带的溅射」迟早在
## **叠加方式**上分叉（一个 `=` 一个 `+=` 就够了），
## 而分叉的那一侧静默生效：屏幕上照样溅射，只是量不对。
##
## **键认不认得也只有一处**（[method is_known]）—— 同 [method PBBuffRules.validate]
## 那条：两处各判各的话，「这个键认不认」迟早分叉。
##
## ## 词汇表里的键 = 已经接上读点的键
##
## 同 [PBBuffRules.ALL] 顶上那条（M7-a）。拼对了却没人读的键比拼错更难查：
## 数据、界面、日志全部正常，只有伤害数字不对。所以这里**一个键都不预留**,
## 要加就连着它的读点一起加。今天这六个的读点全部已经在跑：
##
## | 键 | 落在哪个字段 | 谁读它 |
## |---|---|---|
## | `crit_chance` | [member PBAttacker.crit_chance] | [method PBCritRules.chance_of] |
## | `crit_damage` | [member PBAttacker.crit_bonus] | [method PBCritRules.multiplier_of] |
## | `crit_on_hit` | [member PBAttacker.crit_on_hit] | [method PBStrikeRules.land] |
## | `splash` | [member PBAttacker.splash_damage] | [method PBStrikeRules.land] |
## | `heavy_hit` | [member PBAttacker.heavy_bonus] | [method PBStrikeRules.land] |
## | `revive` | [member PBAttacker.revives_max] | [method PBAttacker.take_damage] |
##
## ## 「X% 几率打出更多伤害」就是暴击，不是第七个键
##
## 原版那 10 个被动里有 4 个是这个形状（写轮眼 20% 两倍、削灭斩 20% 额外伤害、
## 风切 [5+等级x4]% 额外伤害、轮回眼 15% 两倍）。它们**用前两个键就写得出来** ——
## 另开一个 `proc_chance` 的话，屏幕上会有两套各自掷骰的暴击，
## 而 M10-c 那条「一个掷点」（[PBCritRules] 顶上）正是为了防这个：
## 掷两次就等于同一条 RNG 流被拨动两次，
## 而 [method PBAttacker.whole_field] 那条与解析式排队模型逐位对拍的
## 退化路径靠的就是「该掷几次就掷几次」。

## 暴击率（常驻那一份）。
const CRIT_CHANCE: StringName = &"crit_chance"

## 暴击倍率的加数。**中性值是 0.0 不是 1.0** —— 见 [member PBAttacker.crit_bonus]。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 命中之后那一小段时间里额外的暴击率。
const CRIT_ON_HIT: StringName = &"crit_on_hit"

## 普攻附带的范围伤害，值是主伤害的几成。
const SPLASH: StringName = &"splash"

## 对血还很多的敌人追加的那一笔，值是主伤害的几成。
const HEAVY_HIT: StringName = &"heavy_hit"

## 一波能重生几次。**取整** —— 半次重生没有意义。
const REVIVE: StringName = &"revive"

## 认得的全部键。见本类顶上「词汇表里的键 = 已经接上读点的键」。
const ALL: Array[StringName] = [
	CRIT_CHANCE, CRIT_DAMAGE, CRIT_ON_HIT, SPLASH, HEAVY_HIT, REVIVE
]


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 把一个常驻效果按给定的量装到这个人身上。返回 false 表示这个键不认得。
##
## **一律是 `+=` 不是 `=`。** 同一个人可以既是某组羁绊的载体、又自带一个被动，
## 而「后装的那一份把先装的覆盖掉」不报错 —— 屏幕上照样有溅射，只是少了一份。
##
## [param amount] 不做范围检查：负数是合法的（原版有「降低自身暴击率」这种
## 代价型被动），而拦在这里等于把设计决定写死在规则层。
static func grant(attacker: PBAttacker, key: StringName, amount: float) -> bool:
	if attacker == null:
		return false
	match key:
		CRIT_CHANCE:
			attacker.crit_chance += amount
		CRIT_DAMAGE:
			attacker.crit_bonus += amount
		CRIT_ON_HIT:
			attacker.crit_on_hit += amount
		SPLASH:
			attacker.splash_damage += amount
		HEAVY_HIT:
			attacker.heavy_bonus += amount
		REVIVE:
			attacker.revives_max += int(round(amount))
		_:
			return false
	return true


## 把一整份被动表（键 → 量）装到这个人身上。返回装上了几个。
##
## **不认得的键在这里不报错，只是不装** —— 拦它的地方是生成器
## （`src/tools/make_roster.gd` 读表那一刻，退出码 1）。
## 规则层再拦一次的话，同一件事就有了两把尺子，
## 而战斗中途 `push_error` 也没有人看得见。
static func grant_all(attacker: PBAttacker, passives: Dictionary) -> int:
	var done: int = 0
	for key: StringName in passives:
		if grant(attacker, key, float(passives[key])):
			done += 1
	return done
