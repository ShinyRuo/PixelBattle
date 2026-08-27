class_name PBBattleSim
extends RefCounted
## 单波战斗的**逐 tick** 模拟。M0 起取代 [PBCombatRules] 的解析式排队模型。
##
## 和排队模型的关系：**语义刻意保持一致，好让两者能对拍。**
## 排队模型是这个模型在「输出恒定、单目标、敌人不还手」前提下的闭式解，
## 所以同样输入下两者的结果应该很接近。`tests/test_battle_sim.gd` 里
## 有一组对拍断言把这个一致性锁住 —— 改坏任何一边都会红。
##
## ## 每个 tick 干四件事，顺序不能换
##
## 1. **激活到点出场的敌人** —— 没出场的打不了也不动
## 2. **分配伤害** —— 打最接近基地的，打死了溢出伤害接着打下一个
## 3. **推进位置** —— 先打后走：一个敌人在抵达那一 tick 仍然可以被打死，
##    这与排队模型的 `would_die_at <= arrives_at` 是同一条边界
## 4. **结算抵达基地的** —— 扣基地血，移出战场
##
## ## M0 还没有的东西
##
## - **AOE 与单体没有区别**：伤害只打最前面那个。这是和排队模型对拍的前提，
##   也是 §04 那条「纯 AOE 在精英波吃力」的验收仍然答不了的原因。技能是 M3
## - **敌人不还手**：只有漏怪伤基地，己方单位不会被打死
## - **没有射程和前中后列**：§02 的纵深要配合技能射程才有意义

## 安全阀：单波最多跑这么多 tick。
##
## 正常情况下战斗必定结束（敌人每 tick 都在前进，迟早抵达基地）。
## 这个上限是防「速度配成 0」之类的配置错误把批量模拟挂死 ——
## 死循环在跑几万局的场景里表现为「卡住不动」，极难定位。
const MAX_TICKS: int = 20000

var _cfg: PBSimConfig
var _wave: PBWave
var _enemies: Array[PBEnemy] = []
var _outcome: PBCombatOutcome

## 每 tick 己方打出的伤害总量。M0 的输出是恒定的 —— 前排先死导致输出下降
## 之类的波内动态要等真单位系统，那是 M3。
var _damage_per_tick: float = 0.0

## 一个敌人漏进基地扣多少血，防御科技减伤已经算进去了。
var _leak_damage: float = 0.0

var _enemy_speed: float = 0.0
var _tick: int = 0

## 队伍最前面那个还活着的敌人在 [member _enemies] 里的下标。
##
## 全体敌人同速前进、且按出场顺序排列，所以**数组顺序天然就是距离顺序** ——
## 不需要每 tick 排序找目标，从这个游标往后扫就行。
var _front: int = 0


func _init(wave: PBWave, dps: float, def_reduction: float, cfg: PBSimConfig) -> void:
	_cfg = cfg
	_wave = wave
	_outcome = PBCombatOutcome.new()
	_damage_per_tick = maxf(dps, 0.0) / float(cfg.tick_rate)

	var leak_mult: float = cfg.boss_leak_mult if wave.is_boss() else 1.0
	_leak_damage = wave.atk_each * leak_mult * (1.0 - clampf(def_reduction, 0.0, 0.95))

	# 速度由 march_seconds 反推：那个参数的含义本来就是「走完全场要多久」。
	# 这里没有引入新的拍脑袋参数，只是换了个表达。
	var march_ticks: float = maxf(cfg.march_seconds, 0.001) * float(cfg.tick_rate)
	_enemy_speed = cfg.field_length / march_ticks

	_spawn_all(wave, cfg)


## 推进一个 tick。战斗已结束时什么都不做。
func step() -> void:
	if is_finished():
		return
	_tick += 1
	_deal_damage()
	_advance_and_leak()


## 一路跑到战斗结束，返回结算结果。批量模拟走这个入口。
func run_to_end() -> PBCombatOutcome:
	while not is_finished() and _tick < MAX_TICKS:
		step()
	return result()


func is_finished() -> bool:
	return _front >= _enemies.size()


## 结算结果。战斗没结束也能取，拿到的是「到目前为止」的快照。
func result() -> PBCombatOutcome:
	_outcome.cleared = _outcome.leaked == 0 and is_finished()
	_outcome.ticks = _tick
	_outcome.battle_seconds = float(_tick) / float(_cfg.tick_rate)
	return _outcome


## 全部敌人，含还没出场和已经死掉的。**渲染层只读，不要改。**
func enemies() -> Array[PBEnemy]:
	return _enemies


func current_tick() -> int:
	return _tick


## 出场时刻已到、且还活着的敌人 —— 渲染层要画的就是这些。
func active_enemies() -> Array[PBEnemy]:
	var out: Array[PBEnemy] = []
	for enemy: PBEnemy in _enemies:
		if enemy.is_active(_tick):
			out.append(enemy)
	return out


## 一次性把整波敌人建好，出场时刻算在这里。
##
## 全部预分配、之后只改字段不再 `.new()` —— §14 对 sim 层的要求。
func _spawn_all(wave: PBWave, cfg: PBSimConfig) -> void:
	_enemies.resize(wave.count)
	var window_ticks: float = cfg.spawn_window * float(cfg.tick_rate)
	for i: int in wave.count:
		var enemy := PBEnemy.new()
		enemy.slot = i
		var at_tick: int = 0
		if wave.count > 1:
			at_tick = int(round(window_ticks * float(i) / float(wave.count - 1)))
		enemy.spawn(wave, _enemy_speed, cfg.field_length, at_tick)
		_enemies[i] = enemy


## 把这一 tick 的伤害打出去。打最接近基地的，溢出的接着打下一个。
##
## 溢出必须结算：高 DPS 一 tick 能打死好几个，漏掉溢出会让战斗时长
## 被系统性拉长，而那正是 §01「单波 30–45 秒」验收要看的数。
func _deal_damage() -> void:
	var remaining: float = _damage_per_tick
	var index: int = _front
	while remaining > 0.0 and index < _enemies.size():
		var enemy: PBEnemy = _enemies[index]
		if not enemy.is_active(_tick):
			# 后面的出场更晚，这一 tick 不会再有可打的目标了。
			break
		if not enemy.alive:
			index += 1
			continue
		var before: float = enemy.hp
		if enemy.take_damage(remaining):
			_outcome.kills += 1
			remaining -= before
			index += 1
		else:
			remaining = 0.0
	_skip_dead()


## 全体前进，抵达基地的算漏怪。
func _advance_and_leak() -> void:
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.is_active(_tick):
			break
		if not enemy.alive:
			continue
		if enemy.advance():
			enemy.alive = false
			_outcome.leaked += 1
			_outcome.base_damage += _leak_damage
	_skip_dead()


## 把游标推到下一个还活着的敌人。已经死掉或漏掉的不再参与任何计算。
func _skip_dead() -> void:
	while _front < _enemies.size() and not _enemies[_front].alive:
		_front += 1
