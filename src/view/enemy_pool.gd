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

## 真素材进来时每系去 `data/actors/` 里查这个键（M6-b）。
##
## 敌人没有 [PBCharacter]，所以借不到 [member PBCharacter.actor_key] 那条路 ——
## 但换皮的入口必须和己方是同一个（[PBActorLibrary]），
## 否则「敌人的形象」会长出第二套加载规则，而两套迟早在朝向或脚底上分叉。
## **查不到就退回白模**，也就是今天走的那一条。
const SKIN_KEYS := {
	PBElement.Type.FIRE: &"enemy_fire",
	PBElement.Type.WIND: &"enemy_wind",
	PBElement.Type.THUNDER: &"enemy_thunder",
	PBElement.Type.EARTH: &"enemy_earth",
	PBElement.Type.WATER: &"enemy_water",
	PBElement.Type.PHYSICAL: &"enemy_physical",
}

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


func _ready() -> void:
	# 按上限一次性建满。COUNT_CAP 是逻辑上限，双端一致（§04），
	# 所以池子大小也不按平台分档。
	var cfg := PBSimConfig.new()
	_frames_per_tick = maxf(
		float(Engine.physics_ticks_per_second) / float(maxi(cfg.tick_rate, 1)), 1.0
	)
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
		if not enemy.is_active(current_tick):
			node.visible = false
			continue
		node.visible = true
		# **位置是落脚点，画布靠 `offset` 往上抬**（M6-a）。
		#
		# 抬节点本身的话 y 排序就按「画布左上角在哪」排了 —— 而己方那边
		# 锚在脚下（[member PBAllyPool._anchors]），两把尺子差一个身高，
		# 表现是「站在前面的忍者被后面的敌人盖住」，而两边坐标都对。
		node.position = screen_position(enemy, field)
		_dress(i, enemy.element)
		_animate(i, enemy)
		node.modulate = _color_of(enemy)
		feet.append(node.position)
	_ringed = show_counter_ring
	_set_shadows(feet)
	_decay_flash()


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


## 这一格该挂哪张皮。真素材查 [constant SKIN_KEYS]，没有就退回白模。
func _dress(index: int, element: PBElement.Type) -> PBActorSkin:
	var skin: PBActorSkin = PBActorLibrary.skin_for(SKIN_KEYS.get(element, &""))
	if skin == null:
		skin = PBWhiteModel.enemy(ELEMENT_SIDES.get(element, 6))
	if _skins[index] != skin:
		_skins[index] = skin
		var node: AnimatedSprite2D = _nodes[index]
		node.sprite_frames = skin.frames
		node.offset = skin.draw_offset()
		node.scale = Vector2.ONE * skin.pixel_scale
	return skin


## 待机 / 行军 / 出手三段。**敌人恒定朝左** —— 他们从战场右端来，
## 目标恒在左边（[method PBActorPose.update] 的 `look_at` 给 NAN 时
## 按移动方向决定，被击退那几 tick 会自然转过去）。
func _animate(index: int, enemy: PBEnemy) -> void:
	var skin: PBActorSkin = _skins[index]
	var pose: PBActorPose = _poses[index]
	var hold: int = maxi(roundi(float(maxi(enemy.attack_interval, 1)) * _frames_per_tick), 2)
	pose.update(enemy.pos(), enemy.alive, enemy.next_shot_at, false, NAN, hold)
	var node: AnimatedSprite2D = _nodes[index]
	var anim: StringName = skin.anim_for(pose.state)
	if node.animation != anim or not node.is_playing():
		node.play(anim)
	node.speed_scale = _anim_speed
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
func _color_of(enemy: PBEnemy) -> Color:
	var base: Color = ELEMENT_COLORS.get(enemy.element, Color.WHITE)
	var health: float = 1.0
	if enemy.max_hp > 0.0:
		health = clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
	var color := base.lerp(Color(0.15, 0.15, 0.15), (1.0 - health) * 0.6)
	var left: int = _flash[enemy.slot] if enemy.slot < _flash.size() else 0
	if left <= 0:
		return color
	return color.lerp(FLASH_COLOR, float(left) / float(FLASH_FRAMES) * 0.8)
