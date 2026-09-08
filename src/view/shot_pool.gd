class_name PBShotPool
extends Node2D
## 战场上飞行中的子弹，以及它们命中那一下的火花。§02，M4-b；美术与命中特效是 M8-a。
##
## ## 它画的是 sim 里真有的东西
##
## 渲染层可以很便宜地伪造一道弹道：每隔几帧从射手往目标画一条线就行。
## 但那会撒谎 —— 伤害早在几帧前就结算完了，子弹会飞向一具尸体，
## 而射速和真实输出没有任何关系。所以子弹是 [PBProjectile]，
## 这里只负责把它画出来，一个字段都不回写（§14）。
##
## ## 屏幕上那条弹道是同一次飞行的「重新参数化」
##
## sim 里子弹从**脚底**飞到**脚底** —— 那不是懒，是因为 sim 是一个平面，
## [member PBAttacker.pos] 的 y 是泳道深度不是高度，「枪口在胸口」
## 在那边没有地方表达（[member PBActorSkin.muzzle_offset] 顶上写着）。
##
## 所以这里把端点换掉：起点取射手的枪口、终点取目标的胸口，
## **进度仍然是 sim 算的那个比例**（从 [member PBProjectile.from] 走了几成）。
## 换句话说画面和判定说的是同一件事，只是画在了正确的高度上 ——
## 在 M8-a 之前，60 像素高的人是**从脚踝射向脚踝**的。
##
## ## 三样东西一个池子
##
## 普攻子弹、技能子弹（地面档那段施法延迟）、命中火花。**故意放在一起**：
## 三样共用同一份 [PBShotSkin]（「子弹长什么样」和「炸开长什么样」
## 是同一份美术的两半），分成三个节点的话「配了子弹忘了配特效」
## 迟早发生，而它不报错。
##
## ## 命中火花的触发读战斗播报，不是「这一发回池了吗」
##
## 后者分不出来：池子槽位会被下一发**在同一渲染帧内**接管
## （[method PBBattleSim._free_shot] 挑的就是第一个空位），
## 那时「刚才那一发是打中了还是目标死了」已经无从判断。
## [PBBattleLog] 恰恰逐条记着「谁打了谁多少」，而且**近战和范围普攻也在里面** ——
## 一把尺子，玩家看到的「打中了」因此不分远近。

## 同屏最多几发。**跟 sim 那边的池子同一个数** —— 少了会有子弹画不出来，
## 多了是白占内存，而两个数各写一份迟早对不上。
const CAPACITY: int = PBBattleSim.SHOT_CAPACITY

## 同屏最多几朵火花。一波潮水一帧里可能有十几处命中，
## 满了就丢掉那一朵：扩池会在热路径上分配（§14），而丢掉一朵的代价
## 只是「同一瞬间的第 17 处命中没有火花」。
const IMPACTS: int = 16

## 没配美术时火花活几个渲染帧（[method PBShotSkin.hit_seconds] 为 0 那一档）。
const IMPACT_FRAMES: int = 8

## 己方的子弹是暖白的，敌人的是暗红的（M4-c）。
##
## **必须分得开。** 两边同色的话，一屏小方块里读不出「有几发正朝我飞」，
## 而那正是敌人分远近之后玩家唯一需要的新信息 —— 前排挡得住近战，
## 挡不住站在后面射的那一批。
##
## 只作用在 [member PBShotSkin.tint_by_side] 那一档（白模）上；
## 真素材各画各的，见那个字段。
const COLOR := Color(0.96, 0.94, 0.72, 0.95)
const ENEMY_COLOR := Color(0.95, 0.42, 0.38, 0.95)

## 一个连 [PBActorSkin] 都查不到的单位（尾兽那种没有本体的）用的枪口与胸口。
## 数值按白模身高（[constant PBWhiteModel.ALLY_HEIGHT]）派生。
const NO_SKIN_MUZZLE := Vector2(7.0, -25.0)
const NO_SKIN_CHEST := Vector2(0.0, -20.0)

var _fly: Array[AnimatedSprite2D] = []
var _hits: Array[AnimatedSprite2D] = []

## 每朵火花还剩几个渲染帧。下标和 [member _hits] 对齐，前 [member _live] 个有效。
var _hit_left: PackedInt32Array = PackedInt32Array()
var _live: int = 0

## 这一帧画了几发子弹。
var _shown: int = 0

