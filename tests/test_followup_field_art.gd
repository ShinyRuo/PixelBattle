extends GutTest

const ART_PATH := "res://data/field_art/areas/serpent_array.tres"

var _cfg: PBSimConfig
var _unit: PBAttacker
var _sim: PBBattleSim
var _skin: PBFieldSkin


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_cfg.spawn_window = 0
	_cfg.unit_min_gap = 0
	var cards: Array[PBUnit] = [
		PBUnit.new(_cfg.characters.by_id(&"orochimaru")),
		PBUnit.new(_cfg.characters.by_id(&"kabuto"))
	]
	var patches := PBBondRules.active_skill_patches(cards, cards, _cfg.bonds)
	_unit = (
		PBCombatRules
		. build_attackers(
			cards,
			PBElement.Type.PHYSICAL,
			1,
			PackedFloat64Array(),
			_cfg,
			null,
			1,
			0,
			{},
			{},
			patches
		)[0]
	)
	_unit.attack = 0
	_unit.dps = 0
	_unit.move_speed = 0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000
	_sim = PBBattleSim.new(wave, 0, 0, _cfg, [_unit])
	var enemy := _sim.enemies()[0]
	enemy.distance = 0.6
	enemy.lane = 0.3
	enemy.speed = 0
	enemy.damage_per_shot = 0
	_skin = PBFieldSkin.new()
	_skin.placeholder = true
	PBFieldArt._cache[ART_PATH] = _skin


func after_each() -> void:
	PBFieldArt._cache.erase(ART_PATH)


func _until(tick: int) -> void:
	while _sim.current_tick() < tick:
		_sim.step()


func _cast() -> PBSkillBarrage:
	assert_true(_sim.cast_skill(_unit, Vector2(0.6, 0.3), 1))
	_until(6)
	return _sim.barrages()[0]


func test_real_followup_starts_at_release_switches_at_damage_and_survives_source_death() -> void:
	var barrage := _cast()
	assert_false(PBPersistentFieldArt.startup_live(barrage, 5))
	assert_true(PBPersistentFieldArt.startup_live(barrage, 6))
	_unit.alive = false
	_until(65)
	assert_true(PBPersistentFieldArt.startup_live(barrage, 65))
	var view := PBFieldEffects.new()
	add_child_autofree(view)
	view.sync_effects([], [], 65, 20, Vector2.ONE, _sim.barrages())
	assert_true(view._impacts.is_empty())
	var hp := _sim.enemies()[0].hp
	_until(66)
	assert_false(PBPersistentFieldArt.startup_live(barrage, 66))
	assert_lt(_sim.enemies()[0].hp, hp)
	view.sync_effects([], [], 66, 20, Vector2.ONE, _sim.barrages())
	assert_eq(view._impacts.size(), 1)
	var entry: Dictionary = view._impacts.values()[0]
	assert_eq(entry.spot, Vector2(0.6, 0.3))
	assert_eq(entry.radius, 0.2025)
	var after := _sim.enemies()[0].hp
	view.sync_effects([], [], 77, 20, Vector2.ONE, _sim.barrages())
	assert_eq(view._impacts.size(), 1, "六帧动画最后一帧仍可见")
	view.sync_effects([], [], 78, 20, Vector2.ONE, _sim.barrages())
	assert_true(view._impacts.is_empty(), "六帧10fps在0.6秒后清理，不重播")
	assert_eq(_sim.enemies()[0].hp, after, "美术读点不制造额外伤害")


func test_visual_snapshot_survives_pool_reuse_and_clear_discards_it() -> void:
	var barrage := _cast()
	_until(66)
	var view := PBFieldEffects.new()
	add_child_autofree(view)
	view.sync_effects([], [], 66, 20, Vector2.ONE, [barrage])
	var old_cast := barrage.cast
	var next := PBSkillCast.new(_cfg.skills.by_id(&"serpent_array").clone())
	next.spot = Vector2(0.2, 0.4)
	barrage.begin(_unit, next, 67)
	view.sync_effects([], [], 67, 20, Vector2.ONE, [barrage])
	assert_true(view._impacts.has(old_cast))
	assert_eq(view._impacts[old_cast].spot, Vector2(0.6, 0.3))
	assert_true(PBPersistentFieldArt.startup_live(barrage, 67))
	view.sync_effects([], [], 0, 20, Vector2.ONE, [])
	assert_true(view._impacts.is_empty(), "回到新波不能带入旧动画")
	view.clear()
	assert_true(view._barrages.is_empty())


