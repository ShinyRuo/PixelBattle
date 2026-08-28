class_name PBStrategyRegistry
extends RefCounted
## 按名字造一个流派。批量模拟用它遍历全部对照组。

## 全部流派，CSV 的 `strategy` 列会用这些名字。
##
## 顺序是有意排的 —— 相邻两项之间只差一个变量，好读差值：
##
## | 对比 | 差值说明的是 |
## |---|---|
## | `balanced` vs `no_rotation` | §03 的属性系统到底值多少（唯一变量：换不换人） |
## | `no_rotation` vs `pure_physical` | 物理保底补丁与「不换人的五系」差距（应该很小） |
## | `balanced` vs `pure_economy` / `pure_power` | §07 的经济与战力平衡点在哪 |
## | `dispatch_never` / `balanced` / `dispatch_always` | §06 三种派遣策略的差异（应 < 20%） |
## | `balanced` vs `rational` | 写死的花钱顺序离「会算账」差多远 |
##
## `rational` 与其余流派性质不同：它是**校价用的仪器**，不是一种玩法。
## 其余流派的花钱顺序写死，读不到 `equip_part_cost`，
## 所以拿它们扫装备价格问不出「玩家会不会改买装备」。见 [PBStratRational]。
const IDS: Array[StringName] = [
	&"balanced",
	&"no_rotation",
	&"pure_physical",
	&"pure_economy",
	&"pure_power",
	&"dispatch_never",
	&"dispatch_always",
	&"rational",
]


## 造一个新的流派实例。名字不认识返回 null。
##
## 每局都要造新的，不能复用 —— 流派对象自己带可变字段（如目标科技等级），
## 跨局复用会让上一局的状态渗进下一局，而这种污染在结果里看不出来。
static func make(id: StringName) -> PBStrategy:
	match id:
		&"balanced":
			return PBStratBalanced.new()
		&"no_rotation":
			return PBStratVariants.NoRotation.new()
		&"pure_physical":
			return PBStratVariants.PurePhysical.new()
		&"pure_economy":
			return PBStratExtremes.PureEconomy.new()
		&"pure_power":
			return PBStratExtremes.PurePower.new()
		&"dispatch_never":
			return PBStratVariants.DispatchNever.new()
		&"dispatch_always":
			return PBStratVariants.DispatchAlways.new()
		&"rational":
			return PBStratRational.new()
		_:
			return null
