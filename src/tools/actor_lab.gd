class_name PBActorLab
extends Node2D
## 战场形象预览台：挑一个忍者或一种怪，把它的五段动作一段段放出来看。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot.exe --path . res://scenes/actor_lab.tscn
## ```
##
## 接素材时「对不对」分成三层，**三层全都不报错**，战斗画面里一样都验不了：
##
## 1. **皮装上了吗** —— [member PBCharacter.actor_key] 和 [member PBActorSkin.key] 拼错一个字就是「还是白模」
## 2. **脚底对齐了吗** —— 锚点错一格，前后关系错一档，而所有坐标看起来都正确
## 3. **段名对上了吗** —— [method AnimatedSprite2D.play] 遇到不存在的动画静默不播，「卡在上一帧」
##
## 这里放大到 8 倍、一段只播一段、画出画布框和脚底十字，信息栏直接写出皮是从 `data/actors/` 装的还是退回了白模。
##
## **怪也在这里看**（阵营开关，6 属性 × 5 形态）：怪的皮键是拼出来的（[method PBEnemyPool.skin_key]），
## 查不到时白模兜底要走敌人那一张（[method PBEnemyPool.white_for]），否则预览台对它唯一要回答的问题给出错的答案。
##
## **不碰 sim**：段是手点的。验的是素材那一半，状态机那一半归 `tests/test_actor_pose.gd`。

## 左边的舞台与右边的控件板。
const STAGE := Rect2(8.0, 8.0, 422.0, 344.0)
const PANEL := Rect2(438.0, 8.0, 198.0, 344.0)

## 舞台上的落脚点。**画布往上长**，所以它要贴着舞台下沿留出 8 倍放大的余量：
## 36 × 8 = 288，而 300 - 288 = 12 还在舞台里。
const FOOT := Vector2(219.0, 300.0)

const ZOOMS: Array[int] = [1, 2, 4, 8]

## 五段。**倒地也要能单独看** —— 它是唯一一段「播完就该停在最后一帧」的，
## 而循环开关写反的表现是死人在地上抽搐。
const STATES: Array = [
	["待机", PBActorPose.State.IDLE],
	["跑动", PBActorPose.State.RUN],
	["攻击", PBActorPose.State.ATTACK],
	["施法", PBActorPose.State.CAST],
	["倒地", PBActorPose.State.DEAD],
]

## 按钮的行高与行距。**20 不是 18** —— [method PBSkin.style_button] 给的
## [StyleBoxFlat] 带 2 像素内边距，[Button] 的最小尺寸因此比你写的 `size` 大，
## 排 18 的话每一行都会往下压两三像素，一行行叠起来就是上下两排咬在一起。
const ROW_H: float = 20.0
const GAP: float = 6.0
const PAD: float = 6.0

## 五种形态的中文名，**按 [method PBEnemyPool.form_of] 的下标排** ——
## 和 [constant PBEnemyPool.FORM_NAMES] 是同一排东西的两种写法
## （那边是皮键里的名字，这边是给人看的），所以长度对不上就是错的，
## `test_actor_lab.gd` 钉着。
const FOE_FORMS: Array[String] = ["近战", "远程", "精英近战", "精英远程", "BOSS"]

## 怪按三个档次枚举。**不按形态下标枚举**：白模的体型要的是档次
## （[constant PBEnemyPool.RANK_BULK]），而从形态倒推档次就是把
## [method PBEnemyPool.form_of] 反着再写一遍 —— 一把尺子两个方向，
## 而 BOSS 那一档「吃掉远近」正好让这个反函数不存在。
const FOE_RANKS: Array[int] = [PBEnemy.Rank.MINION, PBEnemy.Rank.ELITE, PBEnemy.Rank.BOSS]

const GUIDE_GROUND := Color(0.42, 0.47, 0.58, 0.9)
const GUIDE_CANVAS := Color(0.95, 0.78, 0.35, 0.55)
const GUIDE_CROSS := Color(0.42, 0.86, 0.98, 0.95)
const CROSS_ARM: float = 10.0

## 下拉框里现在摆的那一批。每条 `{"title", "key", "element", "rank"}` ——
## **两个阵营共用一种条目**，因为从这里往下（挂皮、染色、量脚底、报缺段）
## 每一步对忍者和怪都是同一句话。分成两条路的话，那几步会各长出一份，
## 而它们迟早在脚底锚点或朝向上分叉 —— 那恰恰是这个工具用来查别人的东西。
var _entries: Array[Dictionary] = []

