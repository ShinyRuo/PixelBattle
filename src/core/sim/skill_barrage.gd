class_name PBSkillBarrage
extends RefCounted
## 一次已经出手的连击。地面连击允许重置冷却后多次施法并存，死亡不收回攻击。
## 自身周围连击默认原地持续施放，死亡或离开原地时终止；向前蔓延则出手后独立结算。

var caster: PBAttacker
var cast: PBSkillCast
var center: Vector2
var spread: float = 0.0
var fired: int = 0
var next_at: int = -1
var last_at: int = -1
var team: Array[PBAttacker] = []
var landings: Array[Vector2] = []
var _first_radius: float = 0.0
var _start_at: int = 0
var _start_effects_done: bool = false
var _area_index: int = 0


func active() -> bool:
	return next_at >= 0


func visual_radius() -> float:
	return cast.skill.radius


func visual_spot() -> Vector2:
	return cast.spot


func visual_spots() -> Array[Vector2]:
	return landings if cast.skill.scatter_steps > 0 else [visual_spot()]


func begin(source: PBAttacker, original: PBSkillCast, tick: int) -> void:
	caster = source
	cast = PBSkillCast.new(original.skill.clone(), original.caster_level)
	cast.skill.hit_count = original.skill.hits_at(original.caster_level)
	center = original.spot
	if original.skill.target == PBSkill.Target.NONE:
		center = source.pos
	cast.spot = center
	spread = original.skill.radius if original.skill.hit_radius > 0.0 else 0.0
	if spread > 0.0:
		cast.skill.radius = original.skill.hit_radius
	fired = 0
	next_at = tick + cast.skill.pulse_delay_ticks
	if cast.skill.scatter_steps > 0:
		next_at = tick + cast.skill.hit_interval_ticks
	landings.clear()
	_start_at = tick
	_start_effects_done = false
	_area_index = 0
	last_at = -1
	_first_radius = cast.skill.radius


## 等面积螺旋分布，首段在圆心；不消费暴击随机流。落点不追踪敌人。
func spot_at(index: int) -> Vector2:
	if cast.skill.hit_step > 0.0:
		return center + Vector2.RIGHT * cast.skill.hit_step * index
	var fraction: float = float(index) / float(maxi(cast.skill.hit_count - 1, 1))
	var angle: float = float(index) * PI * (3.0 - sqrt(5.0))
	return center + Vector2(cos(angle), sin(angle)) * spread * sqrt(fraction)


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
	if cast.skill.area_refresh_ticks.is_empty():
		if not _start_effects_done and tick >= _start_at:
			_start_effects_done = true
			_apply_start_area(enemies, front, cfg, tick)
	else:
		while _area_index < cast.skill.area_refresh_ticks.size():
			if tick < _start_at + cast.skill.area_refresh_ticks[_area_index]:
				break
			_apply_start_area(enemies, front, cfg, tick)
			_area_index += 1
	if tick < next_at:
		return 0
	if (
		cast.skill.target == PBSkill.Target.NONE
		and cast.skill.hit_step == 0.0
		and cast.skill.scatter_steps == 0
		and (not caster.alive or caster.pos != center)
	):
		next_at = -1
		return 0
	landings.clear()
	var kills := 0
	for pulse: int in mini(cast.skill.volley_size, cast.skill.hit_count - fired):
		if cast.skill.scatter_steps > 0:
			center = caster.pos
			# 无 RNG 的估值/诊断沿用确定性分布；真实战斗只消费传入的 combat 流。
			var ring := 1 + fired % cast.skill.scatter_steps
			var angle := float(fired) * PI * (3.0 - sqrt(5.0))
			if rng != null:
				ring = rng.randi_range(1, cast.skill.scatter_steps)
				angle = rng.randf_range(0.0, TAU)
			cast.spot = (
				center + Vector2.from_angle(angle) * spread * ring / cast.skill.scatter_steps
			)
		else:
			cast.spot = spot_at(fired)
		landings.append(cast.spot)
		cast.skill.radius = _first_radius + cast.skill.radius_growth * fired
		kills += _land(enemies, front, cfg, tick, rng, book)
		fired += 1
	last_at = tick
	next_at = tick + cast.skill.hit_interval_ticks if fired < cast.skill.hit_count else -1
	return kills


func _land(
	enemies: Array[PBEnemy],
	front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog
) -> int:
	var rolled := PBCritRules.hit(caster, cast.skill.damage, cast.skill.kind, tick, rng)
	return PBSkillRules.land(
		cast,
		enemies,
		front,
		cfg,
		tick,
		caster,
		float(rolled[PBCritRules.DAMAGE]),
		book,
		bool(rolled[PBCritRules.CRIT])
	)


