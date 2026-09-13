class_name PBBuffBag
extends RefCounted
## **一个单位身上挂着的全部效果**。
##
## **不认识 [PBAttacker] 也不认识 [PBEnemy]**：收裸值、返回裸值，一份实现敌我两处用。
##
## **过期是查询时比 tick，不是扫描时删**：[method amount] 每次按 tick 过滤，那是真相；
## [method sweep] 只回收槽位，漏跑一次不改变任何结算结果。
##
## **槽位固定**（[PBBuffState] 随 bag 预分配，热路径不 `.new()`）。满了顶掉剩余时间最短的 ——
## 丢掉新来的话表现是「我刚放的技能没生效」。

## 一个单位最多同时挂几个。六个是拍的，但它有一条硬性质：
## **超了不是错，是顶掉一个** —— 所以调大调小都不会让任何东西崩，
## 只会改变「同时挂很多个时哪一个先消失」。
const SLOTS: int = 6

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
func clear() -> void:
	for state: PBBuffState in _slots:
		state.clear()


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
	from_slot: int = -1
) -> void:
	if buff == null or ticks <= 0:
		return
	var seat: PBBuffState = _seat_for(buff.id, at_tick)
	seat.take(buff, values, at_tick, ticks, period, from_slot)


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
## 护盾是唯一**会被消耗**的键，扣减只有这一个入口（[method PBAttacker.take_damage] 调它）——
## 让调用方自己扣的话，漏扣一处的表现是「那条路上的护盾用不完」。
##
## 每份护盾有自己的时限，余量记在各自的 [member PBBuffState.mods] 上。
## **按槽位顺序吃**，不按剩余时间排（热路径上不排序）。吃光的那一份留在 0 上，清扫归 [method sweep]。
func absorb(amount: float, at_tick: int) -> float:
	var left: float = amount
	if left <= 0.0:
		return left
	for state: PBBuffState in _slots:
		if left <= 0.0:
			break
		if not state.is_live(at_tick) or not state.mods.has(PBBuffRules.SHIELD):
			continue
		var pool: float = float(state.mods[PBBuffRules.SHIELD])
		if pool <= 0.0:
			continue
		var eaten: float = minf(pool, left)
		state.mods[PBBuffRules.SHIELD] = pool - eaten
		left -= eaten
	return left


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
	for state: PBBuffState in _slots:
		if state.buff != null and not state.is_live(at_tick):
			state.clear()


## 这份 buff 该坐哪个槽：同 id 的那个 → 空的 → 剩余时间最短的那个。
func _seat_for(id: StringName, at_tick: int) -> PBBuffState:
	var empty: PBBuffState = null
	var shortest: PBBuffState = null
	for state: PBBuffState in _slots:
		if state.buff != null and state.buff.id == id:
			return state
		if not state.is_live(at_tick):
			# 已过期的也算空，否则刚过期的槽位会白占一整 tick。
			if empty == null:
				empty = state
			continue
		if shortest == null or state.left(at_tick) < shortest.left(at_tick):
			shortest = state
	return empty if empty != null else shortest
