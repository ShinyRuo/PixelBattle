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
	named.take_damage(named.max_hp, sim.current_tick())

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
	# 「准备阶段专属」那一档里分了出来。
	#
	# **仓库和任务栏仍然收掉**：打起来之后改名单、派任务都没有意义
	# （M5-3 / M5-4）。**C/D 那一列 M6-k 起留着** —— 大本营的血条
	# 现在长在那张图上，而「基地还剩多少」恰恰是战斗中最要紧的一个数。
	var root: Node2D = await _in_battle()
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "这时候该已经在打了")
	assert_true(root._command.visible, "指令卡该留着")
	assert_true(root._unit_info.visible, "信息栏该留着")
	assert_true(root._slots.visible, "大本营那一块要留着 —— 血条长在它上面")
	assert_false(root._bay.visible, "仓库该收掉 —— 战斗中改名单没有意义")
	assert_false(root._quest.visible, "任务栏也该收掉")
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


# ── 忍术改成玩家自己放（§02，M5-9）────────────────────────────


func test_nothing_goes_off_by_itself_when_nobody_is_aiming() -> void:
	# **玩家报的那一条**：「开战后会自动放一个范围伤害，那是什么机制」。
	#
	# 大招原来走 [PBAimRules] 的**自动档**（§02 给手机端留的）。冷却在开波
	# 那一刻全员是好的，于是整队在第 1 tick 同时下达、0.5 秒后同时落地 ——
	# 而这也正是「单波只有 0.55 秒」那条已知配平问题的根源。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	var caster := _shooter()
	caster.dps = 0.0
	caster.attack_speed = 0.0
	var skill := PBSkill.new()
	skill.damage = 1.0e9
	skill.radius = 1.0
	caster.ultimate = PBSkillCast.new(skill)
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	for _i: int in 60:
		sim.step()
	assert_eq(sim.result().kills, 0, "没人下令就一发都不该出去")


func test_the_player_can_order_one_by_hand() -> void:
	# 而手动那条路必须真的打得出来 —— 否则上面那条只是「把功能关掉了」。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	var caster := _shooter()
	caster.dps = 0.0
	caster.attack_speed = 0.0
	var skill := PBSkill.new()
	skill.damage = 1.0e9
	skill.radius = 1.0
	skill.delay_ticks = 6
	caster.ultimate = PBSkillCast.new(skill)
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	sim.step()
	assert_true(sim.can_cast(caster), "开波冷却就是好的 —— 指令卡那一格该亮着")
	assert_true(sim.cast_skill(caster, Vector2(0.5, 0.0)), "点了落点就该下令")
	# **令攒着，下一个 tick 才出手**（M7-h，见 [PBSkillOrders]）——
	# 在那之前指令卡把那一格写成「已下令」，而不是靠冷却把它变灰。
	assert_eq(sim.order_of(caster), 0, "这一刻是攒在手上")
	sim.step()
	assert_false(sim.can_cast(caster), "出手之后进冷却，那一格才转灰")
	for _i: int in 10:
		sim.step()
	assert_gt(sim.result().kills, 0, "延迟走完之后它该真的落地")


func test_an_order_off_the_field_is_refused_instead_of_swallowing_the_cooldown() -> void:
	# 落点非法（[method PBSkillCast.is_spot] 不认）时**不能进冷却** ——
	# 吞掉一次冷却的表现是「我明明还没放，怎么就要等 20 秒」。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	var caster := _shooter()
	caster.ultimate = PBSkillCast.new(PBSkill.new())
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(9), 0.0, 0.0, _cfg, squad)
	sim.step()
	assert_false(sim.cast_skill(caster, PBSkillCast.NO_SPOT), "非法落点该被拒绝")
	assert_true(sim.can_cast(caster), "而且冷却一点都没动")


func test_the_two_click_to_aim_modes_are_mutually_exclusive() -> void:
	# 「攻击」和「忍术」都是两步操作，而两个同时开着的话，
	# 玩家那一下点击到底算哪个，代码里会由分支顺序偷偷决定。
	var picker := PBFieldPicker.new()
	picker.toggle(PBFieldPicker.Aim.TARGET)
	assert_true(picker.aiming, "按一下进入指定状态")
	picker.toggle(PBFieldPicker.Aim.SKILL)
	assert_false(picker.aiming, "按忍术就该退出指定状态")
	assert_eq(picker.aim_mode, PBFieldPicker.Aim.SKILL, "并且换成等落点")
	picker.toggle(PBFieldPicker.Aim.SKILL)
	assert_eq(picker.aim_mode, PBFieldPicker.Aim.OFF, "再按一次退出 —— 那是能后悔的地方")


# ── 那一下点击真的走得到 `_unhandled_input`（M5-10）────────────


