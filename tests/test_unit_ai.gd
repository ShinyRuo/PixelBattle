extends GutTest
## 近战与远程各自的 AI，敌我双方（§02，M4-c）。
##
## ## 这个文件守的是三件事
##
## 1. **交战中绝不后退。** M4-c 之前「够得着」走的是「回家」那一支，
##    于是敌人贴到脸上时忍者边打边往基地退 —— 看起来荒谬，
##    代码里却很自然：回家是默认值，压上去是唯一的例外分支，中间那档没人写
## 2. **近战真的会跑过去，远程真的会站住。** 在这之前两者的差别只是
##    「停火距离不同」，画面上看不出是两种打法
## 3. **远程敌人绝不停下。** 它的射程比己方近战长，停下来就等于站在一个
##    「我打得到你、你打不到我」的位置上 —— 那是个真死锁，
##    一队全近战的阵容会把游戏卡在那一波上

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260830


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 一个会跑、有血、打得动的己方单位。[param bullet] 大于 0 就是远程。
func _fighter(at: Vector2, reach: float, bullet: float) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = 500.0
	out.attack_speed = 1.0
	out.pos = at
	out.home = at
	out.reach = reach
	out.shot_speed = bullet
	out.max_hp = 1.0e9
	out.hp = out.max_hp
	out.leash = _cfg.unit_leash
	out.move_speed = _cfg.field_length / (_cfg.unit_move_seconds * float(_cfg.tick_rate))
	return out


## 一波只有一个敌人、站着不动的靶子局面。
func _one_enemy(squad: Array[PBAttacker], at: Vector2) -> PBBattleSim:
	var wave := _wave(6)
	wave.count = 1
	wave.hp_each = 1.0e12
	_cfg.spawn_window = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.distance = at.x
	enemy.lane = at.y
	enemy.speed = 0.0
	return sim


# ── 交战中不后退 ────────────────────────────────────────────────


func test_nobody_backs_off_while_a_target_is_in_reach() -> void:
	# **M4-c 修掉的那个 bug。** 敌人越走越近，「压到刚好够得着」那个点
	# 一路缩回出生站位，于是已经压上去的忍者会往基地方向退 ——
	# 而他此刻正在开火。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.10), 0.12, 0.0)]
	# 先让他压出去一截：把人挪到皮带绳的尽头。
	squad[0].pos.x = 0.30 + _cfg.unit_leash
	var sim := _one_enemy(squad, Vector2(0.34, 0.10))
	var before: float = squad[0].pos.x
	for _i: int in 20:
		sim.step()
	assert_gte(squad[0].pos.x, before - 1e-9, "够得着的时候一步都不该往回挪")


func test_everyone_walks_home_once_the_field_is_clear() -> void:
	# 不退的话，一波打完全队会停在最前沿，下一波开波的阵型
	# 就不是玩家排的那个了。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.10), 0.12, 0.0)]
	squad[0].pos = Vector2(0.40, 0.20)
	var sim := _one_enemy(squad, Vector2(0.34, 0.10))
	sim.enemies()[0].alive = false
	for _i: int in 60:
		sim.step()
	assert_almost_eq(squad[0].pos, squad[0].home, Vector2(1e-6, 1e-6), "场上没人了就该回原位")


# ── 近战跑过去，远程站住 ────────────────────────────────────────


func test_melee_closes_in_across_both_axes() -> void:
	# 「先跑到敌人周围，再攻击」。只在推进轴上挪的话，
	# 一个隔着几条泳道的目标他永远够不着，而画面上他就站在那儿不动。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.02), 0.05, 0.0)]
	var sim := _one_enemy(squad, Vector2(0.34, 0.22))
	for _i: int in 40:
		sim.step()
	assert_gt(squad[0].pos.y, 0.02 + 1e-6, "近战该朝那条泳道挪过去")
	assert_lte(
		squad[0].pos.distance_to(squad[0].home),
		_cfg.unit_leash + 1e-6,
		"但皮带绳还得拴住他 —— 放开就是全队挤到最前面，§02 的射程梯度没了"
	)


