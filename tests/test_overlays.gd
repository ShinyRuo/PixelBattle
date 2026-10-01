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


func test_drawing_a_card_never_swaps_someone_off_the_field() -> void:
	# **玩家报的 bug（M6-h）**：抽一张忍者，场上的人被换回仓库，
	# 而他一根手指都没动过。
	#
	# 根因不是那个「带人方式」开关，是 [method PBStrategy.bring_to_field]
	# 在自动模式下**每次刷新面板都把整队按战力重排一遍** ——
	# 抽到一张更强的卡就顶掉最弱的那个。实测：抽到迪达拉，波风水门下场。
	#
	# 修法是进准备阶段时就把队伍**固化成手排名单**：自动排出来的队伍
	# 在玩家看来就是他的队伍，系统不该背着他换人。
	# **这一局的仓库从 0 人开始**，队伍靠抽卡一个个攒 —— 所以先攒满出战席。
	var root := _prepared()
	await wait_physics_frames(2)
	var pool: Array[PBCharacter] = root._cfg.characters.all()
	var capacity: int = root._state.field_slots(root._cfg)
	for character: PBCharacter in pool.slice(0, capacity):
		root._state.add_unit(PBUnit.new(character))
		root._refresh_panels()
	var before: Array[StringName] = root._state.field.duplicate()
	assert_eq(before.size(), capacity, "攒满之后出战席该是满的")

	# 再抽一张**全场最强**的卡 —— 重排的话它必然挤掉一个。
	var best: PBUnit = null
	for character: PBCharacter in pool:
		var candidate := PBUnit.new(character)
		if best == null or candidate.power(root._cfg) > best.power(root._cfg):
			best = candidate
	root._state.add_unit(best)
	root._refresh_panels()

	assert_eq(root._state.field, before, "抽一张卡不该换掉场上任何一个人")
	# 上场的那批和屏幕上站的那批必须是同一批 —— 两份的表现是
	# 「我摆好的阵型和实际打的人对不上」，而那不报错。
	var fighting: Array[StringName] = []
	for unit: PBUnit in root._strategy.deploy(root._state, root._plan.wave, root._cfg):
		fighting.append(unit.key())
	assert_eq(fighting, before, "真正上场的还是屏幕上那几个")


func test_a_new_card_still_walks_into_an_empty_slot() -> void:
	# 上面那条的反面，两条缺一不可：**顶不掉人**，但**空位还是要填**。
	# 只钉一次的话后面抽到的人永远进不了队 —— 而这一局是从 0 人开始的。
	var root := _prepared()
	await wait_physics_frames(2)
	var pool: Array[PBCharacter] = root._cfg.characters.all()
	for i: int in mini(3, root._state.field_slots(root._cfg)):
		root._state.add_unit(PBUnit.new(pool[i]))
		root._refresh_panels()
		assert_eq(root._state.field.size(), i + 1, "第 %d 张卡该走进空位" % (i + 1))


func test_the_players_own_hand_stops_the_auto_upkeep() -> void:
	# 玩家一旦自己拖过，系统就不再替他维护名单 —— 他留的空位从此是他的。
	# **两个字段分开的全部理由**，见 [member PBRunState.lineup_by_hand]。
	var root := _prepared()
	await wait_physics_frames(2)
	root._state.add_unit(PBUnit.new(root._cfg.characters.all()[0]))
	root._refresh_panels()
	assert_false(root._state.lineup_by_hand, "系统替他排的不算他亲手排的")
	assert_true(root._state.lineup_manual, "但上场要按这份名单走，不能回去自动重排")

	# 玩家亲手把人全拖下场。
	root._strategy.set_lineup(root._state, [] as Array[PBUnit])
	assert_true(root._state.lineup_by_hand, "拖过之后就归他了")
	root._refresh_panels()
	assert_eq(root._state.lineup.size(), 0, "他要空着就空着，别把名单替他填回去")
	assert_eq(root._strategy.deploy(root._state, root._plan.wave, root._cfg).size(), 0, "上场的也该是零个")
	# **羁绊也得跟着是零个**（M6-i 修的）。在那之前 `bring_to_field` 仍会
	# 按策略往 `field` 里补满，而 `deploy` 只返回名单里的人 ——
	# 于是羁绊算上了一个屏幕上根本不存在的人，不报错，只是倍率虚高。
	assert_eq(root._state.field.size(), 0, "场上没人，在场名单就该是空的")
	assert_eq(root._state.bonded_units(root._cfg).size(), 0, "羁绊不许算上一个不上场的人")


