extends GutTest
## 选尾兽与升尾兽这两条原语（§11，M3.5-f）。
##
## §11 把「带哪只尾兽」定成**整局唯一一次、且不可撤销**的决策。
## 那条性质只能在规则层守住 —— 界面上少画一个「换一只」的按钮不算数，
## 下一个人加个入口就没了。
##
## 尾兽自己的机制（光环、大招、等级放大什么）在 `test_beast.gd`，
## 数据（九只都在、名字不泄漏进 src）在 `test_beast_data.gd`。
## 这里只管「这一局带上了谁、花了多少钱」。

var _cfg: PBSimConfig


func before_each() -> void:
	# 走真表：`PBSimConfig.new()` 的默认配置里没有尾兽表（那是对拍用的），
	# 拿它测「选得了哪只」等于什么都没测。
	_cfg = PBGameData.config()


func test_choosing_a_beast_happens_exactly_once() -> void:
	# §11 把「选哪只」定成整局唯一一次的决策。允许中途换的话它就退化成
	# 「哪一波用哪只」—— 不用取舍，九只全都能用上，决策本身没了。
	var state := PBRunSim.new_state(_cfg)
	var ids := _cfg.beasts.ids()
	assert_true(PBShopRules.choose_beast(state, ids[0], _cfg), "开局该选得了")
	assert_eq(state.beast_id, ids[0], "选了就该记下来")
	assert_eq(state.beast_level, 1, "刚选定该是 Lv1")
	assert_false(PBShopRules.choose_beast(state, ids[1], _cfg), "选过之后不该换得了")
	assert_eq(state.beast_id, ids[0], "被拒之后原来那只不该被动过")


func test_an_unknown_beast_id_is_refused() -> void:
	# 静默按「不带」跑总好过静默按「随便哪只」跑：前者数字明显偏低，
	# 一眼看得出不对（见 [method PBStrategy.choose_beast]）。
	var state := PBRunSim.new_state(_cfg)
	assert_false(PBShopRules.choose_beast(state, &"no_such_beast", _cfg), "表里没有的该被拒")
	assert_eq(state.beast_id, &"", "而且不该留下半个状态")


func test_upgrading_a_beast_charges_and_stops_at_the_cap() -> void:
	# 指令卡上的「升级尾兽」走这条原语。M3.5-e 那会儿它压根没接线 ——
	# 那条指令掉进了「买科技」的兜底分支，点下去纯粹没反应。
	var state := PBRunSim.new_state(_cfg)
	PBShopRules.choose_beast(state, _cfg.beasts.ids()[0], _cfg)
	state.gold = 0
	assert_false(PBShopRules.upgrade_beast(state, _cfg), "没钱该升不动")
	state.gold = 10000000
	while PBShopRules.upgrade_beast(state, _cfg):
		pass
	assert_eq(state.beast_level, _cfg.beast_level_max, "钱管够就该一路升到上限")
	assert_lt(state.gold, 10000000, "升级要真的花钱")


func test_no_beast_means_no_upgrade() -> void:
	var state := PBRunSim.new_state(_cfg)
	state.gold = 10000
	assert_false(PBShopRules.upgrade_beast(state, _cfg), "没带尾兽时没有东西可升")
	assert_eq(state.gold, 10000, "而且不该扣钱")
