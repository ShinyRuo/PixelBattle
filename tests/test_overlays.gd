extends GutTest
## 盖在画面上的那两层模态，以及底栏几块常驻面板的接线。
## §02 的战场直接操作，M3.5-f；M5-6 抽屉全部退场。
##
## ## 为什么和 `test_battle_view.gd` 分开
##
## 那个文件守的是「这一局跑不跑得起来」：定帧、倍速、确定性、
## 渲染层不回写 sim。这里守的是**另一件事** —— 玩家点下去会发生什么，
## 以及哪些操作是不可逆的（三选一掏了钱、选尾兽定终身）。
##
## 直接的触发是 gdlint 报那个文件超过 20 个公开方法。
## 那条上限「超了不是错，是该拆了的信号」，这次它又指对了地方。
##
## ## 文件名从 `test_drawers` 改过来（M5-6）
##
## 四块抽屉一块都不剩了：仓库、忍具、装备栏各自变成底栏的常驻面板
## （M5-3 / M5-5），三选一和选尾兽变成模态（[PBModal]）。
## 留着旧名字的话，下一个来读这个文件的人会先去找一个不存在的类。

const BATTLE_SCENE := "res://scenes/battle.tscn"

## 固定种子，让每条用例都跑同一局。
const FIXED_SEED: int = 20260827


## 停在准备阶段的一局 —— 这两层只在那一段里摊得开。
func _prepared() -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	add_child_autofree(root)
	root._enter_prepare()
	return root


func test_only_one_modal_is_open_at_a_time() -> void:
	# 两层都是「不选就不能继续」。同时摊着两层的话，上面那一层挡住的
	# 是一个玩家已经欠下的回答 —— 不报错，只是下面那层永远点不到。
	var root := _prepared()
	var modals: Array = [root._offer, root._beasts]
	for modal in modals:
		assert_false(modal.visible, "开局两层都该是收着的")
	for modal in modals:
		root._open_modal(modal)
		var open_count: int = 0
		for other in modals:
			if other.visible:
				open_count += 1
		assert_eq(open_count, 1, "同一时刻只该摊着一层")


func test_the_modal_swallows_clicks_meant_for_the_panels_behind_it() -> void:
	# **这就是「模态」这个词的全部内容。** 抽屉那一版底下那些按钮照样能点：
	# 三选一摊着的时候玩家能去点仓库、能把人拖上场，而那些操作在这一刻
	# 全都做得成但没意义 —— 他还欠着一个回答。
	var root := _prepared()
	root._open_modal(root._beasts)
	assert_eq(
		root._beasts.mouse_filter, Control.MOUSE_FILTER_STOP, "弹层这一层必须自己吃掉鼠标"
	)
	root._beasts.close()
	assert_false(root._beasts.visible, "收起来之后它一点都不该再挡路")


func test_the_offer_has_no_way_out_but_picking_one() -> void:
	# **钱在摆牌那一刻就扣了。** 给一个「关掉」的出口等于给一个
	# 把 300 金币变没的出口，而账面上只表现为「金币怎么少了」。
	var root := _prepared()
	root._state.gold = 9999
	root._on_command(&"gacha")
	assert_true(root._offer.visible, "掏了钱就该把三张推到眼前")
	assert_false(root._offer._closable(), "三选一不给关闭按钮")
	assert_false(root._close_modal(), "Esc 也收不掉它")
	assert_true(root._offer.visible, "按完 Esc 还得在")


func test_escape_folds_the_modal_before_clearing_the_selection() -> void:
	# 一下按键做两件事会让人分不清刚才关掉的是哪一个。
	var root := _prepared()
	root._state.gold = 9999
	root._on_command(&"gacha")
	root._on_offer_picked(0)
	var unit: PBUnit = root._state.roster.values()[0]
	root._on_slot_picked(PBSelection.Kind.UNIT, unit.key())
	root._on_command(PBCommandCard.CMD_BEAST_PICK)
	assert_true(root._beasts.visible, "点「选尾兽」该把那一层摊开")
	assert_true(root._close_modal(), "第一下 Esc 收弹层")
	assert_eq(root._selection.kind, PBSelection.Kind.UNIT, "第一下不该顺手把选中也清了")
	assert_false(root._close_modal(), "没有摊着的弹层时该让位给取消选中")


