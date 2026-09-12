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
## 每个攻击者可以带一个 [PBSkillCast]（挂着一份 [PBSkill] 定义）：
## 长冷却、一次性、**有落点**，而且落点在下达时定死、若干 tick 之后才落地。
## 那个延迟是 §02「PC 可预判走位」成立的前提，理由见 [PBSkill] 顶部。
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

## 场上的减速（M3-d，§11 的一尾 / 五尾）。
##
## **它是「场」的属性，不是单位的属性。** 存到每个敌人身上的话，
## 减速期间**新出场**的敌人会漏掉它，而那只表现为
## 「后半波怪走得比前半波快」，不报任何错。
##
## **后来者覆盖前者**，不叠加也不取最强。当前一局只有一只尾兽、冷却 75 秒，
## 两次同类效果不可能重叠；等真会重叠时，「怎么叠」是一个要有依据的
## 设计决定，不该现在拍一个。
##
## ## 全队增伤 M7-a 搬走了，减速没有
##
## 增伤原来是这旁边的一对 `_buff_scale` / `_buff_until`，现在是
## 挂在每个 [member PBAttacker.buffs] 上的一份 [PBBuff] ——
## 「全队增伤」于是变成「给每个人都挂一份」的那种特例，而不是另一套机制。
##
## 减速留在这里，因为上面那条理由今天仍然成立：**它要作用于还没出场的敌人。**
## M7-d 给敌人挂了个体减速（[constant PBBuffRules.ENEMY_SPEED_SCALE]），
## **两者相乘**，而不是把这一份也搬过去 —— 见 [method PBEnemy._speed_mult]。
var _slow_scale: float = 1.0
var _slow_until: int = -1

## 玩家下了但还没放出去的施法指令（M7-h）。**每 tick 推进之前一次放完**，
## 理由见 [PBSkillOrders] 顶部（暂停时状态一个字都不变，而且能反悔）。
var _orders: PBSkillOrders = PBSkillOrders.new()

## 队伍最前面那个还活着的敌人在 [member _enemies] 里的下标。
##
## 全体敌人同速前进、且按出场顺序排列，所以**数组顺序天然就是距离顺序** ——
## 不需要每 tick 排序找目标，从这个游标往后扫就行。
var _front: int = 0

## 暴击掷骰用的流（M10-c）。**null = 不掷**，绝大多数构造点都是。
## 它不是 [member PBRngStreams.combat] 而是 [method PBRngStreams.battle_rng]
## 派生的**本波专属**流 —— 理由写在那个方法顶上。
var _crit_rng: RandomNumberGenerator = null


## [param attackers] 为空时走退化路径：整队折成一个覆盖全场的单体攻击者，
## 此时 [param dps] 就是整队 DPS，行为与 M0 完全相同。
## 给了攻击者列表时 [param dps] 不参与战斗结算 —— 它只是个报数用的汇总量，
## 而汇总量按定义等于各攻击者之和（见 [method PBCombatRules.build_attackers]）。
## [param crit_rng] 见 [member _crit_rng]，不给就是从不暴击。
func _init(
	wave: PBWave,
	dps: float,
	def_reduction: float,
	cfg: PBSimConfig,
	attackers: Array[PBAttacker] = [],
	crit_rng: RandomNumberGenerator = null
) -> void:
	_crit_rng = crit_rng
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
		attacker.prime(cfg.tick_rate, cfg)
		# 开波满血（§03A）。和大招的冷却一样，攻击者对象会跨波、跨探测复用，
		# 不重置的话上一场的残血会漏进这一场，表现为「同一支队伍越探越弱」。
		attacker.revive()
		# 技能对象跨波、跨探测复用，不清的话上一场剩下的冷却会漏进这一场。
		# **每一格都要清**（M7-e）——漏掉一格的表现是「某个技能开波就是灰的」。
		for i: int in PBSkillRules.cast_count(attacker):
			var cast := PBSkillRules.cast_at(attacker, i)
			if cast != null:
				cast.reset()
	_orders.reset(_attackers.size())

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
	# **玩家攒着的指令排在推进之前**（M7-h）：这样「排队再放」和「当场放」
	# 算出来的 `lands_at` 与冷却逐位相同，暂停下攒的一批因此在
	# 取消暂停后的第一个 tick 一起放出。见 [PBSkillOrders]。
	_orders.flush(_attackers, _cfg, _tick, log_to)
	_tick += 1
	_resolve_ultimates()
	# **排在大招落地之后**：这一 tick 挂上的 buff 对这一 tick 的出手就生效，
	# 和 M7-a 之前那对 `_buff_scale` / `_buff_until` 逐字一致。
	_advance_buffs()
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


