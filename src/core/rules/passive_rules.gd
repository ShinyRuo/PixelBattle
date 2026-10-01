class_name PBPassiveRules
extends RefCounted
## 一个**常驻效果**怎么装到一个人身上。全部 static，无状态，零引擎依赖。
##
## 和 [PBBuffRules]（会过期的效果）对着看：这一层管「他站在场上就一直是这样」，
## 不进效果袋，直接加在 [PBAttacker] 的字段上。
##
## 来源有几个（角色自带被动 / 羁绊成员效果 / 尾兽光环 / 装备），**走同一个 [method grant]** ——
## 各写一份映射的话，叠加方式迟早分叉（一个 `=` 一个 `+=`），而分叉的那一侧静默生效。
##
## ## 词汇表里的键 = 已经接上读点的键
##
## 拼对了却没人读的键比拼错更难查，所以**一个键都不预留**，要加就连着读点一起加：
##
## | 键 | 落在哪个字段 | 谁读它 |
## |---|---|---|
## | `crit_chance` | [member PBAttacker.crit_chance] | [method PBCritRules.chance_of] |
## | `crit_damage` | [member PBAttacker.crit_bonus] | [method PBCritRules.multiplier_of] |
## | `crit_on_hit` | [member PBAttacker.crit_on_hit] | [method PBStrikeRules.land] |
## | `splash` | [member PBAttacker.splash_damage] | [method PBStrikeRules.land] |
## | `splash_radius` | [member PBAttacker.splash_radius] | [method PBStrikeRules.splash_reach] |
## | `heavy_hit` | [member PBAttacker.heavy_bonus] | [method PBStrikeRules.land] |
## | `revive` | [member PBAttacker.revives_max] | [method PBAttacker.take_damage] |
## | `dodge` | [member PBAttacker.dodge] | [method dodges] |
## | `bite_current` | [member PBAttacker.bite_current] | [method PBStrikeRules.land] |
## | `bite_lost` | [member PBAttacker.bite_lost] | [method PBStrikeRules.land] |
## | `reflect` | [member PBAttacker.reflect] | [method PBStrikeRules.hurt_ally] |
## | `damage_bonus` | [member PBAttacker.damage_bonus] | [method PBAttacker.strike_for] |
## | `move_speed_bonus` | [member PBAttacker.move_speed_bonus] | [method equip] 折进 `move_speed` |
## | `low_hp` | [member PBAttacker.low_hp_at] | [method PBStrikeRules.wound_ally] |
## | `drain_cut` | [member PBAttacker.drain_cut] | [method PBBuffRules.advance_ally] |
## | `lifesteal` | [member PBAttacker.lifesteal] | [method PBStrikeRules.land] |
## | `dodge_heal` | [member PBAttacker.dodge_heal] | [method PBAttacker.take_damage] |
## | `struck_cd` | [member PBAttacker.struck_cd] | [method PBStrikeRules.hurt_ally] |
## | `heal_power` | [member PBAttacker.heal_power] | [method PBBuffRules.scale_heal] |
## | `struck_aura` | [member PBAttacker.struck_aura] | [method PBStrikeRules.hurt_ally] |
## | `struck_boost` | [member PBAttacker.struck_boost] | [method PBStrikeRules.hurt_ally] |
## | `struck_summon` | [member PBAttacker.struck_summon] | [method PBStrikeRules.hurt_ally] |
## | `open_low_hp` | [member PBAttacker.open_low_hp] | [method PBStrikeRules.open_wave] |
## | `undying_end_heal` | [member PBAttacker.undying_end_heal] | [method PBBuffRules.advance_ally] |
## | `regen_max` | [member PBAttacker.regen_max] | [method PBBuffRules.advance_ally] |
## | `fire_taken` 等六个 | [member PBAttacker.taken_by_element] | [method taken_scale] |
## | `dodge_counter` | [member PBAttacker.dodge_counter] | [method PBStrikeRules.hurt_ally] |
## | `melee_taken` | [member PBAttacker.melee_taken] | [method PBStrikeRules.hurt_ally] |
## | `melee_reflect` | [member PBAttacker.melee_reflect] | [method PBStrikeRules.hurt_ally] |
## | `struck_ranged` | [member PBAttacker.struck_ranged] | [method PBStrikeRules.hurt_ally] |
## | `struck_leap` | [member PBAttacker.struck_leap] | [method PBStrikeRules.hurt_ally] |
## | `pierce` | [member PBAttacker.pierce] | [method PBShotRules.advance] |
## | `armor_pen` | [member PBAttacker.armor_pen] | [method PBStrikeRules.mitigated] |
## | `ninjutsu_pen` | [member PBAttacker.ninjutsu_pen] | [method PBStrikeRules.mitigated] |
## | `ninjutsu_bonus` | [member PBAttacker.ninjutsu_bonus] | [method PBCritRules.hit] |
## | `ninjutsu_crit_chance` | [member PBAttacker.ninjutsu_crit_chance] | [PBCritRules] |
## | `ninjutsu_crit_damage` | [member PBAttacker.ninjutsu_crit_bonus] | [PBCritRules] |
## | `attack_ninjutsu` | [member PBAttacker.attack_ninjutsu] | [method PBCritRules.attack_kind] |
##
## **属性（力敏智、攻击力、防御、生命、攻速）不在这张表里**，在 [PBStatRules]：
## 属性在算三围那一刻注入，行为建人之后装。**移速留在这里**：它是全队一个数，
## 由 [member PBSimConfig.unit_move_seconds] 派生，不是角色属性。
##
## **裸名 = 量型，`_bonus` 后缀 = 率型**，每个键自己说清楚是哪一种。
##
## ## 两件有意不做的事
##
## - **己方的忍术抗性**：伤害已经分类型（[PBDamageKind]），但敌人今天只会普攻（体术），
##   没有一下忍术伤害会打到忍者身上 —— 加了也配了不生效。等敌人会放忍术再加。
## - 普攻暴击仍只有一个掷点。原版独立的攻击起手技能由 [PBOnAttackRules] 处理，
##   不伪装成暴击，也不从命中路径递归触发。

