extends GutTest

var _pool: PBAllyPool
var _one: PBAttacker
var _skin: PBActorSkin
var _unit: PBUnit


func before_each() -> void:
	_skin = PBActorSkin.new()
	_skin.frames = SpriteFrames.new()
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	for anim: StringName in [&"idle", &"attack", &"cast_probe"]:
		_skin.frames.add_animation(anim)
		_skin.frames.set_animation_speed(anim, 99)
		for i: int in 6:
			_skin.frames.add_frame(anim, texture)
	PBActorLibrary._cached[&"cast_animation_test"] = _skin
	var character := PBCharacter.new()
	character.actor_key = &"cast_animation_test"
	_unit = PBUnit.new(character)
	_one = PBAttacker.new()
	_one.max_hp = 1000
	_one.revive()
	var skill := PBSkill.new()
	skill.id = &"probe"
	var cast := PBSkillCast.new(skill)
	cast.cast(Vector2(0.5, 0), 0)
	_one.skills = [cast]
	PBSkillOrders.begin(_one, cast, PBSimConfig.new(), 0, null)
	_pool = PBAllyPool.new()
	add_child_autofree(_pool)


func after_each() -> void:
	PBActorLibrary._cached.erase(&"cast_animation_test")


func _sync(tick: int) -> AnimatedSprite2D:
	_pool.sync_allies([_one], [_unit], Vector2(1, 1), [], tick)
	return _pool._sprites[0]


func test_fallback_attack_is_six_fixed_frames_even_with_fast_art() -> void:
	for tick: int in 12:
		var sprite := _sync(tick)
		assert_eq(sprite.animation, &"attack")
		assert_eq(sprite.frame, int(tick / 2.0))
		assert_false(sprite.is_playing(), "动画由模拟帧定位")
	assert_ne(_sync(12).animation, &"attack")


func test_dedicated_animation_and_pause_speed_follow_sim_tick() -> void:
	_skin.skill_anims[&"probe"] = &"cast_probe"
	for speed: float in [0.0, 1.0, 4.0]:
		_pool.set_anim_speed(speed)
		for i: int in 5:
			var sprite := _sync(6)
			assert_eq(sprite.animation, &"cast_probe")
			assert_eq(sprite.frame, 3)
	assert_eq(_sync(10).frame, 5, "倍速跳过 tick 后直接定位正确帧")


func test_recast_identity_and_new_action_restart_are_stable() -> void:
	_skin.skill_anims[&"probe"] = &"cast_probe"
	_one.skills[0].skill.recast = PBSkill.new()
	_one.casting.advance(_one, PBSimConfig.new(), 6, null)
	_one.skills[0].land(6)
	assert_eq(_sync(8).animation, &"cast_probe")
	assert_eq(_sync(8).frame, 4)
	_one.casting.advance(_one, PBSimConfig.new(), 12, null)
	var cast := _one.skills[0]
	cast.skill.id = &"probe"
	cast.cast(Vector2(0.5, 0), 20)
	PBSkillOrders.begin(_one, cast, PBSimConfig.new(), 20, null)
	assert_eq(_sync(20).frame, 0)


func test_death_and_preparation_clear_cast_pose() -> void:
	_sync(4)
	_one.alive = false
	_one.casting.cancel(_one)
	_sync(4)
	assert_eq(_pool._poses[0].state, PBActorPose.State.DEAD)
	_pool.sync_placed([_unit], [Vector2.ZERO], Vector2(1, 1))
	assert_eq(_pool._sprites[0].animation, &"idle")


func test_pool_clears_start_layers_when_returning_to_preparation() -> void:
	var glow := PBBuffSkin.new()
	glow.placeholder = true
	PBCastGlow._starts[&"probe"] = glow
	_sync(2)
	assert_true(_pool._cast_backs[0].visible)
	assert_true(_pool._cast_fronts[0].visible)
	_pool.sync_placed([_unit], [Vector2.ZERO], Vector2(1, 1))
	assert_false(_pool._cast_backs[0].visible)
	assert_false(_pool._cast_fronts[0].visible)
	PBCastGlow.clear_cache()
