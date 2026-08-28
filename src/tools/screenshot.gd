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
const WARMUP_FRAMES: int = 30

## 第几帧把按键送进去。要早于截图，好让面板有帧可以重画。
const PRESS_FRAME: int = 20

## `--press` 认得的键名。只列准备阶段真的会按的那几个。
const KEY_NAMES := {
	"b": KEY_B,  # 换带人方式（按战力 / 按羁绊）
	"q": KEY_Q,  # 接/不接任务
	"a": KEY_A,  # 自动推进
}

var _scene: Node
var _frames: int = 0
var _wave: int = 20
var _out: String = "res://build/shot.png"
var _auto: bool = false
var _press: Array[int] = []


func _initialize() -> void:
	_parse_args()
	var packed := load("res://scenes/battle.tscn") as PackedScene
	_scene = packed.instantiate()
	# 准备阶段的四块面板只在「手动」时出现 —— 要看的正是它们。
	_scene.set("auto_play", _auto)
	_scene.set("start_wave", _wave)
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
			var event := InputEventKey.new()
			event.keycode = keycode
			event.pressed = true
			Input.parse_input_event(event)
	if _frames < WARMUP_FRAMES:
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
