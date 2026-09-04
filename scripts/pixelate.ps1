#Requires -Version 5.1
<#
.SYNOPSIS
    把 AI 出的高清立绘压成真·低分辨率像素图，再放大回去。M6-p。

.DESCRIPTION
    .\scripts\pixelate.ps1 -In aires\raw\sakura.png

    banana 那一路出的立绘是「看起来像素风的插画」——边缘带半透明、格子宽窄不一、
    脸画得很清楚。这条命令把它**真的**降到几十像素高再用最近邻放大回去，
    得到的每一格都是一个实心方块，脸上只剩几个像素点。
    产出直接当视频模型（Seedance / 可灵这一路）的首帧图用。

    输入可以是一个文件，也可以是一个目录（目录里所有 png/jpg 都过一遍）。
    输出是同目录下的 <名字>_px.png，或者 -Out 指定的目录。

    **想一眼比出该压到哪一档就开插件**：Godot 编辑器底栏那排按钮里点「降采样」，
    六个档位并排出结果，挑一个存盘。两条路走的是同一个类
    （src/tools/pixelate.gd），出的图一模一样。

.PARAMETER Height
    降到多少像素高。默认 96：
      48  只剩色块，认不出五官     96  能看出发型和衣服的分界（推荐）
      128 还能看出一点脸           160 基本没压住

    **实际倍数取整**：N = round(原高 / Height)，小图高 = 原高 / N。
    非整数倍会把像素栅格压成宽窄不一的格子，而它不报错，只表现为「看着有点脏」。

.PARAMETER Colors
    调色板压到几种颜色，默认 24。0 = 不压。
    这一步比降分辨率更能去掉「插画感」——渐变和高光会被并成一块。

.PARAMETER Tol
    抠洋红背景的容差，默认 0.20。**粉色头发的角色不要往上调** ——
    浅粉到洋红的距离只有 0.41，调到 make_actor 那边用的 0.34 就开始啃头发，
    而它不报错。背景不是洋红时用 -NoKey 整个关掉。

.NOTES
    这个脚本自己不做任何图像处理，只是 src/tools/pixelate_cli.gd 的壳，
    而那个又只是 PBPixelate 的调用方。**流水线只有一份** ——
    各写一份的话「命令行出的图和插件出的图差一个色阶」迟早发生，而它不报错。
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)][string]$In,
	[string]$Out = "",
	[int]$Height = 96,
	[int]$Colors = 24,
	[double]$Tol = 0.20,
	[switch]$NoKey
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = "F:\Godot_PJ\_engine\4.7.2\godot_console.exe"

if (-not (Test-Path $In)) { throw "找不到输入：$In" }
$inFull = (Resolve-Path $In).Path
$outFull = ""
if ($Out -ne "") {
	if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }
	$outFull = (Resolve-Path $Out).Path
}

# 小数点在中文/德文区域会被格式化成逗号，而 GDScript 那边 float("0,2") 得到 0 ——
# 图会一点没抠，而它不报错。所以这里显式按不变区域格式化。
$tolText = $Tol.ToString([Globalization.CultureInfo]::InvariantCulture)

$args = @(
	"--headless", "--path", ".", "--script", "res://src/tools/pixelate_cli.gd", "--",
	"--in", $inFull, "--height", $Height, "--colors", $Colors, "--tol", $tolText
)
if ($outFull -ne "") { $args += @("--out", $outFull) }
if ($NoKey) { $args += "--no-key" }

& $godot @args
if ($LASTEXITCODE -ne 0) { throw "降采样失败" }

Write-Host "`n完成。这张图直接当视频模型的首帧图用。" -ForegroundColor Green