## 暴击率（常驻那一份）。
const CRIT_CHANCE: StringName = &"crit_chance"

## 暴击倍率的加数。**中性值是 0.0 不是 1.0** —— 见 [member PBAttacker.crit_bonus]。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 命中之后那一小段时间里额外的暴击率。
const CRIT_ON_HIT: StringName = &"crit_on_hit"

## 普攻附带的范围伤害，值是主伤害的几成。
const SPLASH: StringName = &"splash"

## 溅射够得到多远，**原版码数**（275 / 250 …）。0 = 没配，用默认半径。见 [method PBStrikeRules.splash_reach]。
const SPLASH_RADIUS: StringName = &"splash_radius"

## 对血还很多的敌人追加的那一笔，值是主伤害的几成。
const HEAVY_HIT: StringName = &"heavy_hit"

## 一波能重生几次。**取整** —— 半次重生没有意义。
const REVIVE: StringName = &"revive"

## 挨一下普攻有多大机会一点血都不掉。
const DODGE: StringName = &"dodge"

## 打出要害那一下额外按目标**当前**生命的几成再打一笔。
const BITE_CURRENT: StringName = &"bite_current"

## 同 [constant BITE_CURRENT]，但按目标**已经损失**的生命算。
const BITE_LOST: StringName = &"bite_lost"

## 挨一下就把这一下伤害的几成还给打他的那个敌人。
const REFLECT: StringName = &"reflect"

## 常驻增伤：普攻多打几成。
const ALL_DAMAGE_BONUS: StringName = &"all_damage_bonus"

const TAIJUTSU_BONUS: StringName = &"taijutsu_bonus"

const NINJUTSU_RESIST: StringName = &"ninjutsu_resist"

const DAMAGE_BONUS: StringName = &"damage_bonus"

## 移动速度多几成。中性 0.0，折算在 [method equip] 末尾。
const MOVE_SPEED_BONUS: StringName = &"move_speed_bonus"
## 开战形态将普攻改为远程，射程按原版码数；0 不覆盖，多个来源取最大。
const RANGED_RANGE: StringName = &"ranged_range"

## 生命掉到最大生命的几成以下时，挂上他自带的那几份效果（[member PBAttacker.low_hp_buffs]）。
## 效果本身写在名册同一列的 `on_low_hp=<效果键>`，这个键只管阈值。
const LOW_HP: StringName = &"low_hp"

