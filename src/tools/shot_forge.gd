@tool
class_name PBShotForge
extends RefCounted
## 切好的子弹帧 → 一份 [PBShotSkin]，以及「哪个忍者的普攻用它」那一格。
##
## 输入是 [PBFxForge] 切出来的 `assets/fx/<键>/fly_*.png` 与 `hit_*.png`，
## 输出 `data/shots/<键>.tres`（帧表内嵌在里面，[PBShotLibrary] 不递归子目录，一个文件最省事）。
## 编辑器底栏「战场特效」面板（[PBFxShotPage]）调它，测试也调它 —— 目录都是字段，测试改到 `user://`。
##
## **配给忍者要改两处，而且是同一个值**：名册那一格是真相（[PBRosterSheet]），
## `data/characters/<id>.tres` 是它生成出来的。只改名册的话要再跑一次名册生成器才生效，
## 只改 `.tres` 的话下一次重跑会把它抹掉 —— 所以 [method assign] 两处一起写，写的值走同一个函数。

const FLY := &"fly"
const HIT := &"hit"

## 贴图是屏幕尺寸的几倍（`Docs/素材规格_特效.md` §2.1），和人物同一档。
const HD_FACTOR: int = 3

## 键只许小写英文、数字、下划线：它同时是目录名、文件名和表里的一格。
const KEY_PATTERN := "^[a-z0-9_]+$"

var assets_dir: String = "res://assets/fx"
var data_dir: String = PBShotLibrary.DIR
var roster_path: String = PBRosterSheet.PATH
var characters_dir: String = "res://data/characters"

var fly_fps: float = 12.0
var hit_fps: float = 20.0

## 飞行中转向飞行方向，见 [member PBShotSkin.spin]。
var spin: bool = true

## 两段各自用不用加法混合，见 [member PBShotSkin.additive_fly]。面板按每段的背景模式填（黑底 = 加法）。
var additive_fly: bool = true
var additive_hit: bool = true

## 这颗子弹有没有爆炸特效（命中段）。**关掉就不装命中段**，盘上有 `hit_*.png` 也不读 ——
## 打中时用默认火花（[method PBShotPool._spark]）。面板上那个勾选框（玩家定的）。
var with_hit: bool = true


## 键合不合规矩。**返回错误信息，空串 = 合规。**
static func key_error(key: String) -> String:
	if key == "":
		return "先填子弹键。"
	var pattern := RegEx.create_from_string(KEY_PATTERN)
	if pattern.search(key) == null:
		return "子弹键只用小写英文、数字和下划线：%s" % key
	return ""


## 这一段切好的帧放在哪个目录。
func frame_dir(key: String) -> String:
	return "%s/%s" % [assets_dir, key]


## 盘上这一段有几帧（`<anim>_0.png` 起连续数，断号就停）。**不要求已经导入**，面板拿它判断「切过没有」。
func frames_on_disk(key: String, anim: StringName) -> int:
	var count: int = 0
	while FileAccess.file_exists("%s/%s_%d.png" % [frame_dir(key), anim, count]):
		count += 1
	return count


## 把两段贴图装成一份子弹资源（不碰磁盘）。高清档：缩到 `1/`[constant HD_FACTOR]、平滑过滤；真素材不按敌我染色。
func assemble(key: String, fly: Array[Texture2D], hit: Array[Texture2D]) -> PBShotSkin:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add(frames, FLY, fly_fps, true, fly)
	# 命中段**不循环**：它播一遍就收（[method PBShotSkin.hit_seconds] 按帧数 / 帧率算它活多久）。
	# **可以不配**（玩家定的）：没有这一段，打中时用默认火花（[method PBShotPool._spark]）。
	if not hit.is_empty():
		_add(frames, HIT, hit_fps, false, hit)
	var skin := PBShotSkin.new()
	skin.key = StringName(key)
	skin.frames = frames
	skin.anim_fly = FLY
	skin.anim_hit = HIT
	skin.pixel_scale = 1.0 / float(HD_FACTOR)
	skin.smooth = true
	skin.spin = spin
	skin.tint_by_side = false
	skin.additive_fly = additive_fly
	skin.additive_hit = additive_hit
	return skin