## 一次性把整波敌人建好。**规则在 [PBSpawnRules]**（M9-a 拆出去的）——
## 这里只负责把结果记进 [member _enemies]。
func _spawn_all(wave: PBWave, cfg: PBSimConfig) -> void:
	PBSpawnRules.fill(_enemies, wave, cfg, _enemy_speed, _shot_speed)


## 大招：先结算落地的，再下达新的。**顺序不能反。**
##
## 反过来的话，同一 tick 下达的大招会在下达的那一瞬间就落地，
## 施法延迟等于 0 —— 而那个延迟正是 §02 分层验收的全部依据
## （见 [PBSkill] 顶部）。
func _resolve_ultimates() -> void:
	for attacker: PBAttacker in _attackers:
		# **每一格都要过一遍**（M7-e）：玩家手放的技能也在飞，
		# 只扫大招那一格的话它永远落不了地，而按钮那边看起来一切正常。
		for i: int in PBSkillRules.cast_count(attacker):
			var cast := PBSkillRules.cast_at(attacker, i)
			# 已经下达的照样落地，哪怕施法者中途死了 —— 技能已经出手了。
			# 那是 §02 施法延迟的直接后果，也是「预判」这件事的对称代价。
			if cast != null and cast.is_pending() and _tick >= cast.lands_at:
				_land_skill(attacker, cast)
	for attacker: PBAttacker in _attackers:
		attacker.regen_mana()
	for attacker: PBAttacker in _attackers:
		var cast: PBSkillCast = attacker.ultimate
		if cast == null or not attacker.alive or not cast.is_ready(_tick):
			continue
		# **自动档只会放地面技能**（M7-c）：[PBAimRules] 答的是
		# 「往哪块地放」，它不知道该治谁、该点谁。锁定目标的那几档因此
		# 只有手动入口 —— 而 §6 那条「批量扫描不吃技能」本来就是这个意思。
		if cast.skill.target != PBSkill.Target.GROUND:
			continue
		# 第二道门槛（M3.5-d）：冷却转好了还得有蓝。
		# 这道门槛让六尾的「重置全体 CD」不再是免费的连放。
		if not attacker.can_pay(cast.skill.mp_cost):
			continue
		var spot := PBAimRules.pick_spot(
			_aim_policy,
			_enemies,
			_tick,
			cast.skill,
			_tick - cast.ready_at,
			_cfg.ultimate_min_targets,
			_cfg.ultimate_hold_targets,
			_max_hold_ticks
		)
		if PBSkillCast.is_spot(spot):
			_order(attacker, spot)
	_skip_dead()


## 玩家亲手下达一发地面技能（§02，M5-9）。**收下了返回 true，下一个 tick 才放出去**
## （M7-h，见 [PBSkillOrders]）。
##
## ## 为什么手动要有一条自己的入口
##
## [method _resolve_ultimates] 那一支是 [PBAimRules] 替玩家挑落点的，
## 也就是 §02 的**自动档**（手机端）。玩家自己点落点时那一整套「值不值得放、
## 要不要再攒一会儿」的判断都不该发生 —— 他点了就是要放。
##
## 门槛仍然是同一组（活着 / 冷却好了 / 蓝够），**而且必须共用一份**：
## 各写一份的话「按钮亮着但点了没反应」迟早出现，而它不报错。
func cast_skill(attacker: PBAttacker, spot: Vector2, index: int = 0) -> bool:
	return _orders.place(_attackers, _attackers.find(attacker), index, spot, -1, _tick)


