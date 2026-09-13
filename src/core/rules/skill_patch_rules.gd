class_name PBSkillPatchRules
extends RefCounted
## 「改这个角色的这个技能的某个数」。全部 static，零引擎依赖。
##
## 和 [PBPassiveRules] 是羁绊的两条腿：那一条答「他本人变强了什么」，
## 这一条答「**他那一发变强了什么**」。原版 118 条羁绊效果里 80 条是这个形状。
##
## ## 补丁打在复制品上
##
## [method PBCombatRules._equip_skills] 每一波按 [method PBSkill.clone] 现造一份。
## `clone()` 必须把 `on_hit` / `on_self` 数组复制一份 —— 共享的话往里追加效果
## 等于改写 `.tres` 那一份，会漏进下一波、别的角色和悬崖二分，而它不报错。
##
## ## 每个键自己说清楚是加是乘是设
##
## 原版三种语义都有（伤害 +40% 是乘、多影响一个单位是加、「周围也束缚」是设）。
## 键名带后缀区分，记错的表现只是强度差一截，不报错。

## 伤害倍率乘几（〔叶与根〕三代「【火龙炎弹】的伤害提升 40%」= 1.4）。
const POWER_SCALE: StringName = &"power_scale"

## 作用半径乘几。
const RADIUS_SCALE: StringName = &"radius_scale"

## 作用半径**设成**多少（从 0 变成有的那种）。
const RADIUS_SET: StringName = &"radius_set"

## 冷却乘几（小于 1 = 转得更快）。
const COOLDOWN_SCALE: StringName = &"cooldown_scale"

## 多打几个目标（〔傀儡匠心〕千代「【己生转生】能够额外影响一个单位」= 1）。
const TARGETS_ADD: StringName = &"targets_add"

## 多召几个（〔傀儡匠心〕勘九郎「【乌鸦】能够召唤两头」= 1）。
const SUMMON_ADD: StringName = &"summon_add"

## 召唤物的输出乘几（〔永远的对手〕卡卡西「忍犬的攻击力提升 70%」= 1.7）。
const SUMMON_POWER_SCALE: StringName = &"summon_power_scale"

## 召唤物在场的时间乘几（〔第十班·集合〕志乃「【吸血虫】的持续时间提升 50%」= 1.5）。
const SUMMON_SECS_SCALE: StringName = &"summon_secs_scale"

## 落地时的全场减速**设成**多少（0 = 定住）。
const SLOW_SET: StringName = &"slow_set"

## 那一段减速/定身持续几秒，**设成**多少。
##
## 和上一个通常成对出现（〔叶与根〕团藏「【树根爆葬】爆开后能够晕眩范围敌人 2 秒」）。
## **两个键而不是一个**：原版有「只延长时间不改幅度」的写法，
## 合成一个的话那种效果表达不了。
const SLOW_SECS_SET: StringName = &"slow_secs_set"

## 认得的全部键。**同 [constant PBBuffRules.ALL] 顶上那条**：
## 键跟着读点一起进来，不先把词汇表铺满 —— 拼对了却没人读的键
## 比拼错更难查（数据、界面、日志全正常，只有那一发的强度不对）。
const ALL: Array[StringName] = [
	POWER_SCALE,
	RADIUS_SCALE,
	RADIUS_SET,
	COOLDOWN_SCALE,
	TARGETS_ADD,
	SUMMON_ADD,
	SUMMON_POWER_SCALE,
	SUMMON_SECS_SCALE,
	SLOW_SET,
	SLOW_SECS_SET,
]


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 把一份补丁打到**一份复制品**上。返回打上了几条。
##
## [param skill] 必须是 [method PBSkill.clone] 出来的那一份 ——
## 传盘上那一份进来的话，改动会活到下一波去。
##
## **不认识的键在这里不报错，只是不打** —— 拦它的地方是生成器
## （`make_bonds.gd` 读表那一刻，退出码 1）。同 [method PBPassiveRules.grant_all]：
## 两处各拦一次就是两把尺子，而战斗中途 `push_error` 没有人看得见。
static func apply(skill: PBSkill, patch: Dictionary, rate: int = 20) -> int:
	if skill == null:
		return 0
	var done: int = 0
	for key: StringName in patch:
		if _one(skill, key, float(patch[key]), rate):
			done += 1
	return done


static func _one(skill: PBSkill, key: StringName, amount: float, rate: int) -> bool:
	match key:
		POWER_SCALE:
			skill.power_mult *= amount
		RADIUS_SCALE:
			skill.radius *= amount
		RADIUS_SET:
			skill.radius = amount
		COOLDOWN_SCALE:
			skill.cooldown_ticks = maxi(int(round(float(skill.cooldown_ticks) * amount)), 1)
		TARGETS_ADD:
			skill.max_targets = maxi(skill.max_targets + int(round(amount)), 0)
		SUMMON_ADD:
			skill.summon_count = maxi(skill.summon_count + int(round(amount)), 0)
		SUMMON_POWER_SCALE:
			skill.summon_power *= amount
		SUMMON_SECS_SCALE:
			skill.summon_seconds *= amount
		SLOW_SET:
			skill.slow_scale = amount
		SLOW_SECS_SET:
			skill.slow_ticks = maxi(int(round(amount * float(rate))), 1)
		_:
			return false
	return true
