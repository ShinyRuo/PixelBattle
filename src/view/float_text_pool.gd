class_name PBFloatTextPool
extends Node2D
## 伤害飘字（§02 的手感）。回答「我这一下打了多少」—— 没有它的话满血 BOSS 被打掉四成屏幕上一个数都没有，
## 玩家分不清「打得动但慢」和「压根打不动」（前者等，后者要马上换克制系）。
##
## **池子，不 new**（§14）：飘字频率比敌人生成高一个量级。
## **数字要压缩**：超过一万折成「x.x万」，这个尺度上要的是量级。

## 同屏最多飘几个。超了就抢最老的那一个 ——
## 让新的飘不出来比让旧的早退更糟：**玩家在等的是刚发生的那一下**。
const CAPACITY: int = 24

## 一个数字活多少个渲染帧，以及这期间往上飘多少像素。
const LIFE_FRAMES: int = 26
const RISE: float = 14.0

const FONT_SIZE: int = 8
const KILL_FONT_SIZE: int = 9

## 暴击的字号：**和击杀同一号字，换一个颜色** —— 再大会盖过击杀，而「他死了」仍是唯一会改变决策的那条。
const CRIT_FONT_SIZE: int = 9

## 普通伤害是白的，击杀是金的。**击杀必须比伤害显眼** ——
## 「他死了」是这一串数字里唯一会改变玩家决策的那一条。
const HIT_COLOR := Color(0.94, 0.95, 0.98)
const KILL_COLOR := Color(0.98, 0.85, 0.45)

## 暴击是橙红的。**和金色分得开是硬要求**：一次暴击击杀会同时满足两条，
## 而那时该显示的是「他死了」—— 击杀在 [method pop] 里排在前面。
const CRIT_COLOR := Color(1.0, 0.55, 0.32)

var _labels: Array[Label] = []
var _life: PackedInt32Array = PackedInt32Array()
var _from: PackedVector2Array = PackedVector2Array()
var _next: int = 0


func _ready() -> void:
	_life.resize(CAPACITY)
	_from.resize(CAPACITY)
	for _i: int in CAPACITY:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.visible = false
		add_child(label)
		_labels.append(label)


## 在 [param at] 飘一个数字出来。[param killed] 为真用击杀配色，[param crit] 为真用暴击配色。
## **两个都为真时按击杀画**，写成一条 if/elif 让优先级只有一个答案。
func pop(at: Vector2, amount: float, killed: bool, crit: bool = false) -> void:
	if amount <= 0.0 and not killed:
		return
	var index: int = _next
	_next = (_next + 1) % CAPACITY
	var label: Label = _labels[index]
	label.text = _short(amount)
	var tint: Color = HIT_COLOR
	var size: int = FONT_SIZE
	if killed:
		tint = KILL_COLOR
		size = KILL_FONT_SIZE
	elif crit:
		tint = CRIT_COLOR
		size = CRIT_FONT_SIZE
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	label.visible = true
	# 每个数字往左右错开一点，同一个敌人连着挨打时才不会叠成一坨黑。
	_from[index] = at + Vector2(float(index % 5) - 2.0, -6.0)
	label.position = _from[index]
	_life[index] = LIFE_FRAMES


## 推进一帧：往上飘、淡出、到期收回。每渲染帧调一次。
func step() -> void:
	for i: int in CAPACITY:
		if _life[i] <= 0:
			continue
		_life[i] -= 1
		var t: float = 1.0 - float(_life[i]) / float(LIFE_FRAMES)
		var label: Label = _labels[i]
		label.position = _from[i] - Vector2(0.0, RISE * t)
		# 前三分之一保持全不透明 —— 一出来就开始淡的话，最该看清的那一瞬间最淡。
		label.modulate.a = 1.0 if t < 0.34 else 1.0 - (t - 0.34) / 0.66
		if _life[i] <= 0:
			label.visible = false


## 全部收回（换波、换局）。
func clear() -> void:
	for i: int in CAPACITY:
		_life[i] = 0
		_labels[i].visible = false


## 压缩过的数字。后期一发大招打六位数，原样写出来半个屏幕宽。
func _short(amount: float) -> String:
	if amount < 10000.0:
		return "%d" % int(round(amount))
	return "%.1f万" % (amount / 10000.0)
