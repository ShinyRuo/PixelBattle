class_name PBDisplay
extends RefCounted
## 窗口大小与全屏。M6-c。
##
## ## 为什么「分辨率可调」对像素游戏是一句关于**倍数**的话
##
## 游戏永远按 `640×360` 渲染（`project.godot` 的 `viewport_width/height`），
## 窗口再大也只是把那一张图放大 —— 所以「支持 1080p」不是让游戏渲染
## 1920×1080，而是让它**整数倍**放大到 1920×1080。
##
## 640×360 之所以是个好基准，正是因为主流分辨率全是它的整数倍：
##
## | 窗口 | 倍数 |
## |---|---|
## | 1280×720 | 2× |
## | **1920×1080** | **3×** |
## | 2560×1440 | 4× |
## | 3840×2160 | 6× |
##
## `stretch/scale_mode = "integer"` 把这条钉死：**非整数倍时宁可留黑边**，
## 也不把一个像素拉成 1.5 个 —— 那会让像素栅格出现宽窄不一的行列，
## 而那是像素风最刺眼的一种失真，且**只有盯着截图看才发现**。
##
## ## 为什么不做成设置菜单
##
## 这个项目还没有任何设置界面，而按键操作已经是它的既有形态
## （`A` 自动、`B` 换带人法、`1/2/3` 倍速、`R` 重开）。
## 一个只为放三个选项而生的菜单，比两个按键贵得多。

## 按 F10 循环这几档。全是 640×360 的整数倍，见类顶部那张表。
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]


## 换到 [param size] 这么大。菜单里的下拉框和 [method cycle_window] 都走它。
##
## **全屏时先退出全屏** —— 不退的话改 `size` 在全屏窗口上不生效，
## 玩家选了没反应，而这不报错。
static func set_window(size: Vector2i) -> void:
	if is_fullscreen():
		set_fullscreen(false)
	DisplayServer.window_set_size(size)
	_centre(size)


## 换到下一档窗口大小，返回换成了哪一档。
static func cycle_window() -> Vector2i:
	var current := DisplayServer.window_get_size()
	var next: int = 0
	for i: int in SIZES.size():
		if SIZES[i] == current:
			next = (i + 1) % SIZES.size()
			break
	set_window(SIZES[next])
	return SIZES[next]


## 全屏开关。返回切换之后是不是全屏。
static func toggle_fullscreen() -> bool:
	var want: bool = not is_fullscreen()
	set_fullscreen(want)
	return want


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


## 用**无边框全屏**（`WINDOW_MODE_FULLSCREEN`）而不是独占全屏：
## 切出去不会黑屏闪一下，而这个游戏本来就要和文档、Godot 编辑器来回切。
static func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)


## 当前窗口是基准分辨率的几倍（取整），1 表示还没放大。
## 只用来在信息栏里报一句 —— 真正的整数化是引擎做的。
static func scale_now() -> int:
	var size := DisplayServer.window_get_size()
	return maxi(mini(size.x / int(PBLayout.SCREEN.x), size.y / int(PBLayout.SCREEN.y)), 1)


## 换完大小把窗口挪回屏幕中间。不挪的话从 1440p 换到 720p 之后
## 窗口会缩在左上角，看起来像「换小了还跑偏了」。
static func _centre(size: Vector2i) -> void:
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
