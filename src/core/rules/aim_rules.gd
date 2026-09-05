class_name PBAimRules
extends RefCounted
## 大招往哪儿放。§02「吸怪分层」的全部逻辑都在这里。M3-b。
##
## ## 这个类回答的是一条验收，不是一个功能
##
## §02 的核心乘法关系是：
##
## [codeblock]
## 实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数
## [/codeblock]
##
## **中间那个因子必须由玩家决定，否则游戏退化成纯拼数值。**
## 但两端输入精度不同，所以 §02 把这个技巧做成分层的：
## 手机点一下自动选，PC 手动指定、可预判。
##
## 分层要成立，两件事都得为真：
##
## 1. 自动**够用** —— 「纯自动落点玩到的极限波次 ≥ 手动的 78%」，
##    否则手机端是残废版
## 2. 手动**有赚头** —— 「手动带来 15–25% 的效率提升」，
##    否则 PC 端的走位技巧没有意义，原版最有意思的那层操作就没了
##
## 这两条是一对**上下夹**：自动太笨则第 1 条挂，自动太聪明则第 2 条挂。
## [enum Policy] 的三档就是量这对夹子的仪器。

## 落点策略。三档对应 §02 的两端加一个基线。
enum Policy {
	NONE,  ## 不放大招。基线，用来量「大招整体值多少」
	AUTO,  ## 手机 / 手柄：冷却一好、够门槛就放，落点取**当前帧**最密处
	LEAD,  ## PC 鼠标：**攒着等聚拢**，落点取**落地那一刻**最密处
}

## 找不到值得放的落点时返回 [constant PBSkillCast.NO_SPOT]。
## 哨兵定义在 [PBSkillCast] 那边 —— 字段在谁身上，哨兵就归谁。


## 挑一个落点。返回 [constant NO_SPOT] 表示这一 tick 不放。
##
## ## 两档在两个维度上分叉：往哪儿放，和什么时候放
##
## **往哪儿放（预判）**：[constant Policy.AUTO] 看当前帧，
## [constant Policy.LEAD] 把每个敌人按速度推进 `delay_ticks` 之后再看。
##
## > **实测这一维几乎不值钱，得记住原因。** 领先距离 = 速度 × 延迟，
## > 默认配置下是 0.042，而杀伤半径 0.12 —— 而且**全体敌人同速前进，
## > 整个队形是刚性平移**。提前量远小于半径时，预判点罩住的是同一批人，
## > 只是中心偏了一点。首次接上时量到 `lead ÷ auto = 1.000`，一分不赚。
## > 要让这一维真的有价值，得让敌人不同速（§04 的波型可以给不同速度），
## > 或者把半径压到和领先距离同量级 —— 而后者会让 AOE 本身变废。
##
## **什么时候放（等聚拢）**：这才是技巧真正的所在，也是 §02 原话
## 「卡在敌人即将聚拢的位置」的后半截。[constant Policy.AUTO] 冷却一好、
## 够 [param min_targets] 就放；[constant Policy.LEAD] 攒着，
## 等罩得住 [param hold_targets] 个才放 —— 攒过头了也有个死线
## （[param max_hold_ticks]），否则一波打完大招还在手上，反而更差。
##
## **两档共用同一套「找最密窗口」的算法**，只在上面两处分叉。
## 各写一份的话，两者的差里会混进算法本身的差异，
## 而那正是这个仪器要量的东西 —— 混进去就再也分不开了。
##
## ## 二维之后怎么找最密处（M4-a）
##
## 精确的「最密圆」要枚举圆心，太贵（一 tick 每人一次）。这里用两轮
## **同一个一维滑窗**：先在推进轴上找最密的那段，再在那一段里的敌人的
## 泳道上找最密的那条 —— 也就是一次网格式的贪心。
##
## 近似是刻意的，而且方向是**保守**的：它可能错过一个斜着摆的更优圆，
## 但绝不会报出一个罩不住那么多人的落点，因为门槛判断
## （[method _count_within]）用的是**真圆**。
static func pick_spot(
	policy: Policy,
	enemies: Array[PBEnemy],
	tick: int,
	skill: PBSkill,
	held_ticks: int,
	min_targets: int,
	hold_targets: int,
	max_hold_ticks: int
) -> Vector2:
	if policy == Policy.NONE:
		return PBSkillCast.NO_SPOT

	var lead: int = skill.delay_ticks if policy == Policy.LEAD else 0
	var xs := PackedFloat64Array()
	var lanes := PackedFloat64Array()
	for enemy: PBEnemy in enemies:
		if not enemy.has_spawned(tick):
			# 后面的出场更晚，这一 tick 不会再有目标了。
			break
		if not enemy.alive:
			continue
		var at: float = enemy.distance - enemy.speed * float(lead)
		# 落地前就冲进基地的敌人不算 —— 那时候他已经不在场上了。
		if at <= 0.0:
			continue
		xs.append(at)
		lanes.append(enemy.lane)

	var floor_targets: int = maxi(min_targets, 1)
	if xs.size() < floor_targets:
		return PBSkillCast.NO_SPOT
	var spot := _densest_spot(xs, lanes, skill.radius)
	if policy != Policy.LEAD:
		return spot

	# 会玩的玩家在等一堆值得的目标。等不到就别捏死在手里 ——
	# 攒到战斗结束等于一发没放，那比手机端还差。
	if held_ticks >= max_hold_ticks:
		return spot
	if _count_within(xs, lanes, spot, skill.radius) >= maxi(hold_targets, floor_targets):
		return spot
	return PBSkillCast.NO_SPOT


