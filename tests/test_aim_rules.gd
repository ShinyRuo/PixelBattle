extends GutTest
## [PBAimRules] 与 [PBSkillCast] 的测试。M3-b，M7-b 起大招拆成
## [PBSkill]（设定）+ [PBSkillCast]（这一波的冷却/落点状态）。
##
## ## 这个文件守的是一对上下夹，不是一个功能
##
## §02 把吸怪技巧做成分层的（手机自动选点 / PC 手动操作），
## 而那条分层只有在**两头同时成立**时才算数：
##
## - 自动**够用**：「纯自动落点玩到的极限波次 ≥ 手动的 78%」
## - 手动**有赚头**：「手动带来 15–25% 的效率提升」
##
## 自动太笨则手机端残废，自动太聪明则 PC 的走位技巧没意义。
## 下面几条钉的是这对夹子赖以成立的机制本身 ——
## 具体的百分比要靠整局扫描量，那是 `batch_sim.gd --aim` 的事。
##
## 手动比自动强在**两个维度**上，两维都在这里各有断言：
##
## 1. **往哪儿放**（预判落地那一刻的位置）—— 实测这一维几乎不值钱，
##    因为敌人同速前进、领先距离远小于杀伤半径，理由见 [method PBAimRules.pick_spot]
## 2. **什么时候放**（攒着等聚拢）—— 技巧真正的所在

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


## 造一个只关心半径与延迟的技能定义，别的字段用不上。
func _skill(radius: float, delay_ticks: int) -> PBSkill:
	var out := PBSkill.new()
	out.radius = radius
	out.delay_ticks = delay_ticks
	return out

func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260828


## 造一排敌人，[param distances] 是各自离基地多远（必须从小到大，
## 那是敌人数组天然的顺序：先出场的走得久、离基地近）。
##
## **全部摆在泳道 0 上**（M4-a）。本文件量的是「往哪儿放、什么时候放」，
## 那两条都在推进轴上；散开泳道的话，落点的 y 会跟着动，
## 断言里的每一个 x 都要连带解释一遍纵向，而纵向不是这里的题目。
## 落点真的会挑泳道，那一条钉在 `test_field_2d.gd` 里。
func _enemies_at(distances: Array, speed: float = 0.01) -> Array[PBEnemy]:
	var out: Array[PBEnemy] = []
	for d: float in distances:
		var enemy := PBEnemy.new()
		enemy.alive = true
		enemy.hp = 100.0
		enemy.max_hp = 100.0
		enemy.distance = d
		enemy.speed = speed
		enemy.spawn_tick = 0
		out.append(enemy)
	return out


# ── 落点怎么挑 ──────────────────────────────────────────────────


func test_it_picks_the_densest_cluster_not_the_nearest_enemy() -> void:
	# 落点的全部价值在命中数上（§02 那条乘法关系）。
	# 挑「最靠近基地的那个」是普攻的规则，不是大招的 —— 搞混了的话
	# 大招永远只打一个人，§02 中间那个因子就恒等于 1。
	var enemies := _enemies_at([0.10, 0.50, 0.52, 0.54])
	var spot := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.05, 0), 0, 1, 1, 0
	)
	assert_almost_eq(spot.x, 0.52, 0.021, "该罩住 0.50–0.54 那三个，而不是孤零零的 0.10")


func test_a_tie_goes_to_the_cluster_closest_to_the_base() -> void:
	# 两堆一样多时打更紧急的那堆 —— 同样打 n 个，打掉快漏进去的那 n 个更值。
	var enemies := _enemies_at([0.20, 0.22, 0.70, 0.72])
	var spot := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.03, 0), 0, 1, 1, 0
	)
	assert_lt(spot.x, 0.5, "并列时该选靠近基地的那一堆")


func test_it_holds_fire_when_too_few_targets_are_in_reach() -> void:
	# 攒着不放也是一种决策。冷却 20 秒、单波才十几秒，
	# 一发喂给一个杂兵等于这一波白打。
	var enemies := _enemies_at([0.40])
	var spot := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.05, 0), 0, 3, 1, 0
	)
	assert_false(PBSkillCast.is_spot(spot), "只有一个目标、门槛是三个，应该攒着")


func test_the_none_policy_never_fires() -> void:
	# 基线档。用来量「大招整体值多少」，它必须真的一发都不放。
	var enemies := _enemies_at([0.40, 0.42, 0.44, 0.46])
	var spot := PBAimRules.pick_spot(
		PBAimRules.Policy.NONE, enemies, 0, _skill(0.05, 0), 0, 1, 1, 0
	)
	assert_false(PBSkillCast.is_spot(spot), "NONE 档不该给出任何落点")


