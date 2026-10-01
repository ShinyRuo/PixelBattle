extends GutTest

const COPY_SKILL = preload("res://data/skills/white_copy.tres")
const ROOT := "user://summon_art_test"
var _bindings: PBSummonArtBindings
var _skin: PBActorSkin


func before_each() -> void:
	_bindings = PBSummonArtBindings.new()
	_bindings.binding_dir = ROOT + "/bindings"
	_bindings.actor_dir = ROOT + "/actors"
	_bindings.shot_dir = ROOT + "/shots"
	for directory: String in [_bindings.actor_dir, _bindings.shot_dir, _bindings.binding_dir]:
		DirAccess.make_dir_recursive_absolute(directory)
	_skin = PBWhiteModel.ally().duplicate(true) as PBActorSkin
	_skin.key = &"summon_probe"
	for anim: StringName in [_skin.anim_idle, _skin.anim_run, _skin.anim_attack, _skin.anim_dead]:
		while _skin.frames.get_frame_count(anim) < 6:
			_skin.frames.add_frame(anim, _skin.frames.get_frame_texture(anim, 0))
		while _skin.frames.get_frame_count(anim) > 6:
			_skin.frames.remove_frame(anim, _skin.frames.get_frame_count(anim) - 1)
		_skin.frames.set_animation_speed(anim, 10.0)
	ResourceSaver.save(_skin, _bindings.actor_dir + "/summon_probe.tres")
	var shot := PBWhiteModel.shot().duplicate(true) as PBShotSkin
	shot.key = &"summon_bullet"
	ResourceSaver.save(shot, _bindings.shot_dir + "/summon_bullet.tres")


func after_each() -> void:
	PBSummonArt.clear_cache()
	PBActorLibrary.reload()
	PBShotLibrary.reload()
	_wipe(ROOT)


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for directory: String in DirAccess.get_directories_at(path):
		_wipe(path.path_join(directory))
	DirAccess.remove_absolute(path)


func test_only_real_summons_are_listed_and_binding_round_trips() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in _bindings.entries():
		ids.append(entry.id)
	assert_eq(ids.size(), 6)
	assert_has(ids, "sun_halo_dance")
	assert_does_not_have(ids, "clay_spider")
	assert_eq(_bindings.assign("puppet_crow", "summon_probe", "summon_bullet"), "")
	var art := _bindings.read("puppet_crow")
	assert_eq(art.actor_key, &"summon_probe")
	assert_eq(art.shot_key, &"summon_bullet")
	assert_eq(_bindings.assign("puppet_crow", "", ""), "")
	assert_eq(_bindings.read("puppet_crow").actor_key, &"")
	assert_ne(_bindings.assign("ash_burn", "summon_probe", ""), "")


func test_invalid_assets_cannot_overwrite_saved_binding() -> void:
	assert_eq(_bindings.assign("puppet_crow", "summon_probe", "summon_bullet"), "")
	assert_ne(_bindings.assign("puppet_crow", "missing", ""), "")
	assert_ne(_bindings.assign("puppet_crow", "summon_probe", "missing"), "")
	_skin.frames.remove_frame(_skin.anim_dead, 0)
	ResourceSaver.save(_skin, _bindings.actor_dir + "/summon_probe.tres")
	assert_ne(_bindings.assign("puppet_crow", "summon_probe", ""), "")
	assert_eq(_bindings.read("puppet_crow").shot_key, &"summon_bullet")


func _summon() -> PBAttacker:
	var caster := PBAttacker.new()
	caster.attack = 20.0
	caster.max_hp = 100.0
	caster.attack_speed = 1.0
	caster.shot_speed = 0.01
	caster.reach = 2.0
	caster.pos = Vector2(0.2, 0.3)
	var one := PBAttacker.new()
	one.slot = 0
	one.summoned = true
	PBSummonRules.raise_from(
		[one], caster, load("res://data/skills/puppet_crow.tres"), 0, PBSimConfig.new()
	)
	return one


