extends GutTest
## 效果在屏幕上的两处，加施法回音（技能案 §4.4 / §4.5，M7-f）。
##
## ## 这个文件守的是「两处不许各说各的」
##
## 「暖 = 增益、冷 = 减益」这句话在图标条和战场染色两处都要用，
## 而两处各写一份的话，面板上那一格和战场上那个人迟早对同一份 buff
## 说两种颜色 —— **不报错**，只表现为「颜色好像没什么规律」。
## 所以它只有一处（[method PBBuffStrip.tinted] 和那几个常量同类）。
##
## ## 另一条是「没有 buff 时一个像素都不许变」
##
## 染色走 `modulate`，而 `modulate` 是乘上去的。空袋子必须返回**逐位相同**
## 的那个颜色 —— 差一点点的表现是「所有人看起来都有点脏」，
## 而它会被当成美术问题查很久。

const FIXED_SEED: int = 20260907

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()


func _buff(id: StringName, friendly: bool, seconds: float = 5.0) -> PBBuff:
	var out := PBBuff.new()
	out.id = id
	out.kind = PBBuff.Kind.DURATION
	out.friendly = friendly
	out.duration_seconds = seconds
	return out


func _bag_with(friendly: bool, count: int = 1) -> PBBuffBag:
	var bag := PBBuffBag.new()
	for i: int in count:
		var one := _buff(StringName("b%d" % i), friendly)
		bag.add(one, {}, 0, one.duration_ticks(_cfg), 0)
	return bag


func _strip() -> PBBuffStrip:
	var out := PBBuffStrip.new()
	add_child_autofree(out)
	return out


func _attacker(slot: int) -> PBAttacker:
	var out := PBAttacker.new()
	out.slot = slot
	out.max_hp = 100.0
	out.hp = 100.0
	out.pos = Vector2(0.3, 0.0)
	return out


func _field() -> Vector2:
	return Vector2(_cfg.field_length, _cfg.field_height)


# ── 图标条 ──────────────────────────────────────────────────────


func test_the_strip_shows_one_icon_per_live_effect() -> void:
	var strip := _strip()
	strip.show_bag(_bag_with(true, 2), 1, _cfg)
	assert_eq(strip.shown(), 2, "挂着两份就画两格")
	assert_false(strip.has_overflow(), "两份还没满，不该出现「还有」那一格")


func test_an_expired_effect_leaves_the_strip_on_its_own() -> void:
	# 过期是**查询时比 tick**，不是扫描时删（[PBBuffBag] 顶部）——
	# 所以这一条不跑清扫也必须成立。
	var strip := _strip()
	var bag := _bag_with(true, 1)
	var gone: int = bag.states()[0].until_tick + 1
	strip.show_bag(bag, gone, _cfg)
	assert_eq(strip.shown(), 0, "过期的不该还画着")


func test_a_full_strip_says_there_are_more_instead_of_lying() -> void:
	# **画满四格然后闭嘴是撒谎**：玩家看到四个图标，而他身上其实有六个。
	# 最后一格改成「还有」的记号，四格里因此只画得下三份。
	var strip := _strip()
	strip.show_bag(_bag_with(false, PBBuffBag.SLOTS), 1, _cfg)
	assert_true(strip.has_overflow(), "满了就该说还有")
	assert_eq(strip.shown(), PBBuffStrip.SLOTS - 1, "最后一格让给那个记号")


func test_the_clock_line_shrinks_as_the_effect_runs_out() -> void:
	var strip := _strip()
	var bag := _bag_with(true, 1)
	var whole: int = bag.states()[0].until_tick
	strip.show_bag(bag, 1, _cfg)
	var early: float = strip._left[0]
	strip.show_bag(bag, whole, _cfg)
	assert_lt(strip._left[0], early, "越接近到期，那条时钟线越短")
	assert_gt(strip._left[0], 0.0, "但还没到期就不该是空的")


# ── 战场上的染色 ────────────────────────────────────────────────


func test_an_empty_bag_leaves_the_colour_bit_identical() -> void:
	# **本文件的另一条正题。** `modulate` 是乘上去的，空袋子差一点点的
	# 表现是「所有人看起来都有点脏」，而它会被当成美术问题查很久。
	var base := Color(0.4, 0.6, 0.8, 1.0)
	assert_eq(PBBuffStrip.tinted(base, PBBuffBag.new(), 7), base, "没挂东西就一个像素都不动")


