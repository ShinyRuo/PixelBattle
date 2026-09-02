extends SceneTree
## 把一堆视频帧变成一套能直接进游戏的战场形象。M6-f。
##
## ```powershell
## .\scripts\make_actor.ps1 -Key asm
## ```
##
## ## 它替掉的是「打开 Godot 编辑器手做」那一段
##
## [`Docs/AI出图_战场形象.md`](../../Docs/AI出图_战场形象.md) 第 3 / 4 节原来写的是
## 手工流程：Aseprite 抠背景、降采样、逐帧对齐画布，再回编辑器里拖 [SpriteFrames]。
## 那套流程有三个**不报错**的坑（脚底错一格、段名拼错、帧尺寸不齐），
## 而且一个角色要重复五段、全表要重复 30 次。
##
## 这里把它整条做成一条命令。**人只负责看结果**（`scenes/actor_lab.tscn`）。
##
## ## 为什么脏活分给 ffmpeg
##
## 一帧 1280×720 是 92 万像素，四段共 388 帧 —— GDScript 逐像素扫一遍要几分钟。
## 所以**抠洋红、预乘 alpha、粗缩**三件事全在 ffmpeg 里做完（见 `make_actor.ps1`），
## 这边拿到的已经是 640×360 的 RGBA。剩下的重活也一律走 [Image] 的 C++ 接口
## （[method Image.get_used_rect] / [method Image.get_region] /
## [method Image.blit_rect] / [method Image.resize]），
## 真正的逐像素循环只发生在**最后那张 48×32 的画布上**。
##
## ## 为什么中间那一趟必须是「预乘」的
##
## 抠完背景之后背景像素是全透明的，但它的 RGB 仍然是洋红。缩放会把相邻像素
## 平均起来 —— 于是人物边缘会渗出一圈粉色，**而 alpha 看起来完全正常**。
## 预乘（`rgb *= a`）让透明像素的 RGB 归零，插值因此只会稀释、不会染色；
## 缩完再除回来（[method _unpremultiply]）。

## 目标身高（像素，脚底到头顶）。**跟白模一个数**
## （[constant PBWhiteModel.ALLY_HEIGHT]）—— 真素材和白模会同屏站在一起，
## 差一截的表现是「这个人怎么比别人矮」，而两边的数字都看起来正常。
##
## 41 是 M6-g 抬上来的（27 × 1.5）。**这个数同时是「屏幕上多大」和
## 「一张图有多少像素」** —— 2D 坐标系恒为 640×360，而
## [member PBActorSkin.pixel_scale] 只能填整数，所以一张素材的像素高度
## 就是它在屏幕上的高度。想更清晰只能连着「更大」一起要。
const TARGET_HEIGHT: int = 41

## 画布上下左右各留几格。留白给跑动的起伏和出拳的伸展，
## **不能太大** —— 画布高度超过 [constant PBLayout.SPRITE_HEADROOM]
## 的话最上面那排的头会戳进顶栏。
const PAD_TOP: int = 6
const PAD_SIDE: int = 5

## 中间帧的尺寸，要和 `make_actor.ps1` 里 `scale=` 的那个数一致。
##
## **它比成品大得多是有意的。** 源视频里人物约 360 像素高，直接一步缩到
## 41 会把细节碾成噪点；先按面积平均缩到这一档，最后一档降采样在
## [method _compose] 里连着对齐一起做。
const MID := Vector2i(960, 540)

## 半透明像素归到哪一边。像素画不许有半透明边缘（规格第 8 节），
## 所以这里是**硬阈值**不是渐变。
const ALPHA_CUT: float = 0.45

## 描边：把剪影最外圈那一层压暗多少、压向哪个色。
##
## **压暗而不是往外扩一圈。** 扩出去的话人会比目标身高高 2 像素，
## 而 27 这个数是和泳道间距抢地方抢出来的（见 [PBWhiteModel] 顶部）。
const RIM_COLOR := Color(0.06, 0.06, 0.09, 1.0)
const RIM_MIX: float = 0.55

## 量人物大小用哪一档分位数。**不用最大值** —— AI 视频里总有一两帧
## 人物突然放大，取最大值会让整套素材跟着那一帧缩小。
const REF_PERCENTILE: float = 0.90

