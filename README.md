# PixelBattle

魔兽争霸3 RPG 地图《忍法战场》的复刻版 —— 2D 像素风、横屏、无限流 PVE 塔防自走棋，
目标 PC + 手机双端。Godot 4.7.2 + GDScript。开发使用 Codex / Claude Code + VSCode，Godot 编辑器按需打开。

抽忍者 → 排阵型 → 自动战斗 + 手动放大招 → 打无限波次，看能推多远。
核心策略是五系属性克制配上敌人属性固定轮转，逼玩家凑齐五系而不是堆一套最优解。

## 30 秒上手

```powershell
# 1. 打开工作区
code F:\Godot_PJ\PixelBattle\PixelBattle.code-workspace

# 2. 确认环境健康（默认功能检查通常需要几分钟）
.\scripts\check.ps1

# 3. 跑起来看看
godot_console --path .
```

VSCode 里：`Ctrl+Shift+B` = 自检，`F5` = 带断点运行。

跑起来之后，准备阶段基本靠鼠标：**点选忍者、拖动摆位、拖进任务栏派任务**。
键盘只剩几个：`回车` 开打，`A` 开关自动推进，`R` 重开，
`Esc` 一下收一层（说明卡 → 弹层 → 瞄准 → 选中 → 功能菜单），
`F10` 换窗口大小，`F11` 全屏。

看战场形象（接美术素材时用）：

```powershell
F:\Godot_PJ\_engine\4.7.2\godot.exe --path . res://scenes/actor_lab.tscn
```

**当前进度**：M-1～M10 已落地，M12「向原版对齐」进行中；数值回归在 M12 之后。
角色与敌人已有成品素材，缺素材时自动使用白模。具体待办以 [开发路线图](Docs/开发路线图.md) 为准。

## 文档

| 文档 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | Codex 自动入口、必读文档与协作偏好 |
| [CLAUDE.md](CLAUDE.md) | **开发代理共用约定**：架构铁律、自检契约、编码规范、场景文件规矩、坑位 |
| [Docs/代码导读.md](Docs/代码导读.md) | `src/` 的分层、数据流、类速查、「想改 X 去哪」 |
| [Docs/开发路线图.md](Docs/开发路线图.md) | 当前进度、里程碑、待决策、风险登记 |
| [Docs/施工策划案.md](Docs/施工策划案.md) | 主规格：规则、公式、可调参数、验收标准 |
| [Docs/玩法拆解_忍法战场.md](Docs/玩法拆解_忍法战场.md) | 原版考据，理解「为什么这么设计」 |
| [Docs/环境搭建记录.md](Docs/环境搭建记录.md) | 这套环境怎么装出来的，换机器照着重来一遍 |
| [Docs/Godot上手笔记.md](Docs/Godot上手笔记.md) | UE → Godot 概念对照、GDScript 速查、常用操作 |

## 目录

```
src/core/     模拟与规则，零引擎依赖（架构铁律 1）
src/data/     data/ 的装载器（ResourceLoader 在 core 里禁用）
src/tools/    批量扫描、诊断、截图，不是游戏代码
src/view/     渲染与 HUD
data/         角色 / 羁绊 / 语言表（.tres + .json）—— **换皮只改这里**
scenes/       .tscn 场景
assets/       美术、音频
tests/        GUT 用例
scripts/      开发脚本（PowerShell），不是游戏代码
addons/       第三方插件（GUT 测试框架、Godot MCP），不改不 lint
Docs/         项目文档
```

## 自检闭环

改完任何代码或场景，跑 `.\scripts\check.ps1`，默认五项通过、退出码 0 才算改完：

1. **导入** — 解析全部脚本，抓语法错误和断掉的资源引用
2. **core 纯度** — grep `src/core/`，出现任何引擎 API 就报错
3. **gdlint** — 命名、行长、代码异味
4. **运行时冒烟** — 真跑主场景 120 帧，抓「解析得过但一 `_ready` 就炸」
5. **GUT** — 单元测试

```powershell
.\scripts\check.ps1 -Fix        # 顺手 gdformat 格式化
.\scripts\check.ps1 -Deep       # 连慢档（配平扫描）一起跑
.\scripts\check.ps1 -SkipTests  # 只做快速校验
.\scripts\check.ps1 -SkipLint   # 显式跳过静态检查（只算部分检查）
.\scripts\check.ps1 -Full       # 打印每阶段完整输出（默认只在失败时打）
```

测试分两档：默认功能档通常需要几分钟，具体数量和耗时以本次报告为准。
慢档装的是靠整局扫描才能验的配平结论，**仅在用户明确要求或已授权专项深度验证时运行**；修改、提交和验收不自动触发。
详见 CLAUDE.md 的「测试分两档」。

缺少必需依赖会在导入前报错。显式跳过的阶段会在最终报告标为“未验证”；
GUT 没实际执行测试时也会失败。自检脚本的隔离验证：
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test_check.ps1`。

默认静默是有意的：成功时刷 200 行导入进度条既没信息量，又会白吃掉 AI 的上下文窗口。

## 环境

| 项 | 值 |
|---|---|
| 引擎（GUI） | `F:\Godot_PJ\_engine\4.7.2\godot.exe` |
| 引擎（命令行） | `F:\Godot_PJ\_engine\4.7.2\godot_console.exe` |
| 测试 | GUT 9.7.1 |
| 静态检查 | gdtoolkit 4.5.0（gdlint / gdformat） |
| MCP | `@satelliteoflove/godot-mcp` 4.1.9（需 Godot 编辑器开着） |

**命令行一律用 `godot_console.exe`。** `godot.exe` 是 GUI 子系统程序，stdout 不回传终端，
用它跑 `--headless` 会看到一片空白。