## 玩家亲手把一发技能放在**一个队友**身上（[constant PBSkill.Target.ALLY]，M7-c）。
##
## 目标要活着 —— 死人身上放不了。**而下达之后他再死掉是另一回事**：
## 那一发照样飞完，落地时空放（见 [method PBSkillRules.land_on_ally]）。
func cast_skill_on(attacker: PBAttacker, target: PBAttacker, index: int = 0) -> bool:
	var slot: int = -1 if target == null else target.slot
	return _orders.place(
		_attackers, _attackers.find(attacker), index, PBSkillCast.NO_SPOT, slot, _tick
	)


## 玩家亲手把一发技能放在**一个敌人**身上（[constant PBSkill.Target.ENEMY]，M8-b）。
##
## 这一档 M7-c 就有合法形状，但一直没有入口 —— 火球术那一类
## （[member PBSkill.shot_cross_seconds] 不为 0）落地时才需要它。
func cast_skill_at(attacker: PBAttacker, enemy: PBEnemy, index: int = 0) -> bool:
	var slot: int = -1 if enemy == null else enemy.slot
	return _orders.place(
		_attackers, _attackers.find(attacker), index, PBSkillCast.NO_SPOT, slot, _tick
	)


## 玩家亲手放一发**不需要挑目标**的技能（[constant PBSkill.Target.NONE]，M7-c）。
func cast_skill_now(attacker: PBAttacker, index: int = 0) -> bool:
	return _orders.place(
		_attackers, _attackers.find(attacker), index, PBSkillCast.NO_SPOT, -1, _tick
	)


## 收回这个人手上那条还没放出去的指令（M7-h）。
func cancel_order(attacker: PBAttacker) -> void:
	_orders.cancel(_attackers.find(attacker))


## 这个人手上攒着的是第几格技能（-1 = 没有）。指令卡拿它显示「已下令」。
func order_of(attacker: PBAttacker) -> int:
	return _orders.index_of(_attackers.find(attacker))


## 攒着的全部指令，下标和 [method attackers] 一一对应。**渲染层只读，不要改。**
func orders() -> PBSkillOrders:
	return _orders


## 这个人现在放不放得出第 [param index] 个技能（0 = 大招）。
## **指令卡那一格的亮/灰读的就是它。** 规则在 [method PBSkillRules.can_cast]。
##
## **它不看「手上攒着一条没放出去的指令」** —— 那是操作层的事
## （指令卡把那一格写成「已下令」，见 [method PBSkillBar.show_on]）。
## 混进来的话，一个攒着指令的人会被判成「放不出」，而放出去那一遍
## 恰恰要再问一次这个函数。
func can_cast(attacker: PBAttacker, index: int = 0) -> bool:
	return PBSkillRules.can_cast(attacker, index, _tick)


## 自动档下达一发地面技能。**不进指令队列** —— 队列是「玩家下的令」，
## 而这一支是 [PBAimRules] 替玩家挑的落点，本来就发生在 tick 里面。
## 下达之后那三件事两条路共用（[method PBSkillOrders.issue]）。
func _order(attacker: PBAttacker, spot: Vector2) -> void:
	var cast: PBSkillCast = attacker.ultimate
	cast.cast(spot, _tick)
	PBSkillOrders.issue(attacker, cast, _cfg, _tick, log_to)


