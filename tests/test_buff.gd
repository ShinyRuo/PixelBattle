extends GutTest
## 效果层（§03A，M7-a）：[PBBuff] / [PBBuffState] / [PBBuffBag] / [PBBuffRules]。
##
## ## 这个文件钉的是**根因**，不是现象
##
## 这一层的每一种错都不报错，只表现为「这个 buff 好像没用」或者
## 「这个人打着打着好像变弱了」。所以断言直接压在那几条不变量上：
##
## - **持续效果永远不写回基础字段** —— 过期之后基数要**逐位**等于原值
## - **过期是查询时比 tick，不是扫描时删** —— 不跑清扫也必须过期
## - **空 bag 的合计是不折不扣的中性值** —— 率型正好 1.0，浮点乘它是精确的，
##   M3-a 那条解析式对拍因此一位都不会动
## - **同 id 整份覆盖** —— 那就是「刷新时长」，也是 M7-a 迁移能逐位相同的依据

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


## 造一份持续型效果。[param values] 是 1 级时的数值。
func _lasting(id: StringName, values: Dictionary, seconds: float = 5.0) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = seconds
	buff.mods = values
	return buff


func _attacker(dps: float = 100.0) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = dps
	out.max_hp = 500.0
	out.attack_speed = 1.0
	out.prime(_cfg.tick_rate)
	out.revive()
	return out


# ── 不写回基础字段 ──────────────────────────────────────────────


func test_an_expired_buff_leaves_the_base_number_bit_identical() -> void:
	# **本文件的正题。** 上 buff 时改基数、过期时除回来，看着更省，但浮点乘除
	# 不可逆 —— 几十次上下之后基数会漂，而它不报错，只表现为
	# 「这个人打着打着好像变弱了」。所以断言是**逐位相等**，不是近似相等。
	var attacker := _attacker()
	var base: float = attacker.damage_per_shot()
	attacker.buffs.add(_lasting(&"boost", {PBBuffRules.DAMAGE_SCALE: 1.3}), {
		PBBuffRules.DAMAGE_SCALE: 1.3
	}, 10, 40, 0)
	assert_almost_eq(attacker.strike_for(20), base * 1.3, base * 1e-9, "窗口内该多打三成")
	assert_eq(attacker.damage_per_shot(), base, "基数在窗口内也一个字没动")
	assert_eq(attacker.strike_for(51), base, "过期之后要逐位回到原值")


func test_an_empty_bag_is_exactly_neutral() -> void:
	# 率型的中性值必须是**正好 1.0**：M3-a 那条「整队折成一个标量攻击者」
	# 的解析式对拍要求逐字段一致，而浮点乘 1.0 是精确的、乘 0.999… 不是。
	var attacker := _attacker()
	assert_eq(attacker.strike_for(0), attacker.damage_per_shot(), "空 bag 不该改变任何数")
	assert_eq(attacker.buffs.amount(PBBuffRules.DAMAGE_SCALE, 0), 1.0, "率型空着是 1.0")
	assert_eq(attacker.buffs.amount(PBBuffRules.HEAL, 0), 0.0, "量型空着是 0.0")


# ── 过期 ────────────────────────────────────────────────────────


func test_expiry_is_a_query_not_a_sweep() -> void:
	# 清扫只回收槽位。**一次都不清扫，效果也必须到期** ——
	# 反过来（删除即真相）的话，清扫的时机、顺序、和暂停的关系
	# 全都变成正确性问题。
	var bag := PBBuffBag.new()
	bag.add(_lasting(&"boost", {PBBuffRules.DAMAGE_SCALE: 2.0}), {
		PBBuffRules.DAMAGE_SCALE: 2.0
	}, 0, 5, 0)
	assert_eq(bag.amount(PBBuffRules.DAMAGE_SCALE, 5), 2.0, "第 5 tick 还在（含）")
	assert_eq(bag.amount(PBBuffRules.DAMAGE_SCALE, 6), 1.0, "第 6 tick 该没了，而且没清扫过")
	assert_eq(bag.count(6), 0, "数一数也是 0")