## 掐头去尾。AI 视频的头尾几帧经常在「淡入」或者姿势还没稳定。
const TRIM: int = 8

## 五段的播放参数。`want` 是要几帧，`pick` 是挑帧的策略，见 [method _select]。
const ANIMS: Array = [
	{"name": &"idle", "fps": 4.0, "loop": true, "want": 2, "pick": "breath"},
	{"name": &"run", "fps": 10.0, "loop": true, "want": 4, "pick": "cycle"},
	{"name": &"attack", "fps": 12.0, "loop": false, "want": 3, "pick": "reach"},
	{"name": &"dead", "fps": 4.0, "loop": false, "want": 1, "pick": "settle"},
]

## 剪影比对用的小掩码尺寸。按包围盒归一化之后再缩到这么大，
## 所以它**不受人物平移与缩放影响** —— 比的是姿势，不是位置。
const MASK := Vector2i(16, 24)

var _key: String = ""
var _mid_dir: String = "res://build/aires/mid"
var _assets: String = "res://assets/actors"
var _data: String = "res://data/actors"
var _phase: String = "frames"
var _canvas := Vector2i.ZERO
var _measured_height: float = float(TARGET_HEIGHT)


func _initialize() -> void:
	_read_args()
	if _key == "":
		printerr("要 --key <actor_key>")
		quit(1)
		return
	var ok: bool = _run_frames() if _phase == "frames" else _run_link()
	quit(0 if ok else 1)


func _read_args() -> void:
	var argv := OS.get_cmdline_user_args()
	var i: int = 0
	while i < argv.size():
		var name: String = argv[i]
		var value: String = argv[i + 1] if i + 1 < argv.size() else ""
		match name:
			"--key":
				_key = value
				i += 1
			"--mid":
				_mid_dir = value
				i += 1
			"--phase":
				_phase = value
				i += 1
			_:
				pass
		i += 1


# ── 第一趟：量、挑、切 ──────────────────────────────────────────


## 把中间帧变成 `assets/actors/<key>/` 下的成品帧。
func _run_frames() -> bool:
	var takes: Dictionary = {}
	for spec: Dictionary in ANIMS:
		var anim: String = String(spec["name"])
		var shots := _measure("%s/%s" % [_mid_dir, anim])
		if shots.is_empty():
			printerr("这一段一帧都没读到：%s/%s" % [_mid_dir, anim])
			return false
		takes[anim] = shots
	var scales := _scales(takes)

	# **先挑帧再定画布。** 按全部 97 帧算的话，AI 视频里任何一帧的杂点
	# 都会把画布撑宽，而那一帧根本不会进游戏。
	var chosen: Dictionary = {}
	for spec: Dictionary in ANIMS:
		var anim: String = String(spec["name"])
		var shots: Array = takes[anim]
		chosen[anim] = _select(shots, String(spec["pick"]), int(spec["want"]))
		print("%-7s 共 %d 帧，挑 %s" % [anim, shots.size(), str(chosen[anim])])
	_canvas = _fit_canvas(takes, scales, chosen)
	print("画布 %d×%d　目标身高 %d" % [_canvas.x, _canvas.y, TARGET_HEIGHT])

	var out_dir: String = "%s/%s" % [_assets, _key]
	DirAccess.make_dir_recursive_absolute(out_dir)
	for spec: Dictionary in ANIMS:
		var anim: String = String(spec["name"])
		var shots: Array = takes[anim]
		var picks: Array[int] = chosen[anim]
		for slot: int in picks.size():
			var image := _compose(shots[picks[slot]], float(scales[anim]))
			var path: String = "%s/%s_%d.png" % [out_dir, anim, slot]
			var err := image.save_png(path)
			if err != OK:
				printerr("存不下来（%d）：%s" % [err, path])
				return false
	print("成品帧写好了：%s" % out_dir)
	return true


## 量一整段的每一帧：人物包围盒、脚底中点、归一化剪影。
##
## **全部走 [method Image.get_used_rect]**（C++）—— 逐像素找边界的话，
## 97 帧 × 23 万像素在 GDScript 里要跑一分多钟。
func _measure(dir_path: String) -> Array:
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
		# **只留量出来的那几个数，不留图。** 一段 97 帧 × 960×540 RGBA
		# 是 200 MB，四段一起攥在手里就爆了 —— 而真正要用的只有挑中的那几帧，
		# [method _compose] 那时再按路径读回来。
		out.append(
			{
				"path": path,
				"used": used,
				"feet_x": _feet_x(image, used),
				"mask": _mask(image, used),
			}
		)
	return out


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


