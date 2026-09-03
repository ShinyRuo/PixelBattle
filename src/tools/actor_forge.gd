@tool
class_name PBActorForge
extends RefCounted
## 视频帧 → 成品战场形象的那条流水线本身。M6-f 写在 `make_actor.gd` 里，
## **M6-l 抽出来**，好让命令行和编辑器插件走同一条。
##
## ## 为什么必须只有一份
##
## 两条路要做的事一模一样：抠背景→量→挑帧→定画布→缩→坐到底边→描边。
## 各写一份的话，「命令行出的素材和插件出的素材尺寸差一像素」这种事迟早发生，
## 而它**不报错** —— 表现是同一个角色的两段动画高矮不一，
## 或者脚陷进地里半格。这个项目为「同一件事两把尺子」付过很多次代价。
##
## 所以这里是唯一的实现：[method PBActorForgeCli._run_frames]（命令行）
## 和 [PBActorForgePanel]（编辑器插件）都只是它的调用方。
##
## ## 为什么脏活分给 ffmpeg
##
## 一帧 1280×720 是 92 万像素，四段共 388 帧 —— GDScript 逐像素扫一遍要几分钟。
## 所以**抠洋红、预乘 alpha、粗缩**三件事全在 ffmpeg 里做完（[constant FILTER]），
## 这边拿到的已经是 [constant MID] 的 RGBA。剩下的重活也一律走 [Image] 的
## C++ 接口，真正的逐像素循环只发生在**最后那张几十像素见方的画布上**。
##
## ## 为什么中间那一趟必须是「预乘」的
##
## 抠完背景之后背景像素是全透明的，但它的 RGB 仍然是洋红。缩放会把相邻像素
## 平均起来 —— 于是人物边缘会渗出一圈粉色，**而 alpha 看起来完全正常**。
## 预乘（`rgb *= a`）让透明像素的 RGB 归零，插值因此只会稀释、不会染色；
## 缩完再除回来（[method _unpremultiply]）。

## 目标身高（**屏幕像素**，脚底到头顶）。M6-m 从 41 抬到 60，玩家定的。
##
## **这是 B 这个框放得下的极限，不是一个还能再调的数**：画布要装下人
## 加一点留白，而上限是 [constant PBLayout.SPRITE_HEADROOM] = 64。
## 再高就要压地面带或者撑大 B，两条都改配平。
##
## **白模没有跟着抬**（玩家定的「白模先不动」）—— 它的画布是方的
## （手臂要摆得开），按同样比例放到 60 要 79 见方，装不进 64。
## 所以真素材和白模现在**差一截**，那是已知的、暂时的，
## 见 [constant PBWhiteModel.ALLY_HEIGHT]。
##
## 高清档（[member scale_up]）里这个数仍然是「屏幕上多大」，
## 「一张图有多少像素」由 [method texture_height] 回答 —— M6-l 之前两者是一回事。
const TARGET_HEIGHT: int = 60

## 画布上下左右各留几格。**不能太大** —— 画布高度超过
## [constant PBLayout.SPRITE_HEADROOM] 的话最上面那排的头会戳进顶栏。
##
## **顶上这个 M6-m 从 6 压到 2**：身高抬到 60 之后，64 的上限里
## 只剩这么多了。压它是安全的 —— [method fit_canvas] 里那个 `tall`
## 已经取了**挑中的全部帧**的最大值（跑动的起伏、出拳的伸展都在里面），
## 这一截纯粹是余量，不是给谁腾地方。
##
## 左右那个不受上限管（画布宽度没有天花板），所以没动。
const PAD_TOP: int = 2
const PAD_SIDE: int = 5

## 中间帧的尺寸。**它比成品大得多是有意的**：源视频里人物约 360 像素高，
## 直接一步缩到 41 会把细节碾成噪点；先按面积平均缩到这一档，
## 最后一档降采样在 [method compose] 里连着对齐一起做。
const MID := Vector2i(960, 540)

## ffmpeg 那条滤镜链。三段缺一不可：
## `colorkey` 抠洋红、`premultiply` 防边缘渗粉（见类顶部）、
## `scale=area` 按面积平均粗缩。
##
## **`scripts/make_actor.ps1` 里必须是同一条**（那条路自己调 ffmpeg）——
## `test_actor_forge.gd` 逐字符钉着这一条，改了一边不改另一边会红。
const FILTER := (
	"colorkey=0xFF00FF:0.34:0.0,format=rgba,premultiply=inplace=1,scale=960:540:flags=area"
)

