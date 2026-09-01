class_name PBEnemy
extends RefCounted
## 战场上的一个敌人。M0 起，战斗从解析式排队模型换成逐 tick 推进，
## 敌人因此需要有身份和位置 —— 排队模型里它们只是一个计数。
##
## **这个类会被对象池复用，不要在战斗中 `.new()`。** §14 的要求：
## GDScript 每 tick 创建大量临时对象会触发频繁的引用计数开销，
## 48 单位 × 20 tick/s 的规模下这笔开销很实在。
## 复用的入口是 [method spawn]，它把所有字段重置成出生状态。

## 还活着（没被打死、也没走到基地）。
var alive: bool = false

var hp: float = 0.0
var max_hp: float = 0.0

## 本波的属性。同一波内所有敌人属性相同（§04），存在个体上是为了
## 将来的「混合属性波」（§04 的 50 波后机制）不用改结构。
var element: PBElement.Type = PBElement.Type.FIRE

## 攻击力。两处用得上：漏进基地时扣多少血，以及**打己方单位时打多少**。
##
## M0 到 M3 只有前一处 —— 那时敌人不还手。§03A 之后忍者有了血和防，
## 「谁来打掉这些血」必须有答案，答案就是这个字段。
var atk: float = 0.0

## 一次出手对己方单位打多少（M4-c 起是离散的，和己方同一套）。
##
## 和 [member atk] 分开存，是因为漏怪那一下是**一次性**的整份 atk，
## 而打人是按攻速分次打出去的 —— 同一个数在两处的量纲不同，
## 合成一个字段迟早有一边写错，而那不报错。
var damage_per_shot: float = 0.0

## 隔几 tick 出一手。由 [member PBSimConfig.enemy_attack_speed] 反推。
var attack_interval: int = 1

## 第几 tick 起可以出下一手。和 [member PBAttacker.next_shot_at] 同一套写法。
var next_shot_at: int = 0

## 子弹每 tick 飞多远。**0 表示近战**（接触即伤），和
## [member PBAttacker.shot_speed] 同一条规矩。
var shot_speed: float = 0.0

## 打得到多远。与 [member distance] 同轴。
##
## **近战**射程很短：敌人自出生点走向基地，先撞上站得最靠前的己方单位
## （§02 的前排）—— 所以前排先挨打，坦克因此有意义。
## **远程**（M4-c）射程长得多，他们会停在更远处放子弹，
## 于是「前排挡住了」不再等于「全场安全」。
var reach: float = 0.0

## 这一 tick 有没有咬住己方单位。**咬住了就不前进**（War3 的交战行为）。
##
## 每 tick 由 [PBBattleSim] 重算，不是持久状态 —— 目标死了就该立刻恢复推进。
var engaged: bool = false

## 距离基地还有多远。出生时等于战场长度，走到 0 就是漏怪。**推进轴（x）。**
##
## 名字没跟着改成 `x`：漏怪、大招落点、行军速度全都只关心这一根轴，
## 而「离基地多远」比「横坐标是多少」更说得清它是什么。
var distance: float = 0.0

## 在哪条泳道上，0 到 [member PBSimConfig.field_height]。**纵轴（y）。**
##
## M4-a 之前这个量只存在于渲染层（画面用「槽位号 × 黄金比」编出来，
## 好让 48 个敌人不挤成一条线）。搬进 sim 之后**画面一个像素都没变**，
## 但它从此参与射程、大招半径与防挤 —— 也就是「圆」从此不是谎话。
##
## 出生时由 [method PBSimConfig.enemy_lane] 定死，**推进过程中不变**
## （M4-c 的近战 AI 才会动它）。
var lane: float = 0.0

## 每 tick 前进多少。由 `march_seconds` 反推，不是新拍的参数。
var speed: float = 0.0

## 这个敌人第几个 tick 出场。没到就不激活、不能被打也不移动。
var spawn_tick: int = 0

## 出生在多远处。**击退的上限就是这个数**（不该被推回到自己出生点之外）。
##
## M4-d 之前整波都从 [member PBSimConfig.field_length] 出发，所以那时候
## 直接拿战场长度当上限就够了。现在方阵后面几列出生在**战场之外**，
## 拿战场长度封顶会把他们**往前拽** —— 一个「击退」把敌人推得离基地更近，
## 而那不报错，只表现为「三尾有时候好像在帮敌人」。
var start_x: float = 0.0

## 渲染层用来认人的槽位号，等于它在对象池里的下标。
## view 层靠它把节点和逻辑敌人对上，不用每帧重新匹配。
var slot: int = 0


## 把这个实例重置成一个刚出生的敌人。对象池复用走这里，不要 `.new()`。
func spawn(
	wave: PBWave, enemy_speed: float, at_x: float, at_tick: int, at_lane: float = 0.0
) -> void:
	alive = true
	max_hp = wave.hp_each
	hp = max_hp
	element = wave.element
	atk = wave.atk_each
	distance = at_x
	start_x = at_x
	lane = at_lane
	speed = enemy_speed
	spawn_tick = at_tick
	engaged = false
	next_shot_at = at_tick


## 定下这个敌人的攻击方式（M4-c）。[method spawn] 之后调一次。
##
## ## 为什么和 `spawn` 分开
##
## `spawn` 的参数已经到七个了，而这四个是**同一件事的四个面**：
## 打多远、隔多久、一次多少、发不发子弹。捆在一起传的话，
## 调用方每次都要把「近战怎么配、远程怎么配」重写一遍，
## 而那份配置只该有一处（[method PBSimConfig.enemy_is_ranged]）。
func arm(at_reach: float, interval: int, per_shot: float, bullet_speed: float) -> void:
	reach = at_reach
	attack_interval = maxi(interval, 1)
	damage_per_shot = per_shot
	shot_speed = bullet_speed