## 每一段各自的缩放比。
##
## **逐段归一化，不是全套用同一个比。** AI 视频每一条里人物大小都不完全一样，
## 用同一个比的话玩家会看到「他一跑起来就长高两像素」——
## 而那比「跑动和待机的身高差一点」难看得多。
##
## `dead` 借用 `idle` 的比：人躺着，包围盒高度不是身高。
func _scales(takes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var idle_scale: float = 1.0
	for spec: Dictionary in ANIMS:
		var anim: String = String(spec["name"])
		if anim == "dead":
			continue
		var reference := _reference_height(takes[anim] as Array)
		var scale: float = float(TARGET_HEIGHT) / maxf(reference, 1.0)
		out[anim] = scale
		if anim == "idle":
			idle_scale = scale
			_measured_height = reference * scale
	out["dead"] = idle_scale
	return out


## 这一段里人物「站直了」有多高。取 [constant REF_PERCENTILE] 分位数。
func _reference_height(shots: Array) -> float:
	var heights: Array[float] = []
	for i: int in range(mini(TRIM, shots.size()), maxi(shots.size() - TRIM, 1)):
		heights.append(float((shots[i]["used"] as Rect2i).size.y))
	if heights.is_empty():
		return 1.0
	heights.sort()
	var at: int = clampi(roundi(float(heights.size() - 1) * REF_PERCENTILE), 0, heights.size() - 1)
	return heights[at]


## 画布定多大：装得下**挑中的那几帧**，再各留一点边。
##
## 算出来而不是写死 36×36：出拳那一帧比站着宽得多，写死的话手会被裁掉，
## **而裁掉的那一截只是不见了，不报错**。
func _fit_canvas(takes: Dictionary, scales: Dictionary, chosen: Dictionary) -> Vector2i:
	var half: float = 0.0
	var tall: float = 0.0
	for spec: Dictionary in ANIMS:
		var anim: String = String(spec["name"])
		var scale: float = float(scales[anim])
		for index: int in chosen[anim] as Array[int]:
			var shot: Dictionary = takes[anim][index]
			var used: Rect2i = shot["used"]
			var feet: float = shot["feet_x"]
			half = maxf(half, (feet - float(used.position.x)) * scale)
			half = maxf(half, (float(used.end.x) - feet) * scale)
			tall = maxf(tall, float(used.size.y) * scale)
	var width: int = (ceili(half) + PAD_SIDE) * 2
	var height: int = ceili(tall) + PAD_TOP
	# 高度撞上头顶那一截就压回去 —— 超了的话最上面那排的头会戳进 A 顶栏，
	# 而 `tests/test_layout.gd` 钉的是 [PBLayout] 的常量，钉不到素材。
	if height > int(PBLayout.SPRITE_HEADROOM):
		print("画布高度 %d 超过头顶余量 %d，压回去" % [height, int(PBLayout.SPRITE_HEADROOM)])
		height = int(PBLayout.SPRITE_HEADROOM)
	return Vector2i(width + (width % 2), height + (height % 2))


## 把一帧摆进画布：脚底中点落在**画布底边中点**上，然后缩到位。
##
## ## 对齐做两遍，最后一遍在成品分辨率上
##
## 先在中间分辨率上粗摆一次，只为了别把人裁掉；**真正的对齐在缩完之后**
## （[method _seat]）。只在缩之前对齐的话，人会浮在地面上方一像素 ——
## 最底那排鞋底只有薄薄一条，面积平均之后 alpha 掉到
## [constant ALPHA_CUT] 以下，整排被切掉了，**而所有数字看起来都完全正确**
## （实测：预览台上画布框贴着地面线，人却悬空）。
func _compose(shot: Dictionary, scale: float) -> Image:
	var factor: float = 1.0 / maxf(scale, 0.0001)
	var work := Vector2i(
		maxi(roundi(float(_canvas.x) * factor), 1), maxi(roundi(float(_canvas.y) * factor), 1)
	)
	var canvas := Image.create_empty(work.x, work.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	var used: Rect2i = shot["used"]
	var at := Vector2i(
		roundi(float(work.x) * 0.5 - float(shot["feet_x"])), work.y - used.end.y
	)
	var source := Image.load_from_file(shot["path"])
	canvas.blit_rect(source, Rect2i(Vector2i.ZERO, MID), at)
	# 缩放仍在**预乘**空间里做，见类顶部那段。
	canvas.resize(_canvas.x, _canvas.y, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(canvas)
	canvas = _seat(canvas)
	_rim(canvas)
	return canvas


## 把已经缩到成品尺寸的这一帧**精确坐到画布底边中点上**。
##
## 纵向按最下面那排实心像素，横向按脚底那一截的中点（不是整个包围盒的中点，
## 理由同 [method _feet_x]：出拳那几帧手臂伸出去老远，按包围盒对齐的话
## 人会在挥拳的瞬间横向弹一下）。
func _seat(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return image
	var feet: float = _feet_x(image, used)
	var move := Vector2i(
		roundi(float(_canvas.x) * 0.5 - feet), _canvas.y - used.end.y
	)
	if move == Vector2i.ZERO:
		return image
	var seated := Image.create_empty(_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8)
	seated.fill(Color(0.0, 0.0, 0.0, 0.0))
	seated.blit_rect(image, Rect2i(Vector2i.ZERO, _canvas), move)
	return seated


## 除回 alpha，并且把半透明像素归到两边去（像素画不许有半透明边缘）。
func _unpremultiply(image: Image) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < ALPHA_CUT:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var inv: float = 1.0 / pixel.a
			image.set_pixel(
				x,
				y,
				Color(
					minf(pixel.r * inv, 1.0), minf(pixel.g * inv, 1.0), minf(pixel.b * inv, 1.0), 1.0
				)
			)


## 把剪影最外圈压暗一档。
##
## **这不是装饰。** 同一列会叠着七八个人，没有描边的话几个同系角色在屏幕上
## 是一根实心色条 —— 数不出几个人，也点不中中间那个（M6-c 实测）。
## 素材本身画了描边，但从 360 像素缩到 27 之后那一圈基本没了。
##
## **压暗现有像素，不往外扩**：扩一圈等于把身高抬到 29，
## 而 27 是和泳道间距抢出来的。
func _rim(image: Image) -> void:
	var edge: Array[Vector2i] = []
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a <= 0.0:
				continue
			if _on_edge(image, x, y):
				edge.append(Vector2i(x, y))
	for at: Vector2i in edge:
		image.set_pixel(at.x, at.y, image.get_pixel(at.x, at.y).lerp(RIM_COLOR, RIM_MIX))


## 这个实心像素是不是贴着外面。**先收集再写**（和 [method PBWhiteModel._outline]
## 同一条）：边判边写的话刚压暗的那一圈会被当成背景，一趟扫下来压出三四层。
func _on_edge(image: Image, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at := Vector2i(x + step.x, y + step.y)
		if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
			return true
		if image.get_pixel(at.x, at.y).a <= 0.0:
			return true
	return false


# ── 挑帧：靠量，不靠数格子 ──────────────────────────────────────


func _select(shots: Array, how: String, want: int) -> Array[int]:
	match how:
		"cycle":
			return _pick_cycle(shots, want)
		"reach":
			return _pick_reach(shots, want)
		"settle":
			return _pick_settle(shots)
		_:
			return _pick_breath(shots, want)


## 待机：呼吸的最高点和最低点。那两帧之间差的就是一两像素的起伏，
## 而那正是一段 idle 的全部信息量。
func _pick_breath(shots: Array, want: int) -> Array[int]:
	var low: int = TRIM
	var high: int = TRIM
	for i: int in range(TRIM, maxi(shots.size() - TRIM, TRIM + 1)):
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
## 相似度最高的那一个偏移就是一个周期。数格子数出来的循环长度
## 十次有八次差一帧，而差一帧的表现是跑起来一瘸一拐。
func _pick_cycle(shots: Array, want: int) -> Array[int]:
	var start: int = clampi(shots.size() / 3, TRIM, maxi(shots.size() - TRIM - 1, TRIM))
	var best: int = 8
	var score: float = -1.0
	var limit: int = mini(40, shots.size() - start - 1)
	for step: int in range(6, maxi(limit, 7)):
		var similar := _similar(shots[start]["mask"], shots[start + step]["mask"])
		if similar > score:
			score = similar
			best = step
	var out: Array[int] = []
	for i: int in want:
		out.append(mini(start + roundi(float(best) * float(i) / float(want)), shots.size() - 1))
	print("　　跑动循环 %d 帧（相似度 %.2f）" % [best, score])
	return out


## 攻击：**手伸得最远那一帧当第 0 帧**。
##
## 规格里这是硬要求（第 8 节）—— 起手动作占了前两帧的话，游戏里的伤害
## 结算比画面早半拍，玩家看到的是「先掉血、后挥手」。
## 「伸得最远」量的是从脚底中点往右到剪影右沿有多远，所以抬腿不算数。
func _pick_reach(shots: Array, want: int) -> Array[int]:
	var hit: int = TRIM
	var far: float = -1.0
	for i: int in range(TRIM, maxi(shots.size() - TRIM, TRIM + 1)):
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


# ── 第二趟：连线 ────────────────────────────────────────────────


## 把已经导入的 PNG 装成 [SpriteFrames] + [PBActorSkin]，写进 `data/actors/`。
##
## **必须和第一趟分开跑**，中间隔一次 `--import`：引擎只认导入过的贴图，
## 刚写到磁盘上的 PNG 在同一次进程里 `load()` 不出来。
func _run_link() -> bool:
	var frames := SpriteFrames.new()
	var total: int = 0
	for spec: Dictionary in ANIMS:
		var anim: StringName = spec["name"]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(spec["fps"]))
		frames.set_animation_loop(anim, bool(spec["loop"]))
		var slot: int = 0
		while true:
			var path: String = "%s/%s/%s_%d.png" % [_assets, _key, anim, slot]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(anim, load(path) as Texture2D)
			slot += 1
			total += 1
		if slot == 0:
			printerr("这一段一帧都没有：%s（第一趟跑了吗？）" % anim)
			return false
		print("%-7s %d 帧　%.0f fps　%s" % [anim, slot, spec["fps"], "循环" if spec["loop"] else "单次"])
	frames.remove_animation(&"default")

	# **图集放子目录里，不和形象表并排。**
	# [method PBActorLibrary.load_from] 把 `data/actors/` 下的每个 `.tres`
	# 都当成一张 [PBActorSkin]，装不进来就 `push_error` —— 那条报错是对的
	# （放错类型就该说），所以图集不能放在它眼皮底下。它不递归子目录。
	DirAccess.make_dir_recursive_absolute("%s/frames" % _data)
	var frames_path: String = "%s/frames/%s.tres" % [_data, _key]
	var err := ResourceSaver.save(frames, frames_path)
	if err != OK:
		printerr("图集存不下来（%d）：%s" % [err, frames_path])
		return false

	var skin := PBActorSkin.new()
	skin.key = StringName(_key)
	skin.frames = frames
	skin.anim_idle = &"idle"
	skin.anim_run = &"run"
	skin.anim_attack = &"attack"
	# **施法段没有素材就留一个查不到的名字**，[method PBActorSkin.anim_for]
	# 会自己退回攻击段。指到 `idle` 的话施法半秒会变成站着不动，更看不出在放招。
	skin.anim_cast = &"cast"
	skin.anim_dead = &"dead"
	skin.source_faces = PBActorSkin.Facing.RIGHT
	skin.pixel_scale = 1.0
	# 脚底已经对到画布底边中点上了，所以留默认锚（见 [member PBActorSkin.foot_offset]）。
	skin.foot_offset = Vector2.ZERO
	# **真素材不染色**：它自己有颜色，再乘一层属性色会把美术定的色拉偏。
	skin.tint_by_element = false
	skin.height_px = float(TARGET_HEIGHT)
	var skin_path: String = "%s/%s.tres" % [_data, _key]
	err = ResourceSaver.save(skin, skin_path)
	if err != OK:
		printerr("形象表存不下来（%d）：%s" % [err, skin_path])
		return false
	print("写好了：%s（%d 帧）" % [skin_path, total])
	print("最后一步：把 data/characters/<角色>.tres 的 actor_key 填成 &\"%s\"" % _key)
	return true
