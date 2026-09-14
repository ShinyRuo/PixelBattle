class_name PBPassiveRules
extends RefCounted
## 一个**常驻效果**怎么装到一个人身上。全部 static，无状态，零引擎依赖。
##
## 和 [PBBuffRules]（会过期的效果）对着看：这一层管「他站在场上就一直是这样」，
## 不进效果袋，直接加在 [PBAttacker] 的字段上。
##
## 来源有几个（角色自带被动 / 羁绊成员效果 / 尾兽光环 / 装备），**走同一个 [method grant]** ——
## 各写一份映射的话，叠加方式迟早分叉（一个 `=` 一个 `+=`），而分叉的那一侧静默生效。
##
## ## 词汇表里的键 = 已经接上读点的键
##
## 拼对了却没人读的键比拼错更难查，所以**一个键都不预留**，要加就连着读点一起加：
##
## | 键 | 落在哪个字段 | 谁读它 |
## |---|---|---|
## | `crit_chance` | [member PBAttacker.crit_chance] | [method PBCritRules.chance_of] |
## | `crit_damage` | [member PBAttacker.crit_bonus] | [method PBCritRules.multiplier_of] |
## | `crit_on_hit` | [member PBAttacker.crit_on_hit] | [method PBStrikeRules.land] |
## | `splash` | [member PBAttacker.splash_damage] | [method PBStrikeRules.land] |
## | `splash_radius` | [member PBAttacker.splash_radius] | [method PBStrikeRules.splash_reach] |
## | `heavy_hit` | [member PBAttacker.heavy_bonus] | [method PBStrikeRules.land] |
## | `revive` | [member PBAttacker.revives_max] | [method PBAttacker.take_damage] |
## | `dodge` | [member PBAttacker.dodge] | [method dodges] |
## | `bite_current` | [member PBAttacker.bite_current] | [method PBStrikeRules.land] |
## | `bite_lost` | [member PBAttacker.bite_lost] | [method PBStrikeRules.land] |
## | `reflect` | [member PBAttacker.reflect] | [method PBStrikeRules.hurt_ally] |
## | `damage_bonus` | [member PBAttacker.damage_bonus] | [method PBAttacker.strike_for] |
## | `move_speed_bonus` | [member PBAttacker.move_speed_bonus] | [method equip] 折进 `move_speed` |
## | `low_hp` | [member PBAttacker.low_hp_at] | [method PBStrikeRules.wound_ally] |
## | `drain_cut` | [member PBAttacker.drain_cut] | [method PBBuffRules.advance_ally] |
##
## **属性（力敏智、攻击力、防御、生命、攻速）不在这张表里**，在 [PBStatRules]：
## 属性在算三围那一刻注入，行为建人之后装。**移速留在这里**：它是全队一个数，
## 由 [member PBSimConfig.unit_move_seconds] 派生，不是角色属性。
##
## **裸名 = 量型，`_bonus` 后缀 = 率型**，每个键自己说清楚是哪一种。
##
## ## 两件有意不做的事
##
## - **忍术抗性**：要求敌人的伤害分类型，今天敌人只有一种伤害，
##   加了字段也没有任何一条伤害会去查它 —— 配了不生效。
## - **「X% 几率打出更多伤害」不另开键**：那就是暴击（前两个键写得出来）。
##   另开一个概率键等于同一次出手掷两遍骰，破了 [PBCritRules] 那条「一个掷点」。

## 暴击率（常驻那一份）。
const CRIT_CHANCE: StringName = &"crit_chance"

## 暴击倍率的加数。**中性值是 0.0 不是 1.0** —— 见 [member PBAttacker.crit_bonus]。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 命中之后那一小段时间里额外的暴击率。
const CRIT_ON_HIT: StringName = &"crit_on_hit"

## 普攻附带的范围伤害，值是主伤害的几成。
const SPLASH: StringName = &"splash"

## 溅射够得到多远，**原版码数**（275 / 250 …）。0 = 没配，用默认半径。见 [method PBStrikeRules.splash_reach]。
const SPLASH_RADIUS: StringName = &"splash_radius"

## 对血还很多的敌人追加的那一笔，值是主伤害的几成。
const HEAVY_HIT: StringName = &"heavy_hit"

## 一波能重生几次。**取整** —— 半次重生没有意义。
const REVIVE: StringName = &"revive"

## 挨一下普攻有多大机会一点血都不掉。
const DODGE: StringName = &"dodge"

## 打出要害那一下额外按目标**当前**生命的几成再打一笔。
const BITE_CURRENT: StringName = &"bite_current"

## 同 [constant BITE_CURRENT]，但按目标**已经损失**的生命算。
const BITE_LOST: StringName = &"bite_lost"

## 挨一下就把这一下伤害的几成还给打他的那个敌人。
const REFLECT: StringName = &"reflect"

## 常驻增伤：普攻多打几成。
const DAMAGE_BONUS: StringName = &"damage_bonus"

