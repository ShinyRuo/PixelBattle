class_name PBEnemyPool
extends Node2D
## 敌人节点的对象池。§14 要求战斗中零新建 —— 节点的创建/销毁在
## 48 单位 × 20 tick/s 的规模下是实打实的开销，而且会造成帧时间抖动。
##
## 池子在 `_ready()` 一次性建满 `COUNT_CAP` 个，之后只改属性和 `visible`。
##
## ## 属性的视觉编码（§02）
##
## `640×360` 下一个敌人只有十来个像素，头顶挂图标根本看不清，所以属性必须
## **编码进精灵本身**。§02 要求三层：
##
## 1. **主色调** —— 五系各占一个明确色相
## 2. **轮廓形状** —— 每系一个可辨识的剪影。**不能只靠颜色**：
##    色觉障碍 + 缩放后色彩失真，两条都会让纯色方案失效
## 3. **描边高亮** —— 可被当前阵容克制的敌人脚下点一圈白
##
## §02 的验收项是「去色后仍能仅凭剪影区分五系」，所以形状不是装饰。
## M6-b 把静态多边形换成了**会动的多边形**（[method PBWhiteModel.enemy]）：
## 剪影一个顶点都没变，但待机、行军、出手三段从此分得出来。

## 五系 + 物理的主色调。§02 指定的色相。
const ELEMENT_COLORS := {
	PBElement.Type.FIRE: Color(0.90, 0.35, 0.20),
	PBElement.Type.WIND: Color(0.25, 0.80, 0.55),
	PBElement.Type.THUNDER: Color(0.95, 0.85, 0.25),
	PBElement.Type.EARTH: Color(0.60, 0.45, 0.25),
	PBElement.Type.WATER: Color(0.30, 0.55, 0.95),
	PBElement.Type.PHYSICAL: Color(0.70, 0.70, 0.72),
}

## 每系的边数，用来生成可区分的剪影。物理用 8 边（接近圆）。
## 去色之后靠的就是这个 —— 三角、方、五边、六边、菱形一眼能分开。
const ELEMENT_SIDES := {
	PBElement.Type.FIRE: 3,
	PBElement.Type.WIND: 5,
	PBElement.Type.THUNDER: 4,
	PBElement.Type.EARTH: 6,
	PBElement.Type.WATER: 7,
	PBElement.Type.PHYSICAL: 8,
}

## 每系在皮键里的名字。真素材进来时去 `data/actors/` 里查（M6-b）。
##
## 敌人没有 [PBCharacter]，所以借不到 [member PBCharacter.actor_key] 那条路 ——
## 但换皮的入口必须和己方是同一个（[PBActorLibrary]），
## 否则「敌人的形象」会长出第二套加载规则，而两套迟早在朝向或脚底上分叉。
## **查不到就退回白模**，也就是今天走的那一条。
const ELEMENT_NAMES := {
	PBElement.Type.FIRE: "fire",
	PBElement.Type.WIND: "wind",
	PBElement.Type.THUNDER: "thunder",
	PBElement.Type.EARTH: "earth",
	PBElement.Type.WATER: "water",
	PBElement.Type.PHYSICAL: "physical",
}

## 五种形态，按 [method form_of] 的下标排（M9-c，玩家定的）。
##
## ## BOSS 只有一种，不分近远
##
## **而它现在实际上是远程的**：`boss_count = 2`，槽位 0 和 1，
## 而 [method PBSimConfig.enemy_is_ranged] 判的是 `posmod(slot, 10) < 3` ——
## 两只都落在远程那一档。超级 BOSS 只有一只，槽位 0，同理。
##
## 所以 `*_boss` 那张皮的 `attack` 段要按**放术**画，画成挥拳的话
## 游戏里就是隔着 0.15 打空气，而没有任何一处会报错。
const FORM_NAMES: Array[String] = ["melee", "ranged", "elite_melee", "elite_ranged", "boss"]

## 白模按档次分大小（M9-c）。形状那一维已经被属性占满了
## （[constant ELEMENT_SIDES]，§02 要求去色后仍能凭剪影分五系），
## 所以档次只能靠大小说。
const RANK_BULK: Array[float] = [1.0, 1.4, 1.9]

