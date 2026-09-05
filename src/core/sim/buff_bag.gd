class_name PBBuffBag
extends RefCounted
## **一个单位身上挂着的全部效果**（M7-a）。
##
## ## 它不认识 [PBAttacker]，也不认识 [PBEnemy]
##
## 收裸值、返回裸值 —— 和 [PBActorPose] 同一条规矩。敌我两边字段名不同
## （攻击者有 `alive` 和大招，敌人没有），收裸值才能一份实现两处用。
## 两套的话「减速的判定」迟早在两边分叉，而那不报错。
##
## ## 过期是**查询时比 tick**，不是扫描时删
##
## [method amount] 每次遍历都按 tick 过滤，那是**真相**；
## [method sweep] 只是回收槽位和界面上那一行，**漏跑一次不可能改变任何
## 结算结果**。反过来（删除即真相）的话，清扫的时机、顺序、和暂停的关系
## 全都变成正确性问题 —— 而 [PBBattleSim] 现有的 `_speed_scale()`
## 就是这个写法，照抄。
##
## ## 槽位固定，满了顶掉剩余时间最短的那个
##
## §14 那条「热路径不 `.new()`」：48 个敌人 × 20 tick/s 的规模下这笔开销很实在，
## 所以 [PBBuffState] 随 bag 一起预分配。
##
## 满了之后**顶掉剩余最短的**而不是丢掉新来的：丢新的表现是
## 「我刚放的技能没生效」，而它不报错；顶掉最短的至少保证
## 「刚放下去的一定看得见」。

## 一个单位最多同时挂几个。六个是拍的，但它有一条硬性质：
## **超了不是错，是顶掉一个** —— 所以调大调小都不会让任何东西崩，
## 只会改变「同时挂很多个时哪一个先消失」。
const SLOTS: int = 6

var _slots: Array[PBBuffState] = []


func _init() -> void:
	_slots.resize(SLOTS)
	for i: int in SLOTS:
		_slots[i] = PBBuffState.new()


## 全部槽位，**含空的和已过期的**。渲染层与 [PBBattleSim] 遍历它时
## 自己用 [method PBBuffState.is_live] 过滤 —— 返回一个筛过的新数组
## 会在热路径上分配，而这个函数每 tick 每个单位都要调一次。
##
## **只读，不要改。** 和 [method PBBattleSim.shots] 同一条约定。
func states() -> Array[PBBuffState]:
	return _slots


## 全部腾空。**开波、复用对象时必须调** —— 不调的话上一波的效果会漏进这一波，
## 而那和 [method PBSkillCast.reset] 顶上记着的「上一场剩下的冷却漏进下一场」
## 是同一个形状：不报任何错，只表现为「后半局怎么好像变了」。
func clear() -> void:
	for state: PBBuffState in _slots:
		state.clear()


## 挂一份上去。[param values] 是**已经按等级算完**的数值
## （[method PBBuffRules.resolve]）。
##
## ## 同 id 整份覆盖 —— 那就是「刷新时长」（决策 5）
##
## 不是「到期取较长者」：一个先挂的长弱档 + 后挂的短强档，取较长会得到
## 「强档持续很久」，比两者都好，而没有人要过那个东西。
## 整份覆盖同时也和 [PBBattleSim] 原来那对 `_buff_scale` / `_buff_until`
## 逐字一致（那里写的是「后来者覆盖前者」），M7-a 的迁移靠这一条保持逐位相同。
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
##
## **一个空 bag 返回的是不折不扣的中性值** —— 率型正好是 `1.0`，
## 而浮点乘 1.0 是精确的。M3-a 那条「整队折成一个标量攻击者」的解析式对拍
## 因此一位都不会动。
func amount(key: StringName, at_tick: int) -> float:
	var out: float = PBBuffRules.neutral(key)
	for state: PBBuffState in _slots:
		if not state.is_live(at_tick):
			continue
		if state.mods.has(key):
			out = PBBuffRules.fold(key, out, float(state.mods[key]))
	return out


## 现在挂着几份。**「身上有没有东西」也问这一个**（`count(t) > 0`）——
## 另开一个 `has_any` 就是同一个问题的第二个答案。
func count(at_tick: int) -> int:
	var live: int = 0
	for state: PBBuffState in _slots:
		if state.is_live(at_tick):
			live += 1
	return live


## 把过期的槽位腾出来。**纯回收** —— 见本类顶部，漏跑不影响任何结算。
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
			# 已过期的也算空 —— 等 [method sweep] 跑过才复用的话，
			# 一个刚过期的槽位会白占一整 tick。
			if empty == null:
				empty = state
			continue
		if shortest == null or state.left(at_tick) < shortest.left(at_tick):
			shortest = state
	return empty if empty != null else shortest