## 这一 tick 出不出得了手。
func ready_to_fire(current_tick: int) -> bool:
	return alive and current_tick >= next_shot_at


## 出了一手，转入下一次的间隔。
func on_fired(current_tick: int) -> void:
	next_shot_at = current_tick + attack_interval


## 战场坐标。x 是离基地多远，y 是泳道。
##
## 每次现造一个 Vector2 而不是存一个字段：两个分量各有各的写入路径
## （x 每 tick 推进、y 只在出生时定），存成一个字段就有两份真相，
## 而漏同步一次的表现是「某个敌人的判定和它画出来的位置对不上」。
## Vector2 是值类型，不进堆，§14 那条「热路径不 `.new()`」管不着它。
func pos() -> Vector2:
	return Vector2(distance, lane)


## 已出场**且**还活着 —— 也就是「此刻真的在场上」。渲染层要画的就是这些。
func is_active(current_tick: int) -> bool:
	return alive and current_tick >= spawn_tick


## 只问出场，不问死活。
##
## ## 为什么这两件事必须分开问
##
## 敌人数组按出场顺序排列，所以遍历时「碰到一个还没出场的就可以停」——
## 后面的只会出场更晚。但那个 `break` 的条件必须是**只看出场**：
## 用 [method is_active] 的话，一具**中途死掉的尸体**也会让扫描提前结束，
## 它后面还活着的敌人就此被漏掉。
##
## M3-a 之前这个错误不会发作：单目标集火只在队头杀人，
## 死者都被 `_front` 游标跳过了，中间不会有尸体。
## **射程、AOE 和大招让敌人开始乱序死亡之后它才会现形** ——
## 而现形的样子是「后排敌人突然不动了」，从现象反推极难。
func has_spawned(current_tick: int) -> bool:
	return current_tick >= spawn_tick


## 扣血。返回这次是否把它打死了。
##
## 返回值而不是让调用方比较 hp，是为了让「溢出伤害」有个明确的结算点：
## 打死之后剩下的伤害要接着打下一个，漏掉这个判断会让高 DPS 白白浪费。
func take_damage(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false


## 前进一个 tick。返回是否在这一 tick 走到了基地。
##
## [param speed_scale] 是场上的减速效果（0 = 定身，1 = 正常）。
## **它是个参数而不是敌人身上的一个字段**，因为减速是**场的属性**不是
## 单位的属性 —— §11 的一尾（全屏减速力场）和五尾（地形阻挡）都作用于整片战场。
## 存到每个敌人身上的话，新出场的敌人会漏掉当前正生效的减速，
## 而那种漏只表现为「后半波怪走得比前半波快」，不报任何错。
func advance(speed_scale: float = 1.0) -> bool:
	distance -= speed * maxf(speed_scale, 0.0)
	if distance <= 0.0:
		distance = 0.0
		return true
	return false


## 朝 [param at] 走一个 tick（M5-7）。**两轴一起走，而且永远走不到基地** ——
## 这一支是「扑向一个还活着的忍者」，不是「推进」。
##
## ## 为什么和 [method advance] 分成两个函数
##
## 那一个的返回值语义是「这一 tick 漏进基地了吗」，而这一支**结构上
## 不可能漏怪**：目标是一个站在场上的忍者，走到他跟前就会进射程、就会咬住。
## 合成一个函数的话，调用方每次都要先判断「这次算不算漏」，
## 而判错一次的表现是**基地凭空掉血**，从现象反推极难。
##
## 纵轴在这之前只有出生时写过一次（见 [member lane]）——
## 敌人第一次会换泳道，正是为了绕到没人的那一侧去够人。
func march_to(at: Vector2, speed_scale: float = 1.0) -> void:
	var step: float = speed * maxf(speed_scale, 0.0)
	if step <= 0.0:
		return
	var here := pos().move_toward(at, step)
	distance = maxf(here.x, 0.0)
	lane = here.y


## 朝围攻环上自己那一格挪（M5-10）。**绝不后退，一步都不往出怪点那侧退。**
##
## ## 为什么咬住之后还准他动
##
## 「咬住了就不走」（[member engaged]）说的是**不许越过那堵墙**，
## 不是「就地钉死」。钉死的话先到的那几个把近侧堵满，后面的人
## 永远轮不到位置 —— 那正是「围不起来，排成一队」的另一半根因
## （另一半见 [method PBCrowdRules.siege_spot]）。
##
## ## 墙不是靠这里守的，那条钳位曾经反了
##
## 第一版钳的是「`distance` 只增不减」（不许朝基地挪），而那**造出了
## 一个只往右的棘轮**：防挤永远把人往出怪点那侧推
## （[method PBCrowdRules.separate_enemies]），而这条钳位又不让他回来 ——
## 于是敌人一路飘到屏幕外面去。
##
## 墙其实由**围攻点本身**守着：那个点的 x 恒 ≥ 忍者的 x
## （[method PBCrowdRules.siege_spot] 里的 `absf(cos)`），从右边走过去
## 到不了忍者身后。所以这里该钳的是反过来的那一条 ——
## **不许后退** —— 它同时把防挤推出去的那一截拉了回来。
func siege_to(at: Vector2, speed_scale: float = 1.0) -> void:
	var hold: float = distance
	march_to(at, speed_scale)
	distance = minf(distance, hold)


## 渲染用的进度：0 = 刚出生，1 = 抵达基地。
func progress(field_length: float) -> float:
	if field_length <= 0.0:
		return 1.0
	return clampf(1.0 - distance / field_length, 0.0, 1.0)
