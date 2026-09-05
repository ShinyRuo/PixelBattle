class_name PBProjectile
extends RefCounted
## 一发飞行中的远程攻击。§02，M4-b。
##
## ## 为什么子弹是 sim 里的实体，不是渲染层的表演
##
## 渲染层画一道假弹道是便宜的，但它会撒谎：伤害早在几帧前就结算完了，
## 于是子弹会飞向一具尸体，而射速和真实输出没有任何关系。
## 那和「把大招落点画成圆」是同一类错误 —— 玩家看到的东西不是判定的东西。
##
## 真弹道要先把出手**离散化**（每 N tick 打一发，见 [member PBAttacker.attack_speed]），
## 子弹才有东西可承载。做了之后角色表里那个「攻速」第一次被战斗读到，
## 而铁律 4（element 挂在伤害事件上）第一次有了真正的载体 ——
## 在这之前一个角色的普攻是一条没有边界的连续流，没有「一次伤害事件」可言。
##
## ## 这个类会被对象池复用，不要在战斗中 `.new()`
##
## 和 [PBEnemy] 同一条规矩（§14）。复用的入口是 [method launch]。
##
## ## 目标死了子弹就消失，不改打别人
##
## 那是「命中才结算」的直接后果，也是离散出手唯一的真实损耗：
## 连续输出模型里溢出伤害会无损转移给下一个，而那才是不真实的那一半。
## 追着换目标的话，一发子弹等于永远不会浪费，离散和连续就没有区别了。

## 还在飞。对象池靠它找空位。
var alive: bool = false

## 战场坐标，与 [member PBAttacker.pos] 同一套。
var pos: Vector2 = Vector2.ZERO

## 出膛的地方（M8-a）。**纯记录，任何规则都不读它。**
##
## 渲染层要把这条弹道从**枪口**画到**胸口**（[method PBActorSkin.muzzle]），
## 而那需要「这一发飞了几成」这个比例 —— 没有起点就算不出来。
##
## **存在这里而不是让渲染层自己记**：这个类是对象池复用的，
## 一发回池之后槽位立刻被下一发接管，渲染层那份记录会对不上，
## 而它不报错 —— 只表现为「偶尔有一发子弹从别人身上冒出来」。
var from: Vector2 = Vector2.ZERO

## 追的是第几个。**存下标不存引用** —— §12 的存档要序列化这个，
## 而引用序列化不了。下标指向哪个数组由 [member at_ally] 决定。
var target: int = -1

## 这一发是敌人射向己方的（M4-c）。false = 己方射向敌人。
##
## ## 为什么是一个开关而不是两个池子
##
## 飞行、命中判定、目标死了就消失 —— 三条规则两个方向逐字相同。
## 分两份实现的话，「己方子弹的命中距离」和「敌人子弹的命中距离」
## 迟早对不上，而那种分叉不报错，只表现为「某一边的子弹好像更准」。
var at_ally: bool = false

## 命中时打多少。
##
## ## 两个方向的口径不一样，这是既有的不对称，不是这里新造的
##
## **己方射向敌人**：属性克制、科技、羁绊、装备全部已经乘进来了
## （和 [member PBAttacker.dps] 一样，战斗层只认这个数）。
## **敌人射向己方**：这里存的是**裸伤害**，减伤与克制在命中那一刻才折算 ——
## 因为它要读挨打那个人的防御和防元素，而那是飞行途中可能变的东西。
var damage: float = 0.0

## 这一发按哪一系算克制（§14 铁律 4：**element 挂在伤害事件上，不挂在单位上**）。
##
## 只有射向己方的那一半读它（见 [member damage]）。铁律在这里第二次真正用上 ——
## 第一次是大招（[member PBSkill.element]），而普攻在离散化之前
## 根本没有「一次伤害事件」这种东西可以挂。
var element: PBElement.Type = PBElement.Type.PHYSICAL

## 每 tick 飞多远。由 [member PBSimConfig.projectile_cross_seconds] 反推。
var speed: float = 0.0

## 这一发是**哪个技能**射出去的（M8-b）。**null = 普攻。**
##
## ## 为什么子弹要背着技能，而不是出膛时就把效果算掉
##
## 玩家的原话：「火球术就是子弹技能，飞到了才出伤」。伤害与
## [member PBSkill.on_hit] 因此要等到 [method PBShotRules._hit_enemy] 那一刻 ——
## 而那时施法者可能已经死了、技能可能已经转好了下一发冷却，
## 所以这一份**必须挂在子弹上**，不能回头去问施法者。
##
## 背的是**引用**不是拷贝：[PBSkill] 是不可变的定义（谁都不改它的字段），
## 而每发子弹拷一份是热路径上的分配（§14）。
var skill: PBSkill = null

## 射出这一发的人**当时**几级（M8-b）。效果数值按它现算，
## 理由同 [member PBSkillCast.caster_level]。
var level: int = 1

## **谁打的这一发**（M6-j）。下标那一头由 [member at_ally] 决定，
## 和 [member target] 正好反过来：射向己方的那一半，这里是敌人的下标。
##
## 战斗结算一个字都不读它 —— 它只喂 [PBBattleLog]。**存在这里而不是
## 让日志自己去猜**：一发子弹飞几个 tick，落地那一刻「谁离得最近」
## 和「谁打的」可以是两个人，而猜错不报错。
var source: int = -1


## 把这个实例重置成一发刚出膛的子弹。对象池复用走这里，不要 `.new()`。
func launch(
	from_at: Vector2,
	at: int,
	hit_for: float,
	per_tick: float,
	toward_ally: bool = false,
	of_element: PBElement.Type = PBElement.Type.PHYSICAL,
	from_slot: int = -1,
	of_skill: PBSkill = null,
	caster_level: int = 1
) -> void:
	alive = true
	pos = from_at
	from = from_at
	target = at
	damage = hit_for
	speed = per_tick
	at_ally = toward_ally
	element = of_element
	source = from_slot
	skill = of_skill
	level = caster_level


## 朝 [param goal] 飞一个 tick。返回这一 tick 是否够到了目标。
##
## 判据是「这一步跨得过去」而不是「距离小于某个阈值」：
## 阈值要么让快子弹永远跳过目标（穿过去继续飞），要么让慢子弹提前命中。
## 用步长本身当阈值，两种都不会发生。
func fly(goal: Vector2) -> bool:
	var gap: float = pos.distance_to(goal)
	if gap <= speed or speed <= 0.0:
		pos = goal
		return true
	pos += (goal - pos) / gap * speed
	return false


## 打完了 / 目标没了。回到池子里等下一次 [method launch]。
func retire() -> void:
	alive = false
	target = -1
	# 回池的子弹不该再攥着一份技能引用。[method launch] 每次都会重设它，
	# 所以这一行是第二道保险 —— 而「背着上一发火球的效果飞出去」
	# 恰恰是那种只在特定顺序下发作、且不报错的毛病。
	skill = null
	level = 1
