class_name PBEnemy
extends RefCounted
## 战场上的一个敌人。
##
## **对象池复用，不要在战斗中 `.new()`**（§14：48 单位 × 20 tick/s 的规模下分配开销很实在）。
## 复用的入口是 [method spawn]，它把所有字段重置成出生状态。

## 这只怪是哪一档。
##
## **是一个字段，不回头去问波次**：渲染层只拿得到 [method PBBattleSim.enemies]，
## 两个来源对不上的表现是精英波里混进一只小怪的图。
## **纯元数据：任何规则都不读它**，血量、数量、伤害全部来自 [PBWave]。
enum Rank {
	MINION,  ## 小怪 —— 常规波与潮水波
	ELITE,  ## 精英波
	BOSS,  ## BOSS 波与超级 BOSS 波
}

## 还活着（没被打死、也没走到基地）。
var alive: bool = false

var hp: float = 0.0
var max_hp: float = 0.0

## 本波的属性。同一波内所有敌人属性相同（§04），存在个体上是为了
## 将来的「混合属性波」（§04 的 50 波后机制）不用改结构。
var element: PBElement.Type = PBElement.Type.FIRE

## 这只怪的档次，见 [enum Rank]。[method spawn] 从波型推出来。
var rank: Rank = Rank.MINION

## **正在起手**，理由同 [member PBAttacker.swinging]。
var swinging: bool = false

## 起手要几 tick —— 从抬手到伤害落地。[method arm] 按
## [method PBSimConfig.windup_ticks] 填，理由同 [member PBAttacker.windup_ticks]。
var windup_ticks: int = 0

## 远程还是近战。**存下来，不从 [member reach] 反推** —— 反推就是第二把尺子：
## 「射程正好等于远程那个数」和「它是一只远程怪」是两句话，
## 哪天两个射程配成一样，屏幕上就会出现一只近战怪举着法杖。
##
## 和 [member rank] 一样是纯元数据，规则一处都不读。
var ranged: bool = false

## 攻击力。两处用：漏进基地时扣多少血，以及打己方单位时一发打多少。
var atk: float = 0.0

## 一次出手对己方单位打多少（取自 [member atk]，和己方同一把尺子）。
var damage_per_shot: float = 0.0

## 隔几 tick 出一手。由 [member PBSimConfig.enemy_attack_speed] 反推。
var attack_interval: int = 1

## 第几 tick 起可以出下一手。和 [member PBAttacker.next_shot_at] 同一套写法。
var next_shot_at: int = 0

## 子弹每 tick 飞多远。**0 表示近战**（接触即伤），和
## [member PBAttacker.shot_speed] 同一条规矩。
var shot_speed: float = 0.0

## 打得到多远。**近战**射程很短，先撞上站得最靠前的己方单位，所以前排先挨打；
## **远程**停在更远处放子弹，「前排挡住了」不再等于「全场安全」。
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
## 出生时由 [method PBSimConfig.enemy_lane] 定死，扑向忍者时才会换泳道（[method march_to]）。
## 参与射程、大招半径与防挤。
var lane: float = 0.0

## 每 tick 前进多少。由 `march_seconds` 反推，不是新拍的参数。
var speed: float = 0.0

## 这个敌人第几个 tick 出场。没到就不激活、不能被打也不移动。
var spawn_tick: int = 0

## 出生在多远处。**击退的上限就是这个数**：方阵后几列出生在战场之外，
## 拿战场长度封顶会把他们往前拽 —— 一个「击退」把敌人推得离基地更近。
var start_x: float = 0.0

## 渲染层用来认人的槽位号，等于它在对象池里的下标。
## view 层靠它把节点和逻辑敌人对上，不用每帧重新匹配。
var slot: int = 0

## 身上挂着的效果。词汇表见 [PBBuffRules]（敌方那几个键不是己方那张照搬）。
## **随敌人一起造，不在战斗中 `.new()`**。**[method spawn] 必须清它**。
var buffs: PBBuffBag = PBBuffBag.new()


