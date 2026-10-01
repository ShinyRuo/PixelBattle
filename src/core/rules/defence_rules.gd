class_name PBDefenceRules
extends RefCounted
## 敌我共用的分型减伤。七种攻防属性的克制先在伤害事件上计算，本类不读取属性。


static func mitigated(
	raw: float,
	kind: PBDamageKind.Type,
	armor: float,
	resist: float,
	armor_pen: float,
	ninjutsu_pen: float,
	cfg: PBSimConfig
) -> float:
	if kind == PBDamageKind.Type.NINJUTSU:
		var effective: float = resist * (1.0 - clampf(ninjutsu_pen, 0.0, 1.0))
		return raw * (1.0 - clampf(effective, 0.0, 1.0))
	var effective: float = armor * (1.0 - clampf(armor_pen, 0.0, 1.0))
	return raw * (1.0 - PBStatRules.damage_reduction(effective, cfg))
