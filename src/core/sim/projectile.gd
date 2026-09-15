class_name PBProjectile
extends RefCounted
## 一发飞行中的远程攻击（§02）。
##
## **子弹是 sim 里的实体，不是渲染层的表演**：画一道假弹道的话伤害早就结算完了，
## 子弹会飞向一具尸体 —— 玩家看到的东西不是判定的东西。
##
## **对象池复用，不要在战斗中 `.new()`**（§14），入口是 [method launch]。
##
## **目标死了子弹就消失，不改打别人**：那是「命中才结算」的直接后果，也是离散出手唯一的真实损耗。
## 追着换目标的话一发子弹永远不会浪费，离散和连续就没有区别了。

## 还在飞。对象池靠它找空位。
var alive: bool = false

## 战场坐标，与 [member PBAttacker.pos] 同一套。
var pos: Vector2 = Vector2.ZERO

## 出膛的地方。**纯记录，任何规则都不读它。**
## 渲染层要把弹道从枪口画到胸口，需要「飞了几成」。存在这里而不是让渲染层自己记：
## 池子复用会让那份记录对不上，表现为「偶尔有一发子弹从别人身上冒出来」。
var from: Vector2 = Vector2.ZERO

## 追的是第几个。**存下标不存引用** —— §12 的存档要序列化这个，
## 而引用序列化不了。下标指向哪个数组由 [member at_ally] 决定。
var target: int = -1

## 这一发是敌人射向己方的。false = 己方射向敌人。
## **一个开关而不是两个池子**：飞行、命中判定、目标死了就消失，三条规则两个方向逐字相同。
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

## 这一发按哪一系算克制（铁律 4：element 挂在伤害事件上）。只有射向己方的那一半读它。
var element: PBElement.Type = PBElement.Type.PHYSICAL

## 每 tick 飞多远。由 [member PBSimConfig.projectile_cross_seconds] 反推。
var speed: float = 0.0

## 这一发是**哪个技能**射出去的。**null = 普攻。**
##
## 「飞到了才出伤」：结算要等 [method PBShotRules._hit_enemy] 那一刻，而那时施法者可能已经死了，
## 所以这一份挂在子弹上。背引用不背拷贝：[PBSkill] 是不可变的定义。
var skill: PBSkill = null

## 射出这一发的人**当时**几级。效果数值按它现算，理由同 [member PBSkillCast.caster_level]。
var level: int = 1

## **谁打的这一发**，只喂 [PBBattleLog]。下标那一头由 [member at_ally] 决定，和 [member target] 反过来。
## 存在这里：落地那一刻「谁离得最近」和「谁打的」可以是两个人。
var source: int = -1

## 这一发是不是暴击，只喂 [PBBattleLog]。
## **掷骰发生在出膛那一刻**：命中时施法者可能已经死了，而掷点必须只有一个（[PBCritRules]）。
var crit: bool = false

## 打中第一个目标之后还能往前穿多远（战场坐标）。0 = 打中就回池。
## 出膛时由射手的 [member PBAttacker.pierce] 定下（同 [member crit]：飞到时射手可能已经死了）。
var pierce_left: float = 0.0

## 已经穿过第一个目标、正在往前飞。这一段**不再追目标**，沿 [member heading] 走直线 ——
## [member target] 仍指着第一个目标，渲染层靠它找出膛的人和胸口高度。
var piercing: bool = false

## 穿透段往哪飞（单位向量）。
var heading: Vector2 = Vector2.ZERO

## 这一发已经打过的敌人下标。穿透段每个敌人只挨一次。**复用同一个数组**，不在热路径里分配（§14）。
var struck: PackedInt32Array = PackedInt32Array()


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
	caster_level: int = 1,
	was_crit: bool = false
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
	crit = was_crit
	_end_pierce()


## 打中了第一个目标 [param through]，转入穿透段：方向是出膛点指向这里，打过的记下它。
## 出膛点和命中点重合（贴脸开火）时朝右飞 —— 敌人从右边来。
func start_pierce(through: int) -> void:
	piercing = true
	heading = (pos - from).normalized()
	if heading == Vector2.ZERO:
		heading = Vector2.RIGHT
	struck.append(through)


## 穿透段走一个 tick。走完穿透距离返回 false（调用方回池）。
func glide() -> bool:
	var step: float = minf(speed, pierce_left)
	pos += heading * step
	pierce_left -= step
	return pierce_left > 0.0


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
	crit = false
	_end_pierce()


## 穿透那一套清零。出膛和回池都走它：漏清一处的表现是「下一发普攻莫名其妙穿了过去」。
func _end_pierce() -> void:
	pierce_left = 0.0
	piercing = false
	heading = Vector2.ZERO
	struck.clear()
