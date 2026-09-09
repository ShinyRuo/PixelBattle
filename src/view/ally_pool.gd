class_name PBAllyPool
extends Node2D
## 战场上的己方忍者。§02 第 8 点，M3.5-g；M6-b 起是一组 [AnimatedSprite2D]。
##
## ## 在它之前，战场上只有敌人
##
## M0 到 M3 的战斗是「整队一个标量 DPS」，**「谁站在哪」根本没有答案**，
## 所以画面上画不出自己人是诚实的。M3-a 把标量拆成一组 [PBAttacker]、
## M3.5 又给了他们血量和跑动之后，那个答案有了 —— 但一直没有出口，
## 于是开打之后玩家看到的还是一条只有敌人在走的空道。
##
## 那不只是难看：**射程、站位、防挤、敌人还手这四件事全部不可见**，
## 而它们正是 M3-a 到 M3.5-c 做的全部内容。看不见的系统等于不存在。
##
## ## 己方和敌人必须一眼分得开
##
## 敌人的白模是**会动的多边形**（每系一个剪影，§02 的第二层视觉编码，
## 见 [method PBWhiteModel.enemy]）。己方是**方头方脑的人形 + 头顶一条血条**：
## 形状类别不同，去色之后照样分得开，而属性色两边共用同一套
## （[constant PBEnemyPool.ELEMENT_COLORS]）—— 玩家在卡面上认的那个颜色就是这个。
##
## 血条**只有己方有**。敌人的血量已经编码进颜色明暗（越暗越残），
## 而己方只有十来个、一个死了就少一份输出，那件事值得一个精确的读数。
##
## ## 尾兽不画
##
## 尾兽是一个 `dps = 0` 的攻击者（[constant PBBeastRules.BEAST_SLOT]），
## 它没有本体、不挨打、位置恒为 0。画出来会是一个贴在基地上永远满血的方块，
## 而玩家会以为那是个忍者。

## 血条尺寸与它离**头顶**多远。头顶多高由那张皮说了算
## （[method PBActorSkin.head_px]）—— 写死一个数的话，换一套画得高一点的
## 素材，血条就埋进胸口里了。
## **跟着人物一起放大**（M6-g，1.5 倍）：一个 41 像素高的忍者配一条
## 13 像素的血条，读数会比人本身还难认。
const BAR: Vector2 = Vector2(20.0, 3.0)
const BAR_LIFT: float = 6.0

## 脚下那圈影子的横向半径与段数（M6-a）。
##
## ## 影子不是装饰，它是这个视角里唯一的高度读数
##
## 压过 y 轴之后（[constant PBLayout.Y_SCALE]）「站得远」和「站得高」
## 在屏幕上是同一个方向的位移 —— 只看小人本身分不出他是往后站了，
## 还是跳起来了。影子钉在地面点上，那个歧义就没了。
##
## 这也是它必须画在**脚底那个点**上的理由：影子的位置就是
## [member PBAttacker.pos]，而小人的身体是从那儿往上长的。
## **地面得比背景亮，影子才有地方落。** 底板原来是 `(0.11,0.12,0.16)`，
## 背景是 `(0.08,0.09,0.12)` —— 黑影子叠上去算出来和背景同一个色号，
## 画了等于没画（实测：影子在算，屏幕上一个都看不见）。M6-a 把底板提到
## `(0.17,0.18,0.22)`，那也正是「地面是一个平面」这句话的视觉前提。
const SHADOW_RX: float = 9.0
const SHADOW_SEGMENTS: int = 12
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)

## 阵亡之后染成什么样。**不藏起来** —— 藏了的话「他死了」和「他从来没上场」
## 在画面上是同一件事，而这一波剩下的时间里玩家正需要知道前排缺了一个。
const DEAD_COLOR := Color(0.22, 0.22, 0.26, 0.75)

const HP_GOOD := Color(0.44, 0.82, 0.55)
const HP_LOW := Color(0.90, 0.42, 0.42)
const BAR_BACK := Color(0.10, 0.11, 0.14, 0.85)

