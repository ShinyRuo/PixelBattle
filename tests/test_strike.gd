extends GutTest
## 普攻的落点与触发型羁绊（§7 的 B02 / B05 / B10 / B15）。M10-d。
##
## ## 这个文件守的是什么
##
## 触发型和 M10-c 那三组光环的区别不在数值，在**它只在某件事发生的那一刻
## 才生效**。而「那件事」在这个项目里有好几个落点：一次命中可以来自近战、
## 来自范围攻击、来自一发飞了几 tick 的子弹；一次阵亡可以来自敌人近战、
## 也可以来自敌人的子弹。
##
## **漏一个落点的表现全是「这个羁绊有时候不生效」**，而它不报错。
## 所以下面一半的断言不是「效果对不对」，是「**每一条路都走到了**」。

const STRIKE_PATH := "res://src/core/rules/strike_rules.gd"
const SHOT_PATH := "res://src/core/rules/shot_rules.gd"
const SIM_PATH := "res://src/core/sim/battle_sim.gd"

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20261010


# ── 空着 = 一字不差 ───────────────────────────────────────────


func test_nothing_happens_when_no_bond_grants_a_trigger() -> void:
	# 四个字段全默认 0，所以没有任何羁绊配它们时整局一位都不动 ——
	# 同 M3.5-f 装备那条「空着 = 一字不差」、M7-g 技能那条。
	var attacker := _striker()
	assert_eq(attacker.crit_on_hit, 0.0, "命中后提暴击默认关")
	assert_eq(attacker.splash_damage, 0.0, "溅射默认关")
	assert_eq(attacker.heavy_bonus, 0.0, "打高血默认关")
	assert_eq(attacker.revives_max, 0, "重生默认没有")

	var enemies := _pack(4)
	var out := PBCombatOutcome.new()
	var before: float = enemies[1].hp
	PBStrikeRules.land(attacker, enemies[0], 10.0, false, enemies, _cfg, 0, null, out)
	assert_eq(enemies[1].hp, before, "没有溅射时旁边那个一点血都不该掉")
	assert_eq(attacker.buffs.count(0), 0, "也不该给自己挂上任何东西")


# ── 阵亡时：重生 ──────────────────────────────────────────────


func test_the_carrier_gets_back_up_once_and_only_once() -> void:
	var attacker := _striker()
	attacker.revives_max = 1
	attacker.revive()
	assert_false(attacker.take_damage(999.0, 0), "第一次打死该被重生接住")
	assert_true(attacker.alive, "他还站着")
	assert_almost_eq(
		attacker.hp, attacker.max_hp * PBAttacker.REVIVE_FRACTION, 0.001, "带着部分血回来"
	)
	assert_true(attacker.take_damage(999.0, 0), "第二次就真死了")
	assert_false(attacker.alive, "这次躺下了")


func test_the_revive_counter_is_refilled_every_wave() -> void:
	# **`revives` 和 `revives_max` 必须是两个字段。** 攻击者对象会跨波、
	# 跨探测复用，只有一个的话「上一波已经用掉了」会漏进下一波，
	# 表现是「第二波起就不复活了」—— 而它不报错。
	var attacker := _striker()
	attacker.revives_max = 1
	attacker.revive()
	attacker.take_damage(999.0, 0)
	assert_eq(attacker.revives, 0, "这一波用掉了")
	attacker.revive()
	assert_eq(attacker.revives, 1, "下一波该重新给")


func test_a_clone_carries_the_quota_but_not_the_spent_counter() -> void:
	# 悬崖二分会 [method PBAttacker.clone] 出几十份反复跑。
	# 复制品是「一个刚站起来的他」，同 `hp` 取 `max_hp` 那一条。
	var attacker := _striker()
	attacker.revives_max = 1
	attacker.revive()
	attacker.take_damage(999.0, 0)
	var copy := attacker.clone()
	assert_eq(copy.revives_max, 1, "配额要跟过来")
	copy.revive()
	assert_eq(copy.revives, 1, "而且是满的 —— 探测量的不能是一个已经用掉的他")


func test_both_ways_of_dying_go_through_the_same_gate() -> void:
	# **这条是这一组里最值钱的一条。** 己方阵亡有两个落点：
	# 近战那一记（[PBBattleSim]）和敌人的子弹命中（[PBShotRules]），
	# 两处都写着 `if take_damage(): allies_lost += 1`。
	# 各判一次重生的话，漏掉的那一处表现是「被子弹打死就复活不了」。
	#
	# 判据不是跑一整场，是**扫源码**：那两处不许自己判重生。
	# 跑场景的话，两条路要凑齐的前置条件（敌人有没有子弹、谁先咬到谁）
	# 比这条断言本身还难保证。
	for path: String in [SIM_PATH, SHOT_PATH]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "读得到 %s" % path)
		assert_false(text.contains("revives"), "%s 不该自己判重生，那是 take_damage 里面的事" % path)


