extends GutTest
## `data/beasts/` 的真尾兽表校验（§11 的九只）。M3-d。
##
## 和 `test_beast.gd` 分开：那边测**机制**，这边测**数据本身**。
## 两者的失效模式不同 —— 机制写错是「所有尾兽一起错」，
## 数据写错是「某一只悄悄变成另一只的复制品」。
##
## 这个文件里最要紧的两条是 §11 的那段警告：
##
## > 七尾必须存在……同理，六尾的「重置全体大招 CD」是连招流的开关。
## > **这两只是机制型尾兽，不能被数值型挤掉。**
##
## 代码守得住的部分是「它们在数据里确实是机制型，而且确实有一只纯数值型
## 可以拿来做对照」。它们在实战里排第几只能靠扫描量。

var _cfg: PBSimConfig
var _table: PBBeastTable


func before_each() -> void:
	_cfg = PBGameData.config()
	_table = _cfg.beasts


func test_the_data_directory_actually_loads() -> void:
	assert_eq(_table.size(), PBBeastLoader.SPEC_BEASTS, "§11 说的九只应该一只不缺")


func test_every_beast_has_an_id_and_a_name_key() -> void:
	# 显示名走语言表，代码里只出现 id（§14 铁律 5）。少一个 name_key
	# 的表现是界面上直接印出 id，不报错。
	for beast: PBBeast in _table.all():
		assert_ne(beast.id, &"", "每只尾兽都要有 id")
		assert_string_starts_with(beast.name_key, "beast.", "name_key 该走 beast.* 命名空间")


func test_every_beast_does_something() -> void:
	# 一只光环为 0、大招也毫无后果的尾兽是个陷阱选项：玩家开局选了它，
	# 整局什么都不会发生，而且**不报任何错**。
	for beast: PBBeast in _table.all():
		var has_aura: bool = (
			beast.aura_power != 0.0
			or beast.aura_def_reduction != 0.0
			or beast.aura_ultimate_cd_scale != 1.0
		)
		assert_true(has_aura or beast.has_ultimate(), "%s 至少要有光环或大招其中一半是活的" % beast.id)


func test_the_two_mechanism_beasts_are_really_mechanism_beasts() -> void:
	# §11 点名不能被挤掉的两只。判据不是「它们很强」，
	# 而是**它们的价值不来自伤害数字** —— 这两只的大招伤害都该是 0。
	var gather: PBBeast = _find(func(b: PBBeast) -> bool: return b.ultimate_gather)
	var reset: PBBeast = _find(func(b: PBBeast) -> bool: return b.ultimate_reset_cooldowns)
	assert_not_null(gather, "必须有一只带纯聚拢大招（§11 的七尾）")
	assert_not_null(reset, "必须有一只能重置全体大招 CD（§11 的六尾）")
	assert_eq(gather.ultimate_damage_seconds, 0.0, "聚拢型的价值不该来自伤害")
	assert_eq(reset.ultimate_damage_seconds, 0.0, "重置型的价值不该来自伤害")


func test_there_is_a_pure_numbers_beast_to_measure_them_against() -> void:
	# **这条是上一条的仪器。** §11 怕的是「数值型把机制型挤掉」，
	# 而那件事要量得出来，表里就得有一只**只有数值**的尾兽做对照。
	#
	# 它正好是八尾：光环全体 +12%，大招「召唤分身承伤」在当前模型下恒为 0
	# （敌人不还手，见 [member PBBeast.aura_def_reduction] 旁边的说明）。
	# 扫描里如果它排在七尾、六尾前面，要动的是数值不是机制。
	var pure: PBBeast = _find(
		func(b: PBBeast) -> bool: return b.aura_power > 0.0 and not b.has_ultimate()
	)
	assert_not_null(pure, "要有一只纯光环尾兽当数值型的对照")
	assert_eq(pure.aura_element, PBBeast.ANY_ELEMENT, "对照组的光环该是全体的，没有筛选")