## 播报已经消化到**第几条**（[member PBBattleLog.total]，只增不减）。
## 不能存 `entries.size()` —— 理由见那个字段。
var _echoed: int = 0


func _ready() -> void:
	# 两个池子都按上限一次建满，之后只改属性和 visible（§14）。
	for _i: int in CAPACITY:
		_fly.append(_make())
	for _i: int in IMPACTS:
		_hits.append(_make())
	_hit_left.resize(IMPACTS)


## 把池子同步到这一帧的战场上。每渲染帧调一次。
##
## [param battle] 只读（[method PBBattleSim.shots] / [method PBBattleSim.attackers]）。
## [param deployed] 是出战席名单 —— 己方的皮要靠它从槽位反查到
## [member PBCharacter.actor_key]。[param book] 可以为 null（那时不出火花）。
func sync_shots(
	battle: PBBattleSim, deployed: Array[PBUnit], book: PBBattleLog, field: Vector2
) -> void:
	_shown = 0
	for shot: PBProjectile in battle.shots():
		if shot.alive:
			_place_shot(shot, battle, deployed, field)
	_place_casts(battle, deployed, field)
	for i: int in range(_shown, _fly.size()):
		_fly[i].visible = false
	_echo(battle, deployed, book, field)
	_age()


## 一发都不画（准备阶段还没有战场，本局结束之后也没有）。
func clear() -> void:
	for dot: AnimatedSprite2D in _fly:
		dot.visible = false
	for spark: AnimatedSprite2D in _hits:
		spark.visible = false
	_hit_left.fill(0)
	_shown = 0
	_live = 0
	_echoed = 0


## 这一帧画着几发子弹。测试拿它确认「在飞才画、到了就收」。
func shown() -> int:
	return _shown


## 这一帧亮着几朵火花。
func sparks() -> int:
	return _live


## 第 [param index] 发子弹画在屏幕上哪儿。测试拿它确认出手点接上了。
func at(index: int) -> Vector2:
	return _fly[index].position if index >= 0 and index < _shown else Vector2.ZERO


## 一发飞行中的普攻子弹。
##
## 起点用 [member PBProjectile.from] 而不是「射手现在站哪」：射手会跑，
## 而这一发是从他**开火那一刻**站的地方出去的 —— 拿当前位置当起点的话，
## 一边跑一边射的远程会把已经飞出去的子弹整条拖着走。
func _place_shot(
	shot: PBProjectile, battle: PBBattleSim, deployed: Array[PBUnit], field: Vector2
) -> void:
	if _shown >= _fly.size():
		return
	var goal: Vector2 = _goal_of(shot, battle)
	var shooter := _actor_skin(shot.source, not shot.at_ally, battle, deployed)
	var victim := _actor_skin(shot.target, shot.at_ally, battle, deployed)
	var lead: float = 1.0 if goal.x >= shot.from.x else -1.0
	var muzzle: Vector2 = NO_SKIN_MUZZLE if shooter == null else shooter.muzzle()
	var chest: Vector2 = NO_SKIN_CHEST if victim == null else victim.chest()
	var from := PBLayout.to_screen(shot.from, field) + Vector2(muzzle.x * lead, muzzle.y)
	var to := PBLayout.to_screen(goal, field) + chest
	var span: float = shot.from.distance_to(goal)
	var gone: float = 1.0
	if span > 0.0:
		gone = clampf(shot.from.distance_to(shot.pos) / span, 0.0, 1.0)
	_show(_fly[_shown], _shot_skin(shooter), from.lerp(to, gone), to - from, shot.at_ally)
	_shown += 1


