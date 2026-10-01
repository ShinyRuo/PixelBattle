extends GutTest


func test_real_ground_order_records_only_actual_landing_and_has_no_extra_damage() -> void:
	var cfg := PBGameData.config()
	cfg.spawn_window = 0
	var cards: Array[PBUnit] = [PBUnit.new(cfg.characters.by_id(&"asuma"))]
	var team := PBCombatRules.build_attackers(
		cards, PBElement.Type.FIRE, 1.0, PackedFloat64Array(), cfg
	)
	team[0].attack = 0
	team[0].dps = 0
	team[0].move_speed = 0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000
	var sim := PBBattleSim.new(wave, 0, 0, cfg, team)
	var enemy := sim.enemies()[0]
	enemy.speed = 0
	enemy.damage_per_shot = 0
	var cast := team[0].skills[0]
	assert_true(sim.cast_skill(team[0], enemy.pos(), 1))
	sim.step()
	var landing := cast.lands_at
	while sim.current_tick() < landing - 1:
		sim.step()
	assert_eq(cast.impact_tick, -1)
	sim.step()
	assert_eq(cast.impact_tick, landing)
	assert_eq(cast.impact_spot, enemy.pos())
	assert_gt(enemy.buffs.count(landing), 0)
	var hp := enemy.hp
	for i: int in 15:
		sim.step()
	assert_eq(enemy.hp, hp, "区域贴图不添加持续伤害")


func test_area_snapshot_survives_cooldown_and_resets_next_wave() -> void:
	var skill := PBGameData.config().skills.by_id(&"ash_burn").clone()
	var cast := PBSkillCast.new(skill)
	cast.cast(Vector2(0.5, 0.2), 0)
	assert_eq(cast.impact_tick, -1)
	cast.land(8)
	assert_eq(cast.impact_tick, 8)
	assert_eq(cast.impact_spot, Vector2(0.5, 0.2))
	assert_eq(cast.impact_skill, skill)
	assert_eq(cast.spot, PBSkillCast.NO_SPOT)
	cast.reset()
	assert_eq(cast.impact_tick, -1)
	assert_null(cast.impact_skill)


func test_self_centered_one_shot_area_records_its_real_cast_position() -> void:
	var skill := PBGameData.config().skills.by_id(&"kaiten").clone()
	assert_true(PBFieldArt.supports_self_area(skill))
	var cast := PBSkillCast.new(skill)
	cast.cast_now(0)
	cast.spot = Vector2(0.42, 0.53)
	cast.land(6)
	assert_eq(cast.impact_tick, 6)
	assert_eq(cast.impact_spot, Vector2(0.42, 0.53))
	assert_eq(cast.impact_skill, skill)
	cast.reset()
	assert_eq(cast.impact_tick, -1)


func test_friendly_self_area_records_the_caster_center() -> void:
	var skill := PBGameData.config().skills.by_id(&"palm_rotation").clone()
	assert_true(PBFieldArt.supports_self_area(skill))
	var cast := PBSkillCast.new(skill)
	cast.cast_now(0)
	var allies: Array[PBAttacker] = []
	PBSkillRules.land_around_allies(cast, Vector2(0.38, 0.61), allies, PBGameData.config(), 6)
	cast.land(6)
	assert_eq(cast.impact_tick, 6)
	assert_eq(cast.impact_spot, Vector2(0.38, 0.61))


func test_target_centered_one_shot_area_records_its_real_landing_position() -> void:
	var skill := PBGameData.config().skills.by_id(&"root_burial").clone()
	assert_true(PBFieldArt.supports_target_area(skill))
	var cast := PBSkillCast.new(skill)
	cast.cast_on(0, 0)
	assert_eq(cast.impact_tick, -1)
	cast.spot = Vector2(0.57, 0.5)
	cast.land(46)
	assert_eq(cast.impact_tick, 46)
	assert_eq(cast.impact_spot, Vector2(0.57, 0.5))
	assert_eq(cast.impact_skill, skill)