## 自身掉血（[constant PBBuffRules.DRAIN_MAX]）抵掉几成。1.0 = 不再掉血（〔吾之牢笼〕那一句）。
const DRAIN_CUT: StringName = &"drain_cut"

## 普攻吸血：这一下让目标**实际掉的血**有几成回到自己身上（尾兽光环、羁绊、装备都给）。
const LIFESTEAL: StringName = &"lifesteal"

## 闪避成功时回复**这一下本该挨的伤害**的几成（〔和平的期望〕「每次成功闪避都能恢复本次伤害 35% 的生命值」）。
const DODGE_HEAL: StringName = &"dodge_heal"

## 受击触发（名册同一列的 `on_struck=<效果键>`）的冷却，秒。0 = 每挨一下都触发；999 = 一波一次。
const STRUCK_CD: StringName = &"struck_cd"

## 这个人**放出去**的治疗量多几成（技能挂的回血、被动挂给自己的回血）。**不是「受到的治疗」**。
const HEAL_POWER: StringName = &"heal_power"

## 受击效果变成光环：周围多少**原版码数**内的队友挨打时，也按他的受击效果触发。取大。
const STRUCK_AURA: StringName = &"struck_aura"

## 受击效果里的量型数值多几成（防御、回血……，率型不乘）。
const STRUCK_BOOST: StringName = &"struck_boost"
const STRUCK_STRENGTH_BONUS: StringName = &"struck_strength_bonus"
const STRUCK_DODGE: StringName = &"struck_dodge"

## 挨敌人一下时有几成几率从他自己的召唤技能里召出**一个**（〔共同修行〕「受攻击时 15% 几率出一个影分身」）。
## 冷却复用 [constant STRUCK_CD]。
const STRUCK_SUMMON: StringName = &"struck_summon"

## 开波就当血量已经掉过线，挂上他的血量阈值效果（〔共同修行〕「尾兽外衣开局即可开启」）。量写 1。
const OPEN_LOW_HP: StringName = &"open_low_hp"

## 「不死」效果（[constant PBBuffRules.UNDYING]）到期那一刻，还活着就回复最大生命的几成
## （〔不死二人组〕「死司凭血持续时间结束后能够恢复 20% 的生命值」）。
const UNDYING_END_HEAL: StringName = &"undying_end_heal"

## 每秒回复最大生命的几成（原版「每秒恢复 2% 的生命值」）。按 tick 均摊，死人不回。
const REGEN_MAX: StringName = &"regen_max"

## 挨某一系敌人攻击时伤害多几成（负数 = 少几成）。−0.55 = 「降低 55% 的风属性伤害」，2.0 = 「额外提升 200%」。
##
## **没有仙那一格**：敌人的攻击属性只在五系 + 物理里轮转（[method PBWaveRules.element_of]），
## 配了仙也没有一下伤害会去查它 —— 配了不生效。
const FIRE_TAKEN: StringName = &"fire_taken"
const WIND_TAKEN: StringName = &"wind_taken"
const THUNDER_TAKEN: StringName = &"thunder_taken"
const EARTH_TAKEN: StringName = &"earth_taken"
const WATER_TAKEN: StringName = &"water_taken"
const PHYSICAL_TAKEN: StringName = &"physical_taken"

## 闪避成功时反打那个敌人一下，量是自己一发普攻的几成（蛙组手）。
const DODGE_COUNTER: StringName = &"dodge_counter"

## 挨近战攻击时伤害多几成，负数 = 少几成（针地藏「永久降低近战普攻伤害」）。
const MELEE_TAKEN: StringName = &"melee_taken"

## 只反弹近战攻击的那一份（针地藏「将所受近战攻击伤害反弹给攻击方」），和 `reflect` 相加。
const MELEE_REFLECT: StringName = &"melee_reflect"

## 量写 1：受击效果（`on_struck`）只认远程攻击（雷梨热刀「在受远程攻击时」）。取大。
const STRUCK_RANGED: StringName = &"struck_ranged"