func test_sweeping_never_changes_an_answer() -> void:
	var bag := PBBuffBag.new()
	var buff := _lasting(&"boost", {PBBuffRules.DAMAGE_SCALE: 2.0})
	bag.add(buff, {PBBuffRules.DAMAGE_SCALE: 2.0}, 0, 5, 0)
	var before: float = bag.amount(PBBuffRules.DAMAGE_SCALE, 6)
	bag.sweep(6)
	assert_eq(bag.amount(PBBuffRules.DAMAGE_SCALE, 6), before, "清扫前后答案要一样")


# ── 叠加与容量 ──────────────────────────────────────────────────


func test_the_same_buff_twice_refreshes_instead_of_stacking() -> void:
	# 决策 5：刷新时长。**整份覆盖**，不是「到期取较长者」——
	# 后者会让「先挂长弱档、再挂短强档」得到「强档持续很久」，比两者都好，
	# 而没有人要过那个东西。
	var bag := PBBuffBag.new()
	var buff := _lasting(&"boost", {PBBuffRules.DAMAGE_SCALE: 2.0})
	bag.add(buff, {PBBuffRules.DAMAGE_SCALE: 2.0}, 0, 20, 0)
	bag.add(buff, {PBBuffRules.DAMAGE_SCALE: 3.0}, 10, 5, 0)
	assert_eq(bag.count(10), 1, "同一个 id 只占一个槽位")
	assert_eq(bag.amount(PBBuffRules.DAMAGE_SCALE, 12), 3.0, "数值用新的，不是相乘")
	assert_eq(bag.amount(PBBuffRules.DAMAGE_SCALE, 16), 1.0, "到期也用新的那一份，不取较长")


func test_scales_multiply_and_amounts_add() -> void:
	var bag := PBBuffBag.new()
	bag.add(_lasting(&"a", {}), {PBBuffRules.DAMAGE_SCALE: 2.0}, 0, 20, 0)
	bag.add(_lasting(&"b", {}), {PBBuffRules.DAMAGE_SCALE: 3.0}, 0, 20, 0)
	assert_eq(bag.amount(PBBuffRules.DAMAGE_SCALE, 1), 6.0, "两份率型该连乘")
	bag.add(_lasting(&"c", {}), {PBBuffRules.HEAL: 10.0}, 0, 20, 0)
	bag.add(_lasting(&"d", {}), {PBBuffRules.HEAL: 7.0}, 0, 20, 0)
	assert_eq(bag.amount(PBBuffRules.HEAL, 1), 17.0, "两份量型该累加")


func test_a_full_bag_drops_the_shortest_not_the_newest() -> void:
	# 丢掉新来的那个，表现是「我刚放的技能没生效」，而它不报错。
	var bag := PBBuffBag.new()
	for i: int in PBBuffBag.SLOTS:
		# 越靠后的剩得越久，所以第 0 个是最短的那一个。
		bag.add(_lasting(&"f%d" % i, {}), {PBBuffRules.HEAL: 1.0}, 0, 10 + i, 0)
	assert_eq(bag.count(0), PBBuffBag.SLOTS, "先摆满")
	bag.add(_lasting(&"late", {}), {PBBuffRules.HEAL: 100.0}, 0, 50, 0)
	assert_eq(bag.count(0), PBBuffBag.SLOTS, "还是满的，没长出第七个槽")
	assert_eq(bag.amount(PBBuffRules.HEAL, 0), 105.0, "顶掉的是最短的那一份（1），新的进来了")


# ── 周期型 ──────────────────────────────────────────────────────


func test_a_periodic_buff_fires_once_per_period_starting_one_period_in() -> void:
	# 第一次在**一个周期之后**，不是挂上的当场 —— 当场那一下属于技能自己的
	# 瞬间载荷。合在一起的话「持续 5 秒每秒回 20」会回 6 次而不是 5 次。
	var state := PBBuffState.new()
	var buff := _lasting(&"regen", {PBBuffRules.HEAL: 10.0})
	buff.kind = PBBuff.Kind.PERIODIC
	state.take(buff, {PBBuffRules.HEAL: 10.0}, 0, 100, 20, -1)
	assert_false(state.is_due(0), "挂上的当场不触发")
	assert_false(state.is_due(19), "还差一 tick")
	assert_true(state.is_due(20), "整一个周期之后触发")
	state.on_fired(20)
	assert_false(state.is_due(21), "触发过就排到下一次")
	assert_true(state.is_due(40), "下一次还是隔一个周期")


