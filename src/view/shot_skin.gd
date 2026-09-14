class_name PBShotSkin
extends Resource
## 一发子弹**长什么样**，以及它命中那一下**炸开长什么样**。
##
## **两样放在同一份资源里**：分开的话「配了子弹忘了配特效」的表现是打中之后什么都不发生，而它不报错。
## 和 [PBActorSkin] 同构：换皮只往 `data/shots/` 丢一份 `.tres`、在表里填键，`src/` 一行不动。
## 普攻子弹填名册（[member PBCharacter.shot_key]），技能子弹填技能表（[member PBSkill.shot_key]）。
## 编辑器底栏「战场特效」面板从图集一路生成到这份资源（[PBShotForge]）。
## 空着也能跑：[method PBWhiteModel.shot] 按同一套字段现造一份。

## 查这份子弹用的键，对上 [member PBCharacter.shot_key] / [member PBSkill.shot_key]。
@export var key: StringName = &""

@export var frames: SpriteFrames = null

## 飞行中那一段。**源图一律朝右**（和 [member spin] 一起用）。
@export var anim_fly: StringName = &"fly"

## 命中那一下。播一遍就收，不循环。**可以不配**：没有这一段时命中用默认火花（见 [method PBShotPool._spark]）。
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
## 不按属性：子弹上属性色会和敌人抢辨识，这一层只说「有几发正朝我飞」（[constant PBShotPool.COLOR]）。
## 真素材再染一层会把美术定的颜色拉偏。
@export var tint_by_side: bool = true

## 飞行段用**加法混合**叠上去。黑底出图的发光类（火球、查克拉弹）为真，洋红底的实体（苦无）为假 ——
## 规格见 `Docs/素材规格_特效.md` §2.2。
##
## **两段各一个开关**：一枚苦无（实体、普通混合）打中炸开的是一团火花（发光、加法混合），合成一个的话总有一段是错的。
## 实体用加法混合的表现是「钢刃半透明、压在亮处就看不见」；发光类用普通混合在暗处还凑合，亮处会发灰。
@export var additive_fly: bool = false

## 命中段用加法混合，见 [member additive_fly]。
@export var additive_hit: bool = false


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


## [param anim] 这一段该不该用加法混合，见 [member additive_fly]。**认不出是哪一段就按飞行段算。**
func additive_for(anim: StringName) -> bool:
	return additive_hit if has(anim_hit) and anim == anim_hit else additive_fly


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