## 半透明像素归到哪一边。像素画不许有半透明边缘（规格第 8 节），
## 所以这里是**硬阈值**不是渐变。
const ALPHA_CUT: float = 0.45

## 高清档（[member scale_up] > 1）用的阈值。**只切掉抠背景剩下的那圈毛**，
## 剩下的半透明照原样留着 —— 软边正是这一档买的东西。
const SOFT_CUT: float = 0.08

## 高清档把贴图做到屏幕尺寸的几倍。**3 = 1080p**：坐标系恒为 640×360，
## 1080p 是它的 3 倍（M6-c），所以 41 逻辑像素在那儿正好占 123 个真实像素 ——
## 贴图做到 123 高，1080p 下就是 1:1，一个像素都不浪费也一个都不缺。
##
## 再大只有 4K 用得上，而代价是贴图面积翻倍。见 [member PBActorSkin.smooth]。
const HD_FACTOR: int = 3

## 描边：把剪影最外圈那一层压暗多少、压向哪个色。
## **压暗而不是往外扩一圈** —— 扩出去的话人会比目标身高高 2 像素。
const RIM_COLOR := Color(0.06, 0.06, 0.09, 1.0)
const RIM_MIX: float = 0.55

## 量人物大小用哪一档分位数。**不用最大值** —— AI 视频里总有一两帧
## 人物突然放大，取最大值会让整套素材跟着那一帧缩小。
const REF_PERCENTILE: float = 0.90

## 掐头去尾。AI 视频的头尾几帧经常在「淡入」或者姿势还没稳定。
const TRIM: int = 8

## 五段的播放参数。`want` 是自动挑要几帧，`pick` 是挑帧策略，见 [method select]。
const ANIMS: Array = [
	{"name": &"idle", "fps": 4.0, "loop": true, "want": 2, "pick": "breath"},
	{"name": &"run", "fps": 10.0, "loop": true, "want": 4, "pick": "cycle"},
	{"name": &"attack", "fps": 12.0, "loop": false, "want": 3, "pick": "reach"},
	{"name": &"dead", "fps": 4.0, "loop": false, "want": 1, "pick": "settle"},
]

## 剪影比对用的小掩码尺寸。按包围盒归一化之后再缩到这么大，
## 所以它**不受人物平移与缩放影响** —— 比的是姿势，不是位置。
const MASK := Vector2i(16, 24)

## 成品帧和形象表写到哪儿。做成字段是为了测试能写进临时目录，
## **不是为了让调用方随便改** —— 游戏只在这两处找素材。
var assets_dir: String = "res://assets/actors"
var data_dir: String = "res://data/actors"

## 贴图做到屏幕尺寸的几倍。**默认就是高清档** —— M6-n 起像素档不再出新素材
## （玩家定的），这个字段留着是因为 `1` 那一档是整条流水线的退化参照，
## 测试还在两档之间对拍；真要把像素档请回来，改的是这个默认值。
##
## 它同时改四件事，而这四件缺一不可：目标身高、留白、画布上限、
## 以及**边缘要不要硬切**。只放大不改后三样的话，人会被头顶那道上限压回去，
## 边缘会被切成锯齿 —— 而两样都不报错。
var scale_up: int = HD_FACTOR

## 上一次 [method fit_canvas] 定下来的画布。[method compose] 读它。
var canvas := Vector2i.ZERO

## 量出来的实际身高（像素）。写进 [member PBActorSkin.height_px]。
var measured_height: float = float(TARGET_HEIGHT)

## 上一次 [method fit_canvas] 有没有撞上头顶那道上限。**撞上了就是切了头**，
## 调用方要说出来 —— 见那个函数里的注释。
var clamped: bool = false


## 这一段的播放参数。段名不认识时返回空字典。
static func spec_of(anim: String) -> Dictionary:
	for spec: Dictionary in ANIMS:
		if String(spec["name"]) == anim:
			return spec
	return {}


## 成品**贴图**里人有多高（像素）。像素档就是 [constant TARGET_HEIGHT]，
## 高清档是它的 [member scale_up] 倍 —— 屏幕上仍然是 41，多出来的全是细节。
func texture_height() -> int:
	return TARGET_HEIGHT * maxi(scale_up, 1)


