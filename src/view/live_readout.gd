class_name PBLiveReadout
extends RefCounted
## 更新面板自有的快照，绝不改写战斗属性。数值不变时不重排文字。
## 攻击显示元素克制前的属性值；攻速显示定帧后的实际每秒出手数。


static func update(stats: PBStats, live: PBAttacker, cfg: PBSimConfig, tick: int) -> bool:
	var attack: float = (
		float(live.damage_attributes.get(&"attack", live.attack))
		+ live.base_attack * PBAllyAuraRules.bonus_rate(live, tick)
	)
	var defence: float = live.defence + live.buffs.amount(PBBuffRules.DEFENCE, tick)
	var speed: float = float(cfg.tick_rate) / live.attack_interval() if live.alive else 0.0
	var strength: float = float(live.damage_attributes.get(&"strength", stats.strength))
	var agility: float = float(live.damage_attributes.get(&"agility", stats.agility))
	var intellect: float = float(live.damage_attributes.get(&"intellect", stats.intellect))
	if (
		stats.hp == live.max_hp
		and stats.mp == live.max_mp
		and stats.atk == attack
		and stats.def == defence
		and stats.attack_speed == speed
		and stats.strength == strength
		and stats.agility == agility
		and stats.intellect == intellect
	):
		return false
	stats.hp = live.max_hp
	stats.mp = live.max_mp
	stats.atk = attack
	stats.def = defence
	stats.attack_speed = speed
	stats.strength = strength
	stats.agility = agility
	stats.intellect = intellect
	return true