func test_forward_barrage_keeps_one_art_snapshot_per_real_pulse() -> void:
	var skill := PBGameData.config().skills.by_id(&"piston_fist").clone()
	skill.hit_count = 4
	skill.hit_step = 0.15
	assert_true(PBFieldArt.supports_forward_area(skill))
	var barrage := PBSkillBarrage.new()
	barrage.cast = PBSkillCast.new(skill)
	barrage.last_at = 6
	barrage.fired = 1
	barrage.cast.spot = Vector2(0.2, 0.5)
	var fx := PBFieldEffects.new()
	var team: Array[PBAttacker] = []
	var enemies: Array[PBEnemy] = []
	var barrages: Array[PBSkillBarrage] = [barrage]
	fx.sync_effects(team, enemies, 6, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 1)
	barrage.last_at = 11
	barrage.fired = 2
	barrage.cast.spot = Vector2(0.35, 0.5)
	fx.sync_effects(team, enemies, 11, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 2)
	fx.sync_effects(team, enemies, 50, 20, Vector2.ONE, barrages)
	assert_true(fx._impacts.is_empty())


func test_expanding_ground_area_uses_each_pulses_actual_radius() -> void:
	var skill := PBGameData.config().skills.by_id(&"deity_gates").clone()
	assert_true(PBFieldArt.supports_expanding_ground_area(skill))
	var barrage := PBSkillBarrage.new()
	barrage.cast = PBSkillCast.new(skill)
	barrage.cast.spot = Vector2(0.55, 0.5)
	barrage.last_at = 9
	barrage.fired = 1
	var fx := PBFieldEffects.new()
	var team: Array[PBAttacker] = []
	var enemies: Array[PBEnemy] = []
	var barrages: Array[PBSkillBarrage] = [barrage]
	fx.sync_effects(team, enemies, 9, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 1)
	var first: Dictionary = fx._impacts.values()[0]
	assert_almost_eq(first.radius, 0.1325, 0.00001)
	barrage.last_at = 14
	barrage.fired = 2
	barrage.cast.skill.radius = 0.195
	fx.sync_effects(team, enemies, 14, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 2)
	var radii: Array[float] = []
	for entry: Dictionary in fx._impacts.values():
		radii.append(entry.radius)
	radii.sort()
	assert_almost_eq(radii[0], 0.1325, 0.00001)
	assert_almost_eq(radii[1], 0.195, 0.00001)


func test_self_barrage_has_a_separate_snapshot_per_pulse() -> void:
	var skill := PBGameData.config().skills.by_id(&"leaf_whirl").clone()
	assert_true(PBFieldArt.supports_self_barrage_area(skill))
	var barrage := PBSkillBarrage.new()
	barrage.cast = PBSkillCast.new(skill)
	barrage.cast.spot = Vector2(0.45, 0.5)
	barrage.last_at = 16
	barrage.fired = 1
	var fx := PBFieldEffects.new()
	var team: Array[PBAttacker] = []
	var enemies: Array[PBEnemy] = []
	var barrages: Array[PBSkillBarrage] = [barrage]
	fx.sync_effects(team, enemies, 16, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 1)
	barrage.last_at = 26
	barrage.fired = 2
	fx.sync_effects(team, enemies, 26, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 2)
	fx.sync_effects(team, enemies, 47, 20, Vector2.ONE, barrages)
	assert_true(fx._impacts.is_empty())


