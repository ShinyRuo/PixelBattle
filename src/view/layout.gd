class_name PBLayout
extends RefCounted
## 界面十个区块的坐标与战场坐标换算。**全项目唯一一份**，这个文件本身就是那张排版图。
##
## 坐标散在各自文件里的话，「屏幕排得下吗」没有地方问，挪一块要去各处抄邻居的坐标，抄漏就重叠 ——
## 而重叠单元测试抓不到，只能截图。
##
## ```
## ┌─────────────────────────────────────────┐
## │ ┌──┐ ┌─── A 本局信息 ────────────────┐ │
## │ │C │ ├───────────────────────────────┤ │
## │ │尾│ │                               │ │
## │ └──┘ │                               │ │
## │ ┌──┐ │        B 战场                 │ │
## │ │D │ │                               │ │
## │ │基│ │      （模态弹层摊在这上面）    │ │
## │ └──┘ │                               │ │
## │ ┌──┐ │                               │ │
## │ │E │ │                               │ │
## │ │任│ │                               │ │
## │ │+4│ │                               │ │
## │ └──┘ └───────────────────────────────┘ │
## │ ┌────┐┌───┐┌────┐┌┐┌──────┐            │
## │ │ F  ││ G ││ H  ││I││  J   │            │
## │ │仓库││忍具││信息││装││操作 │            │
## │ └────┘└───┘└────┘└┘└──────┘            │
## └─────────────────────────────────────────┘
## ```
##
## **640×360 是硬约束**：字号 8–9 下一个汉字约 8 像素宽，长句一律进 tooltip，面板上只留数字和图标。
## **超出去不报错**（溢出的那一截只是画在屏幕外），所以 `test_layout.gd` 把 [constant SCREEN] 钉成了一条断言。

## 视口尺寸。**这里的每一个矩形都必须落在它里面**，见类顶部最后一段。
const SCREEN := Vector2(640.0, 360.0)

# ── A 顶栏：本局信息 ────────────────────────────────────────────

## 出战人口、金币、波次。**横跨整个屏幕宽度**：这一行是全屏最长的一句话，左上角本来就空着。
const A_INFO := Rect2(8.0, 3.0, 560.0, 12.0)

## 下一波预告，和本局信息贴在一起（不隔着战场来回扫）。
const A_PREVIEW := Rect2(8.0, 15.0, 560.0, 12.0)

## 调试入口独占顶栏右侧，不遮挡战场点选。
const A_DEBUG := Rect2(575.0, 2.0, 57.0, 30.0)

## 顶栏两行的字号。
const A_FONT_SIZE: int = 9

# ── B 战场 ──────────────────────────────────────────────────────
#
# **这四个数是战场坐标系的定义**，[PBEnemyPool] 的 `to_screen` / `to_field`
# 全靠它们。改这里等于改「一个战场单位等于多少像素」，
# 而射程圈、大招半径、落点预示都是按那个比例画的。

## B 框的上沿。上下两头都不能越界：玩家会把忍者拖到道的边缘，伸进面板底下的那一截会让人「消失」。
const FIELD_TOP: float = 34.0

## 战线的左右端点：右边出生，左边是基地。
## 「前中后」映射到屏幕右中左，与敌人推进方向一致（§02）。
const FIELD_LEFT: float = 128.0
const FIELD_RIGHT: float = 628.0

## B 框的下沿。**真正的判定下沿是算出来的**（[method lane_bottom]，由 [member PBSimConfig.field_height]
## 与 [constant Y_SCALE] 决定），地面带只占框的上面一截 —— `test_layout.gd` 钉着这条不等式。
## 底栏从 260 起，加上 [constant B_LANE_INSET] 的底板只剩 2 像素，**这个框已经顶到头了**。
const FIELD_BOTTOM: float = 254.0

## 地面的纵向压缩比。**「45 度俯视」的唯一实现**。
##
## **几何量，不是手感参数**：水平地面在俯角 θ 下纵深缩成 `sin θ`，这里是 `sin 45°`。想改视角就改角度。
## 它顺带腾出了小人的身高（人占地面一个点，身体往上长），见 [constant SPRITE_HEADROOM]。
##
## 代价：sim 里的圆在屏幕上是椭圆。画成正圆反而是谎话（玩家会去躲一个不存在的纵向判定），
## 所以**全项目画地面上的圆只准走 [method ground_disc]**。
const Y_SCALE: float = 0.70710678

## 地面带从 [constant FIELD_TOP] 往下让多少（精灵头顶的排版余量）。只管**排版**，和
## [member PBSimConfig.field_height] 抢同一块地方。
##
## 脚在地面点上、身体往上长，不留这一截的话最上面那条泳道的人头会戳进顶栏。
## **64 是这块屏幕的天花板**：地面带约 156 像素，而 B 框只有 220 —— 60 像素高的人加 2 像素留白正好。
## 再高只有两条路，都改配平：压 `field_height`，或撑大 B（上下各只剩几像素）。`test_layout.gd` 钉着这条和。
##
## **一帧最高能画多高是另一个数**（[constant PBActorForge.CANVAS_CEILING]）：站姿不越界，抬手那几帧允许探出去一点。
const SPRITE_HEADROOM: float = 64.0

