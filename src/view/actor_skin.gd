class_name PBActorSkin
extends Resource
## 一个战场形象：一份 [SpriteFrames] + 它和这个游戏之间的全部约定。M6-b。
##
## ## 换皮的边界就画在这个类上
##
## §14 铁律 5 是「换皮 = 改表，`src/` 一行不动」。角色数值那一半
## M2-a 就交给 [PBCharacter] 了，**形象这一半一直没有承载体** ——
## 白模方块的颜色、大小、血条挂多高全写死在 [PBAllyPool] 里。
##
## 所以这里存的不只是图：**脚底在画布的哪一点、源图朝哪边、要不要按属性染色**
## 全是「这份素材的性质」，不是渲染层的常量。写在渲染层的话，
## 换一套画得高一点的素材就得回去改代码，而那正是铁律 5 要避免的事。
##
## ## 为什么是 [AnimatedSprite2D] 而不是 [AnimationTree]
##
## 需要的只有「一次播一段、按状态切」（§这一步只有 idle / run / attack
## 三段通用 + 逐角色的忍术段）。[AnimationTree] 解决的是混合与过渡，
## 那一套的配置成本要摊在 30 个角色上，而它换来的东西这里一个都用不上。
##
## ## 空着也能跑
##
## `assets/` 现在一个素材都没有，所以真实情况是**每个角色都没有皮**。
## [PBWhiteModel] 按同一套字段现造一份白模，于是这条链路从今天起就是通的 ——
## 真素材进来时改的是 `data/actors/*.tres`，[PBAllyPool] 一行不动。

## 源图里的人朝哪边。**只有这一个字段决定要不要 `flip_h`。**
##
## 写成数据而不是「一律画成朝右」：外包回来的素材朝哪边由画的人定，
## 为这件事返工一遍全部资源没有道理，而记错方向的表现是
## 「所有人都背对着敌人打」——看得见，但要盯着看才看得出。
enum Facing { RIGHT, LEFT }

## 查这张皮用的键，对上 [member PBCharacter.actor_key]。
@export var key: StringName = &""

@export var frames: SpriteFrames = null

## 三段通用状态对应的动画名。**留空就退回 [member anim_idle]** ——
## 缺一段的表现该是「他不动」，不是整个人消失。
@export var anim_idle: StringName = &"idle"
@export var anim_run: StringName = &"run"
@export var anim_attack: StringName = &"attack"

## 大招施法段。**没有就用攻击段**：施法延迟只有半秒出头，
## 那半秒里一动不动比播错一段更难看。
@export var anim_cast: StringName = &"cast"

## 倒地。没有就用待机段并靠 [constant PBAllyPool.DEAD_COLOR] 压暗。
@export var anim_dead: StringName = &"dead"

## 逐角色的忍术动画：`{忍术 id: 动画名}`。§09 的功能档与 §11 的尾兽大招
## 各有各的表现，而它们共用 [PBUltimate] 一套实现 —— 区别只在这张表里。
@export var skill_anims: Dictionary = {}

## 源图朝向，见 [enum Facing]。
@export var source_faces: Facing = Facing.RIGHT

## 放大几倍。像素素材只用整数倍，非整数会把像素栅格切碎。
@export var pixel_scale: float = 1.0

## **脚底在画布上的位置**（像素，画布左上角为原点）。
##
## 这是整份规格里最要紧的一个数：y 排序按节点的 y 排，而节点的位置
## 恒等于落脚点（M6-a 立的）。脚底记错一格，这个人和别人的前后关系就错一格，
## **而所有坐标看起来都完全正确**。
##
## 留 [constant Vector2.ZERO] 表示「画布底边中点」，也就是规格里的默认锚。
@export var foot_offset: Vector2 = Vector2.ZERO

## 按属性染色（[member CanvasItem.modulate]）。**白模是 `true`，真素材是 `false`。**
##
## 白模只有一个形状，五系全靠色相分；真素材各画各的，再染一层
## 会把美术定的颜色全部拉偏。
@export var tint_by_element: bool = false

