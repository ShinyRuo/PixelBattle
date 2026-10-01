class_name PBAllyPool
extends Node2D
## 战场上的己方忍者（§02）。一组 [AnimatedSprite2D]。射程、站位、防挤、敌人还手都靠它才看得见。
##
## **己方和敌人一眼分得开**：敌人的白模是会动的多边形，己方是人形 + 头顶血条，去色之后照样分得开；
## 属性色两边共用一套（[constant PBEnemyPool.ELEMENT_COLORS]）。
## **血条只有己方有**：己方只有十来个，死一个就少一份输出，值得一个精确读数。
## **尾兽不画**：它是没有本体、位置恒为 0 的攻击者（[constant PBBeastRules.BEAST_SLOT]），画出来像基地上站着一个人。

## 血条尺寸与它离**头顶**多远。头顶多高由那张皮说了算（[method PBActorSkin.head_px]），
## 写死一个数的话换一套高一点的素材血条就埋进胸口里了。
const BAR: Vector2 = Vector2(20.0, 3.0)
const BAR_LIFT: float = 6.0

## 脚下那圈影子的横向半径与段数。
##
## **影子是这个视角里唯一的高度读数**：压过 y 轴之后「站得远」和「站得高」是同一个方向的位移，
## 影子钉在地面点（[member PBAttacker.pos]）上，歧义就没了。
## 地面底板必须比背景亮，影子才有地方落（否则黑影叠上去和背景同一个色号）。
const SHADOW_RX: float = 9.0
const SHADOW_SEGMENTS: int = 12
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)

## 阵亡之后染成什么样。**不藏起来** —— 藏了的话「他死了」和「他从来没上场」
## 在画面上是同一件事，而这一波剩下的时间里玩家正需要知道前排缺了一个。
const DEAD_COLOR := Color(0.22, 0.22, 0.26, 0.75)

const HP_GOOD := Color(0.44, 0.82, 0.55)
const HP_LOW := Color(0.90, 0.42, 0.42)
const BAR_BACK := Color(0.10, 0.11, 0.14, 0.85)

## 攻击段最多快/慢到什么程度（[method _fit]）。不夹的话，一个攻速 0.85 的
## 角色会得到一段慢到看不出在动的挥击，而攻速 4 的那个会糊成一片。
const FIT_MIN: float = 0.2
const FIT_MAX: float = 3.0

## 每人一个锚节点，**位置就是他的落脚点**。精灵和血条挂在它下面。
##
## ## 为什么要多这一层
##
## y 排序按**节点自己的 y** 排，而精灵的原点由素材的画布决定 ——
## 直接拿精灵当节点的话，排序用的是「画布左上角在哪」而不是「脚踩在哪」，
## 而画布留白多一点的那套素材会整体排错一档，**坐标却完全正确**。
##
## 锚在脚下之后，敌我共用同一把尺子，素材高矮不一也不会打乱前后。
var _remains := PBSummonRemains.new()
var _occupants: Array[String] = []

var _anchors: Array[Node2D] = []

var _sprites: Array[AnimatedSprite2D] = []
var _backs: Array[ColorRect] = []
var _fills: Array[ColorRect] = []

## 每人一份动画状态，记的是**上一帧**的位置与出手时刻（sim 里没有差分，见 [PBActorPose]）。
var _poses: Array[PBActorPose] = []

## 这一格现在挂着哪张皮。换人才重装 [SpriteFrames] —— 每帧重装的话
## 动画会永远停在第一帧，而那看起来就像「这个人不会动」。
var _skins: Array[PBActorSkin] = []
var _glow_backs: Array[PBBuffGlow] = []
var _glow_fronts: Array[PBBuffGlow] = []
var _instant_backs: Array[PBBuffGlow] = []
var _instant_fronts: Array[PBBuffGlow] = []
var _spawn_fronts: Array[PBBuffGlow] = []
var _spawn_ticks: Array[int] = []
var _spawn_keys: Array[StringName] = []
var _cast_backs: Array[PBCastGlow] = []
var _cast_fronts: Array[PBCastGlow] = []

## 这一帧每个人的落脚点（屏幕坐标），影子画在这些点上。
var _shadows: PackedVector2Array = PackedVector2Array()

