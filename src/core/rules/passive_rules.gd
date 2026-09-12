class_name PBPassiveRules
extends RefCounted
## 一个**常驻效果**怎么装到一个人身上。全部 static，无状态，零引擎依赖。
##
## 和 [PBBuffRules]（一份会过期的效果）对着看：那一层管的是「这一波暂时怎么样」，
## 这一层管的是「他站在场上就一直是这样」——
## 后者不进效果袋，直接乘死在 [PBAttacker] 的字段上。
##
## ## 为什么它从羁绊里抽出来
##
## M10-d 的 `Landing.CARRIER` 档（重生 / 溅射 / 打高血量多打一笔 / 命中后提暴击）
## 当时只有羁绊一个来源，所以那套映射写在 [PBBondFunctionRules] 里。
## M12-c2 来了第二个来源：**角色自带的被动**（原版 56 张卡里有 10 个是
## 「攻击时 X% 触发 Y」这种没有施法、没有冷却、没有蓝的东西 ——
## 玩家按不出来，它不是技能）。
##
## 两处各写一份映射的话，「羁绊给的溅射」和「角色自带的溅射」迟早在
## **叠加方式**上分叉（一个 `=` 一个 `+=` 就够了），
## 而分叉的那一侧静默生效：屏幕上照样溅射，只是量不对。
##
## **键认不认得也只有一处**（[method is_known]）—— 同 [method PBBuffRules.validate]
## 那条：两处各判各的话，「这个键认不认」迟早分叉。
##
## ## 词汇表里的键 = 已经接上读点的键
##
## 同 [PBBuffRules.ALL] 顶上那条（M7-a）。拼对了却没人读的键比拼错更难查：
## 数据、界面、日志全部正常，只有伤害数字不对。所以这里**一个键都不预留**,
## 要加就连着它的读点一起加。下面每一行的读点都已经在跑：
##
## | 键 | 落在哪个字段 | 谁读它 |
## |---|---|---|
## | `crit_chance` | [member PBAttacker.crit_chance] | [method PBCritRules.chance_of] |
## | `crit_damage` | [member PBAttacker.crit_bonus] | [method PBCritRules.multiplier_of] |
## | `crit_on_hit` | [member PBAttacker.crit_on_hit] | [method PBStrikeRules.land] |
## | `splash` | [member PBAttacker.splash_damage] | [method PBStrikeRules.land] |
## | `heavy_hit` | [member PBAttacker.heavy_bonus] | [method PBStrikeRules.land] |
## | `revive` | [member PBAttacker.revives_max] | [method PBAttacker.take_damage] |
## | `dodge` | [member PBAttacker.dodge] | [method dodges] |
## | `bite_current` | [member PBAttacker.bite_current] | [method PBStrikeRules.land] |
## | `bite_lost` | [member PBAttacker.bite_lost] | [method PBStrikeRules.land] |
## | `reflect` | [member PBAttacker.reflect] | [method PBStrikeRules.hurt_ally] |
## | `damage_bonus` | [member PBAttacker.damage_bonus] | [method PBAttacker.strike_for] |
## | `defence` | [member PBAttacker.defence] | [method PBStatRules.strike_damage] |
## | `hp_bonus` | [member PBAttacker.hp_bonus] | [method equip] 折进 `max_hp` |
## | `move_speed_bonus` | [member PBAttacker.move_speed_bonus] | [method equip] 折进 `move_speed` |
## | `attack_speed` | [member PBAttacker.attack_speed_bonus] | [method PBAttacker.prime] |
##
## ## 裸名 = 量型，`_bonus` 后缀 = 率型
##
## 原版自己两种都用：防御一律写点数（羁绊那边是「全队友军提升 30 点防御」，
## 尾兽那边是「提升 [4x等级] 点防御」），而生命与移速一律写百分比
## （「提升 [1.5x等级]% 最大生命值」「提升 [10x等级]% 的移动速度」）。
##
## **照抄点数是对的，因为刻度是同一把**：M12-b 把换算系数换成了
## `war3mapMisc.txt` 那一套（护甲 `4 + 敏捷×0.22`、生命 `100 + 力量×80`），
## 所以 [member PBAttacker.defence] 本来就在原版的刻度上。
## 发明一个「点数 → 成数」的换算反而会在数值回归改一次基数之后整个失效，
## **而且不报错**（同 [constant PBStrikeRules.BITE_CAP] 顶上那条）。
##
## 统一成一种的话，读表的人得记住哪个字段是哪种，**而记错不报错** ——
## 同 [PBSkillPatchRules] 那条「每个键自己说清楚是加是乘是设」。
##
## ## 忍术抗性没有进来，那是有意的
##
## 原版有一大批「提升 N% 忍术抗性」（一只尾兽、好几组羁绊都带着它），
## 而它要求**敌人的伤害分类型** —— 今天敌人只有一种伤害，
## 加一个抗性字段之后没有任何一条伤害会去查它。
## 那正是「配了不生效」，比「配不了」难查得多（同 M7-a 那条
## 「词汇表里的键 = 已经接上读点的键」）。**降级记在这里。**
##
## ## 「X% 几率打出更多伤害」就是暴击，不是第七个键
##
## 原版那 10 个被动里有 4 个是这个形状（写轮眼 20% 两倍、削灭斩 20% 额外伤害、
## 风切 [5+等级x4]% 额外伤害、轮回眼 15% 两倍）。它们**用前两个键就写得出来** ——
## 另开一个 `proc_chance` 的话，屏幕上会有两套各自掷骰的暴击，
## 而 M10-c 那条「一个掷点」（[PBCritRules] 顶上）正是为了防这个：
## 掷两次就等于同一条 RNG 流被拨动两次，
## 而 [method PBAttacker.whole_field] 那条与解析式排队模型逐位对拍的
## 退化路径靠的就是「该掷几次就掷几次」。

