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

## 已经清掉的角色名。**这条名单只增不减，它防的是复发。**
##
## §07 原本把两个角色的名字写死进了机制名，是 M-1 就欠下的债：
## `tsunade_income` → 现在的 `kill_drop_income`（击杀掉落流），
## `kakuzu_*` → 现在的 `economy_slot_*`（经济位，§07 自己的词汇）。
## 换皮之后那些会变成「以一个不存在的角色命名的机制」。
##
## 债在 M2-a2 之后单独清了一次（动了 CSV 列名与报表表头，所以没有
## 混进别的改动 —— 混进去会让历史扫描结果对不上号）。
##
## **`kakuzu` 不在角色表里，所以下面按表扫描的那条测试永远抓不到它。**
## 这份名单就是补那个洞的：无论角色表里有没有，这些词都不许回到 `src/`。
const RETIRED_NAMES: Array[String] = ["tsunade", "kakuzu", "纲手", "角都"]

var _table: PBCharacterTable
var _cfg: PBSimConfig


func before_all() -> void:
	_table = PBCharacterLoader.load_from(PBCharacterLoader.DIR)
	_cfg = PBGameData.config()


func test_the_data_directory_actually_loads() -> void:
	assert_gt(_table.size(), 0, "data/characters/ 里应该装得出角色")
	# **49 = 原版名册**（M10-b）：文档正表 45 人（两张佐助并成一张 → 44）
	# 加上只在羁绊里点名的 5 个。数字写死是有意的 —— 名册是照抄的，
	# 少一个人就是漏抄了一行，而漏抄不报错（那一组羁绊只是永远凑不齐）。
	assert_eq(_table.size(), 56, "名册该照 data/roster.tsv 铺满 56 个角色")
	assert_gte(_table.size(), 40, "§09 的「PC 首发 40+ 角色」")


func test_every_element_can_fill_the_starting_bench() -> void:
	# 出战席初始 4 格。某一系的角色数少于 4，「这一波上满克制系」
	# 就是做不到的事，§03 的克制加成会被系统性低估。
	#
	# **铺的是 [constant PBElement.PICKABLE] 不是 `Type.size()`**（M12-a）：
	# 仙不是一个「该有四个人」的系，它是三个特定角色身上的东西，
	# 照枚举个数铺的话这条会因为「仙系只有两个人」而红，
	# 而红的是一条不该存在的要求。
	for element: int in PBElement.PICKABLE:
		var count: int = 0
		for character: PBCharacter in _table.all():
			if int(character.element) == element:
				count += 1
		assert_gte(count, _cfg.deploy_slots_base, "属性 %d 的角色数应够填满初始出战席" % element)


func test_no_element_is_over_represented() -> void:
	# 上面那条只管下限。**上限同样要管** —— 物理超配就会破 §03 的
	# 「纯物理 < 五系的 70%」，实测 20% 占比即破线。
	# **±2% 放宽到 ±7%**（M10-b，玩家定的）。旧的那个容差配的是一张
	# **我们自己造的**六系均分表（各 5 个），而那份均分不是设计要求 ——
	# 它是为了让此前的扫描结论（GROWTH 1.10、装备 300、经济位曲线）
	# 继续成立而人为摆出来的。
	#
	# 照抄原版名册之后分布就是原版的：风 10 / 土 10 / 物理 11 / 火 7 /
	# 水 6 / 雷 5，最大偏差约 6 个百分点。**旧基线因此作废**，
	# 而那笔账 M9-e/f 之后本来就已经欠着了。
	#
	# 上限那一半仍然要管：物理 22.4% 已经贴着 §03 那条实测破线（20% 即破），
	# 而「纯物理队 < 五系队」由 `test_element.gd` 直接量，红了去看那一条。
	var counts := {}
	for character: PBCharacter in _table.all():
		counts[int(character.element)] = int(counts.get(int(character.element), 0)) + 1
	# 均分只对 [constant PBElement.PICKABLE] 那六系成立（M12-a）——
	# 仙不参与均分，它按角色给，不按系铺。
	var share: float = 1.0 / float(PBElement.PICKABLE.size())
	for element: int in PBElement.PICKABLE:
		var got: float = float(counts.get(element, 0)) / float(_table.size())
		assert_almost_eq(got, share, 0.07, "属性 %d 的占比偏离均分太多（%.1f%%）" % [element, got * 100.0])


func test_every_rarity_has_someone() -> void:
	# 抽卡是「掷稀有度 → 在该稀有度里取一个」。某一档空了就要走退化路径，
	# 而那条路径会把实际的稀有度分布悄悄改掉。
	for rarity: int in PBUnit.Rarity.size():
		assert_gt(_table.of_rarity(rarity as PBUnit.Rarity).size(), 0, "稀有度 %d 一个角色都没有" % rarity)


func test_the_top_rarity_stays_scarce() -> void:
	# §08：顶档是稀有度阶梯的头。角色太多会让「抽到顶档」失去分量，
	# 太少则同一张反复重复。
	#
	# **今天只有下界，上界故意还没加**（M10-a）。
	#
	# 四档并成三档之后，原来的 USR 三张并进了 SSR —— 于是顶档变成
	# **11/30，是三档里最大的一档**（R 9、SR 10、SSR 11）。那不是这次
	# 合并造成的，是它把一直存在的头重脚轻**露了出来**：老断言只管
	# 「USR 在 2~5 之间」，从来没人量过 SSR 占多少。
	#
	# 现在加一条 30% 的上界，红的会是「名册还没照文档重排」，
	# 而不是「顶档太多了」—— 那是把测试写成迁就实现的反面：
	# **写一条今天必然红的断言，等于把自检契约变成一句空话。**
	# 上界跟着 M10-b 的名册重铺一起进来（原版是 8 SSR / 45 人 = 17.8%）。
	var top: int = _table.of_rarity(PBUnit.Rarity.SSR).size()
	assert_gte(top, 2, "顶档角色太少，同一张会反复重复")


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
	# 这条测试写出来的第一次就抓到一条真的（`tsunade` 写死在 §07 的收入流名里）——
	# 以前没有角色表，这种泄漏根本无从发现。那笔债已经清掉，见 [constant RETIRED_NAMES]。
	var offenders := PackedStringArray()
	for character: PBCharacter in _table.all():
		if _src_mentions(String(character.id)):
			offenders.append(String(character.id))
	assert_eq(String(", ").join(offenders), "", "这些角色 id 出现在了 src/ 里，换皮就不再是纯改表")


func test_retired_character_names_never_come_back() -> void:
	# **上面那条按角色表扫描，所以它有个盲区**：不在表里的角色名它看不见。
	# §07 的经济位就是这种情况 —— 那张卡在原版里叫「角都」，
	# 但它在本案里不是一个可抽的角色，永远不会进 data/characters/。
	#
	# 所以清掉的名字要单独列一份，中英文都列（注释里也不许留）。
	var offenders := PackedStringArray()
	for name: String in RETIRED_NAMES:
		if _src_mentions(name):
			offenders.append(name)
	assert_eq(String(", ").join(offenders), "", "已清掉的角色名又回到了 src/ 里")


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