## 播放速度（倍速；暂停与顿帧时是 0）。见 [method set_anim_speed]。
var _anim_speed: float = 1.0

var _tick_rate: int = 20
var _frames_per_tick: float = 3.0


func _ready() -> void:
	# 按出战席上限一次建满，之后只改属性和 visible —— 和敌人池同一条规矩（§14）。
	#
	# **一个人的三块（精灵 + 血条底 + 血条）挂在同一个锚下**，一起前后移动。
	# 分三个池子平铺的话，y 排序会把血条和它的主人拆开排。
	var cfg := PBSimConfig.new()
	_tick_rate = maxi(cfg.tick_rate, 1)
	_frames_per_tick = maxf(float(Engine.physics_ticks_per_second) / float(_tick_rate), 1.0)
	_ensure_capacity(cfg.deploy_slots_max)


func _ensure_capacity(want: int) -> void:
	_remains.ensure_capacity(want, self)
	while _sprites.size() < want:
		var anchor := Node2D.new()
		add_child(anchor)
		_anchors.append(anchor)
		var glow_back := PBBuffGlow.new()
		anchor.add_child(glow_back)
		_glow_backs.append(glow_back)
		var instant_back := PBBuffGlow.new()
		anchor.add_child(instant_back)
		_instant_backs.append(instant_back)
		var cast_back := PBCastGlow.new()
		anchor.add_child(cast_back)
		_cast_backs.append(cast_back)
		var sprite := AnimatedSprite2D.new()
		# **不居中**：原点要落在脚底，偏移由那张皮给（[method PBActorSkin.draw_offset]）。
		sprite.centered = false
		sprite.visible = false
		anchor.add_child(sprite)
		_sprites.append(sprite)
		var glow_front := PBBuffGlow.new()
		glow_front.front = true
		anchor.add_child(glow_front)
		_glow_fronts.append(glow_front)
		var instant_front := PBBuffGlow.new()
		instant_front.front = true
		anchor.add_child(instant_front)
		_instant_fronts.append(instant_front)
		var spawn_front := PBBuffGlow.new()
		spawn_front.front = true
		anchor.add_child(spawn_front)
		_spawn_fronts.append(spawn_front)
		_spawn_ticks.append(-1)
		_spawn_keys.append(&"")
		var cast_front := PBCastGlow.new()
		cast_front.front = true
		anchor.add_child(cast_front)
		_cast_fronts.append(cast_front)
		_backs.append(_add_rect(anchor, BAR, BAR_BACK))
		_fills.append(_add_rect(anchor, BAR, HP_GOOD))
		_poses.append(PBActorPose.new())
		_skins.append(null)
		_occupants.append("")


## 倍速（暂停和顿帧给 0）。**必须跟着走**：否则暂停时一群人还在原地跑步，而暂停时画面必须是静止的局面。
func set_anim_speed(scale: float) -> void:
	_anim_speed = maxf(scale, 0.0)


## 把池子同步到这一波的攻击者上。每渲染帧调一次。**位置直接读 [member PBAttacker.pos]。**
##
## [param units] 是与攻击者同序的上场名单，用来取属性色和那张皮（[PBAttacker] 身上没有攻元素）。
## [param enemies] 只用来查他要打的那个在哪（朝向），见 [member PBAttacker.aim_at]。
func sync_allies(
	attackers: Array[PBAttacker],
	units: Array[PBUnit],
	field: Vector2,
	enemies: Array[PBEnemy],
	current_tick: int = 0,
	bond_auras: Dictionary = {}
) -> void:
	_ensure_capacity(attackers.size())
	_remains._tick_rate = _tick_rate
	_remains.sync(attackers, current_tick, field)
	var shown: int = 0
	var feet := PackedVector2Array()
	for attacker: PBAttacker in attackers:
		if attacker.summoned and (attacker.expires_at == PBSummonRules.GONE or not attacker.alive):
			continue
		if shown >= _sprites.size():
			break
		# 尾兽那一个不画，见类顶部。
		if attacker.slot < 0 or attacker.max_hp <= 0.0:
			continue
		var at := PBLayout.to_screen(attacker.pos, field)
		var look_slot: int = attacker.appearance_slot if attacker.phantom else attacker.slot
		var unit: PBUnit = units[look_slot] if look_slot >= 0 and look_slot < units.size() else null
		_place(
			shown,
			at,
			attacker,
			unit,
			_look_x(attacker, enemies),
			current_tick,
			_in_range(attacker, enemies),
			attackers,
			bond_auras
		)
		# 死人不留影子 —— 人已经躺下了，一个还站在地上的影子会让人
		# 以为他还在那儿挡着。
		if attacker.alive:
			feet.append(at)
		shown += 1
	for i: int in range(shown, _sprites.size()):
		_hide(i)
	_set_shadows(feet)


