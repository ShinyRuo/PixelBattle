# AI 出图：一个忍者的整套战场形象

配套读 [`素材规格_战场形象.md`](素材规格_战场形象.md)（尺寸、锚点、朝向那一页）。
这一页只管**怎么让 AI 把图生出来，以及生出来之后怎么装进游戏**。

---

## 0. 先接受一件事：AI 生不出可用的序列帧

这不是提示词写得不够好的问题，是这类模型的结构决定的：

- **帧间不连续。** 让它一次出 4 帧跑步图，四张里的人衣服、发型、比例都会变。
- **像素栅格是假的。** 它画的是「看起来像素风的插画」，放大看格子宽窄不一、
  边缘带半透明——而这个游戏的画布只有 36×36，一格都错不起。
- **不认锚点。** 你说「脚踩在画布底边」它不懂，那是排版约束不是画面内容。

所以**可行的流程是「高清出图 → 人工降采样对齐」**，AI 负责的是造型和配色，
不是最终像素。下面这套提示词就是按这个前提写的：**一次只出一张、
高分辨率、纯色背景、正侧面站姿**，姿势之间靠**同一张参考图**保持一致。

> 想省这一步的话，专门做像素序列帧的工具（Scenario、PixelLab 之类）
> 比通用模型靠谱得多，它们直接吐 `.png` 序列。但**产出照样要过第 3 节的
> 那道降采样与对齐**——脚底锚点错一格，游戏里前后关系就错一档。

---

## 1. 主提示词（先出这一张，它是全套的基准）

把 `<ROLE>` 换成这个角色的设定，别的一个字不动。

```
2D game character sprite, single character, full body, strict side view
(profile), facing right, standing idle pose, feet flat on an implied
ground line at the very bottom of the frame, arms relaxed at the sides.

<ROLE>

Art style: retro pixel art, 16-bit fighting game sprite, in the style of
Flash-era anime fighting games; bold clean 1px dark outline around the
whole silhouette; flat cel shading with at most 3 tones per material;
saturated but not neon palette; strong readable silhouette that stays
legible when shrunk to 36 pixels tall.

Composition: character centred horizontally, occupying the full height
of the frame with a small margin at the top, nothing cropped.
Plain flat magenta background (#FF00FF), no ground shadow, no scenery,
no text, no logo, no border, no frame, no character sheet, no multiple
poses, no turnaround.
```

`<ROLE>` 的写法（一句到两句，说清**剪影**和**配色**，不要写角色姓名）：

> 例：`A young male ninja, spiky blonde hair, orange and black jumpsuit,
> blue forehead protector, red spiral emblem on the back.`

**为什么这么写**

| 这一句 | 挡的是什么 |
|---|---|
| `strict side view (profile), facing right` | 默认给你四分之三侧，那种图翻转之后会明显不对称 |
| `feet flat ... at the very bottom of the frame` | 脚底锚点唯一能在生成阶段争取到的东西 |
| `1px dark outline` | 战场上同一列会叠着七八个人，**没有描边就数不出几个人**（实测） |
| `at most 3 tones per material` | 降到 36 像素之后，渐变会糊成噪点 |
| `plain flat magenta background` | 抠背景最省事的颜色，人身上几乎不会出现 |
| `no character sheet, no multiple poses` | 不写它，十次有六次给你一张四宫格 |

**负面提示词**（支持的模型填这里，不支持的就把上面最后一段留着）：

```
3/4 view, three-quarter view, front view, back view, turnaround sheet,
multiple poses, multiple characters, sprite sheet grid, text, watermark,
signature, ui, frame, border, drop shadow, ground shadow, blurry,
anti-aliased edges, soft gradient, photorealistic, 3d render, chibi
proportions, cropped limbs, cut off feet
```

---

## 2. 其余姿势：每一张都带上第 1 张当参考

**关键是「参考」而不是「重写描述」。** 用 img2img / reference image /
character reference 之类的功能，把第 1 张待机图喂进去，权重给中高
（img2img 的 denoise 建议 0.45~0.6：低了不改姿势，高了换个人）。
提示词只改**姿势那一句**，风格段和背景段一个字不动。

| 段 | 换掉的那一句 | 要几张 |
|---|---|---|
| `idle` | `standing idle pose, arms relaxed at the sides, slight breathing motion` | 2~4 |
| `run` | `running to the right, mid-stride, one leg forward one leg back, arms swinging, torso leaning slightly forward` | 4~6 |
| `attack` | `attacking to the right, arm fully extended forward in a strike, weight on the front foot, body twisted into the blow` | 3~5 |
| `cast`（可选） | `channelling chakra, both hands together in a hand seal in front of the chest, feet planted, energy glow around the hands` | 2~3 |
| `dead`（可选） | `lying face down on the ground, collapsed, seen from the side` | 1 |

**同一段里的几帧靠「插值」而不是「再生一次」**：出这一段的**首帧和末帧**，
中间帧在像素编辑器里手挪（一格一格地推手臂和腿），比再抽一次卡稳得多。
`run` 那种循环段，第 3 帧通常就是第 1 帧的镜像姿势。

**一次要出五段 × 一个角色 × 30 个角色，别手点。** 写个批处理脚本按上面的
表格套模板，一次跑完再统一挑。

---

## 3. 出图之后：三步降采样对齐（这一步不能跳）

工具用 Aseprite（最顺手）、或者 Photoshop / GIMP / libresprite 都行。