## 选中那个忍者的射程圈（§02 的战斗中操作，M4-e）。
##
## ## 为什么画在这里，而不是再开一个池子
##
## 它是**某一个己方单位**的属性，和血条一样跟着那个人走。
## 单开一个节点的话，「圈的位置」和「小人的位置」会各算一遍，
## 而差几个像素的表现是「射程圈好像没对准他」。
##
## 圈画在自己的 `_draw` 里 —— [CanvasItem] 先画自己再画子节点，
## 所以它自然落在小人和血条**底下**，不会盖住谁。
const RANGE_FILL := Color(0.55, 0.78, 0.95, 0.06)
const RANGE_EDGE := Color(0.62, 0.84, 0.98, 0.55)
const RANGE_SEGMENTS: int = 32

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
var _anchors: Array[Node2D] = []

var _sprites: Array[AnimatedSprite2D] = []
var _backs: Array[ColorRect] = []
var _fills: Array[ColorRect] = []

## 每人一份动画状态（M6-b）。它记的是**上一帧**的位置与出手时刻，
## sim 里没有这两样的差分，见 [PBActorPose]。
var _poses: Array[PBActorPose] = []

## 这一格现在挂着哪张皮。换人才重装 [SpriteFrames] —— 每帧重装的话
## 动画会永远停在第一帧，而那看起来就像「这个人不会动」。
var _skins: Array[PBActorSkin] = []

## 射程圈的屏幕圆心与半径。半径 0 = 不画。
var _range_at: Vector2 = Vector2.ZERO
var _range_px: float = 0.0

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
	for _i: int in cfg.deploy_slots_max:
		var anchor := Node2D.new()
		add_child(anchor)
		_anchors.append(anchor)
		var sprite := AnimatedSprite2D.new()
		# **不居中**：原点要落在脚底，偏移由那张皮给（[method PBActorSkin.draw_offset]）。
		sprite.centered = false
		sprite.visible = false
		anchor.add_child(sprite)
		_sprites.append(sprite)
		_backs.append(_add_rect(anchor, BAR, BAR_BACK))
		_fills.append(_add_rect(anchor, BAR, HP_GOOD))
		_poses.append(PBActorPose.new())
		_skins.append(null)


## 倍速（暂停和顿帧给 0）。M6-b。
##
## **必须跟着走**：动画自己按墙上时间播，倍速时人物会比战斗慢一半，
## 而暂停时一群人还在原地跑步 —— §02 特意允许暂停下操作，
## 那一刻画面必须是静止的局面，不是一段循环播放的舞蹈。
func set_anim_speed(scale: float) -> void:
	_anim_speed = maxf(scale, 0.0)


## 把池子同步到这一波的攻击者上。每渲染帧调一次。
##
## [param units] 是与攻击者同序的上场名单（[member PBWavePlan.deployed]），
## 用来取属性色和那张皮 —— [PBAttacker] 身上没有「攻元素」，那一份克制倍率
## 在建攻击者时就乘进 `dps` 了（§14 铁律 4：element 挂在伤害事件上）。
## [param enemies] 只用来查**他要打的那个在哪**（朝向），见
## [member PBAttacker.aim_at]。
##
## **位置直接读 [member PBAttacker.pos]**（M4-a）。在那之前 y 是这里
## 按显示序号现编的 —— sim 是一维的，纵向没有答案可读。
func sync_allies(
	attackers: Array[PBAttacker],
	units: Array[PBUnit],
	field: Vector2,
	enemies: Array[PBEnemy],
	current_tick: int = 0
) -> void:
	var shown: int = 0
	var feet := PackedVector2Array()
	for attacker: PBAttacker in attackers:
		if shown >= _sprites.size():
			break
		# 尾兽那一个不画，见类顶部。
		if attacker.slot < 0 or attacker.max_hp <= 0.0:
			continue
		var at := PBLayout.to_screen(attacker.pos, field)
		var unit: PBUnit = units[attacker.slot] if attacker.slot < units.size() else null
		_place(
			shown,
			at,
			attacker,
			unit,
			_look_x(attacker, enemies),
			current_tick,
			_in_range(attacker, enemies)
		)
		# 死人不留影子 —— 人已经躺下了，一个还站在地上的影子会让人
		# 以为他还在那儿挡着。
		if attacker.alive:
			feet.append(at)
		shown += 1
	for i: int in range(shown, _sprites.size()):
		_hide(i)
	_set_shadows(feet)


