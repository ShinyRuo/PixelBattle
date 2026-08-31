class_name PBGameData
extends RefCounted
## `data/` 下全部数据表的**唯一装载入口**。M2-b2。
##
## ## 为什么要这一层
##
## M2-a2 只有角色表时，游戏入口写的是 `PBCharacterLoader.config()`。
## M2-b2 加了羁绊表，如果继续照那个写法，四个入口
## （主场景、批量模拟、单波节奏、压力曲线）就要各自记住「装哪几张表」——
## **而漏装一张不会报错**，只会静默退回合成表，跑出来的数值和真游戏对不上。
##
## M3 又加了装备表（M3-c）和尾兽表（M3-d）。每加一张表就去四个地方各补一行，
## 漏掉一处的概率随表数增长，且那种失败没有任何声响。
## 所以入口收成一个：**新表只在本文件里接一次。**
##
## `test_battle_view.gd` 里有一条断言守着主场景确实走了这里。


## 新建一份装好全部真数据的配置。**游戏入口用这个，别直接 `PBSimConfig.new()`。**
static func config() -> PBSimConfig:
	return install(PBSimConfig.new())


## 把全部真数据表装进一份配置。返回同一个 [param cfg]，方便串写。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	PBCharacterLoader.install(cfg)
	PBBondLoader.install(cfg)
	PBEquipLoader.install(cfg)
	PBBeastLoader.install(cfg)
	return cfg
