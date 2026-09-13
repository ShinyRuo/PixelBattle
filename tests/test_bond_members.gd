extends GutTest
## 「每个在场成员各拿自己那一份」（M12-d1）。

## ## 这个文件守的是什么
##
## 原版**每组羁绊给每个成员各发一份属于他自己的效果**（解包文档 §6 开头那句）——
## 45 组里只有 3 组是人人同一句。而我们此前是「一组一个载体拿一份」，
## 表达不了〔军师夫妇〕那种「手鞠改她的气流乱舞、鹿丸改他的影子模仿术」。
##
## 四条：
##
## 1. **每个人各拿各的**，而不是全组同一份
## 2. **不在场就不兑现** —— 同载体那条门槛
## 3. **两组给同一个人同一个键时量相加**，不是后一组盖前一组
## 4. **没凑满一份都不发**

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func test_each_member_gets_their_own_share_not_a_shared_one() -> void:
	var bond := _bond({&"a": {PBPassiveRules.CRIT_CHANCE: 0.2}, &"b": {PBPassiveRules.DODGE: 0.3}})
	var out := _ask(bond, [&"a", &"b"], [&"a", &"b"])
	assert_eq(out.size(), 2, "两个人各有一份")
	assert_almost_eq(float(out[&"a"][PBPassiveRules.CRIT_CHANCE]), 0.2, 0.0001, "a 拿他的")
	assert_almost_eq(float(out[&"b"][PBPassiveRules.DODGE]), 0.3, 0.0001, "b 拿他的")
	assert_false(out[&"a"].has(PBPassiveRules.DODGE), "a 不该拿到 b 那一份")


func test_a_member_who_is_not_fighting_gets_nothing() -> void:
	# 同载体那条门槛（M3-f）：凑齐人数**且**他真的在打这一波。
	# 只看「凑没凑齐」的话，派去做任务的人照样兑现，而 §06 的代价就没了。
	var bond := _bond({&"a": {PBPassiveRules.CRIT_CHANCE: 0.2}, &"b": {PBPassiveRules.DODGE: 0.3}})
	var out := _ask(bond, [&"a", &"b"], [&"a"])
	assert_true(out.has(&"a"), "在场的照发")
	assert_false(out.has(&"b"), "不在场的不发")


func test_nothing_comes_out_before_the_group_is_full() -> void:
	var bond := _bond({&"a": {PBPassiveRules.CRIT_CHANCE: 0.2}})
	assert_eq(_ask(bond, [&"a"], [&"a"]).size(), 0, "只到一个人不该发")


func test_two_bonds_on_the_same_person_add_up_instead_of_overwriting() -> void:
	# **同 [PBBuffBag] 同 id 整份覆盖那个坑**（M10-c 为它把光环挤出了效果袋）：
	# 盖的话玩家凑满两组只拿到一组的量，而那不报错。
	var one := _bond({&"a": {PBPassiveRules.CRIT_CHANCE: 0.2}}, &"one")
	var two := _bond({&"a": {PBPassiveRules.CRIT_CHANCE: 0.3}}, &"two")
	var table := PBBondTable.new()
	table.add(one)
	table.add(two)
	var who := _units([&"a", &"b"])
	var out := PBBondRules.active_passives(who, who, table)
	assert_almost_eq(float(out[&"a"][PBPassiveRules.CRIT_CHANCE]), 0.5, 0.0001, "两组该加起来")


func test_the_share_really_reaches_the_attacker() -> void:
	# 上面几条量的是那张表，这一条量「它真的乘到人身上了吗」——
	# 中间那一步（[method PBCombatRules.build_attackers]）漏掉的话，
	# 表算得再对屏幕上也什么都不会发生。
	var deployed := _units([&"a", &"b"])
	var passives := {&"a": {PBPassiveRules.CRIT_CHANCE: 0.25}}
	var built := PBCombatRules.build_attackers(
		deployed, PBElement.Type.PHYSICAL, 1.0, 1.0, PackedFloat64Array(), _cfg, null, 1, 0, {},
		passives
	)
	assert_almost_eq(built[0].crit_chance, 0.25, 0.0001, "他那一份该到他身上")
	assert_almost_eq(built[1].crit_chance, 0.0, 0.0001, "别人不该沾上")


func test_the_real_table_moved_the_trigger_bonds_over_without_changing_a_number() -> void:
	# M10-d 那四个键原来走 `Landing.CARRIER`，M12-d1 把那一档整个去掉了。
	# **迁移不许改数**：量仍然取 `CARRIER_AMOUNTS`，一个都没动。
	var found: Dictionary = {}
	for bond: PBBond in _cfg.bonds.all():
		for who: StringName in bond.member_functions:
			for key: StringName in bond.member_functions[who]:
				if not PBBondFunctionRules.CARRIER_AMOUNTS.has(key):
					continue
				found[key] = true
				assert_almost_eq(
					float(bond.member_functions[who][key]),
					float(PBBondFunctionRules.CARRIER_AMOUNTS[key]),
					0.0001,
					"「%s」的量被改过了" % key
				)
	assert_gt(found.size(), 0, "真表里一个触发型键都没有，上面什么都没量")
	# **不断「四个都在用」** —— 那是数据状态不是规则。日向兄妹 d1 起改用了
	# 更贴原版的柔拳形状（`crit_chance` + `bite_current`），`heavy_hit`
	# 因此暂时没人用；写死 4 的话它会在内容变好的那天变红。


func test_every_key_in_the_real_table_is_one_we_know() -> void:
	# 生成器读表那一刻就拦（退出码 1），这条是第二道 —— 盘上的 `.tres`
	# 也可能是手改的。不认识的键静默躺在数据里的表现是「配了不生效」。
	var seen: int = 0
	for bond: PBBond in _cfg.bonds.all():
		for who: StringName in bond.member_functions:
			assert_true(bond.member_ids.has(who), "「%s」不是 %s 的成员" % [who, bond.id])
			for key: StringName in bond.member_functions[who]:
				assert_true(PBModRules.is_known(key), "「%s」这个键没人认得" % key)
				seen += 1
	assert_gt(seen, 0, "真表里一份成员效果都没有，上面什么都没量")


## 一组满档人数 = 2 的羁绊，成员 a / b。
func _bond(shares: Dictionary, id: StringName = &"probe_bond") -> PBBond:
	var bond := PBBond.new()
	bond.id = id
	bond.match_mode = PBBond.Match.MEMBERS
	bond.member_ids = [&"a", &"b"] as Array[StringName]
	bond.tier_counts = [2] as Array[int]
	bond.tier_power = [0.0] as Array[float]
	bond.member_functions = shares
	return bond


func _units(ids: Array) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for id: StringName in ids:
		var character := PBCharacter.new()
		character.id = id
		out.append(PBUnit.new(character))
	return out


func _ask(bond: PBBond, bonded: Array, deployed: Array) -> Dictionary:
	var table := PBBondTable.new()
	table.add(bond)
	return PBBondRules.active_passives(_units(bonded), _units(deployed), table)