## 量写 1：受击效果触发时跳到打他的那个敌人身前（雷梨热刀「突袭跳跃到目标身前」）。取大。
const STRUCK_LEAP: StringName = &"struck_leap"

## 普攻子弹打中目标后接着往前穿多远，原版码数（纸手里剑「穿透距离：500」）。取大。只对放子弹的人有意义。
const PIERCE: StringName = &"pierce"

## 普攻无视目标几成护甲（〔艺术二人组〕蝎「获得 60% 的护甲穿透」= 0.6）。封在 0~1。
const ARMOR_PEN: StringName = &"armor_pen"

## 忍术无视目标几成忍术抗性。封在 0~1。
const NINJUTSU_PEN: StringName = &"ninjutsu_pen"

## 忍术伤害多几成（原版装备「忍术伤害 +25%」）。作用于技能、忍术普攻；持续伤害不吃（挂上去时没有出手的人）。
const NINJUTSU_BONUS: StringName = &"ninjutsu_bonus"

## 忍术暴击率（万花筒写轮眼「+15% 的忍术暴击率」）。和普攻那一份（`crit_chance`）是两个数。
const NINJUTSU_CRIT_CHANCE: StringName = &"ninjutsu_crit_chance"

## 忍术暴击倍数的加数（原版装备「忍术暴击倍数 +1.0」）。中性 0.0，基础倍数见 [constant PBCritRules.NINJUTSU_CRIT_BASE]。
const NINJUTSU_CRIT_DAMAGE: StringName = &"ninjutsu_crit_damage"

## 量写 1：普攻的伤害类型从体术改成忍术（万花筒写轮眼「普攻变为忍术伤害」）。取大。
const ATTACK_NINJUTSU: StringName = &"attack_ninjutsu"

## 上面六个键各管哪一系。
const TAKEN_ELEMENTS: Dictionary = {
	FIRE_TAKEN: PBElement.Type.FIRE,
	WIND_TAKEN: PBElement.Type.WIND,
	THUNDER_TAKEN: PBElement.Type.THUNDER,
	EARTH_TAKEN: PBElement.Type.EARTH,
	WATER_TAKEN: PBElement.Type.WATER,
	PHYSICAL_TAKEN: PBElement.Type.PHYSICAL,
}

## 认得的全部键。见本类顶上「词汇表里的键 = 已经接上读点的键」。
const STACK_HARM_BONUS: StringName = &"stack_harm_bonus"
const STACK_DEFENCE: StringName = &"stack_defence"

const ALL: Array[StringName] = [
	STACK_HARM_BONUS,
	STACK_DEFENCE,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	CRIT_ON_HIT,
	SPLASH,
	SPLASH_RADIUS,
	HEAVY_HIT,
	REVIVE,
	DODGE,
	BITE_CURRENT,
	BITE_LOST,
	REFLECT,
	ALL_DAMAGE_BONUS,
	TAIJUTSU_BONUS,
	NINJUTSU_RESIST,
	DAMAGE_BONUS,
	MOVE_SPEED_BONUS,
	RANGED_RANGE,
	LOW_HP,
	DRAIN_CUT,
	LIFESTEAL,
	DODGE_HEAL,
	STRUCK_CD,
	HEAL_POWER,
	STRUCK_AURA,
	STRUCK_BOOST,
	STRUCK_STRENGTH_BONUS,
	STRUCK_DODGE,
	STRUCK_SUMMON,
	OPEN_LOW_HP,
	UNDYING_END_HEAL,
	REGEN_MAX,
	FIRE_TAKEN,
	WIND_TAKEN,
	THUNDER_TAKEN,
	EARTH_TAKEN,
	WATER_TAKEN,
	PHYSICAL_TAKEN,
	DODGE_COUNTER,
	MELEE_TAKEN,
	MELEE_REFLECT,
	STRUCK_RANGED,
	STRUCK_LEAP,
	PIERCE,
	ARMOR_PEN,
	NINJUTSU_PEN,
	NINJUTSU_BONUS,
	NINJUTSU_CRIT_CHANCE,
	NINJUTSU_CRIT_DAMAGE,
	ATTACK_NINJUTSU,
]