## 四个段名，按 [constant ANIMS] 的顺序。
static func anim_names() -> PackedStringArray:
	var out := PackedStringArray()
	for spec: Dictionary in ANIMS:
		out.append(String(spec["name"]))
	return out


## 找 ffmpeg。**winget 装的那份在用户 PATH 里，但已经开着的进程拿的是
## 安装前那份快照** —— 所以显式兜一下那个目录（和 `make_actor.ps1` 同一条）。
static func ffmpeg_path() -> String:
	if OS.execute("ffmpeg", ["-version"], []) == 0:
		return "ffmpeg"
	var linked: String = OS.get_environment("LOCALAPPDATA").path_join(
		"Microsoft/WinGet/Links/ffmpeg.exe"
	)
	return linked if FileAccess.file_exists(linked) else ""


## 把一段视频抽成中间帧，写进 [param out_dir]。**返回错误信息，空串 = 成功。**
##
## 每次都先清空目标目录：留着上一次的帧的话，新视频短一些时尾巴上会
## 挂着上一条的几帧，而它们照样会被量、被挑中 —— 不报错，只是出错了人。
func extract(video: String, out_dir: String) -> String:
	var exe := ffmpeg_path()
	if exe == "":
		return "找不到 ffmpeg。装一个：winget install Gyan.FFmpeg（装完新开一个终端）"
	if not FileAccess.file_exists(video):
		return "找不到视频：%s" % video
	_wipe(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var args: PackedStringArray = [
		"-v", "error", "-y", "-i", ProjectSettings.globalize_path(video),
		"-vf", FILTER, "-fps_mode", "passthrough",
		ProjectSettings.globalize_path(out_dir).path_join("%03d.png"),
	]
	var log: Array = []
	var code := OS.execute(exe, args, log, true)
	if code != 0:
		return "ffmpeg 失败（%d）：%s" % [code, "\n".join(PackedStringArray(log))]
	return ""


## 量一整段的每一帧：人物包围盒、脚底中点、归一化剪影。
##
## **全部走 [method Image.get_used_rect]**（C++）—— 逐像素找边界的话，
## 97 帧 × 23 万像素在 GDScript 里要跑一分多钟。
##
## **只留量出来的那几个数，不留图。** 一段 97 帧 × 960×540 RGBA 是 200 MB，
## 四段一起攥在手里就爆了 —— 真正要用的只有挑中的那几帧，
## [method compose] 那时再按路径读回来。
func measure(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".png"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var image := Image.load_from_file(path)
		if image == null:
			continue
		var used := image.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		out.append(
			{
				"path": path,
				"used": used,
				"feet_x": _feet_x(image, used),
				"mask": _mask(image, used),
			}
		)
	return out


## 每一段各自的缩放比。
##
## **逐段归一化，不是全套用同一个比。** AI 视频每一条里人物大小都不完全一样，
## 用同一个比的话玩家会看到「他一跑起来就长高两像素」——
## 而那比「跑动和待机的身高差一点」难看得多。
##
## `dead` 借用 `idle` 的比：人躺着，包围盒高度不是身高。
func scales(takes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var idle_scale: float = 1.0
	for spec: Dictionary in ANIMS:
		var anim: String = String(spec["name"])
		if anim == "dead" or not takes.has(anim):
			continue
		var reference := _reference_height(takes[anim] as Array)
		var scale: float = float(texture_height()) / maxf(reference, 1.0)
		out[anim] = scale
		if anim == "idle":
			idle_scale = scale
			measured_height = reference * scale
	out["dead"] = idle_scale
	return out


## 画布定多大：装得下**挑中的那几帧**，再各留一点边。写进 [member canvas]。
##
## 算出来而不是写死：出拳那一帧比站着宽得多，写死的话手会被裁掉，
## **而裁掉的那一截只是不见了，不报错**。
##
## **先挑帧再定画布**（[param chosen] 是必须的）：按全部 97 帧算的话，
## AI 视频里任何一帧的杂点都会把画布撑宽，而那一帧根本不会进游戏。
func fit_canvas(takes: Dictionary, scale_of: Dictionary, chosen: Dictionary) -> Vector2i:
	var half: float = 0.0
	var tall: float = 0.0
	for anim: String in chosen:
		if not takes.has(anim):
			continue
		var scale: float = float(scale_of.get(anim, 1.0))
		for index: int in chosen[anim] as Array[int]:
			var shot: Dictionary = takes[anim][index]
			var used: Rect2i = shot["used"]
			var feet: float = shot["feet_x"]
			half = maxf(half, (feet - float(used.position.x)) * scale)
			half = maxf(half, (float(used.end.x) - feet) * scale)
			tall = maxf(tall, float(used.size.y) * scale)
	var width: int = (ceili(half) + PAD_SIDE * scale_up) * 2
	var height: int = ceili(tall) + PAD_TOP * scale_up
	# 高度撞上头顶那一截就压回去 —— 超了的话最上面那排的头会戳进 A 顶栏，
	# 而 `tests/test_layout.gd` 钉的是 [PBLayout] 的常量，钉不到素材。
	#
	# **上限也要乘 [member scale_up]**：那道墙量的是**逻辑像素**，
	# 而高清档的画布是贴图像素 —— 忘了乘的话人会被压掉三分之二，
	# 而画布、坐标、锚点全部看起来完全正确。
	var ceiling: int = int(PBLayout.SPRITE_HEADROOM) * scale_up
	# **压回去这一下要留个话。** 被压掉的那一截是**头**（脚坐在底边上，
	# 见 [method _seat]），而画布、坐标、锚点全部看起来完全正确 ——
	# 不说的话人只会觉得「这个角色怎么是平头」。
	clamped = height > ceiling
	height = mini(height, ceiling)
	canvas = Vector2i(width + (width % 2), height + (height % 2))
	return canvas


## 把一帧摆进画布：脚底中点落在**画布底边中点**上，然后缩到位。
##
## ## 对齐做两遍，最后一遍在成品分辨率上
##
## 先在中间分辨率上粗摆一次，只为了别把人裁掉；**真正的对齐在缩完之后**
## （[method _seat]）。只在缩之前对齐的话，人会浮在地面上方一像素 ——
## 最底那排鞋底只有薄薄一条，面积平均之后 alpha 掉到 [constant ALPHA_CUT]
## 以下，整排被切掉了，**而所有数字看起来都完全正确**
## （实测：预览台上画布框贴着地面线，人却悬空）。
func compose(shot: Dictionary, scale: float) -> Image:
	var factor: float = 1.0 / maxf(scale, 0.0001)
	var work := Vector2i(
		maxi(roundi(float(canvas.x) * factor), 1), maxi(roundi(float(canvas.y) * factor), 1)
	)
	var image := Image.create_empty(work.x, work.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var used: Rect2i = shot["used"]
	var at := Vector2i(roundi(float(work.x) * 0.5 - float(shot["feet_x"])), work.y - used.end.y)
	var source := Image.load_from_file(shot["path"])
	if source == null:
		return image
	image.blit_rect(source, Rect2i(Vector2i.ZERO, MID), at)
	# 缩放仍在**预乘**空间里做，见类顶部那段。
	image.resize(canvas.x, canvas.y, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(image)
	image = _seat(image)
	_rim(image)
	return image


## 自动挑帧。**靠量，不靠数格子** —— 数格子十次有八次差一帧，
## 而差一帧的表现是「跑起来一瘸一拐」或者「先掉血、后挥手」。
##
## 插件里它是「自动挑」那个按钮：先让它出一版，人再逐帧改。
func select(shots: Array, how: String, want: int) -> Array[int]:
	if shots.is_empty():
		return [] as Array[int]
	match how:
		"cycle":
			return _pick_cycle(shots, want)
		"reach":
			return _pick_reach(shots, want)
		"settle":
			return _pick_settle(shots)
		_:
			return _pick_breath(shots, want)


## 这个角色**已经在盘上**的帧有多大。没有帧就是 [constant Vector2i.ZERO]。
##
## 一段一段导的时候，它就是「画布」这件事的真相：规格要求同一个角色每一帧
## 尺寸完全一致（[method PBActorSkin.canvas_size] 只读第一帧算锚点），
## 所以新导的这一段必须和它对齐，见 [method recanvas]。
func canvas_on_disk(key: String) -> Vector2i:
	var dir := DirAccess.open("%s/%s" % [assets_dir, key])
	if dir == null:
		return Vector2i.ZERO
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".png"):
			continue
		var image := Image.load_from_file("%s/%s/%s" % [assets_dir, key, file_name])
		if image != null:
			return image.get_size()
	return Vector2i.ZERO


## 把这个角色已经在盘上的帧重新裱到 [param to] 这个画布上。
## **返回错误信息，空串 = 成功。**
##
## ## 为什么这是安全的
##
## **纯补透明边，一个像素都不重采样。** 脚坐在底边中点上（[method _seat]），
## 所以变高就在**顶上**补、变宽就**两边各补一半** —— 两个画布尺寸都是偶数
## （[method fit_canvas] 最后那一步凑的），所以一半是整数，脚不会偏半格。
##
## ## 什么时候要它
##
## 一段一段导的时候，后导的那一段可能比前面几段宽（出拳那一段几乎总是最宽）。
## 不裱的话同一个角色的帧尺寸就不一致了 —— 锚点只对得上第一帧，
## 人会在动画之间上下跳，而 `tests/test_actor_data.gd` 会红。
func recanvas(key: String, to: Vector2i) -> String:
	var dir_path: String = "%s/%s" % [assets_dir, key]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".png"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var was := Image.load_from_file(path)
		if was == null or was.get_size() == to:
			continue
		var grown := Image.create_empty(to.x, to.y, false, Image.FORMAT_RGBA8)
		grown.fill(Color(0.0, 0.0, 0.0, 0.0))
		var at := Vector2i((to.x - was.get_width()) / 2, to.y - was.get_height())
		grown.blit_rect(was, Rect2i(Vector2i.ZERO, was.get_size()), at)
		var err := grown.save_png(path)
		if err != OK:
			return "重裱不了（%d）：%s" % [err, path]
	return ""


## 把一段的成品帧写进 `assets/actors/<key>/`。**返回错误信息，空串 = 成功。**
##
## **多出来的旧帧要删掉。** 这次挑了 3 帧、上次挑了 5 帧的话，
## `attack_3/4` 会留在原地，而 [method link] 是**一直数到断号为止**的 ——
## 于是上一次那两帧会跟着进游戏，不报错。
##
## **只删多出来的那几张，前面的原地覆盖。** 全删再重写的话，
## 每一张的 `.import` 都会重新生成一个新的 `uid` —— 素材一个像素没变，
## `git diff` 里却是十个文件都改了，而真正改了什么就淹在里面了。
func save_frames(key: String, anim: String, images: Array) -> String:
	var out_dir: String = "%s/%s" % [assets_dir, key]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_drop_extra(out_dir, anim, images.size())
	for slot: int in images.size():
		var path: String = "%s/%s_%d.png" % [out_dir, anim, slot]
		var err := (images[slot] as Image).save_png(path)
		if err != OK:
			return "存不下来（%d）：%s" % [err, path]
	return ""


## 把已经导入的 PNG 装成 [SpriteFrames] + [PBActorSkin]，写进 `data/actors/`。
## **返回错误信息，空串 = 成功。**
##
## **命令行那条路必须和第一趟分开跑**，中间隔一次 `--import`：引擎只认
## 导入过的贴图，刚写到磁盘上的 PNG 在同一次进程里 `load()` 不出来。
## 编辑器插件那条路没有这个问题 —— 它能让编辑器当场重扫一遍
## （[method PBActorForgePanel._rescan]），这也是做成插件最实在的一处好处。
func link(key: String) -> String:
	if scale_up > 1:
		_want_mipmaps(key)
	var frames := SpriteFrames.new()
	for spec: Dictionary in ANIMS:
		var anim: StringName = spec["name"]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(spec["fps"]))
		frames.set_animation_loop(anim, bool(spec["loop"]))
		var slot: int = 0
		while true:
			var path: String = "%s/%s/%s_%d.png" % [assets_dir, key, anim, slot]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(anim, load(path) as Texture2D)
			slot += 1
		if slot == 0:
			return "这一段一帧都没有：%s（导出跑过吗？）" % anim
	frames.remove_animation(&"default")

	# **图集放子目录里，不和形象表并排。**
	# [method PBActorLibrary.load_from] 把 `data/actors/` 下的每个 `.tres`
	# 都当成一张 [PBActorSkin]，装不进来就 `push_error` —— 那条报错是对的
	# （放错类型就该说），所以图集不能放在它眼皮底下。它不递归子目录。
	DirAccess.make_dir_recursive_absolute("%s/frames" % data_dir)
	var err := ResourceSaver.save(frames, "%s/frames/%s.tres" % [data_dir, key])
	if err != OK:
		return "图集存不下来（%d）" % err

	var skin := PBActorSkin.new()
	skin.key = StringName(key)
	skin.frames = frames
	skin.anim_idle = &"idle"
	skin.anim_run = &"run"
	skin.anim_attack = &"attack"
	# **施法段没有素材就留一个查不到的名字**，[method PBActorSkin.anim_for]
	# 会自己退回攻击段。指到 `idle` 的话施法半秒会变成站着不动，更看不出在放招。
	skin.anim_cast = &"cast"
	skin.anim_dead = &"dead"
	skin.source_faces = PBActorSkin.Facing.RIGHT
	# 高清档填 `1/N`：贴图是屏幕尺寸的 N 倍，节点缩回去，缩小交给 GPU。
	# [member PBActorSkin.head_px] 因此照旧算出 41 —— 血条、影子、克制圈
	# 全部读那个数，两档共用一份。
	skin.pixel_scale = 1.0 / float(maxi(scale_up, 1))
	skin.smooth = scale_up > 1
	# 脚底已经对到画布底边中点上了，所以留默认锚（见 [member PBActorSkin.foot_offset]）。
	skin.foot_offset = Vector2.ZERO
	# **真素材不染色**：它自己有颜色，再乘一层属性色会把美术定的色拉偏。
	skin.tint_by_element = false
	skin.height_px = float(texture_height())
	err = ResourceSaver.save(skin, "%s/%s.tres" % [data_dir, key])
	return "" if err == OK else "形象表存不下来（%d）" % err


# ── 量 ──────────────────────────────────────────────────────────


## 脚底那一截的横向中点。
##
## **只看最下面一成，不看整个包围盒。** 出拳那几帧手臂伸出去老远，
## 按包围盒中心对齐的话人会在挥拳的瞬间横向弹一下 —— 而脚是不动的。
func _feet_x(image: Image, used: Rect2i) -> float:
	var band: int = maxi(roundi(float(used.size.y) * 0.10), 2)
	var strip := Rect2i(used.position.x, used.end.y - band, used.size.x, band)
	var region := image.get_region(strip)
	var inner := region.get_used_rect()
	if inner.size.x <= 0:
		return float(used.position.x) + float(used.size.x) * 0.5
	return float(strip.position.x + inner.position.x) + float(inner.size.x) * 0.5


## 归一化剪影：按包围盒裁出来再缩到 [constant MASK]，只留「有没有像素」。
## 用来比姿势 —— 平移和缩放都被归一化掉了。
func _mask(image: Image, used: Rect2i) -> PackedByteArray:
	var small := image.get_region(used)
	small.resize(MASK.x, MASK.y, Image.INTERPOLATE_BILINEAR)
	var bits := PackedByteArray()
	bits.resize(MASK.x * MASK.y)
	for y: int in MASK.y:
		for x: int in MASK.x:
			bits[y * MASK.x + x] = 1 if small.get_pixel(x, y).a >= 0.5 else 0
	return bits


## 这一段里人物「站直了」有多高。取 [constant REF_PERCENTILE] 分位数。
##
## **片子太短就不掐头去尾。** 原来那版无条件掐 [constant TRIM] 帧，
## 于是一段只有几帧的素材会掐出一个**空**区间，函数返回 1.0 —— 缩放比
## 因此变成 41 倍，人被放大到撑爆画布再被压回头顶余量。
## AI 视频是 97 帧，这条路上永远走不到；**插件里人可以自己剪一段短的**，
## 而那时的表现是「出来的人糊成一团」，没有任何一句报错
## （`test_actor_forge.gd` 那条 3 帧的用例就是抓这个的）。
func _reference_height(shots: Array) -> float:
	var trim: int = TRIM if shots.size() > TRIM * 3 else 0
	var heights: Array[float] = []
	for i: int in range(trim, maxi(shots.size() - trim, 1)):
		heights.append(float((shots[i]["used"] as Rect2i).size.y))
	if heights.is_empty():
		return 1.0
	heights.sort()
	var at: int = clampi(roundi(float(heights.size() - 1) * REF_PERCENTILE), 0, heights.size() - 1)
	return heights[at]


# ── 切 ──────────────────────────────────────────────────────────


## 把已经缩到成品尺寸的这一帧**精确坐到画布底边中点上**。
##
## 纵向按最下面那排实心像素，横向按脚底那一截的中点（不是整个包围盒的中点，
## 理由同 [method _feet_x]）。
func _seat(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return image
	var feet: float = _feet_x(image, used)
	var move := Vector2i(roundi(float(canvas.x) * 0.5 - feet), canvas.y - used.end.y)
	if move == Vector2i.ZERO:
		return image
	var seated := Image.create_empty(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	seated.fill(Color(0.0, 0.0, 0.0, 0.0))
	seated.blit_rect(image, Rect2i(Vector2i.ZERO, canvas), move)
	return seated


## 除回 alpha。像素档顺手把半透明像素归到两边去（像素画不许有半透明边缘）；
## **高清档留着它们** —— 软边正是那一档买的东西，切硬了等于把 GPU 缩出来的
## 那点好处又扔掉。两档只差一个阈值和一个「alpha 写不写死 1」。
func _unpremultiply(image: Image) -> void:
	var hard: bool = scale_up <= 1
	var cut: float = ALPHA_CUT if hard else SOFT_CUT
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < cut:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var inv: float = 1.0 / pixel.a
			image.set_pixel(
				x,
				y,
				Color(
					minf(pixel.r * inv, 1.0),
					minf(pixel.g * inv, 1.0),
					minf(pixel.b * inv, 1.0),
					1.0 if hard else pixel.a
				)
			)


## 把剪影最外圈压暗一档。
##
## **这不是装饰。** 同一列会叠着七八个人，没有描边的话几个同系角色在屏幕上
## 是一根实心色条 —— 数不出几个人，也点不中中间那个（M6-c 实测）。
## 素材本身画了描边，但从 360 像素缩到 41 之后那一圈基本没了。
##
## **压暗现有像素，不往外扩**：扩一圈等于把身高抬高 2 像素。
## **高清档这一圈要加粗到 [member scale_up] 像素**，而且「外面」的判据要从
## 「完全透明」抬到「半透明以下」—— 软边那一圈的 alpha 是连续的，
## 照旧只认 0 的话压暗的是最外面那几乎看不见的一层，等于没描。
func _rim(image: Image) -> void:
	var solid: float = 0.0 if scale_up <= 1 else 0.5
	var edge: Array[Vector2i] = []
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a <= solid:
				continue
			if _on_edge(image, x, y, solid):
				edge.append(Vector2i(x, y))
	for at: Vector2i in edge:
		var was := image.get_pixel(at.x, at.y)
		var dark := was.lerp(RIM_COLOR, RIM_MIX)
		# **alpha 原样留着。** [method Color.lerp] 连 alpha 一起插值，而
		# [constant RIM_COLOR] 是不透明的 —— 跟着插的话软边会被描边推硬，
		# 表现是人身上镶了一道锯齿边，而颜色看起来完全正常。
		image.set_pixel(at.x, at.y, Color(dark.r, dark.g, dark.b, was.a))


## 这个实心像素离外面还有几格。**先收集再写**（和 [method PBWhiteModel._outline]
## 同一条）：边判边写的话刚压暗的那一圈会被当成背景，一趟扫下来压出三四层。
func _on_edge(image: Image, x: int, y: int, solid: float) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for far: int in range(1, maxi(scale_up, 1) + 1):
			var at := Vector2i(x + step.x * far, y + step.y * far)
			if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
				return true
			if image.get_pixel(at.x, at.y).a <= solid:
				return true
	return false


# ── 自动挑帧 ────────────────────────────────────────────────────


## 待机：呼吸的最高点和最低点。那两帧之间差的就是一两像素的起伏，
## 而那正是一段 idle 的全部信息量。
func _pick_breath(shots: Array, want: int) -> Array[int]:
	var low: int = mini(TRIM, shots.size() - 1)
	var high: int = low
	for i: int in range(low, maxi(shots.size() - TRIM, low + 1)):
		var h: int = (shots[i]["used"] as Rect2i).size.y
		if h > (shots[high]["used"] as Rect2i).size.y:
			high = i
		if h < (shots[low]["used"] as Rect2i).size.y:
			low = i
	var out: Array[int] = [high]
	out.append(low if low != high else mini(high + 8, shots.size() - 1))
	return out.slice(0, want)


## 跑动：先找出一个循环有多长，再在循环上均匀取四帧。
##
## 循环长度靠**剪影自相关**量出来：把起点那一帧和后面每一帧比姿势，
## 相似度最高的那一个偏移就是一个周期。
func _pick_cycle(shots: Array, want: int) -> Array[int]:
	var start: int = clampi(shots.size() / 3, 0, maxi(shots.size() - 2, 0))
	var best: int = 8
	var score: float = -1.0
	var limit: int = mini(40, shots.size() - start - 1)
	for step: int in range(6, maxi(limit, 7)):
		if start + step >= shots.size():
			break
		var similar := _similar(shots[start]["mask"], shots[start + step]["mask"])
		if similar > score:
			score = similar
			best = step
	var out: Array[int] = []
	for i: int in want:
		out.append(mini(start + roundi(float(best) * float(i) / float(want)), shots.size() - 1))
	return out


## 攻击：**手伸得最远那一帧当第 0 帧**。
##
## 规格里这是硬要求（第 8 节）—— 起手动作占了前两帧的话，游戏里的伤害
## 结算比画面早半拍，玩家看到的是「先掉血、后挥手」。
## 「伸得最远」量的是从脚底中点往右到剪影右沿有多远，所以抬腿不算数。
func _pick_reach(shots: Array, want: int) -> Array[int]:
	var hit: int = mini(TRIM, shots.size() - 1)
	var far: float = -1.0
	for i: int in range(hit, maxi(shots.size() - TRIM, hit + 1)):
		var used: Rect2i = shots[i]["used"]
		var reach: float = float(used.end.x) - float(shots[i]["feet_x"])
		if reach > far:
			far = reach
			hit = i
	var out: Array[int] = []
	for i: int in want:
		out.append(mini(hit + i * 3, shots.size() - 1))
	return out


## 倒地：躺稳之后随便一帧。取最后二十帧里包围盒最矮的那个 ——
## 人趴下去了，「最矮」就是「躺平了」。
func _pick_settle(shots: Array) -> Array[int]:
	var best: int = shots.size() - 1
	for i: int in range(maxi(shots.size() - 20, 0), shots.size()):
		if (shots[i]["used"] as Rect2i).size.y < (shots[best]["used"] as Rect2i).size.y:
			best = i
	var out: Array[int] = [best]
	return out


## 两个剪影有多像（交并比）。
func _similar(a: PackedByteArray, b: PackedByteArray) -> float:
	var both: int = 0
	var either: int = 0
	for i: int in a.size():
		var hit: bool = a[i] > 0 or b[i] > 0
		if a[i] > 0 and b[i] > 0:
			both += 1
		if hit:
			either += 1
	return float(both) / float(maxi(either, 1))


# ── 文件 ────────────────────────────────────────────────────────


## 给这个角色的全部成品帧打开 mipmap。
##
## **高清档必须有它。** 那张贴图在 1080p 下是 1:1，但在 720p 下是缩小采样的
## （0.67 倍）—— 没有 mipmap 的表现是**人一走动身上就闪**，
## 而静止截图完全看不出来，所以这条只能靠规则守，看不出来。
##
## 改的是 `.import` 里的一个键，改完要再导一次才生效：命令行那条路后面本来
## 就跟着一次 `--import`，插件那条路要再 `scan()` 一遍。
##
## `.import` 是 INI，所以走 [ConfigFile] —— 手拼字符串的话，
## 引擎哪天加一个键就会被抹掉，而表现是「这张图导入设置回默认了」。
func _want_mipmaps(key: String) -> void:
	var dir_path: String = "%s/%s" % [assets_dir, key]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".png.import"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		if bool(cfg.get_value("params", "mipmaps/generate", false)):
			continue
		cfg.set_value("params", "mipmaps/generate", true)
		cfg.save(path)


## 清空一个目录里的 png。**不删目录本身** —— 编辑器可能正盯着它。
func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if file_name.ends_with(".png"):
			dir.remove(file_name)


## 删掉这一段第 [param keep] 帧起的旧成品帧（连 `.import` 一起）。
## 见 [method save_frames]。
func _drop_extra(dir_path: String, anim: String, keep: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var slot: int = keep
	while slot < 64:
		for suffix: String in [".png", ".png.import"]:
			var file_name: String = "%s_%d%s" % [anim, slot, suffix]
			if dir.file_exists(file_name):
				dir.remove(file_name)
		slot += 1
