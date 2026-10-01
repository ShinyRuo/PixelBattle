@tool
class_name PBFieldSkin
extends Resource
## 区域图是俯视圆画布，运行时压成地面椭圆；连线图朝右，左右边中点为端点。

@export var frames: Array[Texture2D] = []
@export_range(1.0, 60.0) var fps: float = 10.0
@export_range(1.0, 64.0) var link_width: float = 5.0
@export var tint: Color = Color.WHITE
@export var placeholder: bool = false
@export_range(0.1, 4.0) var area_scale: float = 1.0
## 以判定半径为单位的地面偏移，仅影响贴图。
@export var area_offset: Vector2 = Vector2.ZERO


func problem() -> String:
	if not is_finite(area_scale) or area_scale <= 0 or not area_offset.is_finite():
		return "特效缩放必须为有限正数，偏移必须有限"
	if not is_finite(fps) or fps <= 0 or not is_finite(link_width) or link_width <= 0:
		return "帧率和线宽必须为有限正数"
	var size := Vector2.ZERO
	for texture: Texture2D in frames:
		if texture == null:
			return "帧不能为空"
		if size != Vector2.ZERO and size != texture.get_size():
			return "所有帧必须同画布"
		size = texture.get_size()
	return ""


func duration() -> float:
	return float(maxi(frames.size(), 6)) / fps if placeholder else float(frames.size()) / fps
