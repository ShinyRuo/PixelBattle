class_name PBWhiteModel
extends RefCounted
## 代码画出来的**白模帧**。M6-b。
##
## ## 它存在的理由是「这条链路今天就要是通的」
##
## §14 说白模阶段不动 `assets/`，所以真素材一张都没有。而一套动画系统
## 如果要等素材才跑得起来，它就得在**没有任何反馈**的情况下写完 ——
## 脚底锚点、朝向翻转、攻击段压进攻击间隔，这三样全是「差一点点也不报错」
## 的东西，光看代码看不出对不对。
##
## 所以这里按 [PBActorSkin] 的同一套字段现造一份图：真素材进来时
## 换掉的只是 `data/actors/*.tres`，[PBAllyPool] 与 [PBEnemyPool] 一行不动。
## **白模就是第一个「换皮」的样本**，铁律 5 因此从第一天起就被走过一遍。
##
## ## 敌我为什么长得不一样
##
## §02 的验收项是「去色后仍能仅凭剪影区分五系」，敌人的多边形剪影是
## 唯一的载体（[constant PBEnemyPool.ELEMENT_SIDES]）。所以敌人的白模是
## **一个会动的多边形**，不是小人 —— 换成小人的话那条验收当场作废。
## 己方是方头方脑的人形：形状类别不同，去色之后照样敌我分得开
## （[PBAllyPool] 类顶部那条）。
##
## 两份都只画纯白 + 底部一道暗边，颜色一律交给
## [member CanvasItem.modulate]（[member PBActorSkin.tint_by_element]）——
## 把属性色烤进图里的话，五系就要各存一份一模一样的图。

## 己方白模的画布与身高。画布 54 见方正是素材规格里的默认档，
## 头顶留白由 [constant PBLayout.SPRITE_HEADROOM] 兜着（= 画布 + 2）。
##
## ## 这个数和泳道间距是抢同一块地方
##
## 战场的纵深在屏幕上只有 155 像素（`field_height × px_per_lane`），
## 而 [member PBSimConfig.ally_lane] 把**全部上场的人**平铺在这一段里 ——
## 站满 10 个人时每两条道只隔 **15.6 像素**。也就是说身高一旦超过它，
## 后面那个人就会被前面那个挡掉一截，这是几何，不是可以调好的东西。
##
## 27 是**故意超出去的**（M6-c，玩家定的「正式资源是白模的 1.5 倍」）：
## 挡住一截换来的是脸认得出来 —— 18 高的画布上画不出一个认得出的角色，
## 而 y 排序保证挡的关系永远是对的（近的挡远的）。
## 真要不挡，只有两条路，两条都改配平：把 [member PBSimConfig.field_height]
## 抬上去，或者让 `ally_lane` 按列分摊而不是全队平铺。**归数值回归。**
##
## **M6-g 又抬了一次 1.5 倍**（27 → 41，画布 36 → 54，玩家试玩后定的）。
## 这一次买的是「战场上看得清」——40 像素的人物在 640×360 里才和界面
## 那些面板一个量级。代价照旧全在遮挡上：泳道间距没动，
## 站 7 个人时每两条道仍然只隔 22 像素，而人比那高了快一倍。
## **归数值回归的那两条路一条没变。**
const ALLY_CANVAS: int = 54
const ALLY_HEIGHT: int = 41

## 画白模用的那一套坐标是按 **36 见方**写死的（上面那一版画布）。
## 改大小时不去逐个改那些字面量，而是整体按比例缩 —— 见 [method _s]。
const ALLY_BASE_CANVAS: float = 36.0

## 敌人白模的画布与多边形半径。比己方小一圈 ——
## 十来个忍者 vs 最多 48 个敌人，一样大的话潮水波会糊成一片。
const ENEMY_CANVAS: int = 36
const ENEMY_RADIUS: float = 11.25

## 底部这几行压暗，给一点「站在地上」的体积感。纯平的一块白在
## 压过 y 轴的地面上会像一张贴纸。**跟着画布一起缩**（[method _s]）。
const SHADE_ROWS: int = 4
const SHADE: float = 0.72