## 把这个实例重置成一个刚出生的敌人。对象池复用走这里，不要 `.new()`。
func spawn(
	wave: PBWave, enemy_speed: float, at_x: float, at_tick: int, at_lane: float = 0.0
) -> void:
	alive = true
	max_hp = wave.hp_each
	hp = max_hp
	element = wave.element
	rank = rank_of(wave)
	atk = wave.atk_each
	distance = at_x
	start_x = at_x
	lane = at_lane
	speed = enemy_speed
	spawn_tick = at_tick
	engaged = false
	swinging = false
	next_shot_at = at_tick
	# **不清的话上一波的减速会漏进这一波**，表现是「后半局的怪好像变慢了」。
	# 和 [method PBSkillCast.reset] 顶上记着的「上一场剩下的冷却漏进下一场」
	# 是同一个形状，而它同样不报任何错。
	buffs.clear()


## 定下这个敌人的攻击方式。[method spawn] 之后调一次。
## 打多远、隔多久、一次多少、发不发子弹是同一件事的四个面，配置只在 [method PBSimConfig.enemy_is_ranged] 一处。
func arm(
	at_reach: float,
	interval: int,
	per_shot: float,
	bullet_speed: float,
	is_ranged: bool = false,
	windup: int = 0
) -> void:
	reach = at_reach
	attack_interval = maxi(interval, 1)
	damage_per_shot = per_shot
	shot_speed = bullet_speed
	ranged = is_ranged
	windup_ticks = clampi(windup, 0, maxi(attack_interval - 1, 0))
	swinging = false


## 波型 → 档次。**潮水波也是小怪、超级 BOSS 也是 BOSS** ——
## 这两条合并是有意的：屏幕上要分的是「长什么样」，而潮水波的怪和常规波的怪
## 是同一种东西（只是更多更薄），超级 BOSS 和 BOSS 也是。
##
## 「是不是 BOSS」走 [method PBWave.is_boss]，不另判一遍：那句话已经有主了，
## 抄一份出来的话，哪天加一档 BOSS 波型，两处就会对同一波说两种话。
static func rank_of(wave: PBWave) -> Rank:
	if wave.is_boss():
		return Rank.BOSS
	return Rank.ELITE if wave.shape == PBWave.Shape.ELITE else Rank.MINION


## 这一 tick 出不出得了手。
##
## **晕眩判在这里面**（[constant PBBuffRules.STUN]）：近战与远程在调用方那一句之后才分岔。
## **被定住那几 tick 冷却不推进**（[member next_shot_at] 只在 [method on_fired] 里走）——
## 否则禁锢结束那一瞬敌人会把攒下的几下一起打出来。
func ready_to_fire(current_tick: int) -> bool:
	if not alive or current_tick < next_shot_at:
		return false
	return buffs.amount(PBBuffRules.STUN, current_tick) <= 0.0


## 出了一手，转入下一次的间隔。**减掉起手那一段**，理由同
## [method PBAttacker.on_fired]。
func on_fired(current_tick: int) -> void:
	swinging = false
	# 攻速被压低（[constant PBBuffRules.ENEMY_ATTACK_SPEED_SCALE]）时下一次间隔拉长。下限防除零。
	var pace: float = maxf(buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, current_tick), 0.05)
	var interval: int = int(round(float(attack_interval) / pace))
	next_shot_at = current_tick + maxi(interval - windup_ticks, 1)


## 抬手，同 [method PBAttacker.begin_swing]。
func begin_swing(current_tick: int) -> bool:
	if windup_ticks <= 0 or swinging:
		return false
	swinging = true
	next_shot_at = current_tick + windup_ticks
	return true


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
## 敌人数组按出场顺序排列，遍历时「碰到一个还没出场的就可以停」—— 那个 `break` 必须**只看出场**：
## 用 [method is_active] 的话，一具中途死掉的尸体会让扫描提前结束，后面活着的敌人被漏掉，
## 表现是「后排敌人突然不动了」。
func has_spawned(current_tick: int) -> bool:
	return current_tick >= spawn_tick