## 准备阶段把上场名单画在他们的开战位置上（§02）。摆位要成为一个操作，第一步是让玩家看见现在摆成什么样。
## 不画血条：还没开打，恒满的血条只是噪声。
func sync_placed(units: Array[PBUnit], spots: Array[Vector2], field: Vector2) -> void:
	var feet := PackedVector2Array()
	for i: int in _sprites.size():
		var shown: bool = i < units.size() and i < spots.size()
		if not shown:
			_hide(i)
			continue
		var at := PBLayout.to_screen(spots[i], field)
		_anchors[i].position = at
		_glow_backs[i].clear()
		_glow_fronts[i].clear()
		_instant_backs[i].clear()
		_instant_fronts[i].clear()
		_spawn_fronts[i].clear()
		_cast_backs[i].clear()
		_cast_fronts[i].clear()
		var skin := _dress(i, units[i])
		var sprite: AnimatedSprite2D = _sprites[i]
		sprite.visible = true
		sprite.modulate = _tint(skin, units[i].element)
		# 站着等开打：一律待机、一律朝着敌人来的那一侧。
		_poses[i].reset(spots[i], PBActorPose.FACE_RIGHT)
		_animate(i, skin, skin.anim_for(PBActorPose.State.IDLE), 1.0)
		_backs[i].visible = false
		_fills[i].visible = false
		feet.append(at)
	_set_shadows(feet)


## 一个都不画（本局结束之后没有战场）。
func clear() -> void:
	_remains.clear()
	for i: int in _sprites.size():
		_hide(i)
		# 上一波的位置与出手时刻一起丢掉：留着的话下一波第一帧会
		# 从一个隔了半个战场的「上一帧」算出一次跑动。
		_poses[i].reset(Vector2.INF, PBActorPose.FACE_RIGHT)
	_set_shadows(PackedVector2Array())


## 影子画在地面层；射程圈另经裁切层绘制，避免远程大圈盖住任务栏和顶部文字。
func _draw() -> void:
	for at: Vector2 in _shadows:
		draw_colored_polygon(PBLayout.ground_disc(at, SHADOW_RX, SHADOW_SEGMENTS), SHADOW_COLOR)


## 影子换了才重画。位置每帧都在动，所以这道门平时拦不住多少 ——
## 它真正管用的是**暂停**和准备阶段：那时一帧都不用重绘。
func _set_shadows(feet: PackedVector2Array) -> void:
	if _shadows == feet:
		return
	_shadows = feet
	queue_redraw()


## [param at] 是**落脚点**，不是中心，精灵的脚底贴在那个点上。
## y 排序问的是**谁的脚更靠下**；按中心锚的话高矮不同的人站在同一条线上会排出先后。
func _aura_ids(
	unit: PBAttacker, team: Array[PBAttacker], card: PBUnit = null, bond_auras: Dictionary = {}
) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not unit.is_targetable():
		return ids
	for source: PBAttacker in team:
		if not source.is_targetable():
			continue
		for cast: PBSkillCast in source.skills:
			var skill := cast.skill
			if source == unit:
				var source_art := StringName("%s_source" % skill.id)
				if PBBuffGlow.skin_for(source_art) != null and not ids.has(source_art):
					ids.append(source_art)
			var covered := PBHealingAuraRules.covers(source, unit, skill)
			if PBMotionAuraRules.enabled(skill):
				covered = (
					covered
					or source == unit
					or (
						skill.radius > 0.0
						and source.pos.distance_to(unit.pos) <= skill.radius + 0.0000001
					)
				)
			if skill.ranged_attack_aura > 0.0 and unit.ranged_attack:
				covered = covered or source.pos.distance_to(unit.pos) <= skill.radius + 0.0000001
			if covered:
				var id := StringName("%s_aura" % skill.id)
				if not ids.has(id):
					ids.append(id)
	if card != null and not unit.summoned:
		for id: StringName in bond_auras.get(card.character.id, []):
			if not ids.has(id):
				ids.append(id)
	return ids


