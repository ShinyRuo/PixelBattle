class_name PBModRules
extends RefCounted
## 词条系统的**总目录**：一个键认不认得。全部 static，无状态，零引擎依赖。
##
## ## 词条分两张表，因为生效时刻不同
##
## | | 词汇表 | 什么时候生效 |
## |---|---|---|
## | **属性** | [PBStatRules] | 算三围那一刻，**属性克制之前** |
## | **行为** | [PBPassiveRules] | 建好人之后，装到 [PBAttacker] 身上 |
##
## 属性必须在前：二级属性从一级派生（`生命 = 100 + 力量×80`），事后加力量只是
## 一个孤立的数；攻击力还要吃克制（[member PBAttacker.attack] = `stats.atk × 克制倍率`）。
##
## ## 「认不认得」只在这里判
##
## 生成器、尾兽加载器、测试都在问同一个问题。各写一句 `A.is_known or B.is_known`
## 的话，加第三张表时漏改的那一处会拒收能用的键，或放过拼错的键。

## 按**成数**记的那几个键（中性 0.0，屏幕上要写成百分比）。
##
## 其余是**量型**，直接就是点数。两者在表里靠名字分不开
## （`attack` 是点数、`attack_speed` 是成数），而**猜错的表现是
## 界面上写着「攻速 +0%」**—— 0.30 按点数格式化出来就是这个。
## 所以判据收在这里一处，两块面板共用。
const RATE_KEYS: Array[StringName] = [
	PBPassiveRules.STACK_HARM_BONUS,
	PBStatRules.ALL_STATS_BONUS,
	PBStatRules.ALL_STATS_TOTAL_BONUS,
	PBStatRules.HP_BONUS,
	PBStatRules.ATTACK_SPEED,
	PBPassiveRules.CRIT_CHANCE,
	PBPassiveRules.CRIT_DAMAGE,
	PBPassiveRules.CRIT_ON_HIT,
	PBPassiveRules.SPLASH,
	PBPassiveRules.HEAVY_HIT,
	PBPassiveRules.DODGE,
	PBPassiveRules.BITE_CURRENT,
	PBPassiveRules.BITE_LOST,
	PBPassiveRules.REFLECT,
	PBPassiveRules.DAMAGE_BONUS,
	PBPassiveRules.MOVE_SPEED_BONUS,
	PBPassiveRules.LOW_HP,
	PBPassiveRules.DRAIN_CUT,
	PBPassiveRules.LIFESTEAL,
	PBPassiveRules.DODGE_HEAL,
	PBPassiveRules.HEAL_POWER,
	PBPassiveRules.STRUCK_BOOST,
	PBPassiveRules.STRUCK_STRENGTH_BONUS,
	PBPassiveRules.STRUCK_DODGE,
	PBPassiveRules.STRUCK_SUMMON,
	PBPassiveRules.UNDYING_END_HEAL,
	PBPassiveRules.REGEN_MAX,
	PBPassiveRules.FIRE_TAKEN,
	PBPassiveRules.WIND_TAKEN,
	PBPassiveRules.THUNDER_TAKEN,
	PBPassiveRules.EARTH_TAKEN,
	PBPassiveRules.WATER_TAKEN,
	PBPassiveRules.PHYSICAL_TAKEN,
	PBPassiveRules.DODGE_COUNTER,
	PBPassiveRules.MELEE_TAKEN,
	PBPassiveRules.MELEE_REFLECT,
	PBPassiveRules.ARMOR_PEN,
	PBPassiveRules.NINJUTSU_PEN,
	PBPassiveRules.NINJUTSU_BONUS,
	PBPassiveRules.ALL_DAMAGE_BONUS,
	PBPassiveRules.TAIJUTSU_BONUS,
	PBPassiveRules.NINJUTSU_RESIST,
	PBPassiveRules.NINJUTSU_CRIT_CHANCE,
	PBPassiveRules.NINJUTSU_CRIT_DAMAGE,
]


## 这个键有人认得吗 —— 属性表或者行为表，两张里有一张就算。
static func is_known(key: StringName) -> bool:
	return PBStatRules.is_known(key) or PBPassiveRules.is_known(key)


## 这个键是按成数记的吗。见 [constant RATE_KEYS]。
static func is_rate(key: StringName) -> bool:
	return RATE_KEYS.has(key)


## 屏幕上该拿哪个数去格式化。成数乘 100，量型原样。
static func display_value(key: StringName, value: float) -> float:
	return value * 100.0 if is_rate(key) else value
