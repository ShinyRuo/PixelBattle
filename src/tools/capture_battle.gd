extends SceneTree
## 把战斗画面截成 PNG（看一眼对不对、去色剪影测试）。
##
## **不能加 `--headless`**：headless 下渲染服务器是空实现，截出来是一片黑，而且不报错。
##
## [codeblock]
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --path . \
##     --script res://src/tools/capture_battle.gd -- --at 400 --out shot.png
## [/codeblock]
##
## `--at` 是等多少个物理帧再截（60 帧 = 1 秒）。

const OUT_DIR := "res://build"

var _frames_to_wait: int = 300
var _out_name: String = "battle.png"
var _seed: int = 20260827
var _speed: int = 1

## 快进到第几波再截。后期波次的密度是 `COUNT_CAP` 定夺的依据（§04），
## 正常打过去要十几分钟。
var _start_wave: int = 1

## 强制敌人数量，纯视觉用。0 表示按 §04 的公式正常算。
var _enemy_count: int = 0

## 关掉自动推进，停在准备阶段截图。
var _manual: bool = false


func _initialize() -> void:
	_parse_args()

	var scene: PackedScene = load("res://scenes/battle.tscn")
	if scene == null:
		push_error("加载不了 battle.tscn")
		quit(1)
		return

	var battle: Node2D = scene.instantiate()
	# 固定种子：截图要能复现，否则两次截出来的画面没法对比。
	battle.run_seed = _seed
	battle.start_wave = _start_wave
	battle.debug_enemy_count = _enemy_count
	battle.auto_play = not _manual
	root.add_child(battle)
	battle.set("_speed", _speed)

	for _i: int in _frames_to_wait:
		await physics_frame

	# 必须等这一帧真的画完，否则拿到的是上一帧甚至空白。
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	_ensure_out_dir()
	var path: String = "%s/%s" % [OUT_DIR, _out_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("存不了 %s：%s" % [path, error_string(err)])
		quit(1)
		return

	var info: Variant = battle.get("_info")
	print("截图已存到 %s（等了 %d 个物理帧）" % [path, _frames_to_wait])
	if info != null:
		print("画面文本：%s" % (info as Label).text)
	quit()


func _ensure_out_dir() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	_manual = args.has("--manual")
	for i: int in args.size():
		if i + 1 >= args.size():
			continue
		var value: String = args[i + 1]
		match args[i]:
			"--at":
				_frames_to_wait = maxi(value.to_int(), 1)
			"--out":
				_out_name = value
			"--seed":
				_seed = value.to_int()
			"--speed":
				_speed = clampi(value.to_int(), 1, 3)
			"--wave":
				_start_wave = maxi(value.to_int(), 1)
			"--enemies":
				_enemy_count = maxi(value.to_int(), 0)
