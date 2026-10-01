class_name PBMoveRules
extends RefCounted
## 己方单位这一 tick 往哪儿挪（§02 / §03A）。
##
## 这里**只读位置、只写 [member PBAttacker.pos]** —— 不看血、不结算伤害。
## 和 [PBTargetRules] 对称：那边答「敌人该打谁」，这边答「我方该往哪儿走」。
##
## 三条互斥的状态，顺序就是优先级：
##
## 1. **够得着 → 站住。** 交战中绝不挪窝
## 2. **够不着 → 按自己的打法靠过去**（近战贴身、远程只前压）
## 3. **场上一个活人都没有 → 慢慢走回自己的位置**


## 这一 tick 这根皮带绳有多长。平时就是 [member PBAttacker.leash]；
## 目标已经站定（[member PBEnemy.engaged]）而绳子够不着它时放长。
##
## 必须有这个例外：敌人停在哪由**它挑的那个忍者**决定，忍者能走多远由
## **他自己的站位**决定，两把尺子很容易量出一个谁都够不着的位置 ——
## 表现是一排忍者站着挨枪，一动不动。
##
## - **点名不松绳**：否则点一个在别处挨打的敌人等于把他拔出阵型。
## - **够得着就不放**：判据是 `leash + reach`（绳拴脚，打人用射程），
##   和 [method PBBattleSim._nearest_enemy] 挑目标用的是同一个数。
## - **放到刚好够到这一个，再压一道天花板**（绳长 + 远程敌人射程）。
##   这是弹簧不是棘轮：目标死了或还在走，绳子立刻缩回。天花板不能省，
##   否则每杀一个、下一个照着新位置再停，他就往外挪一截。
##
## **不要加「咬的不是我就不松绳」**：敌人咬住同列另一个人时，离同列每个人的家
## 正好多出一个泳道差，那道门槛会把够不着的近战永久锁死在绳边，整波一发不放。
## 天花板一个就挡住了阵型塌陷。
static func leash_for(
	attacker: PBAttacker, target: PBEnemy, named: PBEnemy, cfg: PBSimConfig
) -> float:
	if not target.engaged or named == target:
		return attacker.leash
	if attacker.home.distance_to(target.pos()) <= attacker.leash + attacker.reach:
		return attacker.leash
	var ceiling: float = attacker.leash + cfg.enemy_reach_ranged
	var want: float = attacker.home.distance_to(target.pos()) + attacker.stop_gap()
	return clampf(want, attacker.leash, ceiling)


## 远程：**只在推进轴上前压**，压到刚好够得着为止。
##
## 不走二维：射程圈本来就罩着大半条道，追着目标上下跑会让一队远程来回甩动。
##
## **例外：纵向差本身就超出射程时**，横着挪多远都够不着（射程是真圆），
## 改走 [method close_in] 二维靠过去 —— 否则敌人全聚在前排一个人身上时，
## 另一头的远程全程一发不放。皮带绳照旧拴着。
static func press_forward(attacker: PBAttacker, target: PBEnemy, leash: float) -> void:
	if absf(target.pos().y - attacker.pos.y) >= attacker.reach:
		close_in(attacker, target, leash)
		return
	# 二维之后「刚好够得着」要先扣掉纵向差的那一截，见 [method PBAttacker.reach_stop_x]。
	var want: float = minf(attacker.reach_stop_x(target.pos()), attacker.home.x + leash)
	var to: float = maxf(want, attacker.home.x)
	var gap: float = to - attacker.pos.x
	var step: float = PBMotionAuraRules.move_step(attacker)
	attacker.pos.x += clampf(gap, -step, step)


## 近战：**二维贴上去**，停在自己的接触距离上。
##
## 停在射程边缘而不是踩到对方身上，否则防挤推开 → 够不着 → 再贴上，来回抖。
##
## **停在射程的九成上**（[constant PBAttacker.STOP_RING]）：正好停在 `reach` 上时
## 浮点量回来略大于 `reach`，他会判定够不着、原地跑。
##
## 皮带绳按二维距离量。放开的话所有人挤到最前面，§02 的射程梯度就没了。
static func close_in(attacker: PBAttacker, target: PBEnemy, leash: float) -> void:
	var at := target.pos()
	var gap: Vector2 = at - attacker.pos
	var want: float = gap.length()
	var stop: Vector2 = at if want <= 0.0 else at - gap / want * attacker.stop_gap()
	var from_home: Vector2 = stop - attacker.home
	var leashed: float = from_home.length()
	if leashed > leash:
		stop = attacker.home + from_home / leashed * leash
	attacker.pos = attacker.pos.move_toward(stop, PBMotionAuraRules.move_step(attacker))
