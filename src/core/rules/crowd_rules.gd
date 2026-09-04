class_name PBCrowdRules
extends RefCounted
## 防挤：把重合的单位推开（§03A，M3.5-c）。**敌我两侧各一套。** 全部 static。
##
## ## 为什么从 [PBBattleSim] 里搬出来
##
## 直接的触发是 gdlint 报那个文件破了 1000 行上限。那条上限
## 「超了不是错，是该拆了的信号」，这次它又指对了地方 ——
## 和 [PBFieldPicker] 当初从 [PBBattleView] 里分出来是同一回事。
##
## 分出来的这一块有一个说得清的边界：**它只按位置把人推开**，
## 不看血、不看射程、不看谁在打谁。战斗的其余部分一个字段都不碰。
##
## ## 它顺带让聚拢看得见
##
## §02 的拉拽、§11 的七尾、§09 的功能档会把一群敌人拖到**同一个点**，
## 画出来是一个单位 —— 玩家看不出大招起没起作用。摊开之后聚拢仍然有效
## （间距 0.012 远小于大招半径 0.12），但看得出来是「一堆人」。

## 铺开用的角度步长（黄金角，弧度）。见 [method siege_spot] 与 [method _push_dir]。
const SPREAD_ANGLE: float = 2.399963229728653

## 围攻环取射程的几成。**绝不能取 1.0。**
##
## 正好踩在射程边界上时浮点会翻车：站位 0.30 加射程 0.02 算出来是
## 0.32000000000000006，回头量距离得到 0.020000000000000018，
## 而判定写的是 `gap > reach` —— **那个敌人站在自己的射程边上，
## 判定却是够不着**，于是一枪不放。实测就是这个：一堵一亿血的墙，
## 四百 tick 一滴血没掉，而所有位置数字看起来都完全正确。
##
## 0.9 是「明显在里面」而不是「差一点点」—— 靠 `is_equal_approx` 那类
## 容差去救的话，救的是判定，而站位本身仍然贴在悬崖边上。
##
## **它和己方那一侧是同一把尺子**（[constant PBAttacker.STOP_RING]）。
## M5-10 只改了敌人这半边，己方那半边一直踩着边界停 —— 同一个 bug
## 在另一侧又活了六个里程碑，M6-q 才补上。写成引用而不是又抄一个 0.9：
## 抄一份的话哪天调了一边、另一边的现象会一模一样地回来。
const SIEGE_RING: float = PBAttacker.STOP_RING


## 围住 [param at] 的时候，第 [param slot] 个敌人该站在环上的哪一格（M5-10）。
##
## ## 为什么不是「都走到他身上」
##
## M5-9 之前每个敌人都直奔 `prey.pos`，走到 [param reach] 之内就咬住不动。
## 于是**先到的那几个把近侧堵死**，后面的全被防挤往身后垫 ——
## 屏幕上是一条斜着排开的长队，而不是围住那个忍者。
## 换掉防挤的推开方向（M5-9）没能修好它：**根因在「大家的目标是同一个点」**，
## 从同一侧走向同一个点，两两之间的连线本来就指着队伍延伸的方向。
##
## 给每个人环上一个自己的角度之后，二十个敌人是从二十个方向压过来的。
##
## ## 只取朝出怪点那半圈
##
## `absf(cos)` 把 x 分量钉成非负 —— 敌人只会围到**前半圈和两侧**，
## 不会绕到忍者背后。绕过去的话「忍者是一堵墙」就破了：
## §02 要求墙没破之前后面是安全的，而一个站在忍者与基地之间的敌人
## 已经越过了那堵墙。
##
## [param height] 是战场纵深。**取 0 就退回一维**（所有人的 y 都是 0），
## 那是升维改造的对拍锚点，`test_field_2d.gd` 靠它活着。
static func siege_spot(at: Vector2, slot: int, reach: float, height: float) -> Vector2:
	var angle: float = float(slot) * SPREAD_ANGLE
	var ring: float = reach * SIEGE_RING
	return Vector2(
		at.x + absf(cos(angle)) * ring, clampf(at.y + sin(angle) * ring, 0.0, height)
	)


## 敌人这一侧。[param front] 起、[param tick] 这一刻已经出场且活着的才参与。
##
## ## 围上来，不是排成一队（M5-9）
##
## 这一侧原来**只往推进轴上垫**：后一个被推到前一个身后 `gap` 处。
## 行军队列里那是对的（大家本来就一前一后），**敌人改成扑向最近的活忍者
## 之后就不对了** —— 整波奔向**同一个点**，一律往后垫就把他们排成一条长龙，
## 屏幕上是几十个敌人站成一列纵队等着挨个上前，而不是围住那个忍者。
##
## 改动只有一处：**推开的方向从「一律沿推进轴」换成两人之间的连线**，
## 于是一群人挤向同一个点时自然摊成一片。
##
## ## 两条老规矩一个字都没动，而且缺一不可
##
## **只有下标靠后的那个让**。两个人各让一半的话，挤在最前面的那个会被
## 后面整群人的压力**一路顶开**，永远够不到忍者 —— 实测就是这个结果：
## 一个 1 点血、站着不动的靶子能把整波熬到自己不掉血。
##
## **而且只往远离基地的方向让**。让拥挤把敌人往前送等于**凭空多出漏怪**，
## 玩家看到的是「忍者明明挡住了，基地血还是在掉」。
##
## 代价是 O(n²)，n 最大是 [member PBSimConfig.count_cap]（48）——
## 每 tick 约 1100 次比较，和「攻击者 × 敌人」那一遍同量级。
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
