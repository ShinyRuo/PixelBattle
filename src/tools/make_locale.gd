extends SceneTree
## 按 `data/roster.tsv` 和 `data/bonds.tsv` 重写语言表里的 `char.*` / `bond.*`。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_locale.gd
## ```
##
## ## 为什么名字不能在两个地方各写一遍
##
## 名册和羁绊表里已经有显示名了（第 2 列）。语言表再手写一份的话，
## 「表里改了名字、屏幕上还是旧的」迟早发生 —— 而它不报错：
## [method PBLocale.text] 查不到就返回 key 本身，查得到就返回旧值，
## 两种情况屏幕上都有字。所以这一份是**派生物**，改名字只改 tsv。
##
## ## 别的键一个都不动
##
## 表里没有的前缀（`beast.` / `equip.` / `equip_part.` / `buff.` / `skill.` /
## `bond.fn.` / `_note`）**原样搬过去，顺序也不变** —— 它们不是这两张表的
## 产出，扫一遍就重排会让每次跑这个工具都产生一大片无意义的 diff。

const ROSTER := "res://data/roster.tsv"
const BONDS := "res://data/bonds.tsv"
const SKILLS := "res://data/skills.tsv"
const BUFFS := "res://data/buffs.tsv"
const LOCALE := "res://data/locale/zh_CN.json"

## 显示名在第几列。**不是每张表都在第 2 列**：技能表第 2 列是角色键、第 3 列才是显示名 ——
## 取错列的表现是指令卡上的技能格写着角色的英文键，而它不报错。
const NAME_COL: int = 1
const SKILL_NAME_COL: int = 2


func _init() -> void:
	var file := FileAccess.open(LOCALE, FileAccess.READ)
	if file == null:
		printerr("打不开语言表：%s" % LOCALE)
		quit(1)
		return
	var table: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	if table == null:
		printerr("语言表不是合法 JSON")
		quit(1)
		return

	var out: Dictionary = {}
	# 先搬别的键，保持原顺序。`bond.fn.*` 是功能名，不是羁绊名，也留着。
	for key: String in table:
		if key.begins_with("char.") or key.begins_with("skill.") or key.begins_with("buff."):
			continue
		if key.begins_with("bond.") and not key.begins_with("bond.fn."):
			continue
		out[key] = table[key]
	var bonds: int = _fill(out, BONDS, "bond.")
	var characters: int = _fill(out, ROSTER, "char.")
	var skills: int = _fill(out, SKILLS, "skill.", SKILL_NAME_COL)
	var buffs: int = _fill(out, BUFFS, "buff.")

	# 缩进用一个空格：仓库里那一份就是这个格式，换成 Tab 的话每跑一次整张表都算改过。
	var text := JSON.stringify(out, " ")
	var write := FileAccess.open(LOCALE, FileAccess.WRITE)
	if write == null:
		printerr("写不进语言表")
		quit(1)
		return
	write.store_string(text + "\n")
	write.close()
	print(
		(
			"语言表写好了：%d 个角色名 + %d 组羁绊名 + %d 个技能名 + %d 份效果名"
			% [characters, bonds, skills, buffs]
		)
	)
	quit(0)


## 从一张 tsv 铺 `<前缀><第 1 列> = <第 name_col 列>`，返回铺了几条。
func _fill(out: Dictionary, path: String, prefix: String, name_col: int = NAME_COL) -> int:
	var count: int = 0
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		if cells.size() <= name_col:
			continue
		out["%s%s" % [prefix, cells[0].strip_edges()]] = cells[name_col].strip_edges()
		count += 1
	return count
