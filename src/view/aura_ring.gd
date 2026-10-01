class_name PBAuraRing
extends Node2D
## 选中光环载体时画绿色虚线，和蓝色普攻射程圈区分；只读实际技能范围。
## 放在战场裁切层里，圈再大也不覆盖基地、信息栏和指令卡。

const EDGE := Color(0.45, 0.9, 0.65, 0.8)
const SEGMENTS: int = 64

var center: Vector2 = Vector2.ZERO
var radius_px: float = 0.0


func _ready() -> void:
	var clip := get_parent() as Control
	if clip != null and clip.clip_contents:
		clip.position = PBLayout.B_FIELD.position
		clip.size = PBLayout.B_FIELD.size
		position = -clip.position


func sync_live(unit: PBAttacker, field: Vector2) -> void:
	if unit == null or not unit.is_targetable():
		clear()
		return
	var radius: float = 0.0
	for cast: PBSkillCast in unit.skills:
		radius = maxf(radius, _aura_radius(cast.skill))
	_show_radius(unit.pos, radius, field)


func sync_preview(at: Vector2, skills: Array[PBSkill], field: Vector2) -> void:
	var radius: float = 0.0
	for skill: PBSkill in skills:
		radius = maxf(radius, _aura_radius(skill))
	_show_radius(at, radius, field)


func clear() -> void:
	if radius_px == 0.0:
		return
	radius_px = 0.0
	queue_redraw()


func _aura_radius(skill: PBSkill) -> float:
	if skill != null and skill.enemy_aura_radius > 0.0:
		return skill.enemy_aura_radius
	if (
		skill != null
		and (
			skill.ranged_attack_aura > 0.0
			or PBMotionAuraRules.enabled(skill)
			or PBHealingAuraRules.enabled(skill)
		)
	):
		return skill.radius
	return 0.0


func _show_radius(at: Vector2, radius: float, field: Vector2) -> void:
	var point: Vector2 = PBLayout.to_screen(at, field)
	var size: float = radius * PBLayout.px_per_unit(field)
	if center == point and radius_px == size:
		return
	center = point
	radius_px = size
	queue_redraw()


func _draw() -> void:
	if radius_px <= 0.0:
		return
	var ring := PBLayout.ground_disc(center, radius_px, SEGMENTS)
	for i: int in range(0, ring.size() - 1, 2):
		draw_line(ring[i], ring[i + 1], EDGE, 1.2)
	var label_at: Vector2 = center + Vector2(radius_px * 0.65, -radius_px * PBLayout.Y_SCALE * 0.65)
	label_at.x = clampf(
		label_at.x, PBLayout.B_FIELD.position.x + 4.0, PBLayout.B_FIELD.end.x - 22.0
	)
	label_at.y = clampf(
		label_at.y, PBLayout.B_FIELD.position.y + 10.0, PBLayout.B_FIELD.end.y - 4.0
	)
	draw_string(ThemeDB.fallback_font, label_at, "光环", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, EDGE)