func test_birth_and_inflight_projectile_keep_summon_identity() -> void:
	var one := _summon()
	assert_eq(one.summon_skill_id, &"puppet_crow")
	assert_eq(one.summon_serial, 1)
	var enemy := PBEnemy.new()
	enemy.spawn(PBWave.new(), 0, 0.5, 0, 0.3)
	var shot := PBProjectile.new()
	assert_true(
		PBStrikeRules._strike_single(
			one,
			[enemy],
			[shot],
			0,
			PBSimConfig.new(),
			0,
			RandomNumberGenerator.new(),
			null,
			PBCombatOutcome.new()
		)
	)
	assert_eq(shot.summon_skill_id, &"puppet_crow")
	PBSummonRules.dismiss(one)
	PBSummonRules.raise_from([one], PBAttacker.new(), COPY_SKILL, 1, PBSimConfig.new())
	assert_eq(one.summon_skill_id, &"white_copy")
	assert_eq(one.summon_serial, 2)
	assert_eq(shot.summon_skill_id, &"puppet_crow", "在途弹不读复用后的槽位")
	shot.retire()
	assert_eq(shot.summon_skill_id, &"")
	shot.summon_skill_id = &"old"
	shot.launch(Vector2.ZERO, 0, 1.0, 1.0)
	assert_eq(shot.summon_skill_id, &"")


func test_shadow_clone_birth_smoke_plays_once_and_expires() -> void:
	var art := load("res://data/summon_art/shadow_clones.tres") as PBSummonArt
	assert_eq(art.spawn_fx_key, &"summon_shadow_clones_spawn")
	var skin := load(
		"res://data/instant_buff_art/summon_shadow_clones_spawn.tres"
	) as PBBuffSkin
	assert_eq(skin.front_frames.size(), 6)
	var caster := PBAttacker.new()
	caster.attack = 20.0
	caster.max_hp = 100.0
	caster.attack_speed = 1.0
	caster.shot_speed = 0.01
	caster.reach = 2.0
	caster.pos = Vector2(0.2, 0.3)
	var one := PBAttacker.new()
	one.slot = 0
	one.summoned = true
	PBSummonRules.raise_from(
		[one], caster, load("res://data/skills/shadow_clones.tres"), 0, PBSimConfig.new()
	)
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	pool.sync_allies([one], [], Vector2.ONE, [], 0)
	assert_eq(pool._spawn_keys[0], &"summon_shadow_clones_spawn")
	assert_true(pool._spawn_fronts[0].visible)
	pool.sync_allies([one], [], Vector2.ONE, [], 10)
	assert_false(pool._spawn_fronts[0].visible)
	PBSummonRules.dismiss(one)
	pool.sync_allies([one], [], Vector2.ONE, [], 11)
	assert_eq(pool._spawn_keys[0], &"")
	var dog_art := load("res://data/summon_art/pursuing_fangs.tres") as PBSummonArt
	assert_eq(dog_art.spawn_fx_key, &"summon_pursuing_fangs_spawn")
	var dog_smoke := load(
		"res://data/instant_buff_art/summon_pursuing_fangs_spawn.tres"
	) as PBBuffSkin
	assert_eq(dog_smoke.front_frames.size(), 6)
	assert_almost_eq(dog_smoke.pixel_scale, 0.18, 0.001)
	var white_art := load("res://data/summon_art/white_copy.tres") as PBSummonArt
	assert_eq(white_art.spawn_fx_key, &"summon_white_copy_spawn")
	var white_spores := load(
		"res://data/instant_buff_art/summon_white_copy_spawn.tres"
	) as PBBuffSkin
	assert_eq(white_spores.front_frames.size(), 6)
	var crow_art := load("res://data/summon_art/puppet_crow.tres") as PBSummonArt
	assert_eq(crow_art.spawn_fx_key, &"summon_puppet_crow_spawn")
	assert_eq(crow_art.shot_key, &"qianben")
	var crow_smoke := load(
		"res://data/instant_buff_art/summon_puppet_crow_spawn.tres"
	) as PBBuffSkin
	assert_eq(crow_smoke.front_frames.size(), 6)
	var bugs_art := load("res://data/summon_art/vampire_bugs.tres") as PBSummonArt
	assert_eq(bugs_art.spawn_fx_key, &"summon_vampire_bugs_spawn")
	assert_eq(bugs_art.shot_key, &"bugsball")
	var bugs_spawn := load(
		"res://data/instant_buff_art/summon_vampire_bugs_spawn.tres"
	) as PBBuffSkin
	assert_eq(bugs_spawn.front_frames.size(), 6)
	assert_almost_eq(bugs_spawn.pixel_scale, 0.25, 0.001)
	var halo_art := load("res://data/summon_art/sun_halo_dance.tres") as PBSummonArt
	assert_eq(halo_art.spawn_fx_key, &"summon_sun_halo_spawn")
	var halo_spawn := load(
		"res://data/instant_buff_art/summon_sun_halo_spawn.tres"
	) as PBBuffSkin
	assert_eq(halo_spawn.front_frames.size(), 6)


