class_name PBDebugPanel
extends PBModal
## 调试操作容器；实际状态修改交给战斗入口和规则层。

signal deploy_requested(id: StringName)

var _ninjas: OptionButton
var _deploy: Button
var _status: Label


func _ready() -> void:
	super()
	set_title("Debug · 测试工具")
	set_hint("准备阶段直接出战；关闭窗口后按回车开打。")


func configure(table: PBCharacterTable, can_deploy: bool) -> void:
	if _ninjas.item_count == 0:
		for character: PBCharacter in table.all():
			_ninjas.add_item("%s · %s" % [PBLocale.text(character.name_key), character.id])
			_ninjas.set_item_metadata(_ninjas.item_count - 1, character.id)
	_deploy.disabled = not can_deploy or _ninjas.item_count == 0
	_status.text = "免费创建一名 1 级忍者并上场。" if can_deploy else "请在准备阶段添加出战忍者。"


func report(message: String) -> void:
	_status.text = message


func _body_height() -> float:
	return 100.0


func _build_body() -> void:
	var label := PBSkin.label(body(), Vector2(10, 5), 200, PBSkin.FONT_BODY, PBSkin.TEXT)
	label.text = "选择测试忍者"
	_ninjas = OptionButton.new()
	_ninjas.position = Vector2(10, 23)
	_ninjas.size = Vector2(panel_rect().size.x - 20, 18)
	_ninjas.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(_ninjas, PBSkin.Tone.PLAIN)
	_ninjas.size = Vector2(panel_rect().size.x - 20, 18)
	_ninjas.get_popup().add_theme_font_size_override("font_size", PBSkin.FONT_BODY)
	_ninjas.get_popup().max_size = Vector2i(0, 420)
	body().add_child(_ninjas)
	_deploy = Button.new()
	_deploy.text = "直接出战"
	_deploy.position = Vector2(10, 49)
	_deploy.size = Vector2(86, 18)
	_deploy.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(_deploy, PBSkin.Tone.PRIMARY)
	_deploy.size = Vector2(86, 18)
	_deploy.pressed.connect(
		func() -> void:
			if _ninjas.selected >= 0:
				deploy_requested.emit(StringName(_ninjas.get_selected_metadata()))
	)
	body().add_child(_deploy)
	_status = PBSkin.label(
		body(), Vector2(10, 76), panel_rect().size.x - 20, PBSkin.FONT_BODY, PBSkin.TEXT
	)
