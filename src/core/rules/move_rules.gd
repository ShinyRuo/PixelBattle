class_name PBMoveRules
extends RefCounted
## 己方单位这一 tick 往哪儿挪（§02 / §03A）。M3.5-c 写在 [PBBattleSim] 里，
## **M6-q 拆出来**：那个文件顶到了 gdlint 的 1000 行上限，
## 而「超了不是错，是该拆了的信号」这次指对了地方。
##
## ## 边界
##
## 这里的三个函数**只读位置、只写 [member PBAttacker.pos]** —— 不看血、
## 不结算伤害、不碰 tick 计数。挑目标那一半留在 [PBBattleSim]（要扫敌人表、
## 要知道第几 tick 谁出场了），和 [PBTargetRules] 是对称的一组：
## 那边回答「敌人该打谁」，这边回答「我方该往哪儿走」。
##
## ## 三条互斥的状态，顺序就是优先级（M4-c）
##
## 1. **够得着 → 站住。** 交战中绝不挪窝
## 2. **够不着 → 按自己的打法靠过去**（近战贴身、远程只前压）
## 3. **场上一个活人都没有 → 慢慢走回自己的位置**
##
## 第 1 条是 M4-c 修掉的那个 bug：在它之前，「够得着」走的是「回家」那一支，
## 于是敌人贴到脸上时忍者**边打边往基地退**。看起来荒谬，代码里却很自然 ——
## 「回家」是默认值，「压上去」是唯一的例外分支，中间那档没人写。


## 这一 tick 这根皮带绳有多长。平时就是 [member PBAttacker.leash]，
## **一种情形下放长**：目标已经站定（[member PBEnemy.engaged]）、
## 绳子够不着它、而且**它咬的就是我**。
##
## ## 为什么必须有这个例外
##
## 敌人一走进自己的射程就站住。它站的位置由**它自己挑的那个忍者**决定，
## 而忍者能走多远由**他自己的站位**决定 —— 两把尺子量的不是同一件事，
## 于是很容易出现一个谁都够不着的位置。M5-8 之前的实测：一队全近战
## 对上停在 0.80 放枪的远程敌人，**105 秒、每人打出 6 下、全灭** ——
## 屏幕上是四个忍者站成一排挨枪，一动不动。
##
## ## 三道门槛，每一道挡的都是一种「被拽出阵型」
##
## **点名不松绳。** [PBBattleSim] 那条注释从 M4-e 起就写着「皮带绳照旧拴着，
## 所以他不会横穿半个战场」，而代码一直会松开 —— 于是点一个正在别处挨打的
## 敌人，等于把这个忍者从阵型里拔出去（M6-q 补的）。
##
## **咬的不是我就不松绳**（M6-q）。判据走 [method PBTargetRules.nearest_ally]，
## 和敌人自己挑人是同一个函数 —— 抄一份的话「谁该去救」会有两个答案。
## 在它之前的条件是「任何一个站定的敌人」，于是围着**别人**打的那一群也会
## 把我拽过去：一个人被拽出去 → 敌人跟着停在他的新位置上 → 队友的目标
## 也到了绳外 → 全队一个接一个塌到同一点。实测第 20 波那个近战
## **210/271 tick 在绳外、离家 0.55，而绳长 0.35**。
##
## **放长到刚好够到这一个，还要压一道绝对天花板**（M6-q）。原来返回的是
## [method PBSimConfig.field_diagonal]，也就是彻底松开 —— 那是个**棘轮**：
## 判据量的是 `home` 而 `home` 不动，所以这一波剩下的时间里绳子再也收不回来。
## 现在它是根**弹簧**：目标在哪儿就放到哪儿，目标死了或者下一个还在走
## （`engaged` 为假）绳子立刻缩回去，[method close_in] 把他拉回自己那一格。
##
## 天花板不能省：咬住我的那个我走过去打死了，下一个照着我的**新位置**再停，
## 于是每杀一个就往外挪一截。取「我站在自己那一格的最边上时，一个远程敌人
## 最远能停在哪」= 绳长 + 它的射程：够得着任何一个**冲我来的**，
## 但绝不跟着战线往外飘。
##
## **退回去不会把敌人晾在原地**：[member PBEnemy.engaged] 每 tick 重算，
## 够不着我了它就继续走过来。
static func leash_for(
	attacker: PBAttacker,
	target: PBEnemy,
	named: PBEnemy,
	squad: Array[PBAttacker],
	cfg: PBSimConfig
) -> float:
	if not target.engaged or named == target:
		return attacker.leash
	if attacker.home.distance_to(target.pos()) <= attacker.leash + attacker.reach:
		return attacker.leash
	if PBTargetRules.nearest_ally(squad, target) != attacker:
		return attacker.leash
	var ceiling: float = attacker.leash + cfg.enemy_reach_ranged
	var want: float = attacker.home.distance_to(target.pos()) + attacker.stop_gap()
	return clampf(want, attacker.leash, ceiling)


