@tool
class_name PBCastArtPage
extends PBBuffArtPage
## 命名起手光资源，沿用环身光编辑器；技能绑定是独立步骤。

var _key: LineEdit


func _init() -> void:
	_bindings.output_dir = "res://data/cast_art"
	asset_dir = "res://assets/fx/casts"
	cast_preview = true


func _ready() -> void:
	super._ready()
	name = "起手光效"


func _build_choices() -> void:
	_key = LineEdit.new()
	_key.placeholder_text = "光效键，例如 castGlowA；填写后点击新建/读取"
	_key.text = "castGlowA"
	add_child(_key)
	_key.text_submitted.connect(func(_text: String) -> void: _select())
	_button(self, "新建 / 读取此光效", _select)
	_buffs = OptionButton.new()
	add_child(_buffs)
	_button(self, "刷新已有光效", _refresh)
	_buffs.item_selected.connect(_choose_existing)
	_refresh()


func _refresh() -> void:
	_buffs.clear()
	for key: String in PBCastArtBindings.new().keys():
		_buffs.add_item(key)
		_buffs.set_item_metadata(_buffs.item_count - 1, key)


func _choose_existing(index: int) -> void:
	_key.text = str(_buffs.get_item_metadata(index))
	_select()


func _id() -> String:
	return _key.text.strip_edges()
