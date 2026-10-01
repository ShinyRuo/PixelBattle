class_name PBEnemyAbilityRules
extends RefCounted
## 主动施法独立于普攻冷却；沉默不限制体术或忍术普攻。


static func advance(
	enemy: PBEnemy,
	team: Array[PBAttacker],
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	if not enemy.is_hostile(tick) or enemy.abilities.is_empty():
		return
	if (
		enemy.buffs.amount(PBBuffRules.SILENCE, tick) > 0.0
		or enemy.buffs.amount(PBBuffRules.STUN, tick) > 0.0
	):
		return
	var target := PBTargetRules.nearest_ally(team, enemy)
	if target == null:
		return
	for index: int in enemy.abilities.size():
		var ability := enemy.abilities[index]
		if (
			tick < enemy.ability_ready_at[index]
			or enemy.pos().distance_to(target.pos) > ability.reach
		):
			continue
		enemy.ability_ready_at[index] = tick + ability.cooldown_ticks
		var raw: float = ability.damage_base + enemy.atk * ability.attack_scale
		raw += enemy.intellect * ability.intellect_scale
		var hit := PBCritRules.enemy_hit(enemy, raw, ability.kind, tick, rng)
		PBStrikeRules.hurt_ally(
			target,
			enemy,
			hit[PBCritRules.DAMAGE],
			ability.element,
			cfg,
			tick,
			rng,
			book,
			out,
			PBEnemyHitContext.new(
				team, hit[PBCritRules.CRIT], ability.kind, enemy.armor_pen, enemy.ninjutsu_pen
			)
		)
		break