## 远程：**只在推进轴上前压**，压到刚好够得着为止。
##
## 不走二维是有意的：远程的射程圈本来就罩着大半条道，横着挪一步能多够到的人
## 远比竖着挪多。让他们也追着敌人上下跑的话，一队远程会跟着最近的目标
## 来回甩动，而那不是玩家排的阵型。
##
## ## 一个例外：纵向差本身就超出射程（M5-8）
##
## 那一档里**横着挪多远都够不着** —— 射程圈是个真圆（M4-a），
## 纵向已经出圈的话 x 上没有任何一个点能把它收回来。
##
## 这一档在 M5-7 之前几乎不发生：敌人沿直线推进，每条泳道上迟早都有人走过。
## 敌人改成扑向最近的活忍者之后，**整波会聚到前排那一个人身上** ——
## 于是一个站在另一头的远程忍者，视野里从头到尾一个敌人都没有，
## 全程站着不动、一发不放，直到前排倒下敌人才散开找他。
##
## 补法是掉头走 [method close_in]（**二维靠过去，停在射程边缘**），
## 而不是放开皮带绳：绳子仍然拴着，所以他挪的是自己那一格附近。
static func press_forward(attacker: PBAttacker, target: PBEnemy, leash: float) -> void:
	if absf(target.pos().y - attacker.pos.y) >= attacker.reach:
		close_in(attacker, target, leash)
		return
	# 二维之后「刚好够得着」要先扣掉纵向差的那一截，见 [method PBAttacker.reach_stop_x]。
	var want: float = minf(attacker.reach_stop_x(target.pos()), attacker.home.x + leash)
	var to: float = maxf(want, attacker.home.x)
	var gap: float = to - attacker.pos.x
	attacker.pos.x += clampf(gap, -attacker.move_speed, attacker.move_speed)


## 近战：**二维贴上去**，停在自己的接触距离上。
##
## 停在射程边缘而不是踩到对方身上：踩上去的话防挤会立刻把两边推开，
## 而推开之后又够不着了 —— 整场战斗表现为近战在敌人身上来回抖。
##
## **停在射程的九成上**（[constant PBAttacker.STOP_RING]），不是踩着边界停：
## 正好停在 `reach` 上的话，浮点量回来是 `0.020000000000000018 > 0.02`，
## 于是他站在自己的射程边上却判定够不着，每 tick 重走一遍这个函数 ——
## 目标被防挤推得一直在动，落脚点跟着抖，而净位移是零。
## 那就是「离怪一点点距离原地跑」（实测 76/271 tick，M6-q 修）。
##
## 皮带绳按**二维距离**量。放开它就等于「自由跑向敌人」，所有人挤到最前面
## 接敌，§02 的射程梯度（「场上稳定有人」的唯一来源，实测 1.7 → 6.0）就没了。
static func close_in(attacker: PBAttacker, target: PBEnemy, leash: float) -> void:
	var at := target.pos()
	var gap: Vector2 = at - attacker.pos
	var want: float = gap.length()
	var stop: Vector2 = at if want <= 0.0 else at - gap / want * attacker.stop_gap()
	var from_home: Vector2 = stop - attacker.home
	var leashed: float = from_home.length()
	if leashed > leash:
		stop = attacker.home + from_home / leashed * leash
	attacker.pos = attacker.pos.move_toward(stop, attacker.move_speed)
