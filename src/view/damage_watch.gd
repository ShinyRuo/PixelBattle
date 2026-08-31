class_name PBDamageWatch
extends RefCounted
## 逐帧比对敌人血量，报出「这一帧谁挨了多少、谁死了」。M3.5-h。
##
## ## 为什么是渲染层比对，而不是让 sim 发事件
##
## 手感那三样（命中白闪、伤害飘字、击杀顿帧）要的都是**事件**：
## 「刚才挨了一下」「刚才死了一个」。而 [PBBattleSim] 里只有**状态**：
## 现在还剩多少血、还活着没有。
##
## 往 sim 里加一条伤害事件流是可以的，但代价完全不对等：
## 那是**给渲染层的方便去改一份确定性模拟** —— 事件要不要进存档、
## 批量扫描里几万局的事件要不要分配内存、回放对不对得上，全都要回答一遍。
## 而渲染层自己存一份上一帧的血量就够了，**它本来就是逐帧跑的**。
##
## ## 攒够了才飘一个数
##
## 逐 tick 的普攻每次只掉一点点血，每一下都飘字的话，一波潮水就是
## 一屏滚动的「3」。所以攒到 [constant MIN_FRACTION] 才飘一次 ——
## 飘出来的数因此是「这一小段时间他挨了多少」，而不是单次伤害。
##
## **死亡永远飘**，而且把攒着的那部分一起结掉：一个敌人最后一下掉的血
## 可能只有 1%，但那一下是玩家最想看到的一下。

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
	_hp.fill(0.0)
	_pending.fill(0.0)


## 比对一帧。返回这一帧**挨了打的**那些槽位，每条是
## `{"slot": int, "shown": float, "killed": bool}`。
##
## `shown` 是这一条该飘出来的数字，**0 表示还没攒够、这次只闪不飘**。
func poll(enemies: Array[PBEnemy], current_tick: int) -> Array[Dictionary]:
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
		out.append({"slot": slot, "shown": _take(slot, enemy, died), "killed": died})
	_ready = true
	return out


## 这一帧死了几个。击杀顿帧靠它。
func killed_this_frame() -> int:
	return _kills


## 攒够了（或者他死了）就把攒着的那笔取出来飘，否则返回 0。
func _take(slot: int, enemy: PBEnemy, died: bool) -> float:
	if not died and _pending[slot] < enemy.max_hp * MIN_FRACTION:
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
