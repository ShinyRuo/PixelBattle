extends GutTest
## 敌人那一侧的效果袋（§03A，M7-d）：易伤、个体减速、掉血。
##
## ## 这个文件钉的是三条「不报错」的性质
##
## - **上一波的减速不许漏进这一波** —— [PBEnemy] 是复用的，
##   [method PBEnemy.spawn] 不清袋子的话表现是「后半局的怪好像变慢了」
## - **全场减速和个体减速是两个东西，两者相乘** ——
##   全场那一份要作用于**还没出场**的敌人，搬不进袋子；
##   而「定住这一个」在全场那一份里没有地方表达
## - **读点在类里面，不在调用方** —— 易伤有六处调用方、走位有三处，
##   漏乘一处的表现是「某一种攻击方式吃不到易伤」，要盯着日志看很久才发现

const FIXED_SEED: int = 20260905

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


## 一个站在场上、血量写死的敌人。不走 [method PBEnemy.spawn] 的那几条
## 测试直接摆字段 —— 它们要的只是「有血、活着、走得动」。
func _enemy(hp: float = 100.0, speed: float = 0.01) -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = hp
	out.hp = hp
	out.speed = speed
	out.distance = 1.0
	return out


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 一个站在原地、够得着全场的射手。
func _shooter(dps: float = 1000.0) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = dps
	out.attack_speed = 4.0
	out.pos = Vector2.ZERO
	out.reach = _cfg.field_diagonal()
	out.max_hp = 1.0e9
	out.hp = out.max_hp
	return out


## 一份持续型效果（不带周期载荷）。
func _lasting(id: StringName, values: Dictionary, seconds: float = 5.0) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = seconds
	buff.mods = values
	return buff


## 一份周期型效果（中毒、灼烧那一类）。
func _periodic(id: StringName, per_tick: float, seconds: float, period: float) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.PERIODIC
	buff.duration_seconds = seconds
	buff.period_seconds = period
	buff.mods = {PBBuffRules.HARM: per_tick}
	return buff


## 把一份效果按它自己的时长挂到 [param enemy] 身上。
func _hang(enemy: PBEnemy, buff: PBBuff, at_tick: int) -> void:
	enemy.buffs.add(
		buff,
		PBBuffRules.resolve(buff, 1),
		at_tick,
		buff.duration_ticks(_cfg),
		buff.period_ticks(_cfg)
	)


# ── 上一波的减速不许漏进下一波 ──────────────────────────────────


func test_spawn_clears_the_bag() -> void:
	# **本文件的正题之一。** 敌人是复用的（[PBEnemy] 顶部），袋子不清的话
	# 上一波挂上的减速会跟着这个实例进下一波，而它不报任何错 ——
	# 表现只是「后半局的怪好像变慢了」，和「上一场剩下的冷却漏进下一场」
	# （[method PBSkillCast.reset] 顶上）是同一个形状。
	var enemy := _enemy()
	_hang(enemy, _lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}), 0)
	assert_eq(enemy.buffs.count(1), 1, "先确认真的挂上了")

	enemy.spawn(_wave(3), 0.02, 1.0, 0, 0.0)
	assert_eq(enemy.buffs.count(1), 0, "出生那一刻身上不该带着上一波的东西")
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0, "合计要逐位回到中性值，不是「差不多是 1」")


# ── 全场 × 个体 ────────────────────────────────────────────────


func test_a_field_freeze_beats_any_personal_slow() -> void:
	# 相乘而不是取最小：全场定身（0.0）期间再上一个个体减速，速度仍是 0。
	var enemy := _enemy()
	_hang(enemy, _lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}), 0)
	var before: float = enemy.distance
	enemy.advance(0.0, 1)
	assert_eq(enemy.distance, before, "全场定身期间一步都不许走")


func test_the_field_slow_and_a_personal_slow_multiply() -> void:
	var plain := _enemy()
	var chilled := _enemy()
	_hang(chilled, _lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}), 0)

	plain.advance(0.5, 1)
	chilled.advance(0.5, 1)
	var field_only: float = 1.0 - plain.distance
	var both: float = 1.0 - chilled.distance
	assert_almost_eq(both, field_only * 0.5, 1e-12, "0.5 × 0.5 该是 0.25 倍速")


