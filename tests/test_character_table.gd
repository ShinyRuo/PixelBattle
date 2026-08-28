extends GutTest
## [PBCharacter] / [PBCharacterTable] 的测试。M2-a。
##
## 身份层是当作**可对拍的重构**引入的：合成表必须精确复现 M-1 至 M1 的卡池，
## 这样「换成真角色表」那一步的数值变化才能和「引入身份层」这一步分开看。
## 下面第一组断言就是那个凭据 —— 它红了，说明合成表已经不是原来那副牌，
## 此前所有扫描结论（`GROWTH` 1.10、装备 300、角都曲线）的基准都失效了。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func test_the_synthetic_table_reproduces_the_pre_m2_card_pool() -> void:
	# M2 之前一张卡是 `(属性, 稀有度, 变体)`，卡池 = 4 × 6 × characters_per_bucket。
	var table := _cfg.characters
	var expected: int = 4 * PBElement.Type.size() * _cfg.characters_per_bucket
	assert_eq(table.size(), expected, "合成卡池应该还是 4 稀有度 × 6 属性 × %d 变体" % _cfg.characters_per_bucket)

	# 每一格都要填满 —— 抽卡是先掷属性再掷变体的，缺一格就会走到退化路径，
	# 而那条路径会悄悄改变抽卡的实际分布。
	for rarity: int in PBUnit.Rarity.size():
		for element: int in PBElement.Type.size():
			assert_eq(
				table.count_in_cell(element as PBElement.Type, rarity as PBUnit.Rarity),
				_cfg.characters_per_bucket,
				"（属性 %d, 稀有度 %d）这一格应该是满的" % [element, rarity]
			)


func test_every_character_has_a_unique_id() -> void:
	# id 是仓库字典的键，也是 §12 存档认卡用的值。撞 id 会让两个角色
	# 被当成同一张卡去升星 —— 那种错误在结果里完全看不出来。
	var seen := {}
	for character: PBCharacter in _cfg.characters.all():
		assert_false(seen.has(character.id), "id 撞车：%s" % character.id)
		assert_ne(character.id, &"", "id 不能是空的")
		seen[character.id] = true
	assert_eq(seen.size(), _cfg.characters.size(), "每个角色都该有自己的 id")


func test_rarity_buckets_partition_the_whole_table() -> void:
	# 估值按「稀有度概率 ÷ 该稀有度下的角色数」算单张卡的概率
	# （见 PBValuation.expected_surplus）。分组要是没盖全表，那个除法就是错的。
	var total: int = 0
	for rarity: int in PBUnit.Rarity.size():
		var pool := _cfg.characters.of_rarity(rarity as PBUnit.Rarity)
		total += pool.size()
		for character: PBCharacter in pool:
			assert_eq(int(character.rarity), rarity, "%s 被分到了错的稀有度" % character.id)
	assert_eq(total, _cfg.characters.size(), "四个稀有度加起来应该正好是整张表")


func test_pick_wraps_instead_of_running_off_the_end() -> void:
	var table := _cfg.characters
	var first := table.pick(PBElement.Type.FIRE, PBUnit.Rarity.SSR, 0)
	assert_not_null(first, "合成表这一格必然有人")
	assert_eq(
		table.pick(PBElement.Type.FIRE, PBUnit.Rarity.SSR, _cfg.characters_per_bucket).id,
		first.id,
		"下标该绕回，不该越界"
	)
	assert_eq(
		table.pick(PBElement.Type.FIRE, PBUnit.Rarity.SSR, -1).id,
		table.pick(PBElement.Type.FIRE, PBUnit.Rarity.SSR, _cfg.characters_per_bucket - 1).id,
		"负下标也要绕回"
	)


func test_pick_falls_back_when_a_cell_is_empty() -> void:
	# **这条守的是真角色表**（M2-a2）：30 个角色摊到 4 稀有度 × 6 属性 上，
	# 必然有空格（比如没有水系 USR）。抽卡不能因为格子空了就掉一张空 ——
	# 掉空会在几百局之后表现为「某些局莫名少几张卡」，极难反推。
	var sparse := PBCharacterTable.new()
	sparse.add(PBCharacter.make(&"only_fire_r", PBElement.Type.FIRE, PBUnit.Rarity.R))
	var missing := sparse.pick(PBElement.Type.WATER, PBUnit.Rarity.R, 0)
	assert_not_null(missing, "同稀有度里还有人，就不该返回 null")
	assert_eq(missing.id, &"only_fire_r")
	assert_null(sparse.pick(PBElement.Type.FIRE, PBUnit.Rarity.USR, 0), "整个稀有度都空才返回 null")


func test_a_card_is_identified_by_its_character() -> void:
	var character := _cfg.characters.pick(PBElement.Type.THUNDER, PBUnit.Rarity.SSR, 0)
	var unit := PBUnit.new(character)
	assert_eq(unit.key(), character.id, "卡的身份就是角色 id（§14 铁律 5）")
	assert_eq(unit.element, character.element, "属性从角色复制")
	assert_eq(unit.rarity, character.rarity, "稀有度从角色复制")


func test_the_table_refuses_bad_entries_and_says_so() -> void:
	# 拒收要**回报**，不能静默吞掉 —— 装载器靠这个返回值才知道
	# 哪份 `.tres` 写错了（core 里没有文件路径可报，所以只返回状态）。
	var table := PBCharacterTable.new()
	assert_true(
		table.add(PBCharacter.make(&"dup", PBElement.Type.FIRE, PBUnit.Rarity.R)), "第一个应该收下"
	)
	assert_false(
		table.add(PBCharacter.make(&"dup", PBElement.Type.WATER, PBUnit.Rarity.SSR)), "重复 id 应该被拒"
	)
	assert_false(
		table.add(PBCharacter.make(&"", PBElement.Type.FIRE, PBUnit.Rarity.R)), "空 id 应该被拒"
	)
	assert_false(table.add(null), "null 应该被拒，而不是崩")
	assert_eq(table.size(), 1, "被拒的都不该进表")


func test_the_gacha_only_ever_draws_characters_that_exist_in_the_table() -> void:
	# 抽卡返回的卡必须是表里那一个对象，不是现造的 —— 现造的卡
	# 在羁绊系统眼里不属于任何一组（M2-b）。
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i: int in 300:
		var unit := PBEconomyRules.roll_gacha(1 + i % 60, 0, _cfg, rng)
		assert_not_null(unit, "抽卡不该掉空")
		assert_eq(
			_cfg.characters.by_id(unit.key()), unit.character, "抽到的应该是表里那一个角色对象：%s" % unit.key()
		)
