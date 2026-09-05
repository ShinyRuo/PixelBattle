class_name PBSkillOrders
extends RefCounted
## 玩家下了、但还没放出去的施法指令（§02，M7-h）。零引擎依赖。
##
## ## 为什么指令要先攒着
##
## 《博德之门2》/《正义之怒》那套暂停操作的定义是：**暂停时画面和状态都冻住，
## 只收指令。** 在这之前本项目是反过来的 —— 玩家在暂停里点一下，蓝当场扣、
## 自增益当场挂、播报当场多一行、落点圈当场亮起，而且**反悔不了**。
## 「同时放」倒是早就成立（暂停时 tick 不推进，几发的 `lands_at` 是同一个数），
## 所以这一步买的不是同时性，是**「暂停时状态一个字都不变」和「能反悔」**。
##
## ## 实时和暂停走同一条路
##
## 不分「暂停时排队、平时直接放」两条 —— 那是两把尺子，而这个项目为这种形状
## 付过三次代价（M3.5-i 那三条）。所有施法指令一律进这里，
## [method PBBattleSim.step] 在推进那一 tick **之前**一次放完：
##
## - 实时下达：下一个 tick 在 50 毫秒内就到，玩家感觉不到差别
## - 暂停下达：tick 不跑，指令攒着；取消暂停后第一个 tick 全部放出
##
## **放的时机排在 `_tick += 1` 之前**，所以「排队再放」和「当场放」
## 算出来的 `lands_at` 与冷却**逐位相同** —— 这一步因此不改任何配平数字。
##
## ## 一个人手上只攒一条
##
## 后下的顶掉先下的（同 War3 / BG2：新指令替换当前动作）。于是这里是
## **每个攻击者一格的定长数组**，热路径零分配（§14），
## 而「最多攒几条」是结构性的，不是拍出来的一个上限。
##
## ## 放出去那一刻要重新过一遍门槛
##
## 施法者死了、目标死了、蓝不够了，整条丢掉。暂停期间这些都不会变，
## 但实时下达时中间隔着一个 tick —— 而「下令时能放、轮到放时不能了」
## 正是这条重新检查要挡的东西。

## 每个攻击者攒着的是第几格技能（[method PBSkillRules.cast_at] 的下标）。
## **-1 = 这个人手上没有指令。**
##
## 三条平行的定长数组而不是一个指令对象的数组：这一份每 tick 都要扫一遍，
## 而 §14 要求 sim 层的热路径不 `.new()`（同 [PBTelegraphPool] 那三条）。
var _index: PackedInt32Array = PackedInt32Array()

## 地面档（[constant PBSkill.Target.GROUND]）的落点。
var _spot: PackedVector2Array = PackedVector2Array()

## 锁定档（[constant PBSkill.Target.ALLY]）锁的那个己方单位的槽位。
##
## 存槽位不存引用，和 [member PBSkillCast.target_slot] 同一条规矩（§12 的存档）。
var _target: PackedInt32Array = PackedInt32Array()

## 现在攒着几条。**扫描那一路恒为 0**，[method flush] 因此直接早退 ——
## 一局几万 tick，不能让一条没人用的功能在每个 tick 上留下痕迹。
var _count: int = 0


## 开波：按人数重建指令位，全部清空。
func reset(size: int) -> void:
	_index.resize(size)
	_spot.resize(size)
	_target.resize(size)
	for i: int in size:
		_index[i] = -1
		_spot[i] = PBSkillCast.NO_SPOT
		_target[i] = -1
	_count = 0


## 玩家给第 [param at] 个攻击者下了第 [param index] 格技能的令。收下了返回 true。
##
## [param spot] 只有地面档看，[param target_slot] 只有锁定档看 ——
## 哪一档看哪个由**技能自己**说（[member PBSkill.target]），
## 不由调用方分档：分了就是第二份真相，而它和技能表可以分叉。
func place(
	attackers: Array[PBAttacker],
	at: int,
	index: int,
	spot: Vector2,
	target_slot: int,
	tick: int
) -> bool:
	if at < 0 or at >= _index.size():
		return false
	var cast := PBSkillRules.cast_at(attackers[at], index)
	if cast == null or not PBSkillRules.can_cast(attackers[at], index, tick):
		return false
	if not _fits(cast.skill, spot, target_slot, attackers):
		return false
	if _index[at] < 0:
		_count += 1
	_index[at] = index
	_spot[at] = spot
	_target[at] = target_slot
	return true


