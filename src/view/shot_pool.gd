class_name PBShotPool
extends Node2D
## 战场上飞行中的子弹。§02，M4-b。
##
## ## 它画的是 sim 里真有的东西
##
## 渲染层可以很便宜地伪造一道弹道：每隔几帧从射手往目标画一条线就行。
## 但那会撒谎 —— 伤害早在几帧前就结算完了，子弹会飞向一具尸体，
## 而射速和真实输出没有任何关系。所以子弹是 [PBProjectile]，
## 这里只负责把它的位置画出来，一个字段都不回写（§14）。
##
## ## 画成一个小方块，不是一条线
##
## 线要有起点，而起点是「射手上一帧在哪」—— 那是渲染层得自己记的第二份状态。
## 一个点只需要 [member PBProjectile.pos]，而 `640×360` 下 3 像素的方块
## 已经看得清是什么在动了。**颜色不分属性**：属性色是给单位用的
## （§02 的第一层视觉编码），子弹也上色的话，一屏的小方块会和敌人抢辨识。

## 子弹的边长（像素）。比敌人（半径 5）和己方（11×11）都小一档 ——
## 它是过程不是单位，抢眼会让人以为场上多了一堆东西。
const SIZE: Vector2 = Vector2(3.0, 3.0)

## 己方的子弹是暖白的，敌人的是暗红的（M4-c）。
##
## **必须分得开。** 两边同色的话，一屏小方块里读不出「有几发正朝我飞」，
## 而那正是敌人分远近之后玩家唯一需要的新信息 —— 前排挡得住近战，
## 挡不住站在后面射的那一批。
const COLOR := Color(0.96, 0.94, 0.72, 0.95)
const ENEMY_COLOR := Color(0.95, 0.42, 0.38, 0.95)

var _dots: Array[ColorRect] = []


func _ready() -> void:
	# 按 sim 那边的池子上限一次建满，之后只改属性和 visible（§14）。
	for _i: int in PBBattleSim.SHOT_CAPACITY:
		var dot := ColorRect.new()
		dot.size = SIZE
		dot.color = COLOR
		dot.visible = false
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		_dots.append(dot)


## 把池子同步到 sim 的子弹上。每渲染帧调一次。
##
## [param shots] 是 [method PBBattleSim.shots] 给的只读数组 ——
## **下标不是身份**，回池的子弹会被下一发复用，所以这里按「第几个还活着」
## 顺序填格子，不按下标对齐。子弹没有血条也没有选中态，认不认得出是同一发
## 对画面没有区别。
func sync_shots(shots: Array[PBProjectile], field: Vector2) -> void:
	var shown: int = 0
	for shot: PBProjectile in shots:
		if not shot.alive or shown >= _dots.size():
			continue
		var dot: ColorRect = _dots[shown]
		dot.visible = true
		dot.color = ENEMY_COLOR if shot.at_ally else COLOR
		dot.position = PBEnemyPool.to_screen(shot.pos, field) - SIZE * 0.5
		shown += 1
	for i: int in range(shown, _dots.size()):
		_dots[i].visible = false


## 一发都不画（准备阶段还没有战场，本局结束之后也没有）。
func clear() -> void:
	for dot: ColorRect in _dots:
		dot.visible = false
