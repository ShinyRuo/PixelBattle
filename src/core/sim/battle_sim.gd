class_name PBBattleSim
extends RefCounted
## 单波战斗的**逐 tick** 模拟。M0 起取代 [PBCombatRules] 的解析式排队模型。
##
## 和排队模型的关系：**语义刻意保持一致，好让两者能对拍。**
## 排队模型是这个模型在「输出恒定、单目标、敌人不还手」前提下的闭式解，
## 所以同样输入下两者的结果应该很接近。`tests/test_battle_sim.gd` 里
## 有一组对拍断言把这个一致性锁住 —— 改坏任何一边都会红。
##
## ## 每个 tick 干七件事，顺序不能换
##
## 1. **大招** —— 先结算落地的，再下达新的，见 [method _resolve_ultimates]
## 2. **己方跑动** —— 射程内没目标就往前压，见 [method _move_attackers]
## 3. **定攻击目标** —— 每人一个，画线与开火共用一份，见 [method _aim_targets]
## 4. **己方分配伤害** —— 每个攻击者各自在射程内选目标，见 [method _deal_damage]
## 5. **敌人还手** —— 咬住射程内的己方单位，见 [method _enemies_attack]
## 6. **推进位置** —— 先打后走：一个敌人在抵达那一 tick 仍然可以被打死，
##    这与排队模型的 `would_die_at <= arrives_at` 是同一条边界。
##    **咬住了人的敌人这一 tick 不动**；没咬住的**扑向最近的活忍者**，
##    场上一个活人都没有了才走基地，抵达基地的算漏怪（M5-7）
## 7. **防挤** —— 把重合的单位推开，见 [method _separate]
##
## 己方先打是有意的：一个刚被打死的敌人不该在同一 tick 还手，
## 反过来则会让「抢先手」变成一个玩家无法感知却影响每一场的隐形规则。
##
## ## M3-a：从一个标量 DPS 换成一组 [PBAttacker]
##
## M0 的模型里整队是**一个**标量 DPS，每 tick 全砸在最前面那个敌人身上。
## 那是「单服务台排队」，而 M0 已经证明它在数学上不存在中间态 ——
## 战场空旷 / 单波 12 秒 / BOSS 比精英轻松三条缺口同出于此。
##
## **不传 [param attackers] 时整队折成一个覆盖全场的单体攻击者，行为与 M0
## 逐字节相同** —— 那条退化路径是有意留的，见 [method PBAttacker.whole_field]。
##
## ## M3-b：大招与落点
##
## 每个攻击者可以带一个 [PBUltimate]：长冷却、一次性、**有落点**，
## 而且落点在下达时定死、若干 tick 之后才落地。那个延迟是 §02
## 「PC 可预判走位」成立的前提，理由见 [PBUltimate] 顶部。
## 落点怎么挑由 [PBAimRules] 决定 —— 手机端看当前帧，PC 端看落地那一刻。
##
## ## M3.5-b：敌人还手，忍者会死
##
## 敌人拿到攻速与射程，会**咬住射程内最近的己方单位**并停止推进；
## 己方单位有血、有防、有防元素，会被打死，死了就不再输出也不再放大招。
## **每波开波全员满血复活**（§03A）—— 一波之内的失误有真实代价，
## 但不会毁掉整局。
##
## **`max_hp == 0` 的攻击者敌人看不见**，那是 [method PBAttacker.whole_field]
## 造出来的退化标量。这条约定让 M3-a 的对拍锚点原样活着，不用加配置开关。
##
## ## 还没有的东西
##
## **装备与羁绊只加攻不加防** —— §10 那两件防御装、§11 一尾的减伤光环
## 仍然按「诚实的 0」填着，接上它们是装备改造那一步的事。
## （「普攻输出恒定」那一条 M4-b 已经不成立：出手是离散的。）

## 同屏最多几发子弹（M4-b）。
##
## 出战席 10 人，最慢的攻速约 0.85 次/秒（间隔 24 tick），最快也就几 tick 一发；
## 飞完全场 0.35 秒 = 7 tick。也就是说同时在飞的远不到 10 发。
## 64 是个宽到不用再想的数，而池子按上限一次建满（§14）。
const SHOT_CAPACITY: int = 64

## 安全阀：单波最多跑这么多 tick。
##
## 正常情况下战斗必定结束（敌人每 tick 都在前进，迟早抵达基地）。
## 这个上限是防「速度配成 0」之类的配置错误把批量模拟挂死 ——
## 死循环在跑几万局的场景里表现为「卡住不动」，极难定位。
const MAX_TICKS: int = 20000

## 战斗播报（§02，M6-j）。**默认 null = 一个字都不记** ——
## 批量扫描一局跑几万 tick，记下来的东西没有任何人会看。
## 只有画面那一路塞得进来，见 [PBBattleLog]。
var log_to: PBBattleLog = null

var _cfg: PBSimConfig
var _wave: PBWave
var _enemies: Array[PBEnemy] = []
var _outcome: PBCombatOutcome

## 本波的己方攻击者，按出战席顺序。**遍历顺序固定，不排序、不打乱** ——
## 两个攻击者同 tick 打同一个目标时，谁先打决定了溢出伤害归谁，
## 顺序一变结果就变，而那种差异在批量统计里只表现为「波次悄悄偏了一点」。
var _attackers: Array[PBAttacker] = []

## 一个敌人漏进基地扣多少血，防御科技减伤已经算进去了。
var _leak_damage: float = 0.0

## 飞行中的子弹（M4-b）。**一次建满、之后只改字段**，和敌人池同一条规矩（§14）。
var _shots: Array[PBProjectile] = []

## 子弹每 tick 飞多远。由 `projectile_cross_seconds` 反推，不是新拍的参数。
var _shot_speed: float = 0.0

