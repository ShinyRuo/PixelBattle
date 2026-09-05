class_name PBShotSkin
extends Resource
## 一发子弹**长什么样**，以及它命中那一下**炸开长什么样**。M8-a。
##
## ## 为什么两样放在同一份资源里
##
## 分成「子弹表」和「命中特效表」两份的话，「配了子弹忘了配特效」的表现是
## **打中之后屏幕上什么都不发生** —— 而它不报错。两者本来就是一套美术
## （火球和火球炸开、苦无和苦无入肉），拆开只会多一处能对不上的地方。
##
## ## 和 [PBActorSkin] 同构
##
## 一份 [SpriteFrames] 加它和这个游戏之间的约定。换皮的边界画在这个类上：
## 往 `data/shots/` 丢一份 `.tres`、在角色皮上填一个 [member PBActorSkin.shot_key]，
## `src/` 一行不动（§14 铁律 5）。
##
## ## 空着也能跑
##
## `assets/` 里一张子弹图都没有，所以真实情况是**谁都没配**。
## [method PBWhiteModel.shot] 按同一套字段现造一份：子弹还是今天那个小方块，
## 命中是一圈很短的火花。**链路因此今天就是通的**，
## 和 [PBWhiteModel] 顶上那条理由逐字相同。

## 查这份子弹用的键，对上 [member PBActorSkin.shot_key]。
@export var key: StringName = &""

@export var frames: SpriteFrames = null

## 飞行中那一段。**源图一律朝右**（和 [member spin] 一起用）。
@export var anim_fly: StringName = &"fly"

## 命中那一下。播一遍就收，不循环。
@export var anim_hit: StringName = &"hit"

## 放大几倍。规矩同 [member PBActorSkin.pixel_scale]：
## 像素档只用整数倍，高清档填 `1/N`。
@export var pixel_scale: float = 1.0

## 高清档（贴图比屏幕上占的地方大好几倍），见 [member PBActorSkin.smooth]。
@export var smooth: bool = false

## 飞行中要不要**转向飞行方向**。
##
## 有方向的东西（苦无、箭、火球拖尾）必须转，圆球状的不必 ——
## 一律转的话，一颗对称的球每帧转一个角度，边缘会抖。
@export var spin: bool = true

## 按**敌我**上色（[member CanvasItem.modulate]）。**白模是 `true`，真素材是 `false`。**
##
## 不是按属性 —— 那是给单位用的（§02 的第一层视觉编码）。子弹上属性色的话，
## 一屏小方块会和敌人抢辨识；而「有几发正朝我飞」才是这一层唯一要说的话
## （M4-c 定的两个颜色，见 [constant PBShotPool.COLOR]）。
##
## 真素材各画各的，再染一层会把美术定的颜色拉偏 ——
## 同 [member PBActorSkin.tint_by_element]。
@export var tint_by_side: bool = true


## 这段动画在不在。
func has(anim: StringName) -> bool:
	return frames != null and frames.has_animation(anim)


## 把一个动画名落成一个**确实存在**的名字。
##
## 这一层兜底必须有，理由同 [method PBActorSkin.resolve]：
## [method AnimatedSprite2D.play] 遇到不存在的动画只是**静默不播**，
## 表现是「子弹卡在上一帧」或者「命中什么都没有」，而从现象反推极难。
func resolve(anim: StringName) -> StringName:
	if frames == null:
		return anim
	if frames.has_animation(anim):
		return anim
	var names: PackedStringArray = frames.get_animation_names()
	return StringName(names[0]) if names.size() > 0 else anim


## 命中那一段播完要多少秒。没配就返回 0（调用方退回自己的默认时长）。
func hit_seconds() -> float:
	var anim: StringName = resolve(anim_hit)
	if not has(anim):
		return 0.0
	var fps: float = maxf(frames.get_animation_speed(anim), 0.001)
	return float(frames.get_frame_count(anim)) / fps


## 该用哪种贴图过滤，见 [member smooth]。规矩同 [method PBActorSkin.filter_mode] ——
## 不打开的那一档返回**继承**而不是写死最近邻。
func filter_mode() -> CanvasItem.TextureFilter:
	if not smooth:
		return CanvasItem.TEXTURE_FILTER_PARENT_NODE
	return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