## 现在看的是怪不是忍者。
var _foes: bool = false

var _index: int = 0
var _state: int = PBActorPose.State.IDLE
var _zoom: int = 4
var _flip: bool = false
var _guides_on: bool = true
var _paused: bool = false

## 现在挂着的皮，以及它是不是从 `data/actors/` 装出来的。
## 后者是这个场景最要紧的一个读数，见类顶部第 1 条。
var _skin: PBActorSkin = null
var _from_data: bool = false

var _sprite: AnimatedSprite2D = null
var _pick: OptionButton = null
var _title: Label = null
var _family: Button = null
var _info: RichTextLabel = null
var _ground: Line2D = null
var _canvas: Line2D = null
var _cross_x: Line2D = null
var _cross_y: Line2D = null
var _last_frame: int = -1

@onready var _stage_rect: ColorRect = $Stage
@onready var _anchor: Node2D = $Anchor
@onready var _guides: Node2D = $Guides
@onready var _ui: Control = $HUD/Panel


func _ready() -> void:
	_build_entries()
	_stage_rect.position = STAGE.position
	_stage_rect.size = STAGE.size
	_anchor.position = FOOT
	_build_stage()
	_build_panel()
	_dress()


func _process(_delta: float) -> void:
	# 帧号变了才重写信息栏。每帧重写一次 [RichTextLabel] 是白给的开销，
	# 而这里恰恰要盯着帧号看（「attack 的第一帧是不是打出去那一下」）。
	if _sprite.frame == _last_frame:
		return
	_last_frame = _sprite.frame
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_SPACE:
			_toggle_pause()
		KEY_LEFT:
			_choose(_index - 1)
		KEY_RIGHT:
			_choose(_index + 1)
		KEY_F10:
			PBDisplay.cycle_window()
		KEY_F11:
			PBDisplay.toggle_fullscreen()
		_:
			return
	get_viewport().set_input_as_handled()


## 舞台上的三样：小人、地面线、画布框 + 脚底十字。
##
## 辅助线用 [Line2D] 而不是在 `_draw` 里画：[CanvasItem] 先画自己再画子节点，
## 而画布框必须压在小人**上面**才看得出「他有没有顶出画布」。
func _build_stage() -> void:
	_sprite = AnimatedSprite2D.new()
	# **不居中**：原点要落在脚底，偏移由那张皮给（[method PBActorSkin.draw_offset]）。
	_sprite.centered = false
	_anchor.add_child(_sprite)
	_ground = _line(GUIDE_GROUND)
	_canvas = _line(GUIDE_CANVAS)
	_cross_x = _line(GUIDE_CROSS)
	_cross_y = _line(GUIDE_CROSS)


func _line(color: Color) -> Line2D:
	var node := Line2D.new()
	node.width = 1.0
	node.default_color = color
	node.antialiased = false
	_guides.add_child(node)
	return node


func _build_panel() -> void:
	PBSkin.panel(_ui, PANEL)
	var left: float = PANEL.position.x + PAD
	var width: float = PANEL.size.x - PAD * 2.0
	var y: float = PANEL.position.y + PAD

	_title = PBSkin.label(_ui, Vector2(left, y), width, PBSkin.FONT_TITLE, PBSkin.TITLE)
	_title.text = _title_line()
	y += 15.0
	_pick = OptionButton.new()
	_pick.position = Vector2(left, y)
	_pick.size = Vector2(width, 16.0)
	_pick.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(_pick, PBSkin.Tone.PLAIN)
	_fill_picker()
	_pick.item_selected.connect(_choose)
	_ui.add_child(_pick)
	y += 16.0 + GAP * 2.0

	y = _build_states(left, width, y)
	y = _build_playback(left, width, y)
	y = _build_zoom(left, width, y)
	y = _build_toggles(left, width, y)

	_info = PBSkin.rich(_ui, Rect2(left, y, width, PANEL.position.y + PANEL.size.y - y - PAD))


func _build_states(left: float, width: float, top: float) -> float:
	PBSkin.label(_ui, Vector2(left, top), width, PBSkin.FONT_BODY, PBSkin.DIM).text = "动作"
	var y: float = top + 12.0
	var cell: float = (width - GAP * 2.0) / 3.0
	for i: int in STATES.size():
		var row: Array = STATES[i]
		var at := Vector2(left + float(i % 3) * (cell + GAP), y + float(i / 3) * (ROW_H + GAP))
		var state: int = row[1] as int
		_button(row[0] as String, Rect2(at, Vector2(cell, ROW_H)), func() -> void: _play(state))
	return y + (ROW_H + GAP) * 2.0 + GAP


