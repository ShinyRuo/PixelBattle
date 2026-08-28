class_name PBRosterPanel
extends Control
## 准备阶段的阵容面板。M1-c。
##
## ## 为什么只展示、不让玩家自己选人
##
## 当前的伤害公式是
## `队伍 DPS = Σ(上场单位对本波的有效战力) × 科技 × 羁绊 × 装备`。
## **后三个乘数都不依赖于「上了谁」** —— 羁绊看仓库人数、装备看位置数。
## 所以「按有效战力取前 N」在数学上**严格最优，没有例外**：
## 自由选人只能选得更差，那不是决策，是陷阱。
##
## 让阵容变成真决策的东西全在后面：羁绊组合（§09，M2）、
## 前中后排与技能射程（§02/M3）、波型对 AOE 与单体的偏好（§04/M3）。
## **等它们到位再开放选人**，现在开放只是给玩家一个犯错的机会。
##
## ## 那这一层做什么
##
## 把 §03 那 1.41 倍**摆到屏幕上**。
##
## 「每波换上克制系值 1.41 倍战力」这个数以前只存在于扫描报告里，
## 玩家在游戏里完全看不到 —— 而这正是原版的老毛病：
## 克制关系要点开技能说明才看得到，玩家只能背攻略（§03）。
##
## 面板每波把两条并排算给你看：**按克制排的 DPS** vs **按裸战力排的 DPS**。
## 敌方属性五波一轮（§04），所以这个差值每波都在动 ——
## 卡池缺哪一系，差值就在对应那波塌下来。

## 每个上场位显示成一个小方块 + 一行字。
const SLOT_SIZE := Vector2(66.0, 22.0)
## 高度 224 → 206：见 [constant PBPreparePanel.PANEL_RECT]，
## 两块准备面板一起让出 18px 给底部的羁绊带。
const PANEL_RECT := Rect2(286.0, 96.0, 308.0, 206.0)
const FONT_SIZE: int = 9

## 属性的单字名。与 [PBEnemyPool.ELEMENT_COLORS] 用同一套色相。
const ELEMENT_NAMES := {
	PBElement.Type.FIRE: "火",
	PBElement.Type.WIND: "风",
	PBElement.Type.THUNDER: "雷",
	PBElement.Type.EARTH: "土",
	PBElement.Type.WATER: "水",
	PBElement.Type.PHYSICAL: "物",
}

const RARITY_NAMES: Array[String] = ["R", "SR", "SSR", "USR"]

var _header: Label
var _slots: Array[Label] = []
var _standby: Label
var _rotation: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.07, 0.10, 0.92)
	backdrop.position = PANEL_RECT.position
	backdrop.size = PANEL_RECT.size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_header = _add_label(PANEL_RECT.position + Vector2(8.0, 6.0), PANEL_RECT.size.x - 16.0)

	# 出战席按上限一次建满，之后只改文字 —— 和敌人池同一条规矩（§14）。
	var cfg := PBSimConfig.new()
	_slots.resize(cfg.deploy_slots_max)
	for i: int in cfg.deploy_slots_max:
		var column: int = i % 4
		var row: int = i / 4
		var at := (
			PANEL_RECT.position
			+ Vector2(8.0 + float(column) * (SLOT_SIZE.x + 4.0), 24.0 + float(row) * 24.0)
		)
		_slots[i] = _add_label(at, SLOT_SIZE.x)

	_standby = _add_label(PANEL_RECT.position + Vector2(8.0, 110.0), PANEL_RECT.size.x - 16.0)
	_rotation = _add_label(PANEL_RECT.position + Vector2(8.0, 132.0), PANEL_RECT.size.x - 16.0)
	_rotation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 面板压到 206 高之后这里最多到 132 + 70 = 202，正好不越界。
	_rotation.size.y = 70.0


## 按当前状态和**这一波的属性**刷新。属性每波轮转（§04），
## 所以同一套卡在不同波次的有效战力完全不同 —— 那正是要显示的东西。
func refresh(state: PBRunState, cfg: PBSimConfig, wave: PBWave) -> void:
	var deployed := PBValuation.deployed_for(state, wave.element, cfg)
	_header.text = (
		"阵容　对第 %d 波（%s）　出战 %d/%d　仓库 %d"
		% [
			wave.index,
			ELEMENT_NAMES.get(wave.element, "?"),
			deployed.size(),
			state.open_slots(cfg),
			state.roster.size(),
		]
	)
	for i: int in _slots.size():
		_fill_slot(_slots[i], deployed, i, wave.element, cfg)

	var bench: int = state.deploy_capacity(cfg) + state.standby_capacity(cfg)
	var on_bench: int = mini(state.roster.size(), bench)
	var idle: int = maxi(state.roster.size() - on_bench, 0)
	_standby.text = (
		"待命台 %d/%d（可派遣，羁绊照算）　仓库外 %d 张不生效"
		% [maxi(on_bench - deployed.size(), 0), state.standby_capacity(cfg), idle]
	)
	_rotation.text = _rotation_text(state, cfg, wave, deployed)


## §03 的那 1.41 倍，逐波算给玩家看。
func _rotation_text(
	state: PBRunState, cfg: PBSimConfig, wave: PBWave, deployed: Array[PBUnit]
) -> String:
	if deployed.is_empty():
		return "还没有人上场 —— 先去左边抽卡。"
	var smart: float = PBValuation.dps_of(deployed, wave.element, state, cfg)
	var naive: float = PBValuation.dps_of(
		PBValuation.deployed_by_raw_power(state, cfg), wave.element, state, cfg
	)
	if naive <= 0.0:
		return "按克制排　%.0f" % smart
	var text: String = (
		"按克制排 %.0f　按裸战力排 %.0f　换人多赚 %+.0f%%" % [smart, naive, (smart / naive - 1.0) * 100.0]
	)
	# 缺克星的时候把话说明白 —— §03 说这是原版最大的短板：
	# 玩家不知道自己为什么突然打不动了。
	var needed := PBElement.counter_of(wave.element)
	if not state.can_counter(wave.element):
		text += "\n\n本波缺 %s 系克星，这一波只能硬吃。" % ELEMENT_NAMES.get(needed, "?")
	else:
		text += (
			"\n\n%s 克 %s，上场的克制系吃 ×%.1f 倍。"
			% [
				ELEMENT_NAMES.get(needed, "?"),
				ELEMENT_NAMES.get(wave.element, "?"),
				cfg.mult_counter,
			]
		)
	return text


func _fill_slot(
	label: Label, deployed: Array[PBUnit], index: int, element: PBElement.Type, cfg: PBSimConfig
) -> void:
	if index >= deployed.size():
		label.text = "—"
		label.modulate = Color(0.35, 0.35, 0.38)
		return
	var unit: PBUnit = deployed[index]
	var relation := PBElement.relation(unit.element, element)
	label.text = (
		"%s%s%s ×%.2f"
		% [
			ELEMENT_NAMES.get(unit.element, "?"),
			RARITY_NAMES[int(unit.rarity)],
			"★%d" % unit.star() if unit.star() > 1 else "",
			cfg.damage_multiplier(relation),
		]
	)
	# 用敌人池那套色相，玩家在战场上认到的颜色和这里是同一个。
	label.modulate = PBEnemyPool.ELEMENT_COLORS.get(unit.element, Color.WHITE)


func _add_label(at: Vector2, width: float) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(width, 18.0)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(label)
	return label