## 描边色。**这不是装饰，是「几个人」这个读数的唯一载体。**
##
## ## 为什么必须有它
##
## [member PBSimConfig.ally_lane] 把全部上场的人平铺在 155 像素的纵深里，
## 站 7 个人时每两条道只隔 22 像素 —— 而一个 41 高的小人比那高出快一倍。
## 于是同一列里几个同系的人**在屏幕上叠成一根实心色条**：
## 玩家看不出那是五个人，也点不中中间那个（实测截图，M6-c）。
##
## 描边把「一个人的边界」画了出来，叠起来也数得清。它是这个问题
## **唯一不动 sim 的解** —— 另外两条（抬 `field_height`、让泳道按列分摊）
## 都会改开战站位，也就是改配平。
##
## 白模尤其需要它：白模一系只有一个形状一个颜色，五个火系忍者长得一模一样，
## 而真素材各画各的，本来就分得开。**规格里仍然要求真素材带描边** ——
## 因为「五个不同角色挤在一起」和「一个角色」的边界一样需要被画出来。
const OUTLINE := Color(0.06, 0.06, 0.09, 1.0)

## 待机 / 跑动 / 攻击各自的播放帧率。攻击那一段的实际速度会被
## [method PBAllyPool._fit] 按攻击间隔再缩一次，这里只是基准。
const FPS_IDLE: float = 4.0
const FPS_RUN: float = 10.0
const FPS_ATTACK: float = 12.0

static var _ally: PBActorSkin = null
static var _enemies: Dictionary = {}


## 己方的白模。全局一份，按属性染色。
static func ally() -> PBActorSkin:
	if _ally != null:
		return _ally
	var frames := SpriteFrames.new()
	_add(frames, &"idle", FPS_IDLE, true, [_ally_frame(0, 0, 2), _ally_frame(1, 0, 2)])
	_add(
		frames,
		&"run",
		FPS_RUN,
		true,
		[
			_ally_frame(0, 2, 3),
			_ally_frame(3, 2, 1),
			_ally_frame(0, 2, 1),
			_ally_frame(3, 2, 3),
		]
	)
	_add(
		frames,
		&"attack",
		FPS_ATTACK,
		false,
		[_ally_frame(1, -2, 2), _ally_frame(0, 2, 11), _ally_frame(0, 1, 6)]
	)
	_add(frames, &"cast", FPS_IDLE, true, [_ally_frame(3, 0, 4), _ally_frame(4, 0, 4)])
	_add(frames, &"dead", FPS_IDLE, false, [_ally_dead()])
	frames.remove_animation(&"default")
	_ally = _skin(&"_white_ally", frames, float(ALLY_HEIGHT))
	return _ally


## 某一系敌人的白模。[param sides] 走 [constant PBEnemyPool.ELEMENT_SIDES]。
static func enemy(sides: int) -> PBActorSkin:
	var key: int = maxi(sides, 3)
	if _enemies.has(key):
		return _enemies[key]
	var frames := SpriteFrames.new()
	_add(
		frames,
		&"idle",
		FPS_IDLE,
		true,
		[_enemy_frame(key, 0, 1.0), _enemy_frame(key, 1, 0.96)]
	)
	_add(
		frames,
		&"run",
		FPS_RUN,
		true,
		[
			_enemy_frame(key, 0, 1.0),
			_enemy_frame(key, 2, 0.94),
			_enemy_frame(key, 0, 1.0),
			_enemy_frame(key, 2, 1.06),
		]
	)
	_add(
		frames,
		&"attack",
		FPS_ATTACK,
		false,
		[_enemy_frame(key, 1, 0.88), _enemy_frame(key, 0, 1.22), _enemy_frame(key, 0, 1.0)]
	)
	frames.remove_animation(&"default")
	# 高度按多边形的上沿算，血条那套敌人用不上，但落点预示与选中框要用。
	var skin := _skin(&"_white_enemy_%d" % key, frames, ENEMY_RADIUS * 2.0 + 1.0)
	_enemies[key] = skin
	return skin


## 造一张皮。白模一律**按属性染色**、朝右、不放大。
static func _skin(key: StringName, frames: SpriteFrames, height: float) -> PBActorSkin:
	var skin := PBActorSkin.new()
	skin.key = key
	skin.frames = frames
	skin.tint_by_element = true
	skin.source_faces = PBActorSkin.Facing.RIGHT
	skin.height_px = height
	return skin


static func _add(
	frames: SpriteFrames, anim: StringName, fps: float, loops: bool, images: Array
) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loops)
	for image: Image in images:
		frames.add_frame(anim, ImageTexture.create_from_image(image))