func test_editor_lists_supported_followup_phases_and_excludes_moving_expanding_shapes() -> void:
	var entries: Dictionary = {}
	for row: Dictionary in PBFieldArtBindings.new().choices():
		var key: String = row.kind + "/" + row.id
		assert_false(entries.has(key), "每个入口只出现一次")
		entries[key] = row.name
	assert_true(entries.has("startups/serpent_array"))
	assert_true(entries.has("areas/serpent_array"))
	assert_true(entries["areas/serpent_array"].contains("追加"))
	assert_true(entries.has("startups/true_hands"))
	assert_true(entries.has("pulses/true_hands"))
	assert_true(entries.has("areas/deity_gates"))
	assert_false(entries.has("startups/water_surge"))
	assert_false(entries.has("pulses/serpent_array"))


func test_whole_sheet_cut_and_bind_keeps_startup_impact_and_parent_independent() -> void:
	var source := Image.create_empty(96, 16, false, Image.FORMAT_RGBA8)
	for i: int in 6:
		source.fill_rect(Rect2i(i * 16 + 4, 4, 8, 8), Color(float(i) / 6, 1, 0, 1))
	var path := "user://followup_field_sheet.png"
	assert_eq(source.save_png(path), OK)
	var page := PBFieldArtPage.new()
	add_child_autofree(page)
	page._bindings.output_dir = "user://followup_field_bindings"
	for i: int in page._rows.size():
		if page._rows[i].kind == "startups" and page._rows[i].id == "serpent_array":
			page._choices.select(i)
			page._select()
	page._sheet.use_sheet(path)
	page._sheet._columns.value = 6
	page._sheet._rows.value = 1
	page._sheet._count.value = 6
	page._cut()
	assert_eq(page._cut_images.size(), 6)
	assert_true(page._range.text.contains("405码"))
	assert_true(page._range.text.contains("400码"))
	assert_true(page._range.text.contains("3.00秒"))
	assert_eq(page._bindings.save("startups", "serpent_array", page._skin), "")
	var impact := page._skin.duplicate() as PBFieldSkin
	impact.fps = 20
	assert_eq(page._bindings.save("areas", "serpent_array", impact), "")
	assert_eq(page._bindings.read("startups", "serpent_array").fps, 10.0)
	assert_eq(page._bindings.read("areas", "serpent_array").fps, 20.0)
	assert_eq(page._bindings.read("areas", "great_breakthrough").frames.size(), 0)
	assert_eq(page._bindings.read("startups", "serpent_array").frames.size(), 6)
	for kind: String in ["startups", "areas"]:
		var dir := page._bindings.output_dir + "/" + kind
		DirAccess.remove_absolute(dir + "/serpent_array.tres")
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(page._bindings.output_dir)
	DirAccess.remove_absolute(path)


func test_preview_placement_changes_art_only_and_overlapping_impacts_keep_own_clocks() -> void:
	var first := _cast()
	_until(66)
	var second := PBSkillBarrage.new()
	var cast := PBSkillCast.new(first.cast.skill.clone())
	cast.spot = Vector2(0.2, 0.4)
	second.begin(_unit, cast, 8)
	second.advance([], 0, _cfg, 68, null, null)
	var view := PBFieldEffects.new()
	add_child_autofree(view)
	view.sync_effects([], [], 68, 20, Vector2.ONE, [first, second])
	assert_eq(view._impacts.size(), 2)
	view.sync_effects([], [], 78, 20, Vector2.ONE, [first, second])
	assert_eq(view._impacts.size(), 1)
	assert_eq(view._impacts.values()[0].tick, 68)
	var preview := PBFieldArtPreview.new()
	add_child_autofree(preview)
	preview.skill = first.cast.skill
	preview.skin = _skin
	_skin.area_scale = 2
	_skin.area_offset = Vector2.ONE
	assert_eq(preview.radius_units(), 0.2025)
	assert_eq(preview.control_radius_units(), 0.2)
