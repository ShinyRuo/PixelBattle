extends GutTest
## 操作层：指令卡上那几格技能，以及按下去之后战场上的那一下点击（M7-e）。
##
## ## 这个文件守的是「一把尺子」
##
## 同一件事在三处出现过：**按钮亮不亮**、**按下去进什么状态**、
## **那之后点战场是什么意思**。M7-e 之前这三处各判各的
## （`Aim.ULTIMATE` 一个枚举值 + 一处 `can_cast` + 一处落点分支），
## 而技能一多就必然分叉 —— 表现是「第二个技能的按钮点了放出第一个」，
## 或者「点了队友却在地上炸了一发」，两条都不报错。
##
## 现在三处认的都是 [method PBSkillRules.cast_at] 的下标，
## 而「这一下点击是什么意思」一律读 [member PBSkill.target]。
##
## ## 那一下点击要**真推事件**
##
## 直接调 `_on_field_click` 测不到「点击有没有走到那个函数」——
## M5-10 为这件事付过三个里程碑的代价。场景因此装进自己的 [SubViewport]：
## GUT 的面板是一块盖满屏幕的 [Control]，往主视口推的话先被它吃掉。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const FIXED_SEED: int = 20260906

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


func _shooter() -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = 100.0
	out.attack_speed = 1.0
	out.pos = Vector2.ZERO
	out.reach = _cfg.field_diagonal()
	out.max_hp = 1.0e9
	out.hp = out.max_hp
	return out


## 一份技能定义。[param tier] 是它点什么（[enum PBSkill.Target]）。
func _skill(tier: int, damage: float = 0.0) -> PBSkill:
	var out := PBSkill.new()
	out.id = &"probe"
	out.target = tier
	out.affects = (
		PBSkill.Party.ALLIES if tier == PBSkill.Target.ALLY else PBSkill.Party.ENEMIES
	)
	out.damage = damage
	out.radius = 1.0
	out.cooldown_ticks = 100
	return out


## 给 [param live] 的技能表加一格，返回那一格的状态对象。
func _give(live: PBAttacker, tier: int, damage: float = 0.0) -> PBSkillCast:
	var cast := PBSkillCast.new(_skill(tier, damage))
	live.skills.append(cast)
	return cast


func _in_battle(box: SubViewport = null) -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = true
	if box == null:
		add_child_autofree(root)
	else:
		box.add_child(root)
	await wait_physics_frames(8)
	return root


## 选中场上第一个忍者，返回他。
func _pick_first(root: Node2D) -> PBAttacker:
	var live: PBAttacker = root._battle.attackers()[0]
	root._select(PBSelection.Kind.UNIT, root._plan.deployed[live.slot].key())
	return live


# ── 格子：按钮亮 ⇔ 放得出 ──────────────────────────────────────


func test_a_ninja_without_a_skill_has_no_cell_to_press() -> void:
	# **M7-h 把忍术那一格删了**（玩家定的）：大招谁都有、谁都一样，
	# 那一格因此不表达任何角色差异。没配技能的忍者现在只会普攻。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	assert_eq(root._command.command_at(2), &"", "没配技能就一格都不摆")
	assert_eq(root._command.command_at(3), &"", "下面那一行也是空的")

	_give(live, PBSkill.Target.GROUND)
	root._refresh_battle_panels()
	assert_eq(
		root._command.command_at(2), PBCommandCard.CMD_SKILL_1, "配了才有，而且顶上忍术让出的位置"
	)
	assert_eq(root._command.command_at(3), &"", "只配了一个就只摆一格")

	_give(live, PBSkill.Target.GROUND)
	root._refresh_battle_panels()
	assert_eq(root._command.command_at(3), PBCommandCard.CMD_SKILL_2, "第二个排在它后面")


func test_the_ultimate_has_no_back_door_either() -> void:
	# 按钮没了，入口也得没 —— 留着的话 `screenshot.gd --aim` 就是第二个入口，
	# 而屏幕上没有任何地方说得出「刚才那一发是怎么放出去的」。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	root._on_command(PBCommandCard.CMD_ULTIMATE)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.OFF, "大招那一格按不动")
	assert_eq(root._battle.order_of(live), -1, "也不该攒下一条指令")