## 克制高亮：**脚下一圈白**（M6-b 从「本体加一圈亮边」改过来）。
##
## ## 为什么必须是纯白
##
## 它要对全部六种属性色都有对比度。初版用的是淡黄 `(1.0, 0.98, 0.72)`，
## 撞上雷系的黄色本体之后亮边直接消失 —— 而雷系恰恰是玩家最需要看到
## 「我克得住」的场合之一。任何带色相的亮边都会和某一系撞车。
##
## ## 为什么从描边改成了地面圈
##
## 描边那一版是「比本体大一圈的同形状多边形」画在本体后面。本体换成
## 有身高的精灵之后，那圈边整个埋进了精灵里 —— 它假设的是
## 「本体是一个贴在地面上的小多边形」，而 M6-a 之后不是了。
## 画在脚下则和影子、射程圈同一个平面，视角一致，也不会挡住剪影。
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.75)
const RING_RX: float = 12.0
const RING_SEGMENTS: int = 14

## 挨打之后白闪几帧。§02 的「命中反馈」，M3.5-h。
##
## **只有几帧**：逐 tick 的普攻是连续的，闪久了整片战场会一直亮着，
## 那时闪光就不再代表「刚挨了一下」，而只是背景噪声。
const FLASH_FRAMES: int = 4
const FLASH_COLOR := Color(1.0, 1.0, 1.0)

## 30 个皮键，`_keys[属性][形态]`。**开局算一次** —— 每帧现拼的话
## 48 个敌人 × 60 帧就是每秒近三千个新 [StringName]，而 §14 要求战斗中零新建。
var _keys: Dictionary = {}

var _nodes: Array[AnimatedSprite2D] = []

## 每人一份动画状态（M6-b），和己方共用一份实现，见 [PBActorPose]。
var _poses: Array[PBActorPose] = []

## 这一格现在挂着哪张皮。整波属性相同，所以实际上一波只换一次。
var _skins: Array[PBActorSkin] = []

## 每个槽位还剩几帧白闪。**渲染层自己的状态，不进 sim** ——
## 它是「上一帧到这一帧之间发生了什么」，而 sim 里只有「现在是什么样」。
var _flash: PackedInt32Array = PackedInt32Array()

## 这一帧每个敌人的落脚点（屏幕坐标）。影子画在这些点上，
## 理由和己方那份一样，见 [constant PBAllyPool.SHADOW_RX]。
var _shadows: PackedVector2Array = PackedVector2Array()

## 这一波克不克得住 —— 克得住就在每个脚下点一圈白。
var _ringed: bool = false

var _anim_speed: float = 1.0
var _frames_per_tick: float = 3.0
var _tick_rate: int = 20


func _ready() -> void:
	# 按上限一次性建满。COUNT_CAP 是逻辑上限，双端一致（§04），
	# 所以池子大小也不按平台分档。
	var cfg := PBSimConfig.new()
	_tick_rate = maxi(cfg.tick_rate, 1)
	_frames_per_tick = maxf(
		float(Engine.physics_ticks_per_second) / float(maxi(cfg.tick_rate, 1)), 1.0
	)
	for element: PBElement.Type in ELEMENT_NAMES:
		var forms: Array[StringName] = []
		for form: int in FORM_NAMES.size():
			forms.append(
				StringName("enemy_%s_%s" % [ELEMENT_NAMES[element], FORM_NAMES[form]])
			)
		_keys[element] = forms
	_nodes.resize(cfg.count_cap)
	_skins.resize(cfg.count_cap)
	_flash.resize(cfg.count_cap)
	for i: int in cfg.count_cap:
		var node := AnimatedSprite2D.new()
		# **不居中**：原点要落在脚底，偏移由那张皮给 —— 和己方同一把尺子，
		# 否则 y 排序会把敌我按差一个身高的两个基准排（见 [member PBAllyPool._anchors]）。
		node.centered = false
		node.visible = false
		add_child(node)
		_nodes[i] = node
		_poses.append(PBActorPose.new())


## 倍速（暂停和顿帧给 0）。见 [method PBAllyPool.set_anim_speed]。
func set_anim_speed(scale: float) -> void:
	_anim_speed = maxf(scale, 0.0)


