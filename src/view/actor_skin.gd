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

## 源图里的人朝哪边。**只有这一个字段决定要不要 `flip_h`**，
## 而问它的路只有一条：[method flips_for]。
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
## 各有各的表现，而它们共用 [PBSkill] 一套实现 —— 区别只在这张表里。
@export var skill_anims: Dictionary = {}

## 源图朝向，见 [enum Facing]。
@export var source_faces: Facing = Facing.RIGHT

## 放大几倍。**像素档只用整数倍**，非整数会把像素栅格切碎。
##
## [member smooth] 那一档正好相反：它填的是 `1/N`（贴图比屏幕大 N 倍），
## 缩小交给 GPU，所以不存在「栅格切碎」这回事。
@export var pixel_scale: float = 1.0

## 高清档：贴图比它在屏幕上占的地方**大好几倍**，缩小交给 GPU。
##
## ## 它换到的是什么
##
## `stretch/mode` 是 `canvas_items`（M6-d），也就是**坐标系恒为 640×360，
## 但光栅化发生在窗口的真实分辨率上** —— 文字在 1080p 上清晰正是这条。
## 于是一个「41 逻辑像素高」的精灵在 1080p 上实际占 123 个真实像素。
## 贴图只有 41 像素高的话，那 123 个像素里只装得下 41 个色块的信息；
## 贴图做到 123 像素高，GPU 就能在渲染时把全部细节铺满。
##
## ## 代价
##
## **它不是像素画了。** 边缘是软的、颜色是连续的，而屏幕上其余全部东西
## （面板、卡面、白模、克制亮边）都是硬边像素。混着放看得出来 ——
## 这是一个美术方向的取舍，不是一个可以两边都要的开关。
##
## 打开的那一档**必须配 mipmap**（[member PBActorForge.scale_up] 会把
## 贴图的 `.import` 改掉）：720p 下这张图是缩小采样的，没有 mipmap
## 的表现是人一走动身上就闪，而静止截图完全看不出来。
@export var smooth: bool = false

## **脚底在画布上的位置**（像素，画布左上角为原点）。
##
## 这是整份规格里最要紧的一个数：y 排序按节点的 y 排，而节点的位置
## 恒等于落脚点（M6-a 立的）。脚底记错一格，这个人和别人的前后关系就错一格，
## **而所有坐标看起来都完全正确**。
##
## 留 [constant Vector2.ZERO] 表示「画布底边中点」，也就是规格里的默认锚。
@export var foot_offset: Vector2 = Vector2.ZERO

## 这个人的普攻子弹用哪一份 [PBShotSkin]（M8-a）。空着退回
## [method PBWhiteModel.shot]（今天那个小方块）。
##
## 挂在**形象**上而不是角色数值上：一发苦无长什么样是「这份素材的性质」，
## 和脚底锚点、源图朝向同一类东西 —— 换一套美术就该跟着换。
## 技能自己的子弹另配（[member PBSkill.shot_key]）：那是技能的性质，不是人的。
@export var shot_key: StringName = &""

## **枪口在哪**（像素，相对脚底，**向上为负 y**；未乘 [member pixel_scale]）。
##
## ## 为什么它只在渲染层生效，绝不进 sim
##
## 两条，第二条更硬：
##
## - sim 是一个**平面**，[member PBAttacker.pos] 的 y 是泳道深度不是高度 ——
##   「枪口在胸口」这句话在那边没有地方表达。
## - 进 sim 会改飞行距离 → 改命中时刻 → **改配平**。
##
## 屏幕上那条弹道因此是同一次飞行的**重新参数化**：进度还是 sim 算的
## （从 [member PBProjectile.from] 到目标走了几成），只是把两个端点
## 从脚底换成枪口和胸口。
##
## 留 [constant Vector2.ZERO] 表示按 [member height_px] 派生（约六成身高）——
## M6-m 之后人有 60 像素高，而在这之前子弹是**从脚踝射向脚踝**的。
##
## **x 会跟着朝向翻转**（由 [PBShotPool] 按飞行方向做）：填正数就是「身前」。
@export var muzzle_offset: Vector2 = Vector2.ZERO

## **子弹打在身上哪个高度**（同 [member muzzle_offset] 的坐标约定）。
## 留 [constant Vector2.ZERO] 表示按 [member height_px] 派生（半身高）。
##
## 命中特效也放在这一点上 —— 两处各配一个的话，「子弹打在胸口、
## 火花炸在脚下」迟早发生，而它不报错。
@export var hit_offset: Vector2 = Vector2.ZERO

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

