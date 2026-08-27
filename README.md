# PixelBattle

魔兽争霸3 RPG 地图《忍法战场》的复刻版 —— 2D 像素风、横屏、无限流 PVE 塔防自走棋，
目标 PC + 手机双端。Godot 4.7.2 + GDScript。开发在 VSCode + Claude Code，Godot 编辑器按需打开。

抽忍者 → 排阵型 → 自动战斗 + 手动放大招 → 打无限波次，看能推多远。
核心策略是五系属性克制配上敌人属性固定轮转，逼玩家凑齐五系而不是堆一套最优解。

## 30 秒上手

```powershell
# 1. 打开工作区
code F:\Godot_PJ\PixelBattle\PixelBattle.code-workspace

# 2. 确认环境健康（首次会慢一点，之后 10 秒内跑完）
.\scripts\check.ps1

# 3. 跑起来看看
godot_console --path .
```

VSCode 里：`Ctrl+Shift+B` = 自检，`F5` = 带断点运行。

## 文档

| 文档 | 内容 |
|---|---|
| [CLAUDE.md](CLAUDE.md) | **给 Claude 的约定**：架构铁律、自检契约、编码规范、场景文件规矩、坑位 |
| [Docs/开发路线图.md](Docs/开发路线图.md) | 当前进度、里程碑、待决策、风险登记 |
| [Docs/施工策划案.md](Docs/施工策划案.md) | 主规格：规则、公式、可调参数、验收标准 |
| [Docs/玩法拆解_忍法战场.md](Docs/玩法拆解_忍法战场.md) | 原版考据，理解「为什么这么设计」 |
| [Docs/环境搭建记录.md](Docs/环境搭建记录.md) | 这套环境怎么装出来的，换机器照着重来一遍 |
| [Docs/Godot上手笔记.md](Docs/Godot上手笔记.md) | UE → Godot 概念对照、GDScript 速查、常用操作 |

## 目录

```
src/          游戏脚本，按系统分子目录
scenes/       .tscn 场景
assets/       美术、音频
tests/        GUT 用例
scripts/      开发脚本（PowerShell），不是游戏代码
addons/       第三方插件（GUT 测试框架、Godot MCP），不改不 lint
Docs/         项目文档
```

## 自检闭环

改完任何代码或场景，跑 `.\scripts\check.ps1`，退出码 0 才算改完。四个阶段：

1. **导入** — 解析全部脚本，抓语法错误和断掉的资源引用
2. **gdlint** — 命名、行长、代码异味
3. **运行时冒烟** — 真跑主场景 120 帧，抓「解析得过但一 `_ready` 就炸」
4. **GUT** — 单元测试

```powershell
.\scripts\check.ps1 -Fix        # 顺手 gdformat 格式化
.\scripts\check.ps1 -SkipTests  # 只做快速校验
.\scripts\check.ps1 -Full       # 打印每阶段完整输出（默认只在失败时打）
```

默认静默是有意的：成功时刷 200 行导入进度条既没信息量，又会白吃掉 AI 的上下文窗口。

## 环境

| 项 | 值 |
|---|---|
| 引擎（GUI） | `F:\Godot_PJ\_engine\4.7.2\godot.exe` |
| 引擎（命令行） | `F:\Godot_PJ\_engine\4.7.2\godot_console.exe` |
| 测试 | GUT 9.6.1 |
| 静态检查 | gdtoolkit 4.5.0（gdlint / gdformat） |
| MCP | `@satelliteoflove/godot-mcp` 4.1.9（需 Godot 编辑器开着） |

**命令行一律用 `godot_console.exe`。** `godot.exe` 是 GUI 子系统程序，stdout 不回传终端，
用它跑 `--headless` 会看到一片空白。