# ── 命中时：三个触发 ──────────────────────────────────────────


func test_a_splash_carrier_also_hurts_the_ones_standing_next_to_the_target() -> void:
	var attacker := _striker()
	attacker.splash_damage = 0.5
	var enemies := _pack(3, 0.01)
	var out := PBCombatOutcome.new()
	var neighbour: float = enemies[1].hp
	PBStrikeRules.land(attacker, enemies[0], 100.0, false, enemies, _cfg, 0, null, out)
	assert_lt(enemies[1].hp, neighbour, "贴着站的那个该跟着掉血")
	assert_almost_eq(neighbour - enemies[1].hp, 50.0, 0.001, "掉的是主伤害的五成")


func test_the_splash_does_not_reach_across_the_field() -> void:
	# 半径放大到大招那个量级的话，一次普攻会盖住半个战场 —— 而 §02
	# 把「一次罩住多少人」定为 AOE 的全部价值，那等于白送一个 AOE。
	var attacker := _striker()
	attacker.splash_damage = 0.5
	var enemies := _pack(3, PBStrikeRules.SPLASH_RADIUS * 3.0)
	var out := PBCombatOutcome.new()
	var far: float = enemies[2].hp
	PBStrikeRules.land(attacker, enemies[0], 100.0, false, enemies, _cfg, 0, null, out)
	assert_eq(enemies[2].hp, far, "站得远的那个一点血都不该掉")


func test_an_original_splash_radius_reaches_farther_than_the_default() -> void:
	# 被动配了原版码数（`splash_radius=275`）就按那把尺子换算；没配的还是默认半径。
	var attacker := _striker()
	attacker.splash_damage = 0.5
	var gap: float = PBStrikeRules.SPLASH_RADIUS * 2.0
	var enemies := _pack(2, gap)
	var out := PBCombatOutcome.new()
	var before: float = enemies[1].hp
	PBStrikeRules.land(attacker, enemies[0], 100.0, false, enemies, _cfg, 0, null, out)
	assert_eq(enemies[1].hp, before, "前提：默认半径够不着这个距离")
	attacker.splash_radius = 275.0
	assert_almost_eq(PBStrikeRules.splash_reach(attacker, _cfg), 0.1375, 0.0001, "275 码 = 0.1375")
	assert_gt(PBStrikeRules.splash_reach(attacker, _cfg), gap, "前提：换算后的半径盖得住")
	PBStrikeRules.land(attacker, enemies[0], 100.0, false, enemies, _cfg, 1, null, out)
	assert_almost_eq(before - enemies[1].hp, 50.0, 0.001, "配了原版溅射范围就够得着")


func test_hitting_a_healthy_enemy_lands_the_extra_but_a_hurt_one_does_not() -> void:
	# 判据看的是**这一下之前**的血量比 —— 打完再看的话，一记正好把人
	# 打到半血以下的攻击会拿不到加成，而玩家读到的是「有时候触发有时候不」。
	var attacker := _striker()
	attacker.heavy_bonus = 0.5
	var enemies := _pack(2)
	var out := PBCombatOutcome.new()
	var full: float = enemies[0].hp
	PBStrikeRules.land(attacker, enemies[0], 100.0, false, enemies, _cfg, 0, null, out)
	assert_almost_eq(full - enemies[0].hp, 150.0, 0.001, "满血的该多挨五成")

	enemies[1].hp = enemies[1].max_hp * 0.2
	var hurt: float = enemies[1].hp
	PBStrikeRules.land(attacker, enemies[1], 100.0, false, enemies, _cfg, 0, null, out)
	assert_almost_eq(hurt - enemies[1].hp, 100.0, 0.001, "已经残血的就是原样一份")


func test_the_extra_and_the_main_hit_are_one_number_not_two() -> void:
	# 分开打的话易伤（M7-d）会乘两次，而且屏幕上一次普攻会飘出两个数。
	var attacker := _striker()
	attacker.heavy_bonus = 0.5
	var enemies := _pack(1)
	var book := PBBattleLog.new()
	PBStrikeRules.land(
		attacker, enemies[0], 100.0, false, enemies, _cfg, 0, book, PBCombatOutcome.new()
	)
	var hits: Array[Dictionary] = []
	for entry: Dictionary in book.entries:
		if int(entry.get("kind", -1)) == PBBattleLog.Kind.HIT_ENEMY:
			hits.append(entry)
	assert_eq(hits.size(), 1, "一次普攻只该记一条播报")
	assert_almost_eq(float(hits[0]["amount"]), 150.0, 0.001, "而且那一条是加起来之后的数")