1. **抠背景。** 按洋红色选中，删掉。**边缘不要羽化** ——
   留下的半透明像素在游戏里会变成一圈脏边。
2. **降到 36 像素高。** 缩放算法必须选**最近邻 / Nearest Neighbor**
   （Aseprite 里是 `Sprite > Sprite Size > Nearest`）。
   双线性会把每个像素糊成四个半调像素，像素风当场消失。
   降完**一定要手工修一遍**：眼睛、发梢、武器这些一两像素的东西
   降采样之后必然糊掉，得手动点回来。
3. **对齐画布。** 新建 36×36 画布，把人贴进去，
   **脚底落在第 36 行（最底一行）、水平居中**。
   同一个角色的**所有帧共用这一个对齐**——逐帧各对各的，人会在动画里抖。

自查（和规格那页的清单是同一份）：

- [ ] 每一帧都是 36×36
- [ ] 脚踩在最底一行，水平居中
- [ ] 全部朝右（或者全部朝左，并在 `.tres` 里说明）
- [ ] 有 1px 深色描边
- [ ] 没有半透明边缘
- [ ] `attack` 的**第一帧就是打出去的那一下**（起手动作 0~1 帧，收招可以长）

---

## 4. 装进游戏

假设角色叫 `naruto`（`actor_key`，小写英文 + 下划线，**不要用中文名**）。

### 4.1 放文件

把切好的帧放进 `assets/actors/naruto/`：

```
assets/actors/naruto/idle_0.png  idle_1.png
assets/actors/naruto/run_0.png   run_1.png  run_2.png  run_3.png
assets/actors/naruto/attack_0.png  attack_1.png  attack_2.png
```

放完在 Godot 编辑器里等它导入完（或者跑一次 `.\scripts\check.ps1`，
第 1 步就是 `--import`）。

### 4.2 关掉纹理过滤（**漏了这一步整套图会糊**）

项目已经全局设成了「最近邻」（`project.godot` 的
`textures/canvas_textures/default_texture_filter=0`），所以正常不用管。
但如果某张图在编辑器里被单独改过导入设置，要在**导入面板**里把
`Filter` 关掉、`Mipmaps` 关掉，然后按「重新导入」。

### 4.3 建 `SpriteFrames`

1. 新建一个资源，类型选 `SpriteFrames`，存成 `data/actors/naruto_frames.tres`
2. 双击打开，底部的动画面板里建三段：`idle` / `run` / `attack`
   （**名字必须是这三个**，或者在下一步的 `.tres` 里改映射）
3. 每一段把对应的 png 按顺序拖进去
4. 每一段设帧率：`idle` 4~6、`run` 10~12、`attack` 12~16
5. 循环：`idle` 和 `run` 开，**`attack` 关**
6. 把默认那个空的 `default` 段删掉

### 4.4 建 `PBActorSkin`

新建资源，类型选 `PBActorSkin`，存成 `data/actors/naruto.tres`，填：

| 字段 | 填什么 |
|---|---|
| `key` | `naruto`（和文件名一样；留空会按文件名兜底） |
| `frames` | 拖 `naruto_frames.tres` 进来 |
| `anim_idle` / `anim_run` / `anim_attack` | `idle` / `run` / `attack` |
| `anim_cast` / `anim_dead` | 有就填，没有留着——查不到会自动退回攻击段和待机段 |
| `skill_anims` | `{ 忍术 id: 段名 }`，没有就空着 |
| `source_faces` | 你画的是朝右就 `RIGHT`，朝左就 `LEFT` |
| `pixel_scale` | `1.0`。**要放大只能填整数**，非整数会切碎像素栅格 |
| `foot_offset` | **留 `(0,0)`**，那表示「画布底边中点」，也就是规格里的默认锚 |
| `tint_by_element` | **`false`**（真素材自己有颜色，再染一层会把美术定的色拉偏） |
| `height_px` | 站着时从脚底到头顶多少像素，36 画布的话一般填 `27` |

### 4.5 把角色指过去

打开 `data/characters/naruto.tres`，把 **`actor_key`** 填成 `naruto`。
（**不是 `icon_key`** —— 那个是卡面头像，另一套规格，还没开工。）

### 4.6 看一眼

```powershell
F:\Godot_PJ\_engine\4.7.2\godot.exe --path .
```

或者直接截图：

```powershell
F:\Godot_PJ\_engine\4.7.2\godot.exe --path . `
    --script res://src/tools/screenshot.gd -- --wave 12 --auto --out build/check.png
```

**没换上去的话按这个顺序查**（每一条都不报错，只表现为「还是白模」）：

1. `PBCharacter.actor_key` 和 `PBActorSkin.key` 拼写对不上
2. `.tres` 没放在 `data/actors/` 下面
3. `frames` 那一格是空的
4. 段名和 `SpriteFrames` 里的对不上——这一条**会退回待机段**而不是白模，
   现象是「他会站但不会跑」

---

## 5. 一个角色的工作量估算

| | |
|---|---|
| AI 出图 | 5 段 × 首尾两张 ≈ 10 张，挑一轮 |
| 降采样 + 手修 | 每帧 5~15 分钟，一套 12 帧 |
| 中间帧手挪 | 一套 3~6 帧 |
| 建 `.tres` + 接线 | 5 分钟 |

**先做一个走通全流程再批量。** 第一个角色会暴露一堆这页没写到的问题
（配色在战场底色上够不够跳、27 像素高够不够认出是谁），
而那些问题改的是提示词，一次改完剩下 29 个都省了。
