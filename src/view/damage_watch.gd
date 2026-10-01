class_name PBDamageWatch
extends RefCounted
## 逐帧比对敌人血量，报出「这一帧谁挨了多少、谁死了」。
##
## **渲染层比对，不让 sim 发事件**：手感要的是事件，而 [PBBattleSim] 里只有状态。往确定性模拟里加事件流
## 要回答进不进存档、扫描要不要分配、回放对不对得上；渲染层本来就逐帧跑，存一份上一帧的血量就够了。
##
## **攒够了才飘一个数**（[constant MIN_FRACTION]）：逐 tick 的小伤害每下都飘就是一屏滚动的「3」。
## **死亡永远飘**，把攒着的一起结掉 —— 最后一下可能只掉 1%，但那是玩家最想看到的一下。

## 攒够满血的百分之几才飘一个数。
const MIN_FRACTION: float = 0.12

## 上一帧每个槽位的血量。下标就是 [member PBEnemy.slot]。
var _hp: PackedFloat64Array = PackedFloat64Array()

## 已经挨了但还没飘出来的累计伤害。
var _pending: PackedFloat64Array = PackedFloat64Array()

var _alive: PackedByteArray = PackedByteArray()
var _ready: bool = false
var _kills: int = 0


## 新的一波（或者换了一局）：忘掉上一场的血量快照。
##
## 不清的话，开波第一帧会把「上一波那个槽位剩 3 点血」和
## 「这一波这个槽位满血」的差算成一次治疗（负伤害），
## 或者反过来算成一次巨额伤害 —— 开波瞬间满屏飘字。
func reset() -> void:
	_ready = false
	_kills = 0
	# 攒着但还没飘出来的那一笔也要扔掉 —— 留着的话开波第一次飘字里
	# 会掺进上一波的一截伤害，而它看起来只是「这一下打得有点多」。
	_hp.fill(0.0)
	_pending.fill(0.0)


## 比对一帧。返回这一帧**挨了打的**槽位，每条是 `{"slot": int, "shown": float, "killed": bool, "crit": bool}`。
## `shown` 为 0 表示还没攒够、这次只闪不飘。
##
## [param crit_slots] 是这一帧吃了暴击的槽位（[method PBHitFeedback._crit_slots] 从播报读出来）。
## 暴击那一下**强制结算攒着的那笔**，理由同「死亡永远飘」。
func poll(
	enemies: Array[PBEnemy], current_tick: int, crit_slots: Dictionary = {}
) -> Array[Dictionary]:
	_fit(enemies.size())
	_kills = 0
	var out: Array[Dictionary] = []
	for enemy: PBEnemy in enemies:
		var slot: int = enemy.slot
		if slot < 0 or slot >= _hp.size():
			continue
		# 还没出场的不比 —— 它满血挂在那儿，出场那一帧会被算成零伤害，
		# 但「上一帧」这个概念对它还不成立，先把快照对齐再说。
		if not enemy.has_spawned(current_tick):
			_hp[slot] = enemy.hp
			_alive[slot] = 1 if enemy.alive else 0
			continue
		var was_alive: bool = _alive[slot] == 1
		var lost: float = _hp[slot] - enemy.hp
		var died: bool = was_alive and not enemy.alive
		_hp[slot] = enemy.hp
		_alive[slot] = 1 if enemy.alive else 0
		if not _ready:
			continue
		if died:
			_kills += 1
		if lost <= 0.0 and not died:
			continue
		_pending[slot] += maxf(lost, 0.0)
		var crit: bool = crit_slots.has(slot)
		(
			out
			. append(
				{
					"slot": slot,
					"shown": _take(slot, enemy, died or crit),
					"killed": died,
					"crit": crit,
				}
			)
		)
	_ready = true
	return out


## 这一帧死了几个。击杀顿帧靠它。
func killed_this_frame() -> int:
	return _kills


## 攒够了（或者他死了、或者刚吃了一发暴击）就把攒着的那笔取出来飘，否则返回 0。
func _take(slot: int, enemy: PBEnemy, forced: bool) -> float:
	if not forced and _pending[slot] < enemy.max_hp * MIN_FRACTION:
		return 0.0
	var shown: float = _pending[slot]
	_pending[slot] = 0.0
	return shown


func _fit(size: int) -> void:
	if _hp.size() >= size:
		return
	_hp.resize(size)
	_pending.resize(size)
	_alive.resize(size)