func test_scatter_barrage_keeps_three_independent_landings_per_volley() -> void:
	var skill := PBGameData.config().skills.by_id(&"false_darkness").clone()
	assert_true(PBFieldArt.supports_scatter_area(skill))
	var barrage := PBSkillBarrage.new()
	barrage.cast = PBSkillCast.new(skill)
	barrage.cast.skill.radius = skill.hit_radius
	barrage.last_at = 6
	barrage.fired = 3
	barrage.landings = [Vector2(0.3, 0.4), Vector2(0.5, 0.4), Vector2(0.7, 0.4)]
	var fx := PBFieldEffects.new()
	var team: Array[PBAttacker] = []
	var enemies: Array[PBEnemy] = []
	var barrages: Array[PBSkillBarrage] = [barrage]
	fx.sync_effects(team, enemies, 6, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 3)
	barrage.last_at = 10
	barrage.fired = 6
	barrage.landings = [Vector2(0.35, 0.6), Vector2(0.5, 0.6), Vector2(0.65, 0.6)]
	fx.sync_effects(team, enemies, 10, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 6)
	for spot: Vector2 in barrage.landings:
		var found := false
		for entry: Dictionary in fx._impacts.values():
			if entry.spot == spot:
				found = true
		assert_true(found)
	fx.sync_effects(team, enemies, 31, 20, Vector2.ONE, barrages)
	assert_true(fx._impacts.is_empty())
	fx.free()


func test_travel_wave_keeps_real_step_snapshots_and_direction() -> void:
	var skill := PBGameData.config().skills.by_id(&"water_surge").clone()
	assert_true(PBFieldArt.supports_travel_wave_area(skill))
	var wave := PBTravelWave.new()
	wave.cast = PBSkillCast.new(skill)
	wave.cast.spot = Vector2(0.4, 0.5)
	wave.direction = Vector2.RIGHT
	wave.last_at = 8
	wave.fired = 1
	var fx := PBFieldEffects.new()
	var team: Array[PBAttacker] = []
	var enemies: Array[PBEnemy] = []
	var barrages: Array[PBSkillBarrage] = [wave]
	fx.sync_effects(team, enemies, 8, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 1)
	wave.cast.spot = Vector2(0.42, 0.52)
	wave.cast.skill.radius = 0.062
	wave.direction = Vector2(1, 1).normalized()
	wave.last_at = 10
	wave.fired = 2
	fx.sync_effects(team, enemies, 10, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 2)
	var first: Dictionary = fx._impacts["%d:1" % wave.get_instance_id()]
	var second: Dictionary = fx._impacts["%d:2" % wave.get_instance_id()]
	assert_eq(first.spot, Vector2(0.4, 0.5))
	assert_eq(second.spot, Vector2(0.42, 0.52))
	assert_almost_eq(first.rotation, 0.0, 0.00001)
	assert_true(second.rotation > 0.0)
	fx.free()


func test_expanding_self_strike_keeps_each_real_ring_radius() -> void:
	var skill := PBGameData.config().skills.by_id(&"sun_halo_dance").clone()
	assert_true(PBFieldArt.supports_expanding_self_area(skill))
	assert_false(PBFieldArt.supports_self_barrage_area(skill))
	var strike := PBExpandingStrike.new()
	strike.cast = PBSkillCast.new(skill)
	strike.spread = skill.radius
	strike.cast.skill.radius = 0.0
	strike.center = Vector2(0.4, 0.5)
	strike.last_at = 8
	strike.fired = 1
	var fx := PBFieldEffects.new()
	var team: Array[PBAttacker] = []
	var enemies: Array[PBEnemy] = []
	var barrages: Array[PBSkillBarrage] = [strike]
	fx.sync_effects(team, enemies, 8, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 1)
	strike.last_at = 16
	strike.fired = 5
	fx.sync_effects(team, enemies, 16, 20, Vector2.ONE, barrages)
	assert_eq(fx._impacts.size(), 2)
	var first: Dictionary = fx._impacts["%d:1" % strike.get_instance_id()]
	var fifth: Dictionary = fx._impacts["%d:5" % strike.get_instance_id()]
	assert_almost_eq(first.radius, 0.2165, 0.00001)
	assert_almost_eq(fifth.radius, 0.4825, 0.00001)
	fx.free()


