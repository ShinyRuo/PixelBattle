extends GutTest
## H 区信息栏与 G 区忍具仓库的改版。§02，M6-j。
##
## ## 这几条守的是「玩家说的那句话」
##
## 四条改动全部来自一次试玩反馈，每条都有一句原话，断言就照那句话写：
##
## - 「人物信息卡中的星级去掉」
## - 「不显示再补就能进的羁绊，只显示已生效的」
## - 「鼠标移到羁绊文字上弹出 tooltips 羁绊中的人物」
## - 「场上有的人物和没有的用颜色区分」
##
## 面板上的字最容易出现的失败是**它还在，只是被挤到看不见的地方**
## （[PBLayout] 顶部那条出界断言就是为这个立的）。所以这里断的是
## 「那句话在不在文本里」，不是「它画在哪一格」。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const FIXED_SEED: int = 20260902


func _prepared() -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	add_child_autofree(root)
	root._enter_prepare()
	return root


## 造一队人并选中第一个，返回那块信息栏。
func _with_a_squad(root: Node2D, count: int) -> PBUnitInfo:
	for character: PBCharacter in root._cfg.characters.all().slice(0, count):
		root._state.add_unit(PBUnit.new(character))
	root._refresh_panels()
	return root._unit_info


func test_the_card_no_longer_shows_a_star_level() -> void:
	# M5-9 起重复抽到的是**另一个人**，「同卡 3 张升 1 星」那条规则作废 ——
	# 这个数因此恒为 1，而一个永远不变的数字只会让人以为自己漏了
	# 一套没做出来的养成系统。
	var root := _prepared()
	var info := _with_a_squad(root, 3)
	var unit: PBUnit = root._state.all_units()[0]
	root._select(PBSelection.Kind.UNIT, unit.key())
	assert_false(info._head.text.contains("★"), "卡头上不该再有星级：%s" % info._head.text)
	assert_true(info._head.text.contains("Lv"), "等级还是要留着")


func test_the_team_card_only_lists_bonds_that_are_actually_live() -> void:
	# 羁绊改成全有或全无之后（见 [PBBond]），「差一个人」处处都是 ——
	# 把没凑上的也摊开等于把整张羁绊表抄在一块 168 像素宽的面板上。
	var root := _prepared()
	var info := _with_a_squad(root, 4)
	root._selection.set_to(PBSelection.Kind.NONE)
	root._refresh_panels()
	assert_false(info._body.text.contains("再补就能进"), "这一段整个删掉了：%s" % info._body.text)
	var units: Array[PBUnit] = root._state.bonded_units(root._cfg)
	for bond: PBBond in root._cfg.bonds.all():
		if bond.tier_at(PBBondRules.active_count(bond, units)) > 0:
			assert_true(
				info._body.text.contains(PBLocale.of_bond(bond)),
				"生效的那几组要写出来（缺 %s）" % PBLocale.of_bond(bond)
			)


func test_hovering_a_bond_asks_for_a_card_of_its_members() -> void:
	# 「都有谁」是问一次就走的信息，不该常驻占三行 —— 所以它在悬停卡里。
	# **认不出来的 meta 一律不响应**：静默弹一张空卡比什么都不做更难查。
	var root := _prepared()
	var info := _with_a_squad(root, 4)
	var bond: PBBond = root._cfg.bonds.all()[0]
	watch_signals(info)
	info._on_meta_hover(PBUnitInfo.BOND_META + bond.id)
	assert_signal_emitted(info, "hint_requested", "停在羁绊那一行上就该要一张卡")
	info._on_meta_hover("nonsense")
	assert_signal_emit_count(info, "hint_requested", 1, "认不出来的 meta 不该弹")


func test_the_card_colours_members_by_where_they_are() -> void:
	# 玩家的原话：「场上有的人物和没有的用颜色区分」。
	# **三档不是两档**：在场 / 抽到了但不在场上 / 压根没抽到 ——
	# 中间那一档是这一下就能补上的，第三档只能等抽卡。
	# 这也正是编队页删掉之后一直没找到家的那份三色名单（M3-e 起记在待决策表上）。
	var root := _prepared()
	var info := _with_a_squad(root, 4)
	# 挑一组「有人在场、也有人没抽到」的羁绊出来，两档才都验得到。
	var picked: PBBond = null
	for bond: PBBond in root._cfg.bonds.all():
		var owned: int = 0
		var total: int = 0
		for character: PBCharacter in root._cfg.characters.all():
			if not bond.counts_character(character):
				continue
			total += 1
			for unit: PBUnit in root._state.all_units():
				if unit.character.id == character.id:
					owned += 1
					break
		if owned > 0 and owned < total:
			picked = bond
			break
	assert_not_null(picked, "得有一组羁绊是「有几个、缺几个」的，否则测不到颜色")
	var body: String = info._bond_body(picked)
	assert_true(body.contains("（在场）"), "在场的那几个要标出来：%s" % body)
	assert_true(body.contains("（未拥有）"), "没抽到的也要摆着 —— 那是抽卡的目标")
	assert_true(
		body.contains(PBSkin.GOOD.to_html(false)) and body.contains(PBSkin.DIM.to_html(false)),
		"两档必须是不同的颜色，不能只靠后面那几个字"
	)


