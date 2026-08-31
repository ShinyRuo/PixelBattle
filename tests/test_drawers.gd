extends GutTest
## 四块抽屉的接线（§02 的战场直接操作，M3.5-f）。
##
## ## 为什么和 `test_battle_view.gd` 分开
##
## 那个文件守的是「这一局跑不跑得起来」：定帧、倍速、确定性、
## 渲染层不回写 sim。抽屉守的是**另一件事** —— 玩家点下去会发生什么，
## 以及哪些操作是不可逆的（三选一掏了钱、选尾兽定终身）。
##
## 直接的触发是 gdlint 报那个文件超过 20 个公开方法。
## 那条上限「超了不是错，是该拆了的信号」，这次它又指对了地方。

const BATTLE_SCENE := "res://scenes/battle.tscn"

## 固定种子，让每条用例都跑同一局。
const FIXED_SEED: int = 20260827


## 停在准备阶段的一局 —— 抽屉只在那一段里开得起来。
func _prepared() -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	add_child_autofree(root)
	root._enter_prepare()
	return root


func test_only_one_drawer_is_open_at_a_time() -> void:
	# 四块抽屉共用战场那条道（[constant PBDrawer.BAND]）。各自抢显示权的话，
	# 「点了忍者弹装备栏、但仓库还开着」这种叠着两块的局面迟早出现 ——
	# 不报错，只是下面那块永远点不到。
	var root := _prepared()
	var drawers: Array = [root._offer, root._equip, root._stash, root._beasts]
	for drawer in drawers:
		assert_false(drawer.visible, "开局四块抽屉都该是收起来的")
	for drawer in drawers:
		root._toggle_drawer(drawer, true)
		var open_count: int = 0
		for other in drawers:
			if other.visible:
				open_count += 1
		assert_eq(open_count, 1, "同一时刻只该开着一块")


func test_escape_folds_the_drawer_before_clearing_the_selection() -> void:
	# 一下按键做两件事会让人分不清刚才关掉的是哪一个。
	var root := _prepared()
	root._state.gold = 9999
	root._on_command(&"gacha")
	root._on_offer_picked(0)
	var unit: PBUnit = root._state.roster.values()[0]
	root._on_slot_picked(PBSelection.Kind.UNIT, unit.key())
	# **选中不再顺手弹装备栏**（M4-f）：战场上现在站着人、还能拖动摆位，
	# 每选一个人就弹一块盖住半个战场的抽屉，等于把最高频的那个操作
	# 挡在自己的反馈前面。装备栏改成指令卡上点「装备」才开。
	root._on_command(PBCommandCard.CMD_EQUIP)
	assert_true(root._equip.visible, "点「装备」该把装备栏弹出来")
	assert_true(root._close_open_drawer(), "第一下 Esc 收抽屉")
	assert_eq(root._selection.kind, PBSelection.Kind.UNIT, "第一下不该顺手把选中也清了")
	assert_false(root._close_open_drawer(), "没有开着的抽屉时该让位给取消选中")


func test_starting_a_wave_is_blocked_while_an_offer_is_pending() -> void:
	# **钱在摆牌那一刻就扣了。** 开打会把那一组连同那笔钱一起冲掉，
	# 而账面上只表现为「金币怎么少了 300」。
	var root := _prepared()
	root._state.gold = 9999
	root._on_command(&"gacha")
	assert_eq(root._state.pending_offer.size(), 3, "先摆出三张")
	root._finish_prepare()
	assert_eq(root._phase, PBBattleView.Phase.PREPARE, "还没挑就不该开打")
	assert_true(root._offer.visible, "而且要把那块抽屉推到玩家眼前")
	root._on_offer_picked(1)
	root._finish_prepare()
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "挑完就该放行")


func test_the_warehouse_is_where_a_benched_ninja_gets_picked() -> void:
	# 没有仓库的话「派上场」是条点不到的指令：屏幕上只画了出战席和出任务，
	# 待命台与仓库里的人一个都看不见。
	var root := _prepared()
	root._state.gold = 999999
	for _i: int in 6:
		root._on_command(&"gacha")
		root._on_offer_picked(0)
	root._toggle_drawer(root._stash, true)
	assert_true(root._stash.visible, "仓库该开得起来")
	var picked: PBUnit = root._state.roster.values()[root._state.roster.size() - 1]
	root._stash.unit_picked.emit(picked.key())
	assert_eq(root._selection.unit_id, picked.key(), "点仓库里的卡应该选中他")
	assert_true(root._stash.visible, "从仓库里点人时仓库要留着 —— 他还在翻")


func test_equipping_goes_through_the_shared_primitive() -> void:
	# 界面绝不自己动 `state.equipped`，和花钱、排名单同一个理由。
	var root := _prepared()
	root._state.gold = 999999
	root._on_command(&"gacha")
	root._on_offer_picked(0)
	var unit: PBUnit = root._state.roster.values()[0]
	root._selection.set_to(PBSelection.Kind.UNIT, unit.key())
	root._on_equip_changed(&"blunt_blade", true)
	assert_eq(
		PBEquipRules.pinned_of(root._state.equipped, unit.key()).size(), 1, "挂上该记进状态"
	)
	root._on_equip_changed(&"blunt_blade", false)
	assert_false(root._state.equipped.has(unit.key()), "卸光了该把条目一起去掉")


func test_choosing_a_beast_from_the_drawer_locks_it_in() -> void:
	var root := _prepared()
	root._toggle_drawer(root._beasts, true)
	var first: StringName = root._cfg.beasts.ids()[0]
	root._on_beast_chosen(first)
	assert_eq(root._state.beast_id, first, "选了就该定下来")
	assert_false(root._beasts.visible, "定完这块抽屉就没有内容了，该收起来")


func test_the_battlefield_actually_shows_your_own_ninjas() -> void:
	# **开打之后场上只有敌人**是 M0 到 M3.5-f 一直存在的缺口：整队标量 DPS
	# 时代「谁站在哪」没有答案，所以画不出来是诚实的；M3-a 拆成一组
	# [PBAttacker] 之后那个答案有了，但一直没有出口。
	#
	# 射程、站位、防挤、敌人还手 —— M3-a 到 M3.5-c 做的全部内容
	# 只有在这里才看得见。
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = true
	add_child_autofree(root)
	await wait_physics_frames(30)
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "这时候该已经在打了")
	assert_gt(root._plan.deployed.size(), 0, "自动模式下该有人上场")

	var shown: int = 0
	for rect: ColorRect in (root.get_node("Deployed") as PBAllyPool).get_children():
		if rect.visible:
			shown += 1
	assert_gt(shown, 0, "战斗中场上应该画得出己方忍者")


func test_your_ninjas_are_gone_again_once_the_wave_has_not_started() -> void:
	# 准备阶段没有战场（敌人要等 `_finish_prepare` 才生成），
	# 这时候还画着上一波的方块就成了「战场上有人但打不起来」。
	var root := _prepared()
	for rect: ColorRect in (root.get_node("Deployed") as PBAllyPool).get_children():
		assert_false(rect.visible, "准备阶段不该有己方单位画在战场上")