## 技能的子弹：**地面档那段施法延迟，本来就是飞行时间**（M8-a）。
##
## [member PBSkill.delay_ticks] 从 M3-b 起就在，它的全部意义是 §02 的预判窗口
## —— 落点在下达时定死、若干 tick 之后才结算。在这之前屏幕上只有一个
## 落点预示圈（[PBTelegraphPool]），**那段时间里什么都没有在飞**。
##
## 所以这里没有新加任何飞行：进度直接读 `lands_at`，
## 伤害与 buff 仍然在 `lands_at` 那一 tick 结算，**一个数都没动**。
##
## 锁定档（治疗、单体）延迟恒为 0（[method PBSkillRules.validate] 拦着），
## 因此走不到这里 —— 它们要真的发一发子弹是 M8-b 的事。
func _place_casts(battle: PBBattleSim, deployed: Array[PBUnit], field: Vector2) -> void:
	var now: int = battle.current_tick()
	for attacker: PBAttacker in battle.attackers():
		for i: int in PBSkillRules.cast_count(attacker):
			if _shown >= _fly.size():
				return
			var cast := PBSkillRules.cast_at(attacker, i)
			if cast == null or not cast.is_pending() or cast.lands_at <= now:
				continue
			if cast.skill.target != PBSkill.Target.GROUND or cast.skill.delay_ticks <= 0:
				continue
			var skin := _actor_skin(attacker.slot, true, battle, deployed)
			var muzzle: Vector2 = NO_SKIN_MUZZLE if skin == null else skin.muzzle()
			var lead: float = 1.0 if cast.spot.x >= attacker.pos.x else -1.0
			var from := (
				PBLayout.to_screen(attacker.pos, field) + Vector2(muzzle.x * lead, muzzle.y)
			)
			# 落点是**地上一个点**，所以终点不加胸口偏移 —— 加了的话
			# 子弹会停在落点上方，而预示圈画在地上，两者对不上。
			var to := PBLayout.to_screen(cast.spot, field)
			var gone: float = 1.0 - float(cast.lands_at - now) / float(cast.skill.delay_ticks)
			var art := PBShotLibrary.skin_for(cast.skill.shot_key)
			_show(
				_fly[_shown],
				PBWhiteModel.shot() if art == null else art,
				from.lerp(to, clampf(gone, 0.0, 1.0)),
				to - from,
				false
			)
			_shown += 1


## 把播报里**新出现**的那几次命中变成火花。
##
## 消化到第几条由本池子自己记 —— 那是它的账（同 [method PBSkillFxPool.echo]）。
## 火花的美术取**打人那一方**配的那份（[method PBShotSkin.anim_hit]），
## 位置取**挨打那一个**的胸口：两处各配一个的话，「子弹打在胸口、
## 火花炸在脚下」迟早发生。
func _echo(
	battle: PBBattleSim, deployed: Array[PBUnit], book: PBBattleLog, field: Vector2
) -> void:
	if book == null:
		return
	for i: int in range(book.fresh_from(_echoed), book.entries.size()):
		var entry: Dictionary = book.entries[i]
		var kind: int = int(entry.get("kind", -1))
		if kind != PBBattleLog.Kind.HIT_ENEMY and kind != PBBattleLog.Kind.HIT_ALLY:
			continue
		var to_ally: bool = kind == PBBattleLog.Kind.HIT_ALLY
		var victim := _actor_skin(int(entry.get("target", -1)), to_ally, battle, deployed)
		var spot := _screen_of(int(entry.get("target", -1)), to_ally, battle, field)
		if spot == PBSkillCast.NO_SPOT:
			continue
		var chest: Vector2 = NO_SKIN_CHEST if victim == null else victim.chest()
		var shooter := _actor_skin(int(entry.get("source", -1)), not to_ally, battle, deployed)
		_spark(_shot_skin(shooter), spot + chest, to_ally)
	_echoed = book.total


## 点一朵火花。池子满了就丢掉这一朵，见 [constant IMPACTS]。
func _spark(art: PBShotSkin, spot: Vector2, at_ally: bool) -> void:
	var slot: int = _free_spark()
	if slot < 0:
		return
	var node: AnimatedSprite2D = _hits[slot]
	_show(node, art, spot, Vector2.ZERO, at_ally, art.resolve(art.anim_hit))
	# **从头播**：这个槽位上一朵可能刚播到一半。不重置的话新的一朵会接着
	# 上一朵的进度演完，表现是「有时候火花只闪半下」。
	node.set_frame_and_progress(0, 0.0)
	var seconds: float = art.hit_seconds()
	_hit_left[slot] = (
		IMPACT_FRAMES
		if seconds <= 0.0
		else maxi(roundi(seconds * float(Engine.physics_ticks_per_second)), 1)
	)


## 一个空的火花槽位。没有就返回 -1。
##
## **按槽位找空位，不把活着的往前挪** —— 挪的话要连贴图、当前帧、播放进度
## 一起搬，而那正是 [AnimatedSprite2D] 最容易搬漏的地方（搬漏的表现是
## 「有一朵火花突然换了个样子」）。
func _free_spark() -> int:
	for i: int in _hits.size():
		if _hit_left[i] <= 0:
			return i
	return -1


