extends GutTest
## 忍者的射程：**照抄原版码数，按一把尺子换成战场坐标**（[method PBSimConfig.reach_of]）。
##
## 这里错了都不报错：换算写了两处、一处改了另一处没改，表现是「射程圈画到了、人却打不到」；
## 敌人的近战射程比某个近战忍者长，那个忍者站在怪堆里一发都打不出去。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func test_original_units_convert_with_the_skill_table_ruler() -> void:
	# 技能表的「范围」一直按 2000 码 = 1 个战场长度换算，射程用同一把尺子，两者的比例才和原版一样。
	var character := PBCharacter.make(&"probe_range", PBElement.Type.FIRE, PBUnit.Rarity.R)
	character.attack_range = 600.0
	assert_almost_eq(_cfg.reach_of(character), 0.30, 0.0001, "原版 600 码 = 0.30")
	character.attack_range = 125.0
	assert_almost_eq(_cfg.reach_of(character), 0.0625, 0.0001, "原版 125 码 = 0.0625")


func test_a_character_without_a_range_falls_back_to_its_tier() -> void:
	var character := PBCharacter.make(&"probe_range", PBElement.Type.PHYSICAL, PBUnit.Rarity.R)
	assert_eq(character.attack_range, 0.0, "前提：代码现造的角色没配射程")
	assert_eq(_cfg.reach_of(character), _cfg.reach_distance(character.reach_tier()), "没配就按射程档的默认距离")


func test_every_roster_character_has_an_original_range() -> void:
	var table := PBCharacterLoader.table()
	assert_gt(table.size(), 0, "前提：名册读得到")
	for character: PBCharacter in table.all():
		assert_gt(character.attack_range, 0.0, "%s 没有射程 —— 名册「射程」列要填原版码数" % character.id)


func test_melee_stands_in_front_and_ranged_shoots_farther() -> void:
	# 「攻击距离」那一列决定站前排还是中排，「射程」那一列决定打多远 —— 两列说的必须是同一件事。
	for character: PBCharacter in PBCharacterLoader.table().all():
		var reach := _cfg.reach_of(character)
		if character.reach_tier() == PBCharacter.Reach.MELEE:
			assert_lt(reach, _cfg.enemy_reach_ranged, "%s 站前排，射程却比敌人远程还远" % character.id)
		else:
			assert_gt(reach, _cfg.enemy_reach_ranged, "%s 站中排，射程却够不到敌人远程" % character.id)


func test_no_melee_ninja_is_outranged_by_melee_enemies() -> void:
	# 敌人一走进自己的射程就站住。比忍者长的话，那个近战忍者结构上永远够不着他。
	for character: PBCharacter in PBCharacterLoader.table().all():
		assert_gte(_cfg.reach_of(character), _cfg.enemy_reach, "%s 的射程比敌人近战还短，贴不上去" % character.id)
	assert_lte(_cfg.enemy_reach, _cfg.reach_melee, "默认近战档也要够得着")


func test_the_battle_uses_each_characters_own_range() -> void:
	# 战斗实例按人读射程，不按射程档读 —— 同是远程，800 码的那一个真的打得更远。
	var table := PBCharacterLoader.table()
	var cfg := PBSimConfig.new()
	cfg.characters = table
	var units: Array[PBUnit] = []
	for character: PBCharacter in table.all():
		units.append(PBUnit.new(character))
	var ones := PackedFloat64Array()
	ones.resize(units.size())
	ones.fill(1.0)
	var attackers := PBCombatRules.build_attackers(units, PBElement.Type.FIRE, 1.0, ones, cfg)
	assert_eq(attackers.size(), units.size(), "前提：每人一个战斗实例")
	for i: int in units.size():
		assert_almost_eq(
			attackers[i].reach,
			cfg.reach_of(units[i].character),
			0.0001,
			"%s 的战斗射程" % units[i].character.id
		)