func test_a_personal_slow_also_slows_the_chase() -> void:
	# **读点在 [method PBEnemy.march_to] 里面，不在 [PBBattleSim] 的调用处。**
	# 只在 `advance` 那一支乘的话，扑向忍者的那一支（也就是绝大多数 tick）
	# 完全吃不到减速 —— 而屏幕上「怪好像没被减速」和「减速数值配小了」
	# 长得一模一样。
	var plain := _enemy()
	var chilled := _enemy()
	_hang(chilled, _lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}), 0)
	var goal := Vector2(0.0, 0.0)

	plain.march_to(goal, 1.0, 1)
	chilled.march_to(goal, 1.0, 1)
	assert_almost_eq(1.0 - chilled.distance, (1.0 - plain.distance) * 0.5, 1e-12, "扑人也要减速")

	# 围攻那一支借道 `march_to`，所以它自动跟着 —— 但要真的跟着。
	var sieged := _enemy()
	_hang(sieged, _lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.0}), 0)
	var held: float = sieged.distance
	sieged.siege_to(goal, 1.0, 1)
	assert_eq(sieged.distance, held, "定身的敌人围也围不过去")


func test_an_expired_personal_slow_leaves_the_step_bit_identical() -> void:
	# 持续效果永远不写回基础字段：过期之后这一步的长度要**逐位**等于原值。
	var enemy := _enemy()
	var plain := _enemy()
	_hang(enemy, _lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}, 1.0), 0)
	var gone: int = enemy.buffs.states()[0].until_tick + 1

	enemy.advance(1.0, gone)
	plain.advance(1.0, gone)
	assert_eq(enemy.distance, plain.distance, "过期之后要逐位和没挂过的一样")
	assert_eq(enemy.speed, plain.speed, "基础速度在窗口内也一个字没动")


# ── 易伤 ────────────────────────────────────────────────────────


func test_a_vulnerability_is_multiplied_inside_take_damage() -> void:
	var enemy := _enemy(100.0)
	_hang(enemy, _lasting(&"frail", {PBBuffRules.HURT: 2.0}), 0)
	enemy.take_damage(30.0, 1)
	assert_almost_eq(enemy.hp, 40.0, 1e-9, "易伤 2 倍，30 点该掉 60")


func test_a_vulnerability_reaches_a_real_battle() -> void:
	# 直接调 `take_damage` 测出来的只是「那一行乘对了」。这一条问的是
	# **战斗里真的走得到它** —— 出手有三条路（单体、连续输出、范围），
	# 加上子弹命中、技能落地、周期载荷共六处，而它们全都不该自己乘。
	# **两局共用同一份 [PBWave]。** 各造一份的话 `_rng` 已经被前一次
	# 推进过，两波的血量根本不是同一个数 —— 而那种对照组本身就是错的。
	var wave := _wave(6)
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [_shooter(20.0)])
	var plain := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [_shooter(20.0)])
	var victim: PBEnemy = sim.enemies()[0]
	_hang(victim, _lasting(&"frail", {PBBuffRules.HURT: 3.0}, 60.0), 0)

	for _i: int in 12:
		sim.step()
		plain.step()
	assert_true(victim.alive, "输出要小到两边都还活着，否则比的是「谁先死」")
	var hurt_taken: float = victim.max_hp - victim.hp
	var plain_taken: float = plain.enemies()[0].max_hp - plain.enemies()[0].hp
	assert_gt(plain_taken, 0.0, "对照组要真的挨到打，否则这条什么都没测")
	assert_almost_eq(hurt_taken, plain_taken * 3.0, plain_taken * 1e-6, "同样的输出该掉三倍血")


func test_the_overflow_path_pays_in_damage_not_in_hit_points() -> void:
	# 连续输出那条退化路径打死一个之后要把「花掉的那一份」减掉接着打下一个，
	# 而易伤让「掉了多少血」和「花了多少伤害」不再是同一个数。
	# 拿掉这条换算，退化路径就和 [PBCombatRules] 的解析式排队模型对不上了。
	var enemy := _enemy(100.0)
	_hang(enemy, _lasting(&"frail", {PBBuffRules.HURT: 2.0}), 0)
	assert_almost_eq(enemy.damage_to_kill(1), 50.0, 1e-9, "易伤 2 倍，50 点伤害就够")
	assert_true(enemy.take_damage(50.0, 1), "而 50 点真的该打死它")

	var plain := _enemy(100.0)
	assert_eq(plain.damage_to_kill(1), plain.hp, "没有易伤时逐位等于剩余血量")


# ── 掉血（中毒、灼烧） ─────────────────────────────────────────


func test_periodic_harm_fires_once_per_period() -> void:
	var enemy := _enemy(100.0)
	# 每 0.5 秒（10 tick）掉 7 点，持续 2 秒。第一次在**一个周期之后**。
	_hang(enemy, _periodic(&"burn", 7.0, 2.0, 0.5), 0)
	assert_eq(PBBuffRules.advance_enemy(enemy, 5), 0.0, "还没到第一个周期")
	assert_almost_eq(PBBuffRules.advance_enemy(enemy, 10), 7.0, 1e-9, "第一个周期到了")
	assert_eq(PBBuffRules.advance_enemy(enemy, 15), 0.0, "周期之间不掉血")
	assert_almost_eq(PBBuffRules.advance_enemy(enemy, 20), 7.0, 1e-9, "第二个周期")
	assert_eq(PBBuffRules.advance_enemy(enemy, 60), 0.0, "过期之后不再掉血")


