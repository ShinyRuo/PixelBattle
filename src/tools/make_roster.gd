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

## 表头那六列的列号。
const COL_ID: int = 0
const COL_NAME: int = 1
const COL_RARITY: int = 2
const COL_REACH: int = 3
const COL_ATTACK: int = 4
const COL_DEFENCE: int = 5

const RARITIES := {"R": PBUnit.Rarity.R, "SR": PBUnit.Rarity.SR, "SSR": PBUnit.Rarity.SSR}
const REACHES := {"近战": PBCharacter.Reach.MELEE, "远程": PBCharacter.Reach.RANGED}
const ELEMENTS := {
	"火": PBElement.Type.FIRE,
	"风": PBElement.Type.WIND,
	"雷": PBElement.Type.THUNDER,
	"土": PBElement.Type.EARTH,
	"水": PBElement.Type.WATER,
	"物理": PBElement.Type.PHYSICAL,
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
		if cells.size() < 6:
			printerr("这一行少了列（要 6 列，实际 %d）：%s" % [cells.size(), trimmed])
			continue
		out.append(cells)
	return out


## 铺一个角色。**返回错误信息，空串 = 成功。**
func _write_one(row: PackedStringArray) -> String:
	var key: String = row[COL_ID]
	var path: String = "%s/%s.tres" % [OUT_DIR, key]
	var character := PBCharacter.new()
	# 三样人工填的先从旧文件里捞回来，见类顶部。
	var old: PBCharacter = null
	if ResourceLoader.exists(path):
		old = ResourceLoader.load(path) as PBCharacter
	if old != null:
		character.actor_key = old.actor_key
		character.icon_key = old.icon_key
		character.skill_ids = old.skill_ids.duplicate()

	character.id = StringName(key)
	character.name_key = "char.%s" % key
	if String(character.icon_key) == "":
		character.icon_key = key
	if not RARITIES.has(row[COL_RARITY]):
		return "%s 的稀有度不认识：%s" % [key, row[COL_RARITY]]
	if not REACHES.has(row[COL_REACH]):
		return "%s 的攻击距离不认识：%s" % [key, row[COL_REACH]]
	if not ELEMENTS.has(row[COL_ATTACK]) or not ELEMENTS.has(row[COL_DEFENCE]):
		return "%s 的攻/防属性不认识：%s / %s" % [key, row[COL_ATTACK], row[COL_DEFENCE]]
	character.rarity = RARITIES[row[COL_RARITY]]
	character.reach = REACHES[row[COL_REACH]]
	character.element = ELEMENTS[row[COL_ATTACK]]

	# **战力那一段走规则层那一份，不在这里再算一遍。**
	# 它读 `rarity` / `element` / `reach_tier()`，所以上面那三行必须先填。
	PBStatRules.fill_placeholder(character)

	# **护甲属性要排在后面。** `fill_placeholder` 里那一句
	# `def_element = counter_of(element)` 是给合成表用的占位推导，
	# 而名册这一栏是原版实测值 —— 先填会被它盖掉，表现是
	# 「表里写着物理，游戏里按土算」，而两个数看起来都很正常。
	character.def_element = ELEMENTS[row[COL_DEFENCE]]

	var err := ResourceSaver.save(character, path)
	return "" if err == OK else "%s 存不下来（%d）" % [key, err]


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