## 这一下闪掉了吗。
##
## **[member PBAttacker.dodge] 为 0 时一次骰子都不掷**（同 [method PBCritRules.strike]）：
## 掷了就算没闪也拨动了那条流，对拍退化路径靠「该掷几次就掷几次」。
##
## [param rng] 为 null 时（批量扫描、探测）恒不闪避且不掷骰。
## 常驻那一份加上效果袋里临时的那一份（[constant PBBuffRules.DODGE]），两者都是 0 才不掷。
static func dodges(attacker: PBAttacker, rng: RandomNumberGenerator, at_tick: int) -> bool:
	if attacker == null or rng == null:
		return false
	var chance: float = attacker.dodge + attacker.buffs.amount(PBBuffRules.DODGE, at_tick)
	if chance <= 0.0:
		return false
	return rng.randf() < chance


## 挨 [param element] 系的一下时伤害乘几（[constant TAKEN_ELEMENTS]）。没配就是 1.0，下限 0（加减伤不会变成回血）。
static func taken_scale(attacker: PBAttacker, element: PBElement.Type) -> float:
	return maxf(1.0 + float(attacker.taken_by_element.get(element, 0.0)), 0.0)


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 把一个常驻效果按给定的量装到这个人身上。返回 false 表示这个键不认得。
##
## **一律是 `+=` 不是 `=`。** 同一个人可以既是某组羁绊的载体、又自带一个被动，
## 而「后装的那一份把先装的覆盖掉」不报错 —— 屏幕上照样有溅射，只是少了一份。
##
## **例外取大**：[constant SPLASH_RADIUS]、[constant LOW_HP]、[constant STRUCK_CD]、
## [constant STRUCK_AURA]、[constant PIERCE] —— 距离、门槛、冷却都不是一份量；
## 还有几个开关（[constant OPEN_LOW_HP]、[constant STRUCK_RANGED]、[constant STRUCK_LEAP]），量写 1。
## 两个来源各给 275 码加起来成了 550 码；75% 加 90% 成了 165%，开波第一下就触发。
## 羁绊把某个人自带的 75% 改成 90%，靠的正是取大。
##
## [param amount] 不做范围检查：负数是合法的（原版有「降低自身暴击率」这种
## 代价型被动），而拦在这里等于把设计决定写死在规则层。
static func grant(attacker: PBAttacker, key: StringName, amount: float) -> bool:
	if attacker == null:
		return false
	if TAKEN_ELEMENTS.has(key):
		var element: int = TAKEN_ELEMENTS[key]
		attacker.taken_by_element[element] = (
			float(attacker.taken_by_element.get(element, 0.0)) + amount
		)
		return true
	match key:
		STACK_HARM_BONUS:
			attacker.stack_harm_bonus += amount
		STACK_DEFENCE:
			attacker.stack_defence += amount
		CRIT_CHANCE:
			attacker.crit_chance += amount
		CRIT_DAMAGE:
			attacker.crit_bonus += amount
		CRIT_ON_HIT:
			attacker.crit_on_hit += amount
		SPLASH:
			attacker.splash_damage += amount
		SPLASH_RADIUS:
			attacker.splash_radius = maxf(attacker.splash_radius, amount)
		HEAVY_HIT:
			attacker.heavy_bonus += amount
		REVIVE:
			attacker.revives_max += int(round(amount))
		DODGE:
			attacker.dodge += amount
		BITE_CURRENT:
			attacker.bite_current += amount
		BITE_LOST:
			attacker.bite_lost += amount
		REFLECT:
			attacker.reflect += amount
		ALL_DAMAGE_BONUS:
			attacker.all_damage_bonus += amount
		TAIJUTSU_BONUS:
			attacker.taijutsu_bonus += amount
		NINJUTSU_RESIST:
			attacker.ninjutsu_resist += amount
		DAMAGE_BONUS:
			attacker.damage_bonus += amount
		MOVE_SPEED_BONUS:
			attacker.move_speed_bonus += amount
		RANGED_RANGE:
			attacker.ranged_range = maxf(attacker.ranged_range, amount)
		LOW_HP:
			attacker.low_hp_at = maxf(attacker.low_hp_at, amount)
		DRAIN_CUT:
			attacker.drain_cut += amount
		LIFESTEAL:
			attacker.lifesteal += amount
		DODGE_HEAL:
			attacker.dodge_heal += amount
		STRUCK_CD:
			attacker.struck_cd = maxf(attacker.struck_cd, amount)
		HEAL_POWER:
			attacker.heal_power += amount
		STRUCK_AURA:
			attacker.struck_aura = maxf(attacker.struck_aura, amount)
		STRUCK_BOOST:
			attacker.struck_boost += amount
		STRUCK_STRENGTH_BONUS:
			attacker.struck_strength_bonus += amount
		STRUCK_DODGE:
			attacker.struck_dodge += amount
		STRUCK_SUMMON:
			attacker.struck_summon += amount
		OPEN_LOW_HP:
			attacker.open_low_hp = maxf(attacker.open_low_hp, amount)
		UNDYING_END_HEAL:
			attacker.undying_end_heal += amount
		REGEN_MAX:
			attacker.regen_max += amount
		DODGE_COUNTER:
			attacker.dodge_counter += amount
		MELEE_TAKEN:
			attacker.melee_taken += amount
		MELEE_REFLECT:
			attacker.melee_reflect += amount
		STRUCK_RANGED:
			attacker.struck_ranged = maxf(attacker.struck_ranged, amount)
		STRUCK_LEAP:
			attacker.struck_leap = maxf(attacker.struck_leap, amount)
		PIERCE:
			attacker.pierce = maxf(attacker.pierce, amount)
		ARMOR_PEN:
			attacker.armor_pen += amount
		NINJUTSU_PEN:
			attacker.ninjutsu_pen += amount
		NINJUTSU_BONUS:
			attacker.ninjutsu_bonus += amount
		NINJUTSU_CRIT_CHANCE:
			attacker.ninjutsu_crit_chance += amount
		NINJUTSU_CRIT_DAMAGE:
			attacker.ninjutsu_crit_bonus += amount
		ATTACK_NINJUTSU:
			attacker.attack_ninjutsu = maxf(attacker.attack_ninjutsu, amount)
		_:
			return false
	return true


