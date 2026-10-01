@tool
class_name PBFieldArtBindings
extends RefCounted

var output_dir: String = "res://data/field_art"


func choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var children := _followup_names()
	var death_skills := _death_skill_ids()
	for line: String in FileAccess.get_file_as_string("res://data/skills.tsv").split("\n"):
		if line.begins_with("#") or line.strip_edges().is_empty():
			continue
		var row := line.split("\t")
		var skill := load("res://data/skills/%s.tres" % row[0]) as PBSkill
		if skill == null:
			continue
		var title: String = row[2]
		if children.has(skill.id):
			title += "（%s追加）" % children[skill.id]
		if PBFieldArt.supports_startup(skill):
			out.append({"kind": "startups", "id": row[0], "name": title + " · 蓄势区域"})
		if PBFieldArt.supports_attack_chain_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": title + " · 普攻触发连锁落点"})
		if children.has(skill.id) and PBFieldArt.supports_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": title + " · 单次落地"})
		if children.has(skill.id) and PBFieldArt.supports_expanding_ground_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": title + " · 逐次扩张落地"})
		if children.has(skill.id) and PBFieldArt.supports_travel_wave_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": title + " · 扇形推进区域"})
		if PBFieldArt.supports_persistent(skill):
			out.append({"kind": "pulses", "id": row[0], "name": title + " · 多段伤害区"})
			if skill.zone_seconds > 0:
				out.append({"kind": "zones", "id": row[0], "name": row[2] + " · 持续减益区"})
		if PBFieldArt.supports_enemy_aura_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": title + " · 随身压制区域"})
		var owner_path := "res://data/characters/%s.tres" % row[1]
		if not ResourceLoader.exists(owner_path):
			# 阵亡派生技能不占角色技能栏，但结算后仍有真实落地快照。
			if death_skills.has(skill.id) and PBFieldArt.supports_area(skill):
				out.append({"kind": "areas", "id": row[0], "name": title + " · 落地区域"})
			continue
		var owner := load(owner_path) as PBCharacter
		if owner == null or not owner.skill_ids.has(StringName(row[0])):
			continue
		if PBFieldArt.supports_area(skill) and not children.has(skill.id):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 落地区域"})
		if PBFieldArt.supports_self_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 自身瞬发区域"})
		if PBFieldArt.supports_self_barrage_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 自身连击区域"})
		if PBFieldArt.supports_expanding_self_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 自身逐段扩圈区域"})
		if PBFieldArt.supports_scatter_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 分散落点区域"})
		if PBFieldArt.supports_travel_wave_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 扇形推进区域"})
		if PBFieldArt.supports_line_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 直线拼接区域"})
		if PBFieldArt.supports_target_area(skill):
			out.append({"kind": "areas", "id": row[0], "name": row[2] + " · 锁定目标落地区域"})
		if skill.id == &"adamantine_chains":
			for buff: PBBuff in skill.on_hit:
				out.append({"kind": "links", "id": String(buff.id), "name": row[2] + " · 封锁连线"})
		if skill.sacrifice_transfer and skill.transfer_buff != null:
			out.append({"kind": "links", "id": String(skill.transfer_buff.id), "name": row[2] + " · 传递连线"})
		if skill.summon_lifesteal > 0.0:
			out.append({"kind": "links", "id": row[0], "name": row[2] + " · 吸血回流"})
		if skill.channel_control:
			for buff: PBBuff in skill.on_hit:
				if not seen.has(buff.id):
					out.append({"kind": "links", "id": String(buff.id), "name": row[2] + " · 控制连线"})
					seen[buff.id] = true
	return out


func _death_skill_ids() -> Dictionary:
	var ids: Dictionary = {}
	for bond: PBBond in PBGameData.config().bonds.all():
		for member: StringName in bond.member_skill_patches:
			for id: StringName in bond.member_skill_patches[member]:
				var patch: Dictionary = bond.member_skill_patches[member][id]
				if patch.has(PBSkillPatchRules.ON_DEATH):
					ids[id] = true
	return ids


func _followup_names() -> Dictionary:
	var names: Dictionary = {}
	for line: String in FileAccess.get_file_as_string("res://data/skills.tsv").split("\n"):
		if line.begins_with("#") or line.strip_edges().is_empty():
			continue
		var row := line.split("\t")
		var skill := load("res://data/skills/%s.tres" % row[0]) as PBSkill
		if skill != null and skill.followup_id != &"":
			names[skill.followup_id] = row[2]
	return names


func read(kind: String, id: String) -> PBFieldSkin:
	var path := "%s/%s/%s.tres" % [output_dir, kind, id]
	var skin := (
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBFieldSkin
		if ResourceLoader.exists(path)
		else null
	)
	return skin.duplicate() as PBFieldSkin if skin != null else PBFieldSkin.new()


func save(kind: String, id: String, skin: PBFieldSkin) -> String:
	var supported := false
	for row: Dictionary in choices():
		if row.kind == kind and row.id == id:
			supported = true
	if not supported:
		return "此技能尚无对应表现读点，不能绑定"
	var error := skin.problem()
	if error != "":
		return error
	var path := "%s/%s/%s.tres" % [output_dir, kind, id]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var result := ResourceSaver.save(skin, path)
	PBFieldArt._cache.erase(path)
	return "" if result == OK else error_string(result)


func import_frames(skin: PBFieldSkin, paths: PackedStringArray) -> String:
	paths = paths.duplicate()
	var ordered: Array[String] = []
	ordered.assign(paths)
	ordered.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var frames: Array[Texture2D] = []
	for path: String in ordered:
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			return "先将 PNG 放入 assets 并等待 Godot 导入"
		var texture := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		if texture == null:
			return "请选择 PNG 贴图"
		frames.append(texture)
	var trial := skin.duplicate() as PBFieldSkin
	trial.frames = frames
	var error := trial.problem()
	if error == "":
		skin.frames = frames
		skin.placeholder = false
		skin.tint = Color.WHITE
	return error
