class_name PBHitFeedback
extends RefCounted
## 手感那一段的接线：命中白闪、伤害飘字、击杀顿帧（§02）。
##
## **三样共用一份血量比对**（[PBDamageWatch]）：各比一遍的话「闪了但没飘字」这种半拍的不一致迟早出现。
## 它只吃这一帧的战斗状态，吐「往哪儿闪、往哪儿飘、顿几帧」，和阶段机、面板、输入一条都不沾。

## 击杀顿帧停多少个物理帧。60Hz 下 5 帧约 83 毫秒 ——
## 够让眼睛把「那一下」和前后分开，又短到不会读成掉帧。
const HITSTOP_FRAMES: int = 5

## 一波的最后一只死掉时停久一点。那一下是「这波过了」，值得一个更重的标点。
const HITSTOP_WAVE_FRAMES: int = 12

## 逐帧比对敌人血量，报出「谁挨了多少、谁死了」。见 [PBDamageWatch]。
var _watch := PBDamageWatch.new()

## 战斗播报**消化到第几条**。**-1 = 还没对齐**，见 [method _crit_slots]。
## 存的是 [member PBBattleLog.total] 而不是 `entries.size()`（理由见那个字段）。
var _seen: int = -1


## 走一帧。**返回这一帧该顿多少个物理帧**（0 = 不顿）。
##
## 由调用方去决定怎么顿 —— 顿帧只是几帧不推进，绝不跳 tick、
## 绝不碰 `Engine.time_scale`（那是 §12 存档回滚与 §13 每日种子的地基），
## 而「怎么不推进」是阶段机的事。
func poll(
	battle: PBBattleSim,
	wave: PBWave,
	pool: PBEnemyPool,
	floats: PBFloatTextPool,
	field: Vector2
) -> int:
	var enemies: Array[PBEnemy] = battle.enemies()
	var crits: Dictionary = _crit_slots(battle.log_to)
	for hit: Dictionary in _watch.poll(enemies, battle.current_tick(), crits):
		var slot: int = int(hit["slot"])
		pool.flash(slot)
		var shown: float = float(hit["shown"])
		if shown > 0.0:
			floats.pop(
				pool.screen_position(enemies[slot], field),
				shown,
				bool(hit["killed"]),
				bool(hit["crit"])
			)
	return _hitstop_for(battle, wave)


## 这一帧哪几个槽位吃了暴击 —— **从战斗播报读，不从血量比**：血量里混着暴击和易伤，
## 还会把几帧攒成一个数，那一层结构上分不出。**没有日志就没有暴击色**，不退回去猜。
func _crit_slots(book: PBBattleLog) -> Dictionary:
	var out: Dictionary = {}
	if book == null:
		return out
	# 还没对齐（刚换波），或者日志被整局清过（`total` 退回去了）：
	# 这一帧只对游标，不发暴击。**少一次比多一次好** —— 多的那一次
	# 会把上一波的暴击画在这一波刚出场的那个敌人身上。
	if _seen < 0 or _seen > book.total:
		_seen = book.total
		return out
	for i: int in range(book.fresh_from(_seen), book.entries.size()):
		var entry: Dictionary = book.entries[i]
		if int(entry.get("kind", -1)) != PBBattleLog.Kind.HIT_ENEMY:
			continue
		if bool(entry.get("crit", false)):
			out[int(entry["target"])] = true
	_seen = book.total
	return out


## 血量快照跟着新的一波从头来。
##
## 不清的话，开波第一帧会把「上一波那个槽位剩 3 点血」和「这一波满血」
## 的差算成一次巨额伤害 —— 表现是开波瞬间满屏飘字。
func reset() -> void:
	_watch.reset()
	# 播报的游标也要重新对齐：日志跨波留着（只保留一局），
	# 不对齐的话开波第一帧会把上一波末尾那几条暴击补画一遍。
	_seen = -1


## 顿帧只给**看得出来的那几下**。
##
## 潮水波一秒能死七八个，每个都顿一下就是持续抖动 —— 那时顿帧不再是强调，
## 而是卡顿。所以只在两种情况下顿：
##
## 1. **精英 / BOSS 波的击杀** —— 那种波一波才几只，每一只都是事件
## 2. **一波的最后一只** —— 无论什么波型，那一下是「这波过了」
func _hitstop_for(battle: PBBattleSim, wave: PBWave) -> int:
	if _watch.killed_this_frame() <= 0:
		return 0
	var out: PBCombatOutcome = battle.result()
	if out.kills + out.leaked >= wave.count:
		return HITSTOP_WAVE_FRAMES
	if wave.shape != PBWave.Shape.SWARM and wave.shape != PBWave.Shape.NORMAL:
		return HITSTOP_FRAMES
	return 0
