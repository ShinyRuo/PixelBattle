extends GutTest
## 「打出要害那一下按目标生命百分比再打一笔」（M12-c2 的 `bite_current` /
## `bite_lost`）。从 `tests/test_passive.gd` 搬出来，M12-e2。
##
## ## 为什么它自己一个文件
##
## 触发的是 gdlint 的 20 个公开方法上限（同 M12-c2 拆出
## `tests/test_enemy_control.gd` / `tests/test_hurt_ally.gd` 那两次），
## 而上限那条「超了不是错，是该拆了的信号」这次指的地方也是对的：
## 这三条**测的不是被动那条通道，是那一笔伤害本身怎么算**
## —— 读点在 [method PBStrikeRules.land] 里面，
## 而它有自己的一整套夹具（一个打不死的靶子、一个只剩四分之一血的靶子）。
##
## 三条各守一件事：**它骑在暴击那个掷点上**（不另掷一次，M10-c 那条
## 「一个掷点」）、**两个方向是两个字段**（一个人可以两样都带）、
## **封顶不是配平是结构上必须有的**（§04 的 BOSS 血量按波次指数长）。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 7


func test_the_bite_only_happens_on_a_telling_blow() -> void:
	# 它骑在暴击那个掷点上（不另掷一次），所以 `crit` 为 false 时是 0。
	var attacker := _striker()
	attacker.bite_current = 0.5
	var enemies := _pack(1)
	var out := PBCombatOutcome.new()
	var before: float = enemies[0].hp
	PBStrikeRules.land(attacker, enemies[0], 10.0, false, enemies, _cfg, 0, null, out)
	assert_almost_eq(before - enemies[0].hp, 10.0, 0.001, "没打出要害就只有主伤害")


func test_the_two_bites_read_opposite_halves_of_the_health_bar() -> void:
	# `bite_current` 越打越弱、`bite_lost` 越打越强 —— 两个字段而不是
	# 一个加方向开关，因为一个人可以两样都带。
	var now := _striker()
	now.bite_current = 0.2
	var lost := _striker()
	lost.bite_lost = 0.2
	# 血量故意只有 100：封顶是「这一下伤害的几倍」（这里 10 × 3），
	# 拿一个十万血的人来量的话两边都被封到同一个数，
	# 而那正是下一条要问的事。
	assert_almost_eq(_bite_of(now, _quarter_health()), 5.0, 0.01, "按还剩多少算")
	assert_almost_eq(_bite_of(lost, _quarter_health()), 15.0, 0.01, "按已经掉了多少算")


func test_the_bite_is_capped_so_a_boss_cannot_be_melted_by_a_percentage() -> void:
	# **封顶不是配平。** [member PBAttacker.heavy_bonus] 顶上早就写着：
	# BOSS 血量按波次指数长，百分比伤害是那条曲线的常数倍 ——
	# 不封顶的话这几个角色在后期独占全场，而屏幕上只表现为
	# 「后面几波好像只有他在输出」。原版自己也封（柔拳 8000、骨拔 5000）。
	var attacker := _striker()
	attacker.bite_current = 0.9
	var enemies := _pack(1)
	enemies[0].max_hp = 1000000.0
	enemies[0].hp = 1000000.0
	assert_almost_eq(
		_bite_of(attacker, enemies),
		10.0 * PBStrikeRules.BITE_CAP,
		0.001,
		"封在这一下伤害的几倍上"
	)


func _striker() -> PBAttacker:
	var one := PBAttacker.new()
	one.slot = 0
	one.dps = 100.0
	one.max_hp = 500.0
	one.attack_speed = 1.0
	one.reach = 1.0
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


## 一个满血、打不死的敌人。量的是「掉了多少」，不是「死没死」。
func _pack(count: int) -> Array[PBEnemy]:
	var wave := PBWaveRules.build(3, _cfg, _rng)
	var out: Array[PBEnemy] = []
	for i: int in count:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, _cfg.field_length - float(i) * 0.5, 0, 0.0)
		enemy.slot = i
		enemy.max_hp = 100000.0
		enemy.hp = enemy.max_hp
		out.append(enemy)
	return out


## 一个只剩四分之一血的敌人。**每次现造** —— [method _bite_of] 会扣血，
## 两次量共用一个的话第二次看到的是被第一次打过的那个。
func _quarter_health() -> Array[PBEnemy]:
	var out := _pack(1)
	out[0].max_hp = 100.0
	out[0].hp = 25.0
	return out



## 打一下要害，量出主伤害之外多打了多少。
func _bite_of(attacker: PBAttacker, enemies: Array[PBEnemy]) -> float:
	var out := PBCombatOutcome.new()
	var before: float = enemies[0].hp
	PBStrikeRules.land(attacker, enemies[0], 10.0, true, enemies, _cfg, 0, null, out)
	return before - enemies[0].hp - 10.0
