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

## 敌人在纵向上散布的范围，避免 48 个挤成一条线。
const LANE_TOP: float = 95.0
const LANE_BOTTOM: float = 300.0

## 战线的左右端点：右边出生，左边是基地。
## 「前中后」映射到屏幕右中左，与敌人推进方向一致（§02）。
const FIELD_RIGHT: float = 606.0
const FIELD_LEFT: float = 46.0

var _nodes: Array[Polygon2D] = []


func _ready() -> void:
	# 按上限一次性建满。COUNT_CAP 是逻辑上限，双端一致（§04），
	# 所以池子大小也不按平台分档。
	var cfg := PBSimConfig.new()
	_nodes.resize(cfg.count_cap)
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
func sync_enemies(enemies: Array[PBEnemy], current_tick: int, field_length: float) -> void:
	for i: int in _nodes.size():
		var node: Polygon2D = _nodes[i]
		if i >= enemies.size():
			node.visible = false
			continue
		var enemy: PBEnemy = enemies[i]
		if not enemy.is_active(current_tick):
			node.visible = false
			continue
		node.visible = true
		node.position = _position_of(enemy, field_length)
		node.color = _color_of(enemy)
		if node.polygon.is_empty():
			node.polygon = _shape_for(enemy.element)


## 敌人在屏幕上的位置。x 由推进进度决定，y 按槽位散开。
func _position_of(enemy: PBEnemy, field_length: float) -> Vector2:
	# progress 是 0–1 的归一化进度 —— sim 层不知道屏幕多宽，
	# 换分辨率时只有这一行要改。
	var t: float = enemy.progress(field_length)
	var x: float = lerpf(FIELD_RIGHT, FIELD_LEFT, t)
	# 用槽位号做确定性散布，不掷骰 —— 掷骰会让同一个种子的两次回放长得不一样，
	# 而战报回放（§13）要求画面也可复现。
	var lane: float = fmod(float(enemy.slot) * 0.6180339887, 1.0)
	return Vector2(x, lerpf(LANE_TOP, LANE_BOTTOM, lane))


## 颜色。血量越低越暗，给一点「快死了」的即时反馈。
func _color_of(enemy: PBEnemy) -> Color:
	var base: Color = ELEMENT_COLORS.get(enemy.element, Color.WHITE)
	var health: float = 1.0
	if enemy.max_hp > 0.0:
		health = clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
	return base.lerp(Color(0.15, 0.15, 0.15), (1.0 - health) * 0.6)


## 生成某一系的多边形剪影。
func _shape_for(element: PBElement.Type) -> PackedVector2Array:
	var sides: int = ELEMENT_SIDES.get(element, 6)
	var points := PackedVector2Array()
	for i: int in sides:
		# -PI/2 让第一个顶点朝上，剪影的朝向才稳定。
		var angle: float = -PI / 2.0 + TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * ENEMY_RADIUS)
	return points
