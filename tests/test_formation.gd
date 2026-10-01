extends GutTest
## 开战位置：拖动摆位（§02，M4-f）。
##
## ## 这个文件守的是三件事
##
## 1. **一个人都没拖时，与自动站位一字不差** —— 那是它敢在数值回归之前
##    落地的全部理由，和 M3.5-f 的手动装备是同一条规矩
## 2. **界限是夹取，不是拒绝**。拒绝的话玩家拖到界限外松手就什么都没发生，
##    他不知道是没拖动还是不让摆
## 3. **画在哪 = 打在哪**。准备阶段那个方块的位置和开波之后
##    [PBAttacker] 的位置必须是同一次计算，两处分叉的表现是
##    「我摆好的阵型，一开打就跳了一下」

const BATTLE_SCENE := "res://scenes/battle.tscn"
const FIXED_SEED: int = 20260830

## 位置比较的容差。
##
## [member PBAttacker.pos] 是 `Vector2`，也就是**单精度** —— 而配置里那些
## 站位常量是 `float`（双精度）。0.2 存进 Vector2 再读出来是 0.20000000298，
## 差在 3e-9 上。那是类型的性质，不是算错了：升维之前
## `position` 是单个 float，所以这个差以前不存在。
const EPS: float = 1e-6
const EPS2 := Vector2(EPS, EPS)

var _cfg: PBSimConfig
var _rng: PBRngStreams


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = PBRngStreams.new(FIXED_SEED)


func _stocked_state() -> PBRunState:
	var state := PBRunSim.new_state(_cfg)
	for character: PBCharacter in _cfg.characters.all():
		state.add_unit(PBUnit.new(character))
	PBStratBalanced.new().bring_to_field(state, _cfg)
	return state


## 锁一波计划出来，攻击者已经建好、摆位也已经盖上去了。
func _locked(state: PBRunState) -> PBWavePlan:
	var strategy := PBStratBalanced.new()
	var plan := PBRunSim.begin_wave(state, _cfg, _rng)
	PBRunSim.lock_plan(state, plan, strategy.deploy(state, plan.wave, _cfg), false, _cfg)
	return plan


# ── 空名单 = 一字不差 ───────────────────────────────────────────


func test_an_empty_formation_reproduces_the_automatic_columns() -> void:
	# **数值回归的锚。** 摆位是纯加法进来的，没人拖时结果必须一模一样：
	# 近战前排、远程中排、超远程后排，泳道按出战席序号均分。
	var state := _stocked_state()
	var plan := _locked(state)
	assert_true(state.formation.is_empty(), "还没人拖过")
	for attacker: PBAttacker in plan.attackers:
		if attacker.slot < 0:
			continue
		var unit: PBUnit = plan.deployed[attacker.slot]
		assert_almost_eq(
			attacker.home.x, _cfg.reach_column(unit.character.reach_tier()), EPS, "x 该还是射程档派生的那一列"
		)
		assert_almost_eq(
			attacker.home.y,
			_cfg.ally_lane(attacker.slot, plan.deployed.size()),
			EPS,
			"y 该还是按序号均分的那条泳道"
		)


func test_placing_one_leaves_everyone_else_alone() -> void:
	# 摆位是**逐人**的覆盖，不是一套「手动阵型模式」。
	# 分成两条路的话，玩家拖了一个就等于放弃了其余全部自动站位，
	# 而他那一下的意思只是「这个人站这儿」。
	var state := _stocked_state()
	var wave := PBRunSim.preview_wave(1, _cfg, _rng)
	var moved: PBUnit = PBStratBalanced.new().deploy(state, wave, _cfg)[0]
	PBFormationRules.place(state, moved, Vector2(0.05, 0.12), _cfg)
	var plan := _locked(state)
	for attacker: PBAttacker in plan.attackers:
		if attacker.slot < 0:
			continue
		var unit: PBUnit = plan.deployed[attacker.slot]
		if unit == moved:
			assert_almost_eq(attacker.home, Vector2(0.05, 0.12), EPS2, "拖过的那个照摆的来")
		else:
			assert_almost_eq(
				attacker.home.x, _cfg.reach_column(unit.character.reach_tier()), EPS, "没拖过的还是自动站位"
			)


