class_name PBTopBarText
extends RefCounted
## 顶栏 A 区那**两行字**：本局信息 + 下一波预告。M6-d。
##
## ## 为什么单独一个类
##
## 它们原来长在 [PBBattleView] 里，而那个文件已经贴着 gdlint 的 1000 行上限
## 三个里程碑了 —— 每加一件事就要回去砍一段注释，那不是重构，是拆东墙。
##
## 拼一句给人看的话和「阶段状态机 + 定帧步进 + 按键裁决」不是同一件事，
## 和 [PBShopLabels] 的分工是同一条线：**数从规则层来，排版在这一层**。
##
## ## 预告零副作用
##
## 波次生成是 `(种子, 波次)` 的纯函数（见 [method PBRngStreams.wave_rng]），
## 所以提前算下一波不会动任何 RNG 状态。§03 称这是本案投入产出比最高的
## 一处改进 —— 原版的克制关系要点开技能说明才看得到，玩家全靠背。
##
## ## 属性名与波型名只有一份
##
## 两行都走 [PBUnitTile] 那两张表。M4-f 之前 [PBBattleView] 里另有一份
## （全项目第三份）—— 多一份不报错，只是有一天「物」和「物理」
## 会在两块面板上同时出现。

## 战斗中能按什么。
const KEYS_BATTLE := "空格暂停　1/2/3 倍速　R 重开　Esc 菜单　A 自动:%s"

## 准备阶段能按什么。**和上面那行不是同一批** —— 拖放只在准备阶段有意义，
## 而倍速只在打起来之后有意义。列一份大而全的话，两个阶段各有一半是死的。
const KEYS_PREPARE := "点选/拖动摆位　拖进任务栏派任务　回车开打　B 换带人法　Esc 菜单"


## 第一行：这一波是什么、家底多少、打到哪儿了。
##
## [param outcome] 给 `null` 表示还在准备阶段 —— **不是「战果全是 0」**：
## §01 说准备阶段不限时，所以那一行该说「在等什么」，而不是报一份空战报。
static func status(
	state: PBRunState,
	plan: PBWavePlan,
	outcome: PBCombatOutcome,
	paused: bool,
	speed: int
) -> String:
	var wave: PBWave = plan.wave
	var head := (
		"第 %d 波　%s　%s　　基地 %d　金 %d　卡池 %d"
		% [
			wave.index,
			PBUnitTile.ELEMENT_NAMES.get(wave.element, "?"),
			PBUnitTile.SHAPE_NAMES.get(wave.shape, "?"),
			int(state.base_hp),
			state.gold,
			state.roster.size(),
		]
	)
	if outcome == null:
		# §01：准备阶段不限时。所以这里不显示秒数，只说在等什么。
		var grade: String = String(PBEconomyRules.QUEST_GRADES[plan.quest_grade])
		return "%s　　【准备阶段】敌 %d　任务 %s" % [head, wave.count, grade]
	return (
		"%s　　敌 %d/%d　漏 %d　　%.1fs　%s"
		% [
			head,
			outcome.kills,
			wave.count,
			outcome.leaked,
			outcome.battle_seconds,
			"暂停" if paused else "%d 倍速" % speed,
		]
	)


## 第二行：下一波是什么、你的克制覆盖、现在能按哪些键。
## [param preparing] 为真且 [param auto_play] 为假时列准备阶段那批键。
static func preview(
	state: PBRunState,
	cfg: PBSimConfig,
	rng: PBRngStreams,
	preparing: bool,
	auto_play: bool
) -> String:
	var next := PBRunSim.preview_wave(state.wave_index + 1, cfg, rng)
	var missing := state.missing_counters()
	var covered: int = PBWaveRules.WAVE_ELEMENTS.size() - missing.size()
	var keys: String = KEYS_BATTLE % ("开" if auto_play else "关")
	if preparing and not auto_play:
		keys = KEYS_PREPARE
	return (
		"下一波：%s %s　　克制覆盖 %d/5（%s）　　%s"
		% [
			PBUnitTile.ELEMENT_NAMES.get(next.element, "?"),
			PBUnitTile.SHAPE_NAMES.get(next.shape, "?"),
			covered,
			_gap(missing),
			keys,
		]
	)


## 「缺火水」那一截。全齐了就直说，**不要留空** —— 一行里空一段，
## 玩家读到的是「这里本来该有东西，是不是没算出来」。
static func _gap(missing: Array) -> String:
	if missing.is_empty():
		return "已齐"
	var names := PackedStringArray()
	for element: int in missing:
		names.append(str(PBUnitTile.ELEMENT_NAMES.get(element, "?")))
	return "缺 %s" % "".join(names)
