# PixelBattle — 项目说明书

Godot 4.7.2 / GDScript / 2D。开发使用 Codex / Claude Code + VSCode，Godot 编辑器只在需要
所见即所得的时候开（摆关卡、调 Input Map、看 GUT 面板）。

这是各开发代理共用的项目约定；Codex 自动入口见 [AGENTS.md](AGENTS.md)。

---

## 这是什么游戏

魔兽争霸3 RPG 地图《忍法战场》的复刻版。**2D 像素风 · 横屏 · 无限流 PVE 塔防自走棋**，
目标 PC（Steam）+ 手机双端。

一句话玩法：抽忍者 → 摆阵型 → 自动战斗 + 手动放技能 → 打无限波次，看能推多远。
核心策略来自**属性克制**（五系环 + 物理 + 仙，原版五档矩阵）配上**敌人属性按固定顺序轮转**
（火雷水土风 + 物理，6 波一周期），逼玩家凑齐五系而不是堆一套最优解。

**原版数据的唯一权威来源**是 [Docs/原版数据_忍法战场v1.5.80.md](Docs/原版数据_忍法战场v1.5.80.md)
（从 `.w3x` 地图文件解包，机器生成，别手改）。项目方针是「尽量复刻」。

**当前进度与待办看 [Docs/开发路线图.md](Docs/开发路线图.md)**：M-1 ~ M10 已完成，
M12「向原版对齐」进行中，数值回归排在 M12 之后。每一步的完整经过在 git 历史里。

---

## 架构铁律

破坏任何一条都要付重写代价：

1. **`src/core/` 零引擎依赖** —— 不 `extends Node`（用 `RefCounted`）、不 `get_node()`、
   不访问 `SceneTree`、不读 `delta`、不调全局 `randi()`。守住它才有确定性、可单测、
   可 headless 批量模拟、可换渲染层。
2. **定帧 20 tick/s**，倍速只改每渲染帧步进的 tick 数。
   **绝不用 `Engine.time_scale` 或直接乘 `delta`** —— 浮点漂移会让存档回滚和每日种子失效。
3. **三条独立 RNG 流**（gacha / quest / combat），各持有自己的 `RandomNumberGenerator`，
   `state` 存进档。全局 `randi()` / `randf()` 一律禁用。
4. **`element` 挂在伤害事件上**，不挂在单位上（同一角色的不同技能可以是不同属性）。
5. **代码里不出现角色名字符串**（注释也算，测试会扫整个 `src/`），一律走 `id` + `name_key` 查表。
   角色数据全在 `data/` 的表里，换皮 = 改表，`src/` 一行不动。**短 id 不可用**
   （`rin`、`ay`、`pain` 都是常见单词的子串，会被扫描拦下）。
6. **`COUNT_CAP`（同屏单位上限）不按平台分档**，双端跑同一份模拟，
   性能差异只在渲染层吸收。

---

## 改代码时的几条规矩

- **一处判，调用方不判。** 一件事有好几个调用点时（挨打、命中、易伤、晕眩……），判据收进被调用的那一处，
  再用一条**扫描式断言**钉住调用方不许自己判 —— 漏掉的那条路径在测试里根本走不到。
- **配了不生效比配不了难查。** 词汇表里的键 = 已经接上读点的键；生成器、加载器遇到不认识的键直接报错。
- **断言写规则，不写当下的数据状态。** 「恰好 N 组」「每个角色都有头像」这类断言会在内容变多时变红，而红的不是错误。
- **局部不变量写在代码的类注释里，跨文件的结论写在路线图「各系统的关键结论」里。** 注释写「为什么现在这样、改了会踩什么坑」，
  不写「M 几之前这里是什么」—— 经过在 git 历史里。
- **现阶段只测功能 bug，不测数值**（玩家定的）。改了配平的地方量一下位移、记进路线图的数值回归一节，不去调数。
- **数据由表生成**：名册、羁绊、技能、效果改 `data/*.tsv` 再跑 `src/tools/make_*.gd`，别手改生成出来的 `.tres`。
- **原始素材 `aires/` 不进版本控制，成品帧 `assets/actors/` 与形象资源 `data/actors/` 可以入库**（见 `.gitignore`）。
  本机可能还有未提交素材，提交时**逐个点名暂存**，不要 `git add -A`；缺素材时白模兜底必须一直可用。
- **gdlint 的上限是拆分信号**：单文件 1000 行、单类 20 个公开方法、单函数 6 个 return、每行 100 字符。超了就按职责拆（规则类、测试文件都拆过）。

