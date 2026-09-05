extends GutTest
## 敌人还手、忍者会死、咬住了就不走。§03A，M3.5-b。
##
## ## 这个文件守的是什么
##
## M3.5-b 把战斗从**单向结算**换成**双向战斗**。这种改造有一类特别难发现的
## 失败：**机制根本没触发，而所有既有断言照样绿**（它们量的是漏怪与击杀，
## 而那两个数在敌人还手之前之后都存在）。
##
## 所以这里逐条钉「这件事真的发生了」：
##
## 1. 敌人真的把人打死了
## 2. 死了的人真的不再输出
## 3. 咬住了的敌人真的停住了 —— **忍者是一堵墙，不是路边的减速带**
## 4. `max_hp == 0` 的攻击者真的挨不到打（M3-a 那条对拍锚点靠它活着）
## 5. 开波真的满血复活

## 敌人走完全场要 240 tick（`march_seconds` 12 秒 × 20 tick/s），
## 出怪窗口另有 200 tick。**测位置与交战的用例必须跑够这么久** ——
## 跑 120 tick 的话敌人还没走到前排跟前，测出来的「没挨打」是假的。
const CROSS_TICKS: int = 240
const FULL_TICKS: int = 500

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	# **压平战场**（M4-a 的降维锚点，见 `test_field_2d.gd`）。
	# 本文件测的是「敌人还不还手、谁先挨打、墙破没破」，纵向一条都不涉及；
	# 留着高度的话，摆在同一条泳道上的己方和散在各条泳道上的敌人
	# 会因为纵向差而互相够不着，量出来的是泳道，不是站位。
	_cfg.field_height = 0.0
	# **整波都是近战**（M4-c）。这个文件量的是那堵墙：近战撞上前排就停，
	# 所以「谁先挨打」「墙破了没有」才有意义。
	# 远程敌人**故意不受这堵墙约束** —— 他边走边射、绕不过去也不用绕，
	# 混进来的话这里的每一条都会量到「有几个射手走过去了」。
	# 射手那一侧的行为钉在 `test_unit_ai.gd` 里。
	_cfg.enemy_ranged_share = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260829


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 造一个站在 [param at_x]、有血有防的真单位。
##
## 泳道一律取 0：本文件测的是「敌人还不还手、谁先挨打、墙破没破」，
## 那几条和纵向无关。**摆在同一条泳道上是有意的** ——
## 散开的话「离我最近的那个」会掺进纵向差，量的就不是站位了。
func _unit(at_x: float, hp: float, dps: float = 0.0, reach: float = 0.2) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = dps
	out.pos = Vector2(at_x, 0.0)
	out.reach = reach
	out.max_hp = hp
	out.hp = hp
	out.def_element = PBElement.Type.PHYSICAL
	return out


func _sim(wave: PBWave, squad: Array[PBAttacker]) -> PBBattleSim:
	return PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)


func test_enemies_now_kill_the_ninjas() -> void:
	# 最基本的一条：敌人还手了。血量、防御、坦克定位全都建在这上面，
	# 而它不触发的话，上面那三样只是信息栏里的装饰。
	var squad: Array[PBAttacker] = [_unit(0.30, 1.0)]
	var sim := _sim(_wave(9), squad)
	sim.run_to_end()
	assert_false(squad[0].alive, "一滴血的忍者该被打死")
	assert_eq(sim.result().allies_lost, 1, "结算里该记下这一条命")


func test_a_dead_ninja_stops_dealing_damage() -> void:
	# 「前排先死导致输出下降」是这套模型第一次能表达的东西。
	# 死人照打的话，血量就只是一个不影响任何结果的计数器。
	# 输出压到清不完这一波 —— 清得完的话两边都是满额击杀，
	# 「死没死」在结果上看不出来，那样的绿是假的。
	var wave := _wave(15)
	var fragile: Array[PBAttacker] = [_unit(0.30, 1.0, 50.0, 1.0)]
	var sturdy: Array[PBAttacker] = [_unit(0.30, 1.0e9, 50.0, 1.0)]
	var dead := _sim(wave, fragile).run_to_end()
	var live := _sim(wave, sturdy).run_to_end()
	assert_lt(dead.kills, live.kills, "被打死之后不该还在输出")
	assert_eq(dead.allies_lost, 1, "这一条的前提是他真的死了")


func test_an_engaged_enemy_stops_advancing() -> void:
	# **忍者是一堵墙。** 边打边走的话，防御和血量只能影响「这个人还能输出几秒」，
	# 影响不了「敌人到没到基地」—— 坦克、前排、§02 的站位全部贬值。
	var wave := _wave(9)
	var wall: Array[PBAttacker] = [_unit(0.30, 1.0e9)]
	var none: Array[PBAttacker] = []

	var blocked := _sim(wave, wall)
	var free := _sim(wave, none)
	# 不用 `run_to_end`：这堵墙不输出，敌人咬住它谁也走不了，
	# 那是一场真正的僵局，跑到底只会撞上安全阀。
	for _i: int in FULL_TICKS:
		blocked.step()
		free.step()
	assert_eq(free.result().leaked, wave.count, "没人拦的话整波该走完")
	assert_eq(blocked.result().leaked, 0, "被墙挡住的一个都不该漏过去")


