class_name PBTargetRules
extends RefCounted
## 敌人挑己方单位的两条查询。全部 static，无状态，零引擎依赖。
##
## **两条不合成一个带射程参数的**：[method nearest_defender] 答「现在打得到谁」，
## [method nearest_ally] 答「该往谁那边走」。问错的表现是敌人站在原地不动，不报错。
##
## **遍历顺序固定，平手时先找到的赢** —— 顺序一变结果就变，
## 而那种差异在批量统计里只表现为「波次悄悄偏了一点」。


## 这个敌人**射程内**离它最近的、还活着的己方单位。没有就返回 null。
static func nearest_defender(attackers: Array[PBAttacker], enemy: PBEnemy) -> PBAttacker:
	return _nearest(attackers, enemy.pos(), enemy.reach)


## 离 [param enemy] 最近的还活着的己方单位，**不看射程**。没有就返回 null。
##
## 退化标量（[method PBAttacker.whole_field]）在 [method PBAttacker.is_targetable]
## 里被排除，所以对拍路径上这一支恒为 null。
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