---

## 环境速查

| 项 | 值 |
|---|---|
| 引擎（GUI） | `F:\Godot_PJ\_engine\4.7.2\godot.exe` |
| 引擎（命令行） | `F:\Godot_PJ\_engine\4.7.2\godot_console.exe` |
| 项目根 | `F:\Godot_PJ\PixelBattle` |
| 测试框架 | GUT 9.7.1（`addons/gut`） |
| 格式化 / 静态检查 | `gdformat` / `gdlint`（gdtoolkit 4.5.0） |

**Windows 上必须用 `godot_console.exe` 跑命令行。** `godot.exe` 是 GUI 子系统程序，
stdout 不回传给调用它的终端 —— 用它跑 `--headless` 会看到一片空白，误以为没输出。

---

## 自检契约（最重要的一条）

**任何代码或场景改动之后，跑：**

```powershell
.\scripts\check.ps1
```

默认运行五个阶段，退出码 0 才算改完；显式使用跳过开关只代表部分检查通过：

1. `--import` — 导入资源、解析全部脚本（抓语法错误、断掉的资源引用）
2. **core 纯度** — grep `src/core/`，出现 `get_node`、全局 `randi(`、`delta`、
   `extends Node` 就报错。守铁律 1，见 §14
3. `gdlint` — 静态检查（命名、行长、代码异味、成员声明顺序）
4. `--quit-after 120` — 真跑主场景 120 帧（抓「解析得过但一 `_ready` 就炸」）
5. GUT — 单元测试

