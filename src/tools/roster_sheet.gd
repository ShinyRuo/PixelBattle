@tool
class_name PBRosterSheet
extends RefCounted
## `data/roster.tsv` 的列号与读写：按角色键读一格、改一格。
##
## 名册生成器（`make_roster.gd`）和「战场特效」面板共用这一份。**列号只在这里出现一次** ——
## 各记一份的话，名册加一列时改漏一处会读到相邻那一栏，而它照样是个合法的字符串。
##
## **改一格只动那一格**：表头那一大段注释、空行、其余行原样留着。那段注释是写给人看的，
## 重新序列化整张表会把它弄丢。

const PATH := "res://data/roster.tsv"

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
const COL_SHOT: int = 16

## 表一共几列。少一列就整行不要 —— 用默认值兜底的表现是
## 「那个角色的三围全是 0」，而 0 力量算出来是一个合法的血量。
const COLUMNS: int = 17

## 形象键那一列写这个 = 和角色键同名；被动、普攻子弹那两列写这个 = 没有。
const NONE := "-"

## 原样的每一行（不去首尾空白、不丢注释）。
var lines: PackedStringArray = []


## 读一张名册。读不到就是一张空表（[method rows] 为空），调用方自己说话。
static func read(path: String = PATH) -> PBRosterSheet:
	var sheet := PBRosterSheet.new()
	if FileAccess.file_exists(path):
		sheet.lines = FileAccess.get_file_as_string(path).split("\n")
	return sheet


## 普攻子弹那一格 → [member PBCharacter.shot_key]。`-` 或空 = 没配（白模）。
static func shot_key_of(cell: String) -> StringName:
	var trimmed: String = cell.strip_edges()
	return &"" if trimmed == "" or trimmed == NONE else StringName(trimmed)


## 普攻子弹那一格有没有毛病：填了、却在 [param shots_dir] 里找不到那份 [PBShotSkin]。
## **返回错误信息，空串 = 没毛病。** 找不到就报错而不是留空 —— 留空的表现是「配了还是白模」，而它不报错。
static func shot_error(cell: String, shots_dir: String = PBShotLibrary.DIR) -> String:
	var key: StringName = shot_key_of(cell)
	if key == &"":
		return ""
	var path: String = "%s/%s.tres" % [shots_dir, key]
	if not ResourceLoader.exists(path):
		return "找不到子弹「%s」（%s）—— 先在「战场特效」里生成它" % [key, path]
	return ""


## 全部数据行，每行一个去过首尾空白的 [PackedStringArray]。**空行和 `#` 开头的行跳过。**
## 不检查列数，那是调用方的事（生成器要整行拒收，面板只读其中一格）。
func rows() -> Array:
	var out: Array = []
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		out.append(cells)
	return out


## [param id] 那一行的第 [param col] 格。没有这个人、或者这一行没那么多列，返回空串。
func cell(id: String, col: int) -> String:
	for row: PackedStringArray in rows():
		if row[COL_ID] == id:
			return row[col] if col < row.size() else ""
	return ""


## 把 [param id] 那一行的第 [param col] 格改成 [param value]。**返回错误信息，空串 = 成功。**
##
## 这一行列数不够就用 `-` 补齐到那一格 —— 补齐的都是「没有」，不会凭空填出一个值。
func set_cell(id: String, col: int, value: String) -> String:
	if value.contains("\t") or value.contains("\n"):
		return "这一格的值不能带 Tab 或换行：%s" % value.c_escape()
	for i: int in lines.size():
		var line: String = lines[i]
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		# 保留行尾的 `\r`：名册哪天被存成 CRLF，只改一行却把那一行变成 LF 的话，
		# 差异里会冒出一行「看不出改了什么」的改动。
		var tail: String = "\r" if line.ends_with("\r") else ""
		var cells: PackedStringArray = line.trim_suffix("\r").split("\t")
		if cells[COL_ID].strip_edges() != id:
			continue
		while cells.size() <= col:
			cells.append(NONE)
		cells[col] = value
		lines[i] = "\t".join(cells) + tail
		return ""
	return "名册里没有这个角色：%s" % id


## 第 [param col] 格正好是 [param value] 的那些角色键，按名册里的顺序。
func users_of(col: int, value: String) -> PackedStringArray:
	var out := PackedStringArray()
	for row: PackedStringArray in rows():
		if col < row.size() and row[col] == value:
			out.append(row[COL_ID])
	return out


## 写回盘上。**返回错误信息，空串 = 成功。**
func save(path: String = PATH) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "名册写不进去（%d）：%s" % [FileAccess.get_open_error(), path]
	file.store_string("\n".join(lines))
	file.close()
	return ""
