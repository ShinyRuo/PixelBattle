@tool
class_name PBBuffSkin
extends Resource
## 环身光以脚底为锚，前后两层共用画布；动画时钟取战斗 tick。

enum BlendStyle { ADDITIVE, ALPHA }

@export var blend_style: BlendStyle = BlendStyle.ADDITIVE
@export var back_frames: Array[Texture2D] = []
@export var front_frames: Array[Texture2D] = []
@export_range(1.0, 60.0) var fps: float = 10.0
@export var anchor: Vector2 = Vector2(120, 220)
@export var offset: Vector2 = Vector2.ZERO
@export_range(0.01, 4.0) var pixel_scale: float = 0.333333
@export var tint: Color = Color.WHITE
@export var placeholder: bool = false
@export var foot_ring: bool = false


func problem() -> String:
	if blend_style not in [BlendStyle.ADDITIVE, BlendStyle.ALPHA]:
		return "混合方式不支持"
	if not is_finite(fps) or fps <= 0.0 or not is_finite(pixel_scale) or pixel_scale <= 0.0:
		return "帧率与缩放必须为有限正数"
	if not anchor.is_finite() or not offset.is_finite():
		return "锚点与偏移必须为有限坐标"
	var canvas := Vector2.ZERO
	for frames: Array[Texture2D] in [back_frames, front_frames]:
		for frame: Texture2D in frames:
			if frame == null:
				return "帧不能留空"
			if canvas != Vector2.ZERO and frame.get_size() != canvas:
				return "前后层的全部帧必须同画布"
			canvas = frame.get_size()
	return ""
