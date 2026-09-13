class_name PBDisplay
extends RefCounted
## 窗口大小与全屏。
##
## 2D 坐标系永远是 640×360，「支持 1080p」是让它**整数倍**放大：
##
## | 窗口 | 倍数 |
## |---|---|
## | 1280×720 | 2× |
## | **1920×1080** | **3×** |
## | 2560×1440 | 4× |
## | 3840×2160 | 6× |
##
## `stretch/scale_mode = "integer"` 把这条钉死：**非整数倍时宁可留黑边**，否则像素栅格宽窄不一。

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


## 换完大小把窗口挪回屏幕中间。不挪的话从 1440p 换到 720p 之后
## 窗口会缩在左上角，看起来像「换小了还跑偏了」。
static func _centre(size: Vector2i) -> void:
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
