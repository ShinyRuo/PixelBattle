@tool
class_name PBFxShotPage
extends HBoxContainer
## 「战场特效」面板的「子弹」一页：**切图 → 生成子弹资源 → 配给忍者**，从上到下就是操作顺序。
##
## 左边一栏是操作，右边是预览（[PBFxPreview]）。流水线全在别处：切图 [PBFxForge]、装资源和改名册 [PBShotForge]，
## 这里只接线、说话、让编辑器重扫。
##
## **这里用到的每个类都得是 `@tool`**（[PBFxForge]、[PBShotForge]、[PBRosterSheet]、[PBPortraitForge]）：
## 编辑器里不带它的脚本 `.new()` 出来只是个占位，调它的方法什么都不发生、也不报错 —— 表现是「按钮按了没反应」。
## 只读写导出字段的资源（[PBShotSkin]、[PBCharacter]）不用，占位照样存得下那些字段。
##
## 做成插件换到的东西同「战场形象」：编辑器能当场导入刚写的 PNG，「切 → 导入 → 开 mipmap → 再导入 → 装表」是一个按钮，
## 命令行得分四个进程（`scripts/make_fx.ps1`）。

## 左边那一栏多宽。
const SIDE_WIDTH: float = 320.0

var _forge := PBShotForge.new()
var _key_edit: LineEdit
var _fly: PBFxSegment
var _hit: PBFxSegment
var _hit_check: CheckBox
## 命中段整块（切图那一段 + 命中帧率）。不要爆炸特效时整块藏起来。
var _hit_group: VBoxContainer
var _spin_check: CheckBox
var _fly_fps: SpinBox
var _hit_fps: SpinBox
var _ninja_pick: OptionButton
var _users_label: Label
var _status: RichTextLabel
var _preview: PBFxPreview


func _ready() -> void:
	name = "子弹"
	add_child(_build_side())
	_preview = PBFxPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview)
	_refresh_ninjas()
	_say(
		"新子弹：填键 → 飞行段选图、切图 →（要爆炸特效再切命中段）→ 看预览"
		+ " → 生成子弹资源 → 选忍者、设为普攻子弹。"
	)


## 左边一栏。**包一层滚动、状态栏留在滚动区外**，理由同「战场形象」面板：面板高度是人拖出来的。
func _build_side() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(SIDE_WIDTH + 14.0, 0.0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_key_edit = LineEdit.new()
	_key_edit.placeholder_text = "kunai、fire_ball……"
	_key_edit.tooltip_text = "子弹键：小写英文、数字、下划线。它是 assets/fx 下的目录名，也是名册里填的那个值"
	_key_edit.text_submitted.connect(func(_t: String) -> void: _on_load())
	_key_edit.text_changed.connect(func(_t: String) -> void: _refresh_users())
	side.add_child(_titled("子弹键", _key_edit))
	side.add_child(_button("读这个键已经切好的帧", _on_load))

	side.add_child(HSeparator.new())
	_fly = _segment(PBShotForge.FLY, "飞行段（朝右画）", 48, 3)
	side.add_child(_fly)
	var fly_speed := HBoxContainer.new()
	_fly_fps = _fps_box(fly_speed, "飞行帧率", _forge.fly_fps)
	side.add_child(fly_speed)
	_spin_check = CheckBox.new()
	_spin_check.text = "飞行中转向飞行方向（圆球类可以关）"
	_spin_check.button_pressed = true
	side.add_child(_spin_check)

	side.add_child(HSeparator.new())
	_hit_check = CheckBox.new()
	_hit_check.text = "子弹有爆炸特效（不勾就用默认火花）"
	_hit_check.button_pressed = true
	_hit_check.toggled.connect(func(_on: bool) -> void: _use_hit(_on))
	side.add_child(_hit_check)
	_hit_group = VBoxContainer.new()
	_hit = _segment(PBShotForge.HIT, "命中段（爆炸特效）", 120, 4)
	_hit_group.add_child(_hit)
	var hit_speed := HBoxContainer.new()
	_hit_fps = _fps_box(hit_speed, "命中帧率", _forge.hit_fps)
	_hit_group.add_child(hit_speed)
	side.add_child(_hit_group)

	side.add_child(HSeparator.new())
	side.add_child(_button("生成子弹资源", _on_build))

	side.add_child(HSeparator.new())
	_ninja_pick = OptionButton.new()
	_ninja_pick.fit_to_longest_item = false
	side.add_child(_titled("忍者（括号里是现在配的普攻子弹）", _ninja_pick))
	side.add_child(_button("设为普攻子弹", _on_assign))
	side.add_child(_button("取消这个忍者的普攻子弹（回白模）", _on_unassign))
	_users_label = Label.new()
	_users_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_users_label)

	scroll.add_child(side)
	column.add_child(scroll)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(0.0, 64.0)
	column.add_child(_status)
	return column