var _enemy_speed: float = 0.0
var _tick: int = 0

## 大招落点策略（§02 的双端差异）。从配置抄一份，一波之内不变。
var _aim_policy: PBAimRules.Policy = PBAimRules.Policy.AUTO

## 手动档最多攒多少 tick 就得放。由 `ultimate_max_hold_seconds` 换算。
var _max_hold_ticks: int = 0

## 场上的减速与全队增伤（M3-d，§11 的一尾 / 五尾 / 二尾）。
##
## **两个都是「场」的属性，不是单位的属性。** 减速存到每个敌人身上的话，
## 减速期间新出场的敌人会漏掉它；增伤存到每个攻击者身上的话，
## 每次生效和失效都要遍历改一遍缓存的每 tick 伤害。存在这里只有一份，
## 到期就是一个下标比较。
##
## **同类效果后来者覆盖前者**，不叠加也不取最强。当前一局只有一只尾兽、
## 冷却 75 秒，两次同类效果不可能重叠；等 §09 的功能档进来真会重叠时，
## 「怎么叠」是一个要有依据的设计决定，不该现在拍一个。
var _slow_scale: float = 1.0
var _slow_until: int = -1
var _buff_scale: float = 1.0
var _buff_until: int = -1

## 队伍最前面那个还活着的敌人在 [member _enemies] 里的下标。
##
## 全体敌人同速前进、且按出场顺序排列，所以**数组顺序天然就是距离顺序** ——
## 不需要每 tick 排序找目标，从这个游标往后扫就行。
var _front: int = 0


## [param attackers] 为空时走退化路径：整队折成一个覆盖全场的单体攻击者，
## 此时 [param dps] 就是整队 DPS，行为与 M0 完全相同。
## 给了攻击者列表时 [param dps] 不参与战斗结算 —— 它只是个报数用的汇总量，
## 而汇总量按定义等于各攻击者之和（见 [method PBCombatRules.build_attackers]）。
func _init(
	wave: PBWave,
	dps: float,
	def_reduction: float,
	cfg: PBSimConfig,
	attackers: Array[PBAttacker] = []
) -> void:
	_cfg = cfg
	_wave = wave
	_outcome = PBCombatOutcome.new()
	_aim_policy = cfg.aim_policy
	_max_hold_ticks = int(round(cfg.ultimate_max_hold_seconds * float(cfg.tick_rate)))
	_attackers = attackers
	if _attackers.is_empty():
		var solo: Array[PBAttacker] = [PBAttacker.whole_field(dps, cfg.field_diagonal())]
		_attackers = solo
	for attacker: PBAttacker in _attackers:
		attacker.prime(cfg.tick_rate)
		# 开波满血（§03A）。和大招的冷却一样，攻击者对象会跨波、跨探测复用，
		# 不重置的话上一场的残血会漏进这一场，表现为「同一支队伍越探越弱」。
		attacker.revive()
		# 大招对象跨波、跨探测复用，不清的话上一场剩下的冷却会漏进这一场。
		if attacker.ultimate != null:
			attacker.ultimate.reset()

	var leak_mult: float = cfg.boss_leak_mult if wave.is_boss() else 1.0
	_leak_damage = wave.atk_each * leak_mult * (1.0 - clampf(def_reduction, 0.0, 0.95))

	# 速度由 march_seconds 反推：那个参数的含义本来就是「走完全场要多久」。
	# 这里没有引入新的拍脑袋参数，只是换了个表达。
	var march_ticks: float = maxf(cfg.march_seconds, 0.001) * float(cfg.tick_rate)
	_enemy_speed = cfg.field_length / march_ticks
	# 子弹速度同理由「飞完全场要几秒」反推。0 秒 = 瞬时命中。
	if cfg.projectile_cross_seconds > 0.0:
		_shot_speed = cfg.field_length / (cfg.projectile_cross_seconds * float(cfg.tick_rate))

	_shots.resize(SHOT_CAPACITY)
	for i: int in SHOT_CAPACITY:
		_shots[i] = PBProjectile.new()

	_spawn_all(wave, cfg)


## 推进一个 tick。战斗已结束时什么都不做。
func step() -> void:
	if is_finished():
		return
	_tick += 1
	_resolve_ultimates()
	_move_attackers()
	# **排在跑动之后**：目标是「他站定之后打得到谁」，跑动之前算的是上一帧的位置。
	_aim_targets()
	# **飞行结算排在出手之前**（M4-b）：这一 tick 发出去的子弹不该在
	# 同一 tick 落地，否则飞行时间等于 0，离散出手就退回成瞬时伤害了。
	# 这和大招「先结算落地的、再下达新的」是同一条理由。
	_advance_shots()
	_deal_damage()
	_enemies_attack()
	_advance_and_leak()
	_separate()


## 一路跑到战斗结束，返回结算结果。批量模拟走这个入口。
func run_to_end() -> PBCombatOutcome:
	while not is_finished() and _tick < MAX_TICKS:
		step()
	return result()


func is_finished() -> bool:
	return _front >= _enemies.size()


## 结算结果。战斗没结束也能取，拿到的是「到目前为止」的快照。
func result() -> PBCombatOutcome:
	_outcome.cleared = _outcome.leaked == 0 and is_finished()
	_outcome.ticks = _tick
	_outcome.battle_seconds = float(_tick) / float(_cfg.tick_rate)
	return _outcome


## 全部敌人，含还没出场和已经死掉的。**渲染层只读，不要改。**
func enemies() -> Array[PBEnemy]:
	return _enemies