## 站着时从脚底到头顶有多高（像素，未乘 [member pixel_scale]）。
## 血条挂在这个高度之上 —— 读贴图尺寸的话，一张留白很多的画布会把血条顶到天上。
##
## 默认值跟着白模走（[constant PBWhiteModel.ALLY_HEIGHT]）：真素材和白模
## 同屏站在一起，两边不一样高的表现是「这个人怎么比别人矮一截」。
@export var height_px: float = 41.0


## [param state] 走 [enum PBActorPose.State]。返回一个 [member frames] 里
## **确实存在**的动画名 —— 查不到就一路退回待机，最后退回第一段。
func anim_for(state: int) -> StringName:
	var wanted: StringName = anim_idle
	match state:
		PBActorPose.State.RUN:
			wanted = anim_run
		PBActorPose.State.ATTACK:
			wanted = anim_attack
		PBActorPose.State.CAST:
			wanted = anim_cast if has(anim_cast) else anim_attack
		PBActorPose.State.DEAD:
			wanted = anim_dead
	return resolve(wanted)


## 某个忍术的动画名。表里没有就退回攻击段。
func skill_anim(skill_id: StringName) -> StringName:
	return resolve(skill_anims.get(skill_id, anim_attack))


## 这段动画在不在。
func has(anim: StringName) -> bool:
	return frames != null and frames.has_animation(anim)


## 把一个动画名落成一个真的存在的名字。
##
## **这一层兜底必须有。** `.tres` 里的名字和图集里的名字对不上不报错 ——
## [method AnimatedSprite2D.play] 遇到不存在的动画只是静默不播，
## 表现是「这个角色卡在上一帧」，而从现象反推极难。
func resolve(anim: StringName) -> StringName:
	if frames == null:
		return anim
	if frames.has_animation(anim):
		return anim
	if frames.has_animation(anim_idle):
		return anim_idle
	var names: PackedStringArray = frames.get_animation_names()
	return StringName(names[0]) if names.size() > 0 else anim


## 一整段播完要多少秒（按 [member frames] 里配的帧率，不含 `speed_scale`）。
## 攻击段要压进一个攻击间隔里，靠的就是这个数，见 [method PBAllyPool._fit].
func anim_seconds(anim: StringName) -> float:
	if frames == null or not frames.has_animation(anim):
		return 0.0
	var fps: float = maxf(frames.get_animation_speed(anim), 0.001)
	return float(frames.get_frame_count(anim)) / fps


## 精灵该怎么摆才能让**画布上的脚底落在节点原点上**。
## 配合 `centered = false` 用（[member Sprite2D.centered]）。
##
## **这里不乘 [member pixel_scale]。** [member Sprite2D.offset] 是在节点缩放
## **之前**作用的，而放大是靠 [member Node2D.scale] 做的 —— 两处各乘一遍
## 等于把偏移平方，人会浮在地面上方一整个身高。
##
## `pixel_scale` 恒为 1 的时候看不出来（1 的平方还是 1），而白模正好是 1，
## 所以这一条要等真素材填 2 的那天才发作，**且不报错**。
func draw_offset() -> Vector2:
	return -anchor()


## 脚底在画布上的像素坐标。见 [member foot_offset]。
func anchor() -> Vector2:
	if foot_offset != Vector2.ZERO:
		return foot_offset
	var canvas := canvas_size()
	return Vector2(canvas.x * 0.5, canvas.y)


## 画布尺寸。取第一段第一帧的贴图大小 —— 规格要求全部帧同尺寸。
func canvas_size() -> Vector2:
	if frames == null:
		return Vector2.ZERO
	var names: PackedStringArray = frames.get_animation_names()
	if names.is_empty():
		return Vector2.ZERO
	var first: Texture2D = frames.get_frame_texture(StringName(names[0]), 0)
	return Vector2.ZERO if first == null else first.get_size()


## 血条该挂在脚底上方多少像素。
func head_px() -> float:
	return height_px * pixel_scale
