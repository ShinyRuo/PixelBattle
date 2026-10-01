class_name PBFieldEffects
extends Node2D
## 地面落地单次动画与真实控制连线；统一受战场裁切，人物画在其上。

var _team: Array[PBAttacker] = []
var _enemies: Array[PBEnemy] = []
var _barrages: Array[PBSkillBarrage] = []
## 留住已观察到的单次落地，结算池复用不能截断正在播放的动画。
var _impacts: Dictionary = {}
var _leech_links: Array[Dictionary] = []
var _seen_log: int = 0
var _tick: int = 0
var _rate: int = 20
var _field := Vector2.ONE


func _ready() -> void:
	var clip := get_parent() as Control
	if clip != null and clip.clip_contents:
		position = -PBLayout.B_FIELD.position


func sync_effects(
	team: Array[PBAttacker],
	enemies: Array[PBEnemy],
	tick: int,
	rate: int,
	field: Vector2,
	barrages: Array[PBSkillBarrage] = [],
	book: PBBattleLog = null
) -> void:
	if tick < _tick:
		_impacts.clear()
		_leech_links.clear()
		_seen_log = 0
	_team = team
	_enemies = enemies
	_barrages = barrages
	_tick = tick
	_rate = maxi(rate, 1)
	_field = field
	_sync_impacts()
	_sync_leech_links(book)
	queue_redraw()


func clear() -> void:
	_impacts.clear()
	_leech_links.clear()
	_seen_log = 0
	_barrages = []
	_team = []
	_enemies = []
	queue_redraw()


func _draw() -> void:
	for barrage: PBSkillBarrage in _barrages:
		PBPersistentFieldArt.draw(self, barrage, _tick, _rate, _field)
	for entry: Dictionary in _impacts.values():
		var center := PBLayout.to_screen(entry.spot, _field)
		if entry.has("rotation"):
			draw_set_transform(center, entry.rotation)
			center = Vector2.ZERO
		PBFieldArt.draw_area(
			self, entry.skin, center, entry.radius * PBLayout.px_per_unit(_field),
			float(_tick - entry.tick) / _rate
		)
		if entry.has("rotation"):
			draw_set_transform(Vector2.ZERO)
	for entry: Dictionary in _leech_links:
		PBFieldArt.draw_link(
			self, entry.skin, entry.from, entry.to,
			float(_tick - entry.tick) / _rate
		)
	for actor: PBAttacker in _team:
		for i: int in PBSkillRules.cast_count(actor):
			var cast := PBSkillRules.cast_at(actor, i)
			_draw_enemy_aura(actor, cast)
			_draw_cast(cast)
			_draw_attack_chain(cast)
		for cast: PBSkillCast in actor.attack_casts:
			_draw_attack_chain(cast)
		for cast: PBSkillCast in actor.death_casts:
			_draw_cast(cast)
	for enemy: PBEnemy in _enemies:
		if not enemy.is_active(_tick):
			continue
		for state: PBBuffState in enemy.buffs.states():
			_draw_link(enemy, state)
	for target: PBAttacker in _team:
		if not target.alive:
			continue
		for state: PBBuffState in target.buffs.states():
			_draw_ally_link(target, state)


