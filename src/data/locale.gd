class_name PBLocale
extends RefCounted
## 显示名查表。补的是铁律 5 的另一半：代码里不出现角色名，就得有地方放名字。
##
## 现在是一份 JSON，不是引擎的 `.po` / `tr()`：只有一种语言，而那套要动 `project.godot`（引擎会重写它）。
## 换过去时 `src/` 不用动 —— 调用方只认 [method text]。
##
## **查不到就回退到 key**，不报错、不留空：key 本身可读（`bond.` 打头一眼看出是哪张表），空白会让人以为排版坏了。

const PATH := "res://data/locale/zh_CN.json"

## 以 `_` 开头的键是给人看的说明，不是翻译。
const COMMENT_PREFIX := "_"

static var _table: Dictionary = {}
static var _loaded: bool = false


## [param key] 对应的显示名。查不到就返回 key 本身。
static func text(key: String) -> String:
	if not _loaded:
		_load()
	return String(_table.get(key, key))


## 一个角色的显示名。
static func of_character(character: PBCharacter) -> String:
	if character == null:
		return ""
	return text(character.name_key)


## 一个技能的显示名。**查不到就退回它的 id** —— 空串的话指令卡上是一个没有字的按钮。
static func of_skill(skill: PBSkill) -> String:
	if skill == null:
		return ""
	return text(skill.name_key) if skill.name_key != "" else String(skill.id)


## 一组羁绊的显示名。
static func of_bond(bond: PBBond) -> String:
	if bond == null:
		return ""
	return text(bond.name_key)


## 一个羁绊功能档的显示名（§09 的聚拢 / 吸附 / 定身 / 减速…）。
##
## 键名走 `bond.fn.<功能键>` 拼出来，而不是在 [PBBond] 里再存一份 ——
## 功能键本身已经是全局唯一的标识（[constant PBBondFunctionRules.ALL]），
## 再存一份显示名的键只会多一处能对不上的地方。
static func of_bond_function(key: StringName) -> String:
	if key == &"":
		return ""
	return text("bond.fn.%s" % key)


## 有几条翻译。测试用来确认表真的装上了。
static func size() -> int:
	if not _loaded:
		_load()
	return _table.size()


static func _load() -> void:
	_loaded = true
	_table = {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("语言表打不开：%s" % PATH)
		return
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("语言表不是一个 JSON 对象：%s" % PATH)
		return
	for key: String in parsed as Dictionary:
		if not key.begins_with(COMMENT_PREFIX):
			_table[key] = (parsed as Dictionary)[key]