## 把一整份被动表（键 → 量）装到这个人身上。返回装上了几个。
##
## **不认得的键在这里不报错，只是不装** —— 拦它的地方是生成器
## （`src/tools/make_roster.gd` 读表那一刻，退出码 1）。
## 规则层再拦一次的话，同一件事就有了两把尺子，
## 而战斗中途 `push_error` 也没有人看得见。
static func grant_all(attacker: PBAttacker, passives: Dictionary) -> int:
	var done: int = 0
	for key: StringName in passives:
		if grant(attacker, key, float(passives[key])):
			done += 1
	return done


## 把几份来源一次性装到这个人身上，**装完当场折算**。
##
## [param sources] 按顺序是角色自带 / 羁绊 / 尾兽光环 / 装备，在字段上 `+=` 汇合。
## 返回一共装上了几个。
##
## **折算必须在这里面**：率型键是累加器，要乘进真正的字段才生效。
## 留给调用方的话，「忘了折」的表现是那一份配了不生效。收成一个入口之后，
## 调用方拿不到「装了但没折」的中间状态 —— 一处判，调用方不判。
##
## **先全加完再折一次**：两份 +50% 该是 +100%，边加边折就成了连乘。
##
## 折算在 [method PBAttacker.revive] 之前：开波那一句把 `hp` 填到 `max_hp`，
## 这里不要顺手改 `hp`，否则两处成了两把尺子。
static func equip(attacker: PBAttacker, sources: Array[Dictionary]) -> int:
	if attacker == null:
		return 0
	var done: int = 0
	for one: Dictionary in sources:
		done += grant_all(attacker, one)
	_settle(attacker)
	return done


## 把率型那几个累加器折进它们真正的字段。只由 [method equip] 调。
##
## **下限掐在 −1.0**（同 [method PBAttacker.strike_for] 里那句 `maxf`）：
## 原版有代价型被动，而 −1.5 会算出负的血上限，
## 那时 [method PBAttacker.revive] 会让人一站起来就是死的，**而它不报错**。
static func _settle(attacker: PBAttacker) -> void:
	if attacker.move_speed_bonus != 0.0:
		attacker.move_speed *= 1.0 + maxf(attacker.move_speed_bonus, -1.0)