func test_dead_enemies_in_the_middle_do_not_hide_the_ones_behind_them() -> void:
	# **这条守的是一个不报错的失效。** 扫描碰到「还没出场的」可以停，
	# 但碰到**尸体**必须继续 —— 射程、AOE 和大招会让敌人乱序死亡，
	# 拿「活着且已出场」当停止条件的话，一具中间的尸体会让后面的全被漏掉。
	var enemies := _enemies_at([0.10, 0.50, 0.52, 0.54])
	enemies[0].alive = false
	var spot := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.05, 0), 0, 1, 1, 0
	)
	assert_almost_eq(spot.x, 0.52, 0.021, "队头的尸体不该挡住后面那一堆")


# ── 预判：自动与手动的分野 ──────────────────────────────────────


func test_leading_aims_where_the_pack_will_be_not_where_it_is() -> void:
	# **§02 分层的全部机制就在这一条上。**
	# 手机端看当前帧、PC 端看落地那一刻，两者的差就是「提前半秒压在
	# 行进路线前方」。敌人朝基地走（distance 变小），所以预判点必然更靠前。
	var enemies := _enemies_at([0.50, 0.52, 0.54], 0.01)
	var now := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.05, 10), 0, 1, 1, 0
	)
	var ahead := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 10), 0, 1, 1, 0
	)
	assert_lt(ahead.x, now.x, "预判落点该压在敌人前方（更靠近基地）")
	assert_almost_eq(now.x - ahead.x, 0.10, 1e-6, "领先量应正好等于 速度 × 延迟")


func test_without_a_cast_delay_the_two_policies_cannot_differ() -> void:
	# 延迟为 0 时预判无处可用，两档必然同分 —— §02 那两条验收会
	# 恒等于 100%，看着达标其实什么都没测。
	# 这条把「延迟是分层的前提」这件事钉死，免得有人顺手把它调成 0。
	var enemies := _enemies_at([0.50, 0.52, 0.54])
	var now := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.05, 0), 0, 1, 1, 0
	)
	var ahead := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 0), 0, 1, 1, 0
	)
	assert_eq(now, ahead, "没有施法延迟就没有预判，两档必须同分")


func test_enemies_that_arrive_before_impact_are_not_aimed_at() -> void:
	# 预判要把「落地前就冲进基地的」排除掉 —— 那时候他已经不在场上，
	# 把落点压在他身上等于白放一发。
	var enemies := _enemies_at([0.05, 0.60, 0.62, 0.64], 0.01)
	var ahead := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 10), 0, 1, 1, 0
	)
	assert_gt(ahead.x, 0.3, "已经跑进基地的那个不该被选为落点")


# ── 什么时候放：技巧真正的所在 ──────────────────────────────────


func test_the_manual_policy_saves_it_for_a_worthwhile_cluster() -> void:
	# **手动比自动强的那一维就在这里。**
	# 场上只有两个人时，自动档（门槛 2）已经按下去了，手动档（门槛 5）还在等。
	# 这个差不成立的话，PC 端的操作在模型里没有任何赚头，
	# §02 那条「手动带来 15–25% 提升」就永远量不出来。
	var enemies := _enemies_at([0.40, 0.42])
	var auto_spot := PBAimRules.pick_spot(
		PBAimRules.Policy.AUTO, enemies, 0, _skill(0.05, 0), 0, 2, 5, 100
	)
	var held := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 0), 0, 2, 5, 100
	)
	assert_true(PBSkillCast.is_spot(auto_spot), "自动档够门槛就该放")
	assert_false(PBSkillCast.is_spot(held), "手动档该攒着等更多目标")


func test_the_manual_policy_fires_once_the_cluster_is_worth_it() -> void:
	# 攒是有条件的，不是一味不放。够五个就该按下去。
	var enemies := _enemies_at([0.40, 0.42, 0.44, 0.46, 0.48])
	var held := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 0), 0, 2, 5, 100
	)
	assert_true(PBSkillCast.is_spot(held), "罩得住五个了就该放")


func test_holding_has_a_deadline_so_the_strike_is_never_wasted() -> void:
	# 没有死线的话，稀疏波次里大招会被一直捏到战斗结束 ——
	# 一发没放比手机端还差，验收会得出「手动是负收益」的假结论。
	var enemies := _enemies_at([0.40, 0.42])
	var still_holding := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 0), 30, 2, 5, 100
	)
	var past_deadline := PBAimRules.pick_spot(
		PBAimRules.Policy.LEAD, enemies, 0, _skill(0.05, 0), 100, 2, 5, 100
	)
	assert_false(PBSkillCast.is_spot(still_holding), "没到死线继续攒")
	assert_true(PBSkillCast.is_spot(past_deadline), "到了死线就得放，不能捏死在手里")


