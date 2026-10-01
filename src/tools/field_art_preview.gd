@tool
class_name PBFieldArtPreview
extends Node2D

var skin: PBFieldSkin
var kind: String = "areas"
var skill: PBSkill
var zoom: float = 1.0
var paused: bool = false
var selected_frame: int = 0
var guides: bool = true
var _age: float = 0.0


func _process(delta: float) -> void:
	if not paused:
		_age += delta
	queue_redraw()


func radius_units() -> float:
	if skill == null:
		return 0.15
	if kind == "areas" and PBFieldArt.supports_enemy_aura_area(skill):
		return skill.enemy_aura_radius
	if kind == "areas" and PBFieldArt.supports_scatter_area(skill):
		return skill.hit_radius
	return skill.zone_radius if kind == "zones" else skill.radius


func control_radius_units() -> float:
	return skill.control_radius if skill != null and kind != "zones" else 0.0


func range_text() -> String:
	if kind == "links":
		return "连线按端点拉伸；没有独立圆形伤害判定"
	var text := (
		"黄线：真实判定半径 %.4f 战场单位（%.0f码） · %d 个圆"
		% [radius_units(), radius_units() * 2000, centers().size()]
	)
	if control_radius_units() > 0:
		text += "\n粉线：控制半径 %.4f（%.0f码）" % [control_radius_units(), control_radius_units() * 2000]
	if skill != null and kind == "startups":
		text += (
			"\n释放后循环蓄势 %.2f秒；首段伤害时结束"
			% (float(skill.pulse_delay_ticks) / PBSimConfig.new().tick_rate)
		)
	elif kind == "areas" and skill != null and PBFieldArt.supports_enemy_aura_area(skill):
		text += "\n随施术者移动循环播放；离开战场或倒下后撤除"
	elif kind == "areas" and skill != null and PBFieldArt.supports_expanding_self_area(skill):
		text += "\n%d 次逐段扩圈；黄线显示最后一段最大半径" % skill.hit_count
	elif kind == "areas":
		text += "\n实际落地时单次播放；此处循环仅便于检查"
	return text + "\n青框：特效完整画布（含透明留白）；白十字：落点"


func centers() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	if kind != "zones" or skill == null:
		return points
	for ring: Vector2 in [
		Vector2(skill.zone_ring_count, skill.zone_ring_radius),
		Vector2(skill.zone_outer_count, skill.zone_outer_radius)
	]:
		for i: int in int(ring.x):
			var angle := TAU * float(i + 1) / ring.x
			points.append(Vector2(cos(angle), sin(angle)) * ring.y)
	return points


func _draw() -> void:
	if skin == null or skin.problem() != "":
		return
	var age := float(selected_frame) / skin.fps if paused else _age
	if kind == "links":
		draw_circle(Vector2(-90, 0), 4, Color.GRAY)
		draw_circle(Vector2(90, 0), 4, Color.GRAY)
		PBFieldArt.draw_link(self, skin, Vector2(-90, 0), Vector2(90, 0), age)
		return
	var pixels := PBLayout.px_per_unit(Vector2.ONE) * zoom
	var radius := radius_units() * pixels
	for point: Vector2 in centers():
		var at := point * pixels * Vector2(1, PBLayout.Y_SCALE)
		PBFieldArt.draw_area(self, skin, at, radius, age, true)
		if guides:
			draw_polyline(PBLayout.ground_disc(at, radius), Color(1, 0.8, 0.15), 2, true)
			if control_radius_units() > 0:
				draw_polyline(
					PBLayout.ground_disc(at, control_radius_units() * pixels),
					Color(1, 0.4, 0.8),
					1,
					true
				)
			draw_rect(PBFieldArt.area_rect(skin, at, radius), Color(0.15, 0.8, 1), false, 1)
			draw_line(at - Vector2(5, 0), at + Vector2(5, 0), Color.WHITE)
			draw_line(at - Vector2(0, 5), at + Vector2(0, 5), Color.WHITE)