## 全部己方攻击者，含已经阵亡的。**渲染层只读，不要改。**
##
## 战场上要画得出自己的忍者（§02 第 8 点）—— M3-a 把整队标量拆成一组
## [PBAttacker] 之后，「谁站在哪、还剩多少血」第一次是有答案的，
## 而那个答案在这里之前没有出口，画面上于是只有敌人。
func attackers() -> Array[PBAttacker]:
	return _attackers


## 飞行中的子弹，含已经回池的（`alive` 为 false）。**渲染层只读，不要改。**
func shots() -> Array[PBProjectile]:
	return _shots


func current_tick() -> int:
	return _tick


## 出场时刻已到、且还活着的敌人 —— 渲染层要画的就是这些。
func active_enemies() -> Array[PBEnemy]:
	var out: Array[PBEnemy] = []
	for enemy: PBEnemy in _enemies:
		if enemy.is_active(_tick):
			out.append(enemy)
	return out


## 一次性把整波敌人建好，出场时刻算在这里。
##
## 全部预分配、之后只改字段不再 `.new()` —— §14 对 sim 层的要求。
func _spawn_all(wave: PBWave, cfg: PBSimConfig) -> void:
	_enemies.resize(wave.count)
	var window_ticks: float = cfg.spawn_window * float(cfg.tick_rate)
	# 出手间隔与一发的伤害：和己方同一条换算（[method PBAttacker.prime]）——
	# 由间隔反推一发打多少，平均输出因此分毫不差。
	var interval: int = maxi(
		int(round(float(cfg.tick_rate) / maxf(cfg.enemy_attack_speed, 0.001))), 1
	)
	var per_shot: float = (
		wave.atk_each * cfg.enemy_attack_speed * float(interval) / float(cfg.tick_rate)
	)
	for i: int in wave.count:
		var enemy := PBEnemy.new()
		enemy.slot = i
		var at_tick: int = 0
		if wave.count > 1:
			at_tick = int(round(window_ticks * float(i) / float(wave.count - 1)))
		# 出生在方阵里（M4-d）：第一列在战场边缘，后面几列排在战场之外。
		enemy.spawn(wave, _enemy_speed, cfg.enemy_start_x(i), at_tick, cfg.enemy_lane(i))
		# 远近两种打法（M4-c）。谁是远程按槽位定死，不掷骰 ——
		# 理由见 [member PBSimConfig.enemy_ranged_share]。
		if cfg.enemy_is_ranged(i):
			enemy.arm(cfg.enemy_reach_ranged, interval, per_shot, _shot_speed)
		else:
			enemy.arm(cfg.enemy_reach, interval, per_shot, 0.0)
		_enemies[i] = enemy


## 大招：先结算落地的，再下达新的。**顺序不能反。**
##
## 反过来的话，同一 tick 下达的大招会在下达的那一瞬间就落地，
## 施法延迟等于 0 —— 而那个延迟正是 §02 分层验收的全部依据
## （见 [PBUltimate] 顶部）。
func _resolve_ultimates() -> void:
	for attacker: PBAttacker in _attackers:
		var ult: PBUltimate = attacker.ultimate
		if ult == null:
			continue
		# 已经下达的照样落地，哪怕施法者中途死了 —— 大招已经出手了。
		# 那是 §02 施法延迟的直接后果，也是「预判」这件事的对称代价。
		if ult.is_pending() and _tick >= ult.lands_at:
			_land_ultimate(ult)
	for attacker: PBAttacker in _attackers:
		attacker.regen_mana()
	for attacker: PBAttacker in _attackers:
		var ult: PBUltimate = attacker.ultimate
		if ult == null or not attacker.alive or not ult.is_ready(_tick):
			continue
		# 第二道门槛（M3.5-d）：冷却转好了还得有蓝。
		# 这道门槛让六尾的「重置全体 CD」不再是免费的连放。
		if not attacker.can_pay(ult.mp_cost):
			continue
		var spot := PBAimRules.pick_spot(
			_aim_policy,
			_enemies,
			_tick,
			ult,
			_tick - ult.ready_at,
			_cfg.ultimate_min_targets,
			_cfg.ultimate_hold_targets,
			_max_hold_ticks
		)
		if PBUltimate.is_spot(spot):
			_order(attacker, spot)
	_skip_dead()


## 玩家亲手下达一发大招（§02，M5-9）。放得出来返回 true。
##
## ## 为什么手动要有一条自己的入口
##
## [method _resolve_ultimates] 那一支是 [PBAimRules] 替玩家挑落点的，
## 也就是 §02 的**自动档**（手机端）。玩家自己点落点时那一整套「值不值得放、
## 要不要再攒一会儿」的判断都不该发生 —— 他点了就是要放。
##
## 门槛仍然是同一组（活着 / 冷却好了 / 蓝够），**而且必须共用一份**：
## 各写一份的话「按钮亮着但点了没反应」迟早出现，而它不报错。
func cast_ultimate(attacker: PBAttacker, spot: Vector2) -> bool:
	if not can_cast(attacker) or not PBUltimate.is_spot(spot):
		return false
	_order(attacker, spot)
	return true


## 这个人现在放不放得出大招。**指令卡那一格的亮/灰读的就是它。**
func can_cast(attacker: PBAttacker) -> bool:
	if attacker == null or not attacker.alive or attacker.ultimate == null:
		return false
	return attacker.ultimate.is_ready(_tick) and attacker.can_pay(attacker.ultimate.mp_cost)


## 下达一发：扣蓝、定落点、进冷却。自动与手动共用这一段。
##
## 蓝在**下达**时扣，不是落地时 —— 落地时扣的话，施法延迟那段窗口里
## 还能再下达一发（蓝还没扣掉），于是延迟越长反而放得越多，
## 和冷却从落地算是同一个道理。
func _order(attacker: PBAttacker, spot: Vector2) -> void:
	attacker.pay(attacker.ultimate.mp_cost)
	attacker.ultimate.cast(spot, _tick)
	# **播报记在下达这一刻，不是落地那一刻**（M6-j）：玩家点下去就该看见
	# 回音，而落地还隔着一整段施法延迟（那段延迟正是 §02 要的预判窗口）。
	if log_to != null:
		log_to.ultimate(_tick, attacker.slot)


