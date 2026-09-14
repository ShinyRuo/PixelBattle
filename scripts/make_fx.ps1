#Requires -Version 5.1
<#
.SYNOPSIS
    把一张特效图集（子弹、命中、范围爆发、光环）切成一段帧。

.DESCRIPTION
    .\scripts\make_fx.ps1 -Sheet aires\fx\fire_ball_fly.png -Key fire_ball -Anim fly -Size 96
    .\scripts\make_fx.ps1 -Sheet aires\fx\kunai.png -Key kunai -Anim fly -Mode key -Size 48

    输入：一张图集，同一段的几帧排成一横排，格与格之间留足空白（不画格线）
    输出：assets\fx\<Key>\<Anim>_<序号>.png

    -Mode    dark = 纯黑底（发光类，默认）；key = 洋红底（实体类）
    -Anchor  center = 画面中心为锚点（默认）；bottom = 底边中点为锚点（立起来的爆发）
    -Size    成品画布长边多少像素（屏幕尺寸 x 3），0 = 不缩放
    -Frames  要切出几格，切出来的格数不对就报错；0 = 不检查

    规格与每一类该填多大见 Docs\素材规格_特效.md。

.NOTES
    四趟缺一不可：切 -> 导入 -> 开 mipmap -> 再导入。
    `.import` 是引擎导入时才生成的，所以 mipmap 只能等第一次导入之后再开。
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)][string]$Sheet,
	[Parameter(Mandatory = $true)][string]$Key,
	[Parameter(Mandatory = $true)][string]$Anim,
	[ValidateSet("dark", "key")][string]$Mode = "dark",
	[ValidateSet("center", "bottom")][string]$Anchor = "center",
	[int]$Size = 0,
	[int]$Frames = 0
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Windows 上必须用 godot_console.exe：godot.exe 是 GUI 子系统程序，
# stdout 不回传给调用它的终端，跑 --headless 会看到一片空白。
$godot = "F:\Godot_PJ\_engine\4.7.2\godot_console.exe"

function Invoke-Godot {
	param([string[]]$Arguments, [string]$What)
	# 原生命令的 stderr 不能当成终止错误（PowerShell 5.1 会把每一行包成 ErrorRecord），只认退出码。
	$prev = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try { & $godot @Arguments } finally { $ErrorActionPreference = $prev }
	if ($LASTEXITCODE -ne 0) { throw "$What 失败（退出码 $LASTEXITCODE）" }
}

$sheetPath = (Resolve-Path $Sheet).Path

Write-Host "1/4 切图 ..." -ForegroundColor Cyan
Invoke-Godot -What "切图" -Arguments @(
	"--headless", "--path", ".", "--script", "res://src/tools/make_fx.gd",
	"--", "--sheet", $sheetPath, "--key", $Key, "--anim", $Anim,
	"--mode", $Mode, "--anchor", $Anchor, "--size", "$Size", "--frames", "$Frames"
)

Write-Host "2/4 导入 ..." -ForegroundColor Cyan
Invoke-Godot -What "导入" -Arguments @("--headless", "--path", ".", "--import")

Write-Host "3/4 打开 mipmap ..." -ForegroundColor Cyan
Invoke-Godot -What "改 .import" -Arguments @(
	"--headless", "--path", ".", "--script", "res://src/tools/make_fx.gd",
	"--", "--mipmaps", "1", "--key", $Key
)

Write-Host "4/4 再导一次 ..." -ForegroundColor Cyan
Invoke-Godot -What "导入" -Arguments @("--headless", "--path", ".", "--import")

Write-Host "好了：assets\fx\$Key\$Anim`_*.png" -ForegroundColor Green