## 一帧己方白模。[param lift] 整体抬几像素、[param lean] 前倾几像素、
## [param arm] 手往前伸多长（攻击段就是靠它读出来的）。
##
## **三个参数和下面那批坐标都是 36 画布下的数**，进来先过一遍
## [method _s] 缩到当前画布 —— 改身高只动 [constant ALLY_CANVAS] 一个数。
static func _ally_frame(lift: int, lean: int, arm: int) -> Image:
	var image := _blank(ALLY_CANVAS)
	var base: int = ALLY_CANVAS - _s(lift)
	var tilt: int = _s(lean)
	# 腿、身、头三块，脚底贴在画布底边上（减掉 lift 那点腾空）。
	_box(image, _s(13) + tilt, base - _s(8), _s(4), _s(8))
	_box(image, _s(19) + tilt, base - _s(8), _s(4), _s(8))
	_box(image, _s(13) + tilt, base - _s(20), _s(10), _s(12))
	_box(image, _s(14) + tilt, base - _s(27), _s(8), _s(9))
	if arm > 0:
		_box(image, _s(23) + tilt, base - _s(18), _s(arm), _s(3))
	_shade(image)
	_outline(image)
	return image


## 倒地那一帧：摊平在地上。**不是空图** —— 藏起来的话「他死了」和
## 「他从来没上场」在画面上是同一件事。
static func _ally_dead() -> Image:
	var image := _blank(ALLY_CANVAS)
	_box(image, _s(7), ALLY_CANVAS - _s(6), _s(22), _s(6))
	_shade(image)
	_outline(image)
	return image


## 把一个「36 画布下的坐标」换算到当前画布上。
##
## 白模那身方块是按 36 见方画的，而画布尺寸走过 32 → 24 → 36 → 54 四档
## （每一档的依据都不同，见 [constant ALLY_HEIGHT]）。逐个改字面量的话，
## 改漏一处的表现是「胳膊长在肚子上」——看得见，但要盯着看才看得出。
##
## **不给它保底成 1。** 这里换算的既有宽高也有偏移，而偏移里
## `lift = 0`（没腾空）和 `lean = -2`（后仰）都是正经取值 ——
## 保底会把「不动」变成「往前一格」，把后仰变成前倾。
static func _s(value: int) -> int:
	return roundi(float(value) * float(ALLY_CANVAS) / ALLY_BASE_CANVAS)


## 一帧敌人白模：一个 [param sides] 边形，抬 [param lift]、缩放 [param scale]。
static func _enemy_frame(sides: int, lift: int, scale: float) -> Image:
	var image := _blank(ENEMY_CANVAS)
	var radius: float = ENEMY_RADIUS * scale
	var centre := Vector2(ENEMY_CANVAS * 0.5, float(ENEMY_CANVAS) - 1.0 - radius - float(lift))
	var shape := PackedVector2Array()
	for i: int in sides:
		# -PI/2 让第一个顶点朝上，和 [method PBEnemyPool._shape_for] 同一条规矩。
		var angle: float = -PI / 2.0 + TAU * float(i) / float(sides)
		shape.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	for y: int in ENEMY_CANVAS:
		for x: int in ENEMY_CANVAS:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), shape):
				image.set_pixel(x, y, Color.WHITE)
	_shade(image)
	_outline(image)
	return image


static func _blank(side: int) -> Image:
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	return image


## 一块实心白方块，超出画布的部分自动裁掉。
static func _box(image: Image, x: int, y: int, width: int, height: int) -> void:
	for row: int in height:
		for column: int in width:
			var at := Vector2i(x + column, y + row)
			if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
				continue
			image.set_pixel(at.x, at.y, Color.WHITE)


## 沿剪影外沿描一圈深色，见 [constant OUTLINE]。
##
## **先收集再写**：边描边写的话，刚描上去的那一圈会被当成实体，
## 下一个像素就沿着它再描一圈 —— 一趟扫下来描出三四层，整个人黑掉。
static func _outline(image: Image) -> void:
	var edge: Array[Vector2i] = []
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				continue
			if _touches_body(image, x, y):
				edge.append(Vector2i(x, y))
	for at: Vector2i in edge:
		image.set_pixel(at.x, at.y, OUTLINE)


## 这个空像素的上下左右有没有实体。**只看四邻不看八邻** ——
## 看八邻的话斜角会多描出一格，36 见方的画布上那一格很显眼。
static func _touches_body(image: Image, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at := Vector2i(x + step.x, y + step.y)
		if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
			continue
		if image.get_pixel(at.x, at.y).a > 0.0:
			return true
	return false


## 把最下面几行压暗。染色走 [member CanvasItem.modulate]（乘法），
## 所以这道暗边在五系上都成立。
static func _shade(image: Image) -> void:
	var height: int = image.get_height()
	for row: int in maxi(_s(SHADE_ROWS), 1):
		var y: int = height - 1 - row
		if y < 0:
			break
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			image.set_pixel(x, y, Color(SHADE, SHADE, SHADE, pixel.a))
