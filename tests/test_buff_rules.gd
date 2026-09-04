extends GutTest
## 效果的**词汇表与数据规则**（[PBBuffRules]，M7-a）。
##
## 和 `test_buff.gd` 的分工，与 `test_bond.gd` / `test_bond_data.gd` 同一条线：
## 那边测**机制**（bag 怎么合计、怎么过期、怎么顶槽位），
## 这边测**一份数据合不合法、数值怎么按等级长**。
##
## 这一层的错全部是静默的：拼错的键什么都不发生，只写成长不写基数会
## 静默变成「1 级时是 0」—— 所以断言直接压在「必须被拦下来」上。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func _lasting(id: StringName, values: Dictionary, seconds: float = 5.0) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = seconds
	buff.mods = values
	return buff


# ── 数值按等级长（决策 7）──────────────────────────────────────


func test_the_same_buff_is_stronger_from_a_higher_level_caster() -> void:
	# 定值不行：一个回 120 血的技能在第 5 波很强、第 30 波等于没有，
	# 而它不报错，只表现为「这个角色后期没用」。
	var buff := _lasting(&"cure", {PBBuffRules.HEAL: 80.0})
	buff.mods_growth = {PBBuffRules.HEAL: 14.0}
	assert_eq(PBBuffRules.resolve(buff, 1)[PBBuffRules.HEAL], 80.0, "1 级取基数")
	assert_eq(PBBuffRules.resolve(buff, 10)[PBBuffRules.HEAL], 80.0 + 14.0 * 9.0, "每级加一份")
	# 没有等级的施法者（尾兽、敌人）传 1 —— 不需要为它们分一条支路。
	assert_eq(PBBuffRules.resolve(buff, 0)[PBBuffRules.HEAL], 80.0, "0 级按 1 级算")


func test_a_key_without_growth_simply_does_not_grow() -> void:
	# 「这一项不随等级长」是合法的，率型键通常都这样 —— 它无量纲，
	# 不需要跟难度曲线走。
	var buff := _lasting(&"boost", {PBBuffRules.DAMAGE_SCALE: 1.3})
	assert_eq(PBBuffRules.resolve(buff, 20)[PBBuffRules.DAMAGE_SCALE], 1.3, "没配成长就不长")


# ── 数据校验 ────────────────────────────────────────────────────


func test_a_misspelled_key_is_rejected_instead_of_ignored() -> void:
	# 拼错了不会报错、只是什么都不发生 —— 那种 bug 从现象反推不出来。
	var buff := _lasting(&"oops", {&"damage_scal": 1.3})
	assert_ne(PBBuffRules.validate(buff), "", "不认识的键要被拦下来")


func test_growth_without_a_base_is_rejected() -> void:
	# 只写成长不写基数会静默生效成「1 级时是 0」，而写的人本意是「1 级时就有」。
	var buff := _lasting(&"oops", {PBBuffRules.HEAL: 10.0})
	buff.mods_growth = {PBBuffRules.MANA: 3.0}
	assert_ne(PBBuffRules.validate(buff), "", "只写成长不写基数要被拦下来")
	buff.mods_growth = {PBBuffRules.HEAL: 3.0}
	assert_eq(PBBuffRules.validate(buff), "", "配对了就该放行")


func test_a_lasting_buff_without_a_window_is_rejected() -> void:
	var buff := _lasting(&"oops", {PBBuffRules.DAMAGE_SCALE: 1.3}, 0.0)
	assert_ne(PBBuffRules.validate(buff), "", "持续型没时长要被拦下来")


func test_a_window_shorter_than_a_tick_is_still_one_tick() -> void:
	# 写 0.01 秒的人想要的是「很短」，不是「没有」—— 而 0 tick 的窗口
	# 等于这个 buff 不存在，且不报错。
	var buff := _lasting(&"blink", {PBBuffRules.DAMAGE_SCALE: 2.0}, 0.01)
	assert_eq(buff.duration_ticks(_cfg), 1, "再短也至少一个 tick")
	assert_eq(buff.period_ticks(_cfg), 0, "不是周期型就没有周期")
	buff.kind = PBBuff.Kind.PERIODIC
	buff.period_seconds = 0.5
	assert_eq(buff.period_ticks(_cfg), _cfg.tick_rate / 2, "半秒就是半个 tick_rate")


func test_every_key_in_the_vocabulary_has_a_neutral_and_a_fold() -> void:
	# [constant PBBuffRules.ALL] 里的键 = **已经接上读点的键**。
	# 这一条顺带保证没有键漏配「率还是量」—— 漏配成率型的量型键
	# 会让「没有 buff 时回血变成 1 点」，而漏配成量型的率型键
	# 会让「没有 buff 时伤害变成 0」。后者会立刻发现，前者不会。
	for key: StringName in PBBuffRules.ALL:
		assert_true(PBBuffRules.is_known(key), "%s 该认得" % key)
		var want: float = 1.0 if PBBuffRules.is_scale(key) else 0.0
		assert_eq(PBBuffRules.neutral(key), want, "%s 的中性值" % key)