func _place(
	index: int,
	at: Vector2,
	attacker: PBAttacker,
	unit: PBUnit,
	look_x: float,
	current_tick: int,
	in_range: bool,
	team: Array[PBAttacker],
	bond_auras: Dictionary
) -> void:
	var occupant := "%s:%s" % [attacker.get_instance_id(), attacker.summon_serial]
	if _occupants[index] != occupant:
		_occupants[index] = occupant
		_spawn_ticks[index] = current_tick
		_spawn_keys[index] = (
			PBSummonArt.for_skill(attacker.summon_skill_id).spawn_fx_key
			if attacker.summoned else &""
		)
		_poses[index].reset(attacker.pos, PBActorPose.FACE_RIGHT)
		_sprites[index].stop()
	_anchors[index].position = at
	var auras := _aura_ids(attacker, team, unit, bond_auras)
	_glow_backs[index].sync_bag(attacker.buffs, current_tick, _tick_rate, attacker.alive, auras)
	_glow_fronts[index].sync_bag(attacker.buffs, current_tick, _tick_rate, attacker.alive, auras)
	var instant_age: int = current_tick - attacker.instant_fx_tick
	_instant_backs[index].sync_instant(
		attacker.instant_fx_id, instant_age, _tick_rate, attacker.alive
	)
	_instant_fronts[index].sync_instant(
		attacker.instant_fx_id, instant_age, _tick_rate, attacker.alive
	)
	_spawn_fronts[index].sync_instant(
		_spawn_keys[index], current_tick - _spawn_ticks[index], _tick_rate, attacker.alive
	)
	_cast_backs[index].sync_cast(attacker, current_tick, _tick_rate)
	_cast_fronts[index].sync_cast(attacker, current_tick, _tick_rate)
	var skin := _dress(
		index, unit, attacker.summon_skill_id if attacker.summoned else &"",
		_form_actor_key(attacker, current_tick)
	)
	var sprite: AnimatedSprite2D = _sprites[index]
	sprite.visible = true

	# **每一格都要问**：只看大招那一格的话，玩家手放的技能整段施法期间人站着不动。
	var casting := attacker.casting
	var hold: int = _hold_frames(attacker.attack_interval())
	var pose: PBActorPose = _poses[index]
	var departing: bool = attacker.death_move_until > current_tick
	pose.update(
		attacker.pos,
		attacker.alive or departing,
		attacker.next_shot_at,
		casting.active(current_tick) and not departing,
		look_x,
		hold,
		in_range,
		attacker.swinging and not departing,
		PBActorPose.windup_frames(PBMotionAuraRules.windup_ticks(attacker), _frames_per_tick),
		current_tick < attacker.attack_ends_at and not departing
	)

	var fit: float = 1.0
	var anim: StringName = skin.anim_for(pose.state)
	if pose.state == PBActorPose.State.ATTACK:
		fit = _fit(skin, anim, attacker.attack_interval())
	elif pose.state == PBActorPose.State.CAST:
		# 逐角色的忍术动画（[member PBActorSkin.skill_anims]），按 [member PBSkill.id] 查。
		anim = skin.skill_anim(casting.skill_id)
	_animate(index, skin, anim, fit, PBActorPose.holds_last(pose.state), pose.swing_began)
	if pose.state == PBActorPose.State.CAST:
		sprite.pause()
		var count := skin.frames.get_frame_count(anim)
		sprite.frame = mini(int(casting.frame_at(current_tick) * count / 6.0), count - 1)

	if not attacker.alive and not departing:
		sprite.modulate = DEAD_COLOR
	else:
		var base: Color = Color.WHITE if unit == null else _tint(skin, unit.element)
		sprite.modulate = PBBuffStrip.tinted(base, attacker.buffs, current_tick)
		if attacker.phantom:
			sprite.modulate = Color(0.65, 0.9, 1.0, 0.45)

	_remains.remember(attacker, sprite, skin)

	# 死了不画血条 —— 一条空血条和一条读不出来的血条长得一样，
	# 而人已经躺下并压暗了，那一格信息不需要说两遍。
	_backs[index].visible = attacker.alive and not attacker.phantom
	_fills[index].visible = attacker.alive and not attacker.phantom
	if not attacker.alive:
		return
	var lift: float = skin.head_px() + BAR_LIFT
	var bar_at := -Vector2(BAR.x * 0.5, lift)
	_backs[index].position = bar_at
	_fills[index].position = bar_at
	var ratio: float = clampf(attacker.hp / attacker.max_hp, 0.0, 1.0)
	_fills[index].size = Vector2(BAR.x * ratio, BAR.y)
	_fills[index].color = HP_LOW if ratio < 0.35 else HP_GOOD


