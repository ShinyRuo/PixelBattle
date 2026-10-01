@tool
class_name PBFxForgePanel
extends Control
## 编辑器底栏那块「战场特效」面板。外壳在 `addons/fx_forge/`（零逻辑）。
##
## 一类特效一页（[TabContainer]，页名取节点名）。子弹加工和技能素材绑定分开，
## 前者生成资源，后者绑定已有读点；尚未接入的类型不暴露空配置。

var _tabs: TabContainer
var _shot_page: PBFxShotPage


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 360.0)
	_tabs = TabContainer.new()
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tabs)
	_shot_page = PBFxShotPage.new()
	_tabs.add_child(_shot_page)
	_tabs.add_child(PBArtBindingPage.new())
	_tabs.add_child(PBBuffArtPage.new())
	var instant_page := PBBuffArtPage.new()
	instant_page.instant_only = true
	_tabs.add_child(instant_page)
	_tabs.add_child(PBFieldArtPage.new())
	_tabs.add_child(PBCastArtPage.new())
	_tabs.add_child(PBSummonArtPage.new())