## 把池子里的节点同步到 sim 的敌人状态上。每渲染帧调一次。
##
## [param enemies] 是 [method PBBattleSim.enemies] 给的只读数组，
## 下标就是 [member PBEnemy.slot] —— 靠它把节点和逻辑敌人对上，
## 不用每帧重新匹配。
## [param show_counter_ring] 为真时给敌人脚下点一圈白，表示当前阵容克得住它。
## 整波敌人属性相同（§04），所以这是个整波级别的开关，不用逐个判断。
func sync_enemies(
	enemies: Array[PBEnemy], current_tick: int, field: Vector2, show_counter_ring: bool = false
) -> void:
	var feet := PackedVector2Array()
	for i: int in _nodes.size():
		var node: AnimatedSprite2D = _nodes[i]
		if i >= enemies.size():
			node.visible = false
			continue
		var enemy: PBEnemy = enemies[i]
		if not _on_screen(i, enemy, current_tick):
			node.visible = false
			continue
		node.visible = true
		# **位置是落脚点，画布靠 `offset` 往上抬**（M6-a）。
		#
		# 抬节点本身的话 y 排序就按「画布左上角在哪」排了 —— 而己方那边
		# 锚在脚下（[member PBAllyPool._anchors]），两把尺子差一个身高，
		# 表现是「站在前面的忍者被后面的敌人盖住」，而两边坐标都对。
		node.position = screen_position(enemy, field)
		_dress(i, enemy)
		_animate(i, enemy)
		# 身上挂着东西就染一层（M7-f）。**排在血量与白闪之后** ——
		# 那两层讲的是「还剩多少血」和「刚挨了一下」，而这一层讲的是
		# 「他现在被上了状态」，三句话都要说得出。
		node.modulate = PBBuffStrip.tinted(_color_of(i, enemy), enemy.buffs, current_tick)
		feet.append(node.position)
	_ringed = show_counter_ring
	_set_shadows(feet)
	_decay_flash()


## 这一格现在画不画。M9-b。
##
## ## 为什么不能直接用 [method PBEnemy.is_active]
##
## 那句话是「活着而且已经出场」，也就是**怪一死当帧就藏**。
## 于是倒地那一段从来没有机会播 —— 玩家看到的是怪凭空消失，
## 而己方那边（[PBAllyPool]）早就是「演完倒地再留在场上」。
##
## 所以死了之后还要再画一会儿：直到 `dead` 那一段演完并停在最后一帧
## （[method PBActorPose.holds_last]）。演完就藏，**不是等一个固定的帧数** ——
## 帧数写死的话，换一套帧多的真素材就会被拦腰截断，而那不报错。
##
## ## 槽位被下一波接管时不用额外记账
##
## 一波打完槽位会分给下一波的怪，而那时上一具尸体可能还没演完。
## **但这件事已经被下面那句 `has_spawned` 挡住了**：接管这一格的新怪要么
## 已经出场（那就 `is_active`，照常画它自己，[method _animate] 顺手把姿势
## 从倒地切回来），要么还没出场（那就藏）—— 两条路都走不到尸体那一支。
##
## 我一开始给每个槽位记了一份「这具尸体是谁的」，写完才发现它一次都不会生效。
## 那种字段最难查：它看起来在守着什么，于是没人敢动，而它其实什么都没守。
func _on_screen(index: int, enemy: PBEnemy, current_tick: int) -> bool:
	if enemy.is_active(current_tick):
		return true
	if not enemy.has_spawned(current_tick):
		return false
	# 死了。倒地那一段演完之前留着。
	return not (PBActorPose.holds_last(_poses[index].state) and not _nodes[index].is_playing())


## 这个槽位刚挨了一下，白闪一下（§02 的命中反馈，M3.5-h）。
##
## 由 [PBBattleView] 按 [PBDamageWatch] 报的结果调 —— **谁挨打是逐帧比对
## 血量差得出来的**，sim 里没有这个事件。加一个事件到 sim 层的话，
## 那是给渲染层的方便去改确定性模拟，代价完全不对等。
func flash(slot: int) -> void:
	if slot >= 0 and slot < _flash.size():
		_flash[slot] = FLASH_FRAMES