## 一发技能落地：圈人、挂效果、位置操纵全部交给 [PBSkillRules]。
## 本类只留三件跟「场」有关的事 —— 减速是场的属性
## （见 [member _slow_scale] 顶上的注释）、记账、转入冷却。
##
## **落地的形状由 [member PBSkill.target] 决定**（M7-c）：
## 地面档按半径圈人，锁定档只找那一个，不挑目标的那一档打全场。
## 全场效果（减速 / 全队增伤 / 重置冷却）**三档共用**，
## 它们本来就和「打中了谁」无关。
func _land_skill(attacker: PBAttacker, cast: PBSkillCast) -> void:
	var skill := cast.skill
	# **子弹技能：这一刻只是出膛**（M8-b）。伤害与 `on_hit` 等它飞到目标身上
	# 才结算，见 [member PBSkill.shot_cross_seconds]。冷却从出膛算起 ——
	# `is_pending` 那个状态的全部意义是「落点已定、还没结算」，也就是地面档的
	# 预判窗口；子弹追着目标走，没有预判可言。
	if skill.shot_cross_seconds > 0.0:
		_launch_skill(attacker, cast)
		cast.land(_tick)
		return
	match skill.target:
		PBSkill.Target.ALLY:
			PBSkillRules.land_on_ally(cast, _attackers, _cfg, _tick)
		PBSkill.Target.NONE:
			if skill.affects == PBSkill.Party.ENEMIES:
				_outcome.kills += PBSkillRules.land_on_field(
					cast, _enemies, _front, _cfg, _tick
				)
		PBSkill.Target.ENEMY:
			_outcome.kills += PBSkillRules.land_on_enemy(cast, _enemies, _cfg, _tick)
		_:
			_outcome.kills += PBSkillRules.land(cast, _enemies, _front, _cfg, _tick)
	if skill.slow_ticks > 0 and skill.slow_scale < 1.0:
		_slow_scale = skill.slow_scale
		_slow_until = _tick + skill.slow_ticks
	PBSkillRules.apply_team_buff(skill, _attackers, _tick)
	PBSkillRules.reset_other_cooldowns(skill, cast, _attackers, _tick)
	cast.land(_tick)


## 一发子弹技能出膛（M8-b）。池子满了或者目标已经不在名单里就当空放 ——
## 不报错，也不退回「瞬间结算」：那会让同一个技能在池子满的时候
## 变成另一种技能，而它不报错。
##
## 目标在飞行途中死掉是另一回事：那一发照样飞完，到了发现人没了就消失
## （[method PBShotRules._hit_enemy]），同 [PBProjectile] 顶上那条。
func _launch_skill(attacker: PBAttacker, cast: PBSkillCast) -> void:
	var shot := PBShotRules.free_shot(_shots)
	if shot == null:
		return
	var skill := cast.skill
	var at_ally: bool = skill.target == PBSkill.Target.ALLY
	var limit: int = _attackers.size() if at_ally else _enemies.size()
	if cast.target_slot < 0 or cast.target_slot >= limit:
		return
	# 速度由「飞完全场要几秒」反推，和普攻子弹同一条换算
	# （[member PBSimConfig.projectile_cross_seconds]）—— 两处各拍一个速度单位
	# 的话，「技能子弹比普攻快多少」会变成一个没人说得清的数。
	var per_tick: float = _cfg.field_length / maxf(
		skill.shot_cross_seconds * float(_cfg.tick_rate), 1.0
	)
	shot.launch(
		attacker.pos,
		cast.target_slot,
		skill.damage,
		per_tick,
		at_ally,
		skill.element,
		attacker.slot,
		skill,
		cast.caster_level
	)


## 这一 tick 敌人走多快。1.0 是正常速度，减速生效期间小于 1。
func _speed_scale() -> float:
	return _slow_scale if _tick <= _slow_until else 1.0


