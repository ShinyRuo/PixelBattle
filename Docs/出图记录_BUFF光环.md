# BUFF 光环出图记录（2026-09-28）

模式：imagegen 文生图。四张均为 1536×1024 透明 PNG、3 列×2 行六帧；`src/tools/import_aura_sheet.gd` 按 512×512 固定网格切出，保留原图于 `aires/skills/buff_<键>.png`，成品在 `assets/fx/buffs/<键>/front_0.png` 至 `front_5.png`。单前层、加色、8 fps；脚底锚点 (256,420)，九尾缩放 0.18，其余 0.16。资源在 `data/buff_art/<键>.tres`。

通用提示词：Production-ready transparent PNG sprite sheet 1536x1024, 3 columns x 2 rows, six exact 512x512 equal cells. Effect only for a 2D pixel-art ninja autobattler. Each cell keeps the same centered thin ground ellipse around the ally's feet at x=256,y=420, with six subtle seamless loop phases. Character space above the feet stays transparent. Sparse crisp luminous pixel-art marks, restrained brightness; no character, text, border, opaque backdrop, huge plume or filled disk; real transparent alpha.

| 资源键 | 各张追加主题 | 运行截图 |
|---|---|---|
| `kurama_cloak_aura` | pale-gold protective/recovery ring with a few upward gold motes, gentle breathing | `build/codex-setup/kurama-aura-runtime.png` |
| `battle_chakra_aura` | thin blue-and-red chakra restorative ring, sparse blue/red rising motes | `build/codex-setup/battle-aura-runtime.png` |
| `light_rock_aura` | pale ochre earth-chakra ring, tiny floating dust specks, reduced weight | `build/codex-setup/light-aura-runtime.png` |
| `gale_dance_aura` | pale cyan-green wind ring, fine swirling streaks and tiny leaf flecks | `build/codex-setup/gale-aura-runtime.png` |

截图使用实际 `PBAllyPool` 与真实技能表构造队伍，没有给单位安装假持续 BUFF。按当前数值，九尾与未触发羁绊的轻重岩只覆盖自身；历战覆盖范围内友军；气流乱舞只覆盖范围内远程单位。离圈与来源失效撤光有自动测试；默认自检五阶段通过（1473/1473），未跑 `-Deep`。
