extends GutTest
## 玩家手动挂装备（§10，M3.5-f）。
##
## ## 这个文件守的是三件事
##
## 1. **一件都不挂时，结果和 M3-c 到 M3.5-e 完全一样。** 手动那一份是
##    纯加法进来的，全部既有配平数字不该动一分 —— 那是它敢在
##    数值回归之前落地的全部理由
## 2. **手动优先、自动补满。** 挂了一件不等于放弃其余的自动分配
## 3. **挂不上的条目自动失效，但不被清掉。** 配件一时不够时，
##    玩家之前挂的位置不该永久消失

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


## 一支能同时吃物理装和法术装的队伍：一个物理、两个五系。
##
## **按属性挑，不钉稀有度**（M10-b 改的）。原来写的是
## `PBUnit.of(cfg, WATER, SSR)`，而照抄原版名册之后**没有水系 SSR**
## （8 个 SSR 是火 4 / 土 2 / 风 1 / 雷 1）—— 那一格空了之后
## 这个夹具拿回来的人属性不是水，两条断言跟着红，而红的是夹具。
## 这里只关心「一个物理 + 两个五系」，稀有度是哪一档无所谓。
func _team() -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for element: PBElement.Type in [
		PBElement.Type.PHYSICAL, PBElement.Type.FIRE, PBElement.Type.WATER
	]:
		var character := _any_of(element)
		assert_not_null(character, "名册里该有属性 %d 的角色" % int(element))
		out.append(PBUnit.new(character))
	return out


func _any_of(element: PBElement.Type) -> PBCharacter:
	for character: PBCharacter in _cfg.characters.all():
		if character.element == element:
			return character
	return null


## 手上有 [param count] 套「钝刀」（物理装）与「雷牙」（法术装）的配件。
##
## 配方直接从表里读，不写死 —— 数据改了这个夹具要跟着改，
## 而写死的话它会静默地开始造一堆合不出成品的配件。
func _parts(count: int) -> Dictionary:
	var parts: Dictionary = {}
	for item_id: StringName in [&"blunt_blade", &"thunder_fang"]:
		var item := _cfg.equipment.item(item_id)
		for _i: int in count:
			for part_id: StringName in item.recipe:
				PBEquipRules.add_part(parts, part_id)
	return parts


func test_no_pins_reproduces_the_old_automatic_assignment() -> void:
	# **这一条是数值回归的锚。** 手动那一份是纯加法进来的：
	# `equipped` 空着时每个人吃到的倍率必须和 M3-c 那版一字不差，
	# 否则「装备定价」以来的全部扫描结论都要重跑。
	var team := _team()
	var parts := _parts(2)
	var auto := PBEquipRules.unit_mods(team, parts, _cfg)
	var same := PBEquipRules.unit_mods(team, parts, _cfg, {})
	assert_eq(auto.size(), same.size(), "两种叫法应返回同样长度")
	for i: int in auto.size():
		assert_eq(same[i], auto[i], "第 %d 个人的词条不该因为多了个空字典而变" % i)


func test_multipliers_are_derived_from_the_named_list() -> void:
	# 词条是「身上挂了哪几件」并出来的派生量，不是第二份计算。
	# 分成两份的话，面板上写着挂了雷牙、战斗里却按没挂算 —— 不报错。
	var team := _team()
	var parts := _parts(3)
	var held := PBEquipRules.assign(team, parts, _cfg)
	var worn := PBEquipRules.unit_mods(team, parts, _cfg)
	for i: int in team.size():
		var sum: Dictionary = {}
		for item_id: String in held[i]:
			var item := _cfg.equipment.item(StringName(item_id))
			for key: StringName in item.mods:
				sum[key] = float(sum.get(key, 0.0)) + float(item.mods[key])
		assert_eq(worn[i], sum, "第 %d 个人的词条应等于他身上那几件并起来" % i)


func test_a_pin_wins_over_the_greedy_order() -> void:
	# 贪心是「填满靠前的人再往后发」。玩家把那一件点名给了排最后的人，
	# 就该真的发给他 —— 否则「手动」这两个字是假的。
	var team := _team()
	var parts := _parts(1)
	var pinned: Dictionary = {}
	assert_true(PBEquipRules.pin(pinned, team[2].key(), &"thunder_fang", _cfg), "水系应该挂得上法术装")
	var held := PBEquipRules.assign(team, parts, _cfg, pinned)
	assert_true(held[2].has("thunder_fang"), "点名给谁就该发给谁")
	assert_false(held[1].has("thunder_fang"), "只有一件，不该同时出现在两个人身上")


func test_the_rest_of_the_slots_are_still_filled_automatically() -> void:
	# **挂了一件不等于放弃其余的自动分配。** 玩家点那一下的意思只是
	# 「这件给他」，不是「其余的别管了」。
	var team := _team()
	var parts := _parts(3)
	var pinned: Dictionary = {}
	PBEquipRules.pin(pinned, team[2].key(), &"thunder_fang", _cfg)
	var held := PBEquipRules.assign(team, parts, _cfg, pinned)
	var total: int = 0
	for row: PackedStringArray in held:
		total += row.size()
	var auto_total: int = 0
	for row: PackedStringArray in PBEquipRules.assign(team, parts, _cfg):
		auto_total += row.size()
	assert_eq(total, auto_total, "挂了一件之后发出去的总件数不该变少")


