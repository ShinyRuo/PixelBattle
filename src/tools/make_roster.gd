extends SceneTree
## 按 `data/roster.tsv` 重铺整张角色表。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_roster.gd
## ```
##
## **不抄一遍规则**：换算直接调规则层（[method PBStatRules.apply_original_scale]）。
## **名字不在这个文件里**（铁律 5，`tests/test_character_data.gd` 扫整个 `src/`、注释也算），这里只认列号。
## 列号在 [PBRosterSheet]；`skill_ids` 由 `make_skills.gd` 维护，重铺时从旧文件读回来。

const ROSTER := PBRosterSheet.PATH
const OUT_DIR := "res://data/characters"
const ACTOR_DIR := "res://data/actors"
const BUFF_DIR := "res://data/buffs"

## 被动那一列里指一份效果的写法。其余的键全是 `键=量`。
const ON_HIT := "on_hit"

const PRIMARIES := {
	"力量": PBCharacter.Primary.STRENGTH,
	"敏捷": PBCharacter.Primary.AGILITY,
	"智力": PBCharacter.Primary.INTELLECT,
}

const RARITIES := {"R": PBUnit.Rarity.R, "SR": PBUnit.Rarity.SR, "SSR": PBUnit.Rarity.SSR}
const REACHES := {"近战": PBCharacter.Reach.MELEE, "远程": PBCharacter.Reach.RANGED}
const ELEMENTS := {
	"火": PBElement.Type.FIRE,
	"风": PBElement.Type.WIND,
	"雷": PBElement.Type.THUNDER,
	"土": PBElement.Type.EARTH,
	"水": PBElement.Type.WATER,
	"物理": PBElement.Type.PHYSICAL,
	"仙": PBElement.Type.SAGE,
}


func _init() -> void:
	var rows := _read_roster()
	if rows.is_empty():
		printerr("名册是空的：%s" % ROSTER)
		quit(1)
		return
	var wanted: Dictionary = {}
	for row: PackedStringArray in rows:
		var err := _write_one(row)
		if err != "":
			printerr(err)
			quit(1)
			return
		wanted[row[PBRosterSheet.COL_ID]] = true
	print("写好 ", rows.size(), " 个角色")
	_sweep(wanted)
	quit(0)


## 读名册（[PBRosterSheet]）。**列数不够的行整行不要**，并且说出来。
func _read_roster() -> Array:
	var out: Array = []
	for cells: PackedStringArray in PBRosterSheet.read(ROSTER).rows():
		if cells.size() < PBRosterSheet.COLUMNS:
			printerr(
				"这一行少了列（要 %d 列，实际 %d）：%s"
				% [PBRosterSheet.COLUMNS, cells.size(), "\t".join(cells)]
			)
			continue
		out.append(cells)
	return out


## 铺一个角色。**返回错误信息，空串 = 成功。**
func _write_one(row: PackedStringArray) -> String:
	var key: String = row[PBRosterSheet.COL_ID]
	var path: String = "%s/%s.tres" % [OUT_DIR, key]
	var character := PBCharacter.new()
	# `skill_ids` 从旧文件里捞回来（由 `make_skills.gd` 维护）。`actor_key` 只从名册读 ——
	# 两处都能给的话，删掉 `data/characters/` 重跑一次会得到不同的结果。
	var old: PBCharacter = null
	if ResourceLoader.exists(path):
		old = ResourceLoader.load(path) as PBCharacter
	if old != null:
		character.skill_ids = old.skill_ids.duplicate()

	character.id = StringName(key)
	character.name_key = "char.%s" % key
	character.icon_key = key

	# 形象键：名册那一列写 `-` 就按角色键找。**盘上没有就留空** ——
	# 留一个查不到的键和留空是同一个结果（退回白模），
	# 但留空时预览台的信息栏会照实说「来源：白模兜底」。
	var actor: String = row[PBRosterSheet.COL_ACTOR]
	if actor == PBRosterSheet.NONE or actor == "":
		actor = key
	if ResourceLoader.exists("%s/%s.tres" % [ACTOR_DIR, actor]):
		character.actor_key = StringName(actor)
	character.shot_key = PBRosterSheet.shot_key_of(row[PBRosterSheet.COL_SHOT])
	character.attack_range = float(row[PBRosterSheet.COL_RANGE])

	var bad := _row_error(row)
	if bad != "":
		return "%s %s" % [key, bad]
	character.rarity = RARITIES[row[PBRosterSheet.COL_RARITY]]
	character.reach = REACHES[row[PBRosterSheet.COL_REACH]]
	character.element = ELEMENTS[row[PBRosterSheet.COL_ATTACK]]
	character.def_element = ELEMENTS[row[PBRosterSheet.COL_DEFENCE]]
	character.primary = PRIMARIES[row[PBRosterSheet.COL_PRIMARY]]

	# 三围与成长是**数据**，逐个从名册读。
	character.strength = float(row[PBRosterSheet.COL_STR])
	character.agility = float(row[PBRosterSheet.COL_AGI])
	character.intellect = float(row[PBRosterSheet.COL_INT])
	character.strength_growth = float(row[PBRosterSheet.COL_STR_GROW])
	character.agility_growth = float(row[PBRosterSheet.COL_AGI_GROW])
	character.intellect_growth = float(row[PBRosterSheet.COL_INT_GROW])

	# **换算走规则层那一份，不在这里再算一遍**。也**不调 `fill_placeholder`**：它会按稀有度覆盖三围、
	# 把 DPS 拉回阶梯，刚读进来的三围在最后一步被抹平，而属性栏里每个数都对、不报错。
	PBStatRules.apply_original_scale(character, float(row[PBRosterSheet.COL_INTERVAL]))

	var trouble := _fill_passives(character, row[PBRosterSheet.COL_PASSIVE])
	if trouble != "":
		return "%s 的被动：%s" % [key, trouble]

	var err := ResourceSaver.save(character, path)
	return "" if err == OK else "%s 存不下来（%d）" % [key, err]