## 他要看着谁。有点名/有目标就看那个敌人（[member PBAttacker.aim_at]），
## 否则交给 [PBActorPose] 按移动方向决定。
##
## **终点直接读 sim 算好的那一个，不在这里重算** —— 和 [PBAimLines]
## 那条绿线同一个理由：点名、射程、出场时刻、死活四个条件漏抄一个，
## 人就背对着他正在打的敌人，而且不报错。
## 他这一刻够不够得着他要打的那个（[member PBAttacker.aim_at]）。
##
## **这是「在打还是在走」的判据**，见 [method PBActorPose.update] 的
## `in_range` 那段。读的是 sim 已经算好的结论，不在渲染层拿位移大小去猜 ——
## 猜的话防挤的抖动（一 tick 0.006）和真走路（0.0083）分不开。
##
## 没有目标就是「够不着」：那时他要么在往前压、要么在回家，两样都不是打。
func _in_range(attacker: PBAttacker, enemies: Array[PBEnemy]) -> bool:
	if attacker.aim_at < 0 or attacker.aim_at >= enemies.size():
		return false
	return attacker.can_reach(enemies[attacker.aim_at].pos())


func _look_x(attacker: PBAttacker, enemies: Array[PBEnemy]) -> float:
	if attacker.aim_at < 0 or attacker.aim_at >= enemies.size():
		return NAN
	return enemies[attacker.aim_at].distance


## 这一格该挂哪张皮。**没配就用白模** —— `assets/` 现在一个素材都没有，
## 所以今天走的全是这一条，见 [PBWhiteModel]。
func _dress(
	index: int, unit: PBUnit, summon_id: StringName = &"", form_key: StringName = &""
) -> PBActorSkin:
	var skin := PBActorLibrary.skin_for(PBSummonArt.for_skill(summon_id).actor_key)
	if skin == null:
		skin = PBActorLibrary.skin_for(form_key)
	if skin == null and unit != null:
		skin = PBActorLibrary.skin_for(unit.character.actor_key)
	if skin == null:
		skin = PBWhiteModel.ally()
	if _skins[index] != skin:
		_skins[index] = skin
		var sprite: AnimatedSprite2D = _sprites[index]
		sprite.sprite_frames = skin.frames
		sprite.offset = skin.draw_offset()
		sprite.scale = Vector2.ONE * skin.pixel_scale
		sprite.texture_filter = skin.filter_mode()
	return skin


func _form_actor_key(attacker: PBAttacker, current_tick: int) -> StringName:
	if attacker.summoned:
		return &""
	for state: PBBuffState in attacker.buffs.states():
		if state.is_live(current_tick):
			var art := PBFormArt.for_buff(state.buff.id)
			if art.actor_key != &"":
				return art.actor_key
	for cast: PBSkillCast in attacker.skills:
		if cast.skill != null and cast.skill.variant_art_id != &"":
			var art := PBFormArt.for_buff(cast.skill.variant_art_id)
			if art.actor_key != &"":
				return art.actor_key
	return &""


