class_name PBEnemyHitContext
extends RefCounted
## 敌人一次命中的附带信息：受击光环 / 召唤使用当前队伍，播报使用出手时确定的暴击标记。
## 伤害、属性仍显式传给 hurt_ally；将可选信息放在一起，避免每补一种效果就增加漏斗参数。

var team: Array[PBAttacker] = []
var crit: bool = false
var kind: PBDamageKind.Type = PBDamageKind.Type.TAIJUTSU
var armor_pen: float = 0.0
var ninjutsu_pen: float = 0.0


func _init(
	members: Array[PBAttacker] = [],
	was_crit: bool = false,
	of_kind: PBDamageKind.Type = PBDamageKind.Type.TAIJUTSU,
	physical_pen: float = 0.0,
	spell_pen: float = 0.0
) -> void:
	team = members
	crit = was_crit
	kind = of_kind
	armor_pen = physical_pen
	ninjutsu_pen = spell_pen
