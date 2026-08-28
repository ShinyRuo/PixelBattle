# PixelBattle — 项目说明书

Godot 4.7.2 / GDScript / 2D。开发在 VSCode + Claude Code，Godot 编辑器只在需要
所见即所得的时候开（摆关卡、调 Input Map、看 GUT 面板）。

---

## 这是什么游戏

魔兽争霸3 RPG 地图《忍法战场》的复刻版。**2D 像素风 · 横屏 · 无限流 PVE 塔防自走棋**，
目标 PC（Steam）+ 手机双端。

一句话玩法：抽忍者 → 排阵型（前中后三列）→ 自动战斗 + 手动放大招 → 打无限波次，
看能推多远。核心策略来自**五系属性克制**（火→风→雷→土→水→火，克制 200% / 被克 50%）
配上**敌人属性按固定顺序轮转**，逼玩家凑齐五系而不是堆一套最优解。

设计详情看 `Docs/`，下面六条是**架构铁律**，破坏任何一条都要付重写代价：

1. **`src/core/` 零引擎依赖** —— 不 `extends Node`（用 `RefCounted`）、不 `get_node()`、
   不访问 `SceneTree`、不读 `delta`、不调全局 `randi()`。守住它才有确定性、可单测、
   可 headless 批量模拟、可换渲染层。
2. **定帧 20 tick/s**，倍速只改每渲染帧步进的 tick 数。
   **绝不用 `Engine.time_scale` 或直接乘 `delta`** —— 浮点漂移会让存档回滚和每日种子失效。
3. **三条独立 RNG 流**（gacha / quest / combat），各持有自己的 `RandomNumberGenerator`，
   `state` 存进档。全局 `randi()` / `randf()` 一律禁用。
4. **`element` 挂在伤害事件上**，不挂在单位上（同一角色的不同技能可以是不同属性）。
5. **代码里不出现角色名字符串**，一律走 `id` + `name_key` 查表。
   角色数据全在 `data/` 的 `.tres` 里，换皮 = 改表，`src/` 一行不动。
6. **`COUNT_CAP`（同屏单位上限）不按平台分档**，双端跑同一份模拟，
   性能差异只在渲染层吸收。

**当前进度**：**M-1 / M0 / M1 已完成，下一个是 M2（羁绊与派遣）。**

战斗画面是「准备 → 战斗 → 结算」三阶段，准备阶段不限时（§01）。准备阶段三块面板：
左侧花钱面板**每个按钮写着买下去战力涨多少**、右侧阵容面板逐格显示克制倍率并算出
「换人多赚多少」、顶部任务卡显示**派了羁绊掉几档**与「离打不动还差多远」。
三块的数字全部来自 `PBValuation`，与模拟玩家比价同源 ——
**抄成两份会让界面上的数和调参依据慢慢分叉，且不报错。**
`A` 键开关自动推进，`Q` 键接/不接任务。
主场景是 `scenes/battle.tscn`，跑 `godot.exe --path .` 就能看。

**开着的设计缺口有四条，全部挂在 M2/M3 上**：

1. **技能阶梯只有 1.30×**（新手代理 33.9 波 → `rational` 44.2 波），
   §01 的新手档 15–25 波不可达 → **M2** 的羁绊组合是第一个能提供乘法级杠杆的系统
2. §01 单波时长差约 8 倍 → M3
3. 战场长期没有敌人（根因是单目标集火，需要射程与多目标分配）→ M3
4. BOSS 波比精英波还轻松，路标变喘息点 → M3

第 1 条和 §07 的「经济位 = 战力空位」是**同一条结构性事实**：
**在指数难度曲线上，线性/加法的优势只值对数级的波次。**
所以修法只有一个方向 —— 给玩家乘法级的、需要学习才会用的系统。
两条验收都已按实测改写，详见 `Docs/开发路线图.md`。

**美术资源仍然不要动** —— 现在还是白模阶段，真美术在 M5。

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

五个阶段，退出码 0 才算改完：

1. `--import` — 导入资源、解析全部脚本（抓语法错误、断掉的资源引用）
2. **core 纯度** — grep `src/core/`，出现 `get_node`、全局 `randi(`、`delta`、
   `extends Node` 就报错。守铁律 1，见 §14
3. `gdlint` — 静态检查（命名、行长、代码异味、成员声明顺序）
4. `--quit-after 120` — 真跑主场景 120 帧（抓「解析得过但一 `_ready` 就炸」）
5. GUT — 单元测试

> **阶段 5 会因为「测试静默消失」而失败，这是有意的。** 一个测试文件解析失败时
> GUT 只打一行 WARNING 就跳过整个文件，然后**照样返回 0** —— 用例数悄悄少掉一截，
> 而自检报告「全部通过」。所以那一阶段配了 `FailPatterns` 把这种情况拦死。

### 测试分两档

默认跑 **13 秒**的快档（133 用例）。`-Deep` 跑全量 **58 秒**（140 用例）。

慢档只有 `tests/test_balance_scan.gd` 一个文件，装的是**靠整局扫描才能验的配平结论**
（装备定价、经济位不是陷阱也不支配、GROWTH 单调）。它一家占了分档前 98 秒里的 83 秒 ——
因为 `rational` 流派每花一笔钱就重估一遍全部候选项，一局 2.1 秒，
而写死优先级的 `balanced` 只要 93 毫秒，**差 22 倍**。

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
src/          游戏脚本，按系统分子目录（player/、systems/、enemy/…）
scenes/       .tscn 场景
assets/       美术、音频（导入后引擎会在旁边生成 .import 元数据）
tests/        GUT 用例，文件名和方法名都以 test_ 开头
addons/       第三方插件，不改、不 lint
scripts/      开发脚本（PowerShell），不是游戏代码
Docs/         项目文档
```

## 其他文档

**设计**

- [Docs/开发路线图.md](Docs/开发路线图.md) — **先读这份**：当前进度、里程碑、待决策、风险登记
- [Docs/施工策划案.md](Docs/施工策划案.md) — 主规格。每个系统给规则、公式、可调参数、验收标准
- [Docs/玩法拆解_忍法战场.md](Docs/玩法拆解_忍法战场.md) — 原版考据，理解「为什么这么设计」

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
- **`queue_free()` 不是 `free()`。** 节点删除用 `queue_free()`，在帧末安全释放；
  `free()` 立即释放，正在遍历时调用会崩。
- **`@onready` 变量在 `_ready()` 之前赋值**，别在 `_init()` 里访问它们。
- **GitHub 直连不通**，下载依赖走 `https://ghfast.top/` 前缀代理，
  下完对 SHA256。npm registry 直连正常。

---

## 协作方式

沿用「提问 → 方案 → 决策 → 草稿 → 批准」：写文件前先说要写哪个、写什么，
多文件改动给完整变更集，不擅自 commit。
