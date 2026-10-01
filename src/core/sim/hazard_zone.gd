class_name PBHazardZone
extends PBSkillBarrage
## 固定伤害圆与多个减益光环各自有范围、时长。来源死亡不撤销已出手区域。
## 同一区域的重叠光环只刷新一次，不累计同名减益；数值在建立时保存快照。

var aura_until: int = -1
var generation: int = 0
var points: PackedVector2Array = PackedVector2Array()
var _values: Array[Dictionary] = []
var _ring_values: Array[Dictionary] = []


func active() -> bool:
	return next_at >= 0 or aura_until >= 0


func begin(source: PBAttacker, original: PBSkillCast, tick: int) -> void:
	generation += 1
	super.begin(source, original, tick)
	cast.spot = center
	next_at = tick + cast.skill.hit_interval_ticks
	aura_until = tick + roundi(cast.skill.zone_seconds * source._motion_tick_rate)
	points = PackedVector2Array([center])
	for i: int in cast.skill.zone_ring_count:
		var angle: float = TAU * float(i + 1) / cast.skill.zone_ring_count
		points.append(center + Vector2(cos(angle), sin(angle)) * cast.skill.zone_ring_radius)
	for i: int in cast.skill.zone_outer_count:
		var angle: float = TAU * float(i + 1) / cast.skill.zone_outer_count
		points.append(center + Vector2(cos(angle), sin(angle)) * cast.skill.zone_outer_radius)
	_values.clear()
	for buff: PBBuff in cast.skill.zone_effects:
		_values.append(PBBuffRules.resolve(buff, cast.caster_level))
	_ring_values.clear()
	for buff: PBBuff in cast.skill.zone_ring_effects:
		_ring_values.append(PBBuffRules.resolve(buff, cast.caster_level))


func covers(point: Vector2, include_center: bool = true) -> bool:
	for i: int in range(0 if include_center else 1, points.size()):
		if point.distance_to(points[i]) <= cast.skill.zone_radius + 0.0000001:
			return true
	return false


func advance(
	enemies: Array[PBEnemy],
	front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog
) -> int:
	if not active():
		return 0
	if tick >= aura_until:
		aura_until = -1
	if tick < aura_until:
		for i: int in range(front, enemies.size()):
			var enemy: PBEnemy = enemies[i]
			if not enemy.has_spawned(tick):
				break
			if not enemy.is_hostile(tick) or not covers(enemy.pos()):
				continue
			_apply(enemy, cast.skill.zone_effects, _values, cfg, tick)
			if not _ring_values.is_empty() and covers(enemy.pos(), false):
				_apply(enemy, cast.skill.zone_ring_effects, _ring_values, cfg, tick)
	return super.advance(enemies, front, cfg, tick, rng, book) if next_at >= 0 else 0


func _apply(
	enemy: PBEnemy, effects: Array[PBBuff], values: Array[Dictionary], cfg: PBSimConfig, tick: int
) -> void:
	for i: int in effects.size():
		var buff: PBBuff = effects[i]
		enemy.buffs.add(
			buff, values[i], tick, buff.duration_ticks(cfg, cast.caster_level), 0, caster.slot
		)


static func validate_zone(skill: PBSkill) -> String:
	for value: float in [
		skill.zone_seconds, skill.zone_radius, skill.zone_ring_radius, skill.zone_outer_radius
	]:
		if not is_finite(value) or value < 0.0:
			return "地面光环时长与半径必须为有限非负数"
	if skill.zone_seconds == 0.0:
		if (
			not skill.zone_effects.is_empty()
			or not skill.zone_ring_effects.is_empty()
			or skill.zone_radius != 0.0
			or skill.zone_ring_radius != 0.0
			or skill.zone_ring_count != 0
			or skill.zone_outer_count != 0
			or skill.zone_outer_radius != 0.0
		):
			return "未启用地面区域却配置光环"
		return ""
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.hit_count < 2
		or skill.zone_radius <= 0.0
		or skill.zone_ring_count < 0
		or skill.zone_ring_count > 32
		or skill.zone_outer_count < 0
		or skill.zone_outer_count + skill.zone_ring_count > 32
		or ((skill.zone_outer_count == 0) != (skill.zone_outer_radius == 0.0))
		or ((skill.zone_ring_count == 0) != (skill.zone_ring_radius == 0.0))
		or skill.zone_effects.is_empty()
		or skill.hit_radius != 0.0
		or skill.radius_growth != 0.0
		or skill.travel_step != 0.0
		or skill.pulse_radius_step != 0.0
	):
		return "地面光环需要固定圆形多段技能、正半径及持续效果，环形载体最多 32 个"
	for buff: PBBuff in skill.zone_effects + skill.zone_ring_effects:
		if buff == null or buff.kind != PBBuff.Kind.DURATION:
			return "地面光环只允许持续型效果"
	return ""