func test_a_periodic_heal_actually_reaches_the_unit() -> void:
	var attacker := _attacker()
	attacker.hp = 100.0
	var buff := _lasting(&"regen", {PBBuffRules.HEAL: 25.0})
	buff.kind = PBBuff.Kind.PERIODIC
	var wave := PBWaveRules.build(4, _cfg, RandomNumberGenerator.new())
	var squad: Array[PBAttacker] = [attacker]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	# 开波会 revive（满血、清 bag），所以掉血和挂 buff 都放在那之后。
	attacker.hp = 100.0
	attacker.buffs.add(buff, {PBBuffRules.HEAL: 25.0}, 0, 200, 10)
	for _i: int in 10:
		sim.step()
	assert_almost_eq(attacker.hp, 125.0, 0.001, "十个 tick 之后该回了一跳")


func test_healing_never_goes_over_the_cap_or_raises_the_dead() -> void:
	var attacker := _attacker()
	attacker.hp = attacker.max_hp - 5.0
	attacker.heal(999.0)
	assert_eq(attacker.hp, attacker.max_hp, "回血封顶")
	attacker.alive = false
	attacker.hp = 0.0
	attacker.heal(999.0)
	assert_eq(attacker.hp, 0.0, "死人回不了 —— 复活是另一件事")


# ── 一波一份 ────────────────────────────────────────────────────


func test_a_wave_never_inherits_the_last_wave_buffs() -> void:
	# 攻击者对象会跨波、跨探测复用。不清的话上一场剩下的增伤会漏进这一场，
	# 而那和 PBSkillCast.reset 顶上记着的「冷却漏进下一场」是同一个形状。
	var attacker := _attacker()
	attacker.buffs.add(_lasting(&"boost", {}), {PBBuffRules.DAMAGE_SCALE: 9.0}, 0, 9999, 0)
	assert_eq(attacker.buffs.count(1), 1, "先挂上")
	attacker.revive()
	assert_eq(attacker.buffs.count(1), 0, "开波要清干净")


func test_a_clone_starts_with_an_empty_bag() -> void:
	# 复制品是「一个刚站起来的他」，不是「他现在这个样子」—— 和 hp 取 max_hp 同一条。
	var attacker := _attacker()
	attacker.buffs.add(_lasting(&"boost", {}), {PBBuffRules.DAMAGE_SCALE: 9.0}, 0, 9999, 0)
	var copy := attacker.clone()
	assert_eq(copy.buffs.count(1), 0, "复制品身上不该带着别人的 buff")
	assert_eq(attacker.buffs.count(1), 1, "而且原件不受影响")


# ── 全队增伤搬进 bag 之后仍然是全队的 ───────────────────────────


func test_the_team_damage_buff_lands_on_everyone() -> void:
	# M3-d 那个「全场一份」的增伤现在是「给每个人都挂一份」。
	# 它是这一层的第一个客户，而 test_beast / test_bond_function 里
	# 那两条既有断言量的就是它 —— 那两条必须原样还绿。
	var wave := PBWaveRules.build(4, _cfg, RandomNumberGenerator.new())
	var one := _attacker()
	var two := _attacker()
	var skill := PBSkill.new()
	skill.damage = 1.0
	skill.radius = 0.5
	skill.team_damage_scale = 2.0
	skill.buff_ticks = 40
	one.ultimate = PBSkillCast.new(skill)
	var squad: Array[PBAttacker] = [one, two]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.cast_skill(one, Vector2(0.5, 0.1))
	for _i: int in 20:
		sim.step()
	var at: int = sim.current_tick()
	assert_eq(one.buffs.amount(PBBuffRules.DAMAGE_SCALE, at), 2.0, "放的人自己也吃")
	assert_eq(two.buffs.amount(PBBuffRules.DAMAGE_SCALE, at), 2.0, "队友一样吃")