func test_the_defensive_effects_are_honestly_worth_zero() -> void:
	# **这条钉的是一个已知的模型缺口，不是一个愿望。**
	#
	# §11 的一尾光环是「全体防御 +12%」，八尾大招是「召唤分身承伤」——
	# 当前战斗模型里**己方单位不会死、敌人也不还手**，两者都没有作用对象。
	#
	# 一尾那一份照实填进 [member PBBeast.aura_def_reduction]（它在基地减伤上
	# 确实是可表达的，只是当前没有来源会用到它）；八尾那一份直接就是「没有大招」。
	# **不把防御效果折算成伤害** —— 折算了就等于凭空发明一份收益，
	# 而调参的人会拿着那份收益去定价（§10 在装备上定下的同一条规矩）。
	var defensive: PBBeast = _find(func(b: PBBeast) -> bool: return b.aura_def_reduction > 0.0)
	assert_not_null(defensive, "该有一只带全体防御光环的（§11 的一尾）")
	assert_eq(defensive.aura_power, 0.0, "防御光环不该被折算成伤害加成")
	assert_true(defensive.has_ultimate(), "但它的另一半（全屏减速）必须是活的，否则整只是废的")


func test_the_element_beasts_line_up_with_the_counter_ring() -> void:
	# §11 有两只属性专精（三尾水、五尾土）。它们是尾兽与 §03 属性系统的接口：
	# 选了就更想凑同系，而同系只在五波轮转里的一波吃到克制。
	# 光环无差别的话这个接口就没了，「选哪只」退化成纯数值比大小。
	var seen: Dictionary = {}
	for beast: PBBeast in _table.all():
		if beast.aura_element == PBBeast.ANY_ELEMENT:
			continue
		assert_true(
			beast.aura_element >= 0 and beast.aura_element <= int(PBElement.Type.PHYSICAL),
			"%s 的光环属性越界了" % beast.id
		)
		assert_false(seen.has(beast.aura_element), "两只尾兽专精同一个属性会互相挤掉")
		seen[beast.aura_element] = true
	assert_gte(seen.size(), 2, "至少要有两只属性专精尾兽")


func test_every_ultimate_would_actually_come_round_within_a_run() -> void:
	# §11 的 75 秒 ≈ 每 2 波一次，「让玩家必须选择在哪一波交底牌」。
	# 冷却写歪成几百秒的话，那只尾兽整局放不出一发，而症状只是「它好像很弱」。
	for beast: PBBeast in _table.all():
		if not beast.has_ultimate():
			continue
		var seconds: float = beast.ultimate_cooldown_seconds
		if seconds <= 0.0:
			seconds = _cfg.beast_ultimate_cooldown_seconds
		assert_lte(seconds, 90.0, "%s 的大招冷却超出了 §11 的 60–90 区间" % beast.id)
		assert_gte(seconds, 60.0, "%s 的大招冷却低于 §11 的 60–90 区间" % beast.id)


func test_named_auras_point_at_characters_that_exist() -> void:
	# 九尾的「专属强化」按角色 id 点名。角色 id 改了而这里没跟着改的话，
	# 那只尾兽的光环会静默地对谁都不生效 —— 和羁绊成员名单同一种失效方式。
	for beast: PBBeast in _table.all():
		for member_id: StringName in beast.aura_member_ids:
			assert_not_null(
				_cfg.characters.by_id(member_id), "%s 点名了不存在的角色 %s" % [beast.id, member_id]
			)


func test_the_running_game_installs_the_real_beast_table() -> void:
	# 漏装的后果不是报错，是**表里一只都没有，`--beast` 指定哪只都当没带**。
	# 跑出来是对照组的数字，而对照组的数字看上去完全正常。
	assert_gt(PBGameData.config().beasts.size(), 0, "游戏入口该装上真尾兽表")
	assert_eq(PBSimConfig.new().beasts.size(), 0, "裸配置该是空表 —— 那是对照组，不是替身曲线")


func test_no_beast_name_leaks_into_src() -> void:
	# §14 铁律 5：代码里不出现尾兽名，一律走 id + name_key。
	var names: Array[String] = [
		"守鹤", "又旅", "矶抚", "孙悟空", "穆王", "犀犬", "重明", "牛鬼", "九喇嘛"
	]
	for path: String in _gd_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		for beast_name: String in names:
			assert_false(text.contains(beast_name), "%s 里出现了尾兽名「%s」" % [path, beast_name])


## 表里第一只满足条件的。找不到返回 null。
func _find(predicate: Callable) -> PBBeast:
	for beast: PBBeast in _table.all():
		if predicate.call(beast):
			return beast
	return null


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [root, sub]))
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append("%s/%s" % [root, file_name])
	return out
