class_name PBStatRules
extends RefCounted
## 从角色表 + 等级 + 星级 + 词条算出 [PBStats]（§03A）。全部 static，零引擎依赖。
##
## **唯一一处把二级属性折成基础属性的地方** —— 有第二处的话系数迟早对不上，
## 表现为「信息栏的攻击力和战场上打出来的伤害不一样」。
##
## 等级与星级是两条轴：**等级**按各自成长值抬力敏智，放大这张卡已有的偏向；
## **星级**是乘在基础属性上的整体倍率。

## 占位属性表的稀有度阶梯，**必须与 [member PBSimConfig.rarity_power] 一致**。
##
## 它在这里再写一遍，是因为 [method PBCharacter.make] 手上没有配置对象。
## 两份写歪了不会报错，只会让合成角色表和真角色表的强度悄悄分叉 ——
## `test_stats.gd` 里有一条断言把它们钉在一起。
const PLACEHOLDER_RARITY_DPS: Array[float] = [100.0, 130.0, 169.0]

# ── 原版的换算系数 ──────────────────────────────────────────────
#
# 全部来自原版 `war3mapMisc.txt`（`Docs/原版数据_忍法战场v1.5.80.md` §3），
# 是引擎默认值 —— 差异全在每个角色的三围上。
#
# **只给真名册用**（[method apply_original_scale]）。[method fill_placeholder]
# 是合成表那条声明为替身的曲线，回答的不是同一个问题。

## 每点力量给多少生命。
const HP_PER_STRENGTH: float = 80.0

## 每点主属性给多少攻击力。
const ATK_PER_PRIMARY: float = 3.5

## 每点敏捷给多少护甲。
const DEF_PER_AGILITY: float = 0.22

## 每点敏捷给多少攻速（比例）。
const SPEED_PER_AGILITY: float = 0.009

## 每点智力给多少查克拉。
const MP_PER_INTELLECT: float = 0.7

## 不含三围时的生命 / 查克拉 / 攻击 / 护甲。原版每个单位的物编都是这一套 ——
## **所有忍者的基础值完全相同**，差异一格都不在这里。
const BASE_HP: float = 100.0
const BASE_MP: float = 100.0
const BASE_ATK: float = 1.0
const BASE_DEF: float = 4.0

## 主属性按属性分：土/物理 → 力量，风/雷 → 敏捷，火/水/仙 → 智力。
##
## **仙这一格只有占位表用得到。** 真名册里攻仙的两个人主属性并不一致
## （佩恩是敏捷、兜是智力），所以这张表答不了他们 ——
## 而它本来也不负责：真角色的主属性从 `data/roster.tsv` 逐个读。
## 留这一格是为了不让 [method PBCharacter.make] 掉进 `.get` 的兜底，
## 那条路会让一个仙系角色安静地变成力量型。
const PLACEHOLDER_PRIMARY := {
	PBElement.Type.EARTH: PBCharacter.Primary.STRENGTH,
	PBElement.Type.PHYSICAL: PBCharacter.Primary.STRENGTH,
	PBElement.Type.WIND: PBCharacter.Primary.AGILITY,
	PBElement.Type.THUNDER: PBCharacter.Primary.AGILITY,
	PBElement.Type.FIRE: PBCharacter.Primary.INTELLECT,
	PBElement.Type.WATER: PBCharacter.Primary.INTELLECT,
	PBElement.Type.SAGE: PBCharacter.Primary.INTELLECT,
}

## 力量加几点。**量型**（直接加点数）。
const STRENGTH: StringName = &"strength"

## 敏捷加几点。**量型**。
const AGILITY: StringName = &"agility"

## 智力加几点。**量型**。
const INTELLECT: StringName = &"intellect"

## 三围各加几点（原版的「全属性 +N」）。**量型**，和上面三个相加。
const ALL_STATS: StringName = &"all_stats"
## 按忍者当前等级增加三围，包含一级，不是每次升级才加的成长。
const ALL_STATS_PER_LEVEL: StringName = &"all_stats_per_level"