func test_supported_choices_keep_single_and_multi_area_separate() -> void:
	var cfg := PBGameData.config()
	assert_true(PBFieldArt.supports_area(cfg.skills.by_id(&"ash_burn")))
	assert_false(PBFieldArt.supports_area(cfg.skills.by_id(&"infinite_sharks")))
	var bindings := PBFieldArtBindings.new()
	var found: Dictionary = {}
	for row: Dictionary in bindings.choices():
		found[row.id] = row.kind
	assert_eq(found.get("ash_burn"), "areas")
	assert_eq(found.get("bracken_dance"), "areas", "阵亡派生技能也能选择落地区域")
	assert_eq(found.get("clay_self_destruct"), "areas")
	assert_eq(found.get("samsara_rebirth"), "areas")
	assert_eq(found.get("monstrous_strength"), "areas")
	assert_eq(found.get("kaiten"), "areas")
	assert_eq(found.get("almighty_push"), "areas")
	assert_eq(found.get("dance_of_pines"), "areas")
	assert_eq(found.get("root_burial"), "areas")
	assert_eq(found.get("rising_earth"), "areas")
	assert_eq(found.get("piston_fist"), "areas")
	assert_eq(found.get("deity_gates"), "areas")
	assert_eq(found.get("palm_rotation"), "areas")
	assert_eq(found.get("leaf_whirl"), "areas")
	assert_eq(found.get("false_darkness"), "areas")
	assert_eq(found.get("water_surge"), "areas")
	assert_eq(found.get("earth_dragon"), "areas")
	assert_eq(found.get("shark_form"), "areas")
	assert_eq(found.get("sun_halo_dance"), "areas")
	assert_eq(found.get("shadow_hold"), "links")
	assert_eq(found.get("infinite_sharks"), "zones")
	assert_ne(bindings.save("areas", "../escape", PBFieldSkin.new()), "")
	var death_skin := PBFieldArt.read("areas", &"bracken_dance")
	assert_not_null(death_skin)
	assert_eq(death_skin.frames.size(), 6)
	var clay_skin := PBFieldArt.read("areas", &"clay_self_destruct")
	assert_not_null(clay_skin)
	assert_eq(clay_skin.frames.size(), 6)
	var healing_skin := PBFieldArt.read("areas", &"samsara_rebirth")
	assert_not_null(healing_skin)
	assert_eq(healing_skin.frames.size(), 6)
	var chain_skin := PBFieldArt.read("areas", &"monstrous_strength")
	assert_not_null(chain_skin)
	assert_eq(chain_skin.frames.size(), 6)
	assert_true(PBFieldArt.supports_attack_chain_area(cfg.skills.by_id(&"monstrous_strength")))
	var kaiten_skin := PBFieldArt.read("areas", &"kaiten")
	assert_not_null(kaiten_skin)
	assert_eq(kaiten_skin.frames.size(), 6)
	var push_skin := PBFieldArt.read("areas", &"almighty_push")
	assert_not_null(push_skin)
	assert_eq(push_skin.frames.size(), 6)
	var pines_skin := PBFieldArt.read("areas", &"dance_of_pines")
	assert_not_null(pines_skin)
	assert_eq(pines_skin.frames.size(), 6)
	var root_skin := PBFieldArt.read("areas", &"root_burial")
	assert_not_null(root_skin)
	assert_eq(root_skin.frames.size(), 6)
	var earth_skin := PBFieldArt.read("areas", &"rising_earth")
	assert_not_null(earth_skin)
	assert_eq(earth_skin.frames.size(), 6)
	var piston_skin := PBFieldArt.read("areas", &"piston_fist")
	assert_not_null(piston_skin)
	assert_eq(piston_skin.frames.size(), 6)
	var gates_skin := PBFieldArt.read("areas", &"deity_gates")
	assert_not_null(gates_skin)
	assert_eq(gates_skin.frames.size(), 6)
	var palm_skin := PBFieldArt.read("areas", &"palm_rotation")
	assert_not_null(palm_skin)
	assert_eq(palm_skin.frames.size(), 6)
	var whirl_skin := PBFieldArt.read("areas", &"leaf_whirl")
	assert_not_null(whirl_skin)
	assert_eq(whirl_skin.frames.size(), 6)
	var false_darkness_skin := PBFieldArt.read("areas", &"false_darkness")
	assert_not_null(false_darkness_skin)
	assert_eq(false_darkness_skin.frames.size(), 6)
	var surge_skin := PBFieldArt.read("areas", &"water_surge")
	assert_not_null(surge_skin)
	assert_eq(surge_skin.frames.size(), 6)
	var dragon_skin := PBFieldArt.read("areas", &"earth_dragon")
	assert_not_null(dragon_skin)
	assert_eq(dragon_skin.frames.size(), 6)
	var shark_skin := PBFieldArt.read("areas", &"shark_form")
	assert_not_null(shark_skin)
	assert_eq(shark_skin.frames.size(), 6)
	var halo_skin := PBFieldArt.read("areas", &"sun_halo_dance")
	assert_not_null(halo_skin)
	assert_eq(halo_skin.frames.size(), 6)
	var preview := PBFieldArtPreview.new()
	preview.kind = "areas"
	preview.skill = cfg.skills.by_id(&"shark_form")
	assert_almost_eq(preview.radius_units(), 0.3, 0.00001)
	preview.skill = cfg.skills.by_id(&"false_darkness")
	assert_almost_eq(preview.radius_units(), 0.0775, 0.00001)
	preview.free()