## 一发大招落地：范围内每个敌人各吃一份完整伤害，聚拢/击退的还会被挪位置。
##
## 和 [method _strike_area] 一样**不结算溢出** —— 大招的价值写在命中数上
## （§02 那条 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`），
## 再让它吃溢出的话，一发大招在密集波里等于无限伤害。
##
## 落地之后还要结算三样**全场**效果（M3-d）：减速、全队增伤、重置冷却。
## 它们和圈人无关，所以放在循环外面。
func _land_ultimate(ult: PBUltimate) -> void:
	var hits: int = 0
	for i: int in range(_front, _enemies.size()):
		if ult.max_targets > 0 and hits >= ult.max_targets:
			break
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive:
			continue
		# M4-a 起是真圆（[member PBUltimate.radius]）。
		if enemy.pos().distance_to(ult.spot) > ult.radius:
			continue
		hits += 1
		if enemy.take_damage(ult.damage):
			_outcome.kills += 1
			continue
		# 活下来的才挪 —— 挪一个尸体没有意义，而且会让「聚拢值多少」虚高。
		if ult.gather:
			# 聚拢是**两轴一起**拖到落点上：只拖 x 的话一圈人会被拉成
			# 一条横线，而「聚成一堆」正是这个机制唯一的产出。
			enemy.distance = ult.spot.x
			enemy.lane = ult.spot.y
		elif ult.knockback > 0.0:
			# 击退只作用在推进轴上 —— 它买的是「敌人晚到基地多久」。
			# 上限是**他自己的出生点**，不是战场长度：方阵后面几列出生在
			# 战场之外，拿战场长度封顶会把他们往前拽（见 [member PBEnemy.start_x]）。
			enemy.distance = minf(enemy.distance + ult.knockback, enemy.start_x)
	_apply_field_effects(ult)
	ult.land(_tick)


## 大招落地时的三样全场效果：减速、全队增伤、重置**其他**大招的冷却。
##
## 重置清的是别人不是自己 —— 自己也清的话它会在同一 tick 反复自我重置。
## 这一条（§11 六尾）的强度与队伍里大招的总量成正比，而不是和它自己的
## 数值成正比，所以它在数据上伤害为 0 却可能是最强的一只。
func _apply_field_effects(ult: PBUltimate) -> void:
	if ult.slow_ticks > 0 and ult.slow_scale < 1.0:
		_slow_scale = ult.slow_scale
		_slow_until = _tick + ult.slow_ticks
	if ult.buff_ticks > 0 and ult.team_damage_scale > 1.0:
		_buff_scale = ult.team_damage_scale
		_buff_until = _tick + ult.buff_ticks
	if not ult.reset_cooldowns:
		return
	for attacker: PBAttacker in _attackers:
		var other: PBUltimate = attacker.ultimate
		if other != null and other != ult and not other.is_pending():
			other.ready_at = _tick


## 这一 tick 敌人走多快。1.0 是正常速度，减速生效期间小于 1。
func _speed_scale() -> float:
	return _slow_scale if _tick <= _slow_until else 1.0


## 这一 tick 的普攻伤害倍率。1.0 是正常，全队增伤生效期间大于 1。
func _damage_scale() -> float:
	return _buff_scale if _tick <= _buff_until else 1.0


## 把这一 tick 的伤害打出去。**每个攻击者各自选目标，互不共享伤害池。**
##
## 「不共享」是这次改造的全部意义所在：整队一个池子就是单服务台排队，
## 而单服务台没有中间态。各打各的之后，射程外的敌人对某个攻击者不存在，
## 于是同一波敌人会被分批处理，战场上才可能长期有人。
func _deal_damage() -> void:
	for attacker: PBAttacker in _attackers:
		# 死人不输出。M3.5-b 之前这一行不存在，因为没有人会死。
		# 冷却没转好也不出手（M4-b）—— 连续输出那条退化路径间隔是 1 tick，
		# 所以它每 tick 都过得了这道门，行为和离散化之前一模一样。
		if not attacker.alive or not attacker.ready_to_fire(_tick):
			continue
		var fired: bool = (
			_strike_area(attacker)
			if attacker.shape == PBAttacker.Shape.AOE
			else _strike_single(attacker)
		)
		# **打空了不进冷却。** 进的话，射程内暂时没人的那几 tick 会白白
		# 吃掉一个间隔，等敌人走进来时他还得再等 —— 表现是「远程有时候发呆」。
		if fired:
			attacker.on_fired(_tick)
	_skip_dead()


## 子弹飞一个 tick，够到目标就结算（M4-b）。
##
## 目标死了子弹就消失，**不改打别人** —— 理由写在 [PBProjectile] 顶部。
func _advance_shots() -> void:
	for shot: PBProjectile in _shots:
		if not shot.alive:
			continue
		if shot.at_ally:
			_fly_at_ally(shot)
		else:
			_fly_at_enemy(shot)
	_skip_dead()


func _fly_at_enemy(shot: PBProjectile) -> void:
	var enemy: PBEnemy = _enemies[shot.target]
	if not enemy.alive:
		shot.retire()
		return
	if not shot.fly(enemy.pos()):
		return
	_note_hit(shot.source, enemy.slot, shot.damage, false)
	if enemy.take_damage(shot.damage):
		_outcome.kills += 1
	shot.retire()