# ── 切图 ────────────────────────────────────────────────────────


func _segment(anim: StringName, title: String, size: int, frames: int) -> PBFxSegment:
	var segment := PBFxSegment.new(anim, title, size, frames)
	segment.said.connect(_say)
	segment.changed.connect(_refresh_preview)
	segment.cut_requested.connect(func() -> void: _on_cut(segment))
	return segment


func _on_cut(segment: PBFxSegment) -> void:
	var key := _key()
	var bad := PBShotForge.key_error(key)
	if bad != "":
		_say(_red(bad))
		return
	var err := segment.cut(_forge.frame_dir(key))
	if err != "":
		_say(_red(err))
		return
	_say(_green(segment.summary()) + "。切好了就按「生成子弹资源」。")
	await _rescan()


func _on_load() -> void:
	var key := _key()
	var bad := PBShotForge.key_error(key)
	if bad != "":
		_say(_red(bad))
		return
	var dir := _forge.frame_dir(key)
	var fly: int = _fly.load_from(dir)
	var hit: int = _hit.load_from(dir)
	_refresh_users()
	if fly == 0 and hit == 0:
		_say("%s 下还没有帧 —— 新子弹，选图切一次。" % dir)
		return
	# 盘上有命中帧就当它有爆炸特效，没有就收起那一段 —— 读回来的样子和上次生成时一致。
	_hit_check.set_pressed_no_signal(hit > 0)
	_use_hit(hit > 0)
	_say("读回来了：%s；%s。" % [_fly.summary(), _hit.summary() if hit > 0 else "没有爆炸特效"])


## 要不要爆炸特效（命中段）。**不要就把那一段整块藏起来**，预览也只播飞行段；生成时不装命中段。
func _use_hit(on: bool) -> void:
	_hit_group.visible = on
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview == null:
		return
	_preview.show_segment(0, _fly.images, _fly_fps.value, _fly.additive())
	var hit: Array[Image] = []
	if _hit_check.button_pressed:
		hit = _hit.images
	_preview.show_segment(1, hit, _hit_fps.value, _hit.additive())


# ── 生成与配置 ──────────────────────────────────────────────────


## 生成 `data/shots/<键>.tres`。**前后各重扫一次**：前一次把刚切的 PNG 导进来（装表要读导入后的贴图），
## 后一次让 mipmap 那一改生效、并让编辑器认出新资源。
func _on_build() -> void:
	var key := _key()
	var bad := PBShotForge.key_error(key)
	if bad != "":
		_say(_red(bad))
		return
	await _rescan()
	_forge.fly_fps = _fly_fps.value
	_forge.hit_fps = _hit_fps.value
	_forge.spin = _spin_check.button_pressed
	_forge.additive_fly = _fly.additive()
	_forge.additive_hit = _hit.additive()
	_forge.with_hit = _hit_check.button_pressed
	var err := _forge.build(key)
	if err != "":
		_say(_red(err))
		return
	await _rescan()
	_refresh_users()
	var kind: String = "带爆炸特效" if _forge.with_hit else "不带爆炸特效，打中用默认火花"
	var done: String = _green("子弹资源生成好了（%s）：%s" % [kind, _forge.shot_path(key)])
	_say(done + "。选一个忍者，按「设为普攻子弹」。")


