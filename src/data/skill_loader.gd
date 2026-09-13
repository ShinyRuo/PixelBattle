class_name PBSkillLoader
extends RefCounted
## 把 `data/skills/*.tres` 装成一张 [PBSkillTable]。与 [PBCharacterLoader] 同构。
##
## **顺带校验每一份 buff**，没有单独的 buff 加载器：[member PBSkill.on_hit] / [member PBSkill.on_self] 存直接引用，
## buff 跟着技能一起读进来。校验必须在这一刻做 —— [method PBBuffRules.validate] 拦的错全部静默生效。
##
## **目录不存在不是错**：没有 `data/skills/` 就是「一个技能都没有」。

const DIR := "res://data/skills"

static var _cached: PBSkillTable = null


## 全部技能。第一次调用读盘，之后走缓存。
static func table() -> PBSkillTable:
	if _cached == null:
		_cached = load_from(DIR)
	return _cached


## 把技能表装进一份配置。返回同一个 [param cfg]，方便串写。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	cfg.skills = table()
	return cfg


## 从指定目录装一张表。坏数据报错并跳过那一份 —— **不整表作废**，一份写坏的技能不该让别的也放不出来。
static func load_from(dir_path: String) -> PBSkillTable:
	var out := PBSkillTable.new()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out

	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var skill := load(path) as PBSkill
		if skill == null:
			push_error("这份技能数据装不进来（不是 PBSkill？）：%s" % path)
			continue
		var why: String = check(skill)
		if why != "":
			push_error("这份技能数据不合法：%s —— %s" % [path, why])
			continue
		if not out.add(skill):
			push_error("这份技能数据被拒收（id 空或重复）：%s" % path)
	return out


## 放出去屏幕上真的什么都不会发生吗。伤害、效果、**召唤**都算「有事发生」——
## 这条守的是「放出去要有事发生」，不是「必须有伤害」。
static func _does_nothing(skill: PBSkill) -> bool:
	if skill.power_mult > 0.0 or skill.summon_count > 0:
		return false
	return skill.on_hit.is_empty() and skill.on_self.is_empty()


## 这份技能连同它挂的每一份 buff 合不合法。空串 = 没问题。
##
## 两层分开报：技能的形状由 [method PBSkillRules.validate] 管，效果的键与成长由 [method PBBuffRules.validate] 管 ——
## 合成一句话的话指不出是技能写错了还是 buff 写错了。只对 `.tres` 成立的几条拦在这一层
## （大招是代码现造的，必须直接写 `damage`）。
static func check(skill: PBSkill) -> String:
	var why: String = PBSkillRules.validate(skill)
	if why != "":
		return why
	if skill.id == &"":
		return "技能没有 id"
	# **写了也不生效**：建人那一刻 [method PBCombatRules._equip_skills]
	# 会按 `power_mult` 算出来覆盖掉它。而「配了不生效」比「配不了」难查 ——
	# 数据、界面、日志全正常，只有伤害数字不对。
	if skill.damage != 0.0:
		return "别在数据里写 damage，写 power_mult —— 那个数会在建人时被覆盖"
	if _does_nothing(skill):
		# 既不打伤害、也不挂效果、还不召人的技能，放出去屏幕上什么都不会发生。
		return "这个技能既没有 power_mult、也没有效果、还不召人 —— 放出去什么都不会发生"
	for buff: PBBuff in skill.on_hit + skill.on_self:
		var bad: String = PBBuffRules.validate(buff)
		if bad != "":
			return "它挂的效果 %s 不合法 —— %s" % [buff.id if buff != null else &"?", bad]
	return ""
