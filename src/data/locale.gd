class_name PBLocale
extends RefCounted
## 显示名查表。M2-d。
##
## ## 它补的是 §14 铁律 5 缺的另一半
##
## 铁律 5 说「代码里不出现角色名，一律走 id + name_key 查表」。
## `id` 和 `name_key` 从 M2-a 就有了，但**那张表一直不存在** ——
## 于是界面上要么没有名字，要么只能显示 `bond.xxx` 这种 key。
## 名字没地方放，压力就会回到代码里（「先在 UI 里写死一下，回头再改」），
## 铁律 5 是这么破的。
##
## ## 为什么现在是一份 JSON 而不是引擎的翻译系统
##
## Godot 有 `.po` / `.csv` + `tr()` 那一套，M5 做多语言时会换过去。
## 现在用不上它，因为只有一种语言，而那套东西要动 `project.godot`
## 的翻译段 —— 而引擎会重写那个文件（见 CLAUDE.md），
## 白模阶段为它折腾不划算。
##
## **换过去时 `src/` 不用动**：调用方只认 [method text]，
## 里面换成 `tr()` 是一行的事。这正是留 `name_key` 这一层的意义。
##
## ## 查不到就回退到 key
##
## 不报错、不留空。缺一条翻译在白模阶段是常态（新角色刚加进来还没配名字），
## 而 key 本身就有可读性（`bond.` 打头一眼看得出是哪张表），能直接指出缺的是哪一条。
## 空白反而会让人以为是排版坏了。

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


## 一组羁绊的显示名。
static func of_bond(bond: PBBond) -> String:
	if bond == null:
		return ""
	return text(bond.name_key)


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
