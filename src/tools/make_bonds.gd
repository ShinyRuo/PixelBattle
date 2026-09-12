extends SceneTree
## 按 `data/bonds.tsv` 重铺整张羁绊表（M10-b）。同 [i]make_roster.gd[/i]。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_bonds.gd
## ```
##
## ## 兜底羁绊全删了
##
## 原来 11 组里有 6 组是**属性型兜底**（同系 4 人 +16%）。玩家定的「羁绊全部
## 按原版文档来」把它们一起删了 —— 而那顺带拆掉了 CLAUDE.md 排第一的那条
## 结构性冲突：§09 的兜底档「按属性匹配，随便带 16 张卡也会每系摊到 2–3 个，
## **不会凑的玩家白拿 1.705×**」，而技能阶梯的定义恰恰是「会玩才拿得到」。
## 两者从同一个数值池子两头拉，删掉兜底就是把池子拆开。
##
## 所以 [enum PBBond.Match] 的属性档从此**没有数据走**。枚举值留着
## （`PBBondTable.synthetic` 的对拍曲线还在用 `EVERYONE` 档），
## 但真表里一条都不会有。
##
## ## 名字不在这个文件里
##
## 同 [i]make_roster.gd[/i]：§14 铁律 5 不许 `src/` 出现角色名，
## 而羁绊 id 另有一条 `test_no_bond_id_leaks_into_src` 钉着。

const TABLE := "res://data/bonds.tsv"
const OUT_DIR := "res://data/bonds"

const COL_ID: int = 0
const COL_NAME: int = 1
const COL_FULL: int = 2
const COL_FUNCTION: int = 3
const COL_CARRIER: int = 4
const COL_MEMBERS: int = 5
const COL_MEMBER_FX: int = 6

## 满档加成 = 本值 ×（满档人数 − 1）。
##
## **从既有的两组反推出来的**：M6-j 塌成一档之后，猪鹿蝶（3 人）是 0.28、
## 凯班（4 人）是 0.42 —— 差 0.14。所以重铺时那两组一个数都不动，
## 新加的 18 组落在同一条线上。拍一个新斜率的话，此前所有扫描结论
## （GROWTH 1.10 的锚点、装备 300 的定价）都要跟着重扫。
const POWER_PER_MEMBER: float = 0.14


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
	bond.tier_power = [POWER_PER_MEMBER * float(full - 1)] as Array[float]
	bond.tier_function_keys = [StringName(row[COL_FUNCTION])] as Array[StringName]
	bond.tier_function_carriers = [StringName(row[COL_CARRIER])] as Array[StringName]
	if row[COL_CARRIER] != "" and not members.has(StringName(row[COL_CARRIER])):
		return "%s 的载体 %s 不是本组成员" % [key, row[COL_CARRIER]]
	var trouble := _fill_members(bond, row, members)
	if trouble != "":
		return "%s 的成员效果：%s" % [key, trouble]

	var err := ResourceSaver.save(bond, "%s/%s.tres" % [OUT_DIR, key])
	return "" if err == OK else "%s 存不下来（%d）" % [key, err]


## 「每个在场成员各拿自己那一份」那张表（M12-d1）。**返回错误信息，空串 = 成功。**
##
## 两个来源汇进同一张表：
##
## - **`功能键` 那一列点到触发型那四个时，翻译成载体本人的一份**
##   （量取 [constant PBBondFunctionRules.CARRIER_AMOUNTS]，**一个数都没动**）。
##   M10-d 时它们走的是 `Landing.CARRIER`，那一档 M12-d1 去掉了 ——
##   留着两条路的话「羁绊给的溅射」会有两个来源，而两个来源迟早不一样大。
## - **`成员效果` 那一列**：`角色id:键=量,键=量;角色id:...`，
##   这才是原版的形状（45 组里只有 3 组是人人同一句）。
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
			if not PBPassiveRules.is_known(name):
				return "不认识的键「%s」" % name
			mine[name] = float(kv[1].strip_edges())
		out[who] = mine
	bond.member_functions = out
	return ""


## 表里没有的 `.tres` 一律删掉 —— 6 组属性型兜底就是这样离场的。
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
