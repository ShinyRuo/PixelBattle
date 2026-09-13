extends SceneTree
## 按 `data/buffs.tsv` + `data/skills.tsv` 重铺技能与效果。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_skills.gd
## ```
##
## 手写一百多个 `.tres` 等于抄一百多遍样板，少一个字段就是取默认值，表现是「这个技能好像没什么用」。
## 和 `make_roster.gd` / `make_bonds.gd` 同一套：表在 `data/`，生成器只认列号，名字不进 `src/`（铁律 5）。
##
## **它是「谁有哪几个技能」的唯一来源**：表里的角色键反写进 `data/characters/<键>.tres` 的 `skill_ids`，
## **表里没有的角色会被清空** —— 只写不清的话，删掉的技能格子还在，按下去查一个不存在的 id。
##
## **不认识的额外键直接 `quit(1)`**：跳过的表现正是「配了不生效」。

const BUFFS := "res://data/buffs.tsv"
const SKILLS := "res://data/skills.tsv"
const BUFF_DIR := "res://data/buffs"
const SKILL_DIR := "res://data/skills"
const CHAR_DIR := "res://data/characters"

const BUFF_COLUMNS: int = 7
const B_KEY: int = 0
const B_NAME: int = 1
const B_KIND: int = 2
const B_SIDE: int = 3
const B_DURATION: int = 4
const B_PERIOD: int = 5
const B_MODS: int = 6

const SKILL_COLUMNS: int = 11
const S_KEY: int = 0
const S_OWNER: int = 1
const S_NAME: int = 2
const S_ELEMENT: int = 3
const S_TARGET: int = 4
const S_AFFECTS: int = 5
const S_POWER: int = 6
const S_RADIUS: int = 7
const S_COOLDOWN: int = 8
const S_MANA: int = 9
const S_EXTRA: int = 10

const KINDS := {
	"瞬间": PBBuff.Kind.INSTANT,
	"持续": PBBuff.Kind.DURATION,
	"周期": PBBuff.Kind.PERIODIC,
}

const SIDES := {"增益": true, "减益": false}

const TARGETS := {
	"不用点": PBSkill.Target.NONE,
	"点队友": PBSkill.Target.ALLY,
	"点敌人": PBSkill.Target.ENEMY,
	"点地面": PBSkill.Target.GROUND,
}

const AFFECTS := {"我方": PBSkill.Party.ALLIES, "敌方": PBSkill.Party.ENEMIES}

const ELEMENTS := {
	"火": PBElement.Type.FIRE,
	"风": PBElement.Type.WIND,
	"雷": PBElement.Type.THUNDER,
	"土": PBElement.Type.EARTH,
	"水": PBElement.Type.WATER,
	"物理": PBElement.Type.PHYSICAL,
	"仙": PBElement.Type.SAGE,
}

## `额外` 那一列认得的键。**改这里要连着表头的注释一起改。**
const EXTRA_KEYS: Array[String] = [
	"on_hit",
	"on_self",
	"delay",
	"fly",
	"targets",
	"gather",
	"knockback",
	"slow",
	"slow_secs",
	"carry",
	"summon",
	"summon_power",
	"summon_hp",
	"summon_secs",
]

var _buffs: Dictionary = {}


func _init() -> void:
	var buff_rows := _read(BUFFS, BUFF_COLUMNS)
	var skill_rows := _read(SKILLS, SKILL_COLUMNS)
	if buff_rows.is_empty() or skill_rows.is_empty():
		printerr("表是空的，检查 %s / %s" % [BUFFS, SKILLS])
		quit(1)
		return
	for row: PackedStringArray in buff_rows:
		var err := _write_buff(row)
		if err != "":
			printerr(err)
			quit(1)
			return
	var owned: Dictionary = {}
	for row: PackedStringArray in skill_rows:
		var err := _write_skill(row, owned)
		if err != "":
			printerr(err)
			quit(1)
			return
	print("写好 ", buff_rows.size(), " 份效果、", skill_rows.size(), " 个技能")
	_sweep(BUFF_DIR, _keys(buff_rows))
	_sweep(SKILL_DIR, _keys(skill_rows))
	_attach(owned)
	quit(0)


