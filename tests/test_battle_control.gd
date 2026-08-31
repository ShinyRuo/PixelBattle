extends GutTest
## 战斗中点选与手动指定攻击目标（§02，M4-e）。
##
## ## 这个文件守的是「听话，但不会因为听话而发呆」
##
## 点名是一个**偏好**，不是一条命令。点中的那个可能被别人打死、
## 可能走出射程、可能压根还没进射程 —— 三种情况下自动规则都要接管。
## 「我点了他，结果这个忍者整场发呆」是玩家最不能接受的一种听话，
## 而它在代码里恰恰是最自然的写法（「有点名就打点名的，没有就自动」）。
##
## 另一半是**暂停时照样点得到**（§02 原话）。那不是顺手做的：
## 输入走 `_unhandled_input`，它不看 `_paused`，所以这条自动成立 ——
## 但只要有人把点击挪进 `_physics_process` 就会静默失效。

const BATTLE_SCENE := "res://scenes/battle.tscn"
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


# ── 点名真的生效 ────────────────────────────────────────────────


func test_a_named_target_gets_hit_first() -> void:
	# 自动规则打的是**最接近基地**的那个。点名之后该改打点的那个，
	# 否则这一整块功能在战斗里没有可观测的后果。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	assert_gt(sim.enemies().size(), 3, "这一波要有几个敌人才谈得上点名")
	var named: PBEnemy = sim.enemies()[sim.enemies().size() - 1]
	squad[0].forced_target = named.slot

	for _i: int in 3:
		sim.step()
	assert_lt(named.hp, named.max_hp, "被点名的那个该先挨打")
	assert_eq(sim.enemies()[0].hp, sim.enemies()[0].max_hp, "队头这时候还没被碰")


func test_the_shooter_falls_back_instead_of_standing_idle() -> void:
	# **本文件的正题。** 点名的那个够不着时必须自动接管 ——
	# 站着不打是最不能接受的一种听话。
	var squad: Array[PBAttacker] = [_shooter()]
	squad[0].reach = 0.2
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	# 点一个远在射程外的。
	squad[0].forced_target = sim.enemies()[sim.enemies().size() - 1].slot
	var reachable: PBEnemy = sim.enemies()[0]
	reachable.distance = 0.1

	for _i: int in 3:
		sim.step()
	assert_lt(reachable.hp, reachable.max_hp, "够得着的那个该照打不误")


func test_a_dead_target_hands_control_back() -> void:
	# 目标死了也要接管。**但点名本身不清掉** ——
	# 「死了就清」会让一个隔着射程点名的目标在他走进来之前就被清掉，
	# 而玩家看到的是「点了没用」。
	var squad: Array[PBAttacker] = [_shooter()]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	var named: PBEnemy = sim.enemies()[2]
	squad[0].forced_target = named.slot
	named.take_damage(named.max_hp)

	var before: int = sim.result().kills
	for _i: int in 20:
		sim.step()
	assert_gt(sim.result().kills, before, "目标没了就该接着打别人")
	assert_eq(squad[0].forced_target, named.slot, "但点名不该被悄悄清掉")


func test_every_wave_starts_back_on_automatic_targeting() -> void:
	# 点名是一波一份。留着的话，下一波那个下标指向的是**另一个敌人** ——
	# 玩家没点过，却有一个忍者在打一个奇怪的目标。
	var squad: Array[PBAttacker] = [_shooter()]
	squad[0].forced_target = 3
	PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	assert_eq(squad[0].forced_target, -1, "开波该回到自动选敌")


# ── 界面那一半 ──────────────────────────────────────────────────


func _in_battle() -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = true
	add_child_autofree(root)
	await wait_physics_frames(6)
	return root


func test_the_command_card_stays_up_during_the_battle() -> void:
	# §02 要求打起来之后照样点得到忍者。指令卡和信息栏因此从
	# 「准备阶段专属」那一档里分了出来，而槽位列、任务卡、羁绊带没有 ——
	# 它们全都占着战场那条道，而战斗中那条道是有人的。
	var root: Node2D = await _in_battle()
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "这时候该已经在打了")
	assert_true(root._command.visible, "指令卡该留着")
	assert_true(root._unit_info.visible, "信息栏该留着")
	assert_false(root._slots.visible, "槽位列该收掉 —— 它压在战场上")
	assert_false(root._quest.visible, "任务卡也是")


func test_clicking_a_ninja_selects_him_even_while_paused() -> void:
	# 输入走 `_unhandled_input`，它不看 `_paused` —— 所以这条自动成立。
	# 钉一条是因为把点击挪进 `_physics_process` 会让它**静默失效**。
	var root: Node2D = await _in_battle()
	root._paused = true
	var live: PBAttacker = root._battle.attackers()[0]
	var at := PBLayout.to_screen(live.pos, root._field())
	root._on_field_click(at)
	assert_eq(root._selection.kind, PBSelection.Kind.UNIT, "点中忍者该选中他")
	assert_eq(
		root._selection.unit_id, root._plan.deployed[live.slot].key(), "而且选中的是点到的那个"
	)


func test_aiming_takes_two_steps_and_can_be_taken_back() -> void:
	# 「按攻击、再点敌人」是 War3 那套，而且它让点错有一个可以后悔的中间态 ——
	# 一步到位的话，手一抖就把主力指到一个残血杂兵身上。
	var root: Node2D = await _in_battle()
	var live: PBAttacker = root._battle.attackers()[0]
	root._select(PBSelection.Kind.UNIT, root._plan.deployed[live.slot].key())

	root._on_command(PBCommandCard.CMD_ATTACK)
	assert_true(root._picker.aiming, "按一下进入指定状态")
	root._on_command(PBCommandCard.CMD_ATTACK)
	assert_false(root._picker.aiming, "再按一下退出 —— 那是这一格能后悔的地方")


func test_clicking_an_enemy_while_aiming_names_it() -> void:
	var root: Node2D = await _in_battle()
	var live: PBAttacker = root._battle.attackers()[0]
	root._select(PBSelection.Kind.UNIT, root._plan.deployed[live.slot].key())
	root._on_command(PBCommandCard.CMD_ATTACK)

	var target: PBEnemy = null
	for enemy: PBEnemy in root._battle.enemies():
		if enemy.is_active(root._battle.current_tick()):
			target = enemy
			break
	assert_not_null(target, "开打之后场上该有敌人")
	root._on_field_click(PBLayout.to_screen(target.pos(), root._field()))

	assert_eq(live.forced_target, target.slot, "点中的那个该被点名")
	assert_false(root._picker.aiming, "点完就该退出指定状态")

	root._on_command(PBCommandCard.CMD_CLEAR_TARGET)
	assert_eq(live.forced_target, -1, "「自动选敌」该把指挥权交回去")