## 地面带的上沿 —— **战场坐标 y=0 落在屏幕的哪一行**。和 [constant FIELD_TOP]（框的上沿）差一个头顶。
const GROUND_TOP: float = FIELD_TOP + SPRITE_HEADROOM

const B_FIELD := Rect2(FIELD_LEFT, FIELD_TOP, FIELD_RIGHT - FIELD_LEFT, FIELD_BOTTOM - FIELD_TOP)

## 战场底板比判定区大一圈，好让玩家看出「这条道到哪儿为止」。
## 横向比纵向多留一点 —— 敌人是从右边走进来的，右端要看得出还有路。
const B_LANE_INSET := Vector2(6.0, 4.0)

# ── C / D / E 左侧一列 ──────────────────────────────────────────
#
# 配额（玩家定的）：任务栏装的是几个数和四个格子，压紧了照样读得出；C/D 装的是图，图太小就只剩色块。

## 尾兽形象。点它 → [constant H_INFO] 显示尾兽信息、[constant J_COMMAND] 显示尾兽操作。
## 是一张图（[PBIconArt]）：九只各有颜色和尾数，空着时是一张带问号的剪影。
const C_BEAST := Rect2(12.0, 30.0, 100.0, 70.0)

## 大本营形象。**比尾兽那张大一圈**（玩家定的，它是这一局的命）。血条横在图的顶端。
const D_BASE := Rect2(12.0, 106.0, 100.0, 84.0)

## 任务栏：当前任务 + 4 个忍者槽（一横排，格子 21 见方，[constant PBQuestCard.SLOT_SIZE]）。
## 长句进 [PBTooltip]。下沿正好是 [constant FIELD_BOTTOM]：左边这一列和战场收在同一条线上。
const E_QUEST := Rect2(12.0, 196.0, 100.0, 58.0)

# ── F ~ J 底栏 ──────────────────────────────────────────────────
#
# 五块一横排，左右各留 6、块间也留 6。J 那 3×3 是这一排唯一放不下就出界的东西（格子宽度乘以三）。

## 忍者仓库。滚动，30 格 —— 角色表正好 30 个，而重复的卡并成星级，
## 所以这个上限现在是自动满足的（角色表扩到 31 个时它才变成一条真规则）。
const F_ROSTER := Rect2(6.0, 260.0, 130.0, 94.0)

## 忍具仓库。**滚动**，上限只是显示容量。窄一点无妨（装的是格子，能滚）；宽度让给装整句文字的 H。
const G_PARTS := Rect2(142.0, 260.0, 74.0, 94.0)

## 信息栏。**两种模式**：没选中人时显示队伍账，选中了人显示他的属性（和 [constant J_COMMAND] 同一条规矩）。
## 宽度按整句算：窄面板对文字的惩罚是换行到看不见，而那不报错。
const H_INFO := Rect2(222.0, 260.0, 168.0, 94.0)

## 忍者装备栏，3 格。只在信息栏显示某个忍者时出现。
const I_EQUIP := Rect2(396.0, 260.0, 44.0, 94.0)

## 操作栏。选中谁就显示谁能做的事。3×3 的格子 58×23，写不下整句，所以说明卡（tooltip）是这块面板的前提。
const J_COMMAND := Rect2(446.0, 260.0, 188.0, 94.0)

# ── 模态弹层 ────────────────────────────────────────────────────

## 模态弹层的宽度（[PBModal]）。**比 B 宽**（600 vs 500）——
## 它不是战场上的一块面板，是盖在整个画面上的一层，
## 对齐 B 只会让三选一那三张卡各窄掉 33 像素。
const MODAL_WIDTH: float = 600.0


## 一层高 [param height] 的模态弹层摆在哪。**横向居中于屏幕，纵向居中于 B。**
##
## 纵向不居中于屏幕是因为底栏那五块（F~J）在 260 以下 ——
## 居中会让弹层压住它们的上沿，而弹层关掉的那一瞬间玩家的视线
## 正要回到那儿。压在 B 上则不影响：准备阶段战场归玩家看，而
## **这两块弹层都是「不选就不能继续」**，此刻没有别的事可做。
static func modal_rect(height: float) -> Rect2:
	# **纵向钳在屏幕里。** 一层比 B 还高的弹层照上面那个式子算会垂到界外，
	# 而垂出去的正是底下那截 —— 提示行和确认按钮都在那儿。
	var top: float = FIELD_TOP + maxf((B_FIELD.size.y - height) * 0.5, 0.0)
	return Rect2(
		(SCREEN.x - MODAL_WIDTH) * 0.5,
		clampf(top, 0.0, maxf(SCREEN.y - height, 0.0)),
		MODAL_WIDTH,
		height
	)