func _apply_start_area(enemies: Array[PBEnemy], front: int, cfg: PBSimConfig, tick: int) -> void:
	if cast.skill.on_start_area.is_empty():
		return
	for i: int in range(front, enemies.size()):
		var enemy: PBEnemy = enemies[i]
		if not enemy.has_spawned(tick):
			break
		var radius := (
			cast.skill.control_radius if cast.skill.control_radius > 0 else cast.skill.radius
		)
		if enemy.is_hostile(tick) and enemy.pos().distance_to(center) <= radius:
			PBSkillRules.apply_all_enemy(
				enemy, cast.skill.on_start_area, cast.caster_level, cfg, tick
			)


static func validate(skill: PBSkill) -> String:
	var timing_error := _validate_scatter(skill)
	if timing_error == "":
		timing_error = _validate_timing(skill)
	if timing_error != "":
		return timing_error
	if skill.hit_count < 1 or skill.hit_interval_ticks < 0:
		return "连击段数必须为正，间隔不能为负"
	if (
		not is_finite(skill.hit_radius)
		or skill.hit_radius < 0.0
		or not is_finite(skill.hit_step)
		or skill.hit_step < 0.0
		or not is_finite(skill.radius_growth)
		or skill.radius_growth < 0.0
	):
		return "每段半径与蔓延距离必须有限且非负"
	if skill.hit_count == 1:
		return (
			"单段技能不能配置连击间隔或分散半径"
			if (
				skill.hit_interval_ticks != 0
				or skill.hit_radius != 0.0
				or skill.hit_step != 0.0
				or skill.radius_growth != 0.0
			)
			else ""
		)
	if skill.hit_interval_ticks < 1:
		return "多段技能必须配置至少一个 tick 的间隔"
	if (
		skill.target not in [PBSkill.Target.GROUND, PBSkill.Target.NONE]
		or skill.affects != PBSkill.Party.ENEMIES
		or (
			skill.target == PBSkill.Target.NONE
			and skill.hit_radius > 0.0
			and skill.scatter_steps == 0
		)
		or (skill.hit_step > 0.0 and skill.target != PBSkill.Target.NONE)
	):
		return "连击只支持地面或自身周围敌方技能，自身周围不能分散落点"
	if (
		not is_finite(skill.radius)
		or skill.radius < 0.0
		or (skill.hit_radius > 0.0 and skill.radius == 0.0)
	):
		return "连击范围必须有限且非负，分散落点必须有正范围"
	return ""


static func _validate_timing(skill: PBSkill) -> String:
	var last := -1
	for at: int in skill.area_refresh_ticks:
		if (
			at <= last
			or at > skill.pulse_delay_ticks + (skill.hit_count - 1) * skill.hit_interval_ticks
		):
			return "范围控制时刻须非负递增且不晚于末段"
		last = at
	if not skill.area_refresh_ticks.is_empty() and skill.on_start_area.is_empty():
		return "范围控制时刻必须配置起手范围效果"
	if skill.pulse_delay_ticks < 0:
		return "首段等待不能为负数"
	for count: int in skill.hit_count_levels:
		if count < 2:
			return "分级连击次数必须至少两段"
	if not skill.hit_count_levels.is_empty() and skill.hit_count_levels[0] != skill.hit_count:
		return "分级连击首项必须等于基础段数"
	if skill.pulse_delay_ticks > 0 or not skill.on_start_area.is_empty():
		if skill.target != PBSkill.Target.GROUND or skill.hit_radius > 0.0:
			return "首段等待与起手范围控制只支持固定地面多段技能"
	for buff: PBBuff in skill.on_start_area:
		if buff == null or buff.kind != PBBuff.Kind.DURATION or buff.mods.has(PBBuffRules.HARM):
			return "起手范围效果只允许无伤害的持续控制"
	return ""


static func _validate_scatter(skill: PBSkill) -> String:
	if skill.scatter_steps < 0 or skill.volley_size < 1:
		return "随机半径档数不能为负，同轮段数必须为正"
	if skill.scatter_steps == 0:
		return "非随机连击不支持同轮多段" if skill.volley_size != 1 else ""
	if (
		skill.target != PBSkill.Target.NONE
		or skill.hit_count < 2
		or skill.hit_count % skill.volley_size != 0
		or skill.hit_radius <= 0.0
		or skill.hit_step != 0.0
		or skill.radius_growth != 0.0
		or skill.pulse_radius_step != 0.0
		or skill.travel_step != 0.0
		or skill.pulse_delay_ticks != 0
		or not skill.on_start_area.is_empty()
	):
		return "跟随随机连击要求无目标、正落点半径、整轮段数，不能混用其他连击模式"
	return ""
