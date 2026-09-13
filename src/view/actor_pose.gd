class_name PBActorPose
extends RefCounted
## 一个战场单位**这一帧该播哪段动画、朝哪边**。
##
## **sim 里只有状态，动画要的是事件**（同 [PBDamageWatch]）：渲染层自己存一份上一帧的位置和出手时刻。
## **不碰 sim 的任何字段**，[method update] 收的全是裸值 —— 敌我一份实现两处用。
##
## **每一档都要「赖」几帧**：sim 20 tick/s、画面 60 帧，三帧里只有一帧位置会变，照直比会 run/idle 地闪。
## 所以记一个倒计时，事件把它顶满，之后一帧帧退。

enum State {
	IDLE,  ## 站着
	RUN,  ## 在挪
	ATTACK,  ## 刚出了一手
	CAST,  ## 大招已经点了落点、还没落地（[method PBSkillCast.is_pending]）
	DEAD,  ## 倒了。**不隐藏** —— 见 [constant PBAllyPool.DEAD_COLOR]
}

const FACE_RIGHT: int = 1
const FACE_LEFT: int = -1

## 挪过之后跑步动画还赖几帧。要盖得住一个 tick 的空档（60/20 = 3 帧），
## 6 帧留了一倍余量 —— 少了会闪，多了会让一个已经站定的人多跑两步。
const MOVE_HOLD: int = 6

## 算不算「在挪」的判据，单位是战场坐标（整条战场是 1.0）。
## 0.001 是一步的八分之一：真走路（约 0.0083/tick）稳稳在它之上，被皮带绳夹在绳边、跟着目标一丝丝滑动
## 稳稳在它之下 —— 判据太小的话人站在原地播一整场跑步动画。
const MOVE_EPSILON: float = 0.001

var state: int = State.IDLE

## 朝左还是朝右（[constant FACE_RIGHT] / [constant FACE_LEFT]），
## **屏幕方向**：战场 x 增大就是屏幕向右（见 [method PBLayout.to_screen]）。
## 忍者站在 x 小的那一侧、敌人从 x 大的那一侧来，所以两边的默认朝向相反。
var facing: int = FACE_RIGHT

## **这一帧是一次新挥击的起点**，池子看见它就把动画拨回第 0 帧。
## [method AnimatedSprite2D.play] 对已经在播的同一段什么都不做，而交战期间攻击状态是连着的 ——
## 两个周期一样长，相位一旦对不上就永远对不上，表现是「子弹在动作开头就射出去了」。
var swing_began: bool = false

var _was_winding: bool = false
var _prev_pos: Vector2 = Vector2.INF
var _prev_shot: int = -1
var _attack_left: int = 0
var _move_left: int = 0


## 这一段播完之后**停在最后一帧**，还是从头再演一遍。**只有倒地那一档停住**（终态）。
##
## 判据是状态，不是 [SpriteFrames] 的循环标志：非循环段演完之后 [AnimatedSprite2D] 只是停下，
## 而 `play()` 在「停在最后一帧」时会从头重来 —— 每帧调 `play` 的渲染层会把它变回循环（尸体在地上抽搐）。
## 攻击段要靠「上一遍演完了」触发下一遍，所以不能一概停住。敌人死了整个节点就藏了，不需要这一条。
static func holds_last(state_now: int) -> bool:
	return state_now == State.DEAD


## 起手占几**渲染帧**。[param windup_ticks] 是 sim 的起手长度（[member PBAttacker.windup_ticks]），
## [param per_tick] 是一 tick 摊几个渲染帧。**来自 sim，不从动画量** —— 否则子弹比挥手早半拍。
static func windup_frames(windup_ticks: int, per_tick: float) -> int:
	return maxi(roundi(float(windup_ticks) * maxf(per_tick, 0.0001)), 0)


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
	_was_winding = false
	swing_began = false


## 推进一帧。
##
## - [param shot_at] 传 `next_shot_at`，**它变大就是刚出了一手**。
## - [param look_at] 是他要看的那个东西的战场 x；[constant @GDScript.NAN] 表示照移动方向看，站着不动保持原朝向。
## - [param attack_hold] 是攻击动画该占几帧（一整个攻击间隔，[method PBAllyPool._hold_frames]）。
## - [param in_range] 是他这一刻够不够得着，**没有默认值**。「刚出过一手」挂到下一手，而 sim 中途可能已经让他
##   跑起来 —— 够不着就不算在打，否则是挥着手滑行。判据用 sim 的结论（己方 `can_reach(aim_at)`，
##   敌人 [member PBEnemy.engaged]），不拿位移大小去猜（防挤的推动和走路一 tick 的位移分不开）。
## - [param swinging] 直接读 [member PBAttacker.swinging]，不拿 `next_shot_at` 反推（收招和起手期间是同一个数）。
##   [param windup] 是起手占几帧，只用来算收招还剩多长。给 false / 0 就是不起手。
func update(
	at: Vector2,
	alive: bool,
	shot_at: int,
	casting: bool,
	look_at: float,
	attack_hold: int,
	in_range: bool,
	swinging: bool = false,
	windup: int = 0
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

	# **上升沿：抬手那一帧。** sim 那边冷却转好 + 射程内有人就抬手
	# （[method PBAttacker.begin_swing]），这边照着它起跑。
	# 持续为真的话每帧都会把动画拨回第 0 帧，持续为真的话每帧都会把动画拨回第 0 帧，
	# 人就永远停在起手那一格上。
	swing_began = swinging and not _was_winding
	_was_winding = swinging

	# 第一帧不算出手：那时手上还没有「上一次是第几 tick」这个参照。
	if _prev_shot >= 0 and shot_at > _prev_shot:
		# 出手了，剩下的是收招。**减掉起手那一段** —— 不减的话每一手都会
		# 占满一整个间隔再加上起手，两手之间的攻击段首尾相接，
		# 人从此再也回不到待机。
		_attack_left = maxi(attack_hold - windup, 1)
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
	elif (swinging or _attack_left > 0) and in_range:
		# **够不着就不算在打**（见 [param in_range]）。倒计时不清零：到位之后要么立刻出新的一手，
		# 要么还没到，中途清掉只会多一次状态跳变。
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