func test_periodic_harm_that_kills_is_counted_in_the_wave_kills() -> void:
	# **杀敌数只有一个来源。** 规则层当场扣血的话这本账就有了第二处，
	# 而漏记一处的表现是「波次结算的击杀数对不上」，不报错。
	var squad: Array[PBAttacker] = [_shooter(0.0)]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var victim: PBEnemy = sim.enemies()[0]
	_hang(victim, _periodic(&"burn", victim.max_hp * 2.0, 3.0, 0.5), 0)
	var before: int = sim.result().kills

	for _i: int in 15:
		sim.step()
	assert_false(victim.alive, "两倍血量的一跳该把它烧死")
	assert_eq(sim.result().kills, before + 1, "而且要记进这一波的击杀数")


# ── on_hit 挂到敌人身上（M7-c 留下的那个缺口） ─────────────────


func test_a_ground_skill_hangs_on_hit_on_everyone_it_caught() -> void:
	var enemy := _enemy(1000.0)
	enemy.distance = 0.5
	enemy.lane = 0.0
	var enemies: Array[PBEnemy] = [enemy]
	var cast := PBSkillCast.new(
		_ground_skill(10.0, [_lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5})])
	)
	cast.cast(Vector2(0.5, 0.0), 0)

	PBSkillRules.land(cast, enemies, 0, _cfg, 1, null, cast.skill.damage)
	assert_eq(enemy.buffs.count(1), 1, "圈中的敌人该被挂上")
	assert_almost_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 0.5, 1e-9, "减速生效")


func test_on_hit_never_lands_on_an_enemy_the_blast_already_killed() -> void:
	# 给一具尸体挂减速没有意义，而且它会让「这一发定住了几个」虚高 ——
	# 那个数以后要上界面（M7-f 的图标条）。
	var enemy := _enemy(5.0)
	enemy.distance = 0.5
	var enemies: Array[PBEnemy] = [enemy]
	var cast := PBSkillCast.new(
		_ground_skill(999.0, [_lasting(&"chill", {PBBuffRules.ENEMY_SPEED_SCALE: 0.5})])
	)
	cast.cast(Vector2(0.5, 0.0), 0)

	assert_eq(PBSkillRules.land(cast, enemies, 0, _cfg, 1, null, cast.skill.damage), 1, "这一发该打死它")
	assert_eq(enemy.buffs.count(1), 0, "死人身上不该挂着东西")


func test_an_instant_harm_in_on_hit_can_kill_and_is_counted() -> void:
	var enemy := _enemy(100.0)
	enemy.distance = 0.5
	var enemies: Array[PBEnemy] = [enemy]
	var bolt := PBBuff.new()
	bolt.id = &"bolt"
	bolt.kind = PBBuff.Kind.INSTANT
	bolt.mods = {PBBuffRules.HARM: 200.0}
	var cast := PBSkillCast.new(_ground_skill(10.0, [bolt]))
	cast.cast(Vector2(0.5, 0.0), 0)

	assert_eq(
		PBSkillRules.land(cast, enemies, 0, _cfg, 1, null, cast.skill.damage), 1, "瞬间伤害补刀也算一个击杀"
	)
	assert_false(enemy.alive, "而且它真的死了")


# ── 空袋子什么都不改 ───────────────────────────────────────────


func test_an_empty_bag_changes_nothing_bit_for_bit() -> void:
	# 三个新键全部是率型 1.0 / 量型 0.0 的中性值，而浮点乘 1.0 是精确的 ——
	# 没有任何敌人挂着东西的那一局（也就是眼下全部既有配平数字的那一局）
	# 因此一位都不会动。
	var enemy := _enemy(100.0)
	enemy.take_damage(30.0, 7)
	assert_eq(enemy.hp, 70.0, "没有易伤时扣的就是给的那个数")
	enemy.advance(1.0, 7)
	assert_eq(enemy.distance, 1.0 - enemy.speed, "没有减速时走的就是自己的速度")
	assert_eq(enemy.buffs.amount(PBBuffRules.HURT, 7), 1.0, "易伤空着是 1.0")
	assert_eq(enemy.buffs.amount(PBBuffRules.HARM, 7), 0.0, "掉血空着是 0.0")


## 一发落在地上的技能，[param on_hit] 是它命中之后挂的东西。
func _ground_skill(damage: float, on_hit: Array[PBBuff]) -> PBSkill:
	var skill := PBSkill.new()
	skill.damage = damage
	skill.radius = 0.2
	skill.on_hit = on_hit
	return skill