## 三围各多几成（原版羁绊的「提升 20% 的全属性」）。**率型**，中性 0.0。
##
## **只放大角色自己的三围**（1 级值 + 等级成长），点数词条排在它后面加、不跟着放大：
## 放大点数的话，装备的「全属性 +30」和羁绊的 +20% 连乘，越往后装备越多、这一句越强。
const ALL_STATS_BONUS: StringName = &"all_stats_bonus"
## 将装备点数并入后再加成；按原触发取整数增量，不放大直接攻击 / 生命词条。
const ALL_STATS_TOTAL_BONUS: StringName = &"all_stats_total_bonus"

## 攻击力加几点。**量型**。
##
## ## 它为什么非在这一层不可
##
## [member PBAttacker.attack] 是 `stats.atk × 属性克制`——**克制已经乘进去了**。
## 事后往攻击者身上加的话，装备给的这 200 点攻击力**不吃克制**，
## 而原版是吃的（克制是伤害倍率，攻击力在它下游）。
## 表现是「带克制系装备的收益比裸的低一截」，而它不报错。
const ATTACK: StringName = &"attack"

## 防御加几点。**量型**。
const DEFENCE: StringName = &"defence"

## 最大生命加几点。**量型**（原版的「生命值 +1200」）。
const MAX_HP: StringName = &"max_hp"

## 最大生命多几成。**率型**，中性 0.0。
const HP_BONUS: StringName = &"hp_bonus"

## 攻速多几成。**率型**，中性 0.0。
## [method PBAttacker.prime] 拿到的 [member PBAttacker.attack_speed] 已经是算完加成的数。
const ATTACK_SPEED: StringName = &"attack_speed"
## 先从基础攻击间隔减秒，再乘敏捷和攻速加成；不是最终间隔直接减秒。
const ATTACK_INTERVAL_REDUCTION: StringName = &"attack_interval_reduction"

## 认得的全部属性词条。见本类顶上「属性 vs 行为」。
const ALL: Array[StringName] = [
	STRENGTH,
	AGILITY,
	INTELLECT,
	ALL_STATS,
	ALL_STATS_PER_LEVEL,
	ALL_STATS_BONUS,
	ALL_STATS_TOTAL_BONUS,
	ATTACK,
	DEFENCE,
	MAX_HP,
	HP_BONUS,
	ATTACK_SPEED,
	ATTACK_INTERVAL_REDUCTION,
]


## 把原版那套换算系数铺到一个角色上。
##
## 三围、成长与攻击间隔由调用方从 `data/roster.tsv` 填（数据），这里只管规则。
## **名册那条路不调 [method fill_placeholder]**：它会按稀有度覆盖三围并把 DPS 拉回阶梯，
## 56 个角色的真三围会在最后一步被抹平，而属性栏里数字全对、不报错。
##
## [param interval] 是原版的攻击间隔（秒）。本项目的攻速是「每秒几次」，所以取倒数。
static func apply_original_scale(character: PBCharacter, interval: float) -> void:
	if character == null:
		return
	character.hp_base = BASE_HP
	character.mp_base = BASE_MP
	character.atk_base = BASE_ATK
	character.def_base = BASE_DEF
	character.hp_per_strength = HP_PER_STRENGTH
	character.atk_per_primary = ATK_PER_PRIMARY
	character.def_per_agility = DEF_PER_AGILITY
	character.mp_per_intellect = MP_PER_INTELLECT
	character.attack_speed_per_agility = SPEED_PER_AGILITY
	character.attack_speed_base = 1.0 / maxf(interval, 0.05)


