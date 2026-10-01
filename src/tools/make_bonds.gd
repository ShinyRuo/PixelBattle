extends SceneTree
## 按 `data/bonds.tsv` 重铺整张羁绊表。同 [i]make_roster.gd[/i]。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_bonds.gd
## ```
##
## 真表里没有属性型兜底羁绊：[enum PBBond.Match] 的属性档没有数据走，枚举值留着给合成表。
## 名字不在这个文件里（铁律 5），羁绊 id 另有 `test_no_bond_id_leaks_into_src` 钉着。

const TABLE := "res://data/bonds.tsv"
const OUT_DIR := "res://data/bonds"

const COL_ID: int = 0
const COL_NAME: int = 1
const COL_FULL: int = 2
const COL_FUNCTION: int = 3
const COL_CARRIER: int = 4
const COL_MEMBERS: int = 5
const COL_MEMBER_FX: int = 6
const COL_PATCHES: int = 7
const COL_BUFFS: int = 8

func _init() -> void:
	var rows := _read_table()
	if rows.is_empty():
		printerr("羁绊表是空的：%s" % TABLE)
		quit(1)
		return
	var wanted: Dictionary = {}
	for row: PackedStringArray in rows:
		var err := _write_one(row)
		if err != "":
			printerr(err)
			quit(1)
			return
		wanted[row[COL_ID]] = true
	print("写好 ", rows.size(), " 组羁绊")
	_sweep(wanted)
	quit(0)


func _read_table() -> Array:
	var text := FileAccess.get_file_as_string(TABLE)
	var out: Array = []
	for line: String in text.split("\n"):
		# **只掐掉行尾**，不掐行首 —— 功能键那两列是空的，
		# `strip_edges` 会把行尾连续的两个 Tab 一起吃掉，列号就错位了。
		var trimmed: String = line.rstrip("\r\n")
		if trimmed.strip_edges() == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		if cells.size() < 6:
			printerr("这一行少了列（要 6 列，实际 %d）：%s" % [cells.size(), trimmed])
			continue
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		out.append(cells)
	return out


## 铺一组羁绊。**返回错误信息，空串 = 成功。**
func _write_one(row: PackedStringArray) -> String:
	var key: String = row[COL_ID]
	var members: Array[StringName] = []
	for one: String in row[COL_MEMBERS].split(","):
		var member: String = one.strip_edges()
		if member != "":
			members.append(StringName(member))
	var full: int = int(row[COL_FULL])
	if full <= 0 or full > members.size():
		return "%s 的满档人数 %d 装不进 %d 个成员" % [key, full, members.size()]

	var bond := PBBond.new()
	bond.id = StringName(key)
	bond.name_key = "bond.%s" % key
	# **一律按成员点名**，不用属性档 —— 见类顶部。
	bond.match_mode = PBBond.Match.MEMBERS
	bond.member_ids = members
	bond.tier_counts = [full] as Array[int]
	# 原版 §6 没有按羁绊人数统一增加输出；此档只用于激活成员专属效果。
	bond.tier_power = [0.0] as Array[float]
	bond.tier_function_keys = [StringName(row[COL_FUNCTION])] as Array[StringName]
	bond.tier_function_carriers = [StringName(row[COL_CARRIER])] as Array[StringName]
	if row[COL_CARRIER] != "" and not members.has(StringName(row[COL_CARRIER])):
		return "%s 的载体 %s 不是本组成员" % [key, row[COL_CARRIER]]
	var trouble := _fill_members(bond, row, members)
	if trouble != "":
		return "%s 的成员效果：%s" % [key, trouble]
	var bad := _fill_patches(bond, row, members)
	if bad != "":
		return "%s 的技能补丁：%s" % [key, bad]

	var err := ResourceSaver.save(bond, "%s/%s.tres" % [OUT_DIR, key])
	return "" if err == OK else "%s 存不下来（%d）" % [key, err]


