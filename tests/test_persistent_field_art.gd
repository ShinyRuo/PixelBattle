extends GutTest

var _cfg: PBSimConfig
var _caster: PBAttacker


func before_each() -> void:
	_cfg = PBGameData.config()
	_caster = PBAttacker.new()
	_caster.slot = 0
	_caster.max_hp = 10000
	_caster.revive()
	_caster.prime(_cfg.tick_rate, _cfg)


func _zone(id: StringName, tick: int = 0) -> PBHazardZone:
	var skill := _cfg.skills.by_id(id).clone()
	var cast := PBSkillCast.new(skill)
	cast.spot = Vector2(0.6, 0.2)
	var zone := PBHazardZone.new()
	zone.begin(_caster, cast, tick)
	return zone


func test_shark_first_hit_and_last_tick_use_real_schedule() -> void:
	var zone := _zone(&"infinite_sharks", 10)
	assert_true(PBPersistentFieldArt.aura_live(zone, 10))
	assert_false(PBPersistentFieldArt.damage_live(zone, 10))
	var first := zone.next_at
	zone.advance([], 0, _cfg, first, null, null)
	assert_eq(zone.fired, 1)
	assert_true(PBPersistentFieldArt.damage_live(zone, first))
	assert_true(PBPersistentFieldArt.damage_live(zone, first + 1))
	while zone.next_at >= 0:
		zone.advance([], 0, _cfg, zone.next_at, null, null)
	assert_eq(zone.fired, 10)
	assert_true(PBPersistentFieldArt.damage_live(zone, zone.last_at))
	assert_false(PBPersistentFieldArt.damage_live(zone, zone.last_at + 1))
	assert_false(PBPersistentFieldArt.aura_live(zone, zone.last_at))


func test_acid_aura_ends_before_damage_and_keeps_own_multi_circle_geometry() -> void:
	for id: StringName in [&"boil_acid", &"boil_acid_kage"]:
		var zone := _zone(id)
		var skill := zone.cast.skill
		assert_eq(zone.points.size(), 1 + skill.zone_ring_count + skill.zone_outer_count)
		assert_ne(skill.radius, skill.zone_radius)
		var end := zone.aura_until
		assert_true(PBPersistentFieldArt.aura_live(zone, end - 1))
		zone.advance([], 0, _cfg, end, null, null)
		assert_false(PBPersistentFieldArt.aura_live(zone, end))
		assert_true(PBPersistentFieldArt.damage_live(zone, end))
		assert_gt(zone.next_at, end)


func test_ground_regions_survive_source_death_and_reuse_resets_old_phase() -> void:
	var zone := _zone(&"sand_waterfall")
	zone.advance([], 0, _cfg, zone.next_at, null, null)
	_caster.alive = false
	assert_true(PBPersistentFieldArt.damage_live(zone, zone.last_at))
	assert_true(PBPersistentFieldArt.aura_live(zone, zone.last_at))
	var original := PBSkillCast.new(_cfg.skills.by_id(&"infinite_sharks").clone())
	original.spot = Vector2(0.1, 0.4)
	zone.begin(_caster, original, 100)
	assert_eq(zone.points[0], original.spot)
	assert_eq(zone.last_at, -1)
	assert_false(PBPersistentFieldArt.damage_live(zone, 100))
	assert_true(PBPersistentFieldArt.aura_live(zone, 100))


func test_overlapping_casts_keep_independent_timing_and_clear() -> void:
	var first := _zone(&"infinite_sharks", 0)
	var second := _zone(&"infinite_sharks", 100)
	assert_false(PBPersistentFieldArt.aura_live(first, 100))
	assert_true(PBPersistentFieldArt.aura_live(second, 100))
	var view := PBFieldEffects.new()
	add_child_autofree(view)
	view.sync_effects([], [], 100, 20, Vector2.ONE, [first, second])
	assert_eq(view._barrages.size(), 2)
	view.clear()
	assert_true(view._barrages.is_empty())


func test_authoring_exposes_variants_and_rejects_moving_or_expanding_shapes() -> void:
	var entries: Dictionary = {}
	var bindings := PBFieldArtBindings.new()
	for row: Dictionary in bindings.choices():
		entries[row.kind + "/" + row.id] = true
	for id: String in ["infinite_sharks", "boil_acid_kage", "sand_waterfall"]:
		assert_true(entries.has("pulses/" + id))
		assert_true(entries.has("zones/" + id))
	assert_true(entries.has("pulses/sand_burial"))
	assert_false(entries.has("zones/sand_burial"))
	var skill := _cfg.skills.by_id(&"infinite_sharks").clone()
	skill.hit_radius = 0.01
	assert_false(PBFieldArt.supports_persistent(skill))
	skill.hit_radius = 0
	skill.travel_step = 0.01
	assert_false(PBFieldArt.supports_persistent(skill))


func test_save_reload_keeps_damage_and_aura_art_independent() -> void:
	var bindings := PBFieldArtBindings.new()
	bindings.output_dir = "user://persistent_art_test"
	var skin := PBFieldSkin.new()
	skin.fps = 7
	assert_eq(bindings.save("pulses", "infinite_sharks", skin), "")
	skin.fps = 12
	assert_eq(bindings.save("zones", "infinite_sharks", skin), "")
	assert_eq(bindings.read("pulses", "infinite_sharks").fps, 7.0)
	assert_eq(bindings.read("zones", "infinite_sharks").fps, 12.0)
	for kind: String in ["pulses", "zones"]:
		DirAccess.remove_absolute("user://persistent_art_test/%s/infinite_sharks.tres" % kind)
		DirAccess.remove_absolute("user://persistent_art_test/%s" % kind)
	DirAccess.remove_absolute("user://persistent_art_test")
