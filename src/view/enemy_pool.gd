class_name PBEnemyPool
extends Node2D
## 敌人节点的对象池。§14 要求战斗中零新建 —— 节点的创建/销毁在
## 48 单位 × 20 tick/s 的规模下是实打实的开销，而且会造成帧时间抖动。
##
## 池子在 `_ready()` 一次性建满 `COUNT_CAP` 个，之后只改属性和 `visible`。
##
## ## 属性的视觉编码（§02）
##
## `640×360` 下一个敌人只有几个像素，头顶挂图标根本看不清，所以属性必须
## **编码进精灵本身**。§02 要求三层，M0 白模阶段做到前两层：
##
## 1. **主色调** —— 五系各占一个明确色相
## 2. **轮廓形状** —— 每系一个可辨识的剪影。**不能只靠颜色**：
##    色觉障碍 + 缩放后色彩失真，两条都会让纯色方案失效
## 3. 描边高亮（可被当前阵容克制的敌人加亮边）—— 留给 M0-c
##
## §02 的验收项是「去色后仍能仅凭剪影区分五系」，所以形状不是装饰。

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

## 敌人的绘制半径（像素）。`640×360` 下 5 像素约等于放大后的一个小怪。
const ENEMY_RADIUS: float = 5.0

## 战场那条道的上沿。**下沿不是常量** —— 见 [method lane_bottom]。
##
## M4-a 之前是 138–194 那条 56 像素的窄缝（出战席横排占了 96–130）。
## 纵向开始算数之后 56 像素装不下任何阵型：近战射程 0.12 换算过来
## 就是 67 像素，一个人的射程圈比整条道还高。
##
## 现在从 90 起，一直到 [method lane_bottom]（默认 196）。
## 上沿卡在任务卡（收在 84）下面，下沿卡在羁绊带（从 200 起）上面 ——
## **两头都不能越界**：M4-f 之后玩家会把忍者拖到道的边缘，
## 而伸进面板底下的那一截会让人「消失」。
##
## 战斗中这一段是干净的：羁绊带、指令卡、信息栏都只在准备阶段显示。
const LANE_TOP: float = 90.0

## 战线的左右端点：右边出生，左边是基地。
## 「前中后」映射到屏幕右中左，与敌人推进方向一致（§02）。
const FIELD_RIGHT: float = 606.0
const FIELD_LEFT: float = 46.0

## 克制高亮的亮边颜色。
##
## **必须对全部六种属性色都有对比度，所以只能用纯白。**
## 初版用的是淡黄 `(1.0, 0.98, 0.72)`，撞上雷系的黄色本体之后亮边直接消失 ——
## 而雷系恰恰是玩家最需要看到「我克得住」的场合之一。
## 任何带色相的亮边都会和某一系撞车，纯白是唯一对六色都成立的选择。
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.9)

## 亮边比本体大多少。要够大才能在 `640×360` 下看出是一圈边而不是描边毛刺。
const RING_SCALE: float = 2.1

## 挨打之后白闪几帧。§02 的「命中反馈」，M3.5-h。
##
## **只有几帧**：逐 tick 的普攻是连续的，闪久了整片战场会一直亮着，
## 那时闪光就不再代表「刚挨了一下」，而只是背景噪声。
const FLASH_FRAMES: int = 4
const FLASH_COLOR := Color(1.0, 1.0, 1.0)

var _nodes: Array[Polygon2D] = []
var _rings: Array[Polygon2D] = []

## 每个槽位还剩几帧白闪。**渲染层自己的状态，不进 sim** ——
## 它是「上一帧到这一帧之间发生了什么」，而 sim 里只有「现在是什么样」。
var _flash: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	# 按上限一次性建满。COUNT_CAP 是逻辑上限，双端一致（§04），
	# 所以池子大小也不按平台分档。
	var cfg := PBSimConfig.new()
	_rings.resize(cfg.count_cap)
	_nodes.resize(cfg.count_cap)
	_flash.resize(cfg.count_cap)
	# 亮边先加，才会画在本体后面 —— Godot 的 2D 绘制顺序就是子节点顺序。
	for i: int in cfg.count_cap:
		var ring := Polygon2D.new()
		ring.color = RING_COLOR
		ring.visible = false
		add_child(ring)
		_rings[i] = ring
	for i: int in cfg.count_cap:
		var node := Polygon2D.new()
		node.visible = false
		add_child(node)
		_nodes[i] = node


