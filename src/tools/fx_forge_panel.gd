@tool
class_name PBFxForgePanel
extends Control
## 编辑器底栏那块「战场特效」面板。外壳在 `addons/fx_forge/`（零逻辑）。
##
## 一类特效一页（[TabContainer]，页名取节点名）。现在只有「子弹」（[PBFxShotPage]）；
## 技能子弹、命中特效、范围特效、光环以后各加一页 —— 每页各管自己那一格配置，互不相干。

var _tabs: TabContainer
var _shot_page: PBFxShotPage


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 360.0)
	_tabs = TabContainer.new()
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tabs)
	_shot_page = PBFxShotPage.new()
	_tabs.add_child(_shot_page)