func test_a_drawn_card_takes_an_empty_slot_but_never_a_taken_one() -> void:
	# 玩家的原话：**场上有空位就上场，没空位就进仓库。**
	# 亲手排过之后这条也得成立 —— 那时自动维护已经停手（上一条测的就是它）。
	var root := _prepared()
	await wait_physics_frames(2)
	var pool: Array[PBCharacter] = root._cfg.characters.all()
	var capacity: int = root._state.field_slots(root._cfg)
	# 亲手把一个人拖上场：从这里起名单归玩家。
	root._state.add_unit(PBUnit.new(pool[0]))
	var mine: Array[PBUnit] = [root._state.all_units()[0]]
	root._strategy.set_lineup(root._state, mine)
	root._refresh_panels()
	assert_true(root._state.lineup_by_hand, "前提：这份名单已经是玩家亲手排的")

	# 空位还剩 capacity - 1 个，抽一张就该直接站上去。
	for i: int in range(1, capacity):
		root._state.pending_offer = [PBUnit.new(pool[i])] as Array[PBUnit]
		root._on_offer_picked(0)
		assert_eq(root._state.lineup.size(), i + 1, "有空位，第 %d 张卡该上场" % (i + 1))
	assert_eq(root._state.field.size(), capacity, "空位填满了")

	# 满了之后再抽，卡进仓库，场上一个人都不许换。
	var before: Array[StringName] = root._state.field.duplicate()
	root._state.pending_offer = [PBUnit.new(pool[capacity])] as Array[PBUnit]
	root._on_offer_picked(0)
	assert_eq(root._state.field, before, "没空位，新卡只能待在仓库")
	assert_eq(root._state.roster.size(), capacity + 1, "但他确实进了仓库")


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
	assert_eq(root._beasts.mouse_filter, Control.MOUSE_FILTER_STOP, "弹层这一层必须自己吃掉鼠标")
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
	var away: Array[PBUnit] = PBFieldRoster.dispatch_preview(root._state)
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
	assert_eq(PBEquipRules.pinned_of(root._state.equipped, unit.key()).size(), 1, "挂上该记进状态")
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


func test_every_beast_aura_shows_up_in_its_description() -> void:
	# 走被动词汇表的光环（防御、闪避、吸血……）以前在这里一个字都不写，一半尾兽读起来是「光环：无」，
	# 而战斗里它们一直在生效。
	var root := _prepared()
	root._open_modal(root._beasts)
	root._beasts.refresh(root._state, root._cfg)
	var seen: int = 0
	for i: int in root._cfg.beasts.all().size():
		var beast: PBBeast = root._cfg.beasts.all()[i]
		if beast.aura_passives.is_empty():
			continue
		root._beasts._describe(i)
		var aura := PBBeastRules.aura_passives(beast, 1, root._cfg)
		for word: String in PBShopLabels.mod_words(aura):
			assert_string_contains(root._beasts._detail.text, word, "%s 的光环没写出来" % beast.id)
		seen += 1
	assert_gt(seen, 0, "前提：有尾兽带被动光环")