## 敌人的子弹（M4-c）。伤害在**命中时**才按防御与属性折算 ——
## 出膛时算的话，飞行途中换了减伤（装备、光环）就对不上了，
## 而那种偏差只表现为「同一发子弹有时候疼有时候不疼」。
func _fly_at_ally(shot: PBProjectile) -> void:
	var target: PBAttacker = _attackers[shot.target]
	if not target.is_targetable():
		shot.retire()
		return
	if not shot.fly(target.pos):
		return
	var hurt: float = PBStatRules.strike_damage(
		shot.damage, shot.element, target.defence, target.def_element, _cfg
	)
	_note_hit(shot.source, target.slot, hurt, true)
	if target.take_damage(hurt):
		_outcome.allies_lost += 1
		_note_down(target.slot)
	shot.retire()


## 记一次命中。**每个见血的地方都走这一句**，而不是各写一遍
## `if log_to != null` —— 漏一处的表现是「某一种攻击方式在日志里不存在」，
## 而那要盯着日志看很久才发现。
func _note_hit(source: int, target: int, amount: float, to_ally: bool) -> void:
	if log_to != null:
		log_to.hit(_tick, source, target, amount, to_ally)


## 记一个忍者倒下。**怪物死了不记**（玩家定的）：一波死几十只，
## 每只一行会把另外五种播报全部冲掉，见 [enum PBBattleLog.Kind]。
func _note_down(slot: int) -> void:
	if log_to != null:
		log_to.ally_down(_tick, slot)


## 找一发空子弹。池子满了返回 null —— 那时**这一发就没了**，
## 不扩池也不覆盖别人：扩池会在热路径里分配（§14），
## 覆盖会让一发已经在飞的伤害凭空消失，而两者都不报错。
func _free_shot() -> PBProjectile:
	for shot: PBProjectile in _shots:
		if not shot.alive:
			return shot
	return null


## 己方跑动（§02 / §03A，M3.5-c）。**射程内没目标就往前压，有目标就站住开火。**
##
## ## 为什么不是「一路跑向最近的敌人」
##
## 那会推翻 §02 的射程梯度：所有人都跑到最前面接敌，战斗退回成 M3-a 之前的
## 单点集火，而那条梯度正是「场上稳定有人」的唯一来源（1.7 → 6.0）。
##
## 所以跑动被 [member PBAttacker.leash] 拴在自己的站位附近，
## 而且**只在打不着的时候才往前** —— 于是超远程几乎不动（它本来就够得着），
## 近战会真的迎上去。射程档因此从「站在哪一列」变成「跑到多近就停」，
## 梯度靠停火距离维持，不靠固定坐标。
##
## ## 三条互斥的状态，顺序就是优先级（M4-c）
##
## 1. **够得着 → 站住。** 交战中绝不挪窝
## 2. **够不着 → 按自己的打法靠过去**（近战贴身、远程只前压）
## 3. **场上一个活人都没有 → 慢慢走回自己的位置**
##
## 第 1 条是 M4-c 修掉的那个 bug：在它之前，「够得着」走的是「回家」那一支，
## 于是敌人贴到脸上时忍者**边打边往基地退**。看起来荒谬，代码里却很自然 ——
## 「回家」是默认值，而「压上去」是唯一的例外分支，中间那档没人写。
##
## 第 3 条不能省：不退的话，一波打完全队会停在最前沿，
## 下一波开波的阵型就不是玩家排的那个了。
func _move_attackers() -> void:
	for attacker: PBAttacker in _attackers:
		if not attacker.alive or attacker.move_speed <= 0.0:
			continue
		var target := _nearest_enemy(attacker)
		if target == null:
			attacker.pos = attacker.pos.move_toward(attacker.home, attacker.move_speed)
			continue
		if attacker.can_reach(target.pos()):
			continue
		var leash: float = _leash_for(attacker, target)
		if attacker.shot_speed > 0.0:
			_press_forward(attacker, target, leash)
		else:
			_close_in(attacker, target, leash)


## 这一 tick 这根皮带绳有多长。平时就是 [member PBAttacker.leash]，
## **一种情形下松开**：目标已经站定（[member PBEnemy.engaged]），
## 而且绳子够不着它。
##
## ## 为什么必须有这个例外
##
## 敌人一走进自己的射程就**永久站住**。它站的位置由「最靠前的那个忍者」决定，
## 而忍者能走多远由**他自己的站位**决定 —— 两把尺子量的不是同一件事，
## 于是很容易出现一个谁都够不着的位置。M5-8 之前的实测：一队全近战
## （皮带绳顶到 0.65）对上停在 0.80 放枪的远程敌人，**105 秒、每人打出
## 6 下、全灭** —— 屏幕上是四个忍者站成一排挨枪，一动不动。
##
## ## 为什么条件是「已经站定」，不是「够不着」
##
## 只看够不着的话，开波那一刻全部敌人都在 x≥1.0，近战忍者的活动范围
## （0.67）本来就罩不住 —— 绳子当场松开，他会**冲向出怪点**，
## 把自己送到远离远程队友的地方单挑整波。
##
## 站定的那个已经不动了，追它是一段有终点的路；迎面走来的那一群不是。
func _leash_for(attacker: PBAttacker, target: PBEnemy) -> float:
	if not target.engaged:
		return attacker.leash
	if attacker.home.distance_to(target.pos()) <= attacker.leash + attacker.reach:
		return attacker.leash
	# 松开就是彻底松开：够不着的那一截没有一个「多给一点」的自然长度，
	# 给一个中间值只会把死局挪到下一个位置上，而现象一模一样。
	return _cfg.field_diagonal()


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
## 补法是掉头走 [method _close_in]（**二维靠过去，停在射程边缘**），
## 而不是放开皮带绳：绳子仍然拴着，所以他挪的是自己那一格附近，
## 不是横穿半个战场去接敌。
func _press_forward(attacker: PBAttacker, target: PBEnemy, leash: float) -> void:
	if absf(target.pos().y - attacker.pos.y) >= attacker.reach:
		_close_in(attacker, target, leash)
		return
	# 二维之后「刚好够得着」要先扣掉纵向差的那一截，见 [method PBAttacker.reach_stop_x]。
	var want: float = minf(attacker.reach_stop_x(target.pos()), attacker.home.x + leash)
	attacker.pos.x = _step_toward(attacker.pos.x, maxf(want, attacker.home.x), attacker.move_speed)


