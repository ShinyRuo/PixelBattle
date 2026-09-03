#Requires -Version 5.1
<#
.SYNOPSIS
    把 AI 生成的几段视频变成一套能直接进游戏的战场形象。M6-f。

.DESCRIPTION
    .\scripts\make_actor.ps1 -Key asm

    输入：aires\<Key>_idle.mp4 / _run.mp4 / _attack.mp4 / _dead.mp4
          （文件名里的段名要和 make_actor.gd 的 ANIMS 对得上）
    输出：assets\actors\<Key>\*.png       成品帧
          data\actors\frames\<Key>.tres   图集（SpriteFrames）
          data\actors\<Key>.tres          形象表（PBActorSkin）

    最后把 data\characters\<角色>.tres 的 actor_key 填成 <Key>，
    再开预览台看一眼。**-Preview 是「跑完顺手打开」，不是「只打开」** ——
    只想看的话走 VSCode 的 F5 →「Godot: 战场形象预览台」，或者：
        F:\Godot_PJ\_engine\4.7.2\godot.exe --path . res://scenes/actor_lab.tscn

    一次完整的走法（含出错对照表）写在 Docs\AI出图_战场形象.md 的 §4.0.2。

    **想自己逐帧挑**：开 Godot 编辑器，底栏那排按钮里点「战场形象」（§4.0.3）。
    两条路走的是同一条流水线（src/tools/actor_forge.gd），出的素材逐字节相同；
    这条命令挑帧是算出来的，插件那条是人挑的。

.NOTES
    重活分给 ffmpeg 的理由写在 make_actor.gd 顶部：一帧 92 万像素，
    GDScript 逐像素扫 388 帧要几分钟。

    ffmpeg 那条滤镜链有三段，缺一不可：
      colorkey    把洋红打成透明
      premultiply 把透明像素的 RGB 归零 —— 不做的话缩放会把洋红渗进人物边缘，
                  而 alpha 看起来完全正常（**不报错**）
      scale=area  按面积平均下采样。最近邻在 2 倍缩放上会丢掉一半细节，
                  而这里只缩到中间尺寸，最后那一档降采样在 Godot 侧做
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)][string]$Key,
	[string]$SrcDir = "aires",
	[string]$MidDir = "build/aires/mid",
	[string[]]$Anims = @("idle", "run", "attack", "dead"),
	[switch]$SkipExtract,
	[switch]$Preview
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = "F:\Godot_PJ\_engine\4.7.2\godot_console.exe"
$godotGui = "F:\Godot_PJ\_engine\4.7.2\godot.exe"

# winget 装的 ffmpeg 在这个目录里放了快捷方式，而它在用户 PATH 里 ——
# 但**已经开着的终端拿的是安装前那份快照**，所以这里显式兜一下。
$ffmpeg = "ffmpeg"
if (-not (Get-Command $ffmpeg -ErrorAction SilentlyContinue)) {
	$linked = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe"
	if (Test-Path $linked) { $ffmpeg = $linked }
	else { throw "找不到 ffmpeg。装一个：winget install Gyan.FFmpeg（装完新开一个终端）" }
}

function Step($text) { Write-Host "`n── $text " -ForegroundColor Cyan }

# ── 1. ffmpeg：抠洋红 → 预乘 → 缩到中间尺寸 ───────────────────────

if (-not $SkipExtract) {
	Step "抽帧（抠洋红 + 预乘 + 缩到 960×540）"
	foreach ($anim in $Anims) {
		$src = Join-Path $root "$SrcDir/${Key}_$anim.mp4"
		if (-not (Test-Path $src)) { throw "少一段视频：$src" }
		$dst = Join-Path $root "$MidDir/$anim"
		if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
		New-Item -ItemType Directory -Force $dst | Out-Null
		& $ffmpeg -v error -y -i $src `
			-vf "colorkey=0xFF00FF:0.34:0.0,format=rgba,premultiply=inplace=1,scale=960:540:flags=area" `
			-fps_mode passthrough (Join-Path $dst "%03d.png")
		if ($LASTEXITCODE -ne 0) { throw "ffmpeg 失败：$anim" }
		$n = (Get-ChildItem $dst -Filter *.png).Count
		Write-Host ("  {0,-8} {1} 帧" -f $anim, $n)
	}
}

# ── 2. Godot 第一趟：量、挑帧、对齐脚底、下采样 ──────────────────

Step "切成成品帧"
& $godot --headless --path . --script res://src/tools/make_actor.gd -- `
	--key $Key --mid "res://$MidDir" --phase frames
if ($LASTEXITCODE -ne 0) { throw "第一趟失败" }

# ── 3. 导入 ──────────────────────────────────────────────────────
#
# **这一步不能省，也不能和第二趟合并。** 引擎只 load 得出导入过的贴图，
# 刚写到磁盘上的 PNG 在同一次进程里是不存在的。

Step "导入新贴图"
& $godot --headless --path . --import | Out-Null

# ── 4. Godot 第二趟：建 SpriteFrames 与 PBActorSkin ──────────────

Step "连线（SpriteFrames + PBActorSkin）"
& $godot --headless --path . --script res://src/tools/make_actor.gd -- --key $Key --phase link
if ($LASTEXITCODE -ne 0) { throw "第二趟失败" }

Step "再导一次（把新写的 .tres 收进去）"
& $godot --headless --path . --import | Out-Null

Write-Host "`n完成。" -ForegroundColor Green
Write-Host "  1. 把 data\characters\<角色>.tres 的 actor_key 填成 &`"$Key`""
Write-Host "  2. 开预览台看一眼：.\scripts\make_actor.ps1 -Key $Key -Preview"

if ($Preview) {
	& $godotGui --path . res://scenes/actor_lab.tscn
}
