extends GutTest

var _pool: PBEnemyPool
var _enemy: PBEnemy
var _buff: PBBuff
var _skin: PBBuffSkin


func before_each() -> void:
	_pool = PBEnemyPool.new()
	add_child_autofree(_pool)
	_enemy = PBEnemy.new()
	_enemy.spawn(PBWave.new(), 0, 0.5, 0, 0.3)
	_buff = load("res://data/buffs/serpent_slow.tres") as PBBuff
	_skin = PBBuffSkin.new()
	_skin.placeholder = true
	PBBuffGlow._library[_buff.id] = _skin


func after_each() -> void:
	PBBuffGlow._library.erase(_buff.id)


func _sync(tick: int) -> void:
	_pool.sync_enemies([_enemy], tick, Vector2.ONE)


func test_enemy_glow_tracks_buff_window_and_pool_nodes_are_reused() -> void:
	var count := _pool.get_child_count()
	_enemy.buffs.add(_buff, {}, 0, 10, 0)
	_sync(0)
	assert_eq(_pool._glow_backs[0]._drawings.size(), 1)
	assert_eq(_pool._glow_fronts[0]._drawings.size(), 1)
	assert_eq(_pool._anchors[0].position, _pool.screen_position(_enemy, Vector2.ONE))
	assert_lt(_pool._glow_backs[0].get_index(), _pool._nodes[0].get_index())
	assert_gt(_pool._glow_fronts[0].get_index(), _pool._nodes[0].get_index())
	var drawing: Dictionary = _pool._glow_backs[0]._drawings[0].duplicate()
	_sync(0)
	assert_eq(_pool._glow_backs[0]._drawings[0], drawing, "暂停时不走帧")
	_sync(10)
	assert_true(_pool._glow_backs[0].visible, "到期tick仍生效")
	_sync(11)
	assert_false(_pool._glow_backs[0].visible)
	assert_false(_pool._glow_fronts[0].visible)
	assert_eq(_pool.get_child_count(), count)


func test_cancel_and_eviction_remove_effect_without_waiting_for_original_expiry() -> void:
	_enemy.buffs.add(_buff, {}, 0, 100, 0)
	_sync(0)
	_enemy.buffs.remove(_buff.id, 1)
	_sync(1)
	assert_false(_pool._glow_fronts[0].visible)
	_enemy.buffs.add(_buff, {}, 2, 100, 0)
	for i: int in PBBuffBag.SLOTS:
		var filler := PBBuff.new()
		filler.id = StringName("enemy_glow_filler_%d" % i)
		_enemy.buffs.add(filler, {}, 2, 1000, 0)
	_sync(2)
	assert_false(_pool._glow_backs[0].visible)
	assert_false(_pool._glow_fronts[0].visible)


func test_death_hidden_slot_and_new_spawn_clear_previous_glow() -> void:
	_enemy.buffs.add(_buff, {}, 0, 100, 0)
	_sync(0)
	_enemy.alive = false
	_sync(1)
	assert_true(_pool._nodes[0].visible, "倒地动作保留")
	assert_false(_pool._glow_backs[0].visible, "尸体不保留状态光")
	_enemy.spawn(PBWave.new(), 0, 0.5, 100, 0.3)
	_sync(2)
	assert_false(_pool._nodes[0].visible)
	assert_false(_pool._glow_fronts[0].visible)
	_sync(100)
	assert_true(_pool._nodes[0].visible)
	assert_true(_pool._glow_backs[0]._drawings.is_empty())
	_enemy.buffs.add(_buff, {}, 100, 100, 0)
	_sync(100)
	_pool.sync_enemies([], 0, Vector2.ONE)
	assert_false(_pool._glow_backs[0].visible)
	assert_false(_pool._glow_fronts[0].visible)


func test_channel_view_hides_invalid_hold_without_mutating_channel() -> void:
	var caster := PBAttacker.new()
	caster.alive = true
	var channel := PBSkillChannel.new()
	channel.caster_ref = weakref(caster)
	channel.target_ref = weakref(_enemy)
	_enemy.buffs.add(_buff, {}, 0, 100, 0)
	channel.attach(_enemy, _buff.id, 0, true)
	var glow := _pool._glow_backs[0]
	glow.sync_bag(_enemy.buffs, 1, 20)
	assert_true(glow.visible)
	caster.alive = false
	glow.sync_bag(_enemy.buffs, 2, 20)
	assert_false(glow.visible)
	assert_true(channel.active, "光效查询不能锁定逻辑中断")


func test_tool_labels_enemy_states_and_whole_sheet_keeps_both_layers() -> void:
	var page := PBBuffArtPage.new()
	add_child_autofree(page)
	for i: int in page._buffs.item_count:
		if page._buffs.get_item_metadata(i) == "serpent_slow":
			assert_true(page._buffs.get_item_text(i).begins_with("[敌方]"))
			page._buffs.select(i)
			page._select()
	var image := Image.create_empty(96, 64, false, Image.FORMAT_RGBA8)
	for i: int in 6:
		image.fill_rect(Rect2i((i % 3) * 32 + 8, (i / 3) * 32 + 8, 16, 16), Color.WHITE)
	var path := "user://enemy_buff_sheet.png"
	assert_eq(image.save_png(path), OK)
	page._sheet.use_sheet(path)
	assert_true(page._cut())
	page._layer.select(1)
	assert_true(page._cut())
	assert_eq(page._skin.back_frames.size(), 6)
	assert_eq(page._skin.front_frames.size(), 6)
	page._bindings.output_dir = "user://enemy_buff_bindings"
	assert_eq(page._bindings.save("serpent_slow", page._skin), "")
	assert_eq(page._bindings.read("serpent_slow").front_frames.size(), 6)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://enemy_buff_bindings/serpent_slow.tres")
	DirAccess.remove_absolute("user://enemy_buff_bindings")
