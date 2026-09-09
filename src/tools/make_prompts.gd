extends SceneTree
## 按 `aires/ninja_art.tsv` + `aires/prompts/_ninja_template.md` 铺提示词（M10-b）。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_prompts.gd
## ```
##
## ## 为什么要生成而不是手写
##
## 一份提示词 250 行，其中约 230 行是**四段图集共用的死文本** ——
## 【图集】【角色】【画风】【背景】那四节「一字不差是有意的」，
## 差一个字都可能让模型换一次手。24 份手写等于把那 230 行抄 96 遍
## （四段 × 24 人），而抄错不报错：出来的图看着都对，只是这一张的
## 方块比那一张细一点、这一段的人比那一段高一点。
##
## 每个角色只有三处不同：角色键、原型、外观段落。表里就只有这三栏。
##
## ## `aires/` 对 `res://` 是不可见的
##
## 那个目录有 `.gdignore`，所以要走
## [method ProjectSettings.globalize_path]（同 [PBPortraitForge] 读
## `aires/headshots.txt` 那一条）。

const TABLE := "aires/ninja_art.tsv"
const TEMPLATE := "aires/prompts/_ninja_template.md"
const OUT_DIR := "aires/prompts"

const COL_KEY: int = 0
const COL_ORIGIN: int = 1
const COL_LOOK: int = 2

## 跑姿与出手（玩家提的：24 个人共用一套跑法和出手，屏幕上会像一队复制人）。
##
## 这两栏落进 `run` / `attack` 那张图集的【动作】**末尾**，
## 前面那六格的骨架一个字不改 —— 骨架是流水线的硬要求：
## `attack` 第 4 格必须是伸得最远的那一格（[method PBActorForge._pick_reach]
## 按它排出手帧，错了游戏里就是「先掉血、后出手」）、`run` 六格要接得回去、
## 不许有和身体断开的碎块（切图会把它当成独立的一格）。
const COL_RUN: int = 3
const COL_ATTACK: int = 4


func _init() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	var template := FileAccess.get_file_as_string(root + TEMPLATE)
	if template == "":
		printerr("读不到模板：%s" % (root + TEMPLATE))
		quit(1)
		return
	var names := _display_names(root)
	var written: int = 0
	for row: PackedStringArray in _read(root + TABLE):
		var key: String = row[COL_KEY]
		if row.size() <= COL_ATTACK:
			# **少一栏不许静默跳过。** 跳过的表现是这一个人的提示词里
			# 留着一个没替换掉的 `{{run}}`，而那一整段照样复制得出去。
			printerr("%s 少了列（要 5 列，实际 %d）" % [key, row.size()])
			quit(1)
			return
		var text: String = template
		text = text.replace("{{key}}", key)
		text = text.replace("{{name}}", String(names.get(key, key)))
		text = text.replace("{{origin}}", row[COL_ORIGIN])
		text = text.replace("{{look}}", row[COL_LOOK])
		text = text.replace("{{run}}", row[COL_RUN])
		text = text.replace("{{attack}}", row[COL_ATTACK])
		var file := FileAccess.open("%s%s/%s.md" % [root, OUT_DIR, key], FileAccess.WRITE)
		if file == null:
			printerr("写不出 %s" % key)
			quit(1)
			return
		file.store_string(text)
		file.close()
		written += 1
	print("写好 ", written, " 份提示词")
	quit(0)


## 显示名从名册里读，**不在这张表里再写一遍** —— 两处写的话
## 提示词标题上的名字和游戏里显示的名字会慢慢分叉。
func _display_names(root: String) -> Dictionary:
	var out: Dictionary = {}
	for row: PackedStringArray in _read(root + "data/roster.tsv"):
		if row.size() >= 2:
			out[row[0]] = row[1]
	return out


func _read(path: String) -> Array:
	var out: Array = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		out.append(cells)
	return out