## 读盘上导入好的两段帧，生成 `data/shots/<键>.tres`。**返回错误信息，空串 = 成功。**
##
## 顺手打开这个键下贴图的 mipmap（改 `.import`）—— **改完要再导入一次才生效**，面板会接着重扫。
## 少这一趟的表现是子弹一飞起来就闪，而静止看完全正常（同 [method PBPortraitForge.want_mipmaps]）。
func build(key: String) -> String:
	var bad := key_error(key)
	if bad != "":
		return bad
	var fly := _textures(key, FLY)
	if fly.is_empty():
		return "飞行段一帧都没有（%s/fly_*.png）—— 先切图，切完等编辑器导入。" % frame_dir(key)
	var hit: Array[Texture2D] = []
	if with_hit:
		hit = _textures(key, HIT)
	# 命中段可以不切；**要了命中段、切了却没导入完**要拦 —— 不拦的话生成出来的子弹静默用默认火花。
	if with_hit and hit.is_empty() and frames_on_disk(key, HIT) > 0:
		return "命中段的帧还没导入完（%s/hit_*.png）—— 等编辑器导入再点一次。" % frame_dir(key)
	PBPortraitForge.new().want_mipmaps(frame_dir(key))
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return "建不了目录：%s" % data_dir
	err = ResourceSaver.save(assemble(key, fly, hit), shot_path(key))
	return "" if err == OK else "子弹资源存不下来（%d）：%s" % [err, shot_path(key)]


func shot_path(key: String) -> String:
	return "%s/%s.tres" % [data_dir, key]


## 把 [param id] 这个忍者的普攻子弹设成 [param key]（空串或 `-` = 取消，退回白模）。
## **返回错误信息，空串 = 成功。**
##
## 先写名册（真相），再写生成出来的角色数据。角色数据还没生成时名册照样写上，
## 报一句「跑一次名册生成器」—— 那时名册已经是对的，重跑就对齐了。
func assign(id: String, key: String) -> String:
	var cell: String = key.strip_edges()
	if cell == "":
		cell = PBRosterSheet.NONE
	var missing := PBRosterSheet.shot_error(cell, data_dir)
	if missing != "":
		return missing
	var sheet := PBRosterSheet.read(roster_path)
	var err := sheet.set_cell(id, PBRosterSheet.COL_SHOT, cell)
	if err == "":
		err = sheet.save(roster_path)
	if err != "":
		return err
	var path: String = "%s/%s.tres" % [characters_dir, id]
	if not ResourceLoader.exists(path):
		return "名册改好了，但还没有 %s —— 跑一次名册生成器（make_roster.gd）。" % path
	var character := ResourceLoader.load(path) as PBCharacter
	if character == null:
		return "读不出角色数据：%s" % path
	character.shot_key = PBRosterSheet.shot_key_of(cell)
	var saved := ResourceSaver.save(character, path)
	return "" if saved == OK else "角色数据存不下来（%d）：%s" % [saved, path]


## 名册里每个忍者现在配的普攻子弹：`[{id, name, shot}]`，按名册顺序。`shot` 为空 = 白模。
func roster_shots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: PackedStringArray in PBRosterSheet.read(roster_path).rows():
		var shot := &""
		if row.size() > PBRosterSheet.COL_SHOT:
			shot = PBRosterSheet.shot_key_of(row[PBRosterSheet.COL_SHOT])
		var name: String = row[PBRosterSheet.COL_NAME] if row.size() > 1 else ""
		out.append({"id": row[PBRosterSheet.COL_ID], "name": name, "shot": shot})
	return out


## 这一段导入好的贴图。**有一帧还没导入就整段不要** —— 装一半的表现是「动画少了几帧」，而它不报错。
func _textures(key: String, anim: StringName) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i: int in frames_on_disk(key, anim):
		var path: String = "%s/%s_%d.png" % [frame_dir(key), anim, i]
		if not ResourceLoader.exists(path):
			out.clear()
			break
		out.append(load(path) as Texture2D)
	return out


static func _add(
	frames: SpriteFrames, anim: StringName, fps: float, loop: bool, textures: Array[Texture2D]
) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for texture: Texture2D in textures:
		frames.add_frame(anim, texture)
