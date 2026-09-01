# data/actors —— 战场形象

这个目录装 `PBActorSkin` 的 `.tres`：**战场上那个会动的小人**，
不是卡面头像（那一套走 `PBCharacter.icon_key`，还没开工）。

**现在它是空的，这是正常状态。** `assets/` 一张图都没有，
所以每个角色都查不到皮，一律退回 `PBWhiteModel` 现画的白模帧。
链路本身是通的 —— 往这里放一份 `.tres`，那个角色当场换掉，
`src/view/` 一行不用改。

## 怎么加一份

1. 按 [`Docs/素材规格_战场形象.md`](../../Docs/素材规格_战场形象.md) 切图
2. 在 Godot 编辑器里新建一份 `SpriteFrames`，建 `idle` / `run` / `attack` 三段
3. 新建一份 `PBActorSkin` 资源存成 `<key>.tres`，把 `SpriteFrames` 填进 `frames`
4. `key` 填成和文件名一样（留空的话按文件名兜底）
5. 角色那一边填 `PBCharacter.actor_key`；敌人那一边的键写死在
   `PBEnemyPool.SKIN_KEYS` 里（`enemy_fire`、`enemy_wind`……）

**别忘了 `foot_offset` 和 `source_faces`。** 这两个填错都不报错：
脚底错一格会让这个人和别人的前后关系错一档，朝向错了他会背对着敌人打。