func test_escape_opens_the_menu_only_after_everything_else_is_closed() -> void:
	# `Esc` 已经有一条链（说明卡 → 弹层 → 瞄准 → 选中），菜单排在**最后**。
	# 排到前面的话，手上挡着一张说明卡时按 `Esc` 会弹出设置，
	# 而玩家要按四下才能取消一次选中。
	var root := _prepared()
	root._open_modal(root._beasts)
	root._on_escape()
	assert_false(root._beasts.visible, "第一下该收掉弹层")
	assert_false(root._menu.visible, "第一下收的是弹层，不是开菜单")
	root._on_escape()
	assert_true(root._menu.visible, "没东西可收了才轮到菜单")


func test_the_graphics_page_steps_back_before_the_menu_closes() -> void:
	# 两页共用一层（[PBModal] 一次只摊一层）。所以 `Esc` 在这一层里有两种含义，
	# 而**判断和执行必须在同一处**（[method PBSystemMenu.back]）——
	# 调用方自己看当前是哪一页再决定的话，加第三页那天两边就分叉了。
	var root := _prepared()
	root._on_escape()
	root._menu._show_page(PBSystemMenu.Page.GRAPHICS)
	root._on_escape()
	assert_true(root._menu.visible, "图形页按 Esc 是退回主页，不是整个关掉")
	assert_eq(root._menu._page, PBSystemMenu.Page.MAIN, "该退回主页")
	root._on_escape()
	assert_false(root._menu.visible, "主页按 Esc 才关掉")


func test_the_menu_pauses_and_hands_the_pause_back() -> void:
	# 菜单第一项写着「继续」，底下的战斗照跑的话那两个字就是假的。
	# 但**他自己按的暂停不能被替他取消** —— 他可能是停下来看局面，
	# 顺手开了菜单，关掉之后那一波不该突然动起来。
	var root := _prepared()
	assert_false(root._paused, "开局不该是暂停的")
	root._on_escape()
	assert_true(root._paused, "摊开菜单就该停下来")
	root._on_escape()
	assert_false(root._paused, "关掉菜单该恢复原样")

	root._paused = true
	root._on_escape()
	root._on_escape()
	assert_true(root._paused, "他自己按的暂停，菜单不该替他取消")


func test_the_resolution_box_never_lies_about_the_current_window() -> void:
	# 玩家可能刚按过 `F10`/`F11`，也可能自己拖过窗口边。**不在档位表里就一项都不选** ——
	# 硬指一个的话，那一行会告诉他「你已经是这个分辨率了」，而他并不是。
	var root := _prepared()
	root._menu.open()
	assert_eq(root._menu._sizes.item_count, PBDisplay.SIZES.size(), "档位表要全列出来")
	var picked: int = root._menu._sizes.selected
	if picked >= 0:
		assert_eq(PBDisplay.SIZES[picked], DisplayServer.window_get_size(), "选中的那一项必须真的等于当前窗口")


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
	# M6-a 起每人多了一层锚节点（脚下那个点），精灵挂在它下面 ——
	# 所以这里要往下找一层，不能只看直接子节点。
	for sprite: Node in _ally_sprites(root):
		if (sprite as AnimatedSprite2D).visible:
			shown += 1
	assert_gt(shown, 0, "战斗中场上应该画得出己方忍者")


func test_your_ninjas_are_gone_again_once_the_wave_has_not_started() -> void:
	# 准备阶段没有战场（敌人要等 `_finish_prepare` 才生成），
	# 这时候还画着上一波的方块就成了「战场上有人但打不起来」。
	var root := _prepared()
	for sprite: Node in _ally_sprites(root):
		assert_false((sprite as AnimatedSprite2D).visible, "准备阶段不该有己方单位画在战场上")


## 己方池子里那些精灵。见 [method PBAllyPool._ready] —— 每人一个锚，
## 精灵和两条血条挂在锚下面。
func _ally_sprites(root: Node2D) -> Array[Node]:
	return (root.get_node("Actors/Deployed") as PBAllyPool).find_children(
		"", "AnimatedSprite2D", true, false
	)
