class_name PBExpandingStrike
extends PBSkillBarrage
## 圆心在出手时固定；每段扩圈并从未命中的敌人中选最近一个，槽位用于等距排序。
## 没有目标也消耗这一段；不重复打同一目标。移动、死亡不撤回已经放出的波。

var struck: PackedInt32Array = PackedInt32Array()
var last_target: int = -1
var inherited_attack: float = 0.0


func begin(source: PBAttacker, original: PBSkillCast, tick: int) -> void:
	super.begin(source, original, tick)
	spread = original.skill.radius
	cast.skill.radius = 0.0
	cast.origin = center
	next_at = tick + cast.skill.hit_interval_ticks
	struck.clear()
	last_target = -1
	inherited_attack = (
		float(source.damage_attributes.get(&"attack", source.attack))
		+ source.base_attack * PBAllyAuraRules.bonus_rate(source, tick)
	)


func radius_at(step: int) -> float:
	return spread - (cast.skill.hit_count - step) * cast.skill.pulse_radius_step


func visual_radius() -> float:
	return radius_at(maxi(fired, 1))


func visual_spot() -> Vector2:
	return center


func advance(
	enemies: Array[PBEnemy],
	_front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog
) -> int:
	if not active() or tick < next_at:
		return 0
	fired += 1
	last_at = tick
	next_at = tick + cast.skill.hit_interval_ticks if fired < cast.skill.hit_count else -1
	var enemy: PBEnemy = _nearest(enemies, tick, radius_at(fired))
	if enemy == null:
		if not active():
			PBPhantomRules.finish(self, enemies, cfg)
		return 0
	struck.append(enemy.slot)
	last_target = enemy.slot
	cast.spot = enemy.pos()
	var raw: float = cast.skill.damage * (1.0 + cast.skill.pulse_damage_step * fired)
	var rolled := PBCritRules.hit(caster, raw, cast.skill.kind, tick, rng)
	var kills: int = PBSkillRules.land(
		cast,
		[enemy],
		0,
		cfg,
		tick,
		caster,
		rolled[PBCritRules.DAMAGE],
		book,
		rolled[PBCritRules.CRIT]
	)
	PBPhantomRules.raise_at(self, enemy, cfg, tick)
	if not active():
		PBPhantomRules.finish(self, enemies, cfg)
	return kills


func _nearest(enemies: Array[PBEnemy], tick: int, radius: float) -> PBEnemy:
	var best: PBEnemy = null
	var distance: float = INF
	for enemy: PBEnemy in enemies:
		if not enemy.is_hostile(tick) or struck.has(enemy.slot):
			continue
		var gap: float = center.distance_squared_to(enemy.pos())
		if gap > radius * radius + 0.0000001:
			continue
		if gap < distance or (gap == distance and best != null and enemy.slot < best.slot):
			best = enemy
			distance = gap
	return best


static func validate_pulse(skill: PBSkill) -> String:
	for value: float in [skill.pulse_radius_step, skill.pulse_damage_step]:
		if not is_finite(value) or value < 0.0:
			return "逐段扩圈参数必须是有限非负数"
	if skill.pulse_radius_step == 0.0:
		return "递增伤害需要逐段扩圈" if skill.pulse_damage_step != 0.0 else ""
	if (
		skill.hit_count <= 1
		or skill.target != PBSkill.Target.NONE
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.shot_cross_seconds > 0.0
		or skill.hit_radius != 0.0
		or skill.hit_step != 0.0
		or skill.max_targets != skill.hit_count
		or skill.radius <= (skill.hit_count - 1) * skill.pulse_radius_step
	):
		return "逐段扩圈仅支持自身圆心、多段单目标；总目标数等于段数，首段半径须为正"
	return ""