默认检查缺少 gdlint 或 GUT 时直接失败；`-Fix` 还必须有 gdformat。
`-SkipLint` / `-SkipTests` 必须在汇总里显示未验证项，不能报告“全部通过”。
GUT 返回 0 但没有实际执行测试也算失败。自检脚本自身的契约用
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test_check.ps1` 验证。

> **阶段 5 会因为「测试静默消失」而失败，这是有意的。** 一个测试文件解析失败时
> GUT 只打一行 WARNING 就跳过整个文件，然后**照样返回 0** —— 用例数悄悄少掉一截，
> 而自检报告「全部通过」。所以那一阶段配了 `FailPatterns` 把这种情况拦死。

### 测试分两档

默认跑快档（几分钟，数量以本次报告为准）。`-Deep` 连慢档一起跑。

慢档只有 `tests/test_balance_scan.gd` 一个文件，装的是**靠整局扫描才能验的配平结论**
（装备定价、经济位不是陷阱也不支配、GROWTH 单调）。`rational` 流派每花一笔钱就重估一遍全部候选项，
所以它很慢（最近一次 340 秒）—— **跑 `-Deep` 要等十分钟起步。**

**判据是「贵 _且_ 结论型」，不是「贵」。** 自洽性测试（确定性、记账守恒、
拆分路径对拍）再贵也留在快档 —— 那些是改代码就会红的。慢档那几条是**调参**才会红的，
而调参正是眼下高频发生的事。

**什么时候必须 `-Deep`**：改了 `PBSimConfig` 的任何数值、改了 `PBValuation` 的估值口径、
动了角色表的属性/稀有度分布、里程碑验收。日常改代码不用。

跳过走的是 GUT 的 `should_skip_script()`，**不是「不扫描那个目录」**：
GUT 会先实例化脚本再判跳过，所以慢档文件的解析错误在快档照样暴露，
报告里也会打出 `[Script skipped]` 并计入 risky。挪目录的话那个文件哪天解析不过都没人知道 ——
那正是上面那条 `FailPatterns` 在防的东西。

常用参数：

```powershell
.\scripts\check.ps1 -Fix        # 顺手用 gdformat 格式化
.\scripts\check.ps1 -Deep       # 连慢档（配平扫描）一起跑
.\scripts\check.ps1 -SkipTests  # 只做快速校验
.\scripts\check.ps1 -Full       # 打印每阶段完整输出（默认只在失败时打）
```

默认静默是有意的：成功时刷 200 行导入进度条既没信息量，又会白吃掉上下文窗口。

---

## 目录约定

```
src/core/     模拟与规则（零引擎依赖，见铁律 1）：sim/ 状态与推进、rules/ 纯规则、rng/ 随机流
src/data/     读盘：把 data/ 与 assets/ 装成 core 认识的表
src/view/     渲染层与界面（只读 sim，改的只有玩家指令）
src/tools/    命令行工具、生成器、编辑器插件的逻辑、脚本玩家（strategies/）
src/player/   环境自检用的最小示例（scenes/main.tscn、tests/test_smoke.gd）
scenes/       .tscn 场景
assets/       美术、音频（导入后引擎会在旁边生成 .import 元数据）
tests/        GUT 用例，文件名和方法名都以 test_ 开头
addons/       第三方插件，不改、不 lint
scripts/      开发脚本（PowerShell），不是游戏代码
Docs/         项目文档
```

## 其他文档

**设计**

- [Docs/开发路线图.md](Docs/开发路线图.md) — **先读这份**：当前进度、待办、待决策、**各系统的关键结论**、风险登记
- [Docs/施工策划案.md](Docs/施工策划案.md) — 主规格。每个系统给规则、公式、可调参数、验收标准
- [Docs/技能与BUFF系统.md](Docs/技能与BUFF系统.md) — **M7 的规格，a~h 全部落地**：三层结构、效果词汇表、施法流程、七条已决策
- [Docs/玩法拆解_忍法战场.md](Docs/玩法拆解_忍法战场.md) — 原版考据，理解「为什么这么设计」
- [Docs/原版数据_忍法战场v1.5.80.md](Docs/原版数据_忍法战场v1.5.80.md) — **原版数据的唯一权威来源**，从 `.w3x` 地图文件直接解包出来（机器生成，别手改）：克制矩阵、64 张卡的三围、每张卡的技能原文、45 组羁绊的真实数字、9 只尾兽、装备与合成树、经济与波次公式。§11 逐条列出它与本项目的差异。名册与羁绊由 `data/roster.tsv` / `data/bonds.tsv` 从它转录，别改 `.tres`
- ~~`Docs/(已废弃)忍法战场_忍者&羁绊完整数值文档.MD`~~ — 玩家早期手工整理的考据，M10 的输入。**已作废**，被上面那份取代（它漏了一半羁绊，并且错误地认为原版没有数字）
- [Docs/进度_技能与羁绊.md](Docs/进度_技能与羁绊.md) — **角色技能与羁绊做到哪了**：56 人逐个、40 组逐个、还缺哪些读点（按它在原版羁绊里出现几条排）。**手写的快照，会过期** —— 顶上写着怎么重新量；它自己记着的头号发现就是一份过期的分诊
- [Docs/素材规格_战场形象.md](Docs/素材规格_战场形象.md) — 给画图的人：画布、脚底锚点、朝向、三段动画
- [Docs/AI出图_战场形象.md](Docs/AI出图_战场形象.md) — 三条出图路线（文生图 / 视频转描 / 像素序列帧工具）的中英提示词、抽帧、降采样对齐、以及怎么装进游戏
- [Docs/素材规格_头像.md](Docs/素材规格_头像.md) — **卡面头像那一套**（M9-g）：78×90、一张 6×5 的表、黑色格线、`icon_key`。提示词在 `aires/prompts/portraits_sheet.md`
- [Docs/素材规格_特效.md](Docs/素材规格_特效.md) — **子弹、命中、范围技能与 buff 特效**：黑底发光 / 洋红底实体、屏幕尺寸 ×3、少画帧代码补动、子弹提示词模板、编辑器底栏「战场特效」面板（切图 → 生成子弹资源 → 配给忍者）

**代码**

- [Docs/代码导读.md](Docs/代码导读.md) — `src/` 的分层、数据流、类速查、「想改 X 去哪」
- [Docs/Godot上手笔记.md](Docs/Godot上手笔记.md) — UE→Godot 概念对照、GDScript 速查

**环境**

- [README.md](README.md) — 人看的入口，30 秒上手
- [Docs/环境搭建记录.md](Docs/环境搭建记录.md) — 环境怎么装出来的、选型理由、踩过的坑

改动涉及环境或工具链时，同步更新《环境搭建记录》；发现新的引擎行为坑位，
写进本文件的「已知坑位」并在《上手笔记》补一条。
设计决策变更时更新《施工策划案》，进度与待办变更时更新《开发路线图》。

---

## GDScript 规范

- **Tab 缩进**，不是空格。gdformat 强制，保存时自动跑。
- 变量、函数 `snake_case`；类名、常量按 `.gdlintrc` 里的正则。
- **写类型标注**：`var speed: float = 220.0`、`func move(d: Vector2) -> void:`。
  Godot 会据此走静态类型路径，比 Variant 快，而且错误在编译期就报出来。
- 私有成员以 `_` 开头。
- 测试方法名用**英文** —— 中文函数名 GDScript 本身能跑，但 gdlint 的
  `function-name` 规则不认。中文写在注释和断言消息里。
- 文档注释用 `##`（会进 Godot 内置文档和 VSCode 悬停提示），普通注释用 `#`。
- **所有 `class_name` 一律加 `PB` 前缀**（PixelBattle）：`PBElement`、`PBRunSim`。
  文件名不加，仍是 `element.gd`、`run_sim.gd`。

  理由是硬性的：**GDScript 没有命名空间**，每个 `class_name` 都注册到全局，
  和 `addons/gut`、`addons/godot_mcp` 以及引擎自带的几百个类共用一个名字空间。
  叫 `Element` / `Unit` / `Strategy` 这种名字，撞名只是时间问题，
  而撞名的报错往往指不到真正的位置。

  > 《施工策划案》里的代码样例用的是 `MR` 前缀（`MRCharacter`、`MRElement`），
  > 那是早期遗留，**已统一改为 `PB`**。看到 `MR` 一律按 `PB` 理解。