func test_the_button_is_lit_exactly_when_the_skill_can_be_cast() -> void:
	# **本文件的正题，也是 M7-e 的验收。** 按钮的亮灰和真正下达时的第一道门
	# 必须读同一个函数（[method PBSkillRules.can_cast]）——
	# 各写一份的话「按钮亮着点了没反应」迟早出现，而玩家只会觉得
	# 这一格时灵时不灵。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	var cast := _give(live, PBSkill.Target.GROUND)
	var tick: int = root._battle.current_tick()

	root._refresh_battle_panels()
	assert_true(root._battle.can_cast(live, 1), "前提：这一格现在放得出")
	assert_true(root._command.enabled_at(2), "放得出就该亮着")

	# 冷却中。
	cast.ready_at = tick + 60
	root._refresh_battle_panels()
	assert_false(root._battle.can_cast(live, 1), "冷却没转好")
	assert_false(root._command.enabled_at(2), "那就该是灰的，而不是点了没反应")

	# 蓝不够。
	cast.ready_at = tick
	cast.skill.mp_cost = live.max_mp + 1.0
	live.max_mp = 100.0
	live.mp = 0.0
	root._refresh_battle_panels()
	assert_false(root._battle.can_cast(live, 1), "蓝不够也放不出")
	assert_false(root._command.enabled_at(2), "两道门槛共用一份，按钮跟着灰")


func test_a_cell_on_cooldown_still_says_how_long() -> void:
	# 灰着的那一格照样写秒数：「还要多久」正是他这时候唯一想知道的事。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	var cast := _give(live, PBSkill.Target.GROUND)
	cast.ready_at = root._battle.current_tick() + 2 * _cfg.tick_rate
	root._refresh_battle_panels()
	assert_string_contains(root._command._slots[2].text, "秒", "灰格子上要写还差几秒")


# ── 按下去进什么状态 ────────────────────────────────────────────


func test_pressing_a_cell_aims_that_cell_and_only_that_cell() -> void:
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	_give(live, PBSkill.Target.GROUND)

	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.SKILL, "进入等点击的状态")
	assert_eq(root._picker.aim_skill, 1, "而且记着是第 1 格，不是大招那一格")


func test_pressing_another_cell_switches_instead_of_backing_out() -> void:
	# 按了「技能 1」之后再按「技能 2」该是**换一格**，不是退出 ——
	# 否则玩家要按两下才换得了格子。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	_give(live, PBSkill.Target.GROUND)
	_give(live, PBSkill.Target.GROUND)

	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._picker.aim_skill, 1, "先在第 1 格")
	root._on_command(PBCommandCard.CMD_SKILL_2)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.SKILL, "还在等点击")
	assert_eq(root._picker.aim_skill, 2, "只是换了一格")
	root._on_command(PBCommandCard.CMD_SKILL_2)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.OFF, "同一格再按一次才退出")
	assert_eq(root._picker.aim_skill, -1, "**两个字段一起清** —— 留一半是个说不清的状态")


func test_a_skill_that_needs_no_target_never_waits_for_a_click() -> void:
	# 让它先进一个「等你点」的状态，等于凭空多要一下点击 ——
	# 而那两步存在的理由是「点错了有一个能后悔的中间态」，
	# 一个没有目标可点错的技能没有这个问题。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	var cast := _give(live, PBSkill.Target.NONE)

	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.OFF, "不该进等点击的状态")
	# **下的令攒着，下一个 tick 才真的放**（M7-h）—— 见 [PBSkillOrders]。
	assert_eq(root._battle.order_of(live), 1, "而是当场就把令下了")
	assert_false(cast.is_pending(), "但还没放出去 —— 那是下一个 tick 的事")


# ── 那一下点击是什么意思 ────────────────────────────────────────


func test_what_the_next_click_means_comes_from_the_skill() -> void:
	# **[enum PBFieldPicker.Aim] 里只有一个 `SKILL`**：点地面还是点队友
	# 由 [member PBSkill.target] 说。在状态机里再分一次档就是第二份真相，
	# 而它和技能表可以分叉 —— 表现是「点了队友却在地上炸了一发」。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	var cast := _give(live, PBSkill.Target.ALLY)
	# 场上只有一个人时就点他自己 —— **自己是一个合法的锁定目标**
	# （§4.2 那句「玩家不知道能不能点自己」问的正是这件事），
	# 而第一波的出战席本来就可能只有一个人。
	var mate: PBAttacker = live
	for other: PBAttacker in root._battle.attackers():
		if other != live and other.slot >= 0 and other.is_targetable():
			mate = other
			break

	root._on_command(PBCommandCard.CMD_SKILL_1)
	root._on_field_click(PBLayout.to_screen(mate.pos, root._field()))
	assert_eq(root._battle.order_of(live), 1, "点中队友就该下令")
	assert_eq(root._battle.orders().target_of(0), mate.slot, "锁的是点中的那一个")
	assert_eq(
		root._battle.orders().spot_of(0), PBSkillCast.NO_SPOT, "锁定档没有落点 —— 别顺手记一个"
	)
	assert_false(cast.is_pending(), "而且这一刻还没放出去")


