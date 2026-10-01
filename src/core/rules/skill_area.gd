class_name PBSkillArea
extends RefCounted
## 圆形与定向直线技能的唯一命中形状；界面从同一份顶点画预示区域。


static func contains(skill: PBSkill, origin: Vector2, spot: Vector2, point: Vector2) -> bool:
	if skill.line_length <= 0.0:
		return point.distance_to(spot) <= skill.radius + 0.0000001
	if not PBSkillCast.is_spot(origin):
		return false
	var direction: Vector2 = heading(origin, spot)
	var offset: Vector2 = point - origin
	var along: float = offset.dot(direction)
	return (
		along >= 0.0
		and along <= skill.line_length
		and absf(offset.cross(direction)) <= skill.radius
	)


## 零长度瞄准时朝敌人出生方向；施法后使用原点与方向快照，不随人移动。
static func heading(origin: Vector2, spot: Vector2) -> Vector2:
	var gap: Vector2 = spot - origin
	return gap.normalized() if gap.length_squared() > 0.00000001 else Vector2.RIGHT


static func outline(skill: PBSkill, origin: Vector2, spot: Vector2) -> PackedVector2Array:
	var direction := heading(origin, spot)
	var side := Vector2(-direction.y, direction.x) * skill.radius
	var end: Vector2 = origin + direction * skill.line_length
	return PackedVector2Array([origin + side, end + side, end - side, origin - side, origin + side])


static func validate(skill: PBSkill) -> String:
	if not is_finite(skill.control_radius) or skill.control_radius < 0:
		return "控制半径必须为有限非负数"
	if (
		skill.control_radius > 0
		and (
			skill.target != PBSkill.Target.GROUND
			or skill.affects != PBSkill.Party.ENEMIES
			or skill.control_radius > skill.radius
			or skill.line_length > 0
			or skill.on_hit.is_empty() and skill.on_start_area.is_empty()
		)
	):
		return "独立控制半径只支持固定地面效果且不得超过伤害半径"
	if not is_finite(skill.line_length) or skill.line_length < 0.0:
		return "直线长度必须是有限非负数"
	if skill.line_length == 0.0:
		return ""
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.hit_count != 1
		or not is_finite(skill.radius)
		or skill.radius <= 0.0
		or skill.center_scale != 1.0
		or skill.target_hp != 0.0
	):
		return "直线只支持有正半宽的单段地面敌方技能，不支持中心衰减或目标生命公式"
	return ""
