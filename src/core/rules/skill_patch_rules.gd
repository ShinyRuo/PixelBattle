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
const FULL_DAMAGE_RADIUS_SET: StringName = &"full_damage_radius_set"
const OUTER_DAMAGE_SCALE_SET: StringName = &"outer_damage_scale_set"
const IMPACT_HOLD_RADIUS: StringName = &"impact_hold_radius"
const IMPACT_HOLD_SECONDS: StringName = &"impact_hold_seconds"
const RANGED_ATTACK_AURA_SET: StringName = &"ranged_attack_aura_set"
const HIT_NINJUTSU_SHIELD_MAX: StringName = &"hit_ninjutsu_shield_max"

## 冷却乘几（小于 1 = 转得更快）。
const COOLDOWN_SCALE: StringName = &"cooldown_scale"
const REBATE_DELAY_SECONDS: StringName = &"rebate_delay_seconds"
const REBATE_MANA_SCALE: StringName = &"rebate_mana_scale"
const REBATE_COOLDOWN_SECONDS: StringName = &"rebate_cooldown_seconds"

## 多打几个目标（〔傀儡匠心〕千代「【己生转生】能够额外影响一个单位」= 1）。
const TARGETS_ADD: StringName = &"targets_add"
const EXTRA_TARGET_RADIUS_SET: StringName = &"extra_target_radius_set"
const EXTRA_CONTROL_SCALE_SET: StringName = &"extra_control_scale_set"
const TRANSFER_SCALE: StringName = &"transfer_scale"
const PHANTOM_ADD: StringName = &"phantom_add"
const FOLLOWUP_ENABLE: StringName = &"followup_enable"
const VARIANT_ENABLE: StringName = &"variant_enable"
const RESCUE_RADIUS: StringName = &"rescue_radius"
const SELF_DURATION_SCALE: StringName = &"self_duration_scale"
const SUMMON_POWER_SET: StringName = &"summon_power_set"

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

## 这个技能**改成阵亡时放**（[member PBSkill.fires_on_death]），量写 1。
##
## 点的技能**不必在他的技能表里**：阵亡技能本来就不进指令卡，是羁绊发给他的。
## 读点在 [method PBCombatRules._equip_skills]（装进 [member PBAttacker.death_casts]）。
const ON_DEATH: StringName = &"on_death"
## 羁绊授予的攻击起手技能，量为独立触发概率，不是普攻暴击率。
const ON_ATTACK_CHANCE: StringName = &"on_attack_chance"
const ATTACK_REPEATS_ADD: StringName = &"attack_repeats_add"
const HEAL_AURA_MAX_SET: StringName = &"heal_aura_max_set"
const HEAL_AURA_HIT_CHANCE: StringName = &"heal_aura_hit_chance"
const HEAL_AURA_LOST: StringName = &"heal_aura_lost"

## 每次命中将范围内存活目标聚到技能圆心。
const GATHER: StringName = &"gather"
const FIRST_CAST_ATTACK: StringName = &"first_cast_attack"
const TARGET_EFFECT_AREA: StringName = &"target_effect_area"
## 命中后附加眩晕秒数，作用范围完全遵守原技能命中名单。
const HIT_STUN_SECONDS: StringName = &"hit_stun_seconds"
const ECHO_DELAY_SECONDS: StringName = &"echo_delay_seconds"
const ECHO_RADIUS_SCALE: StringName = &"echo_radius_scale"
const HITS_ADD: StringName = &"hits_add"
const HIT_INTERVAL_SECONDS: StringName = &"hit_interval_seconds"
const HIT_STEP_SET: StringName = &"hit_step_set"
## 只缩放命中效果的伤害载荷；不改变控制强度、时长或其他技能共享的效果定义。
const ON_HIT_HARM_SCALE: StringName = &"on_hit_harm_scale"