---

## 场景文件（.tscn）怎么改

`.tscn` / `.tres` 是纯文本，**可以直接编辑**，这是 Godot 相对 UE `.uasset` 最大的优势。
但有规矩：

- **不要手写 `uid="uid://xxx"`。** 新增 `ext_resource` 只写 `path="res://..."`，
  跑一次 `--import` 让引擎自己补 uid。手编的 uid 会和引擎数据库对不上。
- **`.gd.uid` 文件要一起提交。** Godot 4.4+ 给每个脚本生成一个 `.uid` 边车文件，
  漏提交会让别人机器上的场景引用断掉。
- 改完 `.tscn` 一定跑 `check.ps1` —— 手写场景很容易节点类型和属性对不上，
  引擎加载时才报错。
- 场景内的信号连线（`[connection signal=...]`）留在 `.tscn` 里没问题，它是可读文本。
  跨场景 / 动态的连接写在代码里用 `connect()`。

## project.godot 的脾气

**引擎会重写这个文件，而且会做三件事**（跑一次 `--import` 就会发生）：

1. **删掉所有注释。** 别在里面写说明，写了也留不住 —— 要解释配置就写在这份 CLAUDE.md 里。
2. **省略等于默认值的项。** 比如 `window/stretch/aspect="keep"` 写进去也会消失，
   因为它本来就是默认值。这不是丢失，是归一化；看不到某一项不代表它没生效。
3. **自动补插件需要的段。** 启用 Godot MCP 后引擎自己加了 `[autoload] MCPGameBridge`
   和 `[godot_mcp]` 段 —— 别手动删，删了 MCP 就连不上运行中的游戏。

不要手写进去的东西：

- **Input Map（输入动作）**。那段 `Object(InputEventKey, ...)` 序列化格式跨版本会变，
  手写极易写出加载不了的项目。用编辑器 Project Settings > Input Map 加。
- **Autoload 路径**同理，用编辑器加，避免路径拼错。

其余普通键值（窗口尺寸、渲染选项等）可以直接改文本，改完跑 `check.ps1`。

---

## 已知坑位

- **截图工具**：`src/tools/screenshot.gd`（`--wave` / `--seed` / `--press` / `--pick` / `--select` / `--modal` / `--actors`）。
  **要 1080p 的图，`--resolution 1920x1080` 得排在 `--path` 前面**，排后面引擎会以退出码 1 静默失败。
  `capture_battle.gd` **不能加 `--headless`**（没有渲染截出来是一片黑）。
- **`.ps1` 必须存成 UTF-8 with BOM。** PowerShell 5.1 对无 BOM 的 UTF-8 按 GBK 解，
  中文和特殊符号会变乱码并导致语法错误。
- **`.gd` 绝不能带 BOM，规矩和 `.ps1` 正好相反。** GDScript 的解析器不认 BOM，
  报的是 `No terminal matches '﻿' at line 1 col 1` —— 指向第 1 行第 1 列，
  但那一行看起来完全正常，光看报错想不到是编码问题。

  最容易踩的路径是**用 PowerShell 批量改 `.gd`**：
  `Set-Content -Encoding UTF8` 在 PowerShell 5.1 里写的是**带 BOM** 的 UTF-8。
  要写无 BOM 得用 `[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))`。
  体检整个仓库：

  ```powershell
  Get-ChildItem src,tests -Recurse -Filter *.gd | ForEach-Object {
	  $b = [IO.File]::ReadAllBytes($_.FullName)
	  if ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) { $_.Name }
  }
  ```