func test_the_ground_tier_still_takes_any_point() -> void:
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	var cast := _give(live, PBSkill.Target.GROUND)

	root._on_command(PBCommandCard.CMD_SKILL_1)
	root._on_field_click(PBLayout.to_screen(Vector2(0.5, 0.0), root._field()))
	assert_eq(root._battle.order_of(live), 1, "地面档哪个点都算，不用点中谁")
	assert_true(
		PBSkillCast.is_spot(root._battle.orders().spot_of(0)), "记下来的是一个真落点"
	)
	assert_eq(root._battle.orders().target_of(0), -1, "地面档不锁人")
	root._battle.step()
	assert_gt(cast.ready_at, 0, "下一个 tick 就放出去了，冷却从这一发算起")


func test_a_real_click_casts_the_waiting_skill() -> void:
	# 直接调 `_on_field_click` 测不到「点击有没有走到那个函数」（M5-10）。
	var box := SubViewport.new()
	box.size = Vector2i(640, 360)
	add_child_autofree(box)
	var root: Node2D = await _in_battle(box)
	var live := _pick_first(root)
	var cast := _give(live, PBSkill.Target.GROUND)
	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "前提：这时候在打")
	assert_eq(root._picker.aim_skill, 1, "前提：推事件之前正等着这一格的点击")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	# 点在施法者自己站的地方 —— 那一定落在战场框里。地面档哪个点都算，
	# 所以这一条量的是**事件走没走到**，不是落点挑得对不对。
	press.position = PBLayout.to_screen(live.pos, root._field())
	box.push_input(press, true)
	await wait_physics_frames(2)
	assert_eq(root._picker.aim_mode, PBFieldPicker.Aim.OFF, "那一下点击要真的走到")
	# **断言的是「进了冷却」，不是「还在飞」**：这一发没有施法延迟，
	# 而等的这两帧足够跨过一个 tick —— 它可能已经落地了。
	# 「还在飞」在这里是个会随帧数漂的性质，「放过了」不是。
	assert_false(root._battle.can_cast(live, 1), "真点一下就该把这一格放出去，然后转灰")
	assert_gt(cast.ready_at, 0, "冷却从这一发算起")


# ── 暂停下的指令（M7-h） ────────────────────────────────────────


func test_pressing_the_cell_again_takes_the_order_back() -> void:
	# 反悔是暂停操作的一半意义：暂停里下的令还没生效，
	# 而在这之前玩家点下去那一刻蓝就已经扣了。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	_give(live, PBSkill.Target.NONE)

	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._battle.order_of(live), 1, "前提：令下了")
	root._on_command(PBCommandCard.CMD_SKILL_1)
	assert_eq(root._battle.order_of(live), -1, "再按一次就是收回")


func test_the_card_says_so_while_the_order_is_waiting() -> void:
	# 暂停下玩家看不出「我刚才那一下有没有生效」—— 画面一动不动，
	# 而技能还没放出去。那一格必须自己说出来。
	var root: Node2D = await _in_battle()
	var live := _pick_first(root)
	_give(live, PBSkill.Target.NONE)

	root._on_command(PBCommandCard.CMD_SKILL_1)
	root._refresh_battle_panels()
	assert_string_contains(root._command._slots[2].text, "已下令", "那一格要写出来")
	assert_true(root._command.enabled_at(2), "而且照样点得动 —— 再按一次是收回")


func test_an_ordered_ninja_is_marked_on_the_field() -> void:
	# 指令卡只显示选中的那一个，而暂停下玩家会连着给好几个人下令 ——
	# 给第 2 个人下令时，第 1 个人下没下过令在屏幕上必须还看得见。
	var one := _shooter()
	var two := _shooter()
	one.slot = 0
	two.slot = 1
	two.pos = Vector2(0.4, 0.0)
	var squad: Array[PBAttacker] = [one, two]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var lines := PBAimLines.new()
	add_child_autofree(lines)
	var picker := PBFieldPicker.new()
	_give(one, PBSkill.Target.ALLY)
	sim.cast_skill_on(one, two, 1)

	lines.sync(sim, _field(), null, picker, Vector2.ZERO, false)
	assert_eq(lines._orders.size(), 2, "一条指令画一对端点（施法者 → 目标）")
	assert_eq(lines._order_tiers[0], PBSkill.Target.ALLY, "线的颜色按档位挑")
	assert_eq(lines._orders[1], PBLayout.to_screen(two.pos, _field()), "终点是他要治的那个")

	sim.cancel_order(one)
	lines.sync(sim, _field(), null, picker, Vector2.ZERO, false)
	assert_eq(lines._orders.size(), 0, "收回之后那一层立刻没了")


