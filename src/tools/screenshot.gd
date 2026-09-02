extends SceneTree
## 把战斗画面截成 PNG。开发用，不是游戏代码。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --path . `
##     --script res://src/tools/screenshot.gd -- --wave 20 --out build/shot.png
## ```
##
## ## 为什么要这么个东西
##
## 白模阶段每加一块面板都要回答「摆得下吗、读得懂吗」，而这两个问题
## **只能看画面**。手开一次游戏、快进到第 20 波、切到准备阶段、截图，
## 每次两分钟；改一版排版就要重来一次，于是排版就不改了。
##
## 它和 `wave_pacing.gd` / `pressure_curve.gd` 是一类东西：把一件
## 「非看不可但手做太烦」的事变成一条命令。
##
## ## 不能加 `--headless`
##
## 无头模式没有渲染器，截出来是空的。所以这个工具会真的开一个窗口 ——
## 这是它和其余 `src/tools/` 下的脚本唯一的不同。

## 截图前先跑几个渲染帧。太少的话面板还没布局完，截出来是空白控件。
##
## `--frames` 可以调大：手感那几样（伤害飘字、命中白闪、落点预示带）
## 只在真打起来之后才出现，而 30 帧的时候战斗刚开始 0.3 秒，
## 屏幕上还没有任何一发伤害 —— 那张图什么都验不了。
const WARMUP_FRAMES: int = 30

## 第几帧把按键送进去。要早于截图，好让面板有帧可以重画。
const PRESS_FRAME: int = 20

## `--press` 认得的键名。只列准备阶段真的会按的那几个。
const KEY_NAMES := {
	# `b`（换带人方式）M6-h 从界面上删了，按它不再有任何反应 ——
	# 留一个按不出效果的开关只会让人以为截图工具坏了。
	"a": KEY_A,  # 自动推进
	# `q`（接/不接任务）M5-7 没了 —— 接不接现在等于任务栏里站着几个人。
	"escape": KEY_ESCAPE,  # 收说明卡 / 收弹层 / 取消选中
	"space": KEY_SPACE,  # 暂停（战斗阶段）。截图前一刻按用 `--pause`
}

var _scene: Node
var _frames: int = 0
var _warmup: int = WARMUP_FRAMES
var _wave: int = 20
var _out: String = "res://build/shot.png"
var _auto: bool = false
var _press: Array[int] = []

## 强行「点」出战席的第几个忍者。-1 表示不点。
##
## 战场直接操作（§02）之后，信息栏和指令卡**只在选中之后才有内容** ——
## 截图工具送的是按键，点不到格子。没有这个开关的话，
## 「这两块排得下吗、读得懂吗」只能靠手开游戏回答，
## 而那正是本工具存在的理由。
var _hover: int = -1

## 摆出「正在等你点」的那一档：`attack` / `ultimate`。空 = 不摆。
var _aim: String = ""

## 截图前一刻按下暂停（M5-12）。**A 线在暂停时画全场**，
## 而那一屏正是要看的东西 —— 不暂停只画选中那一条。
##
## 和 `--press space` 不是一回事：那个按在第 20 帧，战斗还没打起来，
## 于是接下来一百帧都是同一张静止画面。这个按在**截图前两帧**。
var _pause: bool = false

## 强行摊开一层模态（`offer` / `beasts`）。空 = 不开。
## 仓库、忍具、装备栏都不在里面 —— M5-3 到 M5-5 之后它们是常驻面板。
##
## 和 `--pick` 同一个理由：这两层**只在特定操作之后才出现**
## （三选一要先掏钱、选尾兽要先点指令），而截图工具送不出那串操作。
## 没有这个开关的话，「这两层排得下吗」只能靠手开游戏回答 ——
## 而抽屉那一版恰恰是这么伸出屏幕 65 像素而没人发现的（见 [PBLayout]）。
var _modal: String = ""

