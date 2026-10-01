@tool
class_name PBBuffGlow
extends Node2D
## 一名单位固定前后两节点，取消与到期每帧按真实状态收回；同名多来源只画一次。

const FOOT_RING_STEP := 36.0
static var _library: Dictionary = {}
static var _instant_library: Dictionary = {}
var front: bool = false
var _drawings: Array[Dictionary] = []
var _normal := PBBuffGlowLayer.new(false)
var _additive := PBBuffGlowLayer.new(true)


func _init() -> void:
	# 每个前/后层固定两种混合通道；普通透明在下、加色在上，不随状态顺序跳层。
	add_child(_normal)
	add_child(_additive)


static func skin_for(id: StringName) -> PBBuffSkin:
	if not _library.has(id):
		var path := "res://data/buff_art/%s.tres" % id
		var skin := load(path) as PBBuffSkin if ResourceLoader.exists(path) else null
		_library[id] = skin if skin != null and skin.problem() == "" else null
	return _library[id]


static func instant_skin_for(id: StringName) -> PBBuffSkin:
	if not _instant_library.has(id):
		var path := "res://data/instant_buff_art/%s.tres" % id
		var skin := load(path) as PBBuffSkin if ResourceLoader.exists(path) else null
		_instant_library[id] = skin if skin != null and skin.problem() == "" else null
	return _instant_library[id]


func sync_bag(
	bag: PBBuffBag, tick: int, rate: int, alive: bool = true, aura_ids: Array[StringName] = []
) -> void:
	var next: Array[Dictionary] = []
	var seen: Dictionary = {}
	if alive:
		for state: PBBuffState in bag.states():
			if not _live_for_view(state, tick) or seen.has(state.buff.id):
				continue
			seen[state.buff.id] = true
			# 独立四态已经包含完整轮廓时，不再叠旧的环身占位光。
			if PBActorLibrary.skin_for(PBFormArt.for_buff(state.buff.id).actor_key) != null:
				continue
			var skin := skin_for(state.buff.id)
			if skin != null:
				next.append(_drawing(skin, tick - state.applied_at, rate))
		for id: StringName in aura_ids:
			if seen.has(id):
				continue
			seen[id] = true
			var skin := skin_for(id)
			if skin != null:
				next.append(_drawing(skin, tick, rate))
	_set_drawings(next)


## 引导的只读查询不锁定中断；表现开关不能影响下一次战斗结算。
func _live_for_view(state: PBBuffState, tick: int) -> bool:
	return (
		state.buff != null
		and (state.buff.until_wave_end or tick <= state.until_tick)
		and (state.channel == null or state.channel.valid_now(tick))
	)


func preview(skin: PBBuffSkin, tick: int) -> void:
	var next: Array[Dictionary] = []
	if skin != null:
		next.append(_drawing(skin, tick, 20))
	_set_drawings(next)


func preview_once(skin: PBBuffSkin, tick: int, rate: int) -> void:
	if skin == null:
		clear()
		return
	var frames := skin.front_frames if front else skin.back_frames
	var frame := floori(float(maxi(tick, 0)) * skin.fps / maxi(rate, 1))
	_set_drawings([{"skin": skin, "frame": mini(frame, maxi(frames.size() - 1, 0))}])


## 瞬时效果按发生 tick 播一次，六帧结束立即收回；不依赖效果袋。
func sync_instant(id: StringName, elapsed_ticks: int, rate: int, alive: bool = true) -> void:
	var skin := instant_skin_for(id)
	if not alive or skin == null or elapsed_ticks < 0:
		clear()
		return
	var frames := skin.front_frames if front else skin.back_frames
	if frames.is_empty():
		clear()
		return
	var frame := floori(float(elapsed_ticks) * skin.fps / maxi(rate, 1))
	if frame >= frames.size():
		clear()
		return
	_set_drawings([{"skin": skin, "frame": frame}])


func clear() -> void:
	_set_drawings([])


func _drawing(skin: PBBuffSkin, ticks: int, rate: int) -> Dictionary:
	var frames := skin.front_frames if front else skin.back_frames
	var frame := floori(float(maxi(ticks, 0)) * skin.fps / maxi(rate, 1))
	return {"skin": skin, "frame": frame % frames.size() if not frames.is_empty() else frame % 12}


func _set_drawings(next: Array[Dictionary]) -> void:
	visible = not next.is_empty()
	_drawings = []
	var normal: Array[Dictionary] = []
	var additive: Array[Dictionary] = []
	var foot_ring_index := 0
	for item: Dictionary in next:
		var placed := item.duplicate()
		var skin: PBBuffSkin = placed.skin
		if skin.foot_ring:
			placed["stack_offset_y"] = -FOOT_RING_STEP * foot_ring_index
			foot_ring_index += 1
		_drawings.append(placed)
		if skin.blend_style == PBBuffSkin.BlendStyle.ALPHA:
			normal.append(placed)
		else:
			additive.append(placed)
	_normal.sync_drawings(normal, front)
	_additive.sync_drawings(additive, front)