func test_live_skin_and_death_snapshot_survive_slot_reuse_and_pause() -> void:
	var art := PBSummonArt.new()
	art.actor_key = _skin.key
	PBSummonArt._cache[&"puppet_crow"] = art
	PBActorLibrary._cached[_skin.key] = _skin
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	var one := _summon()
	var nodes := pool.get_child_count()
	pool.sync_allies([one], [], Vector2.ONE, [], 0)
	assert_same(pool._skins[0], _skin)
	one.pos = Vector2(0.4, 0.3)
	pool.sync_allies([one], [], Vector2.ONE, [], 1)
	assert_eq(pool._sprites[0].animation, _skin.anim_run)
	PBSummonRules.dismiss(one)
	pool.sync_allies([one], [], Vector2.ONE, [], 2)
	var corpse: AnimatedSprite2D = pool._remains._records[one.slot].sprite
	assert_true(corpse.visible)
	assert_eq(corpse.animation, _skin.anim_dead)
	assert_false(pool._sprites[0].visible)
	assert_eq(corpse.position, PBLayout.to_screen(one.pos, Vector2.ONE))
	pool.sync_allies([one], [], Vector2.ONE, [], 6)
	assert_eq(corpse.frame, 2)
	pool.sync_allies([one], [], Vector2.ONE, [], 6)
	assert_eq(corpse.frame, 2, "暂停不走帧")
	PBSummonRules.raise_from([one], PBAttacker.new(), COPY_SKILL, 7, PBSimConfig.new())
	one.max_hp = 100.0
	one.hp = 100.0
	pool.sync_allies([one], [], Vector2.ONE, [], 7)
	assert_true(corpse.visible, "新召唤不截断旧倒地")
	assert_same(
		pool._skins[0],
		PBActorLibrary.skin_for(&"summon_white_copy"),
		"白绝复制体已有正式绑定，槽位复用后应读取专属形象",
	)
	pool.sync_allies([one], [], Vector2.ONE, [], 14)
	assert_false(corpse.visible)
	assert_eq(pool.get_child_count(), nodes, "退场精灵复用预分配节点")
	pool.clear()
	for record: Dictionary in pool._remains._records.values():
		assert_false(record.sprite.visible)
		assert_false(record.watching)


func test_page_exposes_four_actions_and_persists_selected_assets() -> void:
	var page := PBSummonArtPage.new()
	page._bindings = _bindings
	add_child_autofree(page)
	assert_eq(page._actions.item_count, 4)
	assert_eq(page._summons.item_count, 6)
	page._actors.select(1)
	page._shots.select(1)
	page._show_preview()
	assert_true(page._preview.visible)
	assert_true(page._bullet.visible)
	page._save()
	assert_eq(_bindings.read(page._id()).actor_key, &"summon_probe")
	page._actions.select(3)
	page._show_preview()
	assert_eq(page._preview.animation, _skin.anim_dead)


func test_projectile_view_uses_snapshot_skin_and_its_muzzle() -> void:
	var art := PBSummonArt.new()
	art.actor_key = _skin.key
	art.shot_key = &"summon_bullet"
	PBSummonArt._cache[&"puppet_crow"] = art
	_skin.muzzle_offset = Vector2(13, -37)
	PBActorLibrary._cached[_skin.key] = _skin
	var bullet := load(ROOT + "/shots/summon_bullet.tres") as PBShotSkin
	PBShotLibrary.skins()[art.shot_key] = bullet
	var cfg := PBSimConfig.new()
	cfg.spawn_window = 0.0
	var one := _summon()
	var battle := PBBattleSim.new(
		PBWaveRules.build(4, cfg, RandomNumberGenerator.new()), 0, 0, cfg, [one]
	)
	var shot: PBProjectile = battle.shots()[0]
	shot.launch(Vector2(0.2, 0.3), 0, 5, 0.01, false, PBElement.Type.PHYSICAL, 0)
	shot.summon_skill_id = &"puppet_crow"
	one.summon_skill_id = &"white_copy"
	var pool := PBShotPool.new()
	add_child_autofree(pool)
	pool.sync_shots(battle, [], null, Vector2.ONE)
	assert_same(pool._fly[0].sprite_frames, bullet.frames)
	assert_eq(pool.at(0), PBLayout.to_screen(shot.from, Vector2.ONE) + _skin.muzzle())