func _on_assign() -> void:
	var key := _key()
	var bad := PBShotForge.key_error(key)
	if bad != "":
		_say(_red(bad))
		return
	_apply(key)


func _on_unassign() -> void:
	_apply("")


func _apply(key: String) -> void:
	var id := _picked_ninja()
	if id == "":
		_say(_red("先选一个忍者。"))
		return
	var err := _forge.assign(id, key)
	if err != "":
		_say(_red(err))
		return
	await _rescan()
	_refresh_ninjas()
	if key == "":
		_say(_green("%s 的普攻子弹取消了，回到白模。" % id))
	else:
		_say(_green("%s 的普攻子弹换成了 %s。" % [id, key]) + "进游戏看一眼。")


## 重铺忍者下拉框，保住当前选中的那个。
func _refresh_ninjas() -> void:
	var keep := _picked_ninja()
	_ninja_pick.clear()
	for one: Dictionary in _forge.roster_shots():
		var shot: String = String(one["shot"])
		_ninja_pick.add_item("%s %s（%s）" % [one["id"], one["name"], "白模" if shot == "" else shot])
		_ninja_pick.set_item_metadata(_ninja_pick.item_count - 1, one["id"])
		if one["id"] == keep:
			_ninja_pick.select(_ninja_pick.item_count - 1)
	_refresh_users()


## 「谁在用这颗子弹」。换子弹前先看一眼，免得改了一份资源、却不知道另外三个人也跟着变了。
func _refresh_users() -> void:
	var key := _key()
	if key == "":
		_users_label.text = ""
		return
	var users := PackedStringArray()
	for one: Dictionary in _forge.roster_shots():
		if String(one["shot"]) == key:
			users.append("%s %s" % [one["id"], one["name"]])
	_users_label.text = (
		"%s 还没有忍者在用。" % key if users.is_empty() else "在用 %s 的：%s" % [key, "、".join(users)]
	)


## 让编辑器把刚写的文件导进来。同 [method PBActorForgePanel._rescan]：
## 走 [method Engine.get_singleton] 而不是直接写 `EditorInterface`（游戏进程里没有那个单例，GUT 会解析不过）；
## **轮询而不是等信号**（没有变化时 `filesystem_changed` 不发，会永远等下去）。
func _rescan() -> void:
	var editor := Engine.get_singleton(&"EditorInterface")
	if editor == null:
		return
	var files: Object = editor.get_resource_filesystem()
	files.call("scan")
	for _tick: int in 600:
		await get_tree().process_frame
		if not files.call("is_scanning"):
			return


# ── 小工具 ──────────────────────────────────────────────────────


func _key() -> String:
	return _key_edit.text.strip_edges()


func _picked_ninja() -> String:
	if _ninja_pick == null or _ninja_pick.selected < 0:
		return ""
	return String(_ninja_pick.get_item_metadata(_ninja_pick.selected))


func _say(text: String) -> void:
	_status.text = text


func _red(text: String) -> String:
	return "[color=#e06666]%s[/color]" % text


func _green(text: String) -> String:
	return "[color=#71d08c]%s[/color]" % text


func _fps_box(row: HBoxContainer, label: String, value: float) -> SpinBox:
	var text := Label.new()
	text.text = label
	row.add_child(text)
	var box := SpinBox.new()
	box.min_value = 1.0
	box.max_value = 60.0
	box.value = value
	box.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	row.add_child(box)
	return box


func _titled(title: String, node: Control) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	box.add_child(label)
	box.add_child(node)
	return box


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button