## 近战：**二维贴上去**，停在自己的接触距离上。
##
## 停在射程边缘而不是踩到对方身上：踩上去的话防挤会立刻把两边推开，
## 而推开之后又够不着了 —— 整场战斗表现为近战在敌人身上来回抖。
##
## 皮带绳按**二维距离**量（[member PBAttacker.leash]）。放开它就等于
## 「自由跑向敌人」，所有人挤到最前面接敌，§02 的射程梯度
## （「场上稳定有人」的唯一来源，实测 1.7 → 6.0）就没了。
func _close_in(attacker: PBAttacker, target: PBEnemy, leash: float) -> void:
	var at := target.pos()
	var gap: Vector2 = at - attacker.pos
	var want: float = gap.length()
	var stop: Vector2 = at if want <= 0.0 else at - gap / want * attacker.reach
	var from_home: Vector2 = stop - attacker.home
	var leashed: float = from_home.length()
	if leashed > leash:
		stop = attacker.home + from_home / leashed * leash
	attacker.pos = attacker.pos.move_toward(stop, attacker.move_speed)


## 离 [param attacker] 最近的、已出场且活着的敌人。没有就返回 null。
##
## ## 为什么从「打得最深的那个」换成「离我最近的」
##
## M3.5-c 挑的是最深的那个，理由是省一遍扫描，而且「守方该迎向威胁最大的」。
## 那在一维、所有人共用一个目标时说得通；**近战 AI 一进来就不成立了** ——
## 一个站在下半场的近战会越过身边的敌人去追一个远在另一条泳道的「最深」目标，
## 而玩家看到的是他从怪堆里穿过去。
##
## 代价是每个攻击者各扫一遍（10 × 48 ≈ 480 次比较/tick），
## 和 [method _enemies_attack] 那一遍同量级，不是新的数量级。
func _nearest_enemy(attacker: PBAttacker) -> PBEnemy:
	# 玩家点名了就朝那个走（§02，M4-e）—— **哪怕现在够不着**，
	# 那正是「点他」的意思。皮带绳照旧拴着，所以他不会横穿半个战场。
	var named := _named_target(attacker)
	if named != null:
		return named
	var best: PBEnemy = null
	var best_gap: float = 0.0
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			# 后面的出场更晚，这一 tick 不会再有目标了。
			break
		if not enemy.alive:
			continue
		var gap: float = attacker.pos.distance_to(enemy.pos())
		if best == null or gap < best_gap:
			best = enemy
			best_gap = gap
	return best


## 玩家点名的那个敌人，**这一 tick 还算不算数**（活着、已出场）。不算就 null。
##
## 三处读它：走位（[method _nearest_enemy]）、开火（[method _first_reachable]）、
## 画线（[method _aim_targets]）。抄成三份的话「点名什么时候失效」会有三个答案，
## 而分叉的表现是**线、脚、枪各指一个人**。
func _named_target(attacker: PBAttacker) -> PBEnemy:
	if attacker.forced_target < 0 or attacker.forced_target >= _enemies.size():
		return null
	var named: PBEnemy = _enemies[attacker.forced_target]
	return named if named.alive and named.has_spawned(_tick) else null


## 每人这一 tick 的攻击目标（M5-12），存进 [member PBAttacker.aim_at]。
##
## 三档取第一个有的：**有效点名 → 射程内最靠近基地的 → 全场最近的**。
## 后两档正是 [method _first_reachable] 与 [method _nearest_enemy] 的自动部分；
## 第一档**不问射程** —— 玩家点了一个还没走到的人，意思是「去打他」，
## 而 [method _move_attackers] 也确实会朝他走。
##
## **它不决定伤害打给谁**：开火仍走 [method _first_reachable]，
## 点名够不着时自动规则接管照旧（见 [member PBAttacker.forced_target]）。
## 所以两个答案可以不同 —— 那时画面上是「线指着他要去打的那个，
## 手上打着路过的那个」，而那是实情。
##
## **单独一遍，不搭在开火那一遍上**：搭上去会继承 [method _deal_damage]
## 的冷却与射程两道门槛，见 [member PBAttacker.aim_at]。
func _aim_targets() -> void:
	for attacker: PBAttacker in _attackers:
		_aim_one(attacker)


func _aim_one(attacker: PBAttacker) -> void:
	var mark: PBEnemy = null
	if attacker.alive:
		mark = _named_target(attacker)
		if mark == null:
			mark = _first_reachable(attacker)
		if mark == null:
			mark = _nearest_enemy(attacker)
	attacker.aim_at = -1 if mark == null else mark.slot


## 玩家点名一个敌人（[param slot] 为 -1 = 交回自动选敌）。**点名的唯一入口。**
##
## ## 为什么不能让渲染层自己写那个字段
##
## 因为点名要**立刻**改变「他要打谁」，而那件事由 [method _aim_one] 算。
## 只写 [member PBAttacker.forced_target] 的话，绿线要等
## [method _aim_targets] 下一次跑才切过去 —— 而**暂停时那一遍不跑**。
## 于是玩家在暂停下点了一个敌人，画面上一动不动，直到他取消暂停。
##
## §02 特意允许暂停下操作，那一刻的即时反馈正是这两步操作的全部意义
## （不然玩家无从知道自己那一下点中了没有）。
func name_target(attacker: PBAttacker, slot: int) -> void:
	if attacker == null:
		return
	attacker.forced_target = slot
	_aim_one(attacker)


