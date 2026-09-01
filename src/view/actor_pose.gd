class_name PBActorPose
extends RefCounted
## 一个战场单位**这一帧该播哪段动画、朝哪边**。M6-b。
##
## ## sim 里只有状态，动画要的是事件
##
## 和 [PBDamageWatch] 是同一条路子：sim 记的是「现在还剩多少血 / 下一发在第几
## tick」这种**状态**，而「他刚才打了一下」「他正在跑」是**事件**。
## 往 sim 里加一条动画事件流的代价完全不对等（进不进存档、几万局扫描要不要
## 分配、回放对不对得上全要回答一遍），而渲染层本来就是逐帧跑的 ——
## 自己存一份上一帧的位置和出手时刻就够了。
##
## **所以这个类不碰 sim 的任何一个字段**：[method update] 收的全是裸值。
## 敌我两边字段名不同（[PBAttacker] 有 `alive` 和大招，[PBEnemy] 没有），
## 收裸值才能一份实现两处用 —— 两套的话「跑步动画的判定」迟早在两边分叉。
##
## ## 为什么每一档都要「赖」几帧
##
## sim 是 20 tick/s，画面是 60 帧 —— **三帧里只有一帧位置会变**。
## 照直比「这一帧动了吗」，跑起来的人会 1 帧 run、2 帧 idle 地闪。
## 出手同理：一次出手只在一个帧上是「刚发生」。
## 所以两档都记一个倒计时，事件把它顶满，之后一帧帧退。

enum State {
	IDLE,  ## 站着
	RUN,  ## 在挪
	ATTACK,  ## 刚出了一手
	CAST,  ## 大招已经点了落点、还没落地（[method PBUltimate.is_pending]）
	DEAD,  ## 倒了。**不隐藏** —— 见 [constant PBAllyPool.DEAD_COLOR]
}

const FACE_RIGHT: int = 1
const FACE_LEFT: int = -1

## 挪过之后跑步动画还赖几帧。要盖得住一个 tick 的空档（60/20 = 3 帧），
## 6 帧留了一倍余量 —— 少了会闪，多了会让一个已经站定的人多跑两步。
const MOVE_HOLD: int = 6

## 位置变没变的判据。战场坐标一格是 1.0，`1e-6` 远小于任何一 tick 的位移。
const MOVE_EPSILON: float = 1e-6

var state: int = State.IDLE

## 朝左还是朝右（[constant FACE_RIGHT] / [constant FACE_LEFT]），
## **屏幕方向**：战场 x 增大就是屏幕向右（见 [method PBLayout.to_screen]）。
## 忍者站在 x 小的那一侧、敌人从 x 大的那一侧来，所以两边的默认朝向相反。
var facing: int = FACE_RIGHT

var _prev_pos: Vector2 = Vector2.INF
var _prev_shot: int = -1
var _attack_left: int = 0
var _move_left: int = 0


## 复位到 [param at]，默认朝 [param face]。上场、开波、换人时调。
##
## [member _prev_shot] 要一起清掉：不清的话开波那一下
## （[method PBAttacker.revive] 把 `next_shot_at` 重排过）会被当成一次出手。
func reset(at: Vector2, face: int) -> void:
	state = State.IDLE
	facing = face
	_prev_pos = at
	_prev_shot = -1
	_attack_left = 0
	_move_left = 0


## 推进一帧。
##
## [param shot_at] 传 `next_shot_at` —— **它变大就是刚出了一手**。
## 出手在 sim 里没有事件，但「下一发挪后了」这件事只有出手才做得到。
## [param look_at] 是他要看的那个东西的战场 x；给 [constant @GDScript.NAN]
## 表示「没有目标，照移动方向看」，站着不动时保持原朝向。
## [param attack_hold] 是攻击动画该占几帧，由攻击间隔换算（见
## [method PBAllyPool._hold_frames]）。
func update(
	at: Vector2, alive: bool, shot_at: int, casting: bool, look_at: float, attack_hold: int
) -> void:
	if _prev_pos == Vector2.INF:
		_prev_pos = at
	var step: Vector2 = at - _prev_pos
	_prev_pos = at
	var moved: bool = step.length_squared() > MOVE_EPSILON * MOVE_EPSILON

	if moved:
		_move_left = MOVE_HOLD
	elif _move_left > 0:
		_move_left -= 1

	# 第一帧不算出手：那时手上还没有「上一次是第几 tick」这个参照。
	if _prev_shot >= 0 and shot_at > _prev_shot:
		_attack_left = maxi(attack_hold, 1)
	elif _attack_left > 0:
		_attack_left -= 1
	_prev_shot = shot_at

	_look(step, look_at, at.x)

	if not alive:
		state = State.DEAD
		_attack_left = 0
		_move_left = 0
	elif casting:
		state = State.CAST
	elif _attack_left > 0:
		state = State.ATTACK
	elif _move_left > 0:
		state = State.RUN
	else:
		state = State.IDLE


## 朝向两档：**有目标看目标，没目标看走向**，都没有就保持原样。
##
## 保持原样这一条不是偷懒：一个站定待机的人没有任何新信息说他该转身，
## 而每帧重算一个默认值会让他在目标死掉的那一瞬间「唰」地转回去。
func _look(step: Vector2, look_at: float, own_x: float) -> void:
	if is_finite(look_at) and absf(look_at - own_x) > MOVE_EPSILON:
		facing = FACE_RIGHT if look_at > own_x else FACE_LEFT
		return
	if absf(step.x) > MOVE_EPSILON:
		facing = FACE_RIGHT if step.x > 0.0 else FACE_LEFT