func _sync_impacts() -> void:
	for key in _impacts.keys():
		var entry: Dictionary = _impacts[key]
		if float(_tick - entry.tick) / _rate >= entry.skin.duration():
			_impacts.erase(key)
	for barrage: PBSkillBarrage in _barrages:
		if barrage.cast == null or barrage.last_at < 0 or _tick < barrage.last_at:
			continue
		var skill := barrage.cast.skill
		if barrage is PBExpandingStrike and PBFieldArt.supports_expanding_self_area(skill):
			var ring_skin := PBFieldArt.read("areas", PBPersistentFieldArt.art_key(skill))
			if ring_skin == null or float(_tick - barrage.last_at) / _rate >= ring_skin.duration():
				continue
			var ring_key := "%d:%d" % [barrage.get_instance_id(), barrage.fired]
			if not _impacts.has(ring_key):
				_impacts[ring_key] = {
					"skin": ring_skin,
					"tick": barrage.last_at,
					"spot": barrage.visual_spot(),
					"radius": barrage.visual_radius()
				}
			continue
		if barrage is PBTravelWave and PBFieldArt.supports_travel_wave_area(skill):
			var wave_skin := PBFieldArt.read("areas", PBPersistentFieldArt.art_key(skill))
			if wave_skin == null or float(_tick - barrage.last_at) / _rate >= wave_skin.duration():
				continue
			var wave_key := "%d:%d" % [barrage.get_instance_id(), barrage.fired]
			if not _impacts.has(wave_key):
				var wave := barrage as PBTravelWave
				var projected := Vector2(wave.direction.x, wave.direction.y * PBLayout.Y_SCALE)
				_impacts[wave_key] = {
					"skin": wave_skin,
					"tick": barrage.last_at,
					"spot": barrage.visual_spot(),
					"radius": barrage.visual_radius(),
					"rotation": projected.angle()
				}
			continue
		if PBFieldArt.supports_scatter_area(skill):
			var scatter_skin := PBFieldArt.read("areas", PBPersistentFieldArt.art_key(skill))
			if scatter_skin == null or float(_tick - barrage.last_at) / _rate >= scatter_skin.duration():
				continue
			var spots := barrage.visual_spots()
			for index: int in spots.size():
				var scatter_key := "%d:%d:%d" % [barrage.get_instance_id(), barrage.fired, index]
				if not _impacts.has(scatter_key):
					_impacts[scatter_key] = {
						"skin": scatter_skin,
						"tick": barrage.last_at,
						"spot": spots[index],
						"radius": barrage.visual_radius()
					}
			continue
		var repeated := (
			PBFieldArt.supports_forward_area(skill)
			or PBFieldArt.supports_expanding_ground_area(skill)
			or PBFieldArt.supports_self_barrage_area(skill)
		)
		if not PBFieldArt.supports_area(skill) and not repeated:
			continue
		var key: Variant = (
			"%d:%d" % [barrage.get_instance_id(), barrage.fired]
			if repeated else barrage.cast
		)
		if _impacts.has(key):
			continue
		var skin := PBFieldArt.read("areas", PBPersistentFieldArt.art_key(skill))
		if skin == null or float(_tick - barrage.last_at) / _rate >= skin.duration():
			continue
		_impacts[key] = {
			"skin": skin,
			"tick": barrage.last_at,
			"spot": barrage.visual_spot(),
			"radius": barrage.visual_radius()
		}


func _draw_cast(cast: PBSkillCast) -> void:
	if cast == null or cast.impact_tick < 0 or cast.impact_skill == null:
		return
	var skill := cast.impact_skill
	if PBFieldArt.supports_line_area(skill):
		_draw_line_cast(cast)
		return
	if (
		not PBFieldArt.supports_area(skill)
		and not PBFieldArt.supports_self_area(skill)
		and not PBFieldArt.supports_target_area(skill)
	):
		return
	var skin := PBFieldArt.read("areas", skill.id)
	if skin != null:
		PBFieldArt.draw_area(
			self,
			skin,
			PBLayout.to_screen(cast.impact_spot, _field),
			skill.radius * PBLayout.px_per_unit(_field),
			float(_tick - cast.impact_tick) / _rate
		)


func _draw_enemy_aura(actor: PBAttacker, cast: PBSkillCast) -> void:
	if (
		cast == null
		or not actor.is_targetable()
		or not PBFieldArt.supports_enemy_aura_area(cast.skill)
	):
		return
	var skin := PBFieldArt.read("areas", PBPersistentFieldArt.art_key(cast.skill))
	if skin == null:
		return
	PBFieldArt.draw_area(
		self, skin, PBLayout.to_screen(actor.pos, _field),
		cast.skill.enemy_aura_radius * PBLayout.px_per_unit(_field),
		float(_tick) / _rate, true
	)


func _draw_line_cast(cast: PBSkillCast) -> void:
	if not PBSkillCast.is_spot(cast.impact_origin):
		return
	var skin := PBFieldArt.read("areas", cast.impact_skill.id)
	if skin == null:
		return
	var age := float(_tick - cast.impact_tick) / _rate
	if age < 0.0 or age >= skin.duration():
		return
	var skill := cast.impact_skill
	var direction := PBSkillArea.heading(cast.impact_origin, cast.impact_spot)
	var projected := Vector2(direction.x, direction.y * PBLayout.Y_SCALE)
	var count := maxi(1, ceili(skill.line_length / (skill.radius * 2.5)))
	var radius := skill.radius * 2.0 * PBLayout.px_per_unit(_field)
	for index: int in count:
		var distance := skill.line_length * (float(index) + 0.5) / float(count)
		var center := PBLayout.to_screen(cast.impact_origin + direction * distance, _field)
		draw_set_transform(center, projected.angle())
		PBFieldArt.draw_area(self, skin, Vector2.ZERO, radius, age)
	draw_set_transform(Vector2.ZERO)


