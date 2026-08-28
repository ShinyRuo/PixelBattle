extends GutTest
## `data/characters/*.tres` 这张**真角色表**本身的测试。M2-a2。
##
## 和 `test_character_table.gd` 的分工：那边测的是查表这个**机制**（用合成表），
## 这边测的是 `data/` 里那 30 份**内容**。两者失效方式完全不同 ——
## 机制坏了会崩，内容写歪了只会让数值悄悄偏掉。
##
## ## 为什么内容值得单独钉
##
## M2-a2 实测到一件事：**属性分布是个非常敏感的旋钮。**
## 物理角色从 5 个加到 6 个（占比 16.7% → 20%），
## §03 的验收「纯物理极限波次 < 五系的 70%」就从 60.5% 推到了 73.6%，
## 直接破线。**3.3 个百分点的卡池占比，放大成 13 个百分点的验收指标。**
##
## 所以下面这些不是形式检查，是配平约束。

## §07 把角色名写死进了机制名，是 M-1 就欠下的债。
##
## `tsunade_income`（击杀掉落流）、`GOLD_SOURCES` 里的 `&"tsunade"`、
## `PBSimConfig.tsunade_gain/loss`、CSV 的 `share_tsunade` 列 ——
## 换皮之后这些会变成「以一个不存在的角色命名的机制」。
## 角都同理（`kakuzu_income` / `kakuzu_count` / `kakuzu_base`），
## 只是它还没进首批 30 人表，所以下面那条测试暂时抓不到它。
##
## **清债要在 M5（换皮里程碑）之前做**，而且要单独一次改动 ——
## 它会动 CSV 列名和报表表头，混在别的改动里会让历史扫描结果对不上号。
const KNOWN_LEAKS: Array[StringName] = [&"tsunade"]

var _table: PBCharacterTable
var _cfg: PBSimConfig


func before_all() -> void:
	_table = PBCharacterLoader.load_from(PBCharacterLoader.DIR)
	_cfg = PBCharacterLoader.config()


func test_the_data_directory_actually_loads() -> void:
	assert_gt(_table.size(), 0, "data/characters/ 里应该装得出角色")
	assert_eq(_table.size(), 30, "首批是 30 个角色（M2 的量；§09 的 PC 首发 40+ 在 M5）")


func test_every_element_can_fill_the_starting_bench() -> void:
	# 出战席初始 4 格。某一系的角色数少于 4，「这一波上满克制系」
	# 就是做不到的事，§03 的克制加成会被系统性低估。
	for element: int in PBElement.Type.size():
		var count: int = 0
		for character: PBCharacter in _table.all():
			if int(character.element) == element:
				count += 1
		assert_gte(count, _cfg.deploy_slots_base, "属性 %d 的角色数应够填满初始出战席" % element)


func test_no_element_is_over_represented() -> void:
	# 上面那条只管下限。**上限同样要管** —— 物理超配就会破 §03 的
	# 「纯物理 < 五系的 70%」，实测 20% 占比即破线。
	# 首批表刻意做成六系均分（各 5 个），好让此前所有扫描结论
	# （GROWTH 1.10、装备 300、角都曲线）继续成立。
	var counts := {}
	for character: PBCharacter in _table.all():
		counts[int(character.element)] = int(counts.get(int(character.element), 0)) + 1
	var share: float = 1.0 / float(PBElement.Type.size())
	for element: int in PBElement.Type.size():
		var got: float = float(counts.get(element, 0)) / float(_table.size())
		assert_almost_eq(got, share, 0.02, "属性 %d 的占比偏离均分太多（%.1f%%）" % [element, got * 100.0])


func test_every_rarity_has_someone() -> void:
	# 抽卡是「掷稀有度 → 在该稀有度里取一个」。某一档空了就要走退化路径，
	# 而那条路径会把实际的稀有度分布悄悄改掉。
	for rarity: int in PBUnit.Rarity.size():
		assert_gt(_table.of_rarity(rarity as PBUnit.Rarity).size(), 0, "稀有度 %d 一个角色都没有" % rarity)


func test_the_top_rarity_stays_scarce() -> void:
	# §08：USR 是稀有度阶梯的顶。角色太多会让「抽到 USR」失去分量，
	# 太少则同一个 USR 反复重复、迅速升满星。
	var usr: int = _table.of_rarity(PBUnit.Rarity.USR).size()
	assert_between(usr, 2, 5, "USR 角色数应该少而不空")


func test_ids_and_name_keys_are_wired() -> void:
	# §14 铁律 5：代码里不出现角色名，一律走 id + name_key。
	# name_key 空掉的话，接语言表那天会静默显示成空白。
	for character: PBCharacter in _table.all():
		assert_ne(character.id, &"", "有角色缺 id")
		assert_ne(character.name_key, "", "%s 缺 name_key" % character.id)
		assert_eq(_table.by_id(character.id), character, "%s 按 id 查不回自己" % character.id)


func test_no_character_name_leaks_into_src() -> void:
	# §14 铁律 5 的**执行**：换皮 = 改表，`src/` 一行不动。
	# 只要有一个 id 出现在 src/ 里，那条铁律就已经破了。
	#
	# 这条测试自己就抓出了一条真的（见 KNOWN_LEAKS）—— 以前没有角色表，
	# 这种泄漏根本无从发现。
	var offenders := PackedStringArray()
	for character: PBCharacter in _table.all():
		if character.id in KNOWN_LEAKS:
			continue
		if _src_mentions(String(character.id)):
			offenders.append(String(character.id))
	assert_eq(String(", ").join(offenders), "", "这些角色 id 出现在了 src/ 里，换皮就不再是纯改表")


func test_the_known_leaks_are_still_actually_leaking() -> void:
	# 豁免名单必须会**过期**。债还掉之后这条会红，提醒把名字从名单里删掉 ——
	# 否则豁免名单会变成一张只增不减、越来越没人看的清单。
	for leaked: StringName in KNOWN_LEAKS:
		assert_not_null(_table.by_id(leaked), "%s 已不在角色表里，该从豁免名单删掉了" % leaked)
		assert_true(_src_mentions(String(leaked)), "%s 已经不泄漏了，该从豁免名单删掉了" % leaked)


func _src_mentions(needle: String) -> bool:
	return _scan_dir("res://src", needle)


func _scan_dir(dir_path: String, needle: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	for sub: String in dir.get_directories():
		if _scan_dir("%s/%s" % [dir_path, sub], needle):
			return true
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var file := FileAccess.open("%s/%s" % [dir_path, file_name], FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		if text.contains(needle):
			return true
	return false


func test_the_gacha_only_draws_from_the_real_table() -> void:
	# 装载器忘了装表的话，抽卡会静默退回合成表那副假牌。
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321
	var seen := {}
	for i: int in 400:
		var unit := PBEconomyRules.roll_gacha(1 + i % 60, 0, _cfg, rng)
		assert_not_null(unit, "抽卡不该掉空")
		assert_not_null(_table.by_id(unit.key()), "抽到了表外的卡：%s" % unit.key())
		seen[unit.key()] = true
	assert_gt(seen.size(), 20, "400 抽应该覆盖到大部分角色")