# ── 界限 ────────────────────────────────────────────────────────


func test_the_limit_clamps_instead_of_refusing() -> void:
	# 拒绝的话玩家拖到界限外松手就什么都没发生，他不知道是没拖动还是不让摆。
	# 夹回来至少把「最远只能到这」演示了一遍。
	var state := _stocked_state()
	var unit: PBUnit = state.all_units()[0]
	PBFormationRules.place(state, unit, Vector2(0.95, 0.9), _cfg)
	var at: Vector2 = state.formation[unit.key()]
	assert_almost_eq(at.x, _cfg.deploy_limit_x, EPS, "越过界限该被夹在界限上")
	assert_almost_eq(at.y, _cfg.field_height, EPS, "纵向也夹在战场之内")

	PBFormationRules.place(state, unit, Vector2(-1.0, -1.0), _cfg)
	assert_almost_eq(state.formation[unit.key()], Vector2.ZERO, EPS2, "另一头同样夹住")


func test_the_limit_keeps_the_march_worth_something() -> void:
	# 没有界限的话最优解永远是「全队顶到出生点」，行军距离（§01 的反应窗口）
	# 等于 0，而三档射程也就没有区别了 —— 谁站得靠前谁先打到。
	assert_lt(_cfg.deploy_limit_x, _cfg.field_length, "界限必须真的挡住一段路")
	assert_gt(_cfg.deploy_limit_x, _cfg.column_front, "但要比默认的前排还靠前，不然摆位没有余地")


# ── 画在哪 = 打在哪 ─────────────────────────────────────────────


func test_where_it_is_drawn_is_where_it_fights() -> void:
	# 准备阶段那个方块的位置和开波之后 [PBAttacker] 的位置必须是同一次计算。
	# 两处分叉的表现是「我摆好的阵型，一开打就跳了一下」。
	var state := _stocked_state()
	var wave := PBRunSim.preview_wave(1, _cfg, _rng)
	var deployed := PBStratBalanced.new().deploy(state, wave, _cfg)
	PBFormationRules.place(state, deployed[1], Vector2(0.12, 0.05), _cfg)

	var drawn := PBFormationRules.spots_of(deployed, state.formation, _cfg)
	var plan := _locked(state)
	for attacker: PBAttacker in plan.attackers:
		if attacker.slot < 0:
			continue
		var index: int = deployed.find(plan.deployed[attacker.slot])
		assert_gte(index, 0, "上场名单不该在锁定时换人")
		assert_almost_eq(attacker.home, drawn[index], EPS2, "画的位置和打的位置该是同一个")


func test_dragging_moves_him_on_the_real_screen() -> void:
	# 接线：鼠标拖过去 → 状态里的位置真的变了 → 下一帧画在新地方。
	# 存了却不接的话，[PBFormationRules] 的单测全绿而屏幕上拖不动。
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	root.start_wave = 6
	add_child_autofree(root)
	await wait_physics_frames(3)
	assert_eq(root._phase, PBBattleView.Phase.PREPARE, "该停在准备阶段")

	var units: Array[PBUnit] = root._fighting_now(PBFieldRoster.dispatch_preview(root._state))
	assert_gt(units.size(), 0, "第 6 波该有人上场")
	var field: Vector2 = root._field()
	var spots := PBFormationRules.spots_of(units, root._state.formation, root._cfg)

	# **拖动走引擎的拖放协议**（M5-4）：按下去问「这儿站着谁」，
	# 拖动中每帧一次 `hovered`，松手一次 `card_dropped`。
	var at := PBLayout.to_screen(spots[0], field)
	assert_eq(root._unit_on_field_at(at), units[0].key(), "按在他身上就该抓得起来")
	assert_eq(root._unit_on_field_at(Vector2(620.0, 40.0)), &"", "空地上抓不起人")

	var goal := Vector2(0.08, 0.18)
	root._ground.hovered.emit(
		PBUnitTile.ZONE_FIELD, units[0].key(), PBLayout.to_screen(goal, field)
	)
	assert_almost_eq(root._state.formation[units[0].key()], goal, EPS2, "拖到哪就跟到哪 —— 每帧都写，不是松手才写")


