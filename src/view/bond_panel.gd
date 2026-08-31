class_name PBBondPanel
extends Control
## 准备阶段的羁绊带。M2-d。
##
## ## 它兑现的是 §09 的验收
##
## 「每个羁绊的功能档在实战中**可被玩家明确感知**（不是隐性数值）」。
##
## M2-b 之前羁绊是一个看不见的乘数（替身曲线，按人头），玩家没有任何理由
## 去关心它。装上真羁绊表之后它成了阵容的主要价值来源，
## **但仍然看不见** —— 一个看不见的系统等于不存在，玩家只会继续按战力排队。
##
## ## 两行分工
##
## - **第一行「现在吃着什么」**：总倍率 + 已激活的各组档位。
## - **第二行「差一点能吃到什么」**：离下一档还差几人、补上值多少。
##
## 第二行才是这个面板真正的产出。「已激活」是结果，玩家看一眼就够；
## **「还差 1 人就能进满档，+18%」是可以立刻行动的信息** ——
## 那正是「换人」从排序变成决策的那一刻。
##
## ## 功能档在这里只写「解锁了什么」，不写「谁带」（M3-f）
##
## 第一行现在会在档位后面缀上机制名（`凯班 满档·聚拢`）。**载体是谁、
## 上没上场，留给忍者信息栏**（[PBUnitInfo]）—— 那里才是能立刻行动的地方，
## 这条带子只有 32px 高，塞进「要把某某排进出战席」会把它挤爆。

## 屏幕 640×360，纵向排得很满：Info 5–25、任务卡 28–90、
## 两块准备面板 96–302、**羁绊带 304–336**、下一波预告 338–358。
##
## 第一版摆在 322–356，和「下一波预告」那个常驻标签（334–354）直接叠在一起，
## 底下那行糊成一团 —— 截图一看就知道。腾地方的办法是把两块准备面板
## 各压 18px，不是把这条挤薄。
const PANEL_RECT := Rect2(46.0, 200.0, 548.0, 30.0)
const FONT_SIZE: int = 9

## 第二行最多提几组，多了这一行会被挤爆。按「补上去值多少」排序后取前几名。
const MAX_HINTS: int = 3

var _active: Label
var _next: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	PBSkin.panel(self, PANEL_RECT)

	_active = _add_label(PANEL_RECT.position + Vector2(8.0, 1.0), PBSkin.TEXT)
	_next = _add_label(PANEL_RECT.position + Vector2(8.0, 15.0), PBSkin.TITLE)


## 按当前在场名单刷新。[param bond_aware] 是玩家现在用哪种带人方式（`B` 键切换）。
func refresh(state: PBRunState, cfg: PBSimConfig, bond_aware: bool = false) -> void:
	var units := state.bonded_units(cfg)
	_active.text = _active_text(state, cfg, units, bond_aware)
	_next.text = _next_text(cfg, units)


## 第一行：现在吃着哪些羁绊，以及**是靠什么带出来的**。
##
## 带人方式要写在这里，否则 `B` 键按下去只看得到倍率跳了一下，
## 看不出跳的是什么 —— 一个不说明自己在切什么的开关等于没有。
func _active_text(
	state: PBRunState, cfg: PBSimConfig, units: Array[PBUnit], bond_aware: bool
) -> String:
	var mode: String = "按羁绊带人" if bond_aware else "按战力带人"
	if units.is_empty():
		return "羁绊　在场没有人 —— 先去左边抽卡。　B 键：%s" % mode
	var tiers := PBBondRules.active_tiers(units, cfg.bonds)
	if tiers.is_empty():
		return "羁绊 ×1.00　一组都没凑上（在场 %d 人）　B 键：%s" % [units.size(), mode]

	var parts := PackedStringArray()
	for bond: PBBond in cfg.bonds.all():
		var tier: int = int(tiers.get(bond.id, 0))
		if tier <= 0:
			continue
		var full: String = "满" if tier >= bond.tier_counts.size() else "%d" % tier
		var label: String = "%s %s档" % [PBLocale.of_bond(bond), full]
		var key: StringName = bond.function_at(PBBondRules.active_count(bond, units))
		if key != &"":
			label += "·%s" % PBLocale.of_bond_function(key)
		parts.append(label)
	return (
		"羁绊 ×%.2f（在场 %d · B 键 %s）　%s"
		% [state.bond_mult(cfg), units.size(), mode, String("　").join(parts)]
	)


## 第二行：差一点能吃到什么。**这一行才是这个面板的产出。**
func _next_text(cfg: PBSimConfig, units: Array[PBUnit]) -> String:
	if units.is_empty():
		return ""

	# 收集「还差几人 → 补上去涨多少」，按收益排序。
	# 只提差 1–2 人的：差 3 人以上在一波之内基本凑不出来，摆上去只是噪音。
	var hints: Array[Dictionary] = []
	for bond: PBBond in cfg.bonds.all():
		var missing: int = PBBondRules.to_next_tier(bond, units)
		if missing <= 0 or missing > 2:
			continue
		var active: int = PBBondRules.active_count(bond, units)
		var gain: float = bond.bonus_at(active + missing) - bond.bonus_at(active)
		if gain <= 0.0:
			continue
		hints.append({"name": PBLocale.of_bond(bond), "missing": missing, "gain": gain})
	if hints.is_empty():
		return "没有差一两个人就能补上的档位。"

	hints.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["gain"]) > float(b["gain"])
	)
	var parts := PackedStringArray()
	for hint: Dictionary in hints.slice(0, MAX_HINTS):
		parts.append(
			"%s 差 %d 人（+%.0f%%）" % [hint["name"], hint["missing"], float(hint["gain"]) * 100.0]
		)
	return "再补一个就能进：　%s" % String("　").join(parts)


## 摆不下就掐掉尾巴加省略号。**不换行** —— 这条带子只有 30px 高，
## 一换行第二行就顶掉「再补一个就能进」那句，而那句才是这块面板的产出。
func _add_label(at: Vector2, color: Color) -> Label:
	var label := PBSkin.label(self, at, PANEL_RECT.size.x - 16.0, FONT_SIZE, color)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label
