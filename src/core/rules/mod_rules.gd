class_name PBModRules
extends RefCounted
## 词条系统的**总目录**：一个键认不认得。全部 static，无状态，零引擎依赖。
##
## ## 为什么词条分成两张表
##
## 装备、羁绊、尾兽光环、角色被动写的是同一种东西（「给这个人加点什么」），
## 但它们**生效的时刻不同**，而那个差别是结构性的：
##
## | | 词汇表 | 什么时候生效 |
## |---|---|---|
## | **属性** | [PBStatRules] | 算三围那一刻，**属性克制之前** |
## | **行为** | [PBPassiveRules] | 建好人之后，装到 [PBAttacker] 身上 |
##
## 属性那一档非在前面不可，两个理由缺一不可：
## **二级属性是从一级属性派生的**（`生命 = 100 + 力量×80`），事后加力量
## 只是加了一个孤立的数；而**攻击力还要排在克制之前** ——
## [member PBAttacker.attack] 是 `stats.atk × 克制倍率`，
## 事后加的那 200 点**不吃克制**，而原版是吃的。
##
## ## 为什么「认不认得」要收在这里
##
## 三个生成器、尾兽加载器、四个测试**都在问同一个问题**。
## 各写一句 `A.is_known(k) or B.is_known(k)` 的话，加第三张表时要改七处，
## 而漏掉的那一处的表现是**「这个键在别处能用，在这里被拒收」**——
## 或者更糟，反过来：拒收那一关漏了，于是拼错的键一路走到底，
## 静默地什么都不做。同 [method PBBuffRules.validate] 顶上那条。

## 按**成数**记的那几个键（中性 0.0，屏幕上要写成百分比）。
##
## 其余是**量型**，直接就是点数。两者在表里靠名字分不开
## （`attack` 是点数、`attack_speed` 是成数），而**猜错的表现是
## 界面上写着「攻速 +0%」**—— 0.30 按点数格式化出来就是这个。
## 所以判据收在这里一处，两块面板共用。
const RATE_KEYS: Array[StringName] = [
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
]


## 这个键有人认得吗 —— 属性表或者行为表，两张里有一张就算。
static func is_known(key: StringName) -> bool:
	return PBStatRules.is_known(key) or PBPassiveRules.is_known(key)


## 两张表加起来一共认得几个键。**只给测试用**：它拦的是
## 「同一个键被塞进两张表」—— 那种键会被算两遍，而它不报错。
static func total_keys() -> int:
	return PBStatRules.ALL.size() + PBPassiveRules.ALL.size()


## 这个键是按成数记的吗。见 [constant RATE_KEYS]。
static func is_rate(key: StringName) -> bool:
	return RATE_KEYS.has(key)


## 屏幕上该拿哪个数去格式化。成数乘 100，量型原样。
static func display_value(key: StringName, value: float) -> float:
	return value * 100.0 if is_rate(key) else value
