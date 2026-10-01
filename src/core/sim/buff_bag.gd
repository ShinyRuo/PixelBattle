class_name PBBuffBag
extends RefCounted
## **一个单位身上挂着的全部效果**。
##
## **不认识 [PBAttacker] 也不认识 [PBEnemy]**：收裸值、返回裸值，一份实现敌我两处用。
##
## **过期是查询时比 tick，不是扫描时删**：[method amount] 每次按 tick 过滤，那是真相；
## [method sweep] 只回收槽位，漏跑一次不改变任何结算结果。
##
## **普通槽位固定**（[PBBuffState] 随 bag 预分配）。满了顶掉剩余时间最短的 ——
## 丢掉新来的话表现是「我刚放的技能没生效」。
## 独立周期叠层使用额外可复用槽，只在并发层数达到新高时扩容，不设层数上限。

## 一个单位最多同时挂几个普通效果。独立周期叠层不计入这里。
## **超了不是错，是顶掉一个** —— 所以调大调小都不会让任何东西崩，
## 只会改变「同时挂很多个时哪一个先消失」。
const SLOTS: int = 32

## 状态改变后同步派生属性；接收者使用弱引用，避免效果袋与单位形成引用环。
var on_changed: Callable
var _slots: Array[PBBuffState] = []


func _init() -> void:
	_slots.resize(SLOTS)
	for i: int in SLOTS:
		_slots[i] = PBBuffState.new()


## 全部槽位，**含空的和已过期的**，调用方自己用 [method PBBuffState.is_live] 过滤 ——
## 返回筛过的新数组会在热路径上分配。**只读，不要改。**
func states() -> Array[PBBuffState]:
	return _slots


## 全部腾空。**开波、复用对象时必须调** —— 不调的话上一波的效果会漏进这一波，
## 而那和 [method PBSkillCast.reset] 顶上记着的「上一场剩下的冷却漏进下一场」
## 是同一个形状：不报任何错，只表现为「后半局怎么好像变了」。
func clear(at_tick: int = 0) -> void:
	for state: PBBuffState in _slots:
		state.clear()
	_changed(at_tick)


## 取消同 ID 的全部效果（含独立层），撤掉载荷后再通知派生属性读点。
func remove(id: StringName, at_tick: int, source_slot: int = -1) -> int:
	var removed: int = 0
	for state: PBBuffState in _slots:
		if (
			state.buff != null
			and state.buff.id == id
			and (source_slot < 0 or state.source_slot == source_slot)
		):
			state.clear()
			removed += 1
	if removed > 0:
		_changed(at_tick)
	return removed


## 挂一份上去。[param values] 是**已经按等级算完**的数值（[method PBBuffRules.resolve]）。
##
## **同 id 整份覆盖** —— 那就是「刷新时长」。不取「到期取较长者」：先挂的长弱档加后挂的短强档
## 会得到「强档持续很久」，比两者都好，没人要过那个东西。
func add(
	buff: PBBuff,
	values: Dictionary,
	at_tick: int,
	ticks: int,
	period: int,
	from_slot: int = -1,
	harm: PBHarmContext = null
) -> void:
	if buff == null or (ticks <= 0 and not buff.until_wave_end):
		return
	var seat: PBBuffState = (
		_stack_seat(at_tick) if buff.independent_stacks else _seat_for(buff, at_tick, from_slot)
	)
	seat.take(buff, values, at_tick, ticks, period, from_slot)
	seat.harm_context = harm
	_changed(at_tick)


## 这一 tick [param key] 合计是多少。率型连乘（空 = 1.0）、量型累加（空 = 0.0），
## 由 [method PBBuffRules.neutral] 与 [method PBBuffRules.fold] 定。
## 空 bag 返回精确的中性值，所以解析式对拍一位都不动。
func amount(key: StringName, at_tick: int) -> float:
	var out: float = PBBuffRules.neutral(key)
	for state: PBBuffState in _slots:
		if not state.is_live(at_tick):
			continue
		if state.mods.has(key):
			out = PBBuffRules.fold(key, out, float(state.mods[key]))
	return out


