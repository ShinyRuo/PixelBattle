class_name PBEffectWords
extends RefCounted
## 技能、效果、羁绊**写成人看得懂的几句话**。三张说明卡（指令卡的技能格、信息卡的 buff 格、羁绊行）共用这一处。
##
## **一处写，别处调**：同一份效果在技能卡里写「移速 ×0.70」、在 buff 卡里写「减速 30%」的话，
## 玩家会以为是两个东西，而它不报错。所以效果键 → 句子只有 [method buff_words] 这一条路。
##
## **只写真的进战斗的数**：一律从数据现生成，不另写一份描述文字 —— 手写的描述和数据迟早对不上。
## 句式在语言表里（`buff_fx.*` / `patch.*` / `mod.*`），每个键都有一条，`tests/test_effect_words.gd` 钉着。

const TARGET_WORDS := {
	PBSkill.Target.NONE: "直接施放",
	PBSkill.Target.ALLY: "点队友",
	PBSkill.Target.ENEMY: "点敌人",
	PBSkill.Target.GROUND: "点地面",
}

## 按成数记、显示时要乘 100 的效果键（句式里是 `%`）。
const PERCENT_KEYS: Array[StringName] = [
	PBBuffRules.CRIT_CHANCE, PBBuffRules.CRIT_DAMAGE, PBBuffRules.HEAL_MAX, PBBuffRules.DRAIN_MAX
]


## 技能卡的标题：`名字（属性）`。
static func skill_title(skill: PBSkill) -> String:
	return "%s（%s）" % [PBLocale.of_skill(skill), PBUnitTile.ELEMENT_NAMES.get(skill.element, "?")]


## 技能卡的正文。[param level] 是施法者等级（效果的量随它长，见 [method PBBuffRules.resolve]）。
##
## 战斗中传进来的是这一波打过羁绊补丁、算好伤害的那一份（[member PBSkill.damage] 非 0），
## 准备阶段传的是表里那一份，只写得出倍率。
static func skill_body(skill: PBSkill, cfg: PBSimConfig, level: int = 1) -> String:
	var lines := PackedStringArray()
	var head := PackedStringArray([TARGET_WORDS.get(skill.target, "?")])
	if skill.damage > 0.0:
		head.append("伤害 %.0f" % skill.damage)
	elif skill.power_mult > 0.0:
		head.append("威力 %.1f 倍战力" % skill.power_mult)
	if skill.radius > 0.0:
		head.append("范围 %.2f" % skill.radius)
	if skill.max_targets > 0:
		head.append("最多 %d 个目标" % skill.max_targets)
	lines.append("　".join(head))
	var rate: float = float(maxi(cfg.tick_rate, 1))
	lines.append(
		"冷却 %.0f 秒　耗蓝 %.0f" % [float(skill.cooldown_ticks) / rate, skill.mp_cost]
	)
	lines.append_array(_skill_extras(skill, rate))
	for buff: PBBuff in skill.on_hit:
		lines.append("命中附带：" + buff_line(buff, level))
	for buff: PBBuff in skill.on_self:
		lines.append("自身获得：" + buff_line(buff, level))
	return "\n".join(lines)


## 一份效果写成一行：`名字（N 秒）：词条、词条`。
static func buff_line(buff: PBBuff, level: int) -> String:
	var name: String = PBLocale.text(buff.name_key)
	var words := "、".join(buff_words(PBBuffRules.resolve(buff, level)))
	if buff.kind == PBBuff.Kind.INSTANT:
		return "%s：%s" % [name, words]
	if buff.kind == PBBuff.Kind.PERIODIC:
		return "%s（%s 秒，每 %s 秒）：%s" % [
			name, _secs(buff.duration_seconds), _secs(buff.period_seconds), words
		]
	return "%s（%s 秒）：%s" % [name, _secs(buff.duration_seconds), words]


## buff 格悬停卡的标题：`名字　增益/减益`。
static func buff_title(buff: PBBuff) -> String:
	return "%s　%s" % [PBLocale.text(buff.name_key), "增益" if buff.friendly else "减益"]


## buff 格悬停卡的正文：还剩多久、每几秒一跳、给了什么。量取**挂着的那一份**（[member PBBuffState.mods]），
## 不从表里重算 —— 施法者等级、叠加刷新都已经落在那一份上。
static func buff_body(state: PBBuffState, at_tick: int, cfg: PBSimConfig) -> String:
	var rate: float = float(maxi(cfg.tick_rate, 1))
	var lines := PackedStringArray(["还剩 %s 秒" % _secs(float(state.left(at_tick)) / rate)])
	if state.buff.kind == PBBuff.Kind.PERIODIC:
		lines.append("每 %s 秒一次" % _secs(state.buff.period_seconds))
	var mods: Dictionary = state.mods if not state.mods.is_empty() else state.buff.mods
	lines.append_array(buff_words(mods))
	return "\n".join(lines)