func _build_playback(left: float, width: float, top: float) -> float:
	PBSkin.label(_ui, Vector2(left, top), width, PBSkin.FONT_BODY, PBSkin.DIM).text = "播放"
	var y: float = top + 12.0
	var cell: float = (width - GAP * 2.0) / 3.0
	_button("暂停/继续", Rect2(Vector2(left, y), Vector2(cell, ROW_H)), _toggle_pause)
	_button(
		"◀ 帧", Rect2(Vector2(left + cell + GAP, y), Vector2(cell, ROW_H)), func() -> void: _step(-1)
	)
	_button(
		"帧 ▶",
		Rect2(Vector2(left + (cell + GAP) * 2.0, y), Vector2(cell, ROW_H)),
		func() -> void: _step(1)
	)
	return y + ROW_H + GAP * 2.0


func _build_zoom(left: float, width: float, top: float) -> float:
	PBSkin.label(_ui, Vector2(left, top), width, PBSkin.FONT_BODY, PBSkin.DIM).text = "放大"
	var y: float = top + 12.0
	var cell: float = (width - GAP * 3.0) / 4.0
	for i: int in ZOOMS.size():
		var zoom: int = ZOOMS[i]
		_button(
			"%d×" % zoom,
			Rect2(Vector2(left + float(i) * (cell + GAP), y), Vector2(cell, ROW_H)),
			func() -> void: _set_zoom(zoom)
		)
	return y + ROW_H + GAP * 2.0


## 三个开关挤一行。**阵营那个挤进这一行、不另起一行**：面板高度是排满的
## （下面那块信息栏是「剩下多少给多少」），多一行就从信息栏身上扣 26 像素，
## 而那块正是这个工具的产出 —— 五行里裁掉一行的表现是「来源那一行看不见了」。
func _build_toggles(left: float, width: float, top: float) -> float:
	var cell: float = (width - GAP * 2.0) / 3.0
	_family = _button(
		_family_label(), Rect2(Vector2(left, top), Vector2(cell, ROW_H)), _swap_family
	)
	_button(
		"翻转朝向",
		Rect2(Vector2(left + cell + GAP, top), Vector2(cell, ROW_H)),
		func() -> void:
			_flip = not _flip
			_face()
			_refresh()
	)
	_button(
		"辅助线",
		Rect2(Vector2(left + (cell + GAP) * 2.0, top), Vector2(cell, ROW_H)),
		func() -> void:
			_guides_on = not _guides_on
			_guides.visible = _guides_on
	)
	return top + ROW_H + GAP * 2.0