## 准备阶段把上场名单画在他们的开战位置上（§02，M4-f）。
##
## ## 为什么准备阶段也要画
##
## 在它之前准备阶段的战场是**空的**，上场名单只在屏幕上方那一排头像里 ——
## 于是「谁站前排」这件事只能从射程档反推。摆位要成为一个操作，
## 第一步是让玩家看见现在摆成什么样。
##
## 不画血条：还没开打，那条永远是满的，而一条恒满的血条只是噪声。
func sync_placed(units: Array[PBUnit], spots: Array[Vector2], field: Vector2) -> void:
	var feet := PackedVector2Array()
	for i: int in _sprites.size():
		var shown: bool = i < units.size() and i < spots.size()
		if not shown:
			_hide(i)
			continue
		var at := PBLayout.to_screen(spots[i], field)
		_anchors[i].position = at
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
	for i: int in _sprites.size():
		_hide(i)
		# 上一波的位置与出手时刻一起丢掉：留着的话下一波第一帧会
		# 从一个隔了半个战场的「上一帧」算出一次跑动。
		_poses[i].reset(Vector2.INF, PBActorPose.FACE_RIGHT)
	_set_shadows(PackedVector2Array())
	show_range(Vector2.ZERO, 0.0)


## 把射程圈画在 [param at]（屏幕坐标），半径 [param radius_px] 像素。
## 半径给 0 就是收起来。
func show_range(at: Vector2, radius_px: float) -> void:
	if _range_at == at and is_equal_approx(_range_px, radius_px):
		return
	_range_at = at
	_range_px = radius_px
	queue_redraw()


## 射程圈 + 每个人脚下的影子。
##
## **两样都画在这里而不是各自的精灵上**：本节点的位置恒为 (0,0)，
## 而它装在一个 y 排序的层里（[PBLayout] 的 `Actors`）——
## 于是它自己画的东西一律排在**全部单位后面**，敌我都盖不掉。
## 影子和射程圈都是贴在地面上的东西，那正是它们该在的位置。
func _draw() -> void:
	for at: Vector2 in _shadows:
		draw_colored_polygon(PBLayout.ground_disc(at, SHADOW_RX, SHADOW_SEGMENTS), SHADOW_COLOR)
	if _range_px <= 0.0:
		return
	# 战场上的圆在屏幕上是椭圆（M6-a）—— y 被压过，见 [constant PBLayout.Y_SCALE]。
	var ring := PBLayout.ground_disc(_range_at, _range_px, RANGE_SEGMENTS)
	draw_colored_polygon(ring, RANGE_FILL)
	draw_polyline(ring, RANGE_EDGE, 1.0)


## 影子换了才重画。位置每帧都在动，所以这道门平时拦不住多少 ——
## 它真正管用的是**暂停**和准备阶段：那时一帧都不用重绘。
func _set_shadows(feet: PackedVector2Array) -> void:
	if _shadows == feet:
		return
	_shadows = feet
	queue_redraw()


