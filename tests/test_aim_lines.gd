extends GutTest
## 那根「他要打谁」的线，指向对不对（§02，M5-11 / M5-12）。
##
## ## 这个文件守的是「线说的必须是真的」
##
## 画它只有两条路：**照着同一套规则再算一遍**，或者把 sim 算出来的
## 那一个记下来（[member PBAttacker.aim_at]）。再算一遍就是第二把尺子 ——
## 点名、射程、出场时刻、死活四个条件里漏抄一个，线就指着一个他其实
## 没在打的敌人，**而且不报错**。这个项目为这种形状的 bug 付过四次代价。
##
## 从 [`test_battle_control.gd`] 里分出来是因为那个文件破了 gdlint 的
## 20 个公开方法上限。分界说得清：那边是「点下去会发生什么」，
## 这边是「屏幕上画出来的那一根指着谁」。
##
## **线本身（[PBAimLines]）不在这里测**，那是像素；
## 这里测的是它读的那个字段。

const FIXED_SEED: int = 20260830

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 一个站在原地、够得着全场的射手。
func _shooter() -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = 1000.0
	out.attack_speed = 4.0
	out.pos = Vector2.ZERO
	out.reach = _cfg.field_diagonal()
	out.max_hp = 1.0e9
	out.hp = out.max_hp
	return out


func test_the_sim_records_who_each_ninja_is_going_to_hit() -> void:
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	assert_eq(squad[0].aim_at, -1, "开波还没跑过一个 tick，目标是空的")
	sim.step()
	assert_gte(squad[0].aim_at, 0, "场上有敌人就该有目标")
	assert_lt(squad[0].aim_at, sim.enemies().size(), "而且是一个真敌人的下标")

	var named: PBEnemy = sim.enemies()[sim.enemies().size() - 1]
	squad[0].forced_target = named.slot
	sim.step()
	assert_eq(squad[0].aim_at, named.slot, "点名之后记的该是点名的那个")


func test_the_line_follows_the_naming_even_out_of_range() -> void:
	# 玩家点一个**还没走到**的目标时，那根线恰恰最要紧 —— 它是
	# 「这条命令收到了、他正朝那儿去」的唯一反馈。
	#
	# M5-11 那一版记的是「上一发打中了谁」，于是这一刻画的是别人、
	# 或者干脆什么都不画，而那正是玩家最需要看见它的时候。
	var shooter := _shooter()
	shooter.reach = 0.05
	var squad: Array[PBAttacker] = [shooter]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	var named: PBEnemy = sim.enemies()[sim.enemies().size() - 1]
	shooter.forced_target = named.slot
	sim.step()
	assert_false(shooter.can_reach(named.pos()), "前提：这个目标还够不着")
	assert_eq(shooter.aim_at, named.slot, "够不着也该指着他 —— 那是他要去打的人")


func test_naming_a_target_moves_the_line_without_a_tick() -> void:
	# **暂停时 sim 的每 tick 那一遍不跑**（[method PBBattleSim._aim_targets]），
	# 所以只写 `forced_target` 的话，绿线要等玩家取消暂停才切过去。
	# 而 §02 特意允许暂停下操作 —— 那一刻的即时反馈正是这两步操作的全部意义，
	# 不然玩家无从知道自己那一下点中了没有。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	sim.step()
	var before: int = squad[0].aim_at
	var named: PBEnemy = sim.enemies()[sim.enemies().size() - 1]
	assert_ne(before, named.slot, "前提：他本来要打的不是这一个")
	sim.name_target(squad[0], named.slot)
	assert_eq(squad[0].aim_at, named.slot, "一个 tick 都不用跑就该切过去")
	sim.name_target(squad[0], -1)
	assert_eq(squad[0].aim_at, before, "交回自动选敌也是立刻的")


func test_every_wave_forgets_who_it_was_aiming_at() -> void:
	# 攻击者对象跨波复用（[method PBAttacker.revive]）。不清的话开波第一帧
	# 会拿上一波的下标去索引这一波的敌人数组 —— 画出来的线指向一个
	# **和他毫无关系的敌人**，而下标是合法的，所以不报错。
	var squad: Array[PBAttacker] = [_shooter()]
	var first := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	first.step()
	assert_gte(squad[0].aim_at, 0, "先挑上一个目标")
	PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	assert_eq(squad[0].aim_at, -1, "下一波开波该忘干净")
