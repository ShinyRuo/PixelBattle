class_name PBTravelWave
extends PBSkillBarrage
## 每一道波前进并扩大，同一目标在本道只受击一次；不同道各自保存名单。
## 起点 / 伤害在施放时固定，方向在发射时确定；死亡不撤回已排期的波。

var direction: Vector2 = Vector2.RIGHT
var struck: PackedInt32Array = PackedInt32Array()
var launch_at: int = -1
var _launched: bool = false


func begin(source: PBAttacker, original: PBSkillCast, tick: int) -> void:
	super.begin(source, original, tick)
	launch_at = tick
	next_at = tick + cast.skill.hit_interval_ticks
	direction = Vector2.RIGHT
	struck.clear()
	_launched = false


func spot_at(index: int) -> Vector2:
	return center + direction * cast.skill.travel_step * (index + 1)


func advance(
	enemies: Array[PBEnemy],
	_front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog
) -> int:
	if not active():
		return 0
	if not _launched and tick >= launch_at:
		_launch(enemies, tick, rng)
	if tick < next_at:
		return 0
	cast.spot = spot_at(fired)
	cast.skill.radius = _first_radius + cast.skill.radius_growth * fired
	var picked: Array[PBEnemy] = []
	for enemy: PBEnemy in enemies:
		if (
			enemy.is_hostile(tick)
			and not struck.has(enemy.slot)
			and PBSkillArea.contains(cast.skill, center, cast.spot, enemy.pos())
		):
			struck.append(enemy.slot)
			picked.append(enemy)
	fired += 1
	last_at = tick
	next_at = tick + cast.skill.hit_interval_ticks if fired < cast.skill.hit_count else -1
	if picked.is_empty():
		return 0
	var rolled := PBCritRules.hit(caster, cast.skill.damage, cast.skill.kind, tick, rng)
	return PBSkillRules.land(
		cast,
		picked,
		0,
		cfg,
		tick,
		caster,
		rolled[PBCritRules.DAMAGE],
		book,
		rolled[PBCritRules.CRIT]
	)


func _launch(enemies: Array[PBEnemy], tick: int, rng: RandomNumberGenerator) -> void:
	_launched = true
	if caster.aim_at >= 0 and caster.aim_at < enemies.size():
		var target: PBEnemy = enemies[caster.aim_at]
		if target.is_hostile(tick):
			var gap: Vector2 = target.pos() - caster.pos
			if gap.length_squared() > 0.00000001:
				direction = gap.normalized()
	var steps: int = cast.skill.fan_steps
	var offset: int = 0 if rng == null else rng.randi_range(-steps, steps)
	direction = direction.rotated(deg_to_rad(cast.skill.fan_spread_degrees * offset / steps))


static func validate_wave(skill: PBSkill) -> String:
	if (
		not is_finite(skill.travel_step)
		or skill.travel_step < 0.0
		or skill.wave_count < 0
		or skill.wave_interval_ticks < 0
		or not is_finite(skill.fan_spread_degrees)
		or skill.fan_spread_degrees < 0.0
		or skill.fan_spread_degrees > 180.0
		or skill.fan_steps < 1
	):
		return "移动波参数须有限非负，扇面不超过 180 度，方向细分须为正数"
	if skill.travel_step == 0.0:
		return (
			"波数量 / 扇面需要正移动步长"
			if (
				skill.wave_count > 0
				or skill.wave_interval_ticks > 0
				or skill.fan_spread_degrees > 0.0
				or skill.fan_steps != 1
			)
			else ""
		)
	if (
		skill.target != PBSkill.Target.GROUND
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.hit_count <= 1
		or skill.hit_interval_ticks <= 0
		or skill.radius <= 0.0
		or skill.wave_count <= 0
		or skill.wave_interval_ticks <= 0
		or skill.line_length != 0.0
		or skill.hit_step != 0.0
		or skill.hit_radius != 0.0
		or skill.pulse_radius_step != 0.0
	):
		return "移动波需要地面多段圆形敌方技能、正数量 / 间隔，不能混用直线或逐段选人"
	return ""
