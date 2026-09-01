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
## 3. **敌人不会从活着的忍者身边溜过去。**（M5-7 换掉了原来那一条）
##
## ## 第 3 条 M5-7 反了过来
##
## M4-c 到 M5-6 的规矩是「远程敌人绝不停下」，理由是死锁：它的射程 0.30
## 比己方近战 0.12 长，停下来就站在「我打得到你、你打不到我」的位置上。
##
## 那个前提被两条改动一起拆了 —— 皮带绳放到 0.35、近战改成贴身 0.02，
## 近战够得着停在 0.30 上的射手了。于是「边走边射」变成了错的那一个：
## **一条没人站的泳道等于一条高速公路**，忍者还站着，基地已经在掉血。
##
## 现在敌人**扑向最近的活忍者**，全死光了才走基地。终止性换了依据：
## 敌人的伤害恒大于 0、忍者不回血，所以咬住的一方必定在有限时间内清完场。
## 那正是下面 `test_the_wave_resumes_once_the_defender_is_dead` 钉的东西。

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


func test_ranged_holds_its_lane_while_x_alone_can_still_close_the_gap() -> void:
	# 远程的射程圈本来就罩着大半条道，横着挪一步能多够到的人远比竖着挪多。
	# 让他们也追着最近的目标上下跑的话，一队远程会来回甩动，
	# 而那不是玩家排的阵型。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.20, 0.02), 0.06, 0.10)]
	var sim := _one_enemy(squad, Vector2(0.60, 0.05))
	for _i: int in 40:
		sim.step()
	assert_almost_eq(squad[0].pos.y, 0.02, 1e-6, "纵向差还在射程内，就不该离开自己那条泳道")
	assert_gt(squad[0].pos.x, 0.20 + 1e-6, "但该往前压")


func test_ranged_gives_up_its_lane_only_when_x_provably_cannot_reach() -> void:
	# **M5-8 补的那一档。** 射程是个真圆（M4-a），纵向差本身就超出射程时，
	# x 上没有任何一个点能把它收回来 —— 只在推进轴上挪等于站着不动。
	#
	# 这一档在 M5-7 之前几乎不发生：敌人沿直线推进，每条泳道迟早都有人走过。
	# 敌人改成扑向最近的活忍者之后，整波会聚到前排那一个人身上，于是
	# 一个站在另一头的远程忍者视野里从头到尾一个敌人都没有 ——
	# 实测「1 近战 + 3 远程」里最远那个整场只放得出 5 发。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.20, 0.02), 0.06, 0.10)]
	var sim := _one_enemy(squad, Vector2(0.60, 0.22))
	for _i: int in 40:
		sim.step()
	assert_gt(squad[0].pos.y, 0.02 + 1e-6, "够不着就得朝那条泳道挪过去")
	assert_lte(
		squad[0].pos.distance_to(squad[0].home),
		_cfg.unit_leash + 1e-6,
		"但绳子照旧拴着 —— 挪的是自己那一格附近，不是横穿半个战场"
	)


# ── 皮带绳的那个例外（M5-8）──────────────────────────────────────


func test_a_parked_shooter_beyond_the_leash_gets_chased_down() -> void:
	# 敌人一走进自己的射程就**永久站住**，而站在哪由「最靠前的那个忍者」定；
	# 忍者能走多远由**他自己的站位**定。两把尺子量的不是同一件事，
	# 于是很容易停在一个谁都够不着的位置上。
	#
	# 实测（M5-8 之前）：一队全近战对上停在 0.80 放枪的远程敌人 ——
	# **105 秒、每人打出 6 下、全灭**，屏幕上是四个人站成一排挨枪。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), _cfg.reach_melee, 0.0)]
	var sim := _one_enemy(squad, Vector2(0.30 + _cfg.unit_leash + 0.15, 0.0))
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.reach = 1.0
	for _i: int in 200:
		sim.step()
	assert_true(enemy.engaged, "它已经站定了 —— 这是那个例外的前提")
	assert_almost_eq(
		squad[0].pos.x, enemy.distance - _cfg.reach_melee, 1e-3, "站定的是个静止靶，就该走过去打"
	)


func test_an_incoming_wave_does_not_pull_anyone_off_their_spot() -> void:
	# 例外的条件是「**已经站定**」，不是「够不着」。只看够不着的话，
	# 开波那一刻全部敌人都在 x≥1.0、谁都罩不住，绳子当场松开 ——
	# 近战忍者会**冲向出怪点**，把自己送到远离远程队友的地方单挑整波。
	#
	# 站定的那个已经不动了，追它是一段有终点的路；迎面走来的那一群不是。
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), _cfg.reach_melee, 0.0)]
	var sim := _one_enemy(squad, Vector2(1.0, 0.0))
	sim.enemies()[0].reach = 0.0
	for _i: int in 200:
		sim.step()
	assert_almost_eq(
		squad[0].pos.x, 0.30 + _cfg.unit_leash, 1e-6, "没站定的敌人拉不动他，绳子到头就是到头"
	)