func test_shadow_clones_use_complete_same_size_naruto_art() -> void:
	var art := PBSummonArt.for_skill(&"shadow_clones")
	assert_eq(art.actor_key, &"summon_shadow_clones")
	assert_eq(art.shot_key, &"", "近战影分身不绑定远程子弹")
	var clone := PBActorLibrary.skin_for(art.actor_key)
	var naruto := PBActorLibrary.skin_for(&"naruto")
	assert_not_null(clone)
	assert_not_null(naruto)
	for anim: StringName in [&"idle", &"run", &"attack", &"dead"]:
		assert_true(clone.frames.has_animation(anim))
		assert_eq(clone.frames.get_frame_count(anim), 6)
	assert_almost_eq(
		_idle_visible_height(clone),
		_idle_visible_height(naruto),
		1.0,
		"影分身可见高度必须与鸣人本体一致",
	)
	assert_lt(_run_center_span(clone), 0.5, "影分身跑步六帧不得左右横移")


func test_remaining_summons_have_complete_art_bindings_and_required_sizes() -> void:
	var expected := {
		&"white_copy": {
			"actor": &"summon_white_copy", "shot": &"", "reference": &"naruto", "scale": 1.0
		},
		&"puppet_crow": {
			"actor": &"summon_puppet_crow",
			"shot": &"qianben",
			"reference": &"naruto",
			"scale": 1.0,
		},
		&"vampire_bugs": {
			"actor": &"summon_vampire_bugs",
			"shot": &"bugsball",
			"reference": &"naruto",
			"scale": 1.0,
		},
		&"pursuing_fangs": {
			"actor": &"summon_pursuing_fangs",
			"shot": &"",
			"reference": &"naruto",
			"scale": 0.5,
		},
		&"sun_halo_dance": {
			"actor": &"summon_sun_halo_dance",
			"shot": &"",
			"reference": &"shisui",
			"scale": 1.0,
		},
	}
	for skill_id: StringName in expected:
		var spec: Dictionary = expected[skill_id]
		var art := PBSummonArt.for_skill(skill_id)
		assert_eq(art.actor_key, spec.actor)
		assert_eq(art.shot_key, spec.shot)
		var skin := PBActorLibrary.skin_for(art.actor_key)
		assert_not_null(skin)
		for anim: StringName in [&"idle", &"run", &"attack", &"dead"]:
			assert_true(skin.frames.has_animation(anim))
			assert_eq(skin.frames.get_frame_count(anim), 6)
		var reference := PBActorLibrary.skin_for(spec.reference)
		assert_not_null(reference)
		assert_almost_eq(
			_idle_visible_height(skin),
			_idle_visible_height(reference) * float(spec.scale),
			1.0,
			"召唤物必须遵守忍者同高或忍犬半高约束：%s" % skill_id,
		)
		assert_lt(_run_center_span(skin), 0.5, "召唤物跑步六帧不得左右横移：%s" % skill_id)


func _idle_visible_height(skin: PBActorSkin) -> float:
	var total := 0.0
	var count := skin.frames.get_frame_count(&"idle")
	for frame: int in count:
		var image := skin.frames.get_frame_texture(&"idle", frame).get_image()
		total += float(image.get_used_rect().size.y) * skin.pixel_scale
	return total / float(count)


func _run_center_span(skin: PBActorSkin) -> float:
	var low := INF
	var high := -INF
	for frame: int in skin.frames.get_frame_count(&"run"):
		var image := skin.frames.get_frame_texture(&"run", frame).get_image()
		var used := image.get_used_rect()
		var center := (float(used.position.x) + float(used.size.x) * 0.5) * skin.pixel_scale
		low = minf(low, center)
		high = maxf(high, center)
	return high - low
