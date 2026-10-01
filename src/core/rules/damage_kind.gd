class_name PBDamageKind
extends RefCounted
## 一次伤害是**体术**还是**忍术**；物理只表示七种属性中的一种。和属性（[PBElement]）一样挂在伤害事件上，不挂在单位上。
##
## 伤害类型管护甲 / 忍术抗性、暴击与增伤；七种攻防属性独立计算克制。
## 普攻默认体术，被动可以转换成忍术。技能按施法者攻击属性分型，
## 不按技能自身的属性分型；技能自身的属性仍用于克制。

enum Type {
	TAIJUTSU,
	NINJUTSU,
}


static func skill_kind(attack_element: PBElement.Type) -> Type:
	return Type.TAIJUTSU if attack_element == PBElement.Type.PHYSICAL else Type.NINJUTSU
