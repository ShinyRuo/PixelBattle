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