## 移动速度多几成。中性 0.0，折算在 [method equip] 末尾。
const MOVE_SPEED_BONUS: StringName = &"move_speed_bonus"

## 生命掉到最大生命的几成以下时，挂上他自带的那几份效果（[member PBAttacker.low_hp_buffs]）。
## 效果本身写在名册同一列的 `on_low_hp=<效果键>`，这个键只管阈值。
const LOW_HP: StringName = &"low_hp"

## 自身掉血（[constant PBBuffRules.DRAIN_MAX]）抵掉几成。1.0 = 不再掉血（〔吾之牢笼〕那一句）。
const DRAIN_CUT: StringName = &"drain_cut"

## 认得的全部键。见本类顶上「词汇表里的键 = 已经接上读点的键」。
const ALL: Array[StringName] = [
	CRIT_CHANCE,
	CRIT_DAMAGE,
	CRIT_ON_HIT,
	SPLASH,
	SPLASH_RADIUS,
	HEAVY_HIT,
	REVIVE,
	DODGE,
	BITE_CURRENT,
	BITE_LOST,
	REFLECT,
	DAMAGE_BONUS,
	MOVE_SPEED_BONUS,
	LOW_HP,
	DRAIN_CUT,
]


## 这一下闪掉了吗。
##
## **[member PBAttacker.dodge] 为 0 时一次骰子都不掷**（同 [method PBCritRules.strike]）：
## 掷了就算没闪也拨动了那条流，对拍退化路径靠「该掷几次就掷几次」。
##
## [param rng] 为 null 时（批量扫描、探测）恒不闪避且不掷骰。
static func dodges(attacker: PBAttacker, rng: RandomNumberGenerator) -> bool:
	if attacker == null or rng == null or attacker.dodge <= 0.0:
		return false
	return rng.randf() < attacker.dodge


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 把一个常驻效果按给定的量装到这个人身上。返回 false 表示这个键不认得。
##
## **一律是 `+=` 不是 `=`。** 同一个人可以既是某组羁绊的载体、又自带一个被动，
## 而「后装的那一份把先装的覆盖掉」不报错 —— 屏幕上照样有溅射，只是少了一份。
##
## **例外是 [constant SPLASH_RADIUS] 与 [constant LOW_HP]，取大**：一个是距离、一个是门槛，都不是一份量。
## 两个来源各给 275 码加起来成了 550 码；75% 加 90% 成了 165%，开波第一下就触发。
## 羁绊把某个人自带的 75% 改成 90%，靠的正是取大。
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
		SPLASH_RADIUS:
			attacker.splash_radius = maxf(attacker.splash_radius, amount)
		HEAVY_HIT:
			attacker.heavy_bonus += amount
		REVIVE:
			attacker.revives_max += int(round(amount))
		DODGE:
			attacker.dodge += amount
		BITE_CURRENT:
			attacker.bite_current += amount
		BITE_LOST:
			attacker.bite_lost += amount
		REFLECT:
			attacker.reflect += amount
		DAMAGE_BONUS:
			attacker.damage_bonus += amount
		MOVE_SPEED_BONUS:
			attacker.move_speed_bonus += amount
		LOW_HP:
			attacker.low_hp_at = maxf(attacker.low_hp_at, amount)
		DRAIN_CUT:
			attacker.drain_cut += amount
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


## 把几份来源一次性装到这个人身上，**装完当场折算**。
##
## [param sources] 按顺序是角色自带 / 羁绊 / 尾兽光环 / 装备，在字段上 `+=` 汇合。
## 返回一共装上了几个。
##
## **折算必须在这里面**：率型键是累加器，要乘进真正的字段才生效。
## 留给调用方的话，「忘了折」的表现是那一份配了不生效。收成一个入口之后，
## 调用方拿不到「装了但没折」的中间状态 —— 一处判，调用方不判。
##
## **先全加完再折一次**：两份 +50% 该是 +100%，边加边折就成了连乘。
##
## 折算在 [method PBAttacker.revive] 之前：开波那一句把 `hp` 填到 `max_hp`，
## 这里不要顺手改 `hp`，否则两处成了两把尺子。
static func equip(attacker: PBAttacker, sources: Array[Dictionary]) -> int:
	if attacker == null:
		return 0
	var done: int = 0
	for one: Dictionary in sources:
		done += grant_all(attacker, one)
	_settle(attacker)
	return done


## 把率型那几个累加器折进它们真正的字段。只由 [method equip] 调。
##
## **下限掐在 −1.0**（同 [method PBAttacker.strike_for] 里那句 `maxf`）：
## 原版有代价型被动，而 −1.5 会算出负的血上限，
## 那时 [method PBAttacker.revive] 会让人一站起来就是死的，**而它不报错**。
static func _settle(attacker: PBAttacker) -> void:
	if attacker.move_speed_bonus != 0.0:
		attacker.move_speed *= 1.0 + maxf(attacker.move_speed_bonus, -1.0)