## 落点罩得住几个。**用真圆数**，不是用挑落点时那两轮滑窗数 ——
## 门槛判断要的是「实际会打到几个」，而滑窗只是个找圆心的启发式。
static func _count_within(
	xs: PackedFloat64Array, lanes: PackedFloat64Array, spot: Vector2, radius: float
) -> int:
	var count: int = 0
	for i: int in xs.size():
		if spot.distance_to(Vector2(xs[i], lanes[i])) <= radius:
			count += 1
	return count


## 两轮滑窗：先在推进轴上定 x，再在那一段里的泳道上定 y。见 [method pick_spot]。
static func _densest_spot(
	xs: PackedFloat64Array, lanes: PackedFloat64Array, radius: float
) -> Vector2:
	var center_x: float = _densest_window(xs, radius)
	# 泳道要现排序：敌人数组按**出场顺序**排，而那和泳道没有关系，
	# 而滑窗的前提是输入有序（见 [method _densest_window]）。
	var inside := PackedFloat64Array()
	for i: int in xs.size():
		if absf(xs[i] - center_x) <= radius:
			inside.append(lanes[i])
	if inside.is_empty():
		return Vector2(center_x, 0.0)
	inside.sort()
	return Vector2(center_x, _densest_window(inside, radius))


## 在一串位置里找一个宽 `2 × radius` 的窗口，使窗口内的点最多，返回窗口中心。
##
## [param spots] 必须**从小到大**排好。推进轴那一轮天然如此：
## 全体同速前进、按出场顺序排列，先出场的走得久、离基地近，
## 所以**下标 0 是最靠近基地的那个**。泳道那一轮要调用方先 `sort()`。
##
## 并列最多时取**最靠近基地**的那个窗口 —— 越靠近基地的敌人越紧急，
## 同样打 n 个，打掉快漏进去的那 n 个更值。
static func _densest_window(spots: PackedFloat64Array, radius: float) -> float:
	var width: float = radius * 2.0
	var best_count: int = 0
	var best_spot: float = 0.0
	var head: int = 0
	# spots 从小到大，所以 head 是窗口里最靠近基地的那个、i 是最远的那个。
	for i: int in spots.size():
		while spots[i] - spots[head] > width:
			head += 1
		var count: int = i - head + 1
		# `>` 而不是 `>=`：并列时保住先出现的那个窗口，也就是更靠近基地的那个。
		if count > best_count:
			best_count = count
			best_spot = (spots[head] + spots[i]) * 0.5
	return best_spot