## 影子换了才重画。本节点位置恒为 (0,0)，而它装在一个 y 排序的层里，
## 所以自绘的东西一律排在全部单位后面 —— 影子正该在那儿。
func _set_shadows(feet: PackedVector2Array) -> void:
	if _shadows == feet:
		return
	_shadows = feet
	queue_redraw()


func _draw() -> void:
	for at: Vector2 in _shadows:
		draw_colored_polygon(
			PBLayout.ground_disc(at, PBAllyPool.SHADOW_RX, PBAllyPool.SHADOW_SEGMENTS),
			PBAllyPool.SHADOW_COLOR
		)
	if not _ringed:
		return
	for at: Vector2 in _shadows:
		draw_polyline(PBLayout.ground_disc(at, RING_RX, RING_SEGMENTS), RING_COLOR, 1.0)


## 敌人在屏幕上的位置。
##
## M4-a 之前这里用「槽位号 × 黄金比」现编一个纵向散布 —— 那是渲染层
## **自己发明的装饰**，sim 一个字节都不知道。现在泳道是
## [member PBEnemy.lane]，那个式子搬进了 [method PBSimConfig.enemy_lane]：
## **画面一个像素都没变，但纵向从此算数了。**
func screen_position(enemy: PBEnemy, field: Vector2) -> Vector2:
	return PBLayout.to_screen(enemy.pos(), field)


## 这一格该挂哪张皮。真素材查 [method skin_key]，没有就退回白模。
func _dress(index: int, enemy: PBEnemy) -> PBActorSkin:
	var form: int = form_of(enemy.rank, enemy.ranged)
	var skin: PBActorSkin = PBActorLibrary.skin_for(_keys[enemy.element][form])
	if skin == null:
		skin = PBWhiteModel.enemy(
			ELEMENT_SIDES.get(enemy.element, 6), RANK_BULK[clampi(enemy.rank, 0, 2)]
		)
	if _skins[index] != skin:
		_skins[index] = skin
		var node: AnimatedSprite2D = _nodes[index]
		node.sprite_frames = skin.frames
		node.offset = skin.draw_offset()
		node.scale = Vector2.ONE * skin.pixel_scale
		node.texture_filter = skin.filter_mode()
	return skin


## 30 种里的第几种形态：0 近战小怪 / 1 远程小怪 / 2 近战精英 / 3 远程精英 / 4 BOSS。
##
## **BOSS 那一档吃掉远近这一维**（玩家定的）——见 [constant FORM_NAMES]。
static func form_of(rank: int, ranged: bool) -> int:
	if rank == PBEnemy.Rank.BOSS:
		return 4
	return (2 if rank == PBEnemy.Rank.ELITE else 0) + (1 if ranged else 0)


## 皮键：`enemy_<属性>_<形态>`，共 6 × 5 = 30 个。
##
## **只有这一处拼这个字符串。** 出图那一侧照它建目录，
## 两处各拼一份的话，出好的素材装不进来而工具一句话都不说 ——
## [PBActorLibrary] 查不到就退回白模，表现是「接了素材还是白模」。
static func skin_key(element: PBElement.Type, rank: int, ranged: bool) -> StringName:
	return StringName(
		"enemy_%s_%s" % [ELEMENT_NAMES.get(element, "physical"), FORM_NAMES[form_of(rank, ranged)]]
	)


