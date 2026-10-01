@tool
class_name PBBuffArtBindings
extends RefCounted
## 只保存美术资源，不修改 BUFF 的数值定义。

var output_dir: String = "res://data/buff_art"


func read(id: String) -> PBBuffSkin:
	var path := "%s/%s.tres" % [output_dir, id]
	var skin := (
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBBuffSkin
		if ResourceLoader.exists(path)
		else null
	)
	return skin.duplicate() as PBBuffSkin if skin != null else PBBuffSkin.new()


func save(id: String, skin: PBBuffSkin) -> String:
	if id.is_empty() or not id.is_valid_identifier():
		return "BUFF 键不合法"
	var problem := skin.problem()
	if problem != "":
		return problem
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := ResourceSaver.save(skin, "%s/%s.tres" % [output_dir, id])
	PBBuffGlow._library.erase(StringName(id))
	return "" if error == OK else "保存失败：%s" % error_string(error)


func import_layer(skin: PBBuffSkin, paths: PackedStringArray, front: bool) -> String:
	var ordered: Array[String] = []
	ordered.assign(paths)
	ordered.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var textures: Array[Texture2D] = []
	for path: String in ordered:
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			return "请先将 PNG 放入 assets 并等待 Godot 导入"
		var texture := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		if texture == null:
			return "请选择贴图帧"
		textures.append(texture)
	var trial := skin.duplicate() as PBBuffSkin
	if front:
		trial.front_frames = textures
	else:
		trial.back_frames = textures
	var problem := trial.problem()
	if problem != "":
		return problem
	skin.front_frames = trial.front_frames
	skin.back_frames = trial.back_frames
	skin.placeholder = false
	return ""
