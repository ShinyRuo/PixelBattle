class_name PBSkillLoader
extends RefCounted
## 把 `data/skills/*.tres` 装成一张 [PBSkillTable]（M7-g）。
##
## 和 [PBCharacterLoader] / [PBBondLoader] 同构，两条理由也一样：
##
## - `ResourceLoader` 被 core 纯度检查明令挡住（§14）。core 只认
##   [PBSkillTable] 这个类型，不知道技能数据从哪来。
## - 报错只能在这一层做 —— 只有这里手上有 `.tres` 的路径，
##   能指出是**哪一份数据**写错了。
##
## ## 它顺带校验每一份 buff，而且没有单独的 buff 加载器
##
## [member PBSkill.on_hit] / [member PBSkill.on_self] 存的是**直接引用**
## （`ext_resource` 指向 `data/buffs/*.tres`）—— 那就是 Godot 原生的外键，
## 再套一层 id 查表等于自己发明一遍资源系统。所以 buff 是跟着技能
## 一起被读进来的，没有第二个目录要扫。
##
## 但**校验必须在这一刻做**：[method PBBuffRules.validate] 拦的两条
## （拼错的键、只写成长不写基数）**全部静默生效** ——
## 数据、界面、日志都正常，只有数字不对。装表那一刻不拦，
## 就只剩「这个技能好像没用」这一个现象可查。
##
## ## 目录不存在**不是错**
##
## 和 [PBActorLibrary] 同一条：没有 `data/skills/` 时正确的行为是
## 「一个技能都没有」，而那正是 M7-g 之前的每一天。
## 角色表打不开要 `push_error`（那一局根本没法玩），技能表打不开不用。

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


## 从指定目录装一张表。坏数据会报错并跳过那一份 —— **跳过而不是整表作废**：
## 一份写坏的技能不该让另外几个也放不出来。
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


## 这份技能连同它挂的每一份 buff 合不合法。空串 = 没问题。
##
## 两层分开报：技能自己的形状（点谁 / 打谁 / 施法延迟）由
## [method PBSkillRules.validate] 管，效果的键与成长由
## [method PBBuffRules.validate] 管。合成一句话的话，
## 报错指不出是技能写错了还是它挂的那份 buff 写错了。
static func check(skill: PBSkill) -> String:
	var why: String = PBSkillRules.validate(skill)
	if why != "":
		return why
	if skill.id == &"":
		return "技能没有 id"
	for buff: PBBuff in skill.on_hit + skill.on_self:
		var bad: String = PBBuffRules.validate(buff)
		if bad != "":
			return "它挂的效果 %s 不合法 —— %s" % [buff.id if buff != null else &"?", bad]
	return ""
