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


## 纯物理：只上物理位，恒定吃 `MULT_PHYSICAL`，永不吃克制也永不被克。
##
## §03 的验收标准：**全物理阵容的极限波次 < 五系均衡阵容的 70%。**
## 这个流派就是那条验收线的度量工具。
##
## 注意它天然还吃另一重亏：抽卡属性是六选一等概率，物理只占 1/6，
## 所以它可用的卡池本来就小。这两重劣势在 M-1 里是混在一起的，
## 要拆开看就对比 `no_rotation`（卡池完整但不换人）。
class PurePhysical:
	extends PBStratBalanced

	func _init() -> void:
		super()
		id = &"pure_physical"

	func deploy(state: PBRunState, _wave: PBWave, cfg: PBSimConfig) -> Array[PBUnit]:
		return pick_by_element(state, PBElement.Type.PHYSICAL, cfg, open_slots(state, cfg))

	## 纯物理流当然会把物理卡带上场。
	##
	## M2-c 之后 `pick_by_element` 是在**在场名单**里筛的，而默认的在场名单
	## 按裸战力选 —— 那样这个流派会因为「带错人」而变弱，
	## 而「带错人」不是它要度量的东西（它度量的是 §03 的物理保底补丁值多少）。
	## [param _wave_element] 用不上：这个流派**永远**先带物理，
	## 「换克制系」正是它要放弃的那个变量。
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


## 和 [PBStratRational] **只差一个变量：不会凑羁绊。** M2-c 的度量工具。
##
## §01 要求三档玩家拉开 15–25 / 40–60 / 100+ 波，而 M1 实测整条技能阶梯
## 只有 1.30×（新手代理 33.9 波 → `rational` 44.2 波）。根因是加法杠杆
## 在指数难度曲线上只换得到对数级的波次差 —— 与 §07 的经济张力同一条。
##
## 羁绊是本案第一个**乘法级**杠杆，但它只有在「带谁上场」是个真决策时
## 才提供杠杆。所以要量它，就得有一个除此之外一模一样的对照组。
##
## `rational` 与本流派的比值就是**羁绊贡献的技能阶梯**，
## M2 的验收要求它到 2× 以上。两者的花钱逻辑、派遣逻辑、换人逻辑
## 全部相同，唯一的差别是 [member PBStrategy.field_policy]。
class BondBlind:
	extends PBStratRational

	func _init() -> void:
		super()
		id = &"bond_blind"
		field_policy = Field.RAW_POWER