static func _step_toward(from: float, to: float, step: float) -> float:
	if absf(to - from) <= step:
		return to
	return from + (step if to > from else -step)


## 防挤：把重合的单位推开（§03A，M3.5-c）。**两边都做**，实现在 [PBCrowdRules]。
##
## 搬出去的理由和 [PBFieldPicker] 当初从 [PBBattleView] 里分出来一样：
## 它只按位置把人推开，不看血、不看射程、不看谁在打谁 —— 边界说得清。
func _separate() -> void:
	PBCrowdRules.separate_enemies(
		_enemies, _front, _tick, _cfg.unit_min_gap, _cfg.field_height
	)
	PBCrowdRules.separate_attackers(_attackers, _cfg.unit_min_gap)


## 敌人还手（§03A，M3.5-b）。**咬住射程内最近的己方单位，并停止推进。**
##
## ## 为什么咬住了就不走
##
## 那是 War3 的交战行为，也是这套玩法成立的前提：忍者是一堵**墙**，
## 漏怪意味着墙破了，而不是「时间到了自然会漏」。
## 边打边走的话，防御和血量只能影响「这个人还能输出几秒」，
## 影响不了「敌人到没到基地」—— 坦克、前排、§02 的站位全部贬值。
##
## ## 目标是「离我最近的」，不是「血最少的」
##
## 挑血最少的等于让敌人有集火 AI，那会让玩家的站位失去意义
## （站哪都会被点名）。挑最近的之后，**站得靠前的先挨打**，
## 于是「谁站前排」成为一个有后果的决定 —— 而站位是射程的派生量（§02），
## 玩家因此可以通过选人来选谁扛。
func _enemies_attack() -> void:
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		enemy.engaged = false
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive or enemy.damage_per_shot <= 0.0:
			continue
		var target := PBTargetRules.nearest_defender(_attackers, enemy)
		if target == null:
			continue
		# **M5-7 起远近都咬住。**
		#
		# ## M4-c 到 M5-6 之间只有近战会停
		#
		# 那时的理由是死锁：远程敌人射程 0.30，己方近战只有 0.12 且被
		# 0.10 的皮带绳拴着 —— 远程停下来就站在一个「我打得到你、
		# 你打不到我」的位置上，一队全近战会把那一波卡上十几分钟。
		#
		# ## 那个前提在 M5-7 被两条改动一起拆掉了
		#
		# 皮带绳放到 0.35（[member PBSimConfig.unit_leash]），近战够得着
		# 停在 0.30 上的远程敌人了；而敌人现在会**主动扑向最近的活忍者**
		# （[method _advance_and_leak]），不再是沿直线路过。
		#
		# 于是「远程边走边射」反而成了错的那一个：它会**从活着的忍者
		# 身边溜过去扣基地血**，而玩家点名要的正是
		# 「只有场上忍者全部死亡才会走向基地」。
		#
		# 终止性靠的是另一条：敌人的伤害恒大于 0
		# （[method PBStatRules.strike_damage] 有一条「护甲不可能全免」的断言），
		# 忍者不回血，所以咬住的一方**必定**在有限时间内清完场，然后恢复推进。
		#
		# 「咬住了就不走」和出手冷却**不绑在一起**：绑了的话近战会在
		# 两次出手之间一步一步往前挪，而墙就会漏。
		enemy.engaged = true
		if not enemy.ready_to_fire(_tick):
			continue
		enemy.on_fired(_tick)
		# 远程的那一份走弹道（M4-c），减伤与克制在命中时才折算。
		if enemy.shot_speed > 0.0:
			var shot := _free_shot()
			if shot != null:
				shot.launch(
					enemy.pos(),
					_attackers.find(target),
					enemy.damage_per_shot,
					enemy.shot_speed,
					true,
					enemy.element,
					enemy.slot
				)
			continue
		var damage: float = PBStatRules.strike_damage(
			enemy.damage_per_shot, enemy.element, target.defence, target.def_element, _cfg
		)
		_note_hit(enemy.slot, target.slot, damage, true)
		if target.take_damage(damage):
			_outcome.allies_lost += 1
			_note_down(target.slot)


## 单体攻击：打射程内最接近基地的那个。**打不到人返回 false。**
##
## ## 两条路：一发子弹，还是一股连续伤害
##
## [member PBAttacker.attack_speed] 大于 0 时这是**一次离散出手**：
## 一发打一个，远程放子弹（飞几 tick 才结算），近战当场见血。
## **不结算溢出** —— 一发打死了目标，多出来的伤害没有地方去，
## 那是「命中才结算」的代价，见 [PBProjectile] 顶部。
##
## 攻速为 0 时走的是 M3-a 之前那条**连续输出**的退化路径
## （[method PBAttacker.whole_field]），它必须与 [PBCombatRules] 的解析式
## 排队模型逐字段一致，而那个模型的前提之一就是**溢出无损转移**。
## 所以溢出那一段留着，只在这一档下走。
func _strike_single(attacker: PBAttacker) -> bool:
	if attacker.attack_speed <= 0.0:
		return _pour_damage(attacker)
	var target := _first_reachable(attacker)
	if target == null:
		return false
	var damage: float = attacker.damage_per_shot() * _damage_scale()
	# 近战没有子弹（[member PBAttacker.shot_speed] 为 0），当场结算。
	if attacker.shot_speed <= 0.0:
		_note_hit(attacker.slot, target.slot, damage, false)
		if target.take_damage(damage):
			_outcome.kills += 1
		return true
	var shot := _free_shot()
	if shot == null:
		return false
	shot.launch(
		attacker.pos, target.slot, damage, attacker.shot_speed,
		false, PBElement.Type.PHYSICAL, attacker.slot
	)
	return true


