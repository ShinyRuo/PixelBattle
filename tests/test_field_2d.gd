extends GutTest
## 战场从一维升成二维（§02，M4-a）。
##
## ## 这个文件守的是「升维没有改坏语义」
##
## 改的是**坐标系**，不是规则：射程、大招半径、防挤、敌人还手全部换成
## 二维判定，但**每一条规则说的还是同一句话**。这种改动最容易出的错是
## 「某一条悄悄换了含义」，而它不报错 —— 表现只是几万局扫描的数字偏了一点。
##
## 所以第一条也是最重要的一条是**降维对拍**：把
## [member PBSimConfig.field_height] 设成 0，所有泳道塌成 0，
## 欧氏距离退化成 `|Δx|`，这时逐 tick 的结果必须和一维时代**逐字段一致**。
## 一维那一版的参照物是 [PBCombatRules] 的解析式排队模型 —— 它从 M-1 起
## 一个字没动过，而 `test_battle_sim.gd` 一直拿它对拍。
##
## 其余几条钉的是「二维真的在起作用」：纵向不再是装饰。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260830


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


# ── 降维对拍 ────────────────────────────────────────────────────


func test_a_flat_field_still_matches_the_analytic_queue_model() -> void:
	# **本文件的正题。** 战场高度归零 = 回到一维，这时逐 tick 模型必须
	# 仍然是解析式排队模型的等价物。差了就说明升维改动了某条规则本身，
	# 而不只是换了坐标。
	_cfg.field_height = 0.0
	for dps: float in [120.0, 600.0, 3000.0]:
		for index: int in [3, 11, 20]:
			var wave := _wave(index)
			var ticked := PBBattleSim.new(wave, dps, 0.0, _cfg).run_to_end()
			var solved := PBCombatRules.resolve(wave, dps, 0.0, _cfg)
			assert_eq(
				ticked.kills,
				solved.kills,
				"第 %d 波 %.0f DPS：压平之后两个模型该杀一样多" % [index, dps]
			)
			assert_eq(ticked.leaked, solved.leaked, "漏怪数也该一样")


func test_a_flat_field_makes_reach_one_dimensional_again() -> void:
	# 压平之后「够不够得着」就该退回 `|Δx| <= reach`。
	var attacker := PBAttacker.new()
	attacker.pos = Vector2(0.30, 0.0)
	attacker.reach = 0.12
	assert_true(attacker.can_reach(Vector2(0.42, 0.0)), "正好在射程边缘该够得着")
	assert_false(attacker.can_reach(Vector2(0.43, 0.0)), "多一点就够不着")


func test_the_whole_field_attacker_covers_the_corners() -> void:
	# 退化标量的射程要盖住**对角**，不是长度。用长度的话它够不着角落里的敌人，
	# 而现象是「解析式对拍突然差了几个 tick」—— 从那个现象反推极难。
	var solo := PBAttacker.whole_field(100.0, _cfg.field_diagonal())
	var corner := Vector2(_cfg.field_length, _cfg.field_height)
	assert_true(solo.can_reach(corner), "站在基地上要够得着最远的那个角")


# ── 纵向真的算数了 ──────────────────────────────────────────────


func test_range_is_a_circle_now_not_a_column() -> void:
	# 升维之前 y 是渲染层编的装饰，同一个 x 上的敌人无论在哪条泳道都挨打。
	var attacker := PBAttacker.new()
	attacker.pos = Vector2(0.30, 0.05)
	attacker.reach = 0.10
	assert_true(attacker.can_reach(Vector2(0.30, 0.14)), "同一列、隔 0.09 条泳道，够得着")
	assert_false(attacker.can_reach(Vector2(0.30, 0.20)), "隔 0.15 条泳道就够不着了")


func test_stopping_distance_pays_for_the_lane_gap() -> void:
	# 「往前压到刚好够得着」在二维里不再是 `目标 − 射程`：
	# 纵向差掉的那一截要先从射程里扣掉，否则单位会停在一个打不到的地方，
	# 而现象是「他明明走到位了却不开火」。
	#
	# **M6-q 起扣的是 [method PBAttacker.stop_gap] 不是 `reach`** ——
	# 停在正好够得着那一点上，浮点会让 [method PBAttacker.can_reach] 判成
	# 够不着（下面最后那条断言量的就是这件事）。
	var attacker := PBAttacker.new()
	attacker.pos = Vector2(0.30, 0.0)
	attacker.reach = 0.50
	var flat: float = attacker.reach_stop_x(Vector2(1.0, 0.0))
	assert_almost_eq(flat, 1.0 - attacker.stop_gap(), 1e-6, "同一条泳道就是目标减停火距离")
	var flat_stand := PBAttacker.new()
	flat_stand.pos = Vector2(flat, 0.0)
	flat_stand.reach = attacker.reach
	assert_true(flat_stand.can_reach(Vector2(1.0, 0.0)), "站到那儿就必须真的够得着")
	var slanted: float = attacker.reach_stop_x(Vector2(1.0, 0.30))
	assert_gt(slanted, flat, "斜着够要往前多走一截")
	attacker.pos.x = slanted
	assert_true(attacker.can_reach(Vector2(1.0, 0.30)), "走到那儿就该正好够得着")


