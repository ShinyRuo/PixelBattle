class_name PBPortraitLibrary
extends RefCounted
## 把 `assets/portraits/*.png` 装成一张「键 → 头像贴图」的表。
##
## 和 [PBActorLibrary] 同一条分工线，但**没有资源类**：一张头像只有图本身，尺寸、缩放、过滤整套统一
## （[method PBPortraitForge.texture_size]）。哪天出现逐张不同的约定时再加。
##
## **目录不存在不是错**：打不开时退回白模卡面（[PBUnitTile] 的属性底色 + 稀有度描边）。

const DIR := "res://assets/portraits"

static var _cached: Dictionary = {}
static var _loaded: bool = false


## 全部头像。第一次调用读盘，之后走缓存。
static func portraits() -> Dictionary:
	if not _loaded:
		_cached = load_from(DIR)
		_loaded = true
	return _cached


## 查一张头像，没有就 `null`（调用方退回白模卡面）。
static func portrait_for(icon_key: String) -> Texture2D:
	if icon_key == "":
		return null
	return portraits().get(icon_key, null) as Texture2D


## 重新读盘。切完图想立刻看效果时用，测试里也用它换一张假表。
static func reload() -> void:
	_loaded = false
	_cached = {}


## 从指定目录装一张表。**键就是文件名**（不含扩展名）——
## 头像没有一份「自己说自己叫什么」的资源可查（见类顶部），
## 所以文件名就是键，和 `data/characters/*.tres` 里的 `icon_key` 对上。
static func load_from(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		# **导入过的贴图在磁盘上是 `.png`，但目录里也躺着 `.png.import`。**
		# 不筛的话那份 INI 会被当成一张图去 load，返回 null 而不报错 ——
		# 表现是「有一半头像装不上」，取决于目录列出来的顺序。
		if not file_name.ends_with(".png"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var texture := load(path) as Texture2D
		if texture == null:
			push_error("这张头像装不进来（不是贴图？）：%s" % path)
			continue
		out[file_name.get_basename()] = texture
	return out