## 一份效果键表写成几个词。**两个特例**：移速 ×0 写「定身」、受到伤害 ×0 写「无敌」——
## 写成「×0.00」读起来像是数据坏了。
static func buff_words(mods: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: StringName in mods:
		var value: float = float(mods[key])
		if key == PBBuffRules.ENEMY_SPEED_SCALE and is_zero_approx(value):
			out.append(PBLocale.text("buff_fx.rooted"))
		elif key == PBBuffRules.DAMAGE_TAKEN and is_zero_approx(value):
			out.append(PBLocale.text("buff_fx.invincible"))
		else:
			out.append(_fill("buff_fx.%s" % key, value * (100.0 if PERCENT_KEYS.has(key) else 1.0)))
	return out


## 羁绊满档给什么，一条一行：战力加成、功能（谁带）、每个成员自己的那一份、技能补丁。
static func bond_effects(bond: PBBond, cfg: PBSimConfig) -> PackedStringArray:
	var full: int = bond.full_tier_count()
	var out := PackedStringArray()
	var power: float = bond.bonus_at(full)
	if power > 0.0:
		out.append("战力 +%.0f%%" % (power * 100.0))
	var function: StringName = bond.function_at(full)
	if function != &"":
		var carrier := _name_of(bond.function_carrier_at(full), cfg)
		var who: String = "（由 %s 带）" % carrier if carrier != "" else ""
		out.append("%s%s" % [PBLocale.of_bond_function(function), who])
	for id: StringName in bond.member_functions:
		var words := PBShopLabels.mod_words(bond.member_functions[id])
		out.append("%s：%s" % [_name_of(id, cfg), "、".join(words)])
	for id: StringName in bond.member_skill_patches:
		var patches: Dictionary = bond.member_skill_patches[id]
		for skill_id: StringName in patches:
			var skill: PBSkill = cfg.skills.by_id(skill_id) if cfg.skills != null else null
			var skill_name: String = PBLocale.of_skill(skill) if skill != null else String(skill_id)
			out.append(
				"%s 的 %s：%s" % [_name_of(id, cfg), skill_name, "、".join(patch_words(patches[skill_id]))]
			)
	return out


## 一份技能补丁写成几个词。
static func patch_words(patch: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: StringName in patch:
		out.append(_fill("patch.%s" % key, float(patch[key])))
	return out


## 技能定义里那几项「顺带做的事」。
static func _skill_extras(skill: PBSkill, rate: float) -> PackedStringArray:
	var out := PackedStringArray()
	if skill.gather:
		out.append("把敌人聚拢到落点")
	if skill.knockback > 0.0:
		out.append("击退敌人")
	if skill.slow_ticks > 0:
		out.append(
			"全场减速 ×%.2f（%s 秒）" % [skill.slow_scale, _secs(float(skill.slow_ticks) / rate)]
		)
	if skill.team_damage_scale > 1.0 and skill.buff_ticks > 0:
		out.append(
			"全队伤害 ×%.2f（%s 秒）"
			% [skill.team_damage_scale, _secs(float(skill.buff_ticks) / rate)]
		)
	if skill.reset_cooldowns:
		out.append("重置队友的技能冷却")
	if skill.summon_count > 0:
		out.append("召唤 %d 个（%s 秒）" % [skill.summon_count, _secs(skill.summon_seconds)])
	return out


## 句式里有 `%` 才填数（「定身」「晕眩」那种没有）。直接 `%` 一个不带占位符的串会报错。
static func _fill(key: String, value: float) -> String:
	var pattern: String = PBLocale.text(key)
	return pattern % value if pattern.contains("%") else pattern


static func _name_of(id: StringName, cfg: PBSimConfig) -> String:
	if id == &"" or cfg.characters == null:
		return ""
	var character: PBCharacter = cfg.characters.by_id(id)
	return PBLocale.of_character(character) if character != null else String(id)


## 秒数：先取到一位小数，是整数就不带小数点（「5 秒」不写「5.0 秒」）。
## **先取整再判**：剩余 tick 除以帧率常常差一点点不是整数（101 / 20），直接判的话满屏都是「.0」。
static func _secs(value: float) -> String:
	var tenth: float = snappedf(value, 0.1)
	return "%d" % roundi(tenth) if is_equal_approx(tenth, roundf(tenth)) else "%.1f" % tenth
