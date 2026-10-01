@tool
class_name PBFieldArt
extends RefCounted
## 光效只读取状态，不配置数值；尚未接通的区域类型拒绝绑定。

static var _cache: Dictionary = {}


static func supports_area(skill: PBSkill) -> bool:
	return (
		skill.target == PBSkill.Target.GROUND
		and skill.radius > 0.0
		and skill.hit_count == 1
		and skill.hit_count_levels.is_empty()
		and skill.zone_seconds == 0.0
		and skill.line_length == 0.0
		and skill.travel_step == 0.0
		and skill.hit_step == 0.0
		and skill.hit_radius == 0.0
		and skill.radius_growth == 0.0
		and skill.pulse_radius_step == 0.0
	)


static func supports_attack_chain_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.GROUND
		and skill.attack_chain_count > 0
		and skill.attack_chain_step > 0.0
		and skill.radius > 0.0
	)


static func supports_self_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.NONE
		and skill.radius > 0.0
		and skill.hit_count == 1
		and skill.hit_count_levels.is_empty()
		and skill.zone_seconds == 0.0
		and skill.pulse_radius_step == 0.0
	)


static func supports_target_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.ENEMY
		and skill.radius > 0.0
		and skill.hit_count == 1
		and skill.hit_count_levels.is_empty()
		and skill.zone_seconds == 0.0
		and skill.shot_cross_seconds == 0.0
	)


static func supports_forward_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.NONE
		and skill.affects == PBSkill.Party.ENEMIES
		and skill.radius > 0.0
		and skill.hit_count > 1
		and skill.hit_step > 0.0
		and skill.scatter_steps == 0
	)


static func supports_expanding_ground_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.GROUND
		and skill.radius > 0.0
		and skill.hit_count > 1
		and skill.radius_growth > 0.0
		and skill.line_length == 0.0
		and skill.travel_step == 0.0
		and skill.hit_step == 0.0
		and skill.scatter_steps == 0
	)


static func supports_self_barrage_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.NONE
		and skill.affects == PBSkill.Party.ENEMIES
		and skill.radius > 0.0
		and skill.hit_count > 1
		and skill.hit_step == 0.0
		and skill.scatter_steps == 0
		and skill.radius_growth == 0.0
		and skill.pulse_radius_step == 0.0
	)


static func supports_scatter_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.NONE
		and skill.affects == PBSkill.Party.ENEMIES
		and skill.hit_count > 1
		and skill.scatter_steps > 0
		and skill.volley_size > 0
		and skill.hit_radius > 0.0
	)


static func supports_travel_wave_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.GROUND
		and skill.affects == PBSkill.Party.ENEMIES
		and skill.travel_step > 0.0
		and skill.wave_count > 0
		and skill.hit_count > 1
		and skill.radius > 0.0
	)


static func supports_line_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.GROUND
		and skill.affects == PBSkill.Party.ENEMIES
		and skill.line_length > 0.0
		and skill.radius > 0.0
		and skill.hit_count == 1
	)


static func supports_enemy_aura_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.enemy_aura_radius > 0.0
		and not skill.enemy_aura_effects.is_empty()
	)


static func supports_expanding_self_area(skill: PBSkill) -> bool:
	return (
		skill != null
		and skill.target == PBSkill.Target.NONE
		and skill.affects == PBSkill.Party.ENEMIES
		and skill.hit_count > 1
		and skill.pulse_radius_step > 0.0
	)


static func supports_startup(skill: PBSkill) -> bool:
	return skill.pulse_delay_ticks > 0 and (supports_area(skill) or supports_persistent(skill))


static func read(kind: String, id: StringName) -> PBFieldSkin:
	var path := "res://data/field_art/%s/%s.tres" % [kind, id]
	if not _cache.has(path):
		var skin := load(path) as PBFieldSkin if ResourceLoader.exists(path) else null
		_cache[path] = skin if skin != null and skin.problem() == "" else null
	return _cache[path]


static func supports_persistent(skill: PBSkill) -> bool:
	return (
		skill.target == PBSkill.Target.GROUND
		and skill.radius > 0
		and skill.hit_count > 1
		and skill.line_length == 0
		and skill.travel_step == 0
		and skill.hit_step == 0
		and skill.hit_radius == 0
		and skill.radius_growth == 0
		and skill.pulse_radius_step == 0
	)


static func draw_area(
	node: Node2D,
	skin: PBFieldSkin,
	center: Vector2,
	radius: float,
	age: float,
	looped: bool = false
) -> void:
	if looped and age >= 0 and skin.duration() > 0:
		age = fmod(age, skin.duration())
	var box := area_rect(skin, center, radius)
	var frame := floori(age * skin.fps)
	if frame < 0 or age >= skin.duration():
		return
	if not skin.frames.is_empty():
		node.draw_texture_rect(
			skin.frames[mini(frame, skin.frames.size() - 1)], box, false, skin.tint
		)
	elif skin.placeholder:
		var color := skin.tint
		if not looped:
			color.a *= 1.0 - age / skin.duration()
		node.draw_colored_polygon(
			PBLayout.ground_disc(box.get_center(), radius * skin.area_scale, 24), color
		)


## 工具与战斗共用同一矩形，判定半径不随美术参数改变。
static func area_rect(skin: PBFieldSkin, center: Vector2, radius: float) -> Rect2:
	var half := Vector2(radius, radius * PBLayout.Y_SCALE) * skin.area_scale
	var offset := skin.area_offset * Vector2(radius, radius * PBLayout.Y_SCALE)
	return Rect2(center + offset - half, half * 2)


static func draw_link(
	node: Node2D, skin: PBFieldSkin, from: Vector2, to: Vector2, age: float
) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	if skin.frames.is_empty():
		if skin.placeholder:
			node.draw_line(from, to, skin.tint, skin.link_width)
		return
	node.draw_set_transform(from, (to - from).angle())
	var texture: Texture2D = skin.frames[floori(age * skin.fps) % skin.frames.size()]
	node.draw_texture_rect(
		texture, Rect2(0, -skin.link_width * 0.5, length, skin.link_width), false, skin.tint
	)
	node.draw_set_transform(Vector2.ZERO)