- **PowerShell 5.1 会把单元素的嵌套数组拍平。** `@( @('旧','新') )` 迭代出来的
  不是那一对字符串，而是**两个字符串本身**。写「批量替换」时这个差别是致命的：

  ```powershell
  # 看着像遍历「旧/新」对，实际 $p 是字符串，$p[0] 是它的第一个字符
  foreach ($p in $pairs) { $t = $t.Replace($p[0], $p[1]) }
  ```

  真实后果：一次注释替换把 `battle_view.gd` 里**每个 `#` 换成了空格**
  （`$p[0]` = `#`，`$p[1]` = 空格），527 行代码的注释标记全部消失。
  语法照样能过 —— 注释变成了缩进对不上的语句才报错，指的位置和病因毫无关系。

  两条规矩：**加逗号强制成数组** `@( ,@('旧','新') )`，或者干脆别用脚本改 `.gd`，
  用编辑器的替换。改完必查：

  ```powershell
  Get-ChildItem src,tests -Recurse -Filter *.gd | ForEach-Object {
	  $c = ([IO.File]::ReadAllLines($_.FullName) | Where-Object { $_.TrimStart() -like '#*' }).Count
	  if ($c -eq 0) { "可疑（一行注释都没有）: " + $_.Name }
  }
  ```
- **嵌套 `enum` 撞上引擎的全局枚举名，报错指的地方和病因对不上。**
  Godot 有一批全局枚举（`Side`、`Key`、`Error`、`Corner`…），
  而**类里的嵌套 enum 不会遮住它们**：类型标注 `x: Side` 解析成**全局那个**，
  而赋值 `Side.ENEMIES` 解析成**你自己那个**，于是报

  ```
  Parse Error: Cannot assign a value of type "PBSkill.Side" as "Side".
  ```

  M7-c 实测被它拦下过（`PBSkill.Side` → 改名 `PBSkill.Party`）。
  两条要记住：**改名比全限定省事**（留着撞名的话，以后每个在这个文件里
  写 `Side` 的人都会静默拿到引擎那个）；以及**`--import` 那一关看不出来**，
  它是第 4 关「真跑主场景」才炸的 —— 正是 CLAUDE.md 那句
  「解析得过但一 `_ready` 就炸」。
- **`AnimatedSprite2D.play()` 在「停在最后一帧」时会从头重来。** 一段非循环动画
  演完之后引擎只是**停下**（`is_playing()` 转 false，帧停在最后、进度为 1），
  而这时再调一次 `play()` 就是重播 —— 于是**每帧调一次 `play` 的渲染层
  把非循环段变回了循环**，而 `SpriteFrames` 里的 `loop` 标志明明是 0。

  实测被它咬过：人死了之后倒地动画一遍遍重演（玩家报的）。
  两个池子都写着 `if 换段了 or not is_playing(): play()`，而那个
  `not is_playing()` 是**攻击段每出一手重播一遍**要的
  （两发之间状态一直是 `ATTACK`，只能靠「上一遍演完了」触发下一遍）。
  判据因此收在 `PBActorPose.holds_last()` 一处：**只有倒地那一档停住**。

  白模的倒地段只有一帧，所以这条从 M6-b 起就错着，
  直到真素材（倒地段有好几帧）进来才看得见。
- **`AnimatedSprite2D.stop()` 会把位置清回 0**，`pause()` 才是「停在原地」。
  写测试模拟「一段演完了」的状态时用后者。
- **`queue_free()` 不是 `free()`。** 节点删除用 `queue_free()`，在帧末安全释放；
  `free()` 立即释放，正在遍历时调用会崩。
- **`@onready` 变量在 `_ready()` 之前赋值**，别在 `_init()` 里访问它们。
- **GitHub 直连不通**，下载依赖走 `https://ghfast.top/` 前缀代理，
  下完对 SHA256。npm registry 直连正常。

---

## 协作方式

沿用「提问 → 方案 → 决策 → 草稿 → 批准」：写文件前先说要写哪个、写什么，
多文件改动给完整变更集，不擅自 commit。

中文交流；功能与表现优先，数值回归按路线图安排。用户明确授权的工作直接完成，
不重复确认；明确说“收”“提交”后直接提交。画面改动需要实际截图检查，不能只凭单测推断。