## 收回第 [param at] 个人手上那条指令。没有就什么都不做。
##
## **反悔这条路是暂停操作的一半意义**：暂停里下的令还没生效，
## 而在这之前玩家点下去那一刻蓝就已经扣了。
func cancel(at: int) -> void:
	if at < 0 or at >= _index.size() or _index[at] < 0:
		return
	_index[at] = -1
	_count -= 1


## 第 [param at] 个人攒着的是第几格技能。**-1 = 没有。** 渲染层读这个画反馈。
func index_of(at: int) -> int:
	return _index[at] if at >= 0 and at < _index.size() else -1


## 第 [param at] 条指令的落点（地面档）。
func spot_of(at: int) -> Vector2:
	return _spot[at] if at >= 0 and at < _spot.size() else PBSkillCast.NO_SPOT


## 第 [param at] 条指令锁的那个人（锁定档的槽位，-1 = 没锁）。
func target_of(at: int) -> int:
	return _target[at] if at >= 0 and at < _target.size() else -1


## 现在攒着几条。
func count() -> int:
	return _count


## 把攒着的全部放出去。**每个 tick 推进之前调一次**，见类顶部。
func flush(attackers: Array[PBAttacker], cfg: PBSimConfig, tick: int, book: PBBattleLog) -> void:
	if _count == 0:
		return
	for at: int in _index.size():
		var index: int = _index[at]
		if index < 0:
			continue
		_index[at] = -1
		var attacker: PBAttacker = attackers[at]
		var cast := PBSkillRules.cast_at(attacker, index)
		if cast == null or not PBSkillRules.can_cast(attacker, index, tick):
			continue
		if not _fits(cast.skill, _spot[at], _target[at], attackers):
			continue
		match cast.skill.target:
			PBSkill.Target.GROUND:
				cast.cast(_spot[at], tick)
			PBSkill.Target.ALLY, PBSkill.Target.ENEMY:
				cast.cast_on(_target[at], tick)
			_:
				cast.cast_now(tick)
		issue(attacker, cast, cfg, tick, book)
	_count = 0


## 下达之后共同要做的三件事：扣蓝、挂自增益、记播报。
##
## **自动档（[PBAimRules] 替玩家挑落点那一支）也走这里** —— 两条路各写一份的话
## 「手放的技能扣蓝、自动放的不扣」这种分叉迟早出现，而它不报错。
##
## 蓝在**下达**时扣，不是落地时 —— 落地时扣的话，施法延迟那段窗口里
## 还能再下达一发（蓝还没扣掉），于是延迟越长反而放得越多，
## 和冷却从落地算是同一个道理。
##
## [member PBSkill.on_self] 同理挂在这一刻（M7-c）：人已经把技能交出去了，
## 自增益却要等落地才生效的话，玩家看到的是「按下去没反应」。
##
## 播报也记在这一刻（M6-j）：玩家点下去就该看见回音，
## 而落地还隔着一整段施法延迟（那段延迟正是 §02 要的预判窗口）。
static func issue(
	attacker: PBAttacker, cast: PBSkillCast, cfg: PBSimConfig, tick: int, book: PBBattleLog
) -> void:
	attacker.pay(cast.skill.mp_cost)
	PBSkillRules.apply_on_self(attacker, cast, cfg, tick)
	if book != null:
		book.ultimate(tick, attacker.slot, cast.skill.affects == PBSkill.Party.ALLIES)


## 这条指令配不配得上这个技能的档位。
##
## 四档各要一样东西，而**要哪一样由 [member PBSkill.target] 说**：
## 地面档要一个真落点、锁定队友那档要一个还站得住的人、点敌人那档要一个槽位、
## 不挑目标的那一档什么都不要。
##
## ## 点敌人那一档只查槽位，不查他还活着没有（M8-b）
##
## 查了也没用：从下令到放出去中间隔着一个 tick，从放出去到子弹飞到
## 还隔着一整段飞行 —— 那个人随时可能死。**「目标没了就空放」这条
## 在落地那一侧已经写好了**（[method PBSkillRules.land_on_enemy]、
## [method PBShotRules._hit_enemy]），在这儿再判一次只会给出
## 「下令那一刻他还活着」这种没人需要的保证。
static func _fits(
	skill: PBSkill, spot: Vector2, target_slot: int, attackers: Array[PBAttacker]
) -> bool:
	match skill.target:
		PBSkill.Target.GROUND:
			return PBSkillCast.is_spot(spot)
		PBSkill.Target.ALLY:
			if target_slot < 0 or target_slot >= attackers.size():
				return false
			return attackers[target_slot].is_targetable()
		PBSkill.Target.ENEMY:
			return target_slot >= 0
		PBSkill.Target.NONE:
			return true
	return false
