#Requires -Version 5.1
<#
.SYNOPSIS
    把一张头像表切成一人一张的卡面头像。M9-g。

.DESCRIPTION
    .\scripts\make_portraits.ps1

    输入：aires\headshots.png   一张 N 列 x M 行、带黑色格线的头像表
          aires\headshots.txt   一行一个角色键，从左到右、从上到下
    输出：assets\portraits\<键>.png   成品头像（78x90，高清档）

    最后把 data\characters\<角色>.tres 的 icon_key 填成那个键
    （不是 actor_key —— 那个是战场形象，另一套规格）。

    顺序表是一个外部文件，不是代码里的一张表 —— 理由写在
    src/tools/make_portraits.gd 顶部（§14 铁律 5：代码里不出现角色名）。

.NOTES
    网格是量出来的不是算出来的：出图模型画的格线会飘，实测同一张 4096 见方的表
    五行分别是 800 / 804 / 901 / 855 / 666 像素高。按等分切的话会切进邻格的头发里，
    而**它不报错** —— 只表现为「有几张头像顶上多了一条别人的刘海」。
    详见 src/tools/portrait_forge.gd 顶部。

    四趟缺一不可：切 -> 导入 -> 开 mipmap -> 再导入。
    `.import` 是引擎导入时才生成的，所以 mipmap 只能等第一次导入之后再开；
    而不开的表现是「卡面在窗口缩放时闪一层摩尔纹」，静止截图看不出来。
#>
[CmdletBinding()]
param(
	[string]$Sheet = "res://aires/headshots.png",
	[string]$Order = "res://aires/headshots.txt",
	[string]$Out = "res://assets/portraits"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Windows 上必须用 godot_console.exe：godot.exe 是 GUI 子系统程序，
# stdout 不回传给调用它的终端，跑 --headless 会看到一片空白。
$godot = "F:\Godot_PJ\_engine\4.7.2\godot_console.exe"

function Invoke-Godot {
	param([string[]]$Arguments, [string]$What)
	# **原生命令的 stderr 不能当成终止错误。** PowerShell 5.1 会把 native
	# 命令的每一行 stderr 包成 ErrorRecord，配上 $ErrorActionPreference = "Stop"
	# 就会在一条**提醒**上把整个脚本掐掉 —— 而切图那一步正要用 stderr
	# 报「哪几格没铺满」。所以这里只认退出码。
	$prev = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try { & $godot @Arguments } finally { $ErrorActionPreference = $prev }
	if ($LASTEXITCODE -ne 0) { throw "$What 失败（退出码 $LASTEXITCODE）" }
}

Write-Host "1/4 切图 ..." -ForegroundColor Cyan
Invoke-Godot -What "切图" -Arguments @(
	"--headless", "--path", ".", "--script", "res://src/tools/make_portraits.gd",
	"--", "--sheet", $Sheet, "--order", $Order, "--out", $Out
)

Write-Host "2/4 导入 ..." -ForegroundColor Cyan
Invoke-Godot -What "导入" -Arguments @("--headless", "--path", ".", "--import")

Write-Host "3/4 打开 mipmap ..." -ForegroundColor Cyan
Invoke-Godot -What "改 .import" -Arguments @(
	"--headless", "--path", ".", "--script", "res://src/tools/make_portraits.gd",
	"--", "--mipmaps", "1", "--out", $Out
)

Write-Host "4/4 再导一次 ..." -ForegroundColor Cyan
Invoke-Godot -What "导入" -Arguments @("--headless", "--path", ".", "--import")

Write-Host "好了。开游戏看仓库那一排卡。" -ForegroundColor Green