## 给一个还没有属性数据的角色铺一套占位属性（§03A）。
##
## [method PBCharacter.make] 只填 id / 属性 / 稀有度，[method PBCharacterTable.synthetic]
## 整张合成表走这条路。不铺的话每个角色吃默认值，稀有度阶梯在合成表上消失 ——
## 不会让断言变红，只会让用合成表的整局测试跑在一副全是白板的牌上。
static func fill_placeholder(character: PBCharacter) -> void:
	if character == null:
		return
	var rarity: int = clampi(int(character.rarity), 0, PLACEHOLDER_RARITY_DPS.size() - 1)
	character.primary = PLACEHOLDER_PRIMARY.get(character.element, PBCharacter.Primary.STRENGTH)
	# 防元素 = 克制我攻元素的那一系。攻守指向不同波次，两轴才不会同进同退。
	character.def_element = PBElement.counter_of(character.element)

	var main_value: float = 18.0 + 4.0 * float(rarity)
	var side_value: float = 12.0 + 2.0 * float(rarity)
	var main_growth: float = 2.6 + 0.4 * float(rarity)
	var side_growth: float = 1.4 + 0.2 * float(rarity)
	character.strength = side_value
	character.agility = side_value
	character.intellect = side_value
	character.strength_growth = side_growth
	character.agility_growth = side_growth
	character.intellect_growth = side_growth
	match character.primary:
		PBCharacter.Primary.AGILITY:
			character.agility = main_value
			character.agility_growth = main_growth
		PBCharacter.Primary.INTELLECT:
			character.intellect = main_value
			character.intellect_growth = main_growth
		_:
			character.strength = main_value
			character.strength_growth = main_growth

	# 近战厚而慢，超远程脆而快。
	match character.reach_tier():
		PBCharacter.Reach.MELEE:
			character.hp_base = 260.0
			character.def_base = 3.0
			character.attack_speed_base = 0.85
			character.hp_per_strength = 22.0
			character.def_per_agility = 0.35
		PBCharacter.Reach.LONG:
			character.hp_base = 160.0
			character.def_base = 0.0
			character.attack_speed_base = 1.15
			character.hp_per_strength = 12.0
			character.def_per_agility = 0.15
		_:
			character.hp_base = 200.0
			character.def_base = 1.0
			character.attack_speed_base = 1.0
			character.hp_per_strength = 16.0
			character.def_per_agility = 0.22
	character.mp_base = 60.0 + 10.0 * float(rarity)

	# 反解攻击力基数，使 1 级 1 星的「攻 × 攻速」正好落在稀有度阶梯上。
	# **这是新旧模型的接缝**：换成属性表之后，战力口径一点没变。
	var speed: float = (
		character.attack_speed_base * (1.0 + character.agility * character.attack_speed_per_agility)
	)
	character.atk_base = (
		PLACEHOLDER_RARITY_DPS[rarity] / maxf(speed, 0.001) - main_value * character.atk_per_primary
	)