## 强行选中 C 或 D（`beast` / `base`）。空 = 不选。
##
## 指令卡（J）**选中谁就换成谁能做的事**，而最宽的那一套是大本营那七格
## （「金币科技 Lv3」）—— 不选中它就永远看不到那一屏，
## 而格子宽度放不放得下正是靠这张图判断的。
var _select: String = ""

## 局种子。**0 = 每次都换一局**，也就是默认行为。
##
## 给一个固定值，同一条命令就永远出同一张图 —— 于是排版改动可以
## **逐字节对拍**：改之前截一张、改之后截一张，哈希一样就是「只搬了代码
## 没动画面」。不给种子的话两张图连波次和金币都不一样，
## 「这块面板是不是挪了两像素」只能靠肉眼猜。
var _seed: int = 0


func _initialize() -> void:
	_parse_args()
	var packed := load("res://scenes/battle.tscn") as PackedScene
	_scene = packed.instantiate()
	# 准备阶段的四块面板只在「手动」时出现 —— 要看的正是它们。
	_scene.set("auto_play", _auto)
	_scene.set("start_wave", _wave)
	if _seed != 0:
		_scene.set("run_seed", _seed)
	root.add_child(_scene)


## 返回 true 就退出。**不要写 `super._process()`** —— `SceneTree` 的这个虚函数
## 在 GDScript 侧没有父实现，引擎是从 C++ 那边回调进来的，
## 写了会在解析期就报「Cannot call the parent class' virtual function」。
## 节点自己的 `_process` 照常跑，不受这里影响。
func _process(_delta: float) -> bool:
	_frames += 1
	# 按键走 `Input.parse_input_event` 而不是直接改画面的私有字段 ——
	# 那样验的是「玩家按下去会怎样」，包括 `_unhandled_input` 那一段路。
	# 绕过去直接设字段的话，键位接错了截图照样是对的。
	if _frames == PRESS_FRAME and not _press.is_empty():
		for keycode: int in _press:
			_key(keycode)
	# 暂停按在最后 —— 前面那些帧要让战斗真的打起来（见 [member _pause]）。
	# **留六帧**，不是两帧：按下去到画面上写着「暂停」中间隔着一次输入派发
	# 和一次 `_physics_process`，两帧的余量实测会漏（截出来还在跑）。
	if _pause and _frames == maxi(_warmup - 6, PRESS_FRAME + 3):
		_key(KEY_SPACE)
	# 选中排在按键之后一帧，让面板先摆好。
	if _frames == PRESS_FRAME + 1 and _hover >= 0:
		_hover_tile()
	if _frames == PRESS_FRAME + 2 and _aim != "":
		_aim_at()
	if _frames == PRESS_FRAME + 1 and _select != "":
		_pick_slot()
	if _frames == PRESS_FRAME + 2 and _modal != "":
		_open_modal()
	if _frames < _warmup:
		return false
	var image := root.get_texture().get_image()
	var path := _out
	if not path.begins_with("res://"):
		path = "res://%s" % path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	if err != OK:
		printerr("截图存不下来（%d）：%s" % [err, path])
	else:
		print("截图已存：%s　%dx%d　第 %d 波" % [path, image.get_width(), image.get_height(), _wave])
	return true


## 送一个按键。走 `Input.parse_input_event`，理由见 [method _process]。
func _key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)


## 假装玩家点了仓库里的第 [member _hover] 个忍者。
##
## 直接发格子自己的信号，而不是去 `warp_mouse` —— 后者要等引擎下一帧
## 派发点击，而截图只有三十帧，时序很容易错开。
## 这里少验的那一段（鼠标坐标 → 点击派发）是引擎的事，不是本项目的。
func _hover_tile() -> void:
	var bay := _scene.get_node_or_null("HUD/Stash") as PBRosterBay
	if bay == null or not bay.visible:
		# 战斗阶段仓库是收起来的，而**战斗中的指令卡也要看得见**
		# （M4-e 的攻击 / 自动选敌、M5-9 的忍术）—— 那时选中的入口
		# 是战场上的忍者，不是仓库里的卡。
		_pick_fighter()
		return
	var seen: int = 0
	for tile: PBUnitTile in bay.find_children("", "PBUnitTile", true, false):
		if not tile.visible or tile.unit == null:
			continue
		if seen == _hover:
			tile.picked.emit(tile)
			return
		seen += 1
	printerr("场上没有第 %d 个忍者" % _hover)