## 暴击率（常驻那一份）。
const CRIT_CHANCE: StringName = &"crit_chance"

## 暴击倍率的加数。**中性值是 0.0 不是 1.0** —— 见 [member PBAttacker.crit_bonus]。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 命中之后那一小段时间里额外的暴击率。
const CRIT_ON_HIT: StringName = &"crit_on_hit"

## 普攻附带的范围伤害，值是主伤害的几成。
const SPLASH: StringName = &"splash"

## 对血还很多的敌人追加的那一笔，值是主伤害的几成。
const HEAVY_HIT: StringName = &"heavy_hit"

## 一波能重生几次。**取整** —— 半次重生没有意义。
const REVIVE: StringName = &"revive"

## 挨一下普攻有多大机会一点血都不掉（M12-c2）。
const DODGE: StringName = &"dodge"

## 打出要害那一下额外按目标**当前**生命的几成再打一笔（M12-c2）。
const BITE_CURRENT: StringName = &"bite_current"

## 同 [constant BITE_CURRENT]，但按目标**已经损失**的生命算。
const BITE_LOST: StringName = &"bite_lost"

## 挨一下就把这一下伤害的几成还给打他的那个敌人（M12-c2）。
const REFLECT: StringName = &"reflect"

## 常驻增伤：普攻多打几成（M12-e）。
const DAMAGE_BONUS: StringName = &"damage_bonus"

## 常驻加防，**点数**（M12-e2）。见本类顶上「裸名 = 量型」。
const DEFENCE: StringName = &"defence"

## 最大生命多几成（M12-e2）。中性 0.0，折算在 [method equip] 末尾。
const HP_BONUS: StringName = &"hp_bonus"

## 移动速度多几成（M12-e2）。中性 0.0，折算在 [method equip] 末尾。
const MOVE_SPEED_BONUS: StringName = &"move_speed_bonus"

## 出手多快几成（M12-c4）。中性 0.0。
##
## **键名是裸的 `attack_speed`，而它落在 `attack_speed_bonus` 上** ——
## 表里写的是原版那句「提升 [4x等级]% 的攻击速度」，而
## [member PBAttacker.attack_speed] 那个字段是**基础攻速**，
## 直接往上加等于没加（见 [member PBAttacker.attack_speed_bonus]）。
##
## **它不在 [method _settle] 里折算**，唯一的消费方是
## [method PBAttacker.prime]，而那一句在建人之后才跑。
const ATTACK_SPEED: StringName = &"attack_speed"

## 认得的全部键。见本类顶上「词汇表里的键 = 已经接上读点的键」。
const ALL: Array[StringName] = [
	CRIT_CHANCE,
	CRIT_DAMAGE,
	CRIT_ON_HIT,
	SPLASH,
	HEAVY_HIT,
	REVIVE,
	DODGE,
	BITE_CURRENT,
	BITE_LOST,
	REFLECT,
	DAMAGE_BONUS,
	DEFENCE,
	HP_BONUS,
	MOVE_SPEED_BONUS,
	ATTACK_SPEED,
]


