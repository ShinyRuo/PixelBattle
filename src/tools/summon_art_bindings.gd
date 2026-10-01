@tool
class_name PBSummonArtBindings
extends RefCounted

var binding_dir: String = "res://data/summon_art"
var actor_dir: String = "res://data/actors"
var shot_dir: String = "res://data/shots"
var spawn_dir: String = "res://data/instant_buff_art"
var skill_dir: String = "res://data/skills"


func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: PackedStringArray in PBArtBindings.new().skills():
		var skill := _skill(row[0])
		if skill != null and (skill.summon_count > 0 or skill.phantom_count > 0):
			result.append({"id": row[0], "label": "%s · %s · %s" % [row[2], row[1], row[0]]})
	return result


func read(id: String) -> PBSummonArt:
	var path := "%s/%s.tres" % [binding_dir, id]
	if id.is_valid_identifier() and ResourceLoader.exists(path):
		var art := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBSummonArt
		if art != null:
			return art
	return PBSummonArt.new()


func keys(directory: String) -> PackedStringArray:
	var result := PackedStringArray()
	if DirAccess.dir_exists_absolute(directory):
		for file: String in DirAccess.get_files_at(directory):
			if file.ends_with(".tres"):
				result.append(file.get_basename())
	result.sort()
	return result


func assign(id: String, actor: String, shot: String, spawn: String = "") -> String:
	var skill := _skill(id)
	if skill == null or (skill.summon_count <= 0 and skill.phantom_count <= 0):
		return "请选择已有独立召唤单位的技能。"
	var error := _actor_error(actor)
	if error != "":
		return error
	error = _shot_error(shot)
	if error != "":
		return error
	error = _spawn_error(spawn)
	if error != "":
		return error
	var art := PBSummonArt.new()
	art.actor_key = StringName(actor)
	art.shot_key = StringName(shot)
	art.spawn_fx_key = StringName(spawn)
	var made := DirAccess.make_dir_recursive_absolute(binding_dir)
	if made != OK:
		return error_string(made)
	var saved := ResourceSaver.save(art, "%s/%s.tres" % [binding_dir, id])
	PBSummonArt.clear_cache()
	return "" if saved == OK else error_string(saved)


func _skill(id: String) -> PBSkill:
	if not id.is_valid_identifier():
		return null
	var path := "%s/%s.tres" % [skill_dir, id]
	return load(path) as PBSkill if ResourceLoader.exists(path) else null


func _actor_error(key: String) -> String:
	if key == "":
		return ""
	var path := "%s/%s.tres" % [actor_dir, key]
	if not key.is_valid_identifier() or not ResourceLoader.exists(path):
		return "请先在战场形象工具生成形象表。"
	var art := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBActorSkin
	if art == null or art.frames == null or (art.key != &"" and art.key != StringName(key)):
		return "形象资源无效，或形象键与文件名不一致。"
	for anim: StringName in [art.anim_idle, art.anim_run, art.anim_attack, art.anim_dead]:
		if not art.frames.has_animation(anim) or art.frames.get_frame_count(anim) != 6:
			return "召唤物需要 idle / run / attack / dead 四段，每段六帧。"
	return ""


func _shot_error(key: String) -> String:
	if key == "":
		return ""
	var path := "%s/%s.tres" % [shot_dir, key]
	if not key.is_valid_identifier() or not ResourceLoader.exists(path):
		return "请先在子弹页生成命名子弹。"
	var art := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBShotSkin
	if art == null or not art.has(art.anim_fly) or (art.key != &"" and art.key != StringName(key)):
		return "子弹资源缺少飞行段。"
	return "" if art.frames.get_frame_count(art.anim_fly) > 0 else "子弹飞行段为空。"


func _spawn_error(key: String) -> String:
	if key == "":
		return ""
	var path := "%s/%s.tres" % [spawn_dir, key]
	if not key.is_valid_identifier() or not ResourceLoader.exists(path):
		return "请先在环身光工具生成出生烟资源。"
	var art := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBBuffSkin
	return "" if art != null and art.problem() == "" and art.front_frames.size() == 6 else "出生烟须有六帧前层。"