## 「每个在场成员各拿自己那一份」那张表。**返回错误信息，空串 = 成功。** 两个来源汇进同一张表：
##
## - **`功能键` 那一列点到触发型那几个时，翻译成载体本人的一份**（量取 [constant PBBondFunctionRules.CARRIER_AMOUNTS]）——
##   只有一条路，否则「羁绊给的溅射」有两个来源，迟早不一样大。
## - **`成员效果` 那一列**：`角色id:键=量,键=量;角色id:...`（原版的形状）。
func _fill_members(bond: PBBond, row: PackedStringArray, members: Array) -> String:
	var out: Dictionary = {}
	var key := StringName(row[COL_FUNCTION])
	if PBBondFunctionRules.CARRIER_AMOUNTS.has(key):
		out[StringName(row[COL_CARRIER])] = {key: PBBondFunctionRules.CARRIER_AMOUNTS[key]}
	var cell: String = row[COL_MEMBER_FX] if row.size() > COL_MEMBER_FX else ""
	for chunk: String in cell.split(";", false):
		var half: PackedStringArray = chunk.split(":")
		if half.size() != 2:
			return "「%s」不是 角色id:键=量 的样子" % chunk
		var who := StringName(half[0].strip_edges())
		if not members.has(who):
			return "「%s」不是本组成员" % who
		var mine: Dictionary = out.get(who, {})
		for pair: String in half[1].split(",", false):
			var kv: PackedStringArray = pair.split("=")
			if kv.size() != 2:
				return "「%s」不是 键=量 的样子" % pair
			var name := StringName(kv[0].strip_edges())
			if not PBModRules.is_known(name):
				return "不认识的键「%s」" % name
			mine[name] = float(kv[1].strip_edges())
		out[who] = mine
	bond.member_functions = out
	return ""


## 「每个在场成员各自的技能补丁」那张表。**返回错误信息，空串 = 成功。**
## 列的写法：`角色id:技能id:键=量,键=量;角色id:技能id:...`。词汇表见 [PBSkillPatchRules]，
## **不认识的键直接报错退出** —— 静默跳过的表现正是「配了不生效」。
func _fill_patches(bond: PBBond, row: PackedStringArray, members: Array) -> String:
	var buff_error := _fill_buffs(bond, row)
	if buff_error != "":
		return buff_error
	return _parse_patches(bond, row, members)


func _parse_patches(bond: PBBond, row: PackedStringArray, members: Array) -> String:
	var cell: String = row[COL_PATCHES] if row.size() > COL_PATCHES else ""
	if cell == "":
		return ""
	var out: Dictionary = {}
	for chunk: String in cell.split(";", false):
		var part: PackedStringArray = chunk.split(":")
		if part.size() != 3:
			return "「%s」不是 角色id:技能id:键=量 的样子" % chunk
		var who := StringName(part[0].strip_edges())
		if not members.has(who):
			return "「%s」不是本组成员" % who
		var skill_id := StringName(part[1].strip_edges())
		var mine: Dictionary = out.get(who, {})
		var theirs: Dictionary = mine.get(skill_id, {})
		for pair: String in part[2].split(",", false):
			var kv: PackedStringArray = pair.split("=")
			if kv.size() != 2:
				return "「%s」不是 键=量 的样子" % pair
			var name := StringName(kv[0].strip_edges())
			if not PBSkillPatchRules.is_known(name):
				return "不认识的补丁键「%s」" % name
			theirs[name] = float(kv[1].strip_edges())
		mine[skill_id] = theirs
		out[who] = mine
	bond.member_skill_patches = out
	return ""


func _fill_buffs(bond: PBBond, row: PackedStringArray) -> String:
	if row.size() <= COL_BUFFS or row[COL_BUFFS] == "":
		return ""
	for chunk: String in row[COL_BUFFS].split(";", false):
		var pair := chunk.split(":")
		if pair.size() != 2:
			return "开场效果格式应为 成员:buff键,buff键"
		var buffs: Array[PBBuff] = []
		for id: String in pair[1].split(",", false):
			var path := "res://data/buffs/%s.tres" % id
			if not ResourceLoader.exists(path) or not load(path) is PBBuff:
				return "开场 BUFF 资源不存在：%s" % id
			buffs.append(load(path) as PBBuff)
		bond.member_buffs[StringName(pair[0])] = buffs
	return PBBondBuffRules.validate(bond)


## 表里没有的 `.tres` 一律删掉。
func _sweep(wanted: Dictionary) -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var key: String = file_name.get_basename()
		if wanted.has(key):
			continue
		dir.remove(file_name)
		print("删掉表上没有的：", key)
