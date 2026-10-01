class_name PBAttributeProfile
extends RefCounted
## 战斗内属性增量的基线。角色定义共享只读，词条和赠送值由每个战斗单位独占。
## 重算仍走 PBStatRules.of，不能另抄一套力量 / 敏捷 / 智力派生公式。

var character: PBCharacter
var level: int = 1
var star: int = 1
var mods: Dictionary = {}
var received: Dictionary = {}
var temporary: Dictionary = {}
var current: PBStats
var wave_element: PBElement.Type = PBElement.Type.PHYSICAL
var team_mult: float = 1.0


static func make(
	unit: PBUnit, values: Dictionary, stats: PBStats, element: PBElement.Type, mult: float
) -> PBAttributeProfile:
	var out := PBAttributeProfile.new()
	out.character = unit.character
	out.level = unit.level
	out.star = unit.star()
	out.mods = values.duplicate()
	out.current = stats
	out.wave_element = element
	out.team_mult = mult
	return out


func stats(cfg: PBSimConfig) -> PBStats:
	var additions: Dictionary = received.duplicate()
	for key: StringName in temporary:
		additions[key] = float(additions.get(key, 0.0)) + float(temporary[key])
	return PBStatRules.of(character, level, star, cfg, mods, additions)


func clone() -> PBAttributeProfile:
	var out := PBAttributeProfile.new()
	out.character = character
	out.level = level
	out.star = star
	out.mods = mods.duplicate()
	out.received = received.duplicate()
	out.temporary = temporary.duplicate()
	out.current = current
	out.wave_element = wave_element
	out.team_mult = team_mult
	return out
