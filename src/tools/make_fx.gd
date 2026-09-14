extends SceneTree
## 命令行：把一张特效图集切成一段帧。规格见 `Docs/素材规格_特效.md`。
##
## ```powershell
## .\scripts\make_fx.ps1 -Sheet aires\fx\fire_ball_fly.png -Key fire_ball -Anim fly -Size 96
## .\scripts\make_fx.ps1 -Sheet aires\fx\kunai.png -Key kunai -Anim fly -Mode key -Size 48
## ```
##
## 输出 `assets/fx/<键>/<段>_<序号>.png`。流水线在 [PBFxForge]，这里只读参数、打结果。

const DEFAULT_OUT := "res://assets/fx"
const MODES := {"dark": PBFxForge.Mode.DARK, "key": PBFxForge.Mode.KEY}
const ANCHORS := {"center": PBFxForge.Anchor.CENTER, "bottom": PBFxForge.Anchor.BOTTOM}


func _init() -> void:
	var args := _args()
	var key: String = args.get("key", "")
	if key == "":
		printerr("要给 --key（这份特效的键，也是 assets/fx 下的目录名）")
		quit(1)
		return
	var dir: String = "%s/%s" % [args.get("out", DEFAULT_OUT), key]

	# **第二趟：只改 `.import`**（那些文件要等一次 `--import` 之后才存在）。
	if args.has("mipmaps"):
		PBPortraitForge.new().want_mipmaps(dir)
		print("mipmap 打开了，再导一次就生效。")
		quit()
		return

	var error := _check(args)
	if error != "":
		printerr(error)
		quit(1)
		return
	var forge := PBFxForge.new()
	error = forge.cut(
		args["sheet"],
		dir,
		args["anim"],
		MODES[args.get("mode", "dark")],
		ANCHORS[args.get("anchor", "center")],
		int(args.get("size", "0")),
		int(args.get("frames", "0"))
	)
	if error != "":
		printerr(error)
		quit(1)
		return
	var cells: Array = forge.measured.get("cells", [])
	print("切出 %d 格，原图画布 %s，写在 %s" % [cells.size(), forge.measured.get("canvas"), dir])
	for cell: Rect2i in cells:
		print("  格 %s" % cell)
	quit()


func _check(args: Dictionary) -> String:
	if not args.has("sheet"):
		return "要给 --sheet（图集路径）"
	if not args.has("anim"):
		return "要给 --anim（段名：fly / hit / land / loop …）"
	if not MODES.has(args.get("mode", "dark")):
		return "--mode 只认 dark（黑底发光类）或 key（洋红底实体类）"
	if not ANCHORS.has(args.get("anchor", "center")):
		return "--anchor 只认 center 或 bottom"
	return ""


## `--key value` 收成一张字典。
func _args() -> Dictionary:
	var out: Dictionary = {}
	var argv := OS.get_cmdline_user_args()
	var i: int = 0
	while i < argv.size():
		var name: String = argv[i]
		if name.begins_with("--") and i + 1 < argv.size():
			out[name.substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return out
