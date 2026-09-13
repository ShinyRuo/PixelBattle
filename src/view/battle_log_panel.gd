class_name PBBattleLogPanel
extends Control
## F 区在战斗中的那一块：**战斗日志播报**（§02）。

## 占的是仓库让出来的位置：仓库只在准备阶段出现，战斗中那块框空着，而战斗中恰恰最需要一条文字记录。
## 两块是同一个位置的两种模式。
##
## **文字不是飘字**：飘字是这一刻的强调，会消失；播报是「刚才发生过什么」，可以往回翻。
##
## **名字在这一层拼，不在 sim 里**（铁律 5）：[PBBattleLog] 记下标和数字，这里用名单和语言表翻译。
## 敌人按**属性 + 编号**报，否则一波几十只同名就读不出谁在打谁。

## 一次画多少条。RichTextLabel 自己会滚，但每帧重排整块 BBCode 是有成本的，
## 而这一块每 tick 都可能有新内容 —— 只喂最后这些行。
const TAIL: int = 60

## 面板占 F 区，和仓库同一个框。
const PANEL_RECT := PBLayout.F_ROSTER
const TITLE_H: float = 12.0
const PAD: float = 4.0

var _title: Label
var _body: RichTextLabel

## 上一次画到第几条。**只在长度变了时重排** —— 一波打完之后
## 日志不再变，而这块面板在结算那几十帧里还摊着。
var _drawn: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	PBSkin.panel(self, PANEL_RECT)
	_title = PBSkin.label(
		self, PANEL_RECT.position + Vector2(PAD, 1.0), PANEL_RECT.size.x - PAD * 2.0,
		PBSkin.FONT_BODY, PBSkin.TITLE
	)
	_body = PBSkin.rich(
		self,
		Rect2(
			PANEL_RECT.position + Vector2(PAD, TITLE_H),
			PANEL_RECT.size - Vector2(PAD * 2.0, TITLE_H + 2.0)
		),
		PBSkin.FONT_BODY
	)
	# **可滚动**（玩家点名要的）。`scroll_following` 让新的一条进来时
	# 自动贴着底 —— 不跟的话打起来之后视野停在第一条，而新内容在看不见的下面。
	# 玩家自己往回滚时引擎会停掉跟随，滚回底部再恢复。
	_body.scroll_active = true
	_body.scroll_following = true
	# 要收滚轮，所以这一层不能是 IGNORE（本类自己仍然是 IGNORE）。
	_body.mouse_filter = Control.MOUSE_FILTER_PASS


## 重画。[param deployed] 是这一波上场的那几个，下标对齐
## [member PBAttacker.slot]；[param wave] 只用来给敌人报属性。
func refresh(log: PBBattleLog, deployed: Array[PBUnit], wave: PBWave) -> void:
	if log == null:
		return
	if log.entries.size() == _drawn:
		return
	_drawn = log.entries.size()
	_title.text = "战斗日志"
	var lines := PackedStringArray()
	for entry: Dictionary in log.entries.slice(maxi(_drawn - TAIL, 0)):
		lines.append(line_of(entry, deployed, wave))
	_body.text = "\n".join(lines)


## 开波第一条：第几波、**这一波哪几组羁绊生效**（玩家点名要的第一项）。
##
## 组在这一层而不是 sim 里，理由和 [method line_of] 一样：羁绊的名字在语言表里。
## 一组都没凑齐时照实说 —— 空着的话玩家会以为是这块面板没接上。
static func opening_line(wave: PBWave, state: PBRunState, cfg: PBSimConfig) -> String:
	var names := PackedStringArray()
	if cfg.bonds != null:
		var units := state.bonded_units(cfg)
		for bond: PBBond in cfg.bonds.all():
			if bond.tier_at(PBBondRules.active_count(bond, units)) > 0:
				names.append(PBLocale.of_bond(bond))
	var bonds: String = "、".join(names) if names.size() > 0 else "无"
	return "── 第 %d 波　生效羁绊：%s" % [wave.index, bonds]


## 下一波开打，把游标清掉 —— **日志本身不清**（玩家定的：只保留一局）。
## 不清游标的话，条数恰好没变的那一帧会跳过重排，而名单已经换了一批人。
func rewind() -> void:
	_drawn = -1


## 一条播报翻成一行字。**public 是有意的**：测试直接对它下断言，
## 而从渲染出来的 BBCode 里反解一行字是不可能稳的。
func line_of(entry: Dictionary, deployed: Array[PBUnit], wave: PBWave) -> String:
	var kind: int = int(entry.get("kind", PBBattleLog.Kind.NOTE))
	var source: int = int(entry.get("source", -1))
	var target: int = int(entry.get("target", -1))
	var hurt: int = roundi(float(entry.get("amount", 0.0)))
	var out: String = ""
	match kind:
		PBBattleLog.Kind.NOTE:
			out = PBSkin.tint(str(entry.get("text", "")), PBSkin.TITLE)
		PBBattleLog.Kind.HIT_ENEMY:
			out = "%s → %s %d" % [_ally(source, deployed), _enemy(target, wave), hurt]
		PBBattleLog.Kind.HIT_ALLY:
			out = PBSkin.tint(
				"%s → %s %d" % [_enemy(source, wave), _ally(target, deployed), hurt], PBSkin.WARN
			)
		PBBattleLog.Kind.ALLY_DOWN:
			out = PBSkin.tint("%s 倒下了" % _ally(source, deployed), PBSkin.BAD)
		PBBattleLog.Kind.BASE_HIT:
			out = PBSkin.tint("基地受到 %d 点伤害" % hurt, PBSkin.BAD)
		PBBattleLog.Kind.ULTIMATE:
			out = PBSkin.tint("%s 施展忍术" % _ally(source, deployed), PBSkin.ACCENT)
	return out


## 第几个攻击者是谁。**名单对不上时给一个看得出来的占位**，不是空字符串：
## 空的那一行读起来像「→ 敌人 12」，而问题出在名单上，不在伤害上。
func _ally(slot: int, deployed: Array[PBUnit]) -> String:
	if slot < 0 or slot >= deployed.size():
		return "?"
	return PBLocale.of_character(deployed[slot].character)


## 敌人按**属性 + 编号**报。没有名字是对的 —— 一波几十只同一种怪，
## 报「火忍」的话「谁在打谁」这条信息就没了。
func _enemy(slot: int, wave: PBWave) -> String:
	var element: String = "?"
	if wave != null:
		element = str(PBUnitTile.ELEMENT_NAMES.get(wave.element, "?"))
	return "%s怪#%d" % [element, slot]