## 这一行里查表的那几格（稀有度、攻击距离、攻防属性、主属性、射程、普攻子弹）有没有不认识的值。
## **返回错误信息，空串 = 没有。**
##
## 普攻子弹**填了却找不到就报错**，和形象键相反：形象缺了是素材还没画，
## 子弹键是人在表里（或面板里）亲手填的，找不到只能是填错了。
func _row_error(row: PackedStringArray) -> String:
	if not RARITIES.has(row[PBRosterSheet.COL_RARITY]):
		return "的稀有度不认识：%s" % row[PBRosterSheet.COL_RARITY]
	if not REACHES.has(row[PBRosterSheet.COL_REACH]):
		return "的攻击距离不认识：%s" % row[PBRosterSheet.COL_REACH]
	var attack: String = row[PBRosterSheet.COL_ATTACK]
	var defence: String = row[PBRosterSheet.COL_DEFENCE]
	if not ELEMENTS.has(attack) or not ELEMENTS.has(defence):
		return "的攻/防属性不认识：%s / %s" % [attack, defence]
	if not PRIMARIES.has(row[PBRosterSheet.COL_PRIMARY]):
		return "的主属性不认识：%s" % row[PBRosterSheet.COL_PRIMARY]
	# 射程必须是正数：填成 0 或者写错成字的话 `float()` 给 0，那个人就站在怪堆里一发都打不出去，而它不报错。
	var range_cell: String = row[PBRosterSheet.COL_RANGE]
	if not range_cell.is_valid_float() or float(range_cell) <= 0.0:
		return "的射程不是正数：%s（填原版码数，近战 125、远程 600）" % range_cell
	var shot := PBRosterSheet.shot_error(row[PBRosterSheet.COL_SHOT])
	return "" if shot == "" else "的普攻子弹：%s" % shot


## 把被动那一列的两半都填进去（`键=量` 进 [member PBCharacter.passives]，
## `on_hit=<效果键>` 进 [member PBCharacter.on_hit_buffs]）。**返回错误信息，空串 = 成功。**
func _fill_passives(character: PBCharacter, cell: String) -> String:
	var passives: Variant = _parse_passives(cell)
	if passives is String:
		return passives
	var hung: Variant = _parse_on_hit(cell)
	if hung is String:
		return hung
	character.passives = passives as Dictionary
	character.on_hit_buffs = hung as Array[PBBuff]
	return ""


## 被动那一列：`键=量;键=量`，`-` 或空 = 没有。返回 [Dictionary] = 成功，[String] = 错误信息。
##
## **不认识的键在这里报错，不静默跳过**（静默的表现正是「配了不生效」）。规则层那边只是不装、不报错 ——
## 战斗中途 `push_error` 没人看得见，两处各拦一次就是两把尺子。
func _parse_passives(cell: String) -> Variant:
	var out: Dictionary = {}
	if cell == "" or cell == PBRosterSheet.NONE:
		return out
	for piece: String in cell.split(";", false):
		var pair: PackedStringArray = piece.split("=")
		if pair.size() != 2:
			return "「%s」不是 键=量 的样子" % piece
		var name := StringName(pair[0].strip_edges())
		# `on_hit=` 那几个由 [method _parse_on_hit] 收，这里跳过。
		if name == ON_HIT:
			continue
		if not PBModRules.is_known(name):
			return "不认识的键「%s」" % name
		if out.has(name):
			return "键「%s」写了两遍" % name
		out[name] = float(pair[1].strip_edges())
	return out


## 被动那一列里的 `on_hit=<效果键>`。返回 [Array] = 成功，[String] = 错误信息。
## **查不到那份效果就报错退出**。效果由 `make_skills.gd` 从 `data/buffs.tsv` 铺出来，所以那一支要先跑。
func _parse_on_hit(cell: String) -> Variant:
	var out: Array[PBBuff] = []
	if cell == "" or cell == PBRosterSheet.NONE:
		return out
	for piece: String in cell.split(";", false):
		var pair: PackedStringArray = piece.split("=")
		if pair.size() != 2 or pair[0].strip_edges() != ON_HIT:
			continue
		var path: String = "%s/%s.tres" % [BUFF_DIR, pair[1].strip_edges()]
		if not ResourceLoader.exists(path):
			return "挂不上、查不到的效果「%s」" % pair[1].strip_edges()
		out.append(ResourceLoader.load(path) as PBBuff)
	return out


## 名册里没有的 `.tres` 一律删掉 —— 生成器只写不删的话，「删掉某个角色」这件事做不到。
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
		print("删掉名册上没有的：", key)