## 射程内最接近基地的那个活敌人。没有就返回 null。
##
## **玩家点名的那个优先**（§02，M4-e）—— 但只在他还活着且够得着的时候。
## 够不着就照常自动选，不是站着不打：「我点了他，结果这个忍者整场发呆」
## 是玩家最不能接受的一种听话，理由见 [member PBAttacker.forced_target]。
func _first_reachable(attacker: PBAttacker) -> PBEnemy:
	var named := _named_target(attacker)
	if named != null and attacker.can_reach(named.pos()):
		return named
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			# 后面的出场更晚，这一 tick 不会再有可打的目标了。
			break
		if enemy.alive and attacker.can_reach(enemy.pos()):
			return enemy
	return null


## 连续输出那条退化路径：一股伤害顺着队列往下浇，打死了溢出接着打下一个。
##
## 溢出必须结算：高 DPS 一 tick 能打死好几个，漏掉溢出会让战斗时长
## 被系统性拉长 —— 而这条路径存在的全部理由就是与解析式排队模型对拍。
func _pour_damage(attacker: PBAttacker) -> bool:
	var remaining: float = attacker.damage_per_shot() * _damage_scale()
	var hit: bool = false
	var index: int = _front
	while remaining > 0.0 and index < _enemies.size():
		var enemy: PBEnemy = _enemies[index]
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive or not attacker.can_reach(enemy.pos()):
			index += 1
			continue
		hit = true
		var before: float = enemy.hp
		if enemy.take_damage(remaining):
			_outcome.kills += 1
			remaining -= before
			index += 1
		else:
			remaining = 0.0
	return hit


## 范围攻击：对射程内最靠近基地的若干个目标**各打一份完整伤害**。
## **一个都够不着时返回 false。**
##
## 不结算溢出，是与单体型的实质区别：AOE 的价值写在命中数上
## （§02 那条 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`），
## 再让它吃溢出的话，一个 AOE 攻击者在密集波里等于无限伤害。
##
## **范围型不发子弹**（M4-b）：一发子弹只追一个目标，而这里要同时打几个。
## 要给它一个飞行中的形态，得先回答「范围伤害在半空中是什么形状」——
## 那和大招的落点是同一个问题，而大招已经有一整套答案（[PBUltimate]）。
## 在角色表真的需要「会飞的范围普攻」之前，多一套实现只会多一处分叉。
func _strike_area(attacker: PBAttacker) -> bool:
	var damage: float = attacker.damage_per_shot() * _damage_scale()
	if damage <= 0.0:
		return false
	var hits: int = 0
	var index: int = _front
	while hits < attacker.max_targets and index < _enemies.size():
		var enemy: PBEnemy = _enemies[index]
		if not enemy.has_spawned(_tick):
			break
		index += 1
		if not enemy.alive or not attacker.can_reach(enemy.pos()):
			continue
		_note_hit(attacker.slot, enemy.slot, damage, false)
		if enemy.take_damage(damage):
			_outcome.kills += 1
		hits += 1
	return hits > 0


## 全体前进。**场上还有活忍者就扑向最近的那个，全死光了才走基地。**
##
## ## 为什么不是「一直往基地走，路过谁打谁」
##
## 那是 M4-c 到 M5-6 的做法，而它有一个玩家一眼就看出来的洞：
## **一条没人站的泳道等于一条高速公路。** 敌人沿直线推进，
## 于是忍者还站得好好的，基地已经在掉血了 —— 而 §02 那套
## 「忍者是一堵墙」的说法要求墙没破之前后面是安全的。
##
## 扑向最近的活人之后，「站位」第一次真的决定敌人往哪走：
## 玩家摆的阵型就是敌人的行军路线。代价是**单波会明显变长**
## （敌人要先绕过来），那对 §01 的 30–45 秒是好事，归数值回归确认。
##
## ## 两条路各自的漏怪语义
##
## 扑人那一支**结构上不可能漏怪**（目标站在场上，走到跟前就咬住了），
## 所以它走 [method PBEnemy.march_to]，那个函数没有返回值。
## 只有「场上一个活人都没有」那一支才可能抵达基地。
func _advance_and_leak() -> void:
	var speed_scale: float = _speed_scale()
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive:
			continue
		var prey := PBTargetRules.nearest_ally(_attackers, enemy)
		if prey != null:
			# **围到自己那一格上去**（M5-10）：所有人都直奔 `prey.pos` 的话，
			# 先到的把近侧堵死，后面的被防挤往身后垫成一条长队。
			#
			# 咬住了的照样走这一条 —— 那个点在忍者**身前**，走过去越不过他，
			# 所以「忍者是一堵墙」不需要额外的分支来守
			# （见 [method PBEnemy.siege_to]）。
			enemy.siege_to(
				PBCrowdRules.siege_spot(
					prey.pos, enemy.slot, enemy.reach, _cfg.field_height
				),
				speed_scale
			)
			continue
		# 场上一个活人都没有了才走基地。
		# 这里不用再判 `engaged` —— 没有可咬的人，它这一 tick 就不可能咬着
		# （[method _enemies_attack] 每 tick 从 false 重算）。
		if enemy.advance(speed_scale):
			enemy.alive = false
			_outcome.leaked += 1
			_outcome.base_damage += _leak_damage
			if log_to != null:
				log_to.base_hit(_tick, _leak_damage)
	_skip_dead()


## 把游标推到下一个还活着的敌人。已经死掉或漏掉的不再参与任何计算。
func _skip_dead() -> void:
	while _front < _enemies.size() and not _enemies[_front].alive:
		_front += 1