func test_enemies_spawn_onto_real_lanes() -> void:
	# 泳道从渲染层搬进了 sim。搬之前画面自己编一份，sim 一个字节都不知道；
	# 搬之后**画面一个像素都没变**，但它开始参与判定。
	var sim := PBBattleSim.new(_wave(8), 500.0, 0.0, _cfg)
	var lanes := {}
	for enemy: PBEnemy in sim.enemies():
		assert_between(enemy.lane, 0.0, _cfg.field_height, "泳道要落在战场高度之内")
		lanes[enemy.lane] = true
	assert_gt(lanes.size(), 1, "整波敌人不该全挤在同一条泳道上")


func test_an_ultimate_hits_a_disc_not_a_stripe() -> void:
	# 半径升成真圆之后，落点正上方但隔了几条泳道的敌人打不到了。
	# **一发大招因此比一维时代弱**，那是这次升维最大的一笔数值变动。
	var radius: float = 0.10
	var spot := Vector2(0.5, 0.10)
	assert_true(spot.distance_to(Vector2(0.5, 0.18)) <= radius, "同一列近处的中")
	assert_false(spot.distance_to(Vector2(0.5, 0.24)) <= radius, "同一列远处的不中")


func test_the_aim_picks_a_lane_not_just_a_distance() -> void:
	# 落点是二维的，所以它得挑一条泳道。全挑 0 的话，一半的敌人
	# 永远不会被大招碰到，而那不报错。
	var skill := PBSkill.new()
	skill.radius = 0.06
	skill.delay_ticks = 0
	var enemies: Array[PBEnemy] = []
	for i: int in 6:
		var enemy := PBEnemy.new()
		enemy.slot = i
		enemy.alive = true
		enemy.distance = 0.5
		enemy.lane = 0.20
		enemies.append(enemy)
	var spot := PBAimRules.pick_spot(PBAimRules.Policy.AUTO, enemies, 1, skill, 0, 1, 1, 10)
	assert_true(PBSkillCast.is_spot(spot), "有六个人挤在一起，该放")
	assert_almost_eq(spot.y, 0.20, 1e-6, "落点该压在他们那条泳道上，不是压在 0")


func test_separation_leaves_different_lanes_alone() -> void:
	# 一维时代「同一个 x」就等于重合，所以防挤一律把后面那个往出生点垫。
	# 纵向算数之后，各占一条泳道的两个人本来就没挤在一起 ——
	# 照旧垫的话，整波敌人会被排成一条长队，那正是「敌人一个一个出现」
	# 那个观感的一半来源，而 M4-d 要让他们一起冲上来。
	#
	# 出怪窗口压成 0，让整波同一 tick 出生在同一个 x 上：
	# 留着窗口的话他们本来就前后错开，量不到防挤有没有动手。
	#
	# **判据是整队在推进轴上摊开了多宽**，不是逐对比间距：
	# 出生点在 `field_length` 上，往后垫会被战场边界钳住
	# （那道钳子是 M4-d 「一次全刷」要处理的另一件事），
	# 逐对断言会量到钳子而不是量到泳道。
	# 阵型深度也要关掉（M4-d）：整波方阵本身就有一截 x 跨度，
	# 留着的话量到的是阵型，不是防挤。
	_cfg.spawn_window = 0.0
	_cfg.spawn_column_gap = 0.0
	_cfg.field_height = 0.0
	assert_gt(_span_after(_wave(15), 40), 0.05, "压平之后大家都在同一条泳道上，该被垫成一条长队")

	_cfg = PBSimConfig.new()
	_cfg.spawn_window = 0.0
	_cfg.spawn_column_gap = 0.0
	assert_lt(_span_after(_wave(15), 40), 0.01, "隔着泳道就不该被垫开，整队该还是挤在一起冲")


## 跑 [param ticks] 个 tick 之后，整队敌人在推进轴上摊开了多宽。
##
## 己方 DPS 给 0：死人会退出队列，那会让「摊开多宽」量到的是伤害而不是防挤。
func _span_after(wave: PBWave, ticks: int) -> float:
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg)
	assert_gt(sim.enemies().size(), 6, "这一波要有足够多的敌人")
	for _i: int in ticks:
		sim.step()
	var lo: float = INF
	var hi: float = -INF
	for enemy: PBEnemy in sim.enemies():
		lo = minf(lo, enemy.distance)
		hi = maxf(hi, enemy.distance)
	return hi - lo
