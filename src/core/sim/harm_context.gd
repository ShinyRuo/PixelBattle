class_name PBHarmContext
extends RefCounted
## 施加伤害效果时保存来源、类型、属性与增伤 / 穿透，不持有施法者引用。
## 持续伤害默认不暴击；施法者死亡或词条变化不改变已挂上的效果。

var kind: PBDamageKind.Type = PBDamageKind.Type.NINJUTSU
var element: PBElement.Type = PBElement.Type.PHYSICAL
var has_element: bool = false
var bonus: float = 1.0
var armor_pen: float = 0.0
var ninjutsu_pen: float = 0.0
var source_slot: int = -1
var attributes: Dictionary = {}
var stack_harm_scale: float = 1.0
var stack_defence: float = 0.0


static func from_caster(caster: PBAttacker, skill: PBSkill = null, tick: int = 0) -> PBHarmContext:
	var out := PBHarmContext.new()
	if skill != null:
		out.element = skill.element
		out.kind = skill.kind
		out.has_element = true
	if caster == null:
		return out
	if skill == null:
		out.element = caster.attack_element
		out.kind = PBDamageKind.skill_kind(caster.attack_element)
		out.has_element = true
	out.bonus = PBCritRules.bonus_scale(caster, out.kind)
	out.armor_pen = caster.armor_pen
	out.ninjutsu_pen = caster.ninjutsu_pen
	out.source_slot = caster.slot
	out.stack_harm_scale = maxf(1.0 + caster.stack_harm_bonus, 0.0)
	out.stack_defence = caster.stack_defence
	out.attributes = caster.damage_attributes.duplicate()
	out.attributes[&"attack"] = (
		float(out.attributes.get(&"attack", 0.0))
		+ caster.base_attack * PBAllyAuraRules.bonus_rate(caster, tick)
	)
	return out


static func damage(
	raw: float, source: PBHarmContext, enemy: PBEnemy, cfg: PBSimConfig, tick: int
) -> float:
	if source == null:
		return PBStrikeRules.mitigated(null, enemy, raw, PBDamageKind.Type.NINJUTSU, cfg, tick)
	var amount: float = raw * source.bonus
	if source.has_element:
		amount *= cfg.damage_multiplier(PBElement.relation(source.element, enemy.element))
	# 每份持续伤害先按自己的属性折算，再合并。调用方扣血时不再传属性，避免二次乘算。
	var element_scale: float = (
		enemy.element_hurt_scale(source.element, tick) if source.has_element else 1.0
	)
	return (
		PBStrikeRules.mitigated(null, enemy, amount, source.kind, cfg, tick, source) * element_scale
	)
