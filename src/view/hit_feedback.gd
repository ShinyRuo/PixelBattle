class_name PBHitFeedback
extends RefCounted
## 手感那一段的接线：命中白闪、伤害飘字、击杀顿帧。§02，M3.5-h。
##
## ## 三样必须共用一份血量比对
##
## 它们的输入是同一件事：「刚才谁挨了多少、谁死了」。而 sim 里**只有状态**
## （现在还剩多少血），没有事件 —— 往 sim 加一条伤害事件流的代价完全不对等
## （进不进存档、几万局扫描要不要分配、回放对不对得上全要回答一遍），
## 而渲染层本来就是逐帧跑的，自己存一份上一帧的血量就够了（[PBDamageWatch]）。
##
## 各比一遍的话，「闪了但没飘字」「飘了字但没顿帧」这种半拍的不一致
## 迟早出现，而它看起来只是「反馈有时候会漏」。
##
## ## 为什么从 [PBBattleView] 里搬出来
##
## 直接的触发是那个文件又破了 1000 行上限，而这一块是最好切的一刀：
## 它只吃「这一帧的战斗状态」，吐「往哪儿闪、往哪儿飘、顿几帧」，
## 和阶段机、面板、输入一条都不沾。

## 击杀顿帧停多少个物理帧。60Hz 下 5 帧约 83 毫秒 ——
## 够让眼睛把「那一下」和前后分开，又短到不会读成掉帧。
const HITSTOP_FRAMES: int = 5

## 一波的最后一只死掉时停久一点。那一下是「这波过了」，值得一个更重的标点。
const HITSTOP_WAVE_FRAMES: int = 12

## 逐帧比对敌人血量，报出「谁挨了多少、谁死了」。见 [PBDamageWatch]。
var _watch := PBDamageWatch.new()


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
	for hit: Dictionary in _watch.poll(enemies, battle.current_tick()):
		var slot: int = int(hit["slot"])
		pool.flash(slot)
		var shown: float = float(hit["shown"])
		if shown > 0.0:
			floats.pop(pool.screen_position(enemies[slot], field), shown, bool(hit["killed"]))
	return _hitstop_for(battle, wave)


## 血量快照跟着新的一波从头来。
##
## 不清的话，开波第一帧会把「上一波那个槽位剩 3 点血」和「这一波满血」
## 的差算成一次巨额伤害 —— 表现是开波瞬间满屏飘字。
func reset() -> void:
	_watch.reset()


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