func test_a_buff_and_a_debuff_pull_the_colour_apart() -> void:
	var base := Color(0.5, 0.5, 0.5, 1.0)
	var warm: Color = PBBuffStrip.tinted(base, _bag_with(true), 1)
	var cool: Color = PBBuffStrip.tinted(base, _bag_with(false), 1)
	assert_ne(warm, base, "有增益就该染一层")
	assert_ne(cool, base, "有减益也是")
	assert_gt(warm.r, cool.r, "增益偏暖、减益偏冷 —— 两样长得一样等于什么都没说")


func test_a_debuff_wins_when_both_are_on() -> void:
	# 减益是更急的那一条：增益没兑现只是少赚，减益没看见是要死人的。
	var bag := PBBuffBag.new()
	var good := _buff(&"good", true)
	var bad := _buff(&"bad", false)
	bag.add(good, {}, 0, good.duration_ticks(_cfg), 0)
	bag.add(bad, {}, 0, bad.duration_ticks(_cfg), 0)
	var base := Color(0.5, 0.5, 0.5, 1.0)
	assert_eq(
		PBBuffStrip.tinted(base, bag, 1),
		PBBuffStrip.tinted(base, _bag_with(false), 1),
		"两样都有时按减益染"
	)


# ── 施法回音 ────────────────────────────────────────────────────


func _pool() -> PBSkillFxPool:
	var out := PBSkillFxPool.new()
	add_child_autofree(out)
	return out


func test_a_ring_appears_and_then_goes_away_on_its_own() -> void:
	var pool := _pool()
	assert_eq(pool.shown(), 0, "什么都没放的时候一圈都没有")
	pool.flash(Vector2(100.0, 100.0), false)
	assert_eq(pool.shown(), 1, "放了就有一圈")
	for _i: int in PBSkillFxPool.LIFE_FRAMES + 1:
		pool.step()
	assert_eq(pool.shown(), 0, "它是一次「刚才」的回音，该自己散掉")


func test_the_echo_reads_the_log_and_never_counts_one_twice() -> void:
	# **触发读的是播报，不是「谁身上有一发在飞」**：不挑目标的那一档
	# 下达和落地在同一 tick，渲染层永远抓不到那个中间状态 ——
	# 而那正是最需要回音的一档（它连落点预示圈都没有）。
	var pool := _pool()
	var book := PBBattleLog.new()
	var squad: Array[PBAttacker] = [_attacker(0)]
	book.ultimate(1, 0, true)

	pool.echo(book, squad, _field())
	assert_eq(pool.shown(), 1, "播报里新出现的那一条该变成一圈")
	pool.echo(book, squad, _field())
	assert_eq(pool.shown(), 1, "同一条不许再数一遍")

	book.ultimate(2, 0, false)
	pool.echo(book, squad, _field())
	assert_eq(pool.shown(), 2, "又放了一发就再来一圈")


func test_the_echo_ignores_a_slot_that_is_not_on_the_field() -> void:
	# 尾兽的槽位是 -1（它没有本体），而播报里照样记着它放过忍术。
	var pool := _pool()
	var book := PBBattleLog.new()
	var squad: Array[PBAttacker] = [_attacker(0)]
	book.ultimate(1, -1, false)
	pool.echo(book, squad, _field())
	assert_eq(pool.shown(), 0, "场上没有这个人就不画 —— 别在基地上凭空冒一圈")


func test_the_log_says_which_side_the_cast_landed_on() -> void:
	# 一个人现在有好几格（[method PBSkillRules.cast_at]），而播报只记了
	# 「谁放的」—— 渲染层回头去问只能问到第 0 格，
	# 于是第 1 格的治疗会被画成打人的颜色。所以这一条记在播报里。
	var book := PBBattleLog.new()
	book.ultimate(1, 0, true)
	assert_true(bool(book.entries[0]["to_ally"]), "治疗那一发要标出来")
	book.ultimate(2, 0, false)
	assert_false(bool(book.entries[1]["to_ally"]), "打人那一发不标")
