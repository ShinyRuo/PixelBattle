extends GutTest

var _cfg: PBSimConfig
var _sim: PBBattleSim
var _pool: PBShotPool
var _caster: PBAttacker
var _art: PBShotSkin


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.spawn_window = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5731
	_caster = PBAttacker.new()
	_caster.slot = 0
	_caster.max_hp = 1000.0
	_caster.hp = 1000.0
	_caster.pos = Vector2(0.2, 0.2)
	_sim = PBBattleSim.new(PBWaveRules.build(4, _cfg, rng), 0.0, 0.0, _cfg, [_caster])
	_pool = PBShotPool.new()
	add_child_autofree(_pool)
	var texture := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	_art = PBShotForge.new().assemble("skill_probe", [texture], [texture])
	PBShotLibrary._cached = {&"skill_probe": _art}
	PBShotLibrary._loaded = true


func after_each() -> void:
	PBShotLibrary.reload()


func _skill() -> PBSkill:
	var skill := PBSkill.new()
	skill.id = &"test_skill"
	skill.shot_key = &"skill_probe"
	skill.target = PBSkill.Target.ENEMY
	skill.shot_cross_seconds = 0.3
	return skill


func _sync(book: PBBattleLog = null) -> void:
	_pool.sync_shots(_sim, [], book, Vector2(_cfg.field_length, _cfg.field_height))


func test_locked_skill_flight_and_hit_use_skill_art_without_normal_attack_binding() -> void:
	var skill := _skill()
	var shot := _sim.shots()[0]
	shot.launch(_caster.pos, 0, 10.0, 0.01, false, PBElement.Type.WATER, 0, skill)
	_sync()
	assert_eq(_pool._fly[0].sprite_frames, _art.frames)
	var book := PBBattleLog.new()
	PBSkillRules.hit_by_shot(_sim.enemies()[0], shot, _caster, _cfg, 1, book)
	assert_eq(book.entries[0].get("shot_key"), &"skill_probe")
	_sync(book)
	assert_eq(_pool._hits[0].sprite_frames, _art.frames)
	assert_eq(_pool._hits[0].animation, _art.anim_hit)
	assert_eq(_pool.sparks(), 1)
	shot.launch(_caster.pos, 0, 10.0, 0.01, false, PBElement.Type.WATER, 0)
	_sync()
	assert_eq(_pool._fly[0].sprite_frames, PBWhiteModel.shot().frames)


func test_ground_delay_uses_carrier_art_without_creating_simulation_projectiles() -> void:
	var skill := _skill()
	skill.target = PBSkill.Target.GROUND
	skill.shot_cross_seconds = 0.0
	skill.delay_ticks = 10
	var cast := PBSkillCast.new(skill)
	_caster.skills.append(cast)
	cast.cast(Vector2(0.7, 0.2), _sim.current_tick())
	_sync()
	assert_eq(_pool._casts[0].sprite_frames, _art.frames)
	assert_eq(_pool.shown(), 1)
	for shot: PBProjectile in _sim.shots():
		assert_false(shot.alive)
	assert_eq(cast.lands_at, _sim.current_tick() + 10)


func test_mind_control_contact_gets_art_event_without_fake_damage() -> void:
	var skill := _skill()
	skill.mind_control = true
	var buff := PBBuff.new()
	buff.id = &"test_hold"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 1.0
	buff.mods = {PBBuffRules.STUN: 1.0}
	skill.on_hit = [buff]
	var shot := PBProjectile.new()
	shot.launch(_caster.pos, 0, 0.0, 1.0, false, PBElement.Type.WATER, 0, skill)
	var book := PBBattleLog.new()
	var enemy := _sim.enemies()[0]
	var hp := enemy.hp
	PBSkillRules.hit_by_shot(enemy, shot, _caster, _cfg, 1, book)
	assert_eq(enemy.hp, hp)
	assert_eq(book.entries.size(), 1)
	assert_eq(book.entries[0]["kind"], PBBattleLog.Kind.SKILL_IMPACT)
	assert_false(book.entries[0].has("amount"))
	_sync(book)
	assert_eq(_pool._hits[0].sprite_frames, _art.frames)


func test_healing_projectile_uses_contact_art_without_damage_log() -> void:
	var skill := _skill()
	skill.target = PBSkill.Target.ALLY
	skill.affects = PBSkill.Party.ALLIES
	var buff := PBBuff.new()
	buff.id = &"test_heal"
	buff.mods = {PBBuffRules.HEAL: 20.0}
	skill.on_hit = [buff]
	_caster.hp = 500.0
	var shot := _sim.shots()[0]
	shot.launch(_caster.pos, 0, 0.0, 1.0, true, PBElement.Type.WATER, 0, skill)
	var book := PBBattleLog.new()
	PBShotRules.advance(
		_sim.shots(), _sim.enemies(), _sim.attackers(), _cfg, 1, book, PBCombatOutcome.new()
	)
	assert_eq(_caster.hp, 520.0)
	assert_eq(book.entries[0]["kind"], PBBattleLog.Kind.SKILL_IMPACT)
	assert_true(book.entries[0]["to_ally"])
	_sync(book)
	assert_eq(_pool._hits[0].sprite_frames, _art.frames)
