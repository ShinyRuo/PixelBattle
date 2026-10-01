extends GutTest
## 敌人的晕眩与致盲（M12-c2）。

## ## 这个文件守的是什么
##
## 两个键都只回答一句话：**这个敌人这一下打不打得成**。
## 两者故意不同档：晕眩连手都抬不起来（冷却也不走），
## 致盲是手抬了、冷却也走了，只是打空。
##
## 三条不肯让步的：
##
## 1. **两个读点都只有一处** —— 近战与远程在分岔之后各判一次的
##    表现是「定住了还会放箭」/「只有近战会打空」
## 2. **没被致盲时一次骰子都不掷**（同 M10-c）
## 3. 真表里六份「禁锢」必须两半都停 —— 只补一处的表现是
##    「影子模仿术定得住、追牙之术定不住」，而两边配置看起来都对

const FIXED_SEED: int = 20260912

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


# ── 晕眩：定住的另一半（M12-c2）──────────────────────────────


func test_a_stunned_enemy_cannot_swing_even_though_it_is_standing_right_there() -> void:
	# **这是六份「禁锢」型效果一直缺的那一半。** 在它之前它们全都只写
	# `enemy_speed_scale=0`，而 `data/buffs.tsv` 里就记着那条降级：
	# 「停的是走位，敌人站在原地照样出手」—— 原版写的是
	# 「无法移动**攻击和施法**」。
	var enemy := _enemy()
	enemy.next_shot_at = 0
	assert_true(enemy.ready_to_fire(0), "没挂效果时该出得了手")
	_hang(enemy, _lasting(&"hold", {PBBuffRules.STUN: 1.0}, 2.0), 0)
	assert_false(enemy.ready_to_fire(0), "被定住就不许出手")


func test_the_stun_wears_off_on_its_own() -> void:
	# 过期是**查询时比 tick**（M7-a），不是扫描时删 —— 所以不用推进什么，
	# 问一个足够晚的 tick 就行。
	var enemy := _enemy()
	enemy.next_shot_at = 0
	var stun := _lasting(&"hold", {PBBuffRules.STUN: 1.0}, 2.0)
	_hang(enemy, stun, 0)
	var after: int = stun.duration_ticks(_cfg) + 1
	assert_true(enemy.ready_to_fire(after), "过期之后该能打了")


func test_being_stunned_does_not_bank_up_shots() -> void:
	# **被定住那几 tick 冷却不推进** —— [member PBEnemy.next_shot_at] 只在
	# [method PBEnemy.on_fired] 里往前走。推进的话，一段 2 秒的禁锢结束那一瞬
	# 敌人会把攒下的几下一起打出来，而那正好是玩家花一个技能买来的
	# 那段安全窗口。
	var enemy := _enemy()
	enemy.attack_interval = 10
	enemy.next_shot_at = 0
	_hang(enemy, _lasting(&"hold", {PBBuffRules.STUN: 1.0}, 1.0), 0)
	assert_eq(enemy.next_shot_at, 0, "定身期间那个数一步都不该动")


func test_real_roots_and_stuns_control_movement_and_attacks_independently() -> void:
	# 定身只管移动；禁止攻击显式配置 stun 或 disarm，后者仍允许主动施法。
	var table := PBSkillLoader.table()
	var checked: int = 0
	for id: StringName in table.ids():
		for buff: PBBuff in table.by_id(id).on_hit:
			if float(buff.mods.get(PBBuffRules.ENEMY_SPEED_SCALE, 1.0)) != 0.0:
				continue
			var enemy := _enemy()
			_hang(enemy, buff, 0)
			enemy.speed = 0.1
			var at := enemy.pos()
			enemy.march_to(Vector2.ZERO, 1.0, 0)
			assert_eq(enemy.pos(), at, "定身必须禁止移动")
			var stunned: bool = float(buff.mods.get(PBBuffRules.STUN, 0.0)) > 0.0
			var disarmed: bool = float(buff.mods.get(PBBuffRules.DISARM, 0.0)) > 0.0
			assert_eq(enemy.ready_to_fire(0), not (stunned or disarmed), "定身和禁止攻击独立")
			checked += 1
	assert_gt(checked, 0, "真表里一份禁锢都没有的话，上面什么都没量")