## 读一张表。空行和 `#` 开头的行跳过，列数不够整行不要。
func _read(path: String, columns: int) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var out: Array = []
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		if cells.size() < columns:
			printerr("这一行少了列（要 %d，实际 %d）：%s" % [columns, cells.size(), trimmed])
			continue
		out.append(cells)
	return out


func _keys(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row: PackedStringArray in rows:
		out[row[0]] = true
	return out


## `键=基数` 或 `键=基数+成长`，`;` 隔开。返回 `[基数表, 成长表]`。
func _parse_mods(text: String) -> Array:
	var base: Dictionary = {}
	var growth: Dictionary = {}
	for piece: String in text.split(";"):
		var one: String = piece.strip_edges()
		if one == "":
			continue
		var halves: PackedStringArray = one.split("=")
		if halves.size() != 2:
			return []
		var key := StringName(halves[0].strip_edges())
		var value: String = halves[1].strip_edges()
		var parts: PackedStringArray = value.split("+")
		base[key] = float(parts[0])
		if parts.size() > 1:
			growth[key] = float(parts[1])
	return [base, growth]


func _write_buff(row: PackedStringArray) -> String:
	var key: String = row[B_KEY]
	if not KINDS.has(row[B_KIND]):
		return "%s 的档不认识：%s" % [key, row[B_KIND]]
	if not SIDES.has(row[B_SIDE]):
		return "%s 的善恶不认识：%s" % [key, row[B_SIDE]]
	var parsed := _parse_mods(row[B_MODS])
	if parsed.is_empty():
		return "%s 的效果写歪了：%s" % [key, row[B_MODS]]

	var buff := PBBuff.new()
	buff.id = StringName(key)
	buff.name_key = "buff.%s" % key
	buff.icon_key = "buff.%s" % key
	buff.kind = KINDS[row[B_KIND]]
	buff.friendly = SIDES[row[B_SIDE]]
	buff.duration_seconds = float(row[B_DURATION])
	buff.period_seconds = float(row[B_PERIOD])
	buff.mods = parsed[0]
	buff.mods_growth = parsed[1]

	# **词汇表那一关走 `PBBuffRules.validate`，不在这里另写一份。**
	# 两处各判各的话，「这个键认不认」迟早分叉，而分叉的那一侧静默生效。
	var bad := PBBuffRules.validate(buff)
	if bad != "":
		return "%s：%s" % [key, bad]

	var err := ResourceSaver.save(buff, "%s/%s.tres" % [BUFF_DIR, key])
	if err != OK:
		return "%s 存不下来（%d）" % [key, err]
	_buffs[key] = buff
	return ""


## 三个枚举列一起查。收在一处是为了让 `_write_skill` 待在 gdlint
## 的 6 个 return 上限内 —— 那条上限指的地方是对的：一串平铺的
## 「不认识就返回」本来就是同一件事。
func _check_enums(row: PackedStringArray) -> String:
	var checks: Array = [
		[ELEMENTS, row[S_ELEMENT], "属性"],
		[TARGETS, row[S_TARGET], "「点什么」"],
		[AFFECTS, row[S_AFFECTS], "「落在谁」"],
	]
	for one: Array in checks:
		var table: Dictionary = one[0]
		if not table.has(one[1]):
			return "的%s不认识：%s" % [one[2], one[1]]
	return ""


func _write_skill(row: PackedStringArray, owned: Dictionary) -> String:
	var key: String = row[S_KEY]
	var bad := _check_enums(row)
	if bad != "":
		return "%s %s" % [key, bad]

	var skill := PBSkill.new()
	skill.id = StringName(key)
	skill.name_key = "skill.%s" % key
	skill.element = ELEMENTS[row[S_ELEMENT]]
	skill.target = TARGETS[row[S_TARGET]]
	skill.affects = AFFECTS[row[S_AFFECTS]]
	skill.power_mult = float(row[S_POWER])
	skill.radius = float(row[S_RADIUS])
	skill.cooldown_ticks = _ticks(float(row[S_COOLDOWN]))
	skill.mp_cost = float(row[S_MANA])

	bad = _apply_extra(skill, row[S_EXTRA])
	if bad != "":
		return "%s 的额外那一列：%s" % [key, bad]

	# 校验走加载器那一份（它拦「写了 damage」和「什么都不做的技能」两条）。
	bad = PBSkillLoader.check(skill)
	if bad != "":
		return "%s：%s" % [key, bad]

	var err := ResourceSaver.save(skill, "%s/%s.tres" % [SKILL_DIR, key])
	if err != OK:
		return "%s 存不下来（%d）" % [key, err]
	var owner_key: String = row[S_OWNER]
	if not owned.has(owner_key):
		owned[owner_key] = PackedStringArray()
	owned[owner_key].append(key)
	return ""


## `键=值;键=值`。**不认识的键返回错误，不跳过。**
func _apply_extra(skill: PBSkill, text: String) -> String:
	for piece: String in text.split(";"):
		var one: String = piece.strip_edges()
		if one == "":
			continue
		var halves: PackedStringArray = one.split("=")
		if halves.size() != 2:
			return "写歪了：%s" % one
		var name: String = halves[0].strip_edges()
		var value: String = halves[1].strip_edges()
		if not EXTRA_KEYS.has(name):
			return "不认识的键：%s（认得的：%s）" % [name, ", ".join(EXTRA_KEYS)]
		match name:
			"on_hit", "on_self":
				var list: Array[PBBuff] = []
				for one_key: String in value.split(","):
					var buff_key: String = one_key.strip_edges()
					if not _buffs.has(buff_key):
						return "查不到效果：%s" % buff_key
					list.append(_buffs[buff_key])
				if name == "on_hit":
					skill.on_hit = list
				else:
					skill.on_self = list
			"delay":
				skill.delay_ticks = _ticks(float(value))
			"fly":
				skill.shot_cross_seconds = float(value)
			"targets":
				skill.max_targets = int(value)
			"gather":
				skill.gather = value != "0"
			"knockback":
				skill.knockback = float(value)
			"slow":
				skill.slow_scale = float(value)
			"slow_secs":
				skill.slow_ticks = _ticks(float(value))
			"summon":
				skill.summon_count = int(value)
			"summon_power":
				skill.summon_power = float(value)
			"summon_hp":
				skill.summon_hp_share = float(value)
			"summon_secs":
				skill.summon_seconds = float(value)
			"carry":
				skill.carry_over_ticks = _ticks(float(value))
	return ""


## 秒换 tick。**至少 1** —— 0 tick 的窗口等于没有这一段。
func _ticks(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	return maxi(int(round(seconds * float(PBSimConfig.new().tick_rate))), 1)


## 把「谁有哪几个技能」写回角色表。**表里没有的角色一律清空。**
func _attach(owned: Dictionary) -> void:
	var dir := DirAccess.open(CHAR_DIR)
	if dir == null:
		printerr("打不开 %s" % CHAR_DIR)
		return
	var touched: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var key: String = file_name.get_basename()
		var path: String = "%s/%s" % [CHAR_DIR, file_name]
		var character: PBCharacter = ResourceLoader.load(path) as PBCharacter
		if character == null:
			continue
		var want: Array[StringName] = []
		for one: String in owned.get(key, PackedStringArray()):
			want.append(StringName(one))
		if character.skill_ids == want:
			continue
		character.skill_ids = want
		ResourceSaver.save(character, path)
		touched += 1
	print("角色表更新了 ", touched, " 个的 skill_ids")


## 表里没有的 `.tres` 一律删掉，否则拿走的技能文件会一直被加载器扫进来。
func _sweep(folder: String, wanted: Dictionary) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		if wanted.has(file_name.get_basename()):
			continue
		dir.remove(file_name)
		print("删掉表上没有的：", file_name.get_basename())
