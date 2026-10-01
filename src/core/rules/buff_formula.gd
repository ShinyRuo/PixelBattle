class_name PBBuffFormula
extends RefCounted
## 效果的属性伤害与按等级时长。属性值来自施加时的快照，不能每跳读取施法者。

const STATS: Array[StringName] = [&"strength", &"agility", &"intellect", &"attack", &"max_hp"]


static func resolve(buff: PBBuff, mods: Dictionary, source: PBHarmContext) -> Dictionary:
	if source == null or (buff.harm_stat == &"" and not buff.independent_stacks):
		return mods
	var out: Dictionary = mods.duplicate()
	if buff.harm_stat != &"":
		out[PBBuffRules.HARM] = (
			float(out.get(PBBuffRules.HARM, 0.0))
			+ buff.harm_mult * float(source.attributes.get(buff.harm_stat, 0.0))
		)
	if buff.independent_stacks:
		out[PBBuffRules.HARM] = float(out.get(PBBuffRules.HARM, 0.0)) * source.stack_harm_scale
		out[PBBuffRules.ENEMY_DEFENCE] = (
			float(out.get(PBBuffRules.ENEMY_DEFENCE, 0.0)) + source.stack_defence
		)
	return out


static func validate(buff: PBBuff) -> String:
	var control_error: String = _validate_control(buff)
	if control_error != "":
		return control_error
	if buff.harm_stat != &"" and not STATS.has(buff.harm_stat):
		return "不认识的效果伤害属性：%s" % buff.harm_stat
	if not is_finite(buff.harm_mult) or buff.harm_mult < 0.0:
		return "效果属性系数必须为非负有限数"
	if buff.harm_stat != &"" or buff.harm_mult != 0.0:
		if buff.harm_stat == &"" or not buff.mods.has(PBBuffRules.HARM):
			return "属性伤害必须同时指定 harm_stat 与 harm 基数"
	for seconds: float in buff.duration_levels:
		if not is_finite(seconds) or seconds <= 0.0 or buff.kind == PBBuff.Kind.INSTANT:
			return "分级持续时间必须为正数，且只能用于持续或周期效果"
	var window_error := _validate_ally_window(buff)
	return PBTemporaryAttributeRules.validate(buff) if window_error == "" else window_error


static func _validate_levels(buff: PBBuff) -> String:
	for key: StringName in buff.mods_levels:
		if not buff.mods.has(key) or buff.mods_growth.has(key):
			return "分级效果必须有基数，且不能同时配置线性成长"
		if not buff.mods_levels[key] is PackedFloat32Array:
			return "分级效果必须为数值数组"
		var values: PackedFloat32Array = buff.mods_levels[key]
		if values.is_empty() or not is_equal_approx(values[0], float(buff.mods[key])):
			return "分级效果首项须等于基数，不能空表"
		for value: float in values:
			if not is_finite(value):
				return "分级效果必须为有限数"
	return ""


static func _validate_ally_window(buff: PBBuff) -> String:
	for key: StringName in [
		PBBuffRules.REFLECT,
		PBBuffRules.NINJUTSU_IMMUNE,
		PBBuffRules.CHANNEL,
		PBBuffRules.NINJUTSU_SHIELD,
		PBBuffRules.NINJUTSU_SHIELD_MAX,
		PBBuffRules.BASE_ATTACK_BONUS
	]:
		if not buff.mods.has(key):
			continue
		if not buff.friendly or buff.kind != PBBuff.Kind.DURATION:
			return "反弹、忍术免疫、忍术护盾与持续施放只能用于己方持续效果"
		for value: float in [float(buff.mods[key]), float(buff.mods_growth.get(key, 0.0))]:
			if not is_finite(value) or value < 0.0:
				return "己方持续窗口的基础值与成长必须为非负有限数"
	return ""


static func _validate_stacks(buff: PBBuff) -> String:
	if buff.until_wave_end or buff.per_source:
		if not buff.friendly or buff.kind != PBBuff.Kind.DURATION or buff.independent_stacks:
			return "整波与按来源状态仅支持己方普通持续 BUFF"
		if (
			buff.until_wave_end
			and (buff.duration_seconds != 0.0 or not buff.duration_levels.is_empty())
		):
			return "整波状态不配置到期时长"
	var level_error := _validate_levels(buff)
	if level_error != "":
		return level_error
	if buff.independent_stacks:
		if (
			buff.friendly
			or buff.kind != PBBuff.Kind.PERIODIC
			or not buff.mods.has(PBBuffRules.HARM)
		):
			return "独立叠层仅支持敌方周期伤害"
		for key: StringName in buff.mods:
			if key not in [PBBuffRules.HARM, PBBuffRules.ENEMY_DEFENCE]:
				return "独立叠层只允许伤害与减甲；其他控制请配独立刷新效果"
	return ""


static func _validate_control(buff: PBBuff) -> String:
	var stack_error: String = _validate_stacks(buff)
	if stack_error != "":
		return stack_error
	for key: StringName in [PBBuffRules.DISARM, PBBuffRules.SAGE_HURT_SCALE, PBBuffRules.DOMINATED]:
		if not buff.mods.has(key):
			continue
		if buff.friendly or buff.kind != PBBuff.Kind.DURATION:
			return "禁攻与仙属性易伤只能用于敌方持续效果"
		for value: float in [float(buff.mods[key]), float(buff.mods_growth.get(key, 0.0))]:
			if not is_finite(value) or value < 0.0:
				return "禁攻与仙属性易伤数值必须为非负有限数"
	if buff.mods.has(PBBuffRules.SILENCE) or buff.mods.has(PBBuffRules.AIRBORNE):
		if buff.friendly or buff.kind != PBBuff.Kind.DURATION:
			return "沉默与击飞仅支持敌方持续效果"
	if buff.mods.has(PBBuffRules.AIRBORNE):
		if (
			float(buff.mods.get(PBBuffRules.STUN, 0.0)) <= 0.0
			or float(buff.mods.get(PBBuffRules.ENEMY_SPEED_SCALE, 1.0)) != 0.0
		):
			return "击飞必须同时禁止出手和移动"
	return ""
