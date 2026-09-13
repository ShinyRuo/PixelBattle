class_name PBStratVariants
extends RefCounted
## 与 [PBStratBalanced] 花钱方式相同、只在**上场逻辑**上分叉的三个流派。
##
## 三者共用同一套经济决策是刻意的：这样它们之间的差距只可能来自上场逻辑，
## 不会被「谁更会理财」污染。这是本组对照实验的全部价值所在。


## 不换人：永远上裸战力最高的，完全不看属性。
##
## **这是隔离「换人」效应的对照组，也是本次实验最要紧的一个。**
##
## 五系阵容如果全员固定上场，对任意一波的平均倍率是
## `(2.0 + 0.5 + 1.0×3) / 5 = 1.10`，而纯物理是 `1.05` —— 几乎没差别。
## §03 那 2.0 倍的克制加成**全部来自玩家每波换上克制系**。
##
## 所以 `balanced` 与 `no_rotation` 的差值，才是属性系统真正值多少；
## 而 `no_rotation` 与 `pure_physical` 的差值应该很小 —— 如果不小，
## 说明模型里有别的东西在起作用，结论要重新审。
class NoRotation:
	extends PBStratBalanced

	func _init() -> void:
		super()
		id = &"no_rotation"

	func deploy(state: PBRunState, _wave: PBWave, cfg: PBSimConfig) -> Array[PBUnit]:
		return pick_by_raw_power(state, cfg, open_slots(state, cfg))


## 纯物理：只上物理位。§03 的验收线「全物理阵容的极限波次 < 五系均衡阵容的 70%」的度量工具。
## 它还天然吃另一重亏（物理卡池小），要拆开看就对比 `no_rotation`（卡池完整但不换人）。
class PurePhysical:
	extends PBStratBalanced

	func _init() -> void:
		super()
		id = &"pure_physical"

	func deploy(state: PBRunState, _wave: PBWave, cfg: PBSimConfig) -> Array[PBUnit]:
		return pick_by_element(state, PBElement.Type.PHYSICAL, cfg, open_slots(state, cfg))

	## 纯物理流当然会把物理卡带上场 —— 按默认的裸战力挑在场名单会让它「带错人」，而那不是它要度量的东西。
	## [param _wave_element] 用不上：「换克制系」正是它要放弃的变量。
	func bring_to_field(
		state: PBRunState, cfg: PBSimConfig, _wave_element: int = -1
	) -> Array[PBUnit]:
		var capacity: int = state.open_slots(cfg)
		var physical: Array[PBUnit] = []
		var rest: Array[PBUnit] = []
		for unit: PBUnit in state.sorted_by_power(cfg):
			if unit.element == PBElement.Type.PHYSICAL:
				physical.append(unit)
			else:
				rest.append(unit)
		physical.append_array(rest)
		var chosen := physical.slice(0, capacity)
		state.set_field(chosen)
		return chosen


## 派遣策略的两个极端，其余一切与 `balanced` 相同。
##
## §06 的验收标准：**至少 3 种可行的派遣策略，极限波次差异 < 20%。**
## 加上 `balanced` 自带的 SMART，这里凑够三种。
##
## 差异要是远大于 20%，说明「羁绊 ↔ 金币」这条取舍有唯一最优解，
## 那它就不是取舍而是操作税 —— 正是 §06 想改掉的原版毛病。
class DispatchNever:
	extends PBStratBalanced

	func _init() -> void:
		super()
		id = &"dispatch_never"
		dispatch_policy = Dispatch.NEVER


class DispatchAlways:
	extends PBStratBalanced

	func _init() -> void:
		super()
		id = &"dispatch_always"
		dispatch_policy = Dispatch.ALWAYS


## 和 [PBStratRational] **只差一个变量：不会凑羁绊**（[member PBStrategy.field_policy]）。
##
## 羁绊是乘法级杠杆，只有「带谁上场」是真决策时才提供杠杆 —— 要量它就得有一个除此之外一模一样的对照组。
## `rational` 与本流派的比值就是**羁绊贡献的技能阶梯**（§09 验收）。
class BondBlind:
	extends PBStratRational

	func _init() -> void:
		super()
		id = &"bond_blind"
		field_policy = Field.RAW_POWER