func test_starting_a_wave_is_blocked_while_an_offer_is_pending() -> void:
	# **钱在摆牌那一刻就扣了。** 开打会把那一组连同那笔钱一起冲掉，
	# 而账面上只表现为「金币怎么少了 300」。
	var root := _prepared()
	root._state.gold = 9999
	root._on_command(&"gacha")
	assert_eq(root._state.pending_offer.size(), 3, "先摆出三张")
	root._finish_prepare()
	assert_eq(root._phase, PBBattleView.Phase.PREPARE, "还没挑就不该开打")
	assert_true(root._offer.visible, "而且要把那一层推到玩家眼前")
	root._on_offer_picked(1)
	root._finish_prepare()
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "挑完就该放行")


func test_the_warehouse_is_where_a_benched_ninja_gets_picked() -> void:
	# 没有仓库的话「派上场」是条点不到的指令：屏幕上只画了在场的和出任务的，
	# 仓库里的人一个都看不见。
	#
	# **M5-3 起它是常驻面板**，不用先按一个键才点得到 ——
	# 这条断言跟着改成「准备阶段它本来就在」。
	var root := _prepared()
	root._state.gold = 999999
	for _i: int in 6:
		root._on_command(&"gacha")
		root._on_offer_picked(0)
	assert_true(root._bay.visible, "准备阶段仓库该一直在")
	var picked: PBUnit = root._state.roster.values()[root._state.roster.size() - 1]
	root._bay.unit_picked.emit(picked.key())
	assert_eq(root._selection.unit_id, picked.key(), "点仓库里的卡应该选中他")
	assert_true(root._bay.visible, "选中一个人不该把仓库收走 —— 他还在翻")


func test_the_warehouse_only_holds_the_ones_who_are_neither_fighting_nor_away() -> void:
	# **一个忍者只在一处出现。** 在场的画在战场上、出任务的在任务栏那 4 个槽里，
	# 剩下的才在仓库里。同时出现在两处的话，玩家会以为自己有两个他 ——
	# 那正是抽屉那一版靠三色底条在回避的问题。
	var root := _prepared()
	root._state.gold = 999999
	for _i: int in 6:
		root._on_command(&"gacha")
		root._on_offer_picked(0)
	var away: Array[PBUnit] = root._dispatch_preview()
	var deployed: Array[PBUnit] = root._fighting_now(away)
	assert_gt(deployed.size(), 0, "这一波该有人上场，否则测不到「减掉」那一步")

	var idle := PBRosterBay.idle_units(root._state, deployed, away)
	assert_eq(
		idle.size() + deployed.size() + away.size(),
		root._state.roster.size(),
		"三档加起来必须正好是全部的卡，不多不少"
	)
	for unit: PBUnit in idle:
		assert_false(deployed.has(unit), "在场的人不该同时躺在仓库里")
		assert_false(away.has(unit), "出任务的人不该同时躺在仓库里")


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


func test_picking_a_beast_takes_two_steps() -> void:
	# **手机没有悬停**（§01 要双端）。抽屉那一版是「停上去看详情、
	# 点下去就定了」—— 在触屏上那一版的第一下就是最后一下，
	# 玩家还没读到这只干什么，整局的底牌已经定了。
	var root := _prepared()
	root._open_modal(root._beasts)
	root._beasts.refresh(root._state, root._cfg)
	root._beasts._focus_on(0)
	assert_eq(root._state.beast_id, &"", "点一下只是挑中，还没定")

	var first: StringName = root._cfg.beasts.ids()[0]
	root._beasts._commit()
	assert_eq(root._state.beast_id, first, "按了「确定带它」才算数")
	assert_false(root._beasts.visible, "定完这一层就没有内容了，该收起来")


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
