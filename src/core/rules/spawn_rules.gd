class_name PBSpawnRules
extends RefCounted
## 怎么造一波敌人。M9-a 从 [PBBattleSim] 拆出来 —— 那个文件又顶到了
## gdlint 的 1000 行上限，而那条上限「超了不是错，是该拆了的信号」。
##
## 和 [PBTargetRules]（敌人该打谁）、[PBMoveRules]（我方该往哪走）、
## [PBSkillRules]（一发落在谁身上）、[PBShotRules]（子弹落地）对称：
## **这里答的是「这一波的怪长什么样、打多远、什么时候出场」。**
##
## ## 它一个字段都不推进
##
## 拆出来的这一支只把 [PBWave] 和 [PBSimConfig] 翻译成一排 [PBEnemy]，
## 之后每 tick 的推进仍然全在 sim 里。这和另外四个 `*Rules` 是同一条界线：
## 规则层算「该是什么」，sim 层负责「记在哪本账上」。


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
	# **一发就是它的攻击力**（M12-c5，和己方同一把尺子）。
	# 在它之前这里写的是 `atk_each × 攻速 × 间隔 ÷ tick_rate` —— 由每秒输出反推，
	# 于是每一发都不等于 `atk_each`，而漏怪那一下扣的**恰恰就是整份 `atk_each`**
	# （见 [member PBEnemy.atk]）。同一个数在两条路上是两个意思，
	# 而它不报错：两边各差 ±2%，看数字看不出来。
	var per_shot: float = wave.atk_each
	for i: int in wave.count:
		var enemy := PBEnemy.new()
		enemy.slot = i
		var at_tick: int = 0
		if wave.count > 1:
			at_tick = int(round(window_ticks * float(i) / float(wave.count - 1)))
		# 出生在方阵里（M4-d）：第一列在战场边缘，后面几列排在战场之外。
		enemy.spawn(wave, enemy_speed, cfg.enemy_start_x(i), at_tick, cfg.enemy_lane(i))
		# 远近两种打法（M4-c）。谁是远程按槽位定死，不掷骰 ——
		# 理由见 [member PBSimConfig.enemy_ranged_share]。
		#
		# **一个 `far` 喂四个参数**（M9-a 从 if/else 并过来的）：拆成两支的话
		# 「射程」「子弹速度」「它是不是远程」三样各写一遍，
		# 而漏改一支的表现是一只近战怪发射子弹，或者一只远程怪贴脸站着。
		var far: bool = cfg.enemy_is_ranged(i)
		enemy.arm(
			cfg.enemy_reach_ranged if far else cfg.enemy_reach,
			interval,
			per_shot,
			shot_speed if far else 0.0,
			far,
			cfg.windup_ticks(interval)
		)
		into[i] = enemy
