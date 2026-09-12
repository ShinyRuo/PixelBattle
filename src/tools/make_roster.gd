extends SceneTree
## 按 `data/roster.tsv` 重铺整张角色表（M10-b）。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_roster.gd
## ```
##
## ## 为什么要有这个工具
##
## 30 个 `.tres` 原来是一次性脚本铺的，而**那个脚本没进仓库**（在 gitignore
## 的 `build/` 里）。于是「稀有度阶梯改了要重跑生成脚本」这句话在
## [member PBSimConfig.rarity_power] 顶上写着，却没有脚本可跑 ——
## 补名册的时候只剩手写四十几个文件这一条路。
##
## ## 它不再抄一遍规则
##
## 老脚本是 PowerShell/Python 写的，所以战力那一段在
## [method PBStatRules.fill_placeholder] 之外**又实现了一份**，
## CLAUDE.md 因此有一句「规则与生成脚本逐条相同，改一边就要改另一边」。
## 这一版是 GDScript，直接调那个函数 —— **那句话从此作废**。
##
## ## 名字不在这个文件里
##
## §14 铁律 5：`src/` 不出现角色名，而 `tests/test_character_data.gd`
## 扫的是整个 `src/`、注释也算。名册住在 `data/roster.tsv`，
## 这里只认列号（同 [PBPortraitForge] 读 `aires/headshots.txt`）。
##
## ## 已经填过的三样不覆盖
##
## `actor_key`（接过战场素材的）、`icon_key`、`skill_ids`（M7-g 挂上去的）
## 是**人工填的**，重铺时从旧文件里读回来。覆盖掉的表现是
## 「重跑一次生成器，接好的素材全变回白模」，而它不报错。

const ROSTER := "res://data/roster.tsv"
const OUT_DIR := "res://data/characters"
const ACTOR_DIR := "res://data/actors"

## 表头那十四列的列号。**列号只在这里出现一次** —— 散在下面的话，
## 名册加一列时改漏一处会读到相邻那一栏，而它照样是个合法的数。
const COL_ID: int = 0
const COL_NAME: int = 1
const COL_RARITY: int = 2
const COL_REACH: int = 3
const COL_ATTACK: int = 4
const COL_DEFENCE: int = 5
const COL_PRIMARY: int = 6
const COL_STR: int = 7
const COL_AGI: int = 8
const COL_INT: int = 9
const COL_STR_GROW: int = 10
const COL_AGI_GROW: int = 11
const COL_INT_GROW: int = 12
const COL_INTERVAL: int = 13
const COL_ACTOR: int = 14
const COL_PASSIVE: int = 15

## 表一共几列。少一列就整行不要 —— 用默认值兜底的表现是
## 「那个角色的三围全是 0」，而 0 力量算出来是一个合法的血量。
const COLUMNS: int = 16

## 形象键那一列写这个 = 和角色键同名；被动那一列写这个 = 没有被动。
const SAME_AS_ID := "-"

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
		wanted[row[COL_ID]] = true
	print("写好 ", rows.size(), " 个角色")
	_sweep(wanted)
	quit(0)


## 读名册。**空行和 `#` 开头的行跳过**，同 `aires/headshots.txt` 的规矩。
func _read_roster() -> Array:
	var text := FileAccess.get_file_as_string(ROSTER)
	var out: Array = []
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		if cells.size() < COLUMNS:
			printerr("这一行少了列（要 %d 列，实际 %d）：%s" % [COLUMNS, cells.size(), trimmed])
			continue
		out.append(cells)
	return out