## 这一下闪掉了吗（M12-c2）。
##
## **它是一条规则，不是一份状态**，所以住在这里不住在 [PBAttacker] 上
## —— 同 M7-e 那次把 `cast_at` 放进 [PBSkillRules]（那个类贴着
## gdlint 的 20 个公开方法上限，而上限那条「超了不是错，是该搬了的信号」
## 这两次指的地方都是对的）。
##
## **[member PBAttacker.dodge] 为 0 时一次骰子都不掷** ——
## 同 [method PBCritRules.strike] 顶上那条：掷了就算没闪也已经拨动了那条流，
## 而 [method PBAttacker.whole_field] 那条与 [PBCombatRules] 解析式排队模型
## 逐位对拍的退化路径靠的就是「该掷几次就掷几次」。
##
## [param rng] 为 null 时（批量扫描、探测、老的构造点）恒不闪避且不掷骰。
static func dodges(attacker: PBAttacker, rng: RandomNumberGenerator) -> bool:
	if attacker == null or rng == null or attacker.dodge <= 0.0:
		return false
	return rng.randf() < attacker.dodge


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 把一个常驻效果按给定的量装到这个人身上。返回 false 表示这个键不认得。
##
## **一律是 `+=` 不是 `=`。** 同一个人可以既是某组羁绊的载体、又自带一个被动，
## 而「后装的那一份把先装的覆盖掉」不报错 —— 屏幕上照样有溅射，只是少了一份。
##
## [param amount] 不做范围检查：负数是合法的（原版有「降低自身暴击率」这种
## 代价型被动），而拦在这里等于把设计决定写死在规则层。
static func grant(attacker: PBAttacker, key: StringName, amount: float) -> bool:
	if attacker == null:
		return false
	match key:
		CRIT_CHANCE:
			attacker.crit_chance += amount
		CRIT_DAMAGE:
			attacker.crit_bonus += amount
		CRIT_ON_HIT:
			attacker.crit_on_hit += amount
		SPLASH:
			attacker.splash_damage += amount
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
		DAMAGE_BONUS:
			attacker.damage_bonus += amount
		DEFENCE:
			attacker.defence += amount
		HP_BONUS:
			attacker.hp_bonus += amount
		MOVE_SPEED_BONUS:
			attacker.move_speed_bonus += amount
		ATTACK_SPEED:
			attacker.attack_speed_bonus += amount
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


## 把三份来源一次性装到这个人身上，**装完当场折算**（M12-e2）。
##
## [param sources] 按顺序是角色自带 / 羁绊 / 尾兽光环（[PBCombatRules] 的建人
## 循环里那三行），量各自给、在字段上 `+=` 汇合。返回一共装上了几个。
##
## ## 为什么折算必须在这个函数里面，而不是让调用方补一句
##
## 率型那两个键（[constant HP_BONUS] / [constant MOVE_SPEED_BONUS]）
## 是**累加器**：`grant` 只往 [member PBAttacker.hp_bonus] 上加，
## 真正生效要把它乘进 [member PBAttacker.max_hp]。
## 把这一步留给调用方的话，「忘了折」的表现是**那一组羁绊配了不生效** ——
## 数据、界面、日志全部正常，只有血条不对。
##
## 收成一个入口之后忘不掉：调用方拿不到「装了但没折」的中间状态。
## 同 [method PBStrikeRules.land] / [method PBStrikeRules.hurt_ally]
## 那两个漏斗 —— **一处判，调用方不判**。
##
## ## 为什么是「先全加完，再折一次」
##
## 两组各给 +50% 生命该是 **+100%**（相加），不是 `1.5 × 1.5 = 2.25`（连乘）。
## 边加边折就是连乘，而那不是人会预期的叠加方式 ——
## 同 [member PBAttacker.damage_bonus] 顶上那条。
##
## ## 折算排在 [method PBAttacker.revive] 之前，所以血条跟得上
##
## [PBBattleSim] 开波对每个人调一次 `revive()`，那一句把 `hp` 填到
## `max_hp`。建人这一刻抬高上限，开波那一刻自然就是满的 ——
## 在这里顺手改 `hp` 反而会和 `revive()` 成为两把尺子。
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
	if attacker.hp_bonus != 0.0:
		attacker.max_hp *= 1.0 + maxf(attacker.hp_bonus, -1.0)
	if attacker.move_speed_bonus != 0.0:
		attacker.move_speed *= 1.0 + maxf(attacker.move_speed_bonus, -1.0)
