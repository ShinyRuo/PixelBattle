class_name PBSummonRemains
extends RefCounted
## 已显示的召唤物退场时，保留独立倒地快照；不占模拟槽、不影响再召唤。

var _records: Dictionary = {}
var _tick_rate: int = 20
var _last_tick: int = -1


func ensure_capacity(want: int, parent: Node) -> void:
	for slot: int in range(_records.size(), want):
		var sprite := AnimatedSprite2D.new()
		sprite.centered = false
		sprite.visible = false
		parent.add_child(sprite)
		_records[slot] = {"sprite": sprite, "started": -1, "watching": false}


func sync(attackers: Array[PBAttacker], tick: int, field: Vector2) -> void:
	if tick < _last_tick:
		clear()
	_last_tick = tick
	var present: Dictionary = {}
	for attacker: PBAttacker in attackers:
		present[attacker.slot] = attacker
	for id: int in _records:
		var record: Dictionary = _records[id]
		var attacker := present.get(id) as PBAttacker
		if (
			record.watching
			and (
				attacker == null
				or attacker.expires_at == PBSummonRules.GONE
				or attacker.get_instance_id() != record.identity
				or attacker.summon_serial != record.serial
				or not attacker.alive
			)
		):
			record.watching = false
			record.started = tick
			record.at = record.at_live
			if (
				attacker != null
				and attacker.get_instance_id() == record.identity
				and attacker.summon_serial == record.serial
			):
				record.at = attacker.pos
			_start(record)
		var sprite: AnimatedSprite2D = record.sprite
		if record.started < 0 or not sprite.visible:
			continue
		sprite.position = PBLayout.to_screen(record.at, field)
		var elapsed := float(tick - int(record.started)) / float(_tick_rate)
		var frames := sprite.sprite_frames
		var anim := sprite.animation
		var fps := maxf(frames.get_animation_speed(anim), 0.001)
		var frame: int = 0
		while frame < frames.get_frame_count(anim):
			var duration := frames.get_frame_duration(anim, frame) / fps
			if elapsed < duration:
				break
			elapsed -= duration
			frame += 1
		if frame >= frames.get_frame_count(anim):
			sprite.visible = false
		else:
			sprite.frame = frame


func remember(attacker: PBAttacker, source: AnimatedSprite2D, skin: PBActorSkin) -> void:
	if not attacker.summoned or not attacker.alive or not _records.has(attacker.slot):
		return
	var record: Dictionary = _records[attacker.slot]
	record.watching = true
	record.serial = attacker.summon_serial
	record.identity = attacker.get_instance_id()
	record.skin = skin
	record.at_live = attacker.pos
	record.flip = source.flip_h
	record.tint = source.modulate


func clear() -> void:
	for record: Dictionary in _records.values():
		record.sprite.visible = false
		record.started = -1
		record.watching = false
	_last_tick = -1


func _start(record: Dictionary) -> void:
	var sprite: AnimatedSprite2D = record.sprite
	var skin: PBActorSkin = record.skin
	if not skin.has(skin.anim_dead):
		sprite.visible = false
		return
	if not record.has("at"):
		record.at = record.at_live
	sprite.sprite_frames = skin.frames
	sprite.offset = skin.draw_offset()
	sprite.scale = Vector2.ONE * skin.pixel_scale
	sprite.texture_filter = skin.filter_mode()
	sprite.flip_h = skin.flips_for(
		(
			PBActorPose.FACE_LEFT
			if record.flip != skin.flips_for(PBActorPose.FACE_RIGHT)
			else PBActorPose.FACE_RIGHT
		)
	)
	sprite.modulate = record.tint
	sprite.animation = skin.anim_dead
	sprite.pause()
	sprite.frame = 0
	sprite.visible = true