## 认得的全部键。**同 [constant PBBuffRules.ALL] 顶上那条**：
## 键跟着读点一起进来，不先把词汇表铺满 —— 拼对了却没人读的键
## 比拼错更难查（数据、界面、日志全正常，只有那一发的强度不对）。
const ALL: Array[StringName] = [
	POWER_SCALE,
	RADIUS_SCALE,
	RADIUS_SET,
	FULL_DAMAGE_RADIUS_SET,
	OUTER_DAMAGE_SCALE_SET,
	IMPACT_HOLD_RADIUS,
	IMPACT_HOLD_SECONDS,
	RANGED_ATTACK_AURA_SET,
	HIT_NINJUTSU_SHIELD_MAX,
	COOLDOWN_SCALE,
	REBATE_DELAY_SECONDS,
	REBATE_MANA_SCALE,
	REBATE_COOLDOWN_SECONDS,
	TARGETS_ADD,
	EXTRA_TARGET_RADIUS_SET,
	EXTRA_CONTROL_SCALE_SET,
	TRANSFER_SCALE,
	PHANTOM_ADD,
	FOLLOWUP_ENABLE,
	VARIANT_ENABLE,
	SELF_DURATION_SCALE,
	RESCUE_RADIUS,
	SUMMON_POWER_SET,
	SUMMON_ADD,
	SUMMON_POWER_SCALE,
	SUMMON_SECS_SCALE,
	SLOW_SET,
	SLOW_SECS_SET,
	ON_DEATH,
	ON_ATTACK_CHANCE,
	ATTACK_REPEATS_ADD,
	HEAL_AURA_MAX_SET,
	HEAL_AURA_HIT_CHANCE,
	HEAL_AURA_LOST,
	GATHER,
	FIRST_CAST_ATTACK,
	TARGET_EFFECT_AREA,
	HIT_STUN_SECONDS,
	ECHO_DELAY_SECONDS,
	ECHO_RADIUS_SCALE,
	HITS_ADD,
	HIT_INTERVAL_SECONDS,
	HIT_STEP_SET,
	ON_HIT_HARM_SCALE,
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
		ATTACK_REPEATS_ADD:
			skill.attack_repeat_count += roundi(amount)
		HEAL_AURA_MAX_SET:
			skill.heal_aura_max = amount
		HEAL_AURA_HIT_CHANCE:
			skill.heal_aura_hit_chance = amount
		HEAL_AURA_LOST:
			skill.heal_aura_lost = amount
		VARIANT_ENABLE:
			skill.variant_enabled = amount > 0.0
		REBATE_DELAY_SECONDS:
			skill.rebate_delay_ticks = maxi(roundi(amount * rate), 1)
		REBATE_MANA_SCALE:
			skill.rebate_mana_scale = amount
		REBATE_COOLDOWN_SECONDS:
			skill.rebate_cooldown_ticks = maxi(roundi(amount * rate), 1)
		RESCUE_RADIUS:
			skill.rescue_radius = maxf(amount, 0.0)
		SELF_DURATION_SCALE:
			_scale_self_duration(skill, amount)
		FOLLOWUP_ENABLE:
			skill.followup_enabled = amount > 0.0
		PHANTOM_ADD:
			skill.phantom_count += roundi(amount)
		SUMMON_POWER_SET:
			skill.summon_power = amount
		TRANSFER_SCALE:
			skill.transfer_scale *= amount
		POWER_SCALE:
			skill.power_mult *= amount
			skill.damage_base *= amount
			skill.damage_growth *= amount
			skill.damage_hp *= amount
		RADIUS_SCALE:
			skill.radius *= amount
		RADIUS_SET:
			skill.radius = amount
		FULL_DAMAGE_RADIUS_SET:
			skill.full_damage_radius = amount
		OUTER_DAMAGE_SCALE_SET:
			skill.outer_damage_scale = amount
		IMPACT_HOLD_RADIUS:
			skill.impact_hold_radius = amount
		IMPACT_HOLD_SECONDS:
			skill.impact_hold_seconds = amount
		RANGED_ATTACK_AURA_SET:
			skill.ranged_attack_aura = amount
		HIT_NINJUTSU_SHIELD_MAX:
			_set_shield_max(skill, amount)
		COOLDOWN_SCALE:
			skill.cooldown_ticks = maxi(int(round(float(skill.cooldown_ticks) * amount)), 1)
		TARGETS_ADD:
			PBSkillTargets.add_count(skill, roundi(amount))
		EXTRA_TARGET_RADIUS_SET:
			skill.extra_target_radius = maxf(amount, 0.0)
		EXTRA_CONTROL_SCALE_SET:
			skill.extra_control_scale = amount
		SUMMON_ADD:
			skill.summon_count = maxi(skill.summon_count + int(round(amount)), 0)
		SUMMON_POWER_SCALE:
			skill.summon_power *= amount
			skill.summon_power_growth *= amount
		SUMMON_SECS_SCALE:
			skill.summon_seconds *= amount
		SLOW_SET:
			skill.slow_scale = amount
		ON_DEATH:
			skill.fires_on_death = amount > 0.0
		ON_ATTACK_CHANCE:
			skill.attack_trigger_chance = amount
		GATHER:
			skill.gather = amount > 0.0
		FIRST_CAST_ATTACK:
			skill.first_cast_attack = maxf(amount, 0.0)
		TARGET_EFFECT_AREA:
			skill.target_effect_area = amount > 0.0
		HIT_STUN_SECONDS:
			_add_hit_stun(skill, amount)
		ECHO_DELAY_SECONDS:
			skill.echo_delay_ticks = maxi(roundi(amount * rate), 0)
		ECHO_RADIUS_SCALE:
			skill.echo_radius_scale = maxf(amount, 0.0)
		HITS_ADD:
			skill.hit_count = maxi(skill.hit_count + roundi(amount), 1)
		HIT_INTERVAL_SECONDS:
			skill.hit_interval_ticks = maxi(roundi(amount * rate), 0)
		HIT_STEP_SET:
			skill.hit_step = maxf(amount, 0.0)
		ON_HIT_HARM_SCALE:
			_scale_hit_harm(skill, maxf(amount, 0.0))
		SLOW_SECS_SET:
			skill.slow_ticks = maxi(int(round(amount * float(rate))), 1)
		_:
			return false
	return true


static func _scale_self_duration(skill: PBSkill, scale: float) -> void:
	for i: int in skill.on_self.size():
		var copy: PBBuff = skill.on_self[i].duplicate(true) as PBBuff
		copy.duration_seconds *= scale
		for level: int in copy.duration_levels.size():
			copy.duration_levels[level] *= scale
		skill.on_self[i] = copy


static func _scale_hit_harm(skill: PBSkill, scale: float) -> void:
	for i: int in skill.on_hit.size():
		var original: PBBuff = skill.on_hit[i]
		if not original.mods.has(PBBuffRules.HARM):
			continue
		var copy: PBBuff = original.duplicate(true) as PBBuff
		copy.mods[PBBuffRules.HARM] = float(original.mods[PBBuffRules.HARM]) * scale
		if original.mods_growth.has(PBBuffRules.HARM):
			copy.mods_growth[PBBuffRules.HARM] = (
				float(original.mods_growth[PBBuffRules.HARM]) * scale
			)
		copy.harm_mult *= scale
		skill.on_hit[i] = copy


static func _set_shield_max(skill: PBSkill, amount: float) -> void:
	for i: int in skill.on_hit.size():
		if not skill.on_hit[i].mods.has(PBBuffRules.NINJUTSU_SHIELD):
			continue
		var copy: PBBuff = skill.on_hit[i].duplicate(true) as PBBuff
		copy.mods[PBBuffRules.NINJUTSU_SHIELD_MAX] = amount
		copy.mods_growth.erase(PBBuffRules.NINJUTSU_SHIELD_MAX)
		skill.on_hit[i] = copy


static func _add_hit_stun(skill: PBSkill, seconds: float) -> void:
	var id := StringName("%s_impact_stun" % skill.id)
	# 重新打同一个设定时替换自己的效果，不累加，也不改写原始资源引用。
	for i: int in range(skill.on_hit.size() - 1, -1, -1):
		if skill.on_hit[i].id == id:
			skill.on_hit.remove_at(i)
	if seconds <= 0.0 or not is_finite(seconds):
		return
	var buff := PBBuff.new()
	buff.id = id
	buff.name_key = "effect.impact_stun"
	buff.kind = PBBuff.Kind.DURATION
	buff.friendly = false
	buff.duration_seconds = seconds
	buff.mods = {PBBuffRules.STUN: 1.0, PBBuffRules.ENEMY_SPEED_SCALE: 0.0}
	skill.on_hit.append(buff)
