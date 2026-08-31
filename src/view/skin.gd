class_name PBSkin
extends RefCounted
## 全项目界面共用的一套配色与控件皮肤。M3.5-f。
##
## ## 为什么值得单独一个类
##
## 白模阶段每块面板都自己 `ColorRect.new()` 摆出来，于是**同一种东西在六个
## 文件里有六个色号**：任务卡的底是 `0.06,0.07,0.10`、指令卡的底是
## `0.07,0.08,0.11`、格子的边是 `0.20,0.21,0.26`…… 差别小到看不出是有意的，
## 又大到让整屏显得脏。按钮更明显 —— 全是引擎默认皮肤，
## 在一屏深色面板里白得刺眼。
##
## ## 它不是美术资源
##
## M5 之前不动 `assets/`（§14）。这一层只收拢**颜色、圆角、边框、
## 按钮的四种状态**，全部是代码里的 [StyleBoxFlat]。真美术进来时
## 改这一个文件，其余面板一行不动 —— 那正是把它单独拎出来的收益。
##
## ## 三档语气
##
## 按钮按「这一下有多重」分三档，而不是按「在哪块面板上」分：
## 主行动（开打、确认三选一）最亮，普通指令居中，只读/次要的压暗。
## 同一屏上超过一个「最亮」的按钮，玩家就不知道该先点哪个了。

## 按钮的语气。见类顶部那段。
enum Tone {
	PLAIN,  ## 普通指令
	PRIMARY,  ## 主行动：一屏上最好只有一个
	QUIET,  ## 次要 / 只读 / 大块的可点区域
}

## 面板底色。三档深浅：外框、内容块、被强调的格子。
const PANEL := Color(0.086, 0.098, 0.133, 0.97)

## 抽屉用的**不透明**底。常驻面板留一点透明是好的（底下是纯背景色，
## 看不出来，却让整屏不那么死板）；抽屉不行 —— 它压在羁绊带和预告行上，
## 3% 的透明度足够让底下那两行文字透出一层鬼影。
const PANEL_SOLID := Color(0.086, 0.098, 0.133, 1.0)
const PANEL_SOFT := Color(0.129, 0.145, 0.192, 1.0)
const PANEL_DEEP := Color(0.055, 0.063, 0.086, 1.0)

const EDGE := Color(0.243, 0.271, 0.353, 1.0)
const EDGE_SOFT := Color(0.169, 0.188, 0.243, 1.0)

const TEXT := Color(0.855, 0.878, 0.925, 1.0)
const DIM := Color(0.545, 0.584, 0.667, 1.0)
const TITLE := Color(0.976, 0.847, 0.451, 1.0)

## 好 / 提醒 / 坏。**买得起用普通色，买不起才用 [constant BAD]** ——
## 把「能做的事」染成绿色会让一屏全是绿的，那时颜色就不带信息了。
const GOOD := Color(0.443, 0.816, 0.549, 1.0)
const WARN := Color(0.945, 0.722, 0.322, 1.0)
const BAD := Color(0.898, 0.420, 0.420, 1.0)
const ACCENT := Color(0.376, 0.616, 0.949, 1.0)

const RADIUS: int = 3

## 面板标题 9px、正文 8px。**两档就够** —— 白模阶段字号一多，
## 屏幕上就会出现「这行比那行重要」的假暗示。
const FONT_TITLE: int = 9
const FONT_BODY: int = 8


## 一个填色 + 描边 + 圆角的盒子。所有皮肤都从这里出。
static func box(
	fill: Color, border: Color, radius: int = RADIUS, width: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(2.0)
	return style


## 往 [param parent] 上摆一块面板底，返回它。
##
## 用 [Panel] 而不是 [ColorRect]：前者认 [StyleBoxFlat]，也就是圆角和描边。
## 一圈 1px 的描边是这次改版里最省事的一处提升 —— 深色底块之间没有边界时，
## 相邻两块面板会糊成一整片。
static func panel(parent: Control, rect: Rect2, fill: Color = PANEL) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", box(fill, EDGE))
	parent.add_child(node)
	return node


## 一条不吃鼠标的文字。**面板上的字一律走这里** ——
## 各处自己 `Label.new()` 时，`mouse_filter` 十有八九会忘，
## 于是那行字会挡住底下的按钮，而表现只是「这里点不动」。
static func label(
	parent: Control,
	at: Vector2,
	width: float,
	font_size: int = FONT_BODY,
	color: Color = TEXT
) -> Label:
	var node := Label.new()
	node.position = at
	node.size = Vector2(width, float(font_size) + 5.0)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


## 一段可以带 BBCode 的正文（信息栏、装备栏的说明都用它）。
static func rich(parent: Control, rect: Rect2, font_size: int = FONT_BODY) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.scroll_active = false
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("normal_font_size", font_size)
	node.add_theme_font_size_override("bold_font_size", font_size)
	node.add_theme_color_override("default_color", TEXT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


## 给一个按钮换上皮肤。**四种状态一起给** ——
## 只覆盖 `normal` 的话，鼠标一停上去就跳回引擎默认的白底，
## 那一下比不换皮更难看。
static func style_button(node: Button, tone: Tone = Tone.PLAIN, font_size: int = FONT_BODY) -> void:
	var fill := PANEL_SOFT
	var edge := EDGE
	var ink := TEXT
	match tone:
		Tone.PRIMARY:
			fill = Color(0.204, 0.318, 0.482, 1.0)
			edge = ACCENT
			ink = Color(0.937, 0.965, 1.0, 1.0)
		Tone.QUIET:
			fill = PANEL_DEEP
			edge = EDGE_SOFT
			ink = DIM
		_:
			pass
	node.add_theme_stylebox_override("normal", box(fill, edge))
	node.add_theme_stylebox_override("hover", box(fill.lightened(0.12), TITLE))
	node.add_theme_stylebox_override("pressed", box(fill.darkened(0.18), TITLE))
	node.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	# 禁用态压到几乎和面板底同色：「现在买不起」应当一眼看出是灰的，
	# 而不是让人以为按钮坏了去反复点。
	node.add_theme_stylebox_override("disabled", box(PANEL_DEEP, EDGE_SOFT))
	node.add_theme_color_override("font_color", ink)
	node.add_theme_color_override("font_hover_color", TITLE)
	node.add_theme_color_override("font_pressed_color", TITLE)
	node.add_theme_color_override("font_disabled_color", Color(0.361, 0.388, 0.451, 1.0))
	node.add_theme_font_size_override("font_size", font_size)
	node.clip_text = true


## 把一段文字染色的 BBCode。查一次色号写一次 `[color=#…]` 太容易写错。
static func tint(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]
