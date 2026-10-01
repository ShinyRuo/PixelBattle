class_name PBCastTestClock
extends RefCounted
## 集成测试推进真实模拟；不跳过起手，不直接调用技能结算。


static func until(sim: PBBattleSim, tick: int) -> void:
	while sim.current_tick() < tick and not sim.is_finished():
		sim.step()


static func release(sim: PBBattleSim, unit: PBAttacker) -> int:
	if sim.order_of(unit) >= 0:
		sim.step()
	var tick := unit.casting.releases_at
	until(sim, tick)
	return tick


static func recover(sim: PBBattleSim, unit: PBAttacker) -> void:
	until(sim, unit.casting.ends_at)
