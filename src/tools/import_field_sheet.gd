extends SceneTree
## 将透明三列两行整图走区域插件的切分器，并绑定到真实落地读点。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or args[2] not in ["cut", "bind"]:
		printerr("usage: -- <source.png> <skill_id> <cut|bind>")
		quit(1)
		return
	var dir := "res://assets/fx/fields/areas/%s" % args[1]
	var paths := PackedStringArray()
	for i in 6:
		paths.append("%s/frame_%d.png" % [dir, i])
	if args[2] == "cut":
		var source := Image.load_from_file(args[0])
		var forge := PBFieldSheetForge.new()
		forge.output_size = 384
		forge.center_frames = false
		var frames := forge.slice(source)
		if forge.error != "":
			printerr(forge.error)
			quit(1)
			return
		var write_error := PBFxForge.write(frames, dir, "frame")
		if write_error != "":
			printerr(write_error)
			quit(1)
			return
		quit()
		return
	var bindings := PBFieldArtBindings.new()
	var skin := PBFieldSkin.new()
	skin.fps = 6.0
	var error := bindings.import_frames(skin, paths)
	if error == "":
		error = bindings.save("areas", args[1], skin)
	if error != "":
		printerr(error)
		quit(1)
		return
	quit()