func test_a_pin_that_does_not_fit_is_ignored_but_kept() -> void:
	# §10 的分类匹配：法术装挂不上物理角色。**记账留着、分配时跳过** ——
	# 直接拦在 pin 那一步的话，玩家换了个人上场就会发现那一格莫名消失。
	var team := _team()
	var pinned: Dictionary = {}
	assert_true(PBEquipRules.pin(pinned, team[0].key(), &"thunder_fang", _cfg), "记账不判分类")
	var held := PBEquipRules.assign(team, _parts(1), _cfg, pinned)
	assert_false(held[0].has("thunder_fang"), "物理角色吃不下法术装（§10）")
	assert_eq(PBEquipRules.pinned_of(pinned, team[0].key()).size(), 1, "挂不上不等于该把这条记录抹掉")


func test_a_pin_for_an_item_you_cannot_craft_just_does_nothing() -> void:
	# 配件被合成别的东西之后，之前挂的那件合不出来了。这时候
	# **静默跳过**是对的：下一箱配件到手它会自己回来。
	var team := _team()
	var pinned: Dictionary = {}
	PBEquipRules.pin(pinned, team[1].key(), &"thunder_fang", _cfg)
	var held := PBEquipRules.assign(team, {}, _cfg, pinned)
	for row: PackedStringArray in held:
		assert_eq(row.size(), 0, "一个配件都没有时谁也不该挂着东西")


func test_pins_stop_at_three_per_unit() -> void:
	# §10：每人最多 3 件。第 4 件挂不上，而且要**明确返回 false** ——
	# 静默吞掉的话界面会以为挂上了，然后画一个不存在的槽位。
	var team := _team()
	var pinned: Dictionary = {}
	for i: int in _cfg.equip_items_per_unit:
		assert_true(PBEquipRules.pin(pinned, team[1].key(), &"thunder_fang", _cfg), "第 %d 件" % i)
	assert_false(PBEquipRules.pin(pinned, team[1].key(), &"thunder_fang", _cfg), "第 4 件该挂不上")


func test_unpin_takes_off_exactly_one() -> void:
	var team := _team()
	var pinned: Dictionary = {}
	PBEquipRules.pin(pinned, team[1].key(), &"thunder_fang", _cfg)
	PBEquipRules.pin(pinned, team[1].key(), &"thunder_fang", _cfg)
	assert_true(PBEquipRules.unpin(pinned, team[1].key(), &"thunder_fang"), "卸得掉")
	assert_eq(PBEquipRules.pinned_of(pinned, team[1].key()).size(), 1, "挂着两件只该卸掉一件")
	PBEquipRules.unpin(pinned, team[1].key(), &"thunder_fang")
	assert_false(pinned.has(team[1].key()), "卸光了就该把这个人的条目一起去掉")
	assert_false(PBEquipRules.unpin(pinned, team[1].key(), &"thunder_fang"), "没挂的卸不掉")


func test_the_battle_reads_the_players_pins() -> void:
	# **接线**：手动那一份必须真的进战斗。存了却不读的话，
	# 装备栏点起来一切正常，而战场上什么都没变 —— 不报错。
	var state := PBRunSim.new_state(_cfg)
	var team := _team()
	for unit: PBUnit in team:
		state.add_unit(unit)
	state.equip_parts = _parts(1)
	var before := PBCombatRules.unit_mods(team, state, _cfg)
	PBEquipRules.pin(state.equipped, team[2].key(), &"thunder_fang", _cfg)
	var after := PBCombatRules.unit_mods(team, state, _cfg)
	assert_true(before[2].is_empty(), "点名之前他身上什么都没有")
	assert_false(after[2].is_empty(), "点名要了那一件之后，他身上该有词条")


func test_both_legs_are_walked_everywhere_the_bonuses_are_folded() -> void:
	# **扫描式断言**（M12-h2）。装备从「一个倍率」变成「一张词条表」之后，
	# 逐人加成有了**两条腿**：[method PBCombatRules.unit_multipliers]（尾兽光环）
	# 和 [method PBCombatRules.unit_mods]（装备）。
	#
	# 四个调用点（战斗、估值两处、任务卡预览）**两条都要拿** ——
	# 漏掉一条的表现是「那条路径上装备完全不生效」，而它不报错：
	# 界面照常、战斗照跑，只是打得少一点。同 M9-m 那条 `flips_for` 的扫描。
	for path: String in ["res://src/core/sim/run_sim.gd", "res://src/core/rules/valuation.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_eq(
			text.count("PBCombatRules.unit_multipliers("),
			text.count("PBCombatRules.unit_mods("),
			"%s 里两条腿的次数对不上 —— 有一处只折了一半" % path
		)
