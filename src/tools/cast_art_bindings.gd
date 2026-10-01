@tool
class_name PBCastArtBindings
extends RefCounted

var art_dir: String = "res://data/cast_art"
var binding_dir: String = "res://data/skill_art"
var skill_dir: String = "res://data/skills"


func keys() -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(art_dir):
		return result
	for file: String in DirAccess.get_files_at(art_dir):
		if file.ends_with(".tres"):
			result.append(file.get_basename())
	result.sort()
	return result


func read(id: String) -> StringName:
	var path := "%s/%s.tres" % [binding_dir, id]
	if not ResourceLoader.exists(path):
		return &""
	var binding := (
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBSkillStartArt
	)
	return binding.start_key if binding != null else &""


func assign(id: String, key: String) -> String:
	if not id.is_valid_identifier() or not ResourceLoader.exists("%s/%s.tres" % [skill_dir, id]):
		return "请选择有效技能。"
	if key != "":
		if not key.is_valid_identifier():
			return "光效键不合法。"
		var path := "%s/%s.tres" % [art_dir, key]
		if not ResourceLoader.exists(path):
			return "请先在起手光效页生成资源。"
		var skin := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBBuffSkin
		if skin == null or skin.problem() != "":
			return "起手光资源无效。"
	var binding := PBSkillStartArt.new()
	var saved_path := "%s/%s.tres" % [binding_dir, id]
	if ResourceLoader.exists(saved_path):
		binding = ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if binding == null:
			return "技能美术配置无效。"
	binding.start_key = StringName(key)
	DirAccess.make_dir_recursive_absolute(binding_dir)
	var error := ResourceSaver.save(binding, "%s/%s.tres" % [binding_dir, id])
	PBCastGlow.clear_cache()
	return "" if error == OK else error_string(error)