## 推进两边身上挂着的效果一个 tick（M7-a，敌方那半边是 M7-d）：
## 周期型该触发的触发，过期的腾出来。
##
## **怎么推进在 [PBBuffRules]**，这里只留一件它管不了的事 ——
## **记账**。周期伤害打死一个敌人要计进 [member PBCombatOutcome.kills]，
## 而那本账在本类手上；让规则层当场扣血的话，杀敌数就有了第二个来源，
## 而漏记一处的表现是「波次结算的击杀数对不上」，不报错。
##
## 敌人那一趟从 [member _front] 起扫、碰到没出场的就停 —— 和
## [method PBStrikeRules.first_reachable] 同一条：数组按出场顺序排，后面的只会更晚。
func _advance_buffs() -> void:
	for attacker: PBAttacker in _attackers:
		PBBuffRules.advance_ally(attacker, _tick)
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive:
			continue
		var harm: float = PBBuffRules.advance_enemy(enemy, _tick)
		if harm > 0.0 and enemy.take_damage(harm, _tick):
			_outcome.kills += 1
	_skip_dead()


## 把这一 tick 的伤害打出去。规则整个在 [PBStrikeRules]（M10-d 拆出去的）——
## 这里只留「什么时候调它」和游标维护，同 [method _advance_shots]。
func _deal_damage() -> void:
	PBStrikeRules.deal(
		_attackers, _enemies, _shots, _front, _cfg, _tick, _crit_rng, log_to, _outcome
	)
	_skip_dead()


## 子弹飞一个 tick，够到目标就结算（M4-b；结算搬进 [PBShotRules] 是 M8-b）。
##
## 目标死了子弹就消失，**不改打别人** —— 理由写在 [PBProjectile] 顶部。
func _advance_shots() -> void:
	PBShotRules.advance(
		_shots, _enemies, _attackers, _cfg, _tick, log_to, _outcome, _crit_rng
	)
	_skip_dead()


## 记一次命中。**每个见血的地方都走这一句**，而不是各写一遍
## `if log_to != null` —— 漏一处的表现是「某一种攻击方式在日志里不存在」，
## 而那要盯着日志看很久才发现。
func _note_hit(source: int, target: int, amount: float, to_ally: bool, crit := false) -> void:
	if log_to != null:
		log_to.hit(_tick, source, target, amount, to_ally, crit)


## 记一个忍者倒下。**怪物死了不记**（玩家定的）：一波死几十只，
## 每只一行会把另外五种播报全部冲掉，见 [enum PBBattleLog.Kind]。
func _note_down(slot: int) -> void:
	if log_to != null:
		log_to.ally_down(_tick, slot)


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
## **怎么挪在 [PBMoveRules]**（M6-q 拆出去的），这里只管挑目标和分支。
##
## 三条互斥的状态，顺序就是优先级（M4-c）：够得着就站住、够不着按自己的
## 打法靠过去、场上一个活人都没有就慢慢走回自己的位置。
##
## 最后那条不能省：不退的话，一波打完全队会停在最前沿，
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
		var leash: float = PBMoveRules.leash_for(
			attacker, target, _named_target(attacker), _cfg
		)
		if attacker.shot_speed > 0.0:
			PBMoveRules.press_forward(attacker, target, leash)
		else:
			PBMoveRules.close_in(attacker, target, leash)


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
##
## ## 为什么「守得住的那个」优先（M6-q）
##
## 挑全场最近的那个，会挑中一个**站在皮带绳外面**的敌人 —— 而
## [method PBMoveRules.leash_for] 那时就会把绳子放长。M6-q 之前那一松是
## **整根松开**，判据量的又是永不移动的 `home`，于是这一波剩下的时间里
## 再也收不回来；那个敌人死了之后他就地再挑一个，同样在绳外，于是继续放开。
## 实测第 20 波那个近战 **210/271 tick 在绳外，离家 0.55 而绳长 0.35** ——
## 屏幕上就是「追着怪一路跑出去」。
##
## 放长现在压着一道天花板（M6-q），所以这条优先级的理由变得更直白：
## **自己那一格里还有活可干，就先干自己的**，别跑去帮别人 ——
## 而那也正是 §02 的射程梯度想要的站位。
##
## **这里的 `leash + reach` 必须和 [method PBMoveRules.leash_for] 第二道门槛
## 是同一个数**：那边用它判「够不着才放绳」，这边用它判「这算不算我的活」。
## 两处分叉的话，会出现「挑中了一个我认定守不住的目标，绳子却不肯为它放长」——
## 也就是 M8-c 那条 bug 的形状（贴在绳边，整波一发不放）。
##
## 所以先在**自己守得住的范围**（`home` 半径 `leash + reach`）里挑，
## 挑不到才退回全场最近的。退回那一档正是 M5-8 那个死局
## （谁都够不着 → 全队站着挨打），它必须留着。
##
## 反过来说：**只要自己那一格还有活可干，就不许跑去帮别人打** ——
## 而那也正是 §02 的射程梯度想要的站位。
func _nearest_enemy(attacker: PBAttacker) -> PBEnemy:
	# 玩家点名了就朝那个走（§02，M4-e）—— **哪怕现在够不着**，
	# 那正是「点他」的意思。皮带绳照旧拴着，所以他不会横穿半个战场。
	var named := _named_target(attacker)
	if named != null:
		return named
	var best: PBEnemy = null
	var best_gap: float = 0.0
	# **守得住的那个优先。** 见下面那段注释。
	var post: PBEnemy = null
	var post_gap: float = 0.0
	var post_reach: float = attacker.leash + attacker.reach
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
		if attacker.home.distance_to(enemy.pos()) <= post_reach:
			if post == null or gap < post_gap:
				post = enemy
				post_gap = gap
	return post if post != null else best


