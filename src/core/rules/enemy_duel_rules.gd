class_name PBEnemyDuelRules
extends RefCounted
## 临时转化后的敌方实体仍留在原对象池；只改变敌我筛选，不伪造一张忍者卡。
## 普攻保留原有起手、冷却、弹道、暴击、七属性和体术 / 忍术减伤。


static func attack(
	source: PBEnemy,
	enemies: Array[PBEnemy],
	team: Array[PBAttacker],
	shots: Array[PBProjectile],
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> bool:
	var friendly: bool = source.controlled(tick)
	var target: PBEnemy = _nearest(source, enemies, tick, source.reach)
	if target == null:
		return friendly
	if not friendly:
		var defender := PBTargetRules.nearest_defender(team, source)
		if (
			defender != null
			and source.pos().distance_to(defender.pos) <= source.pos().distance_to(target.pos())
		):
			return false
	source.engaged = true
	if source.damage_per_shot <= 0.0 or not source.ready_to_fire(tick):
		return true
	if source.begin_swing(tick):
		return true
	source.on_fired(tick)
	if PBBuffRules.misses(source, tick, rng):
		return true
	var rolled := PBCritRules.enemy_strike(source, tick, rng)
	var context := PBHarmContext.new()
	context.kind = rolled[PBCritRules.KIND]
	context.element = source.element
	context.has_element = true
	context.armor_pen = source.armor_pen
	context.ninjutsu_pen = source.ninjutsu_pen
	var damage: float = rolled[PBCritRules.DAMAGE]
	if source.shot_speed > 0.0:
		var shot := PBShotRules.free_shot(shots)
		if shot != null:
			shot.launch(
				source.pos(),
				target.slot,
				damage,
				source.shot_speed,
				false,
				source.element,
				source.slot,
				null,
				1,
				rolled[PBCritRules.CRIT]
			)
			shot.enemy_duel = true
			shot.duel_source_friendly = friendly
			shot.duel_context = context
	else:
		_hit(target, damage, context, cfg, tick, rng, book, out, rolled[PBCritRules.CRIT])
	return true


static func advance_shot(
	shot: PBProjectile,
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	if shot.target < 0 or shot.target >= enemies.size():
		shot.retire()
		return
	var target := enemies[shot.target]
	if not target.is_active(tick) or target.controlled(tick) == shot.duel_source_friendly:
		shot.retire()
		return
	if not shot.fly(target.pos()):
		return
	_hit(target, shot.damage, shot.duel_context, cfg, tick, rng, book, out, shot.crit)
	shot.retire()


static func move(
	source: PBEnemy, enemies: Array[PBEnemy], team: Array[PBAttacker], scale: float, tick: int
) -> bool:
	var friendly: bool = source.controlled(tick)
	var target: PBEnemy = _nearest(source, enemies, tick)
	if target == null:
		return friendly
	if not friendly:
		var defender := PBTargetRules.nearest_ally(team, source)
		if (
			defender != null
			and source.pos().distance_to(defender.pos) <= source.pos().distance_to(target.pos())
		):
			return false
	var gap: Vector2 = source.pos() - target.pos()
	var keep: float = source.reach * PBAttacker.STOP_RING
	if gap.length() > keep:
		source.march_to(target.pos() + gap.normalized() * keep, scale, tick)
	return true


static func _nearest(
	source: PBEnemy, enemies: Array[PBEnemy], tick: int, reach: float = -1.0
) -> PBEnemy:
	var friendly: bool = source.controlled(tick)
	var best: PBEnemy = null
	var nearest: float = INF
	for other: PBEnemy in enemies:
		if other == source or not other.is_active(tick) or other.controlled(tick) == friendly:
			continue
		var gap: float = source.pos().distance_to(other.pos())
		if reach >= 0.0 and gap > reach:
			continue
		if gap < nearest:
			best = other
			nearest = gap
	return best


static func _hit(
	enemy: PBEnemy,
	raw: float,
	context: PBHarmContext,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome,
	crit: bool
) -> void:
	var damage: float = PBHarmContext.damage(raw, context, enemy, cfg, tick)
	if enemy.take_damage(damage, tick, rng, true):
		out.kills += 1
	if book != null:
		book.hit(tick, -1, enemy.slot, damage, false, crit)
