class_name PBEnemyPool
extends Node2D
## 敌人节点的对象池。§14 要求战斗中零新建：`_ready()` 一次性建满 `COUNT_CAP` 个，之后只改属性和 `visible`。
##
## 属性的视觉编码（§02 要求三层，640×360 下头顶挂图标看不清）：
##
## 1. **主色调** —— 五系各占一个明确色相
## 2. **轮廓形状** —— 每系一个剪影。**不能只靠颜色**（色觉障碍、缩放后色彩失真）；验收是去色后仍能凭剪影分五系
## 3. **克制高亮** —— 可被当前阵容克制的敌人脚下一圈白

## 五系 + 物理 + 仙的主色调。§02 指定的色相。
##
## **这张表敌我共用**（[method PBAllyPool._element_color] 也读它），
## 所以它必须铺满**己方**能有的每一种属性 —— 少一格的表现是
## 仙系角色的卡面和场上方块一起变成兜底的白，而它不报错。
## 下面那两张（[constant ELEMENT_SIDES] / [constant ELEMENT_NAMES]）
## 只给敌人用，情况相反，见它们各自顶上那段。
const ELEMENT_COLORS := {
	PBElement.Type.FIRE: Color(0.90, 0.35, 0.20),
	PBElement.Type.WIND: Color(0.25, 0.80, 0.55),
	PBElement.Type.THUNDER: Color(0.95, 0.85, 0.25),
	PBElement.Type.EARTH: Color(0.60, 0.45, 0.25),
	PBElement.Type.WATER: Color(0.30, 0.55, 0.95),
	PBElement.Type.PHYSICAL: Color(0.70, 0.70, 0.72),
	PBElement.Type.SAGE: Color(0.78, 0.62, 0.96),
}

## 每系的边数，用来生成可区分的剪影。物理用 8 边（接近圆）。
## 去色之后靠的就是这个 —— 三角、方、五边、六边、菱形一眼能分开。
##
## **没有仙这一格，那是规则不是遗漏。** 怪物只有五系与物理两类
## （[constant PBElement.PICKABLE]，原版也是如此：常规怪五系轮转、
## 精英怪吃物理档），仙只出现在己方的三个角色身上。
## `test_element` 里有一条钉住「波次属性里不许出现仙」——
## 不钉的话哪天真刷出一只仙系怪，它会安静地领到物理的皮和边数，
## 而两处都只是 `.get(…, 兜底)`，一句话都不会说。
const ELEMENT_SIDES := {
	PBElement.Type.FIRE: 3,
	PBElement.Type.WIND: 5,
	PBElement.Type.THUNDER: 4,
	PBElement.Type.EARTH: 6,
	PBElement.Type.WATER: 7,
	PBElement.Type.PHYSICAL: 8,
}

## 每系在皮键里的名字。敌人没有 [PBCharacter]，但换皮入口必须和己方同一个（[PBActorLibrary]），
## 否则会长出第二套加载规则。查不到就退回白模。
const ELEMENT_NAMES := {
	PBElement.Type.FIRE: "fire",
	PBElement.Type.WIND: "wind",
	PBElement.Type.THUNDER: "thunder",
	PBElement.Type.EARTH: "earth",
	PBElement.Type.WATER: "water",
	PBElement.Type.PHYSICAL: "physical",
}

## 五种形态，按 [method form_of] 的下标排（玩家定的）。**BOSS 只有一种，不分近远**。
## BOSS 一律远程（[method PBSpawnRules.fill]，射程 [member PBSimConfig.enemy_reach_boss]），
## 所以 `*_boss` 那张皮的 `attack` 段要按放术画，画成挥拳的话游戏里就是隔着距离打空气。
const FORM_NAMES: Array[String] = ["melee", "ranged", "elite_melee", "elite_ranged", "boss"]

## 白模按档次分大小：形状那一维已经被属性占满了，档次只能靠大小说。
const RANK_BULK: Array[float] = [1.0, 1.4, 1.9]

## 克制高亮：**脚下一圈白**。
## **必须是纯白**：任何带色相的亮边都会和某一系的本体撞车（淡黄撞上雷系就消失）。
## **画在脚下**：本体是有身高的精灵，包在本体外面的描边会埋进精灵里；地面圈和影子、射程圈同一个平面。
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.75)
const RING_RX: float = 12.0
const RING_SEGMENTS: int = 14

## 挨打之后白闪几帧（§02 的命中反馈）。**只有几帧**：普攻是连续的，闪久了整片战场一直亮着，闪光就成了噪声。
const FLASH_FRAMES: int = 4
const FLASH_COLOR := Color(1.0, 1.0, 1.0)

## 30 个皮键，`_keys[属性][形态]`。**开局算一次** —— 每帧现拼的话
## 48 个敌人 × 60 帧就是每秒近三千个新 [StringName]，而 §14 要求战斗中零新建。
var _keys: Dictionary = {}

var _nodes: Array[AnimatedSprite2D] = []

## 每人一份动画状态，和己方共用一份实现，见 [PBActorPose]。
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
			forms.append(key_for(element, form))
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
		# **位置是落脚点，画布靠 `offset` 往上抬**：抬节点本身的话 y 排序按画布左上角排，
		# 而己方锚在脚下，两把尺子差一个身高 —— 站在前面的忍者会被后面的敌人盖住。
		node.position = screen_position(enemy, field)
		_dress(i, enemy)
		_animate(i, enemy)
		# 身上挂着东西就染一层，**排在血量与白闪之后**：三层各说一句（还剩多少血、刚挨了一下、被上了状态）。
		node.modulate = PBBuffStrip.tinted(_color_of(i, enemy), enemy.buffs, current_tick)
		feet.append(node.position)
	_ringed = show_counter_ring
	_set_shadows(feet)
	_decay_flash()


