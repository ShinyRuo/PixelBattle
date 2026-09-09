class_name PBRngStreams
extends RefCounted
## 三条互相独立的随机数流。施工策划案 §12。
##
## | 流 | 消费者 |
## |---|---|
## | `gacha` | 抽卡、保底计数 |
## | `quest` | 任务刷新、波型 |
## | `combat` | 掉落、暴击 |
##
## **为什么必须分开**：三条流各走各的序列，某一路的调用次数变化不会污染另一路。
## 合成一条的话，改一次战斗掉落逻辑就会让所有旧存档的抽卡序列全变 ——
## 存档回滚、每日种子挑战、战报回放三样能力一起失效。
##
## **绝对不要用全局 `randi()` / `randf()`**：它们走共享的全局状态，
## 既不可存档也不可复现。core 纯度检查会直接拦下来。

const STREAM_NAMES: Array[StringName] = [&"gacha", &"quest", &"combat"]

## 抽卡流。
var gacha: RandomNumberGenerator

## 任务与波型流。
var quest: RandomNumberGenerator

## 战斗流。
var combat: RandomNumberGenerator

## 生成三条流所用的基准种子。每日种子挑战（§13）传 `hash(date_utc)` 进来即可。
var base_seed: int = 0


func _init(seed_value: int = 0) -> void:
	base_seed = seed_value
	gacha = _make_stream(&"gacha")
	quest = _make_stream(&"quest")
	combat = _make_stream(&"combat")


## 某一波专属的随机流。**每次调用返回一个全新实例**，种子由基准种子和波次序号派生。
##
## 波次生成必须是 `(种子, 波次)` 的纯函数，不能从一条顺序消费的流里取。
## 理由是 §04 要求「波型在准备阶段提前公示」—— 预告第 n+1 波就得先把它掷出来，
## 而从顺序流里取的话，这一掷会改变后续所有随机数的次序，
## 于是「有没有看预告」会影响后面抽到什么卡。那显然不行。
##
## 做成纯函数之后，预告任意波次都是零副作用的，
## 存档里也不需要记「第几波的波型已经掷过了」。
func wave_rng(wave_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/wave/%d" % [base_seed, wave_index])
	return rng


## 某一波**战斗内部**的随机流（暴击，M10-c）。同 [method wave_rng]：
## 每次调用返回一个全新实例，种子由基准种子和波次序号派生。
##
## ## 为什么不能直接把 [member combat] 传进战斗
##
## [method PBValuation._leaks_at] 每一波要**凭空跑几十场战斗**做悬崖二分
## （「整队缩到几成才开始漏怪」）。那些战斗和真正打的那一场共用一条顺序流的话，
## **「这一局有没有做过估值」会改变真实战斗的暴击序列** ——
## 而估值跑几场取决于二分收敛得多快，也就是取决于队伍强度。
##
## 那正是本类顶上「某一路的调用次数变化不会污染另一路」那条铁律，
## 只是这一次发生在**一条流的内部**。做成纯函数之后，探测掷多少次骰子
## 都不改变任何东西，同种子回放也逐位可复现。
##
## 标签和 [method wave_rng] 不同（`battle` vs `wave`），否则波型和暴击
## 会共用同一条序列 —— 那时改一次暴击判定就会换掉所有波型。
func battle_rng(wave_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/battle/%d" % [base_seed, wave_index])
	return rng


## 导出三条流的 `state` 供存档。
##
## **存成字符串不是 int**：`state` 是 uint64，而 JSON 的数字是双精度浮点，
## 超过 2^53 的部分会被静默截断 —— 读档后 RNG 序列就对不上了，
## 而这种损坏不会报错，只会表现为「玩家发现退出重进能刷好卡」。
## §12 定的存档格式是 JSON，所以在这一层就转成字符串。
func to_state() -> Dictionary:
	return {
		"gacha": str(gacha.state),
		"quest": str(quest.state),
		"combat": str(combat.state),
		"base_seed": str(base_seed),
	}


## 从存档恢复。缺字段的流保持当前状态，不报错 —— 版本迁移时旧档可能没有某条流。
func from_state(state: Dictionary) -> void:
	base_seed = _read_u64(state, "base_seed", base_seed)
	gacha.state = _read_u64(state, "gacha", gacha.state)
	quest.state = _read_u64(state, "quest", quest.state)
	combat.state = _read_u64(state, "combat", combat.state)


## 复制一份当前状态完全相同的流组。用于「从此刻分叉，跑几种不同决策看哪个好」。
func clone() -> PBRngStreams:
	var copy := PBRngStreams.new(base_seed)
	copy.from_state(to_state())
	return copy


## 由基准种子派生某条流的独立种子。
##
## 走 `hash(字符串)` 而不是 `base_seed + 序号`：相邻种子在很多 PRNG 上会产生
## 高度相关的前几个输出，而「玩家 A 用种子 100、玩家 B 用种子 101」在每日种子
## 场景里是必然发生的。哈希打散掉这层相关性。
func _make_stream(stream_name: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/%s" % [base_seed, stream_name])
	return rng


## 从存档字典读一个 uint64。兼容 int 与 String 两种写法。
func _read_u64(state: Dictionary, key: String, fallback: int) -> int:
	if not state.has(key):
		return fallback
	var raw: Variant = state[key]
	if raw is String:
		return (raw as String).to_int()
	return int(raw)
