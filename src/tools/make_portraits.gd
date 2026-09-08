extends SceneTree
## 命令行：把一张头像表切成一人一张的卡面头像。M9-g。
##
## ```powershell
## .\scripts\make_portraits.ps1
## .\scripts\make_portraits.ps1 -Sheet aires\headshots.png -Order aires\headshots.txt
## ```
##
## ## 顺序表为什么是一个外部文件
##
## 切出来的第 k 格是谁，只有画图的人知道 —— 那是一份**排版**，不是一条规则。
## 而且 §14 铁律 5 是「代码里不出现角色名」，[PBCharacterTable] 的测试
## 会扫整个 `src/`（注释也算，实测拦下过）。所以那份名单只能住在
## `aires/` 里的一个文本文件里：一行一个键，空行和 `#` 开头的行跳过。
##
## 重新出一版表、换一个排法，改的是那个文本文件，这里一行不动。

const DEFAULT_SHEET := "res://aires/headshots.png"
const DEFAULT_ORDER := "res://aires/headshots.txt"
const DEFAULT_OUT := "res://assets/portraits"


func _init() -> void:
	var args := _args()
	var sheet: String = args.get("sheet", DEFAULT_SHEET)
	var order: String = args.get("order", DEFAULT_ORDER)
	var out: String = args.get("out", DEFAULT_OUT)

	# **第二趟：只改 `.import`。** 那些文件是引擎导入时才生成的，
	# 切完那一刻还不存在 —— 所以开 mipmap 只能等一次 `--import` 之后。
	if args.has("mipmaps"):
		PBPortraitForge.new().want_mipmaps(out)
		print("mipmap 打开了，再导一次就生效。")
		quit()
		return

	var keys := _read_order(order)
	if keys.is_empty():
		printerr("读不到顺序表，或者它是空的：%s" % order)
		quit(1)
		return

	var forge := PBPortraitForge.new()
	var err := forge.cut(sheet, keys, out)
	if err != "":
		printerr(err)
		quit(1)
		return

	var grid: Dictionary = forge.measured
	print("网格：%d 列 × %d 行" % [grid["cols"].size(), grid["rows"].size()])
	for row: Vector2i in grid["rows"]:
		print("  行 y=%d 高=%d" % [row.x, row.y])
	print("切好 %d 张，写在 %s，成品 %s" % [keys.size(), out, PBPortraitForge.texture_size()])
	# **没铺满的要报出来**，理由见 [member PBPortraitForge.short]。
	if not forge.short.is_empty():
		printerr(
			"这几张的格子不够高，底下留了空：%s —— 重出这张表时把那一行画高一点。"
			% ", ".join(forge.short)
		)
	print("下一步：跑一次 --import，让引擎把这些 PNG 导进来。")
	quit()


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


## 一行一个键。空行和 `#` 开头的行跳过 —— 那份名单要能写注释
## （「第 3 行是晓组织」这种），否则改排版时没人认得出哪一行对哪一格。
func _read_order(path: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(path)
	var out := PackedStringArray()
	for line: String in text.split("\n"):
		var key := line.strip_edges()
		if key == "" or key.begins_with("#"):
			continue
		out.append(key)
	return out