func test_a_ninja_on_the_field_can_be_clicked_and_dragged_anywhere() -> void:
	# **M5-7 修的两条**，都只在准备阶段发作：
	#
	# 1. 战场上的忍者**点不中**。`_on_field_click` 一上来就
	#    `if _phase != Phase.PREPARE` 拦掉了，而在场的人已经不在仓库里
	#    （一个人只在一处）—— 于是他根本没有任何选中入口
	# 2. **拖不进仓库**。那块 [PBDropArea] 和滚动裁剪层是兄弟，而裁剪层盖在
	#    它上面；引擎找放置目标只沿**父链**走，从裁剪层往上根本经过不了它。
	#    结果是只有正好落在某张卡上才收得住，空位一律弹回去
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	root.start_wave = 6
	add_child_autofree(root)
	await wait_physics_frames(3)

	var units: Array[PBUnit] = root._fighting_now(PBFieldRoster.dispatch_preview(root._state))
	assert_gt(units.size(), 0, "第 6 波该有人上场")
	var spots := PBFormationRules.spots_of(units, root._state.formation, root._cfg)
	var at := PBLayout.to_screen(spots[0], root._field())

	root._on_field_click(at)
	assert_eq(root._selection.kind, PBSelection.Kind.UNIT, "点战场上的人就该选中他")
	assert_eq(root._selection.unit_id, units[0].key(), "而且选中的是脚下那一个")
	root._on_field_click(Vector2(620.0, 40.0))
	assert_eq(root._selection.kind, PBSelection.Kind.NONE, "点空地取消选中")

	# 仓库那一块**整块都要收得住**，不只是正好落在某张卡上。
	assert_true(
		root._bay._can_drop_data(
			Vector2.ZERO, {"zone": PBUnitTile.ZONE_FIELD, "unit": units[0].key()}
		),
		"仓库面板本身必须回答得了「可以放」—— 裁剪层挡着那块收件区"
	)
	watch_signals(root._bay)
	root._bay._drop_data(Vector2.ZERO, {"zone": PBUnitTile.ZONE_FIELD, "unit": units[0].key()})
	assert_signal_emitted(root._bay, "card_dropped")
	assert_false(
		root._fighting_now(PBFieldRoster.dispatch_preview(root._state)).has(units[0]), "松手之后他就该下场了"
	)


func test_dragging_a_card_out_of_the_warehouse_puts_him_where_it_lands() -> void:
	# **上场和摆位是同一个动作**（M5-4）。分成两步的话玩家要先「派上场」、
	# 再去战场上把他拖到想要的位置，而他刚才那一下就是在说位置。
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	root.start_wave = 6
	add_child_autofree(root)
	await wait_physics_frames(3)

	# 先抽满仓库 —— 出战席装不下的那几个才会留在里面。
	root._state.gold = 999999
	for _i: int in 12:
		root._on_command(&"gacha")
		root._on_offer_picked(0)
	var away: Array[PBUnit] = PBFieldRoster.dispatch_preview(root._state)
	var deployed: Array[PBUnit] = root._fighting_now(away)
	var idle := PBRosterBay.idle_units(root._state, deployed, away)
	assert_gt(idle.size(), 0, "抽了 12 次，仓库里该有挤不上场的人")

	# **先把一个人从战场拖回仓库**（B → F），腾出一个出战位。
	# 出战席满着的时候拖过去什么都不会发生 —— 挤掉一个已经在场的人
	# 是玩家没要求过的事，而他不会知道被挤掉的是谁。
	var benched: PBUnit = deployed[deployed.size() - 1]
	root._on_card_moved(PBUnitTile.ZONE_FIELD, benched.key(), PBUnitTile.ZONE_STASH)
	assert_false(
		root._fighting_now(PBFieldRoster.dispatch_preview(root._state)).has(benched), "拖回仓库就该下场"
	)

	var goal := Vector2(0.2, 0.3)
	root._ground.card_dropped.emit(
		PBUnitTile.ZONE_STASH, idle[0].key(), PBLayout.to_screen(goal, root._field())
	)
	assert_true(
		root._fighting_now(PBFieldRoster.dispatch_preview(root._state)).has(idle[0]), "拖到战场上就该上场"
	)
	assert_almost_eq(root._state.formation[idle[0].key()], goal, EPS2, "而且就站在松手的那个点")