# ── 致盲：打得出手，但打空 ────────────────────────────────────


func test_a_blinded_enemy_misses_some_of_its_swings() -> void:
	var enemy := _enemy()
	_hang(enemy, _lasting(&"dark", {PBBuffRules.ENEMY_HIT_SCALE: 0.5}, 5.0), 0)
	var missed: int = 0
	for i: int in 400:
		if PBBuffRules.misses(enemy, 0, _rng):
			missed += 1
	assert_between(missed, 150, 250, "一半上下该打空（400 次里）")


func test_two_blinds_multiply_instead_of_adding_up() -> void:
	# **率型是连乘的**（[constant PBBuffRules.SCALES]）。写成「丢失率」相加的话
	# 两份 50% 就是 100% 全空，而那不是人会预期的叠加方式。
	var enemy := _enemy()
	_hang(enemy, _lasting(&"a", {PBBuffRules.ENEMY_HIT_SCALE: 0.5}, 5.0), 0)
	_hang(enemy, _lasting(&"b", {PBBuffRules.ENEMY_HIT_SCALE: 0.5}, 5.0), 0)
	assert_almost_eq(enemy.buffs.amount(PBBuffRules.ENEMY_HIT_SCALE, 0), 0.25, 0.0001, "两份该连乘")


func test_nobody_misses_without_a_blind_and_no_dice_are_rolled() -> void:
	# 没被致盲时命中率恰好是 1.0，**一次都不掷** —— 同
	# [method PBCritRules.strike] 顶上那条：掷了就算打中了也已经拨动了那条流。
	var enemy := _enemy()
	var before: int = _rng.state
	assert_false(PBBuffRules.misses(enemy, 0, _rng), "没致盲就不该打空")
	assert_eq(_rng.state, before, "没致盲就一步都不许走")


func test_without_dice_nobody_ever_misses() -> void:
	# 批量扫描、探测不给 rng —— 那一路必须和没有致盲这件事完全一样。
	var enemy := _enemy()
	_hang(enemy, _lasting(&"dark", {PBBuffRules.ENEMY_HIT_SCALE: 0.0}, 5.0), 0)
	assert_false(PBBuffRules.misses(enemy, 0, null), "不给骰子就照常打中")


func test_missing_is_decided_before_melee_and_ranged_split() -> void:
	# 近战当场见血、远程发一发子弹 —— 分岔之后各判一次的表现是
	# 「只有近战会打空」，而它不报错。判据是**扫源码**：那一句得排在
	# 分岔之前，也就是 `misses` 只出现一次。
	var text := FileAccess.get_file_as_string("res://src/core/sim/battle_sim.gd")
	assert_ne(text, "", "读得到 battle_sim.gd")
	assert_eq(text.split("PBBuffRules.misses(").size() - 1, 1, "致盲只许判一处")


## 一个站在场上、血量写死的敌人。
func _enemy() -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = 100.0
	out.hp = 100.0
	out.speed = 0.01
	out.distance = 1.0
	return out


## 一份持续型效果（不带周期载荷）。
func _lasting(id: StringName, values: Dictionary, seconds: float) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = seconds
	buff.mods = values
	return buff


## 把一份效果按它自己的时长挂到 [param enemy] 身上。
func _hang(enemy: PBEnemy, buff: PBBuff, at_tick: int) -> void:
	enemy.buffs.add(
		buff,
		PBBuffRules.resolve(buff, 1),
		at_tick,
		buff.duration_ticks(_cfg),
		buff.period_ticks(_cfg)
	)