## 摆出「正在等你点」的那一档（M5-11），好让 B / C 两条虚线入镜。
##
## 鼠标要**真的挪过去**（`warp_mouse`）—— 那两条线的终点读的是
## [method Viewport.get_mouse_position]，不挪的话终点是屏幕左上角。
func _aim_at() -> void:
	if _aim != "attack" and _aim != "ultimate":
		printerr("--aim 只认 attack / ultimate，收到：%s" % _aim)
		return
	_scene._on_command(
		PBCommandCard.CMD_ATTACK if _aim == "attack" else PBCommandCard.CMD_ULTIMATE
	)
	Input.warp_mouse(PBLayout.B_FIELD.position + PBLayout.B_FIELD.size * Vector2(0.62, 0.45))


## 战斗中假装玩家点了场上第 [member _hover] 个忍者（M5-9）。
##
## 走 `_select` 而不是伪造一次战场点击：点击要先换算屏幕坐标再做命中测试，
## 而那两样各自都已经有测试钉着（`test_battle_control.gd`）。
## 这里要的只是「指令卡在有人选中时长什么样」。
func _pick_fighter() -> void:
	var deployed: Array[PBUnit] = _scene._plan.deployed
	if _hover >= deployed.size():
		printerr("场上没有第 %d 个忍者" % _hover)
		return
	_scene._select(PBSelection.Kind.UNIT, deployed[_hover].key())


## 假装玩家点了 C（尾兽）或 D（大本营）。走的是槽位自己发的信号，
## 和 `_hover_tile` 同一条路 —— 不 `warp_mouse`，理由见那个函数。
func _pick_slot() -> void:
	var kind := PBSelection.Kind.BASE if _select == "base" else PBSelection.Kind.BEAST
	if _select != "base" and _select != "beast":
		printerr("--select 只认 base / beast，收到：%s" % _select)
		return
	(_scene.get_node("HUD/Slots") as PBFieldSlots).slot_picked.emit(kind, &"")


## 摊开一层模态。三选一那层要先真的掏一次钱 —— 摆着一组假候选
## 会让截图里的卡面和游戏里的对不上，而排版正是靠这张图判断的。
func _open_modal() -> void:
	var node := _scene.get_node_or_null("HUD/%s" % _modal.capitalize()) as PBModal
	if node == null:
		printerr("没有这一层：%s" % _modal)
		return
	if _modal == "offer":
		_scene._state.gold = 99999
		_scene._on_command(&"gacha")
		return
	_scene._open_modal(node)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--wave":
				i += 1
				_wave = int(args[i])
			"--out":
				i += 1
				_out = args[i]
			"--auto":
				_auto = true
			"--pause":
				_pause = true
			"--seed":
				i += 1
				_seed = int(args[i])
			"--pick":
				i += 1
				_hover = int(args[i])
			"--frames":
				# 截图前多跑几帧。手感那几样要打起来才看得到。
				i += 1
				_warmup = maxi(int(args[i]), PRESS_FRAME + 3)
			"--aim":
				i += 1
				_aim = args[i].strip_edges().to_lower()
			"--select":
				i += 1
				_select = args[i].strip_edges().to_lower()
			"--modal":
				i += 1
				_modal = args[i].strip_edges().to_lower()
			"--press":
				# 逗号分隔，例如 `--press b` 或 `--press q,b`。
				i += 1
				for name: String in args[i].split(",", false):
					var key: String = name.strip_edges().to_lower()
					if KEY_NAMES.has(key):
						_press.append(int(KEY_NAMES[key]))
					else:
						printerr("不认识的键：%s（认得 %s）" % [key, ", ".join(KEY_NAMES.keys())])
		i += 1