func _button(text: String, rect: Rect2, on_press: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(node, PBSkin.Tone.PLAIN)
	node.pressed.connect(on_press)
	_ui.add_child(node)
	return node


## 下拉框上那一行。**带上属性**：白模一系一个颜色，不写出来的话
## 挑了半天不知道自己在看火还是雷。
func _title_of(character: PBCharacter) -> String:
	var element: String = PBUnitTile.ELEMENT_NAMES.get(character.element, "?")
	return "%s · %s" % [PBLocale.of_character(character), element]


## 下拉框里摆哪一批。**换阵营整份重建，两批不混在一张表里** ——
## 混着摆的话，想看第 3 种怪要先划过 30 个忍者，
## 而这个工具的用法恰恰是「一种一种往下走」（←→ 就是干这个的）。
func _build_entries() -> void:
	_entries.clear()
	if _foes:
		_build_foes()
		return
	for character: PBCharacter in PBCharacterLoader.table().all():
		(
			_entries
			. append(
				{
					"title": _title_of(character),
					"key": character.actor_key,
					"element": character.element,
					"rank": PBEnemy.Rank.MINION,
				}
			)
		)


## 那 30 种怪：6 属性 × 5 形态。
##
## **按「档次 × 远近」枚举，再靠 [method PBEnemyPool.form_of] 去重**，
## 而不是直接数到 5：BOSS 那一档吃掉了远近这一维，所以 (BOSS, 远) 和
## (BOSS, 近) 是同一种，`seen` 挡掉后一个。这样枚举出来的键和战斗里
## 查的是同一个函数（[method PBEnemyPool.skin_key]），
## 而**档次是顺手拿到的** —— 白模的体型正要它。
func _build_foes() -> void:
	for element: PBElement.Type in PBEnemyPool.ELEMENT_NAMES:
		var seen: Dictionary = {}
		for rank: int in FOE_RANKS:
			for ranged: bool in [false, true]:
				var form: int = PBEnemyPool.form_of(rank, ranged)
				if seen.has(form):
					continue
				seen[form] = true
				(
					_entries
					. append(
						{
							"title": _foe_title(element, form),
							"key": PBEnemyPool.skin_key(element, rank, ranged),
							"element": element,
							"rank": rank,
						}
					)
				)


## 怪那一行：「火 · 精英近战」。**没有名字可写** —— 怪没有 [PBCharacter]，
## 属性和形态就是它全部的身份，也正是皮键的两半。
func _foe_title(element: PBElement.Type, form: int) -> String:
	return "%s · %s" % [PBUnitTile.ELEMENT_NAMES.get(element, "?"), FOE_FORMS[form]]


func _fill_picker() -> void:
	_pick.clear()
	for entry: Dictionary in _entries:
		_pick.add_item(String(entry["title"]))
	if not _entries.is_empty():
		_pick.select(_index)


## 换阵营。**下拉框、标题、按钮三处一起换** ——
## 少换一处的表现是「标题写着忍者，舞台上站着一只怪」。
func _swap_family() -> void:
	_foes = not _foes
	_index = 0
	_build_entries()
	_title.text = _title_line()
	_family.text = _family_label()
	_fill_picker()
	_dress()


func _title_line() -> String:
	return "战场形象预览 · %s" % ("怪物" if _foes else "忍者")


## 按钮上写的是**按下去会发生什么**，不是现在在看什么 —— 后者标题栏
## 已经写着了，两处都写「现在」的话这个按钮就成了一个没有动词的标签。
func _family_label() -> String:
	return "看忍者" if _foes else "看怪物"


func _entry() -> Dictionary:
	if _index < 0 or _index >= _entries.size():
		return {}
	return _entries[_index]


## 这一条该去 [PBActorLibrary] 里查哪个键。忍者是角色表里填的，
## 怪是拼出来的 —— 而**两边查不到的后果一模一样**：安静地退回白模。
func _key() -> StringName:
	var entry := _entry()
	if not entry.has("key"):
		return &""
	return entry["key"]


func _choose(index: int) -> void:
	if _entries.is_empty():
		return
	_index = posmod(index, _entries.size())
	_pick.select(_index)
	_dress()


## 换一张皮。**没配就退回白模** —— 和 [method PBAllyPool._dress] 同一条规矩，
## 而这里额外把「走了哪一条」记下来给信息栏（[member _from_data]）。
func _dress() -> void:
	_skin = null
	var key: StringName = _key()
	if key != &"":
		_skin = PBActorLibrary.skin_for(key)
	_from_data = _skin != null
	if _skin == null:
		_skin = _white_model()
	_sprite.sprite_frames = _skin.frames
	_sprite.offset = _skin.draw_offset()
	_sprite.modulate = _tint()
	_apply_zoom()
	_play(_state)


func _play(state: int) -> void:
	_state = state
	_sprite.play(_skin.anim_for(state))
	if _paused:
		_sprite.pause()
	_face()
	_lay_guides()
	_refresh()


## 朝向**和两个池子同一把尺子**（[method PBActorSkin.flips_for]）—— 专门验朝向的工具不能和它要验的东西各说各的。
func _face() -> void:
	_sprite.flip_h = _skin.flips_for(PBActorPose.FACE_LEFT if _flip else PBActorPose.FACE_RIGHT)


func _toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		_sprite.pause()
	else:
		_sprite.play()
	_refresh()


## 单帧步进。**先停住** —— 不停的话下一个渲染帧就把你刚挪到的那一帧盖掉了。
func _step(by: int) -> void:
	_paused = true
	_sprite.pause()
	var count: int = _frame_count()
	if count <= 0:
		return
	_sprite.set_frame_and_progress(posmod(_sprite.frame + by, count), 0.0)
	_refresh()


func _set_zoom(zoom: int) -> void:
	_zoom = maxi(zoom, 1)
	_apply_zoom()
	_lay_guides()
	_refresh()


## 放大只改**节点的缩放**，不改 [member Sprite2D.offset]：offset 在缩放之前作用，两边都乘一遍的话
## 人会浮在地面线上方一整个身高（放大 1 倍时看不出来）。
func _apply_zoom() -> void:
	_sprite.scale = Vector2.ONE * (_skin.pixel_scale * float(_zoom))


## 查不到真素材时退回哪张白模。**两个阵营不是同一张**：己方那张是个方块人，
## 怪那张是按属性定边数、按档次定体型的多边形（[method PBEnemyPool.white_for]）。
## 退回己方那张的话，预览台会对「这一种怪在游戏里长什么样」——
## 它唯一要回答的问题 —— 给出一个错的答案。
func _white_model() -> PBActorSkin:
	var entry := _entry()
	if not _foes or entry.is_empty():
		return PBWhiteModel.ally()
	var element: PBElement.Type = entry["element"]
	var rank: int = entry["rank"]
	return PBEnemyPool.white_for(element, rank)


## 白模按属性染色，真素材不染（[member PBActorSkin.tint_by_element]）。
func _tint() -> Color:
	var entry := _entry()
	if not _skin.tint_by_element or entry.is_empty():
		return Color.WHITE
	var element: PBElement.Type = entry["element"]
	return PBEnemyPool.ELEMENT_COLORS.get(element, Color.WHITE)


func _frame_count() -> int:
	if _skin.frames == null:
		return 0
	return _skin.frames.get_frame_count(_sprite.animation)


## 地面线、画布框、脚底十字。三样都画在**屏幕坐标**里，
## 因为它们要量的正是「精灵被摆到了哪」。
func _lay_guides() -> void:
	var scale: float = _skin.pixel_scale * float(_zoom)
	var canvas: Vector2 = _skin.canvas_size() * scale
	var top_left: Vector2 = FOOT + _sprite.offset * scale
	_ground.points = PackedVector2Array(
		[Vector2(STAGE.position.x + 4.0, FOOT.y), Vector2(STAGE.end.x - 4.0, FOOT.y)]
	)
	_canvas.points = PackedVector2Array(
		[
			top_left,
			top_left + Vector2(canvas.x, 0.0),
			top_left + canvas,
			top_left + Vector2(0.0, canvas.y),
			top_left,
		]
	)
	_cross_x.points = PackedVector2Array(
		[FOOT - Vector2(CROSS_ARM, 0.0), FOOT + Vector2(CROSS_ARM, 0.0)]
	)
	_cross_y.points = PackedVector2Array(
		[FOOT - Vector2(0.0, CROSS_ARM), FOOT + Vector2(0.0, CROSS_ARM)]
	)


## 信息栏。**头两行是这个场景存在的理由**：这张皮从哪来、段名有没有对上。
func _refresh() -> void:
	if _info == null:
		return
	var lines: Array[String] = []
	var source: String = (
		PBSkin.tint("data/actors", PBSkin.GOOD) if _from_data else PBSkin.tint("白模兜底", PBSkin.WARN)
	)
	var key: String = String(_key())
	lines.append("来源　%s　key「%s」" % [source, key if key != "" else "（空）"])
	lines.append(_missing_line())
	lines.append(
		"段　%s　帧 %d/%d" % [String(_sprite.animation), _sprite.frame + 1, maxi(_frame_count(), 1)]
	)
	var canvas: Vector2 = _skin.canvas_size()
	lines.append(
		(
			"画布 %d×%d　脚底 %s　身高 %d"
			% [int(canvas.x), int(canvas.y), _skin.anchor(), int(_skin.height_px)]
		)
	)
	lines.append(
		"放大 %d×　朝%s　%s" % [_zoom, "左" if _sprite.flip_h else "右", "暂停" if _paused else "播放中"]
	)
	lines.append(PBSkin.tint("空格暂停　←→ 换一个　Esc 退出", PBSkin.DIM))
	_info.text = "\n".join(lines)


## 哪几段是**退回来的**（表里没有那个名字）。
##
## [method PBActorSkin.resolve] 的兜底是有意的（缺一段该「他不动」，
## 不该整个人消失），但它同时把「段名拼错了」这件事藏了起来 ——
## 这一行就是把它端出来。
func _missing_line() -> String:
	var gone: Array[String] = []
	for row: Array in STATES:
		var state: int = row[1] as int
		if _skin.anim_for(state) != _nominal(state):
			gone.append(row[0] as String)
	if gone.is_empty():
		return PBSkin.tint("五段齐全", PBSkin.GOOD)
	return PBSkin.tint("缺段：%s（已退回）" % "、".join(gone), PBSkin.BAD)


## 这一档**本来**该播哪一段（不走兜底）。
func _nominal(state: int) -> StringName:
	match state:
		PBActorPose.State.RUN:
			return _skin.anim_run
		PBActorPose.State.ATTACK:
			return _skin.anim_attack
		PBActorPose.State.CAST:
			return _skin.anim_cast
		PBActorPose.State.DEAD:
			return _skin.anim_dead
		_:
			return _skin.anim_idle
