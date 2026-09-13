extends SceneTree
## 命令行那条路：把一张（或一目录）高清立绘降成像素图。
##
## ```powershell
## .\scripts\pixelate.ps1 -In aires\raw\<角色键>.png -Height 96
## ```
##
## **自己不做任何图像处理** —— 流水线在 [PBPixelate] 里，编辑器插件（[PBPixelatePanel]）调的是同一个类。
## 批量走这条；想比出该压到哪一档就开插件（编辑器底栏的「降采样」）。

var _in: String = ""
var _out: String = ""
var _forge := PBPixelate.new()


func _initialize() -> void:
	_read_args()
	if _in == "":
		printerr("要 --in <图片或目录>")
		quit(1)
		return
	var files := _collect(_in)
	if files.is_empty():
		printerr("找不到图片：%s" % _in)
		quit(1)
		return
	for path: String in files:
		if not _one(path):
			quit(1)
			return
	quit(0)


func _read_args() -> void:
	var argv := OS.get_cmdline_user_args()
	var i: int = 0
	while i < argv.size():
		var name: String = argv[i]
		var value: String = argv[i + 1] if i + 1 < argv.size() else ""
		match name:
			"--in":
				_in = value
				i += 1
			"--out":
				_out = value
				i += 1
			"--height":
				_forge.height = int(value)
				i += 1
			"--colors":
				_forge.colors = int(value)
				i += 1
			"--tol":
				_forge.tol = float(value)
				i += 1
			"--no-key":
				_forge.keyed = false
			_:
				pass
		i += 1


func _collect(path: String) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(path):
		return PackedStringArray([path] if FileAccess.file_exists(path) else [])
	var found := PackedStringArray()
	for name: String in DirAccess.get_files_at(path):
		if name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			found.append(path.path_join(name))
	return found


func _one(path: String) -> bool:
	var source := PBPixelate.read(path)
	if source == null:
		printerr("读不出这张图：%s" % path)
		return false
	var made := _forge.run(source)
	var small: Image = made["small"]
	var dir: String = _out if _out != "" else path.get_base_dir()
	if _out != "" and not DirAccess.dir_exists_absolute(_out):
		DirAccess.make_dir_recursive_absolute(_out)
	var dst := dir.path_join("%s_px.png" % path.get_file().get_basename())
	var err: Error = (made["big"] as Image).save_png(dst)
	if err != OK:
		printerr("写不进去（%d）：%s" % [err, dst])
		return false
	print(
		(
			"%-24s %d×%d → %d×%d（%d 倍块，%s）→ %s"
			% [
				path.get_file(),
				source.get_width(),
				source.get_height(),
				small.get_width(),
				small.get_height(),
				int(made["factor"]),
				"%d 色" % _forge.colors if _forge.colors > 0 else "不压色",
				dst.get_file()
			]
		)
	)
	return true