## [param at] 是**落脚点**，不是中心（M6-a）。精灵的脚底贴在那个点上。
##
## ## 为什么锚点必须是脚
##
## y 排序按节点的 y 排（`Actors` 层），而「谁在前面」问的是**谁的脚更靠下**。
## 按中心锚的话，一个高个子和一个矮个子站在同一条线上会排出先后，
## 而他们其实并排站着。真精灵进来之后这条更硬：素材高度各不相同，
## 中心锚会让同一排人前后乱跳。
func _place(
	index: int,
	at: Vector2,
	attacker: PBAttacker,
	unit: PBUnit,
	look_x: float,
	current_tick: int,
	in_range: bool
) -> void:
	_anchors[index].position = at
	var skin := _dress(index, unit)
	var sprite: AnimatedSprite2D = _sprites[index]
	sprite.visible = true

	# **每一格都要问**（M7-e/f）：只看大招那一格的话，玩家手放的技能
	# 一整段施法期间人是站着不动的，而那半秒正是 §02 的预判窗口。
	var cast := _pending_cast(attacker)
	var hold: int = _hold_frames(attacker.attack_interval())
	var pose: PBActorPose = _poses[index]
	pose.update(
		attacker.pos,
		attacker.alive,
		attacker.next_shot_at,
		cast != null,
		look_x,
		hold,
		in_range,
		attacker.swinging,
		PBActorPose.windup_frames(attacker.windup_ticks, _frames_per_tick)
	)

	var fit: float = 1.0
	var anim: StringName = skin.anim_for(pose.state)
	if pose.state == PBActorPose.State.ATTACK:
		fit = _fit(skin, anim, attacker.attack_interval())
	elif pose.state == PBActorPose.State.CAST and cast != null and cast.skill.id != &"":
		# 逐角色的忍术动画（[member PBActorSkin.skill_anims]）。这张表
		# M6-b 就建好了，但在 [member PBSkill.id] 之前**没有键可查** ——
		# §09 的功能档与 §11 的尾兽大招共用一套实现，区别只在这张表里。
		anim = skin.skill_anim(cast.skill.id)
	_animate(index, skin, anim, fit, PBActorPose.holds_last(pose.state), pose.swing_began)

	if not attacker.alive:
		sprite.modulate = DEAD_COLOR
	else:
		var base: Color = Color.WHITE if unit == null else _tint(skin, unit.element)
		sprite.modulate = PBBuffStrip.tinted(base, attacker.buffs, current_tick)

	# 死了不画血条 —— 一条空血条和一条读不出来的血条长得一样，
	# 而人已经躺下并压暗了，那一格信息不需要说两遍。
	_backs[index].visible = attacker.alive
	_fills[index].visible = attacker.alive
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
func _dress(index: int, unit: PBUnit) -> PBActorSkin:
	var skin: PBActorSkin = null
	if unit != null:
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


## 播这一段。**同一段不重播** —— 每帧重播会把动画钉死在第一帧，
## 而那看起来就是「这个人不会动」。
## 有没有一发在路上，有的话是哪一格（M7-e）。没有就返回 null。
##
## 先到先得：同一 tick 里两发都在飞时播前一格那一段 —— 一个人身上
## 只有一副骨架，而「同时播两段」不是一个能表达的东西。
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
	# **一次新挥击从第 0 帧起跑**（M9-e，见 [member PBActorPose.swing_began]）。
	# 光调 `play` 没用：它对已经在播的同一段什么都不做，而攻击状态在交战期间
	# 是连着的 —— 不拨回去的话动画按自己的周期自由循环，出手落在第几帧全看运气。
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
	_sprites[index].visible = false
	_backs[index].visible = false
	_fills[index].visible = false


## 造一条血条。**一律 `MOUSE_FILTER_IGNORE`**（M5-10）。
##
## [ColorRect] 默认是 `MOUSE_FILTER_STOP`，而**引擎只要在鼠标下面找到
## 任何一个非 IGNORE 的 [Control]，那一下点击就算被 GUI 处理掉了** ——
## `_unhandled_input` 收不到，于是「点战场上的忍者」整条路是死的。
##
## 最坑的是它长什么样：**点在忍者身上没反应，点在他旁边也没反应**
## （底下还压着 `Lane` 和 `Background` 两块同样默认 STOP 的 [ColorRect]）。
## 看起来像「点选功能没做」，而代码里那一整套判定写得好好的。
##
## M6-b 之后本体是 [AnimatedSprite2D]（[Node2D]，压根不参与 GUI 命中），
## 这条只剩血条这两块还需要，但**规矩不变** —— 下一个往锚上挂
## [Control] 的人会踩同一个坑。
func _add_rect(anchor: Node2D, of_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = of_size
	rect.color = color
	rect.visible = false
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(rect)
	return rect