func test_a_melee_ninja_can_reach_whatever_stops_in_front_of_him() -> void:
	# **M5-7 留下的那个洞。** 敌人停在离忍者 `enemy_reach` 处，
	# 而 M5-7 把 [member PBSimConfig.reach_melee] 从 0.12 降到 0.02
	# 却没动 `enemy_reach`（0.06）—— 0.06 > 0.02，于是一个近战忍者
	# 站在怪堆正中间**整场一发打不出去**，挨完打倒下。
	#
	# 现象是「他明明贴着敌人」而伤害数字一个都不飘，攻速、装备、羁绊
	# 全部照常显示在信息栏上，测试也全绿 —— 两边不共用一把尺子就会这样。
	assert_lte(_cfg.enemy_reach, _cfg.reach_melee, "敌人的近战射程不能比忍者的长")
	_cfg.enemy_ranged_share = 0.0
	_cfg.field_height = 0.0
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), _cfg.reach_melee, 0.0)]
	var wave := _wave(6)
	wave.count = 1
	wave.hp_each = 1.0e12
	_cfg.spawn_window = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.hp = wave.hp_each
	enemy.max_hp = enemy.hp
	for _i: int in 400:
		sim.step()
	assert_true(enemy.engaged, "它该走到贴身处咬住")
	assert_lt(enemy.hp, enemy.max_hp, "而忍者该打得还手")


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


func test_an_enemy_never_walks_past_a_living_ninja() -> void:
	# **玩家点名要的那一条**（M5-7）：「只有场上忍者全部死亡才会走向基地扣血」。
	#
	# 在这之前敌人沿直线推进、路过谁打谁，于是**一条没人站的泳道就是一条
	# 高速公路** —— 忍者还站得好好的，基地已经在掉血了。而 §02 那套
	# 「忍者是一堵墙」的说法要求墙没破之前后面是安全的。
	#
	# 局面：忍者站在最上面那条泳道，敌人生在最下面。旧规则下两者永不相遇。
	_cfg.enemy_ranged_share = 0.0
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.02), 0.02, 0.0)]
	squad[0].dps = 0.0
	var wave := _wave(6)
	wave.count = 1
	_cfg.spawn_window = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.lane = _cfg.field_height
	enemy.hp = 1.0e12
	enemy.max_hp = enemy.hp
	for _i: int in 600:
		sim.step()
	assert_true(enemy.engaged, "该扑过来咬住他，不是从旁边溜过去")
	assert_almost_eq(enemy.lane, squad[0].pos.y, 0.05, "而且真的换了泳道")
	assert_eq(sim.result().leaked, 0, "忍者还活着，基地就不该掉一滴血")


func test_the_wave_resumes_once_the_defender_is_dead() -> void:
	# **终止性换了依据。** 敌人咬住就不走，所以「这一波会不会打完」
	# 不再靠「敌人始终在前进」，而靠**忍者一定会死**：
	# 敌人的伤害恒大于 0（护甲不可能全免），而忍者不回血。
	#
	# 这一条是 M4-c 那个「远程绝不停下」的替代品 —— 那一条防的是死锁，
	# 而死锁现在由这里挡住：墙破了，敌人就接着走。
	_cfg.enemy_ranged_share = 1.0
	_cfg.field_height = 0.0
	var squad: Array[PBAttacker] = [_fighter(Vector2(0.30, 0.0), _cfg.reach_melee, 0.0)]
	squad[0].dps = 0.0
	# 血量按真角色的量级给，不是 1e9 —— 一个打不死的忍者会**合法地**
	# 把这一波守到天荒地老，那正是上一条测的设计，不是 bug。
	squad[0].max_hp = 200.0
	squad[0].hp = squad[0].max_hp
	var wave := _wave(6)
	wave.count = 1
	_cfg.spawn_window = 0.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.run_to_end()
	assert_false(squad[0].alive, "打不动又扛不住，这个忍者必须先倒下")
	assert_true(sim.is_finished(), "然后这一波就该正常打完")
	assert_lt(sim.current_tick(), PBBattleSim.MAX_TICKS, "而且不是靠安全阀结束的")
	assert_eq(sim.result().leaked, 1, "墙破了，那个敌人就该走到基地")


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
