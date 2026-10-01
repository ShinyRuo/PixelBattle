class_name PBBondBuffRules
extends RefCounted
## 羁绊开场状态与准备预览共用来源收集。战斗只挂 BUFF，不另写永久加成。


static func collect(
	bonded: Array[PBUnit], deployed: Array[PBUnit], table: PBBondTable
) -> Dictionary:
	var out: Dictionary = {}
	if table == null:
		return out
	for bond: PBBond in table.all():
		if PBBondRules.active_count(bond, bonded) < bond.full_tier_count():
			continue
		for unit: PBUnit in deployed:
			var id := unit.character.id
			var mine: Dictionary = out.get(id, {})
			for buff: PBBuff in bond.member_buffs.get(id, []):
				mine[buff.id] = buff
			if not mine.is_empty():
				out[id] = mine
	return out


static func preview(passives: Dictionary, effects: Dictionary) -> void:
	for id: StringName in effects:
		var mine: Dictionary = passives.get(id, {})
		for buff: PBBuff in effects[id].values():
			for key: StringName in buff.mods:
				mine[key] = float(mine.get(key, 0.0)) + float(buff.mods[key])
		passives[id] = mine


static func install(
	attackers: Array[PBAttacker], deployed: Array[PBUnit], effects: Dictionary
) -> void:
	for attacker: PBAttacker in attackers:
		if attacker.slot < 0 or attacker.slot >= deployed.size() or attacker.summoned:
			continue
		var id := deployed[attacker.slot].character.id
		attacker.opening_buffs.clear()
		for buff: PBBuff in (effects.get(id, {}) as Dictionary).values():
			attacker.opening_buffs.append(buff)


static func validate(bond: PBBond) -> String:
	for id: StringName in bond.member_buffs:
		if not bond.member_ids.has(id) or not bond.member_buffs[id] is Array:
			return "开场 BUFF 必须属于本组成员，且以数组配置"
		for buff: PBBuff in bond.member_buffs[id]:
			if buff == null or not buff.until_wave_end or buff.per_source:
				return "羁绊开场 BUFF 需要非按来源叠加的整波持续效果"
			if PBBuffRules.validate(buff) != "":
				return "羁绊开场 BUFF 数据不合法"
			if not buff.mods_growth.is_empty() or not buff.mods_levels.is_empty():
				return "开场 BUFF 暂只支持固定护甲，不能配置等级成长"
			for key: StringName in buff.mods:
				if key != PBBuffRules.DEFENCE:
					return "开场 BUFF 当前只接通固定护甲"
	return ""
