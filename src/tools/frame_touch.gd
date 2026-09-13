@tool
class_name PBFrameTouch
extends RefCounted
## 一张中间帧上的**人工擦除**。
##
## `colorkey` 只抠得掉洋红，AI 视频里人脚下常有一条**地面阴影**原样留下 —— 而流水线量人全靠
## [method Image.get_used_rect]（所有非透明像素的包围盒）。一条横贯全图的黑影会让脚底中点变成画面正中、
## 画布宽涨到半个屏幕、人悬空几像素，三样都不报错。所以先擦干净，再微调锚点。
##
## **笔迹是数据，不是像素**：存「在哪擦、擦多大」，图是原图重放全部笔迹算出来的 —— 撤销、套到整段、写盘
## 共用同一个 [method apply]。**擦除是幂等的**，所以 [method open] 可以直接拿磁盘当前状态当底。
##
## **擦完立刻写盘**：擦黑影一半的价值是让 `used` / `feet_x` 重新量对，留在内存里的话 [method PBActorForge.measure]
## 读的还是带黑影的图。可逆性靠 [method open] 那一下备份（原帧拷进 `orig/`，[method restore] 从那儿拿回来）。

## 擦成什么。中间帧是**预乘**的（见 [PBActorForge] 类顶那段），所以透明像素的
## RGB 本来就该是 0 —— 只把 alpha 设 0 会留下一圈看不见的颜色，
## 而缩放会把它平均进人物边缘，表现是「边上怎么发灰」。
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)

## 原帧备份放哪个子目录。[method PBActorForge.measure] 只扫文件、不进子目录，
## 所以备份不会被当成一帧量进去。
##
## 它跟着中间帧一起活：[method PBActorForge._wipe] 递归清子目录，
## 于是重抽一次帧备份也跟着换新 —— 留着上一条视频的备份的话，
## 「还原这一帧」会还原成另一个角色的一帧，而它不报错。
const ORIG_DIR: String = "orig"

## 一笔是圆的还是方的。地面阴影横贯整图、和人是分开的，框一下就没了；
## 贴着脚边的零碎再用画笔收拾 —— 两种笔迹存同一份列表，
## 撤销和「套到整段」因此不用分两条路。
const KIND_DAB := &"dab"
const KIND_RECT := &"rect"

var _path: String = ""
var _source: Image = null
var _work: Image = null
var _marks: Array[Dictionary] = []


## 这一帧的原帧备份在哪。
static func backup_of(path: String) -> String:
	return "%s/%s/%s" % [path.get_base_dir(), ORIG_DIR, path.get_file()]


## 一笔画笔：圆心 [param at]、半径 [param radius]，单位都是**中间帧像素**。
static func dab_mark(at: Vector2i, radius: int) -> Dictionary:
	return {"kind": KIND_DAB, "at": at, "size": Vector2i(maxi(radius, 1), 0)}


## 一笔框选。
static func rect_mark(area: Rect2i) -> Dictionary:
	var box := area.abs()
	return {"kind": KIND_RECT, "at": box.position, "size": box.size}


## 把一串笔迹重放到 [param image] 上。**撤销、套到整段、写盘共用这一份。**
static func apply(image: Image, marks: Array) -> void:
	for mark: Dictionary in marks:
		_stroke(image, mark)


## 打开一帧。[param marks] 是这一帧已经攒下的笔迹（面板按段/帧记着）。
## **返回错误信息，空串 = 成功。**
##
## 底图取的是**磁盘当前状态**，不是备份 —— 擦除幂等，所以重放已经落过盘的
## 那几笔只是把透明的地方再设一遍透明，而这样「上一次会话擦掉的东西」
## 不会因为这一次打开又冒回来。
func open(path: String, marks: Array) -> String:
	var backup := backup_of(path)
	if not FileAccess.file_exists(backup):
		DirAccess.make_dir_recursive_absolute(backup.get_base_dir())
		var copy_err := DirAccess.copy_absolute(path, backup)
		if copy_err != OK:
			return "备份不了原帧（%d）：%s" % [copy_err, backup]
	var image := Image.load_from_file(path)
	if image == null:
		return "读不出这一帧：%s" % path
	_path = path
	_source = image
	_marks = []
	for mark: Dictionary in marks:
		_marks.append(mark)
	_rebuild()
	return ""


func path() -> String:
	return _path


## 擦完之后的图。**别改它** —— 下一次 [method undo] 会整张重建。
func image() -> Image:
	return _work


func marks() -> Array[Dictionary]:
	return _marks


## 涂一笔。**增量擦在 [member _work] 上**，不重建 —— 拖着涂的时候
## 每次鼠标移动都全量重放的话，一段几十笔之后就跟不上手了。
func dab(at: Vector2i, radius: int) -> void:
	_add(dab_mark(at, radius))


## 框掉一块。
func wipe(area: Rect2i) -> void:
	_add(rect_mark(area))


## 撤销最后一笔。
func undo() -> void:
	if _marks.is_empty():
		return
	_marks.resize(_marks.size() - 1)
	_rebuild()


## 撤销全部（回到打开这一帧时的样子，**不是回到抽帧时**）。
func clear() -> void:
	_marks = []
	_rebuild()


## 写回中间帧。**返回错误信息，空串 = 成功。**
func save() -> String:
	if _work == null:
		return "还没打开任何一帧"
	var err := _work.save_png(_path)
	return "" if err == OK else "存不下来（%d）：%s" % [err, _path]


## 回到**抽帧那一刻**：从备份拿回原帧、清空笔迹、写盘。
## **返回错误信息，空串 = 成功。**
func restore() -> String:
	var backup := backup_of(_path)
	if not FileAccess.file_exists(backup):
		return "没有备份可还原（这一帧还没被擦过）：%s" % backup
	var image := Image.load_from_file(backup)
	if image == null:
		return "读不出备份：%s" % backup
	_source = image
	_marks = []
	_rebuild()
	return save()


func _add(mark: Dictionary) -> void:
	if _work == null:
		return
	_marks.append(mark)
	_stroke(_work, mark)


func _rebuild() -> void:
	if _source == null:
		return
	_work = _source.duplicate() as Image
	apply(_work, _marks)


## 擦一笔。**两种笔尖都在这儿钳到图内** —— 交给调用方钳的话，
## 面板那边的框选拖出画面就会静默丢掉半笔。
static func _stroke(image: Image, mark: Dictionary) -> void:
	if image == null:
		return
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var at: Vector2i = mark.get("at", Vector2i.ZERO)
	var size: Vector2i = mark.get("size", Vector2i.ZERO)
	if StringName(mark.get("kind", KIND_DAB)) == KIND_RECT:
		var area := Rect2i(at, size).abs().intersection(bounds)
		if area.size.x > 0 and area.size.y > 0:
			image.fill_rect(area, CLEAR)
		return
	var radius: int = maxi(size.x, 1)
	var box := Rect2i(
		at - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)
	).intersection(bounds)
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var dx: int = x - at.x
			var dy: int = y - at.y
			if dx * dx + dy * dy <= radius * radius:
				image.set_pixel(x, y, CLEAR)
