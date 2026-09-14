class_name PBSpawnRules
extends RefCounted
## 怎么造一波敌人：把 [PBWave] 和 [PBSimConfig] 翻译成一排 [PBEnemy]。
##
## 和 [PBTargetRules] / [PBMoveRules] / [PBSkillRules] / [PBShotRules] 对称。
## **一个字段都不推进** —— 规则层算「该是什么」，sim 层负责「记在哪本账上」。


## 一次性把整波敌人建好，出场时刻算在这里。
##
## 全部预分配、之后只改字段不再 `.new()` —— §14 对 sim 层的要求。
## [param into] 会被 resize 成 [member PBWave.count] 并原地填满。
static func fill(
	into: Array[PBEnemy], wave: PBWave, cfg: PBSimConfig, enemy_speed: float, shot_speed: float
) -> void:
	into.resize(wave.count)
	var window_ticks: float = cfg.spawn_window * float(cfg.tick_rate)
	# 出手间隔与一发的伤害：和己方同一条换算（[method PBAttacker.prime]）——
	# 由间隔反推一发打多少，平均输出因此分毫不差。
	var interval: int = maxi(
		int(round(float(cfg.tick_rate) / maxf(cfg.enemy_attack_speed, 0.001))), 1
	)
	# **一发就是它的攻击力**，和己方同一把尺子；漏怪那一下扣的也是整份
	# `atk_each`（见 [member PBEnemy.atk]），同一个数在两条路上是同一个意思。
	var per_shot: float = wave.atk_each
	for i: int in wave.count:
		var enemy := PBEnemy.new()
		enemy.slot = i
		var at_tick: int = 0
		if wave.count > 1:
			at_tick = int(round(window_ticks * float(i) / float(wave.count - 1)))
		# 出生在方阵里：第一列在战场边缘，后面几列排在战场之外。
		enemy.spawn(wave, enemy_speed, cfg.enemy_start_x(i), at_tick, cfg.enemy_lane(i))
		# 远近两种打法。谁是远程按槽位定死，不掷骰 —— 理由见
		# [member PBSimConfig.enemy_ranged_share]。**BOSS 一律远程**，射程另有一档（玩家定的）。
		# **一个 `far` 喂四个参数**：拆成两支的话漏改一支，就是近战怪发子弹或远程怪贴脸站着。
		var boss: bool = enemy.rank == PBEnemy.Rank.BOSS
		var far: bool = boss or cfg.enemy_is_ranged(i)
		var reach: float = cfg.enemy_reach_ranged if far else cfg.enemy_reach
		enemy.arm(
			cfg.enemy_reach_boss if boss else reach,
			interval,
			per_shot,
			shot_speed if far else 0.0,
			far,
			cfg.windup_ticks(interval)
		)
		into[i] = enemy
