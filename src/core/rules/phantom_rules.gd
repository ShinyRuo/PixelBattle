class_name PBPhantomRules
extends RefCounted
## 远程命中生成的无敌幻影：复用召唤位，不继承本体技能 / 被动链。
## 只继承出手时总攻击及生成时体术暴击；攻击间隔、近战距离取幻影物编。

const ATTACK_SECONDS: float = 1.5
const SPEED_PER_LEVEL: float = 0.15
const RANGE_UNITS: float = 120.0
const OFFSET_UNITS: float = 80.0
const MOVE_UNITS: float = 480.0
const ACQUIRE_UNITS: float = 1500.0
const WINDUP_SECONDS: float = 0.2


static func raise_at(
	sequence: PBExpandingStrike, enemy: PBEnemy, cfg: PBSimConfig, tick: int
) -> int:
	var skill := sequence.cast.skill
	if skill.phantom_count <= 0 or enemy.shot_speed <= 0.0:
		return 0
	var made: int = 0
	for one: PBAttacker in sequence.team:
		if made >= skill.phantom_count:
			break
		if not one.summoned or one.expires_at != PBSummonRules.GONE:
			continue
		_stand(one, sequence, enemy, cfg, tick, made)
		made += 1
	return made


static func _stand(
	one: PBAttacker,
	sequence: PBExpandingStrike,
	enemy: PBEnemy,
	cfg: PBSimConfig,
	tick: int,
	ordinal: int
) -> void:
	var caster := sequence.caster
	var skill := sequence.cast.skill
	var level: int = sequence.cast.caster_level
	one.buffs.clear()
	one.summon_skill_id = skill.id
	one.summon_serial += 1
	one.phantom = true
	one.appearance_slot = caster.slot
	one.attribute_profile = null
	one.max_hp = 5.0
	one.hp = one.max_hp
	one.max_mp = 0.0
	one.mp = 0.0
	one.attack_element = skill.phantom_element
	one.attack_ninjutsu = 0.0
	one.base_attack = sequence.inherited_attack * skill.summon_power
	one.attack = (
		one.base_attack
		* cfg.damage_multiplier(PBElement.relation(one.attack_element, enemy.element))
	)
	one.damage_attributes = {&"attack": one.base_attack}
	one.attack_speed = (1.0 + SPEED_PER_LEVEL * level) / ATTACK_SECONDS
	one.dps = one.attack * one.attack_speed
	one.crit_chance = PBCritRules.chance_of(caster, tick)
	one.crit_bonus = caster.crit_bonus
	one.reach = cfg.units_to_field(RANGE_UNITS)
	one.ranged_attack = false
	one.shot_speed = 0.0
	one.move_speed = cfg.units_to_field(MOVE_UNITS) / cfg.tick_rate
	one.leash = cfg.units_to_field(ACQUIRE_UNITS)
	one.lifesteal = 0.0
	one.shape = PBAttacker.Shape.SINGLE
	one.pos = (
		enemy.pos()
		+ Vector2(cfg.units_to_field(OFFSET_UNITS) * (1 if ordinal % 2 == 0 else -1), 0.0)
	)
	one.pos.x = maxf(one.pos.x, 0.0)
	one.home = one.pos
	one.forced_target = enemy.slot
	one.focus_named_target = true
	one.aim_at = enemy.slot
	one.swinging = false
	one.expires_at = tick + maxi(roundi(skill.summon_seconds * cfg.tick_rate), 1)
	one.prime(cfg.tick_rate, cfg)
	one.windup_ticks = maxi(roundi(WINDUP_SECONDS * cfg.tick_rate), 1)
	one.next_shot_at = tick
	one.alive = true


static func finish(sequence: PBExpandingStrike, enemies: Array[PBEnemy], cfg: PBSimConfig) -> void:
	if sequence.cast.skill.phantom_count <= 0 or not sequence.caster.alive:
		return
	for enemy: PBEnemy in enemies:
		if enemy.slot != sequence.last_target or enemy.shot_speed <= 0.0:
			continue
		sequence.caster.pos = enemy.pos() + Vector2(cfg.units_to_field(OFFSET_UNITS), 0.0)
		sequence.caster.forced_target = enemy.slot
		return


static func validate(skill: PBSkill) -> String:
	if skill.phantom_count < 0 or skill.phantom_element not in PBElement.Type.values():
		return "幻影数量不能为负，攻击属性必须合法"
	if skill.phantom_count == 0:
		return ""
	if skill.pulse_radius_step <= 0.0 or skill.summon_count != 0:
		return "远程命中幻影需要逐段扩圈，不能同时配置普通召唤"
	for value: float in [skill.summon_power, skill.summon_seconds]:
		if not is_finite(value) or value <= 0.0:
			return "幻影继承比例与时长必须为有限正数"
	return ""