## 让身上挂着的护盾去吃这一下伤害，返回**剩下多少**。
##
## 护盾是唯一**会被消耗**的键，扣减只有这一个入口（敌我 take_damage 都调它）——
## 让调用方自己扣的话，漏扣一处的表现是「那条路上的护盾用不完」。
##
## 每份护盾有自己的时限，余量记在各自的 [member PBBuffState.mods] 上。
## **按槽位顺序吃**，不按剩余时间排（热路径上不排序）。吃光的那一份留在 0 上，清扫归 [method sweep]。
func absorb(
	amount: float, at_tick: int, kind: PBDamageKind.Type = PBDamageKind.Type.TAIJUTSU
) -> float:
	var left: float = amount
	if left <= 0.0:
		return left
	for state: PBBuffState in _slots:
		if left <= 0.0:
			break
		if not state.is_live(at_tick):
			continue
		for key: StringName in [PBBuffRules.SHIELD, PBBuffRules.NINJUTSU_SHIELD]:
			if key == PBBuffRules.NINJUTSU_SHIELD and kind != PBDamageKind.Type.NINJUTSU:
				continue
			var pool: float = maxf(float(state.mods.get(key, 0.0)), 0.0)
			if pool <= 0.0:
				continue
			var eaten: float = minf(pool, left)
			state.mods[key] = pool - eaten
			left -= eaten
	return left


## 当前还能吸收多少伤害。与 absorb 一样，只认有效且余量为正的护盾；只读，不消耗。
## 敌人的溢出伤害结算需要它，不能直接用血量当作击杀成本。
func shield_left(at_tick: int) -> float:
	var total: float = 0.0
	for state: PBBuffState in _slots:
		if state.is_live(at_tick):
			total += maxf(float(state.mods.get(PBBuffRules.SHIELD, 0.0)), 0.0)
	return total


## 现在挂着几份。**「身上有没有东西」也问这一个**（`count(t) > 0`）——
## 另开一个 `has_any` 就是同一个问题的第二个答案。
func count(at_tick: int) -> int:
	var live: int = 0
	for state: PBBuffState in _slots:
		if state.is_live(at_tick):
			live += 1
	return live


## 把过期的槽位腾出来。**纯回收**，漏跑不影响任何结算。
func sweep(at_tick: int) -> void:
	var changed: bool = false
	for state: PBBuffState in _slots:
		if state.buff != null and not state.is_live(at_tick):
			state.clear()
			changed = true
	if changed:
		_changed(at_tick)


func _changed(at_tick: int) -> void:
	if on_changed.is_valid():
		on_changed.call(at_tick)


## 这份 buff 该坐哪个槽：同 id 的那个 → 空的 → 剩余时间最短的那个。
func _seat_for(buff: PBBuff, at_tick: int, source: int) -> PBBuffState:
	var empty: PBBuffState = null
	var shortest: PBBuffState = null
	for i: int in SLOTS:
		var state: PBBuffState = _slots[i]
		if (
			state.buff != null
			and state.buff.id == buff.id
			and (not buff.per_source or state.source_slot == source)
		):
			return state
		if not state.is_live(at_tick):
			# 已过期的也算空，否则刚过期的槽位会白占一整 tick。
			if empty == null:
				empty = state
			continue
		if shortest == null or state.left(at_tick) < shortest.left(at_tick):
			shortest = state
	return empty if empty != null else shortest


## 独立层不互相顶掉，也不挤占普通槽。只在并发层数达到新高时扩容，过期槽复用。
## 与敌人 / 弹道固定上限不同，这里必须保留原规则的无限叠层语义。
func _stack_seat(at_tick: int) -> PBBuffState:
	for i: int in range(SLOTS, _slots.size()):
		if not _slots[i].is_live(at_tick):
			return _slots[i]
	var seat := PBBuffState.new()
	_slots.append(seat)
	return seat