func test_landing_a_hit_opens_a_crit_window_that_expires() -> void:
	# B10 的窗口必须比普攻间隔长：短于间隔的话它在下一发之前就过期了，
	# **也就是永远只在挂上的那一 tick 有效** —— 而那等于没有，且不报错。
	var attacker := _striker()
	attacker.crit_on_hit = 0.25
	var enemies := _pack(1)
	PBStrikeRules.land(
		attacker, enemies[0], 10.0, false, enemies, _cfg, 0, null, PBCombatOutcome.new()
	)
	assert_almost_eq(PBCritRules.chance_of(attacker, 0), 0.25, 0.001, "命中之后该有暴击率")
	var window: int = PBBuffRules.to_ticks(PBStrikeRules.CRIT_WINDOW_SECONDS, _cfg)
	assert_almost_eq(PBCritRules.chance_of(attacker, window), 0.25, 0.001, "窗口之内还在")
	assert_eq(PBCritRules.chance_of(attacker, window + 1), 0.0, "过期就没了")
	assert_gt(window, 24, "窗口要比最慢的那个攻速间隔长")


# ── 每一条命中路径都走同一个落点 ──────────────────────────────


func test_every_way_a_hit_can_land_goes_through_the_one_funnel() -> void:
	# **和上面那条阵亡的扫描同形。** 一次命中落在敌人身上有三条路
	# （近战当场见血、范围各打一份、子弹飞到了结算），M10-d 之前它们
	# 各写一遍「记播报 → 扣血 → 记杀敌数」。往后面接触发之后，
	# 漏一条的表现是「远程角色的羁绊触发不了」——
	# 而 §7 的 B15 神赐予的伤痛，载体恰恰是个远程（小南）。
	assert_eq(_calls(STRIKE_PATH, "land("), 2, "近战和范围两条路各调一次 land")
	assert_eq(_calls(SHOT_PATH, "PBStrikeRules.land("), 1, "子弹落地那一路也回头调它")


func test_the_log_line_for_a_hit_is_written_in_exactly_one_place() -> void:
	# 记播报和扣血是同一件事的两半（那条播报要带上加成之后的总额、
	# 还要带暴击标记）。分开的话「日志上写 100、血掉了 150」不报错。
	#
	# **数的是事件不是函数。** 这个文件里今天有三种会见血的事，
	# **每种各有且只有一处记播报**：我方打敌人（[method PBStrikeRules.land]）、
	# 敌人打我方（`hurt_ally`，M12-c2）、反弹还回去那一笔（`_reflect`）。
	# 多出第四处就要回来看看它是不是又把同一件事写了两遍。
	assert_eq(_calls(STRIKE_PATH, "book.hit("), 3, "三种见血的事，每种只许一处记播报")


func test_a_ranged_carrier_triggers_on_the_frame_the_bullet_arrives() -> void:
	# 端到端：远程那一路的触发发生在**命中**那一刻，不是出膛那一刻。
	# 小南是远程，而她带的正是溅射。
	var attacker := _striker()
	attacker.splash_damage = 0.5
	attacker.slot = 3
	var enemies := _pack(3, 0.01)
	var shots: Array[PBProjectile] = [PBProjectile.new()]
	shots[0].launch(Vector2(0.0, 0.0), 0, 100.0, 0.02, false, PBElement.Type.PHYSICAL, 3)
	var squad: Array[PBAttacker] = [attacker]
	var out := PBCombatOutcome.new()
	var neighbour: float = enemies[1].hp
	var flown: int = 0
	while shots[0].alive and flown < 200:
		PBShotRules.advance(shots, enemies, squad, _cfg, flown, null, out)
		flown += 1
	assert_false(shots[0].alive, "子弹该已经落地了")
	assert_lt(enemies[1].hp, neighbour, "落地那一下该带出溅射")


# ── 夹具 ──────────────────────────────────────────────────────


## 一个普通的己方攻击者。
func _striker() -> PBAttacker:
	var one := PBAttacker.new()
	one.slot = 0
	one.dps = 100.0
	one.max_hp = 500.0
	one.attack_speed = 1.0
	one.reach = 1.0
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


## [param count] 个挨着站的敌人，间距 [param gap]。全部已经出场，
## **血量拉到打不死** —— 这个文件量的是「掉了多少」，不是「死了几个」。
func _pack(count: int, gap: float = 0.5) -> Array[PBEnemy]:
	var wave := PBWaveRules.build(3, _cfg, _rng)
	var out: Array[PBEnemy] = []
	for i: int in count:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, _cfg.field_length - float(i) * gap, 0, 0.0)
		enemy.slot = i
		enemy.max_hp = 100000.0
		enemy.hp = enemy.max_hp
		out.append(enemy)
	return out


## [param needle] 在这个文件里被**调用**了几次。注释和 `func` 那一行不算 ——
## 后者是定义不是调用，算进去的话这条断言会随着「这个函数写在哪个文件里」变。
func _calls(path: String, needle: String) -> int:
	var seen: int = 0
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#") or code.begins_with("func ") or code.begins_with("static func "):
			continue
		if code.contains(needle):
			seen += 1
	return seen
