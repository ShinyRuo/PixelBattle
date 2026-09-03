class_name PBTargetRules
extends RefCounted
## 敌人挑己方单位的两条查询。全部 static，无状态，零引擎依赖。M6-j。
##
## ## 为什么从 [PBBattleSim] 里搬出来
##
## 直接的触发是那个文件顶到了 gdlint 的 1000 行上限，而战斗日志（M6-j）
## 还要往里接几行。那条上限「超了不是错，是该拆了的信号」——
## 这两个函数是它最该拆的地方：**纯查询，一个字段都不改**，
## 参数只有「一份名单 + 一个敌人」，而周围那些函数全都在推进状态。
##
## ## 两条分开，不合成一个带射程参数的
##
## [method nearest_defender] 回答「现在打得到谁」，[method nearest_ally]
## 回答「该往谁那边走」。合成一个的话调用方每次都要想清楚自己问的是哪一件事，
## 而问错的表现是**敌人站在原地不动**（拿射程内的答案去决定走不走）——
## 不报错，也没有任何日志。
##
## ## 遍历顺序固定，平手时先找到的赢
##
## 和 [member PBBattleSim._attackers] 那条「不排序不打乱」是同一个理由：
## 顺序一变结果就变，而那种差异在批量统计里只表现为「波次悄悄偏了一点」。


## 这个敌人**射程内**离它最近的、还活着的己方单位。没有就返回 null。
static func nearest_defender(attackers: Array[PBAttacker], enemy: PBEnemy) -> PBAttacker:
	return _nearest(attackers, enemy.pos(), enemy.reach)


## 离 [param enemy] 最近的还活着的己方单位，**不看射程**。没有就返回 null。
##
## `max_hp == 0` 的退化标量（[method PBAttacker.whole_field]）
## 在 [method PBAttacker.is_targetable] 里就被排除了 —— 敌人看不见它，
## 所以 M3-a 的对拍路径上这一支恒为 null，行为与升级前一字不差。
static func nearest_ally(attackers: Array[PBAttacker], enemy: PBEnemy) -> PBAttacker:
	return _nearest(attackers, enemy.pos(), -1.0)


## [param within] 为负表示不限射程。
static func _nearest(attackers: Array[PBAttacker], at: Vector2, within: float) -> PBAttacker:
	var best: PBAttacker = null
	var best_gap: float = 0.0
	for attacker: PBAttacker in attackers:
		if not attacker.is_targetable():
			continue
		var gap: float = at.distance_to(attacker.pos)
		if within >= 0.0 and gap > within:
			continue
		if best == null or gap < best_gap:
			best = attacker
			best_gap = gap
	return best