## 有没有一发在路上，有的话是哪一格。没有就返回 null。
## 先到先得：同一 tick 两发都在飞时播前一格那一段（一个人只有一副骨架）。
static func _pending_cast(attacker: PBAttacker) -> PBSkillCast:
	for i: int in PBSkillRules.cast_count(attacker):
		var cast := PBSkillRules.cast_at(attacker, i)
		if cast != null and cast.is_pending():
			return cast
	return null


## 播这一段。[param hold_last] 为真时**演完就停在最后一帧**，见
## [method PBActorPose.holds_last]。
##
## 三种情况要分开：换了一段就从头播；同一段还在演就别碰它（每帧调一次
## `play` 会把它钉死在第一帧，那看起来就是「这个人不会动」）；
## 同一段已经演完，那要么再来一遍（攻击段每出一手一遍），要么就停在那儿。
## 播这一段。**同一段不重播** —— 每帧重播会把动画钉死在第一帧，看起来就是「这个人不会动」。
func _animate(
	index: int,
	skin: PBActorSkin,
	anim: StringName,
	fit: float,
	hold_last: bool = false,
	restart: bool = false
) -> void:
	var sprite: AnimatedSprite2D = _sprites[index]
	var over: bool = not sprite.is_playing()
	if sprite.animation != anim or (over and not hold_last):
		sprite.play(anim)
	# **一次新挥击从第 0 帧起跑**（见 [member PBActorPose.swing_began]）：`play` 对已经在播的同一段什么都不做，
	# 不拨回去的话出手落在第几帧全看运气。
	if restart and sprite.animation == anim:
		sprite.set_frame_and_progress(0, 0.0)
	sprite.speed_scale = _anim_speed * fit
	# **和敌人同一把尺子**（[method PBActorSkin.flips_for]）。
	sprite.flip_h = skin.flips_for(_poses[index].facing)


## 白模按属性染色，真素材不染（[member PBActorSkin.tint_by_element]）。
func _tint(skin: PBActorSkin, element: PBElement.Type) -> Color:
	if not skin.tint_by_element:
		return Color.WHITE
	return PBEnemyPool.ELEMENT_COLORS.get(element, Color.WHITE)


## 攻击段该占几帧。**由攻击间隔换算**，不是一个写死的数：
## 攻速 0.85 和攻速 4 差五倍，写死的话一边拖到下一发还没播完，
## 另一边播完之后干站着大半个间隔。
func _hold_frames(interval_ticks: int) -> int:
	return maxi(roundi(float(maxi(interval_ticks, 1)) * _frames_per_tick), 2)


## 攻击段要放慢/加快几倍才正好占满一个攻击间隔。
##
## 素材的帧率是美术定的（一段挥击 0.25 秒），而这个角色的出手间隔是数值定的 ——
## 两者没有理由相等，所以这里现算一个缩放。夹在
## [constant FIT_MIN] 到 [constant FIT_MAX] 之间，见那两个常量。
func _fit(skin: PBActorSkin, anim: StringName, interval_ticks: int) -> float:
	var want: float = float(maxi(interval_ticks, 1)) / float(_tick_rate)
	var have: float = skin.anim_seconds(anim)
	if have <= 0.0 or want <= 0.0:
		return 1.0
	return clampf(have / want, FIT_MIN, FIT_MAX)


func _hide(index: int) -> void:
	_occupants[index] = ""
	_spawn_keys[index] = &""
	_spawn_ticks[index] = -1
	_glow_backs[index].clear()
	_glow_fronts[index].clear()
	_instant_backs[index].clear()
	_instant_fronts[index].clear()
	_spawn_fronts[index].clear()
	_cast_backs[index].clear()
	_cast_fronts[index].clear()
	_sprites[index].visible = false
	_backs[index].visible = false
	_fills[index].visible = false


## 造一条血条。**一律 `MOUSE_FILTER_IGNORE`**：[ColorRect] 默认 STOP，引擎只要在鼠标下找到任何一个
## 非 IGNORE 的 [Control]，那一下点击就算被 GUI 处理掉了，`_unhandled_input` 收不到 ——
## 表现是「点战场上的忍者没反应」，而判定代码写得好好的。下一个往锚上挂 [Control] 的人会踩同一个坑。
func _add_rect(anchor: Node2D, of_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = of_size
	rect.color = color
	rect.visible = false
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(rect)
	return rect