## 火花走一个渲染帧。**跟顿帧与暂停无关** —— 它是纯表现，
## 跟着 tick 走的话暂停时会冻在半路上，而玩家暂停正是为了看清刚才发生了什么
## （同 [method PBSkillFxPool.step]）。
func _age() -> void:
	_live = 0
	for i: int in _hits.size():
		if _hit_left[i] <= 0:
			continue
		_hit_left[i] -= 1
		if _hit_left[i] <= 0:
			_hits[i].visible = false
		else:
			_live += 1


## 摆好一个精灵：贴图、位置、朝向、颜色。[param heading] 为零向量时不转。
##
## **只在换了段或者停了才 `play`**：飞行段是循环的，每帧调一次 `play`
## 会把它按在第 0 帧上 —— 表现是「拖尾动画不动」。
func _show(
	node: AnimatedSprite2D,
	art: PBShotSkin,
	spot: Vector2,
	heading: Vector2,
	at_ally: bool,
	anim: StringName = &""
) -> void:
	var wanted: StringName = art.resolve(art.anim_fly) if anim == &"" else anim
	node.visible = true
	node.sprite_frames = art.frames
	node.texture_filter = art.filter_mode()
	node.scale = Vector2.ONE * art.pixel_scale
	node.position = spot
	node.rotation = heading.angle() if art.spin and heading != Vector2.ZERO else 0.0
	node.modulate = (ENEMY_COLOR if at_ally else COLOR) if art.tint_by_side else Color.WHITE
	if node.animation != wanted or not node.is_playing():
		node.play(wanted)


## 这一发在追的那个东西现在在哪（战场坐标）。目标没了就用子弹自己的位置 ——
## 那一帧它正要回池，画在原地比画到 `(0,0)` 好。
func _goal_of(shot: PBProjectile, battle: PBBattleSim) -> Vector2:
	if shot.at_ally:
		var allies := battle.attackers()
		if shot.target >= 0 and shot.target < allies.size():
			return allies[shot.target].pos
		return shot.pos
	var enemies := battle.enemies()
	if shot.target >= 0 and shot.target < enemies.size():
		return enemies[shot.target].pos()
	return shot.pos


## [param slot] 那个单位在屏幕上的**脚底**。查不到返回
## [constant PBSkillCast.NO_SPOT] 当哨兵（战场坐标恒非负，屏幕坐标也是）。
func _screen_of(slot: int, ally: bool, battle: PBBattleSim, field: Vector2) -> Vector2:
	if slot < 0:
		return PBSkillCast.NO_SPOT
	if ally:
		for one: PBAttacker in battle.attackers():
			if one.slot == slot:
				return PBLayout.to_screen(one.pos, field)
		return PBSkillCast.NO_SPOT
	var enemies := battle.enemies()
	if slot >= enemies.size():
		return PBSkillCast.NO_SPOT
	return PBLayout.to_screen(enemies[slot].pos(), field)


## [param slot] 那个单位的形象。查不到返回 null（调用方退回默认偏移）。
##
## 己方走 [member PBCharacter.actor_key]，敌人走
## [method PBEnemyPool.skin_key] —— **两条路都和画那个人的池子读同一个键**，
## 各查各的话「子弹从胸口出、人却是另一张皮」迟早发生。
func _actor_skin(
	slot: int, ally: bool, battle: PBBattleSim, deployed: Array[PBUnit]
) -> PBActorSkin:
	if slot < 0:
		return null
	if ally:
		if slot >= deployed.size():
			return null
		return PBActorLibrary.skin_for(deployed[slot].character.actor_key)
	var enemies := battle.enemies()
	if slot >= enemies.size():
		return null
	var enemy: PBEnemy = enemies[slot]
	return PBActorLibrary.skin_for(
		PBEnemyPool.skin_key(enemy.element, enemy.rank, enemy.ranged)
	)


## 这个人的普攻子弹长什么样。没有皮、或者皮上没填就退回白模。
func _shot_skin(shooter: PBActorSkin) -> PBShotSkin:
	if shooter == null:
		return PBWhiteModel.shot()
	var art := PBShotLibrary.skin_for(shooter.shot_key)
	return PBWhiteModel.shot() if art == null else art


func _make() -> AnimatedSprite2D:
	var node := AnimatedSprite2D.new()
	node.visible = false
	# 子弹和火花都以自己的中心为准 —— 它们不站在地上，没有脚底锚点这回事。
	node.centered = true
	add_child(node)
	return node