func test_control_visual_query_is_read_only_and_cancel_removes_link() -> void:
	var caster := PBAttacker.new()
	caster.alive = true
	var enemy := PBEnemy.new()
	enemy.spawn(PBWave.new(), 0, 0.5, 0)
	var channel := PBSkillChannel.new()
	channel.caster_ref = weakref(caster)
	channel.target_ref = weakref(enemy)
	var buff := PBBuff.new()
	buff.id = &"visual_hold"
	enemy.buffs.add(buff, {}, 1, 10, 0)
	channel.attach(enemy, buff.id, 1, true)
	assert_true(channel.valid_now(1))
	caster.alive = false
	assert_false(channel.valid_now(2))
	assert_true(channel.active, "渲染查询不能修改引导状态")
	caster.alive = true
	enemy.buffs.remove(buff.id, 2)
	assert_false(channel.valid_now(2))
	assert_true(channel.active)
	assert_false(channel.is_live(2), "结算查询锁定中断")
	assert_false(channel.active)


func test_art_reload_invalid_frames_and_duration() -> void:
	var bindings := PBFieldArtBindings.new()
	bindings.output_dir = "user://field_art_test"
	var skin := PBFieldSkin.new()
	var texture := ImageTexture.create_from_image(
		Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	)
	skin.frames = [texture, texture, texture]
	skin.fps = 10
	assert_eq(skin.duration(), 0.3)
	assert_eq(bindings.save("areas", "ash_burn", skin), "")
	var reloaded := bindings.read("areas", "ash_burn")
	assert_eq(reloaded.frames.size(), 3)
	assert_eq(reloaded.duration(), 0.3)
	assert_ne(bindings.import_frames(skin, ["res://missing_field_frame.png"]), "")
	assert_eq(skin.frames.size(), 3)
	skin.frames.append(null)
	assert_ne(skin.problem(), "")
	DirAccess.remove_absolute("user://field_art_test/areas/ash_burn.tres")
	DirAccess.remove_absolute("user://field_art_test/areas")
	DirAccess.remove_absolute("user://field_art_test")


func test_panel_and_clear_work_without_assets() -> void:
	var page := PBFieldArtPage.new()
	add_child_autofree(page)
	assert_gt(page._rows.size(), 0)
	var view := PBFieldEffects.new()
	add_child_autofree(view)
	var actor := PBAttacker.new()
	view.sync_effects([actor], [], 5, 20, Vector2.ONE)
	assert_eq(view._team.size(), 1)
	view.clear()
	assert_true(view._team.is_empty())
	assert_true(view._enemies.is_empty())