func test_a_real_click_on_the_field_actually_arrives() -> void:
	# **上面那条从来没测到这一段。** 它直接调 `_on_field_click`，
	# 于是「点击到底有没有走到那个函数」是一片空白 —— 而它没有。
	#
	# 引擎只要在鼠标下面找到**任何一个非 IGNORE 的 [Control]**，
	# 那一下点击就算被 GUI 处理掉了，`_unhandled_input` 收不到。
	# 而 [ColorRect] 默认就是 `MOUSE_FILTER_STOP`：`Background`（盖满全屏）、
	# `Lane`（战场那条道）、以及 [PBAllyPool] 画忍者用的那些方块，
	# 三层叠在一起把整块战场变成了一个吃点击的黑洞。
	#
	# 现象是「点谁都没反应」，看起来像点选功能没做 ——
	# 而代码里那一整套命中判定写得好好的，单元测试也全绿。
	# **场景要装进自己的 [SubViewport] 里**：GUT 自己的面板是一块盖满屏幕的
	# [Control]，直接往主视口推事件的话，先吃掉它的是测试框架的界面。
	var box := SubViewport.new()
	box.size = Vector2i(640, 360)
	add_child_autofree(box)
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = true
	box.add_child(root)
	await wait_physics_frames(8)
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "这时候该已经在打了")

	var live: PBAttacker = root._battle.attackers()[0]
	var at := PBLayout.to_screen(live.pos, root._field())
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	box.push_input(press, true)
	await wait_physics_frames(2)

	assert_eq(root._selection.kind, PBSelection.Kind.UNIT, "真点一下就该选中他")
	assert_eq(root._selection.unit_id, root._plan.deployed[live.slot].key(), "而且是点到的那个")


func test_nothing_on_the_battlefield_swallows_a_click() -> void:
	# 上一条是「结果对不对」，这一条是**根因本身**：战场那块地方
	# 不许站着任何一个会吃掉点击的 [Control]。
	#
	# 分成两条是因为上一条抓得到、却说不出是谁干的 —— 而这一类 bug
	# 每加一块装饰性的 [ColorRect] 就会重来一次
	# （`ColorRect.new()` 默认 `MOUSE_FILTER_STOP`，很难想到）。
	var root: Node2D = await _in_battle()
	var field := PBLayout.B_FIELD
	var guilty: Array[String] = []
	for node: Node in root.find_children("", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		# `PASS` 是可以的：它自己收得到（拖放靠它），也照样往下传。
		if control.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		if control.get_global_rect().intersects(field):
			guilty.append("%s(%s)" % [control.name, control.get_class()])
	assert_eq(guilty, [] as Array[String], "战场上不许有吃点击的控件：%s" % ", ".join(guilty))


# ── 右键收回那两步（M5-11）────────────────────────────────────
#
# 「那根线指着谁」搬去了 `test_aim_lines.gd` —— 这个文件破了 gdlint 的
# 20 个公开方法上限，而那一组恰好有一条说得清的边界。


func test_right_click_takes_back_the_two_step_command() -> void:
	# 两步操作的第一步按下去之后，玩家需要一条**不用把手挪回指令卡**的退路。
	# `Esc` 是第二条路，但按键和鼠标不在一只手上。
	var root: Node2D = await _in_battle()
	root._select(PBSelection.Kind.UNIT, root._plan.deployed[0].key())
	# 忍术那一格 M7-h 删了，所以先给他配一个真技能 —— 没配技能的忍者
	# 现在只会普攻，指令卡上一格都没有。
	_lend_skill(root, 0)
	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.SKILL, "先进入选落点状态")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	root._unhandled_input(press)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.OFF, "右键该取消掉")


func test_a_right_click_never_casts_or_names_anything() -> void:
	# 右键**只取消**。顺手把它当成「确认」的话，玩家想反悔那一下
	# 反而把忍术扔在了鼠标底下 —— 而那正是他要躲开的结果。
	var root: Node2D = await _in_battle()
	var live: PBAttacker = root._battle.attackers()[0]
	root._select(PBSelection.Kind.UNIT, root._plan.deployed[live.slot].key())
	_lend_skill(root, 0)
	root._on_command(PBCommandCard.CMD_SKILL_1)
	var ready: bool = root._battle.can_cast(live, 1)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = PBLayout.to_screen(live.pos, root._field())
	root._unhandled_input(press)
	assert_eq(root._battle.can_cast(live, 1), ready, "冷却一点都不该动")
	assert_eq(root._battle.order_of(live), -1, "也不该顺手下一条令")


## 给场上第 [param slot] 个忍者临时配一格地面技能，返回那一格的状态对象。
##
## 忍术那一格 M7-h 从指令卡上删了（见 [constant PBCommandCard.CMD_ULTIMATE]），
## 而两步操作本身没变 —— 只是现在必须有一个**真配了技能**的人才按得着。
func _lend_skill(root: Node2D, slot: int) -> PBSkillCast:
	var skill := PBSkill.new()
	skill.id = &"probe"
	skill.radius = 1.0
	skill.cooldown_ticks = 100
	var cast := PBSkillCast.new(skill)
	root._battle.attackers()[slot].skills.append(cast)
	root._refresh_battle_panels()
	return cast
