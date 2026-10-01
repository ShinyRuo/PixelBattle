class_name PBBondAuraArt
extends RefCounted
## 只给真实激活羁绊的在场成员配可选光环；没有美术资源的羁绊不生成空状态。


static func active_member_auras(
	bonded: Array[PBUnit], deployed: Array[PBUnit], table: PBBondTable
) -> Dictionary:
	var out: Dictionary = {}
	if table == null:
		return out
	for bond: PBBond in table.all():
		if bond.tier_at(PBBondRules.active_count(bond, bonded)) <= 0:
			continue
		var art_id := StringName("bond_%s_aura" % bond.id)
		if PBBuffGlow.skin_for(art_id) == null:
			continue
		for unit: PBUnit in deployed:
			if not bond.counts(unit):
				continue
			var member_id: StringName = unit.character.id
			if not out.has(member_id):
				out[member_id] = [] as Array[StringName]
			var ids: Array = out[member_id]
			if not ids.has(art_id):
				ids.append(art_id)
	return out