func test_ranged_holds_its_lane_and_only_presses_forward() -> void:
	# 远程的射程圈本来就罩着大半条道，横着挪一步能多够到的人远比竖着挪多。
	# 让他们也追着最近的目标上下跑的话，一队远程会来回甩动，
	# 而那不是玩家排的阵型。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.20, 0.02), 0.06, 0.10)]
	var sim := _one_enemy(squad, Vector2(0.60, 0.22))
	for _i: int in 40:
		sim.step()
	assert_almost_eq(squad[0].pos.y, 0.02, 1e-6, "远程不该离开自己那条泳道")
	assert_gt(squad[0].pos.x, 0.20 + 1e-6, "但该往前压")


# ── 敌人那一侧 ──────────────────────────────────────────────────


func test_the_wave_carries_both_kinds_of_enemy() -> void:
	# 分远近是按槽位定死的，不掷骰 —— 掷骰要占一条 RNG 流，
	# 而且会把它后面全部既有的结果都移走。
	var sim := PBBattleSim.new(_wave(15), 0.0, 0.0, _cfg)
	var melee: int = 0
	var ranged: int = 0
	for enemy: PBEnemy in sim.enemies():
		if enemy.shot_speed > 0.0:
			ranged += 1
		else:
			melee += 1
	assert_gt(ranged, 0, "该有远程")
	assert_gt(melee, ranged, "但主体仍该是近战")


func test_a_melee_enemy_stops_at_the_wall() -> void:
	# 「忍者是一堵墙」：漏怪意味着墙破了，而不是「时间到了自然会漏」。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), 0.12, 0.0)]
	var wave := _wave(6)
	wave.count = 1
	_cfg.spawn_window = 0.0
	_cfg.enemy_ranged_share = 0.0
	_cfg.field_height = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.hp = 1.0e12
	enemy.max_hp = enemy.hp
	for _i: int in 400:
		sim.step()
	assert_true(enemy.engaged, "撞上前排就该咬住")
	assert_gt(enemy.distance, 0.0, "而且再也没往前走一步")


func test_a_ranged_enemy_never_stops_so_it_cannot_deadlock() -> void:
	# **这一条守的是一个真死锁。** 远程敌人的射程（0.30）比己方近战（0.12）长，
	# 停下来就等于站在一个「我打得到你、你打不到我」的位置上 ——
	# 双方都杀不死对方、敌人又不推进，整波只能靠安全阀刹车，
	# 而一队全近战的阵容会把游戏卡在那一波上十几分钟。
	#
	# 所以射手边走边射：玩家必须**杀掉**他，而不是**挡住**他。
	_cfg.enemy_ranged_share = 1.0
	_cfg.field_height = 0.0
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), 0.12, 0.0)]
	squad[0].dps = 0.0
	var wave := _wave(6)
	wave.count = 1
	_cfg.spawn_window = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.run_to_end()
	assert_true(sim.is_finished(), "射手绝不该把一波卡死")
	assert_lt(sim.current_tick(), PBBattleSim.MAX_TICKS, "而且不是靠安全阀结束的")


func test_a_ranged_enemy_shoots_instead_of_touching() -> void:
	# 远程敌人在**够不着的距离外**就开始造成伤害 —— 那是它和近战唯一
	# 看得见的区别。子弹是红的（[constant PBShotPool.ENEMY_COLOR]），
	# 好让玩家读得出「有几发正朝我飞」。
	_cfg.enemy_ranged_share = 1.0
	_cfg.field_height = 0.0
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), 0.12, 0.0)]
	squad[0].dps = 0.0
	squad[0].move_speed = 0.0
	squad[0].max_hp = 1.0e9
	squad[0].hp = squad[0].max_hp
	var wave := _wave(6)
	wave.count = 1
	_cfg.spawn_window = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	var enemy: PBEnemy = sim.enemies()[0]
	var flew: bool = false
	for _i: int in 400:
		sim.step()
		for shot: PBProjectile in sim.shots():
			if shot.alive and shot.at_ally:
				flew = true
		if squad[0].hp < squad[0].max_hp:
			break
	assert_true(flew, "该有红子弹朝己方飞")
	assert_lt(squad[0].hp, squad[0].max_hp, "而且真的打中了")
	assert_gt(enemy.distance, squad[0].pos.x + _cfg.enemy_reach, "开火时还远在近战距离之外")
