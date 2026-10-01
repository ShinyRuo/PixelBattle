extends GutTest
## 蓝量：大招的第二道门槛。§03A，M3.5-d。
##
## ## 这个文件守的是什么
##
## 加一条资源限制最容易出的是**两种相反的静默失败**：
##
## 1. **门槛没生效** —— 蓝条画着，但谁都放得出，智力等于装饰。
##    这正是 §03A 否掉「展示层派生」那条路的理由（玩家迟早发现加了没用）
## 2. **门槛卡死了** —— 蓝根本回不上来，大招整局放不出一发，
##    而表现只是「这局伤害有点低」，从现象反推不出来
##
## 所以这里两头都钉：蓝不够真的放不出，蓝回得来也真的放得出。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260829


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 一个只有大招、不打普攻的施法者。[param mp] 为 0 表示没有蓝条。
func _caster(mp: float, cost: float, cooldown: int = 1) -> PBAttacker:
	var out := PBAttacker.new()
	out.pos = Vector2.ZERO
	# **对角，不是长度**：二维之后「够得着全场」的半径是对角线，
	# 用长度的话角落里的敌人不算数，而本文件量的是「放得出几发」，
	# 一发打不到人会被记成没放（见 [method PBSimConfig.field_diagonal]）。
	out.reach = _cfg.field_diagonal()
	out.max_mp = mp
	out.mp = mp
	out.mp_regen = mp * _cfg.mp_regen_rate / float(_cfg.tick_rate)
	var skill := PBSkill.new()
	skill.damage = 1.0
	skill.radius = _cfg.field_diagonal()
	skill.cooldown_ticks = cooldown
	skill.mp_cost = cost
	out.ultimate = PBSkillCast.new(skill)
	return out


## 跑 [param ticks] 个 tick，返回一共放了几发（按冷却重置的次数数）。
func _casts(caster: PBAttacker, ticks: int) -> int:
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	var fired: int = 0
	var was_pending: bool = false
	for _i: int in ticks:
		sim.step()
		var pending: bool = caster.ultimate.is_pending()
		if pending and not was_pending:
			fired += 1
		was_pending = pending
	return fired


func test_no_mana_means_no_ultimate() -> void:
	# 门槛真的挡得住。挡不住的话智力就只是信息栏里的装饰，
	# 而 §03A 否掉「展示层派生」那条路的理由正是这个。
	var broke := _caster(10.0, 60.0)
	assert_eq(_casts(broke, 40), 0, "蓝不够就一发都放不出")


func test_mana_regenerates_so_the_gate_is_not_a_dead_end() -> void:
	# 反过来的失败：蓝回不上来，大招整局放不出一发，
	# 而表现只是「这局伤害有点低」，从现象反推不出来。
	var caster := _caster(120.0, 60.0)
	assert_gt(_casts(caster, 400), 1, "蓝回得上来就该放得出好几发")


func test_a_bigger_pool_casts_more_often() -> void:
	# 回速按池子的比例算，所以**智力同时抬池子和回速**。
	# 只抬池子的话，高智力只意味着「能存更多发」，攒满的速度一样 ——
	# 那个属性平时就等于没有。
	var small := _casts(_caster(120.0, 60.0), 600)
	var large := _casts(_caster(360.0, 60.0), 600)
	assert_gt(large, small, "蓝池大的该放得更勤")


func test_a_unit_without_a_mana_bar_ignores_the_gate_entirely() -> void:
	# 尾兽的大招攻击者和退化标量都没有蓝条。**尾兽的稀缺性靠 75 秒的
	# 跨波冷却（§11）**，再加一道蓝门槛等于把同一件事收两次费。
	var beastlike := _caster(0.0, 60.0)
	assert_true(beastlike.can_pay(60.0), "没有蓝条的单位永远付得起")
	assert_gt(_casts(beastlike, 60), 0, "它该照常放得出")


func test_mana_is_spent_when_the_order_goes_out_not_when_it_lands() -> void:
	# 落地时扣的话，施法延迟那段窗口里还能再下达一发（蓝还没扣掉），
	# 于是延迟越长反而放得越多 —— 和「冷却从落地算起」是同一个道理。
	var caster := _caster(120.0, 60.0)
	caster.ultimate.skill.delay_ticks = 40
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	while not caster.ultimate.is_pending() and sim.current_tick() < 200:
		sim.step()
	assert_true(caster.ultimate.is_pending(), "该已经下达了")
	assert_lt(caster.mp, 120.0, "下达那一刻蓝就该扣掉，而不是等落地")


func test_everyone_comes_back_at_full_mana_next_wave() -> void:
	# §03A：开波满血**满蓝**。和血一样必须显式重置 ——
	# 探测会 clone 出几十份反复跑，不重置的话上一场的空蓝会漏进下一场。
	var caster := _caster(120.0, 60.0)
	_casts(caster, 60)
	assert_lt(caster.mp, caster.max_mp, "打完这一波该掉蓝")
	var squad: Array[PBAttacker] = [caster]
	PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	assert_eq(caster.mp, caster.max_mp, "下一波开波该满蓝")


func test_the_real_squad_gets_a_mana_bar_from_its_intellect() -> void:
	# 接线测试：`build_attackers` 要把属性表里的蓝真的装到攻击者身上。
	# 漏了的话大招变成无限放，而所有既有断言照样绿。
	var cfg := PBGameData.config()
	var state := PBRunSim.new_state(cfg)
	for character: PBCharacter in cfg.characters.all():
		state.add_unit(PBUnit.new(character))
	var deployed := PBValuation.deployed_by_raw_power(state, cfg)
	var squad := PBCombatRules.build_attackers(
		deployed, PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), cfg
	)
	assert_gt(squad.size(), 0, "该有人上场")
	for i: int in deployed.size():
		assert_gt(squad[i].max_mp, 0.0, "每个真单位都该有蓝条")
		assert_gt(squad[i].mp_regen, 0.0, "而且回得上来")
		assert_gt(squad[i].ultimate.skill.mp_cost, 0.0, "大招该要钱")
