extends SceneTree
## 将透明 3x2 光环整图按固定网格切为六帧，保留原图和全部透明边距。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- <source.png> <aura_id>")
		quit(1)
		return
	var source := Image.load_from_file(args[0])
	if (
		source == null
		or source.is_empty()
		or source.get_width() % 3 != 0
		or source.get_height() % 2 != 0
	):
		printerr("invalid 3x2 sheet")
		quit(1)
		return
	var cell := Vector2i(source.get_width() / 3, source.get_height() / 2)
	var dir := "res://assets/fx/buffs/%s" % args[1]
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 6:
		var frame := source.get_region(Rect2i(Vector2i(i % 3, i / 3) * cell, cell))
		var path := "%s/front_%d.png" % [dir, i]
		var error := frame.save_png(path)
		if error != OK:
			printerr("save failed: ", path)
			quit(1)
			return
	quit()