## 把池子里的节点同步到 sim 的敌人状态上。每渲染帧调一次。
##
## [param enemies] 是 [method PBBattleSim.enemies] 给的只读数组，
## 下标就是 [member PBEnemy.slot] —— 靠它把节点和逻辑敌人对上，
## 不用每帧重新匹配。
## [param show_counter_ring] 为真时给敌人加一圈亮边，表示当前阵容克得住它。
## 整波敌人属性相同（§04），所以这是个整波级别的开关，不用逐个判断。
func sync_enemies(
	enemies: Array[PBEnemy], current_tick: int, field: Vector2, show_counter_ring: bool = false
) -> void:
	for i: int in _nodes.size():
		var node: Polygon2D = _nodes[i]
		var ring: Polygon2D = _rings[i]
		if i >= enemies.size():
			node.visible = false
			ring.visible = false
			continue
		var enemy: PBEnemy = enemies[i]
		if not enemy.is_active(current_tick):
			node.visible = false
			ring.visible = false
			continue
		node.visible = true
		node.position = screen_position(enemy, field)
		node.color = _color_of(enemy)
		if node.polygon.is_empty():
			node.polygon = _shape_for(enemy.element)
			ring.polygon = _shape_for(enemy.element, RING_SCALE)
		ring.visible = show_counter_ring
		ring.position = node.position
	_decay_flash()


## 这个槽位刚挨了一下，白闪一下（§02 的命中反馈，M3.5-h）。
##
## 由 [PBBattleView] 按 [PBDamageWatch] 报的结果调 —— **谁挨打是逐帧比对
## 血量差得出来的**，sim 里没有这个事件。加一个事件到 sim 层的话，
## 那是给渲染层的方便去改确定性模拟，代价完全不对等。
func flash(slot: int) -> void:
	if slot >= 0 and slot < _flash.size():
		_flash[slot] = FLASH_FRAMES


## 一个战场单位在屏幕上换算成多少像素。
##
## **两轴共用这一个比例。** 各算各的话，sim 里的一个圆在屏幕上会是椭圆 ——
## 而 §02 的射程圈、大招落点预示都要求玩家看到的形状就是判定的形状。
static func px_per_unit(field: Vector2) -> float:
	return (FIELD_RIGHT - FIELD_LEFT) / maxf(field.x, 0.001)


## 战场那条道的下沿。**从战场高度算出来，不是常量** ——
## 写死一个数的话，改 [member PBSimConfig.field_height] 就会让画面
## 和判定悄悄错开，而那种错开只表现为「打得到的敌人画在道外面」。
static func lane_bottom(field: Vector2) -> float:
	return LANE_TOP + field.y * px_per_unit(field)


## 屏幕坐标 → 战场坐标。[method to_screen] 的逆，用来把鼠标点到的地方
## 换算回 sim 认得的位置（§02 的战斗中点选，M4-e）。
##
## 和正向那一份**必须成对改**：各写各的话，玩家点到的和实际选中的
## 会差几个像素，而那种偏差表现为「点边上一点就选不中」。
static func to_field(at: Vector2, field: Vector2) -> Vector2:
	var scale: float = px_per_unit(field)
	return Vector2((at.x - FIELD_LEFT) / scale, (at.y - LANE_TOP) / scale)


## 战场坐标 → 屏幕坐标。
##
## **全项目唯一一份。** 敌人、己方单位、落点预示、伤害飘字都走它 ——
## 各写一份的话，「预示圈盖住的位置」和「真正挨打的位置」会差几个像素，
## 而那种偏差看起来只是「大招好像打偏了」。
##
## [param field] 是 `Vector2(field_length, field_height)`。
static func to_screen(at: Vector2, field: Vector2) -> Vector2:
	var scale: float = px_per_unit(field)
	return Vector2(FIELD_LEFT + at.x * scale, LANE_TOP + at.y * scale)


## 敌人在屏幕上的位置。
##
## M4-a 之前这里用「槽位号 × 黄金比」现编一个纵向散布 —— 那是渲染层
## **自己发明的装饰**，sim 一个字节都不知道。现在泳道是
## [member PBEnemy.lane]，那个式子搬进了 [method PBSimConfig.enemy_lane]：
## **画面一个像素都没变，但纵向从此算数了。**
func screen_position(enemy: PBEnemy, field: Vector2) -> Vector2:
	return to_screen(enemy.pos(), field)


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


## 生成某一系的多边形剪影。[param scale] 用来做比本体大一圈的亮边。
func _shape_for(element: PBElement.Type, scale: float = 1.0) -> PackedVector2Array:
	var sides: int = ELEMENT_SIDES.get(element, 6)
	var points := PackedVector2Array()
	for i: int in sides:
		# -PI/2 让第一个顶点朝上，剪影的朝向才稳定。
		var angle: float = -PI / 2.0 + TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * ENEMY_RADIUS * scale)
	return points
