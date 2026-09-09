extends SceneTree
## 命令行那条路：把一堆视频帧变成一套能直接进游戏的战场形象。M6-f。
##
## ```powershell
## .\scripts\make_actor.ps1 -Key asm
## ```
##
## ## 它自己不做任何图像处理
##
## **流水线整个在 [PBActorForge] 里**（M6-l 抽出去的）—— 这里只剩
## 「读命令行参数、按四段循环、把结果打出来」。编辑器插件
## （[PBActorForgePanel]）调的是同一个类。
##
## 各写一份的话，「命令行出的素材和插件出的素材尺寸差一像素」这种事
## 迟早发生，而它不报错。
##
## ## 为什么分成两趟，中间隔一次 `--import`
##
## 引擎只认导入过的贴图，刚写到磁盘上的 PNG 在同一次进程里 `load()`
## 不出来。所以 `--phase frames` 只写 PNG，`--phase link` 才装
## [SpriteFrames]。**插件那条路没有这个问题** —— 它能让编辑器当场重扫，
## 那是做成插件最实在的一处好处。
##
## ## 人只负责看结果
##
## 出完之后开预览台（`scenes/actor_lab.tscn`）—— 「这张皮装上了吗、
## 脚底对齐了吗、段名对上了吗」三样都不报错，只有那儿看得出来。

var _key: String = ""
var _mid_dir: String = "res://build/aires/mid"
var _phase: String = "frames"
var _forge := PBActorForge.new()


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


## 第一趟：量、挑、切。挑帧走的是 [method PBActorForge.select] 的自动档 ——
## **要逐帧自己挑就开插件**（编辑器底栏的「战场形象」）。
func _run_frames() -> bool:
	var takes: Dictionary = {}
	for spec: Dictionary in PBActorForge.ANIMS:
		var anim: String = String(spec["name"])
		var shots := _forge.measure("%s/%s" % [_mid_dir, anim])
		if shots.is_empty():
			printerr("这一段一帧都没读到：%s/%s" % [_mid_dir, anim])
			return false
		takes[anim] = shots
	var scales := _forge.scales(takes)

	var chosen: Dictionary = {}
	for spec: Dictionary in PBActorForge.ANIMS:
		var anim: String = String(spec["name"])
		chosen[anim] = _forge.select(takes[anim], String(spec["pick"]), int(spec["want"]))
		print("%-7s 共 %d 帧，挑 %s" % [anim, (takes[anim] as Array).size(), str(chosen[anim])])
	var canvas := _forge.fit_canvas(takes, scales, chosen)
	print(
		(
			"画布 %d×%d　贴图身高 %d　屏幕身高 %d"
			% [canvas.x, canvas.y, _forge.texture_height(), PBActorForge.TARGET_HEIGHT]
		)
	)
	if _forge.clamped:
		printerr("画布撞上上限，头被切掉了一截 —— 挑帧里有跳得太高的那一张？")

	for spec: Dictionary in PBActorForge.ANIMS:
		var anim: String = String(spec["name"])
		var images: Array[Image] = []
		for index: int in chosen[anim] as Array[int]:
			images.append(_forge.compose(takes[anim][index], float(scales[anim])))
		var err := _forge.save_frames(_key, anim, images)
		if err != "":
			printerr(err)
			return false
	print("成品帧写好了：%s/%s" % [_forge.assets_dir, _key])
	return true


## 第二趟：把已经导入的 PNG 装成 [SpriteFrames] + [PBActorSkin]。
func _run_link() -> bool:
	var err := _forge.link(_key)
	if err != "":
		printerr(err)
		return false
	print("写好了：%s/%s.tres" % [_forge.data_dir, _key])
	print("最后一步：把 data/characters/<角色>.tres 的 actor_key 填成 &\"%s\"" % _key)
	return true