## 玩家点名的那个敌人，**这一 tick 还算不算数**（活着、已出场）。不算就 null。
##
## 三处读它：走位（[method _nearest_enemy]）、开火（[method PBStrikeRules.first_reachable]）、
## 画线（[method _aim_targets]）。抄成三份的话「点名什么时候失效」会有三个答案，
## 而分叉的表现是**线、脚、枪各指一个人**。
func _named_target(attacker: PBAttacker) -> PBEnemy:
	return PBStrikeRules.named_target(attacker, _enemies, _tick)


## 每人这一 tick 的攻击目标（M5-12），存进 [member PBAttacker.aim_at]。
##
## 三档取第一个有的：**有效点名 → 射程内最靠近基地的 → 全场最近的**。
## 后两档正是 [method PBStrikeRules.first_reachable] 与 [method _nearest_enemy] 的自动部分；
## 第一档**不问射程** —— 玩家点了一个还没走到的人，意思是「去打他」，
## 而 [method _move_attackers] 也确实会朝他走。
##
## **它不决定伤害打给谁**：开火仍走 [method PBStrikeRules.first_reachable]，
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
			mark = PBStrikeRules.first_reachable(attacker, _enemies, _front, _tick)
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
		# 抬手，同己方那一支 —— 这里目标已经找到了，不用再问一遍。
		if enemy.begin_swing(_tick):
			continue
		enemy.on_fired(_tick)
		# 致盲（M12-c2）：手抬了、冷却也走了，只是这一下打空。
		# **排在近战/远程分岔之前** —— 分岔之后各判一次的表现是
		# 「只有近战会打空」。和晕眩故意不同档：那一档连手都抬不起来。
		if PBBuffRules.misses(enemy, _tick, _crit_rng):
			continue
		# 远程的那一份走弹道（M4-c），减伤与克制在命中时才折算。
		if enemy.shot_speed > 0.0:
			var shot := PBShotRules.free_shot(_shots)
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
		# 折算、播报、扣血、阵亡、反弹全在那一处（M12-c2）——
		# 子弹那一路（[method PBShotRules._hit_ally]）回头调的是同一个。
		PBStrikeRules.hurt_ally(
			target,
			enemy,
			enemy.damage_per_shot,
			enemy.element,
			_cfg,
			_tick,
			_crit_rng,
			log_to,
			_outcome
		)


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
				speed_scale,
				_tick
			)
			continue
		# 场上一个活人都没有了才走基地。
		# 这里不用再判 `engaged` —— 没有可咬的人，它这一 tick 就不可能咬着
		# （[method _enemies_attack] 每 tick 从 false 重算）。
		if enemy.advance(speed_scale, _tick):
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