## 这一帧要不要水平翻转。[param facing] 走 [member PBActorPose.facing]。
##
## ## 敌我共用这一处（M9-m）
##
## 在这之前两个池子各写了一份两行的判断，而且**符号是反的**：己方是
## `facing == FACE_LEFT`（对），敌人是 `facing == FACE_RIGHT`（错）。
## 敌人那一份的注释写着「白模画的是朝右的剪影，而敌人默认朝左，
## 所以这里的翻转是常态」—— **那句话把「敌人通常朝左」数了两遍**，
## 一遍已经在 `facing` 里了。
##
## **白模看不出来**：那是个正多边形，左右翻过来几乎一模一样。所以这条
## 从 M6-b 起一直错着，直到第一张真怪素材进来才现形 ——
## 表现是「从右往左走，人却朝着右边，像在倒着走」（玩家报的）。
## 同 M6-e 查出的那条 `draw_offset` 平方 bug：都是白模恰好取不到的那个值。
func flips_for(facing: int) -> bool:
	var flip: bool = facing == PBActorPose.FACE_LEFT
	return not flip if source_faces == Facing.LEFT else flip


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


## 把一段**非循环**动画用最后一帧补到 [param count] 帧。M9-e。
##
## ## 为什么要补
##
## 出手落在第 [member PBSimConfig.attack_hit_frame] 帧，而整段被压进一个
## 攻击间隔里（[method PBAllyPool._fit]）—— 也就是说「第几帧」这句话
## **只有在每一段都是同样多帧的时候才是同一个意思**。
##
## 库里的素材是人手挑的，3 到 6 帧都有。一段 4 帧的挥击摊在同一个间隔上，
## 出手那一刻落在它的第 3 帧 —— 手还在挥出去的路上，子弹已经飞了。
##
## 补**最后一帧**是短素材唯一不改动已有姿势的补法：等于把收招停久一点，
## 前面那几帧的时序一格都不挪。
##
## ## 只补非循环段
##
## 循环段（待机、跑动）补上去的表现是「跑两步顿一下」——
## 多出来的那几帧会在循环的接缝上停住，而它不报错。
##
## **补过一次就不再补**：资源是缓存的，[method PBActorLibrary.reload]
## 拿回来的是同一个实例，不挡住的话每重载一次就长 2 帧。
func hold_last_to(anim: StringName, count: int) -> void:
	if frames == null or not frames.has_animation(anim):
		return
	if frames.get_animation_loop(anim):
		return
	var have: int = frames.get_frame_count(anim)
	if have <= 0 or have >= count:
		return
	var last: Texture2D = frames.get_frame_texture(anim, have - 1)
	for _i: int in count - have:
		frames.add_frame(anim, last)


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


## 枪口相对脚底的**屏幕**偏移（像素）。见 [member muzzle_offset]。
##
## 默认取六成身高：那大致是一个人举手投足的高度，而且**必须高于半身**——
## 和命中点（半身高）取同一个数的话，一队人对射时子弹会连成水平的一条线，
## 看不出是谁射的。
func muzzle() -> Vector2:
	if muzzle_offset != Vector2.ZERO:
		return muzzle_offset * pixel_scale
	return Vector2(head_px() * 0.18, -head_px() * 0.62)


## 子弹打在身上哪一点的**屏幕**偏移（像素）。见 [member hit_offset]。
func chest() -> Vector2:
	if hit_offset != Vector2.ZERO:
		return hit_offset * pixel_scale
	return Vector2(0.0, -head_px() * 0.5)


## 这张皮该用哪种贴图过滤，见 [member smooth]。
##
## **两个池子共用这一个判断。** 各写一份的话「己方是高清、敌人还是最近邻」
## 这种事迟早发生，而它不报错 —— 只表现为「有些人边缘糊、有些人边缘硬」。
##
## 不打开的那一档返回 [constant CanvasItem.TEXTURE_FILTER_PARENT_NODE]
## （= 继承项目设置里的最近邻），**不是直接写最近邻**：
## 项目要是哪天改了默认过滤，白模该跟着改，而不是被这里钉死。
func filter_mode() -> CanvasItem.TextureFilter:
	if not smooth:
		return CanvasItem.TEXTURE_FILTER_PARENT_NODE
	return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
