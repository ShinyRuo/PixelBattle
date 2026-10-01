class_name PBPersistentFieldArt
extends RefCounted
## 伤害与光环各取自己的范围和时限。没有独立倒计时，复用状态不会留下旧图。


static func damage_live(barrage: PBSkillBarrage, tick: int) -> bool:
	return (
		barrage.cast != null
		and PBFieldArt.supports_persistent(barrage.cast.skill)
		and barrage.last_at >= 0
		and tick >= barrage.last_at
		and (barrage.next_at >= 0 or tick == barrage.last_at)
	)


static func startup_live(barrage: PBSkillBarrage, tick: int) -> bool:
	return (
		barrage.cast != null
		and PBFieldArt.supports_startup(barrage.cast.skill)
		and barrage.active()
		and barrage.fired == 0
		and tick >= barrage._start_at
		and tick < barrage._start_at + barrage.cast.skill.pulse_delay_ticks
	)


static func aura_live(zone: PBHazardZone, tick: int) -> bool:
	return (
		zone.cast != null
		and PBFieldArt.supports_persistent(zone.cast.skill)
		and tick >= zone._start_at
		and tick < zone.aura_until
	)


static func draw(
	node: Node2D, barrage: PBSkillBarrage, tick: int, rate: int, field: Vector2
) -> void:
	if barrage.cast == null:
		return
	var skill := barrage.cast.skill
	var age := float(tick - barrage._start_at) / maxi(rate, 1)
	if startup_live(barrage, tick):
		var art := PBFieldArt.read("startups", art_key(skill))
		if art != null:
			PBFieldArt.draw_area(
				node,
				art,
				PBLayout.to_screen(barrage.center, field),
				skill.radius * PBLayout.px_per_unit(field),
				age,
				true
			)
	var zone := barrage as PBHazardZone
	if zone != null and aura_live(zone, tick):
		var art := PBFieldArt.read("zones", art_key(skill))
		if art != null:
			for point: Vector2 in zone.points:
				PBFieldArt.draw_area(
					node,
					art,
					PBLayout.to_screen(point, field),
					skill.zone_radius * PBLayout.px_per_unit(field),
					age,
					true
				)
	if damage_live(barrage, tick):
		var art := PBFieldArt.read("pulses", art_key(skill))
		if art != null:
			PBFieldArt.draw_area(
				node,
				art,
				PBLayout.to_screen(barrage.visual_spot(), field),
				barrage.visual_radius() * PBLayout.px_per_unit(field),
				age,
				true
			)


static func art_key(skill: PBSkill) -> StringName:
	return skill.variant_art_id if skill.variant_art_id != &"" else skill.id