# ── 战场坐标换算 ────────────────────────────────────────────────
#
# 算的是排版不是敌人：己方、子弹、落点预示、飘字、鼠标点选全走这里。


## 一个战场单位在屏幕上换算成多少像素。
##
## **两轴共用这一个比例。** 各算各的话，sim 里的一个圆在屏幕上会是椭圆 ——
## 而 §02 的射程圈、大招落点预示都要求玩家看到的形状就是判定的形状。
static func px_per_unit(field: Vector2) -> float:
	return (FIELD_RIGHT - FIELD_LEFT) / maxf(field.x, 0.001)


## 纵深方向的「像素 / 单位」，就是 [method px_per_unit] 压过 [constant Y_SCALE] 之后的那一个。
## 单独一个函数：调用方各自乘的话乘漏一处，那样东西就画在别人上面几十像素的地方。
static func px_per_lane(field: Vector2) -> float:
	return px_per_unit(field) * Y_SCALE


## 战场那条道的下沿。**从战场高度算出来，不是常量** ——
## 写死一个数的话，改 [member PBSimConfig.field_height] 就会让画面
## 和判定悄悄错开，而那种错开只表现为「打得到的敌人画在道外面」。
static func lane_bottom(field: Vector2) -> float:
	return GROUND_TOP + field.y * px_per_lane(field)


## 战场坐标 → 屏幕坐标。**全项目唯一一份。**
##
## 各写一份的话，「预示圈盖住的位置」和「真正挨打的位置」会差几个像素，
## 而那种偏差看起来只是「大招好像打偏了」。
##
## [param field] 是 `Vector2(field_length, field_height)`。
static func to_screen(at: Vector2, field: Vector2) -> Vector2:
	return Vector2(FIELD_LEFT + at.x * px_per_unit(field), GROUND_TOP + at.y * px_per_lane(field))


## 屏幕坐标 → 战场坐标，[method to_screen] 的逆（鼠标点选用）。**和正向那一份必须成对改。**
static func to_field(at: Vector2, field: Vector2) -> Vector2:
	return Vector2(
		(at.x - FIELD_LEFT) / px_per_unit(field), (at.y - GROUND_TOP) / px_per_lane(field)
	)


## 战场上的两个点在**屏幕上**隔多少像素，点选判定走它。
## 不能在战场坐标里量：y 被压过，拿一个标量半径去判定等于要求玩家纵向点得比横向准三成。
static func screen_gap(a: Vector2, b: Vector2, field: Vector2) -> float:
	return to_screen(a, field).distance_to(to_screen(b, field))


## 地面上一个半径 [param radius_px] 的圆，投到屏幕上的那一圈点（首尾闭合）。
##
## **全项目画地面上的圆只准走这里。** 射程圈、忍术落点圈、大招落点预示
## 三处各写一遍 `draw_circle` 的话，它们会在「圆还是椭圆」这件事上分叉，
## 而分叉的表现是「有的圈躲得开、有的躲不开」，玩家无从分辨哪个是真的。
##
## [param radius_px] 是**横向**半径（[method px_per_unit] 换算出来的那个），
## 纵向由 [constant Y_SCALE] 压出来 —— 传两个半径进来就又有两把尺子了。
static func ground_disc(at: Vector2, radius_px: float, segments: int = 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	if radius_px <= 0.0:
		return out
	var steps: int = maxi(segments, 8)
	out.resize(steps + 1)
	for i: int in steps + 1:
		var angle: float = TAU * float(i) / float(steps)
		out[i] = at + Vector2(cos(angle) * radius_px, sin(angle) * radius_px * Y_SCALE)
	return out


## 把上面这些矩形贴到场景节点上。**`.tscn` 里不写死这些数**，否则改排版要两处各改，
## 对不上只表现为「底板和判定区错开几个像素」。
static func apply_to(
	lane: ColorRect, limit: ColorRect, info: Label, preview: Label, field: Vector2, limit_x: float
) -> void:
	var bottom: float = lane_bottom(field)
	# **底板铺满整个 B 框**：只铺地面带的话最里面那条道上的人有半个身子露在背景色上，像站到了场外。
	lane.position = B_FIELD.position - B_LANE_INSET
	lane.size = B_FIELD.size + B_LANE_INSET * 2.0
	# 界限竖线的 x 是算出来的（夹取用 `deploy_limit_x`），否则「拖到线上松手，人却弹回去一点」。
	limit.position = Vector2(to_screen(Vector2(limit_x, 0.0), field).x - 1.0, GROUND_TOP)
	limit.size = Vector2(2.0, bottom - GROUND_TOP)
	for pair: Array in [[info, A_INFO], [preview, A_PREVIEW]]:
		var label := pair[0] as Label
		var rect := pair[1] as Rect2
		label.position = rect.position
		label.size = rect.size
		label.add_theme_font_size_override(&"font_size", A_FONT_SIZE)