# ── sim 那一侧：每一格都要走到 ──────────────────────────────────


func test_every_cell_lands_not_just_the_ultimate() -> void:
	# 落地那一趟只扫大招那一格的话，玩家手放的技能永远落不了地 ——
	# 而按钮那边看起来一切正常（进了冷却、格子转灰）。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	var caster := _shooter()
	caster.dps = 0.0
	caster.attack_speed = 0.0
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var cast := _give(caster, PBSkill.Target.NONE, 1.0e9)
	cast.reset()
	sim.step()

	assert_true(sim.cast_skill_now(caster, 1), "第 1 格该放得出")
	sim.step()
	assert_false(cast.is_pending(), "它该真的落地了")
	assert_gt(sim.result().kills, 0, "而且真的打死了人")


func test_a_new_wave_clears_the_cooldown_of_every_cell() -> void:
	# 漏清一格的表现是「某个技能开波就是灰的」，而它不报错。
	var caster := _shooter()
	var squad: Array[PBAttacker] = [caster]
	PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var cast := _give(caster, PBSkill.Target.GROUND)
	cast.ready_at = 999
	cast.cast(Vector2(0.5, 0.0), 0)

	PBBattleSim.new(_wave(5), 0.0, 0.0, _cfg, squad)
	assert_eq(cast.ready_at, 0, "开波冷却该是清的")
	assert_false(cast.is_pending(), "上一场没落地的那一发也不许漏过来")


func test_a_clone_carries_its_own_copy_of_every_cell() -> void:
	# 悬崖二分会 [method PBAttacker.clone] 出几十份反复改伤害
	# （[method PBValuation._leaks_at]），共享同一份定义的话那一下改动
	# 会污染正在真正战斗的那一份，而它不报错。
	var caster := _shooter()
	var cast := _give(caster, PBSkill.Target.GROUND, 100.0)
	var copy := caster.clone()
	assert_eq(copy.skills.size(), 1, "复制品该有同样多的格子")

	copy.skills[0].skill.damage = 1.0
	assert_eq(cast.skill.damage, 100.0, "改复制品不许碰到原件")


# ── 三条虚线与两种脚下环 ────────────────────────────────────────


func test_the_caster_is_highlighted_in_every_tier() -> void:
	# 高亮的是**正在施法的那个忍者**，地面档也要 —— 它解决的是
	# 「我按了技能之后视线回到战场，忘了是谁在放」，而地面档
	# 压根没有候选目标可高亮。
	var caster := _shooter()
	caster.pos = Vector2(0.3, 0.0)
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var lines := PBAimLines.new()
	add_child_autofree(lines)
	var picker := PBFieldPicker.new()
	_give(caster, PBSkill.Target.GROUND)
	picker.toggle(PBFieldPicker.Aim.SKILL, 1)

	lines.sync(sim, _field(), caster, picker, Vector2(10.0, 10.0), false)
	assert_ne(lines._from, Vector2.ZERO, "施法者那一圈该有位置")
	assert_eq(lines._tier, PBSkill.Target.GROUND, "画哪条线读的是技能自己的档位")
	assert_eq(lines._candidates.size(), 0, "地面档没有候选目标")


func test_candidate_rings_only_show_for_the_locked_tier() -> void:
	# 不画的话玩家不知道能不能点已经倒下的人、能不能点自己。
	var one := _shooter()
	var two := _shooter()
	one.slot = 0
	two.slot = 1
	two.pos = Vector2(0.4, 0.0)
	var squad: Array[PBAttacker] = [one, two]
	var sim := PBBattleSim.new(_wave(4), 0.0, 0.0, _cfg, squad)
	var lines := PBAimLines.new()
	add_child_autofree(lines)
	var picker := PBFieldPicker.new()
	_give(one, PBSkill.Target.ALLY)
	picker.toggle(PBFieldPicker.Aim.SKILL, 1)

	lines.sync(sim, _field(), one, picker, Vector2(10.0, 10.0), false)
	assert_eq(lines._candidates.size(), 2, "两个活人都该画上一圈")

	# 倒下的那个立刻从候选里消失 —— 判据和落地时那一道门读同一份。
	two.alive = false
	lines.sync(sim, _field(), one, picker, Vector2(11.0, 11.0), false)
	assert_eq(lines._candidates.size(), 1, "死人点不中，就不该画成可点的样子")


func _field() -> Vector2:
	return Vector2(_cfg.field_length, _cfg.field_height)