func _draw_attack_chain(cast: PBSkillCast) -> void:
	if cast == null or cast.trigger_tick < 0 or not PBFieldArt.supports_attack_chain_area(cast.skill):
		return
	var skin := PBFieldArt.read("areas", cast.skill.id)
	if skin == null:
		return
	var age := float(_tick - cast.trigger_tick) / _rate
	if age < 0.0 or age >= skin.duration():
		return
	var radius := cast.skill.radius * PBLayout.px_per_unit(_field)
	for index: int in cast.skill.attack_chain_count:
		var spot := (
			cast.trigger_center
			+ cast.trigger_direction * cast.skill.attack_chain_step * float(index + 1)
		)
		PBFieldArt.draw_area(
			self, skin, PBLayout.to_screen(spot, _field), radius, age
		)


func _draw_link(enemy: PBEnemy, state: PBBuffState) -> void:
	if not state.is_live(_tick):
		return
	var skin := PBFieldArt.read("links", state.buff.id)
	if skin == null:
		return
	var caster: PBAttacker = null
	if state.channel != null:
		if not state.channel.valid_now(_tick) or state.channel.caster_ref == null:
			return
		caster = state.channel.caster_ref.get_ref() as PBAttacker
	else:
		for actor: PBAttacker in _team:
			if actor.slot == state.source_slot and actor.alive:
				caster = actor
				break
	if caster == null:
		return
	var from := PBLayout.to_screen(caster.pos, _field)
	var to := PBLayout.to_screen(enemy.pos(), _field)
	if state.channel == null:
		from.y -= 34.0
		to.y -= 34.0
	PBFieldArt.draw_link(
		self,
		skin,
		from,
		to,
		float(_tick - state.applied_at) / _rate
	)


func _draw_ally_link(target: PBAttacker, state: PBBuffState) -> void:
	if not state.is_live(_tick) or state.source_slot < 0:
		return
	var skin := PBFieldArt.read("links", state.buff.id)
	if skin == null:
		return
	for caster: PBAttacker in _team:
		if caster.slot != state.source_slot or not caster.alive:
			continue
		if caster.sacrifice_at < 0 or _tick > caster.sacrifice_at:
			return
		var from := PBLayout.to_screen(caster.pos, _field) + Vector2(0, -34)
		var to := PBLayout.to_screen(target.pos, _field) + Vector2(0, -34)
		PBFieldArt.draw_link(
			self, skin, from, to, float(_tick - state.applied_at) / _rate
		)
		return


func _sync_leech_links(book: PBBattleLog) -> void:
	for i in range(_leech_links.size() - 1, -1, -1):
		var link: Dictionary = _leech_links[i]
		if float(_tick - link.tick) / _rate >= link.skin.duration():
			_leech_links.remove_at(i)
	if book == null:
		return
	for i in range(book.fresh_from(_seen_log), book.entries.size()):
		var entry: Dictionary = book.entries[i]
		if entry.get("kind", -1) != PBBattleLog.Kind.HIT_ENEMY:
			continue
		if entry.get("leech", 0.0) <= 0.0 or _tick - int(entry.tick) > 6:
			continue
		var source: PBAttacker = null
		for actor: PBAttacker in _team:
			if actor.slot == int(entry.get("source", -1)):
				source = actor
				break
		if source == null or source.lifesteal <= 0.0 or source.summon_skill_id == &"":
			continue
		var skin := PBFieldArt.read("links", source.summon_skill_id)
		if skin == null:
			continue
		for enemy: PBEnemy in _enemies:
			if enemy.slot == int(entry.get("target", -1)):
				_leech_links.append({
					"skin": skin,
					"from": PBLayout.to_screen(enemy.pos(), _field) + Vector2(0, -25),
					"to": PBLayout.to_screen(source.pos, _field) + Vector2(0, -20),
					"tick": int(entry.tick)
				})
				break
	_seen_log = book.total
