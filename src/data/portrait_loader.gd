class_name PBPortraitLibrary
extends RefCounted
## 把 `assets/portraits/*.png` 装成一张「键 → 头像贴图」的表。M9-g。
##
## ## 和 [PBActorLibrary] 同一条分工线，但少一层
##
## `ResourceLoader` 被 core 纯度检查明令挡住（§14），所以「读盘」这件事
## 只能发生在 core 外面 —— 这条和形象、角色表那两张是一样的。
##
## **少的那一层是资源类。** [PBActorSkin] 存在是因为一套战场形象随身带着
## 一堆约定（脚底在哪、源图朝哪、要不要按属性染色、身高多少），
## 那些是「这份素材的性质」；而一张头像**只有图本身** ——
## 尺寸、缩放、过滤全是整套统一的（见 [method PBPortraitForge.texture_size]）。
## 现在就造一个 `PBPortraitSkin` 只会多一层永远填着同样值的 `.tres`。
## 哪天真出现逐张不同的约定（比如某个角色要往上挪两像素），那时候再加。
##
## ## 目录不存在不是错
##
## 和 [PBActorLibrary] 顶上那条一模一样：角色表打不开要 `push_error`
## （没有角色表就没有游戏），头像打不开的正确行为恰恰是**退回白模卡面**
## （[PBUnitTile] 那套属性底色 + 稀有度描边）。**空 = 白模**，
## 这是这一步敢在美术还没齐的时候落地的前提。

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
