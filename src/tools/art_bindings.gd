@tool
class_name PBArtBindings
extends RefCounted
## 表现绑定只修改素材引用，不改变伤害、飞行速度或施法时序。

enum Flight { DEFAULT, HIDDEN, NAMED }

var presentation_dir: String = "res://data/skill_art"
var skill_sheet: String = "res://data/skills.tsv"
var skill_dir: String = "res://data/skills"
var character_dir: String = "res://data/characters"
var actor_dir: String = "res://data/actors"
var shot_dir: String = "res://data/shots"


func skills() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(skill_sheet).split("\n"):
		if line.strip_edges().is_empty() or line.begins_with("#"):
			continue
		var row := line.strip_edges().split("\t")
		if row.size() == 11:
			rows.append(row)
	return rows


func actor_path(skill_id: String) -> String:
	for row: PackedStringArray in skills():
		if row[0] != skill_id or row[1] == "-":
			continue
		var path := "%s/%s.tres" % [character_dir, row[1]]
		if not ResourceLoader.exists(path):
			return ""
		var character := load(path) as PBCharacter
		if character != null:
			return "%s/%s.tres" % [actor_dir, character.actor_key]
	return ""


func assign_cast(skill_id: String, paths: PackedStringArray) -> String:
	var path := actor_path(skill_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return "此技能没有独立忍者形象；附加招式沿用主技能动作。"
	if paths.size() != 6:
		return "请选择六张已导入 PNG，按文件名 00–05 排序。"
	paths.sort()
	var textures: Array[Texture2D] = []
	var size := Vector2.ZERO
	for frame_path: String in paths:
		if not frame_path.begins_with("res://") or not ResourceLoader.exists(frame_path):
			return "请先将 PNG 放入项目 assets 并等待导入：%s" % frame_path
		var texture := load(frame_path) as Texture2D
		if texture == null or (size != Vector2.ZERO and texture.get_size() != size):
			return "六张帧必须是相同画布尺寸的贴图。"
		size = texture.get_size()
		textures.append(texture)
	var skin := (load(path) as PBActorSkin).duplicate() as PBActorSkin
	if skin.frames == null:
		return "形象缺少基础四态帧资源。"
	skin.frames = skin.frames.duplicate() as SpriteFrames
	var anim := StringName("cast_%s" % skill_id)
	if skin.frames.has_animation(anim):
		skin.frames.remove_animation(anim)
	skin.frames.add_animation(anim)
	skin.frames.set_animation_loop(anim, false)
	skin.frames.set_animation_speed(anim, 10.0)
	for texture: Texture2D in textures:
		skin.frames.add_frame(anim, texture)
	skin.skill_anims = skin.skill_anims.duplicate()
	skin.skill_anims[StringName(skill_id)] = anim
	return _save_skin(skin, path)


func assign_animation(skill_id: String, anim: StringName) -> String:
	var path := actor_path(skill_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return "请先在战场形象工具生成此忍者的形象。"
	var skin := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBActorSkin
	if skin == null or not skin.has(anim) or skin.frames.get_frame_count(anim) != 6:
		return "请选择此忍者已有的六帧动作。"
	skin.skill_anims = skin.skill_anims.duplicate()
	skin.skill_anims[StringName(skill_id)] = anim
	return _save_skin(skin, path)


func clear_cast(skill_id: String) -> String:
	var path := actor_path(skill_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return "找不到对应的忍者形象。"
	var skin := (load(path) as PBActorSkin).duplicate() as PBActorSkin
	skin.skill_anims = skin.skill_anims.duplicate()
	skin.skill_anims.erase(StringName(skill_id))
	return _save_skin(skin, path)


func assign_shot(skill_id: String, key: String) -> String:
	var path := "%s/%s.tres" % [skill_dir, skill_id]
	var validation := _shot_error(path, key)
	if validation != "":
		return validation
	var original := load(path) as PBSkill
	return _write_shot(skill_id, key, original, path)


func assign_flight(skill_id: String, mode: int, key: String = "") -> String:
	var path := "%s/%s.tres" % [skill_dir, skill_id]
	if not skill_id.is_valid_identifier() or not ResourceLoader.exists(path):
		return "请选择有效技能。"
	if mode not in [Flight.DEFAULT, Flight.HIDDEN, Flight.NAMED]:
		return "请选择有效的飞行表现模式。"
	if mode == Flight.NAMED and key == "":
		return "请选择命名子弹。"
	var art_path := "%s/%s.tres" % [presentation_dir, skill_id]
	var art := PBSkillStartArt.new()
	if ResourceLoader.exists(art_path):
		art = ResourceLoader.load(art_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if art == null:
			return "技能美术配置无效。"
	var skill := load(path) as PBSkill
	var error := ""
	if mode == Flight.NAMED or (mode == Flight.DEFAULT and can_bind_shot(skill)):
		error = assign_shot(skill_id, key if mode == Flight.NAMED else "")
	if error == "":
		art.hide_flight = mode == Flight.HIDDEN
		DirAccess.make_dir_recursive_absolute(presentation_dir)
		error = error_string(ResourceSaver.save(art, art_path))
		PBSkillStartArt._hidden.clear()
	return "" if error == "OK" else error


static func can_bind_shot(skill: PBSkill) -> bool:
	return (
		skill != null
		and (
			skill.shot_cross_seconds > 0.0
			or (skill.target == PBSkill.Target.GROUND and skill.delay_ticks > 0)
		)
	)


func _shot_error(path: String, key: String) -> String:
	if not ResourceLoader.exists(path):
		return "先生成技能资源。"
	var original := load(path) as PBSkill
	if original == null:
		return "技能资源类型错误。"
	if not can_bind_shot(original):
		return "此技能没有弹道或地面延迟载体入口，不能只配图片就改变命中方式。"
	if key != "":
		var error := PBShotForge.key_error(key)
		if error != "":
			return error
		var shot_path := "%s/%s.tres" % [shot_dir, key]
		if not ResourceLoader.exists(shot_path) or not load(shot_path) is PBShotSkin:
			return "先在子弹页生成有效子弹资源。"
	return ""


func _write_shot(skill_id: String, key: String, original: PBSkill, path: String) -> String:
	var lines := FileAccess.get_file_as_string(skill_sheet).split("\n")
	var found: bool = false
	for i: int in lines.size():
		var row := lines[i].strip_edges().split("\t")
		if row.size() != 11 or row[0] != skill_id:
			continue
		var extras := PackedStringArray()
		for extra: String in row[10].split(";", false):
			if not extra.begins_with("shot="):
				extras.append(extra)
		if key != "":
			extras.append("shot=" + key)
		row[10] = ";".join(extras)
		lines[i] = "\t".join(row)
		found = true
	if not found:
		return "技能表中没有此 ID。"
	var copy := original.duplicate() as PBSkill
	copy.shot_key = StringName(key)
	var file := FileAccess.open(skill_sheet, FileAccess.WRITE)
	if file == null:
		return "技能表无法写入。"
	file.store_string("\n".join(lines))
	file.close()
	var saved := ResourceSaver.save(copy, path)
	if saved == OK:
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return "" if saved == OK else "表已更新，资源保存失败；请重新生成技能。"


static func keep_extra_animations(previous: PBActorSkin, frames: SpriteFrames) -> void:
	if previous == null or previous.frames == null:
		return
	for anim: StringName in previous.frames.get_animation_names():
		if frames.has_animation(anim) or anim == &"default":
			continue
		frames.add_animation(anim)
		frames.set_animation_loop(anim, previous.frames.get_animation_loop(anim))
		frames.set_animation_speed(anim, previous.frames.get_animation_speed(anim))
		for i: int in previous.frames.get_frame_count(anim):
			frames.add_frame(
				anim,
				previous.frames.get_frame_texture(anim, i),
				previous.frames.get_frame_duration(anim, i)
			)


func _save_skin(skin: PBActorSkin, path: String) -> String:
	var err := ResourceSaver.save(skin, path)
	if err == OK:
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	PBActorLibrary.reload()
	return "" if err == OK else "形象保存失败：%d" % err