func test_the_wall_holds_only_while_it_is_alive() -> void:
	# 墙破了敌人就该继续走。`engaged` 是每 tick 重算的，不是持久状态 ——
	# 存成持久的话，目标死了敌人会永远钉在原地，整波再也不推进。
	var squad: Array[PBAttacker] = [_unit(0.30, 1.0)]
	var outcome := _sim(_wave(9), squad).run_to_end()
	assert_false(squad[0].alive, "这堵墙该倒")
	assert_gt(outcome.leaked, 0, "墙倒了敌人就该继续走到基地")


func test_a_scalar_attacker_cannot_be_hit_at_all() -> void:
	# **M3-a 那条对拍锚点靠这一条活着。**
	# `whole_field` 造的是 M3-a 之前那个整队标量 DPS 的等价物，
	# 而它要与解析式排队模型逐字段一致 —— 那个模型的前提之一就是敌人不还手。
	#
	# 用「血是不是 0」而不是加一个 `cfg.enemies_fight_back` 开关：
	# 开关会有人忘了设，而一个没血的东西挨不了打是它自身的性质。
	var scalar: Array[PBAttacker] = [PBAttacker.whole_field(50.0, _cfg.field_diagonal())]
	assert_false(scalar[0].is_targetable(), "标量不是单位，敌人看不见它")
	var outcome := _sim(_wave(9), scalar).run_to_end()
	assert_eq(outcome.allies_lost, 0, "标量不该被打死")
	assert_true(scalar[0].alive, "它也不该停止输出")


func test_the_nearest_defender_is_the_one_who_gets_hit() -> void:
	# 挑「离我最近的」而不是「血最少的」：敌人有集火 AI 的话，
	# 站哪都会被点名，玩家的站位就失去意义。挑最近的之后**站得靠前的先挨打**，
	# 而站位是射程的派生量（§02）—— 玩家因此可以通过选人来选谁扛。
	var front := _unit(0.30, 1.0e9)
	var back := _unit(0.10, 1.0e9)
	var squad: Array[PBAttacker] = [back, front]
	var sim := _sim(_wave(9), squad)
	for _i: int in CROSS_TICKS:
		sim.step()
	assert_lt(front.hp, front.max_hp, "站前面的该先挨打")
	assert_eq(back.hp, back.max_hp, "站后面的这时候还没挨着")


func test_everyone_comes_back_at_full_health_next_wave() -> void:
	# §03A：每波开波满血复活 —— 一波之内的失误有真实代价，但不会毁掉整局。
	# **必须显式重置**，不能靠「攻击者是每波新建的」：悬崖二分那类探测
	# 会 clone 出几十份反复跑，不重置的话上一场的残血会漏进下一场。
	var squad: Array[PBAttacker] = [_unit(0.30, 500.0)]
	_sim(_wave(9), squad).run_to_end()
	assert_lt(squad[0].hp, squad[0].max_hp, "打完这一波该掉血")

	_sim(_wave(9), squad)
	assert_eq(squad[0].hp, squad[0].max_hp, "下一波开波该满血")
	assert_true(squad[0].alive, "死了的也该站起来")


func test_a_cast_ultimate_still_lands_when_its_caster_dies() -> void:
	# 已经出手的大招照样落地。那是 §02 施法延迟的直接后果，
	# 也是「预判」这件事的对称代价 —— 落点先定死，之后发生什么都改不了。
	var caster := _unit(0.30, 1.0)
	var skill := PBSkill.new()
	skill.damage = 1.0e9
	# **半径要小**（M4-d）：整波一次全刷之后，一发罩住全场的大招会把
	# 整波清光，于是施法者根本不会死，这条就测不到「他死了大招照样落地」。
	# 在那之前出怪窗口 10 秒，落地那一刻场上只有前几个，剩下的照样走过来。
	skill.radius = 0.05
	skill.delay_ticks = 6
	skill.cooldown_ticks = 10000
	caster.ultimate = PBSkillCast.new(skill)
	var squad: Array[PBAttacker] = [caster]
	var outcome := _sim(_wave(9), squad).run_to_end()
	assert_false(caster.alive, "施法者该死在落地之前")
	assert_gt(outcome.kills, 0, "但那一发该照样落地")


func test_the_battle_still_always_terminates() -> void:
	# 双向战斗多了一种死循环：谁也打不动谁，敌人咬住不走。
	# `MAX_TICKS` 是兜底，但正常配置下不该撞到它 —— 撞到就说明
	# 「打不动」是常态，而那是个配平问题伪装成的死锁。
	var squad: Array[PBAttacker] = [_unit(0.30, 1.0e9, 300.0)]
	var sim := _sim(_wave(9), squad)
	sim.run_to_end()
	assert_true(sim.is_finished(), "战斗该正常结束")
	assert_lt(sim.current_tick(), PBBattleSim.MAX_TICKS, "不该靠安全阀刹车")
