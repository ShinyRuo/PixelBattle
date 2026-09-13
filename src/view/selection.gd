class_name PBSelection
extends RefCounted
## 战场上现在选中了什么（§02）。指令卡、信息栏、装备栏三块都读它。
##
## 一个类而不是两个字段：答案有两半（**哪一类** + **具体是谁**），散开的话每块都要自己记得
## 「kind 是 UNIT 时才读 unit_id」，漏一处就拿着上一个忍者的 id 去画大本营。
## 原版（War3 RPG 地图）的骨架：没有独立页面，选中谁，指令卡就换成谁能做的事。

enum Kind {
	NONE,  ## 什么都没选。指令卡显示提示，信息栏显示整队的账
	BASE,  ## 大本营：升人口/科技、抽卡、重抽任务
	BEAST,  ## 尾兽槽（可能是空的）：升级尾兽
	UNIT,  ## 一个忍者：升级、收回仓库、派去做任务
	DISPATCHED,  ## 正在做任务的一个忍者：只能看，不能操作
}

var kind: Kind = Kind.NONE

## [constant Kind.UNIT] / [constant Kind.DISPATCHED] 时选中的是谁。
##
## **换 kind 的时候一定要一起清掉**（走 [method set_to]），否则
## 「选中大本营」之后它还留着上一个忍者的 id，指令卡照样能升那个人的级 ——
## 界面上什么都看不出来。
var unit_id: StringName = &""


static func of_unit(id: StringName, dispatched: bool = false) -> PBSelection:
	var out := PBSelection.new()
	out.kind = Kind.DISPATCHED if dispatched else Kind.UNIT
	out.unit_id = id
	return out


static func of_kind(selection_kind: Kind) -> PBSelection:
	var out := PBSelection.new()
	out.kind = selection_kind
	return out


## 换成另一种选中。**id 跟着清** —— 见 [member unit_id]。
func set_to(selection_kind: Kind, id: StringName = &"") -> void:
	kind = selection_kind
	unit_id = id


## 选中的那张卡。不是忍者、或者卡已经不在仓库里就返回 null。
func unit_of(state: PBRunState) -> PBUnit:
	if kind != Kind.UNIT and kind != Kind.DISPATCHED:
		return null
	return state.roster.get(unit_id, null) as PBUnit


func is_same(other_kind: Kind, id: StringName = &"") -> bool:
	return kind == other_kind and unit_id == id
