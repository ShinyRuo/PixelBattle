class_name PBCrowdRules
extends RefCounted
## 防挤：把重合的单位推开（§03A）。**敌我两侧各一套。** 全部 static。
##
## 边界：**只按位置把人推开**，不看血、射程、谁在打谁。
## 顺带让聚拢看得见 —— 被拖到同一点的一群敌人摊开之后仍在大招半径内，
## 但画出来是「一堆人」而不是一个。

## 铺开用的角度步长（黄金角，弧度）。见 [method siege_spot] 与 [method _push_dir]。
const SPREAD_ANGLE: float = 2.399963229728653

## 围攻环取射程的几成。**绝不能取 1.0**：正好踩在射程边界上时浮点会翻车
## （0.30 + 0.02 = 0.32000000000000006，量回来 0.020000000000000018 > 0.02），
## 敌人站在射程边上却判定够不着，一枪不放，而所有位置数字看起来都正确。
##
## **和己方是同一把尺子**（[constant PBAttacker.STOP_RING]），写成引用不抄一份 ——
## 两边各一个数的话，调了一边另一边的现象会原样回来。
const SIEGE_RING: float = PBAttacker.STOP_RING


## 围住 [param at] 时，第 [param slot] 个敌人该站在环上哪一格。
##
## 大家都直奔同一个点的话，先到的堵死近侧，后面的被防挤垫成一条长队。
## 每人环上一个自己的角度，二十个敌人才是从二十个方向压过来。
##
## **只取朝出怪点那半圈**（`absf(cos)`）：绕到忍者背后等于越过了那堵墙，
## §02 要求墙没破之前后面是安全的。
##
## [param height] 取 0 就退回一维，那是升维的对拍锚点（`test_field_2d.gd`）。
static func siege_spot(at: Vector2, slot: int, reach: float, height: float) -> Vector2:
	var angle: float = float(slot) * SPREAD_ANGLE
	var ring: float = reach * SIEGE_RING
	return Vector2(
		at.x + absf(cos(angle)) * ring, clampf(at.y + sin(angle) * ring, 0.0, height)
	)


## 敌人这一侧。[param front] 起、[param tick] 这一刻已经出场且活着的才参与。
##
## **推开方向是两人之间的连线**，整波挤向同一个点时自然摊成一片，而不是排成纵队。
##
## 两条规矩缺一不可：
## - **只有下标靠后的那个让。** 各让一半的话，最前面那个会被整群人的压力一路顶开，
##   永远够不到忍者。
## - **只往远离基地的方向让。** 让拥挤把敌人往前送等于凭空多出漏怪。
##
## O(n²)，n 最大是 [member PBSimConfig.count_cap]（48）。
static func separate_enemies(
	enemies: Array[PBEnemy], front: int, tick: int, gap: float, height: float
) -> void:
	if gap <= 0.0:
		return
	var last: int = enemies.size()
	for i: int in range(front, last):
		if not enemies[i].has_spawned(tick):
			# 后面的出场更晚，这一 tick 不会再有人挤了。
			last = i
			break
	for i: int in range(front, last):
		var a: PBEnemy = enemies[i]
		if not a.alive:
			continue
		for j: int in range(i + 1, last):
			var b: PBEnemy = enemies[j]
			if not b.alive:
				continue
			var offset: Vector2 = b.pos() - a.pos()
			var span: float = offset.length()
			if span >= gap:
				continue
			var dir: Vector2 = _push_dir(offset, span, j)
			# **不往基地那侧让**（见本方法顶部）。只把推进轴那一维翻过来，
			# 纵向那一维留着 —— 整个向量翻的话，两人相距 gap/2 时
			# 会被推到**正好重合**，而防挤的全部意义就是别重合。
			b.distance = a.distance + absf(dir.x) * gap
			b.lane = clampf(a.lane + dir.y * gap, 0.0, height)


## 己方这一侧走**两两互推**，不走敌人那种「只有后面那个让」。
##
## 敌人那一侧的前提是「数组顺序 == 出场顺序 == 大致的距离顺序」，
## **己方不满足** —— 出战席顺序和站位没有关系，一个后排可能排在前排前面。
## 照着让的话，一个站 0.10 的超远程会把站 0.30 的近战一路推到 0.09，
## 整个阵型塌向基地，而且每 tick 塌一点，看起来像「全队在慢慢后退」。
##
## 两两互推是 O(n²)，但 n 是出战人数（上限 10），一 tick 一百次比较 ——
## 比每 tick 排一次序还便宜，而且不分配任何对象（§14 对 sim 层的要求）。
static func separate_attackers(attackers: Array[PBAttacker], gap: float) -> void:
	if gap <= 0.0:
		return
	for i: int in attackers.size():
		var a: PBAttacker = attackers[i]
		if not a.is_targetable():
			continue
		for j: int in range(i + 1, attackers.size()):
			var b: PBAttacker = attackers[j]
			if not b.is_targetable():
				continue
			var offset: Vector2 = b.pos - a.pos
			var span: float = offset.length()
			if span >= gap:
				continue
			# 恰好重合时按下标定方向 —— 随便挑一边会让同一份输入
			# 每次跑出不同的结果，而确定性是铁律 3 的一半。
			# 重合时沿推进轴分开，和一维时代同一个方向。
			var dir: Vector2 = offset / span if span > 0.0 else Vector2(1.0, 0.0)
			var push: Vector2 = dir * (gap - span) * 0.5
			a.pos = a.pos - push
			b.pos = b.pos + push
			a.pos.x = maxf(a.pos.x, 0.0)
			b.pos.x = maxf(b.pos.x, 0.0)


## 两个重合的敌人该往哪个方向分开。
##
## 一般情形就是两点连线。**恰好重合那一档要紧**：整波扑向同一个忍者
## （[method PBBattleSim._advance_and_leak]）时，走到跟前的那几个坐标
## 真的会一模一样，而 `span == 0` 时连线是没有方向的。
##
## 固定挑一个方向（比如 `Vector2.RIGHT`）就等于把重合的人全部往后排 ——
## 那正好又变回一条队。所以按下标铺**黄金角**：确定性（铁律 3 要求同种子
## 同结果），而且连续的下标铺出来是一圈，不是一列。
static func _push_dir(offset: Vector2, span: float, index: int) -> Vector2:
	if span > 0.0:
		return offset / span
	var angle: float = float(index) * SPREAD_ANGLE
	return Vector2(cos(angle), sin(angle))
