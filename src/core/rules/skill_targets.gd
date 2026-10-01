class_name PBSkillTargets
extends RefCounted
## 锁定技能只选择一次：主目标优先，追加目标按距离、槽位排序；主目标失效则全部空放。
## 半径是追加目标的搜索范围，不是伤害范围。返回名单后不可在每次命中时再次扩散。


static func locked(skill: PBSkill) -> bool:
	return skill.target in [PBSkill.Target.ALLY, PBSkill.Target.ENEMY] and skill.radius == 0.0


static func add_count(skill: PBSkill, amount: int) -> void:
	if locked(skill):
		skill.max_targets = maxi(maxi(skill.max_targets, 1) + amount, 1)
	elif skill.max_targets > 0:
		skill.max_targets = maxi(skill.max_targets + amount, 1)
	# 范围不限的 0 不能因“增加目标”反而变成限制。


static func allies(
	cast: PBSkillCast, units: Array[PBAttacker], caster: PBAttacker = null
) -> PackedInt32Array:
	var primary: int = cast.target_slot
	if (
		primary < 0
		or primary >= units.size()
		or not PBSacrificeRules.can_target(cast.skill, units[primary], caster)
	):
		return PackedInt32Array()
	if cast.skill.max_targets <= 1:
		return PackedInt32Array([primary])
	var points: Dictionary = {}
	for i: int in units.size():
		if PBSacrificeRules.can_target(cast.skill, units[i], caster):
			points[i] = units[i].pos
	return _ordered(primary, cast, points)


static func enemies(cast: PBSkillCast, units: Array[PBEnemy], tick: int) -> PackedInt32Array:
	var primary: int = cast.target_slot
	if primary < 0 or primary >= units.size() or not units[primary].is_hostile(tick):
		return PackedInt32Array()
	if cast.skill.max_targets <= 1 or not locked(cast.skill):
		return PackedInt32Array([primary])
	var points: Dictionary = {}
	for i: int in units.size():
		if units[i].is_hostile(tick):
			points[i] = units[i].pos()
	return _ordered(primary, cast, points)


static func _ordered(primary: int, cast: PBSkillCast, points: Dictionary) -> PackedInt32Array:
	var selected := PackedInt32Array([primary])
	var skill: PBSkill = cast.skill
	var origin: Vector2 = cast.origin if skill.extra_target_from_caster else points[primary]
	if not PBSkillCast.is_spot(origin):
		return selected
	points.erase(primary)
	while selected.size() < skill.max_targets:
		var best: int = -1
		var distance: float = INF
		for index: int in points:
			var squared: float = origin.distance_squared_to(points[index])
			if squared > skill.extra_target_radius * skill.extra_target_radius + 0.0000001:
				continue
			if squared < distance or (squared == distance and index < best):
				best = index
				distance = squared
		if best < 0:
			break
		selected.append(best)
		points.erase(best)
	return selected


static func validate(skill: PBSkill) -> String:
	if (
		skill.max_targets < 0
		or not is_finite(skill.extra_target_radius)
		or skill.extra_target_radius < 0
	):
		return "目标上限不能为负，追加目标范围必须有限且非负"
	if skill.extra_target_radius > 0.0 and not locked(skill):
		return "追加目标范围只能用于零伤害半径的锁定技能"
	if locked(skill) and skill.max_targets > 1:
		if skill.extra_target_radius <= 0.0:
			return "多目标锁定技能必须指定追加目标范围"
		if skill.delay_ticks > 0 or skill.blink_to_target or skill.summon_count > 0:
			return "追加目标暂不支持延迟阶段、闪烁或召唤技能"
	return ""