## 扣血。返回这次是否把它打死了（溢出伤害的结算点）。
##
## **易伤在这里面乘**：调用方有六处，漏乘一处就是「某一种攻击方式吃不到易伤」。
## [param at_tick] **没有默认值**：给了默认值的话漏传的调用方会静默拿到一个所有效果都已过期的 tick。
func take_damage(amount: float, at_tick: int) -> bool:
	if not alive:
		return false
	hp -= amount * buffs.amount(PBBuffRules.HURT, at_tick)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false


## 打死它还要多少**伤害**——不是还剩多少血。易伤已经折算进去。
##
## ## 只有溢出那一条路需要它
##
## [method PBStrikeRules._pour_damage] 打死一个之后要把「花掉的那一份」
## 从手上的伤害里减掉，接着打下一个。易伤进来之后
## 「掉了多少血」和「花了多少伤害」不再是同一个数，
## 而那条路径正是与 [PBCombatRules] 解析式排队模型对拍的锚点 ——
## 差一点点的表现是「退化路径和解析式对不上」，一条既有测试会红。
##
## 没有任何易伤时倍率精确等于 1.0，除法逐位无损。
func damage_to_kill(at_tick: int) -> float:
	var mult: float = buffs.amount(PBBuffRules.HURT, at_tick)
	return hp if mult <= 0.0 else hp / mult


## 前进一个 tick。返回是否在这一 tick 走到了基地。
##
## [param speed_scale] 是**场上**的减速（0 = 定身，1 = 正常）。它是参数不是字段：减速是场的属性，
## 存到每个敌人身上的话新出场的敌人会漏掉当前正生效的减速。
## 个体减速是另一层，两者相乘（见 [method _speed_mult]）。
func advance(speed_scale: float, at_tick: int) -> bool:
	distance -= speed * _speed_mult(speed_scale, at_tick)
	if distance <= 0.0:
		distance = 0.0
		return true
	return false


## 朝 [param at] 走一个 tick。**两轴一起走，而且永远走不到基地** —— 这是「扑向一个活着的忍者」。
##
## 和 [method advance] 分开：那一个的返回值是「漏进基地了吗」，而这一支结构上不可能漏怪。
## 合成一个的话调用方每次都要判断「这次算不算漏」，判错的表现是基地凭空掉血。
func march_to(at: Vector2, speed_scale: float, at_tick: int) -> void:
	var step: float = speed * _speed_mult(speed_scale, at_tick)
	if step <= 0.0:
		return
	var here := pos().move_toward(at, step)
	distance = maxf(here.x, 0.0)
	lane = here.y


## 朝围攻环上自己那一格挪。**绝不后退，一步都不往出怪点那侧退。**
##
## 咬住之后还准他动：钉死的话先到的几个把近侧堵满，后面的人永远轮不到位置。
##
## **墙由围攻点本身守着**（x 恒 ≥ 忍者的 x，见 [method PBCrowdRules.siege_spot]），
## 这里该钳的是「不许后退」—— 同时把防挤推出去的那一截拉回来。
## 反过来钳「不许朝基地挪」的话，防挤一直往外推、钳位又不让回来，敌人会一路飘出屏幕。
func siege_to(at: Vector2, speed_scale: float, at_tick: int) -> void:
	var hold: float = distance
	march_to(at, speed_scale, at_tick)
	distance = minf(distance, hold)


## 这一 tick 它实际按几成速度走。**全场那一份 × 身上这一份**。
##
## 两份都要：全场那份搬进袋子的话新出场的敌人会漏掉；只留全场那份的话「定住这一个」没有地方表达。
## 相乘不取最小（全场定身期间速度仍是 0）。走这一条的三处都在类里面，调用方一处都不乘。
func _speed_mult(field_scale: float, at_tick: int) -> float:
	var own: float = buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, at_tick)
	return maxf(field_scale, 0.0) * maxf(own, 0.0)