# ── 大招在战斗里的行为 ──────────────────────────────────────────


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 造一个单人小队，大招参数直接给死，免得被配置的占位值牵着走。
func _squad_with_ultimate(damage: float, radius: float, gather: bool = false) -> Array[PBAttacker]:
	var attacker := PBAttacker.new()
	attacker.dps = 0.0
	attacker.pos = Vector2.ZERO
	attacker.reach = 0.0
	var skill := PBSkill.new()
	skill.damage = damage
	skill.radius = radius
	skill.cooldown_ticks = 10000
	skill.delay_ticks = 10
	skill.gather = gather
	attacker.ultimate = PBSkillCast.new(skill)
	var squad: Array[PBAttacker] = [attacker]
	return squad


func test_the_strike_lands_after_the_delay_not_on_the_tick_it_is_ordered() -> void:
	# 施法延迟必须真的存在于时间轴上，否则预判没有立足之地。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_min_targets = 1
	var wave := _wave(8)
	var squad := _squad_with_ultimate(wave.hp_each * 10.0, 1.0)
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.step()
	assert_eq(sim.result().kills, 0, "下达的那一 tick 不该有人死 —— 大招还在飞")
	for _i: int in 10:
		sim.step()
	assert_gt(sim.result().kills, 0, "延迟走完之后才结算伤害")


func test_the_strike_only_hits_inside_its_radius() -> void:
	_cfg.spawn_window = 0.0
	_cfg.ultimate_min_targets = 1
	var wave := _wave(8)
	assert_gt(wave.count, 4, "这一波要有足够多的敌人")
	# 半径给到几乎为零：落点上那一个（可能连带紧挨着的）之外都不该掉血。
	var squad := _squad_with_ultimate(wave.hp_each * 10.0, 0.001)
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	for _i: int in 12:
		sim.step()
	assert_lt(sim.result().kills, wave.count, "半径外的敌人不该被波及")


func test_gathering_drags_survivors_onto_the_landing_spot() -> void:
	# §02 的拉拽：把范围内的敌人拖到一点，好让后续的 AOE 一次罩住更多。
	# 伤害给 0，单纯看位移 —— 掺了伤害就分不清「拖过来了」和「打死了」。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_min_targets = 1
	var wave := _wave(8)
	var squad := _squad_with_ultimate(0.0, 1.0, true)
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	for _i: int in 12:
		sim.step()
	var spread: float = 0.0
	var seen: Array[float] = []
	for enemy: PBEnemy in sim.active_enemies():
		seen.append(enemy.distance)
	assert_gt(seen.size(), 2, "场上要有几个敌人才谈得上聚拢")
	spread = seen.max() - seen.min()
	# **判据是「挤成一团」，不是「落在同一点」。** M3.5-c 的防挤会把
	# 拖到同一点的敌人展开成一个队列（不然画出来是一个单位）。
	# 聚拢的价值本来也不是坐标相等，是「一发 AOE 能罩住几个」——
	# 队列间距 0.012 远小于大招半径，那个价值一分没少。
	assert_lt(
		spread, float(seen.size()) * _cfg.unit_min_gap + 1e-6, "聚拢之后该挤成一条紧队列"
	)


func test_a_battle_with_ultimates_still_conserves_enemies() -> void:
	# 守恒律：一个敌人要么被杀要么漏过去。大招是第三种伤害来源，
	# 记账漏一处不会报错，只表现为「击杀数对不上」。
	_cfg.ultimate_min_targets = 1
	for wave_index: int in [6, 19, 33]:
		var wave := _wave(wave_index)
		var squad := _squad_with_ultimate(wave.hp_each * 2.0, 0.15)
		var out := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad).run_to_end()
		assert_eq(out.kills + out.leaked, wave.count, "第 %d 波：击杀+漏怪应等于总数" % wave_index)


func test_the_cooldown_starts_at_impact_not_at_the_order() -> void:
	# 从下达算的话，施法延迟会被白送成冷却的一部分 —— 延迟越长反而越强，
	# 而延迟本该是预判的**代价**。
	var skill := PBSkill.new()
	skill.cooldown_ticks = 100
	skill.delay_ticks = 10
	var cast := PBSkillCast.new(skill)
	cast.cast(Vector2(0.5, 0.0), 0)
	assert_true(cast.is_pending(), "下达之后应处于待落地状态")
	assert_false(cast.is_ready(0), "手上还有一发没落地时不该再下达")
	cast.land(10)
	assert_false(cast.is_ready(105), "冷却该从落地那一刻算起")
	assert_true(cast.is_ready(110), "落地后满一个冷却才转好")