## 这个键是不是一条属性词条。
##
## **和 [method PBPassiveRules.is_known] 是互斥的两张表**（属性在算三围时注入，
## 行为在建人之后装）。一个键同时进两张表的话会被算两遍，而那不报错。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 把几份词条表并成一份（同键累加）。**只收这张表认得的键** ——
## 别的（暴击、闪避、溅射……）归 [method PBPassiveRules.equip]。
##
## [param sources] 按顺序是角色自带 / 羁绊 / 尾兽光环 / 装备。
## **同键相加不覆盖**：两组羁绊各给 +15 点防御该是 +30，
## 而覆盖的表现是玩家凑满两组只拿到一组的量（同 [PBBuffBag] 那个坑）。
static func collect(sources: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for one: Dictionary in sources:
		for key: StringName in one:
			if is_known(key):
				out[key] = float(out.get(key, 0.0)) + float(one[key])
	return out


## 词条里这个键是多少。没有就是 0。
static func amount(mods: Dictionary, key: StringName) -> float:
	return float(mods.get(key, 0.0))


## 算出一个角色在 [param level] 级、[param star] 星、带着 [param mods] 词条时的全部属性。
## [param star] 走 [method PBUnit.star]，最低 1。
static func of(
	character: PBCharacter,
	level: int,
	star: int,
	cfg: PBSimConfig,
	mods: Dictionary = {},
	runtime_additions: Dictionary = {}
) -> PBStats:
	var out := PBStats.new()
	if character == null:
		return out

	# ── 二级属性：1 级值 + 每级成长 ────────────────────────────
	var steps: float = float(maxi(level, 1) - 1)
	out.strength = character.strength + character.strength_growth * steps
	out.agility = character.agility + character.agility_growth * steps
	out.intellect = character.intellect + character.intellect_growth * steps
	# **一级属性的词条在这儿注入**：下面每个二级属性都从这三个数算出来。
	# 空词条时每一句都是 `+= 0.0` / `*= 1.0`，逐位不变。成数先乘、点数后加（见 [constant ALL_STATS_BONUS]）。
	var own_scale: float = 1.0 + maxf(amount(mods, ALL_STATS_BONUS), -1.0)
	out.strength *= own_scale
	out.agility *= own_scale
	out.intellect *= own_scale
	var every: float = amount(mods, ALL_STATS) + amount(mods, ALL_STATS_PER_LEVEL) * maxi(level, 1)
	out.strength += amount(mods, STRENGTH) + every
	out.agility += amount(mods, AGILITY) + every
	out.intellect += amount(mods, INTELLECT) + every
	var total_bonus: float = maxf(amount(mods, ALL_STATS_TOTAL_BONUS), 0.0)
	if total_bonus > 0.0:
		out.strength += floorf(floorf(out.strength) * total_bonus)
		out.agility += floorf(floorf(out.agility) * total_bonus)
		out.intellect += floorf(floorf(out.intellect) * total_bonus)
	# 开战后的赠送 / 临时增量不再次吃开局的百分比强化。
	out.strength += amount(runtime_additions, STRENGTH)
	out.agility += amount(runtime_additions, AGILITY)
	out.intellect += amount(runtime_additions, INTELLECT)

	# ── 基础属性：固定部分 + 二级属性 × 系数 ──────────────────
	var star_mult: float = 1.0 + cfg.star_power_mult * float(maxi(star, 1) - 1)
	out.hp = (character.hp_base + out.strength * character.hp_per_strength) * star_mult
	out.mp = character.mp_base + out.intellect * character.mp_per_intellect
	out.atk = (
		(character.atk_base + primary_value(character, out) * character.atk_per_primary) * star_mult
	)
	out.def = character.def_base + out.agility * character.def_per_agility
	var base_speed: float = character.attack_speed_base
	if base_speed > 0.0 and amount(mods, ATTACK_INTERVAL_REDUCTION) > 0.0:
		base_speed = 1.0 / maxf(1.0 / base_speed - amount(mods, ATTACK_INTERVAL_REDUCTION), 0.05)
	out.attack_speed = base_speed * (1.0 + out.agility * character.attack_speed_per_agility)
	# 二级属性的词条排在这儿 —— 它们不参与上面那几条派生。
	# **点数不吃星级倍率**：星级放大的是这个角色自己的底子，
	# 而装备给的 200 点攻击力对谁都是 200 点。
	out.base_atk = out.atk
	out.atk += amount(mods, ATTACK)
	out.def += amount(mods, DEFENCE)
	out.hp = (out.hp + amount(mods, MAX_HP)) * (1.0 + amount(mods, HP_BONUS))
	out.attack_speed *= 1.0 + amount(mods, ATTACK_SPEED)
	return out


## 主属性现在是多少点。见 [enum PBCharacter.Primary]。
static func primary_value(character: PBCharacter, stats: PBStats) -> float:
	match character.primary:
		PBCharacter.Primary.AGILITY:
			return stats.agility
		PBCharacter.Primary.INTELLECT:
			return stats.intellect
		_:
			return stats.strength


## 防御把伤害减掉多少（0–1）。**递减曲线，永远到不了 100%。**
##
## 用 `def·k / (1 + def·k)` 而不是线性减免：线性的话防御一旦堆过某个值
## 就完全免疫，那是 §04 指数难度曲线下必然会发生的事
## （敌人 ATK 按 `GROWTH^n` 涨，玩家的防御是加法涨的 —— 反过来也一样，
## 后期防御必然被穿透）。递减曲线两头都不会失控。
static func damage_reduction(def: float, cfg: PBSimConfig) -> float:
	if def <= 0.0:
		return 0.0
	var scaled: float = def * cfg.armor_scale
	return scaled / (1.0 + scaled)


## 一次攻击打多少伤害。**攻方的攻元素对守方的防元素算克制**（§03A）。
##
## 这个函数是攻防双元素唯一的落点。写成 static 且不碰任何状态，
## 是为了让敌人打玩家、玩家打敌人走同一份代码 —— 两份的话
## 「谁的元素当攻、谁的当防」迟早有一边写反，而那不报错。
static func strike_damage(
	attack: float,
	attack_element: PBElement.Type,
	defence: float,
	defence_element: PBElement.Type,
	cfg: PBSimConfig
) -> float:
	var rel := PBElement.relation(attack_element, defence_element)
	var raw: float = attack * cfg.damage_multiplier(rel)
	return raw * (1.0 - damage_reduction(defence, cfg))
