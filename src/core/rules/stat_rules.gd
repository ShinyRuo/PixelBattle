class_name PBStatRules
extends RefCounted
## 从角色表 + 等级 + 星级算出 [PBStats]。§03A，M3.5-a。全部 static，零引擎依赖。
##
## ## 唯一一处把二级属性折成基础属性的地方
##
## §03A 的形状是「二级属性只通过系数影响基础属性」，而**只要有第二处
## 也在做这件事，两处的系数迟早对不上** —— 表现为「信息栏显示的攻击力
## 和战场上真打出来的伤害不一样」，和 CLAUDE.md 那条
## 「四块面板与比价同源」防的是同一种病。
##
## ## 等级与星级是两条不同的轴
##
## - **等级**（§02 的指令卡花金币升）抬**二级属性** —— 力/敏/智各按自己的
##   成长值涨，所以升级会顺着这张卡的定位放大它已有的偏向
## - **星级**（§08 的同卡 3 张升 1 星）是一个**乘在基础属性上的整体倍率** ——
##   它不改变定位，只是整体变强
##
## 分开是有意的：合成一条的话，「升级」和「抽到重复卡」会变成同一件事的
## 两种付款方式，而 §07 的经济张力恰恰建在「这两笔钱抢同一个预算」上。

## 占位属性表的稀有度阶梯，**必须与 [member PBSimConfig.rarity_power] 一致**。
##
## 它在这里再写一遍，是因为 [method PBCharacter.make] 手上没有配置对象。
## 两份写歪了不会报错，只会让合成角色表和真角色表的强度悄悄分叉 ——
## `test_stats.gd` 里有一条断言把它们钉在一起。
const PLACEHOLDER_RARITY_DPS: Array[float] = [100.0, 130.0, 169.0]

# ── 原版的换算系数（M12-b）──────────────────────────────────────
#
# 全部来自原版地图的 `war3mapMisc.txt`，见
# `Docs/原版数据_忍法战场v1.5.80.md` §3。它们是引擎默认值，
# 也就是原版作者**没有改过**这一层 —— 差异全在每个角色的三围上。
#
# **这几个数只给真名册用**（[method apply_original_scale]）。
# [method fill_placeholder] 那条路仍走它自己的一套 —— 那不是两把尺子：
# 占位表是一条**声明为替身的曲线**，它的职责是复现稀有度阶梯，
# 而真角色现在有真三围，两者回答的不是同一个问题。

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


## 把原版那套换算系数铺到一个角色上（M12-b）。
##
## 三围、成长与攻击间隔由调用方从 `data/roster.tsv` 逐个填 —— 那些是**数据**；
## 这里只负责那一层**规则**（几点力量换多少血）。
##
## ## 它和 [method fill_placeholder] 的分工
##
## 那个函数的名字就说清楚了：**给一个还没有属性数据的角色**铺占位值。
## 真角色现在有属性数据了，所以名册那条路不再调它 —— 调了的话，
## 它会先按稀有度覆盖一遍三围，再反解 `atk_base` 把 DPS 拉回阶梯上，
## 于是「56 个角色各有各的三围」这件事在最后一步被抹平，
## **而它不报错**：属性栏里数字全对，只是每个人打出来的伤害一样多。
##
## [param interval] 是原版的攻击间隔（秒）。攻速在本项目里是「每秒几次」
## （[method PBAttacker.prime] 拿 `tick_rate / attack_speed` 换间隔），
## 所以这里取倒数 —— 直接把 1.5 填进 `attack_speed_base` 的话，
## 每个人会变成一秒打一点五下，快出一倍还多。
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
## ## 为什么这个函数必须存在
##
## `data/characters/*.tres` 的属性块是生成脚本铺的，**但代码里造出来的角色没有** ——
## [method PBCharacter.make] 只填 id / 属性 / 稀有度，而
## [method PBCharacterTable.synthetic] 造的那整张合成表全走这条路。
##
## 不铺的话，合成表里每个角色都吃 [PBCharacter] 的默认值：
## **R 和顶档的战力一模一样**，稀有度阶梯在合成表上彻底消失。
## 那不会让任何断言变红（合成表的用例查的是构成，不是强度），
## 只会让所有用合成表的整局测试跑在一副「全是白板」的牌上 ——
## 实测表现为整套测试从 30 秒涨到 120 秒，而没有一条测试报错。
##
## 规则与生成脚本逐条相同，改一边就要改另一边。
static func fill_placeholder(character: PBCharacter) -> void:
	if character == null:
		return
	var rarity: int = clampi(int(character.rarity), 0, PLACEHOLDER_RARITY_DPS.size() - 1)
	character.primary = PLACEHOLDER_PRIMARY.get(
		character.element, PBCharacter.Primary.STRENGTH
	)
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
		character.attack_speed_base
		* (1.0 + character.agility * character.attack_speed_per_agility)
	)
	character.atk_base = (
		PLACEHOLDER_RARITY_DPS[rarity] / maxf(speed, 0.001)
		- main_value * character.atk_per_primary
	)


## 算出一个角色在 [param level] 级、[param star] 星时的全部属性。
##
## [param star] 走 [method PBUnit.star]，最低 1。
static func of(
	character: PBCharacter, level: int, star: int, cfg: PBSimConfig
) -> PBStats:
	var out := PBStats.new()
	if character == null:
		return out

	# ── 二级属性：1 级值 + 每级成长 ────────────────────────────
	var steps: float = float(maxi(level, 1) - 1)
	out.strength = character.strength + character.strength_growth * steps
	out.agility = character.agility + character.agility_growth * steps
	out.intellect = character.intellect + character.intellect_growth * steps

	# ── 基础属性：固定部分 + 二级属性 × 系数 ──────────────────
	var star_mult: float = 1.0 + cfg.star_power_mult * float(maxi(star, 1) - 1)
	out.hp = (character.hp_base + out.strength * character.hp_per_strength) * star_mult
	out.mp = character.mp_base + out.intellect * character.mp_per_intellect
	out.atk = (
		(character.atk_base + primary_value(character, out) * character.atk_per_primary)
		* star_mult
	)
	out.def = character.def_base + out.agility * character.def_per_agility
	out.attack_speed = character.attack_speed_base * (
		1.0 + out.agility * character.attack_speed_per_agility
	)
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