## 铺一个角色。**返回错误信息，空串 = 成功。**
func _write_one(row: PackedStringArray) -> String:
	var key: String = row[COL_ID]
	var path: String = "%s/%s.tres" % [OUT_DIR, key]
	var character := PBCharacter.new()
	# `skill_ids` 是人工挂的（M7-g），从旧文件里捞回来。
	# **`actor_key` 不再从旧文件读** —— M12-b 把那份映射搬进名册最后一列了，
	# 两处都能给的话，删掉 `data/characters/` 重跑一次就会得到不同的结果。
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
	var actor: String = key
	if row.size() > COL_ACTOR and row[COL_ACTOR] != SAME_AS_ID and row[COL_ACTOR] != "":
		actor = row[COL_ACTOR]
	if ResourceLoader.exists("%s/%s.tres" % [ACTOR_DIR, actor]):
		character.actor_key = StringName(actor)
	if not RARITIES.has(row[COL_RARITY]):
		return "%s 的稀有度不认识：%s" % [key, row[COL_RARITY]]
	if not REACHES.has(row[COL_REACH]):
		return "%s 的攻击距离不认识：%s" % [key, row[COL_REACH]]
	if not ELEMENTS.has(row[COL_ATTACK]) or not ELEMENTS.has(row[COL_DEFENCE]):
		return "%s 的攻/防属性不认识：%s / %s" % [key, row[COL_ATTACK], row[COL_DEFENCE]]
	if not PRIMARIES.has(row[COL_PRIMARY]):
		return "%s 的主属性不认识：%s" % [key, row[COL_PRIMARY]]
	character.rarity = RARITIES[row[COL_RARITY]]
	character.reach = REACHES[row[COL_REACH]]
	character.element = ELEMENTS[row[COL_ATTACK]]
	character.def_element = ELEMENTS[row[COL_DEFENCE]]
	character.primary = PRIMARIES[row[COL_PRIMARY]]

	# 三围与成长是**数据**，逐个从名册读（M12-b）。
	character.strength = float(row[COL_STR])
	character.agility = float(row[COL_AGI])
	character.intellect = float(row[COL_INT])
	character.strength_growth = float(row[COL_STR_GROW])
	character.agility_growth = float(row[COL_AGI_GROW])
	character.intellect_growth = float(row[COL_INT_GROW])

	# **换算那一层走规则层那一份，不在这里再算一遍。**
	#
	# 这里**不再调 `fill_placeholder`**（M12-b）：那个函数是给
	# 「还没有属性数据的角色」铺占位值的，它会先按稀有度覆盖一遍三围、
	# 再反解 `atk_base` 把 DPS 拉回稀有度阶梯上 —— 于是上面刚读进来的
	# 56 份三围在最后一步被整个抹平，**而它不报错**：
	# 属性栏里每个数都对，只是同一稀有度的人打出来的伤害一样多。
	PBStatRules.apply_original_scale(character, float(row[COL_INTERVAL]))

	var passives: Variant = _parse_passives(row[COL_PASSIVE])
	if passives is String:
		return "%s 的被动：%s" % [key, passives]
	character.passives = passives as Dictionary

	var err := ResourceSaver.save(character, path)
	return "" if err == OK else "%s 存不下来（%d）" % [key, err]


## 被动那一列：`键=量;键=量`，`-` 或空 = 没有。
##
## **不认识的键在这里报错，不静默跳过。** 静默跳过的表现正是「配了不生效」——
## 数据、界面、日志全部正常，只有那个字段没人写（同 `make_skills.gd`
## 的 `额外` 那一列，M12-c1 定的）。规则层那边
## （[method PBPassiveRules.grant_all]）只是不装、不报错：
## 战斗中途 `push_error` 没有人看得见，而两处各拦一次就是两把尺子。
##
## 返回 [Dictionary] = 成功，返回 [String] = 错误信息。
func _parse_passives(cell: String) -> Variant:
	var out: Dictionary = {}
	if cell == "" or cell == SAME_AS_ID:
		return out
	for piece: String in cell.split(";", false):
		var pair: PackedStringArray = piece.split("=")
		if pair.size() != 2:
			return "「%s」不是 键=量 的样子" % piece
		var name := StringName(pair[0].strip_edges())
		if not PBPassiveRules.is_known(name):
			return "不认识的键「%s」" % name
		if out.has(name):
			return "键「%s」写了两遍" % name
		out[name] = float(pair[1].strip_edges())
	return out


## 名册里没有的 `.tres` 一律删掉。
##
## **不删的话「删掉某个角色」这件事做不到**：生成器只写不删，
## 那几个文件会一直躺在 `data/characters/` 里被加载器扫进来，
## 而唯一的现象是卡池里多出几个名册上没有的人。
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