func test_every_beast_gets_its_own_picture() -> void:
	# 玩家的原话：「尾兽的图片根据选择的尾兽不同而变化，空尾兽也是一张图片」。
	# 按钮那一版里九只长得一模一样（都是「尾兽 / Lv1」两行字），
	# 换了一只屏幕上什么都不变 —— **那正是这张图要解决的事**。
	var seen: Dictionary = {}
	for tails: int in 10:
		var texture: Texture2D = PBIconArt.beast(tails)
		assert_not_null(texture, "第 %d 尾也得有一张图（0 = 还没选）" % tails)
		var key: String = texture.get_image().get_data().hex_encode()
		assert_false(seen.has(key), "第 %d 尾和第 %s 尾画得一模一样" % [tails, seen.get(key, "?")])
		seen[key] = tails
	assert_eq(seen.size(), 10, "十张图必须两两不同")
	# 同一个尾数要拿到**同一个**纹理：不缓存的话每次刷新都重画几百个像素。
	assert_eq(PBIconArt.beast(3), PBIconArt.beast(3), "同一只该走缓存")


func test_the_base_bar_lives_on_the_icon_now() -> void:
	# 竖条从战场左沿搬到了大本营那张图的顶上（玩家定的）。
	# 断言分两半：**场景里不该再有那个节点**（留着就是第二份真相），
	# 而面板上那条要跟着血量走。
	var root := _prepared()
	await wait_physics_frames(2)
	assert_null(root.get_node_or_null("Base"), "战场左沿那条竖条该没有了")
	var slots: PBFieldSlots = root._slots
	slots.show_base_hp(1000.0, 1000.0)
	var full: float = slots._bar_fill.size.x
	slots.show_base_hp(250.0, 1000.0)
	assert_almost_eq(slots._bar_fill.size.x, full * 0.25, 0.5, "四分之一血就该只剩四分之一条")
	assert_true(slots._base_label.text.contains("250"), "那个数也要跟着走")
	# 打起来之后它不能跟着准备阶段的面板一起收掉 ——
	# 「基地还剩多少」恰恰是战斗中最要紧的一个数。
	root._finish_prepare()
	assert_true(slots.visible, "战斗中大本营那一块要留着")


func test_the_quest_slots_sit_in_one_row_inside_the_panel() -> void:
	# 玩家的原话：「4 个槽位并排横放不换行」。
	# **出界那一截只是画在界外，不报错** —— [PBLayout] 顶上那条断言
	# 立起来就是为了这种失败，这里对着任务栏再钉一遍。
	var root := _prepared()
	await wait_physics_frames(2)
	var tiles: Array = root._quest._tiles
	assert_eq(tiles.size(), PBEconomyRules.QUEST_SLOTS, "四个槽，一个不多一个不少")
	var panel: Rect2 = PBLayout.E_QUEST
	for i: int in tiles.size():
		var tile: PBUnitTile = tiles[i]
		assert_eq(tile.position.y, tiles[0].position.y, "第 %d 个槽换行了" % i)
		if i > 0:
			assert_gt(tile.position.x, tiles[i - 1].position.x, "第 %d 个槽该排在前一个右边" % i)
		assert_true(
			panel.encloses(Rect2(tile.position, tile.size)),
			"第 %d 个槽跑出了任务栏：%s vs %s" % [i, tile.position, panel]
		)


func test_the_parts_bay_keeps_every_tile_inside_its_frame() -> void:
	# G 区从 110 缩到 74（M6-j 把地方让给了 H），格子改成流式 + 滚动。
	# **列数是算出来的**：写死的话框一变窄，最右边那列就画到隔壁面板上去了，
	# 而那不报错 —— 和 [PBLayout] 顶部那条出界断言是同一类失败。
	var root := _prepared()
	root._state.equip_parts = {}
	for part: StringName in root._cfg.equipment.parts:
		root._state.equip_parts[part] = 3
	root._refresh_panels()
	var bay: PBPartsBay = root._parts
	var clip: Control = bay._clip
	assert_gt(clip.size.x, 0.0, "裁剪区得有宽度")
	for tile: PBItemTile in bay._tiles:
		if not tile.visible:
			continue
		assert_lte(
			tile.position.x + tile.size.x, clip.size.x + 0.5,
			"格子不许漫出框外（x=%.1f 宽=%.1f 框=%.1f）" % [tile.position.x, tile.size.x, clip.size.x]
		)
		assert_gte(tile.position.x, -0.5, "也不许往左漏")