## 待机 / 行军 / 出手三段。**敌人恒定朝左** —— 他们从战场右端来，
## 目标恒在左边（[method PBActorPose.update] 的 `look_at` 给 NAN 时
## 按移动方向决定，被击退那几 tick 会自然转过去）。
func _animate(index: int, enemy: PBEnemy) -> void:
	var skin: PBActorSkin = _skins[index]
	var pose: PBActorPose = _poses[index]
	var hold: int = maxi(roundi(float(maxi(enemy.attack_interval, 1)) * _frames_per_tick), 2)
	# `engaged` 就是敌人那一侧的「够不够得着」（[method PBBattleSim._enemies_attack]
	# 每 tick 从 false 重算）—— 和己方那边的 `can_reach(aim_at)` 是同一句话，
	# 见 [method PBActorPose.update] 的 `in_range` 那段。
	# 起手（M9-e）：命中那一帧要落在出手的 tick 上。**敌人这一边动画不缩放**
	# （没有 [method PBAllyPool._fit] 那一步），所以实际长度就是素材自己的长度。
	pose.update(
		enemy.pos(),
		enemy.alive,
		enemy.next_shot_at,
		false,
		NAN,
		hold,
		enemy.engaged,
		enemy.swinging,
		PBActorPose.windup_frames(enemy.windup_ticks, _frames_per_tick)
	)
	var node: AnimatedSprite2D = _nodes[index]
	var anim: StringName = skin.anim_for(pose.state)
	# **一次新挥击从第 0 帧起跑**（M9-e）。同 [method PBAllyPool._animate]：
	# 光调 `play` 没用，它对已经在播的同一段什么都不做。
	if pose.swing_began and node.animation == anim:
		node.set_frame_and_progress(0, 0.0)
	# **`holds_last` 那一档演完就停住，不能再 `play`。**
	# `AnimatedSprite2D` 在「停在最后一帧」时再调一次 `play()` 就是重播
	# （见 CLAUDE.md 已知坑位），于是倒地会一遍遍重演 ——
	# 而 M9-b 之前敌人一死就藏，这条从来没机会发作。
	if node.animation != anim or (not node.is_playing() and not PBActorPose.holds_last(pose.state)):
		node.play(anim)
	# **攻击段要压进一个攻击间隔里**（M9-e 补的，己方那边一直有：
	# [method PBAllyPool._fit]）。不压的话白模那 3 帧 0.25 秒就演完了，
	# 而出手要等到间隔的一半 —— 第 4 帧根本不会落在出手那一 tick 上。
	var fit: float = 1.0
	if pose.state == PBActorPose.State.ATTACK:
		var have: float = skin.anim_seconds(anim)
		var want: float = float(maxi(enemy.attack_interval, 1)) / float(_tick_rate)
		if have > 0.0 and want > 0.0:
			fit = clampf(have / want, PBAllyPool.FIT_MIN, PBAllyPool.FIT_MAX)
	node.speed_scale = _anim_speed * fit
	# 白模画的是朝右的剪影，而敌人默认朝左 —— 所以这里的翻转是常态。
	node.flip_h = pose.facing == PBActorPose.FACE_RIGHT
	if skin.source_faces == PBActorSkin.Facing.LEFT:
		node.flip_h = not node.flip_h


func _decay_flash() -> void:
	for i: int in _flash.size():
		if _flash[i] > 0:
			_flash[i] -= 1


## 颜色。血量越低越暗，给一点「快死了」的即时反馈；刚挨打的往白里提。
##
## 两层不冲突：**暗是状态（还剩多少血），白是事件（刚才挨了一下）**。
## 只有暗的那一层时，一个满血 BOSS 挨了整整一波普攻，画面上一点动静都没有。
##
## ## 属性色只染白模
##
## 白模只有一个形状，五系全靠色相分；**真素材各画各的，再乘一层属性色
## 会把美术定的颜色整个拉偏**（[member PBActorSkin.tint_by_element]）。
##
## 己方那边从来就是这么做的（[method PBAllyPool._tint]），敌人这边一直
## 无条件乘 —— M9-c 之前敌人只有白模，所以这条没机会发作。
## 发作起来的样子是「接进来的火系怪整个偏橙红」，而没有一处会报错。
##
## **血量与白闪两层照旧对真素材生效**：它们讲的是「还剩多少血」和
## 「刚挨了一下」，和这个怪本来什么颜色是两回事。
func _color_of(index: int, enemy: PBEnemy) -> Color:
	var skin: PBActorSkin = _skins[index]
	var base := Color.WHITE
	if skin == null or skin.tint_by_element:
		base = ELEMENT_COLORS.get(enemy.element, Color.WHITE)
	var health: float = 1.0
	if enemy.max_hp > 0.0:
		health = clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
	var color := base.lerp(Color(0.15, 0.15, 0.15), (1.0 - health) * 0.6)
	var left: int = _flash[enemy.slot] if enemy.slot < _flash.size() else 0
	if left <= 0:
		return color
	return color.lerp(FLASH_COLOR, float(left) / float(FLASH_FRAMES) * 0.8)