## 这一格现在画不画。
##
## 不能直接用 [method PBEnemy.is_active]（活着且已出场）：怪一死当帧就藏的话倒地段没机会播。
## 死了之后画到 `dead` 那一段演完并停在最后一帧（[method PBActorPose.holds_last]）—— **不等固定帧数**，
## 写死的话帧多的素材会被拦腰截断。
##
## 槽位被下一波接管时不用额外记账：接管的新怪要么已出场（照常画它自己），要么还没出场（藏）。
func _on_screen(index: int, enemy: PBEnemy, current_tick: int) -> bool:
	if enemy.is_active(current_tick):
		return true
	if not enemy.has_spawned(current_tick):
		return false
	# 死了：倒地那一段演完之前留着。
	return not (PBActorPose.holds_last(_poses[index].state) and not _nodes[index].is_playing())


## 这个槽位刚挨了一下，白闪一下。由 [PBBattleView] 按 [PBDamageWatch] 逐帧比出来的结果调，sim 里没有这个事件。
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


## 敌人在屏幕上的位置。泳道来自 [member PBEnemy.lane]。
func screen_position(enemy: PBEnemy, field: Vector2) -> Vector2:
	return PBLayout.to_screen(enemy.pos(), field)


## 这一格该挂哪张皮。真素材查 [method skin_key]，没有就退回白模。
func _dress(index: int, enemy: PBEnemy) -> PBActorSkin:
	var form: int = form_of(enemy.rank, enemy.ranged)
	var skin: PBActorSkin = PBActorLibrary.skin_for(_keys[enemy.element][form])
	if skin == null:
		skin = white_for(enemy.element, enemy.rank)
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
## **只有这一处拼这个字符串**（预览台和战场共用）：出图那一侧照它建目录，两处各拼一份的话出好的素材装不进来，
## [PBActorLibrary] 查不到就退回白模，表现是「接了素材还是白模」。
static func key_for(element: PBElement.Type, form: int) -> StringName:
	var slot: int = clampi(form, 0, FORM_NAMES.size() - 1)
	return StringName("enemy_%s_%s" % [ELEMENT_NAMES.get(element, "physical"), FORM_NAMES[slot]])


## 皮键，按「档次 + 远近」问。战斗里走这一条（那边手上是一只 [PBEnemy]）。
static func skin_key(element: PBElement.Type, rank: int, ranged: bool) -> StringName:
	return key_for(element, form_of(rank, ranged))


## 这一种怪**没有真素材时**长什么样。预览台和战场共用，否则两边的白模会在边数或体型上分叉。
static func white_for(element: PBElement.Type, rank: int) -> PBActorSkin:
	return PBWhiteModel.enemy(ELEMENT_SIDES.get(element, 6), RANK_BULK[clampi(rank, 0, 2)])


## 待机 / 行军 / 出手三段。**敌人恒定朝左** —— 他们从战场右端来，
## 目标恒在左边（[method PBActorPose.update] 的 `look_at` 给 NAN 时
## 按移动方向决定，被击退那几 tick 会自然转过去）。
func _animate(index: int, enemy: PBEnemy) -> void:
	var skin: PBActorSkin = _skins[index]
	var pose: PBActorPose = _poses[index]
	var hold: int = maxi(roundi(float(maxi(enemy.attack_interval, 1)) * _frames_per_tick), 2)
	# `engaged` 就是敌人那一侧的「够不够得着」，和己方的 `can_reach(aim_at)` 同一句话（见 [method PBActorPose.update]）。
	# **敌人的动画不缩放**（没有 [method PBAllyPool._fit] 那一步），实际长度就是素材自己的长度。
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
	# **一次新挥击从第 0 帧起跑**，同 [method PBAllyPool._animate]。
	if pose.swing_began and node.animation == anim:
		node.set_frame_and_progress(0, 0.0)
	# **`holds_last` 那一档演完就停住，不能再 `play`**：停在最后一帧时再调 `play()` 就是重播，倒地会一遍遍重演。
	if node.animation != anim or (not node.is_playing() and not PBActorPose.holds_last(pose.state)):
		node.play(anim)
	# **攻击段要压进一个攻击间隔里**（同 [method PBAllyPool._fit]），否则第 4 帧不会落在出手那一 tick 上。
	var fit: float = 1.0
	if pose.state == PBActorPose.State.ATTACK:
		var have: float = skin.anim_seconds(anim)
		var want: float = float(maxi(enemy.attack_interval, 1)) / float(_tick_rate)
		if have > 0.0 and want > 0.0:
			fit = clampf(have / want, PBAllyPool.FIT_MIN, PBAllyPool.FIT_MAX)
	node.speed_scale = _anim_speed * fit
	# **和己方同一把尺子**（[method PBActorSkin.flips_for]）。
	node.flip_h = skin.flips_for(pose.facing)


func _decay_flash() -> void:
	for i: int in _flash.size():
		if _flash[i] > 0:
			_flash[i] -= 1


## 颜色。血量越低越暗（状态），刚挨打的往白里提（事件）—— 两层不冲突。
##
## **属性色只染白模**：真素材各画各的，再乘一层属性色会把美术定的颜色拉偏（[member PBActorSkin.tint_by_element]），
## 同 [method PBAllyPool._tint]。血量与白闪两层照旧对真素材生效。
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
