class_name PBSkillOrders
extends RefCounted
## 玩家下了、但还没放出去的施法指令（§02）。零引擎依赖。
##
## 暂停操作的定义（BG2 / 正义之怒那一套）：**暂停时画面和状态都冻住，只收指令，而且能反悔**。
## 所以下令那一刻不扣蓝、不挂自增益、不记播报，攒到 tick 推进前一次放出。
##
## **实时和暂停走同一条路**：所有施法指令一律进这里，[method PBBattleSim.step] 在推进那一 tick
## **之前**放完。实时下达的下一个 tick 在 50 毫秒内就到，感觉不到差别；放的时机排在
## `_tick += 1` 之前，所以「排队再放」和「当场放」算出来的 `lands_at` 与冷却逐位相同。
##
## **一个人手上只攒一条**，后下的顶掉先下的。每个攻击者一格的定长数组，热路径零分配。
##
## **放出去那一刻重新过一遍门槛**：施法者死了、蓝不够了，整条丢掉。

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
	attackers: Array[PBAttacker], at: int, index: int, spot: Vector2, target_slot: int, tick: int
) -> bool:
	if at < 0 or at >= _index.size():
		return false
	var cast := PBSkillRules.cast_at(attackers[at], index)
	if cast == null or not PBSkillRules.can_cast(attackers[at], index, tick):
		return false
	if not _fits(cast.skill, spot, target_slot, attackers, attackers[at]):
		return false
	if _index[at] < 0:
		_count += 1
	_index[at] = index
	_spot[at] = spot
	_target[at] = target_slot
	return true


## 收回第 [param at] 个人手上那条指令。没有就什么都不做。
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
		if not _fits(cast.skill, _spot[at], _target[at], attackers, attacker):
			continue
		match cast.skill.target:
			PBSkill.Target.GROUND:
				cast.cast(_spot[at], tick)
			PBSkill.Target.ALLY, PBSkill.Target.ENEMY:
				cast.cast_on(_target[at], tick)
			_:
				cast.cast_now(tick)
		begin(attacker, cast, cfg, tick, book)
	_count = 0


## 起手预扣查克拉；有本体的单位等待第 4 帧才挂自身效果与记播报。
## 无本体的场外技能没有人物动作，仍当场释放。自动与手动共用此入口。
static func begin(
	attacker: PBAttacker, cast: PBSkillCast, cfg: PBSimConfig, tick: int, book: PBBattleLog
) -> void:
	if attacker.slot < 0:
		attacker.pay(PBSkillCostRules.mana(cast.skill, cast.caster_level))
		issue(attacker, cast, cfg, tick, book)
		return
	attacker.casting.begin(attacker, cast, cfg, tick)


## 第 4 帧释放，查克拉已在起手预扣。
static func issue(
	attacker: PBAttacker, cast: PBSkillCast, cfg: PBSimConfig, tick: int, book: PBBattleLog
) -> void:
	if cast.skill.channel_control or cast.skill.mind_control:
		if attacker.channel != null:
			attacker.channel.active = false
		attacker.channel = PBSkillChannel.new()
		attacker.channel.caster_ref = weakref(attacker)
		attacker.swinging = false
	cast.origin = attacker.pos
	PBSkillRules.apply_on_self(attacker, cast, cfg, tick)
	if book != null:
		book.ultimate(tick, attacker.slot, cast.skill.affects == PBSkill.Party.ALLIES)


## 这条指令配不配得上这个技能的档位，**要哪一样由 [member PBSkill.target] 说**：
## 地面档要落点、锁定队友要一个还站得住的人、点敌人要一个槽位、不挑目标的什么都不要。
##
## 点敌人那一档**只查槽位，不查死活**：从下令到子弹飞到隔着好几个 tick，
## 「目标没了就空放」在落地那一侧已经写好了（[method PBSkillRules.land_on_enemy]）。
static func _fits(
	skill: PBSkill,
	spot: Vector2,
	target_slot: int,
	attackers: Array[PBAttacker],
	caster: PBAttacker
) -> bool:
	match skill.target:
		PBSkill.Target.GROUND:
			return PBSkillCast.is_spot(spot)
		PBSkill.Target.ALLY:
			if target_slot < 0 or target_slot >= attackers.size():
				return false
			return PBSacrificeRules.can_target(skill, attackers[target_slot], caster)
		PBSkill.Target.ENEMY:
			return target_slot >= 0
		PBSkill.Target.NONE:
			return true
	return false
