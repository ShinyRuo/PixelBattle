#Requires -Version 5.1
<#
.SYNOPSIS
    PixelBattle 一键自检：导入校验 → 静态检查 → 运行时冒烟 → 单元测试。

.DESCRIPTION
    这是整套 AI 开发环境的心脏。Claude（或你自己）改完代码后跑这一条命令，
    就能知道有没有把项目改坏，不用切回 Godot 编辑器手动点。

    四个阶段任何一个失败，脚本以非零退出码结束 —— 这样 CI 和 AI 都能自动判断。

.PARAMETER Fix
    用 gdformat 就地格式化代码（而不是只检查）。

.PARAMETER SkipTests
    跳过 GUT 单元测试，只做快速校验。

.EXAMPLE
    .\scripts\check.ps1
    .\scripts\check.ps1 -Fix
    .\scripts\check.ps1 -SkipTests
#>
[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$SkipTests,
    [switch]$SkipLint,
    # 打印每个阶段的完整输出。默认只在失败时打印 ——
    # 成功时刷 200 行导入进度条既没信息量，又会白白吃掉 AI 的上下文窗口。
    [switch]$Full
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ProjectRoot = Split-Path -Parent $PSScriptRoot

# godot_console.exe 而不是 godot.exe：Windows 上 GUI 版不会把 stdout 交回终端。
$Godot = $env:GODOT
if (-not $Godot) { $Godot = 'F:\Godot_PJ\_engine\4.7.2\godot_console.exe' }
if (-not (Test-Path $Godot)) {
    Write-Host "找不到 Godot: $Godot" -ForegroundColor Red
    Write-Host "设置环境变量 GODOT 指向 godot_console.exe，或改本脚本顶部的默认路径。" -ForegroundColor Yellow
    exit 127
}

$script:Failures = @()

function Write-Stage {
    param([string]$Text)
    Write-Host ''
    Write-Host ("─" * 64) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("─" * 64) -ForegroundColor DarkGray
}

# 用 Start-Process + 重定向来跑外部程序。
# 不用 `2>&1`：PowerShell 5.1 会把原生程序的 stderr 包成 ErrorRecord，
# 即使程序返回 0 也会把 $? 弄成 false，判断结果就不可靠了。
# 去掉 ANSI 颜色转义，否则日志里全是 [0m[90m 这类噪音
function Remove-Ansi {
    param([string]$Text)
    if (-not $Text) { return '' }
    return ($Text -replace "$([char]27)\[[0-9;]*[A-Za-z]", '')
}

function Invoke-Stage {
    param(
        [string]   $Name,
        [string]   $Exe,
        [string[]] $Arguments,
        [string[]] $FailPatterns = @(),
        # 该阶段的输出本身就是结果（例如测试报告），成功也要打印
        [switch]   $ShowOutput
    )

    Write-Stage $Name

    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $Exe -ArgumentList $Arguments `
                              -NoNewWindow -Wait -PassThru `
                              -RedirectStandardOutput $outFile `
                              -RedirectStandardError  $errFile
        $stdout = ''
        $stderr = ''
        if ((Get-Item $outFile).Length -gt 0) { $stdout = Get-Content $outFile -Raw -Encoding UTF8 }
        if ((Get-Item $errFile).Length -gt 0) { $stderr = Get-Content $errFile -Raw -Encoding UTF8 }
        $combined = Remove-Ansi "$stdout`n$stderr"

        # 先判定成败，再决定打印多少 —— 顺序很重要
        $bad = $false
        $reasons = @()
        if ($proc.ExitCode -ne 0) {
            $bad = $true
            $reasons += "退出码 $($proc.ExitCode)"
        }
        foreach ($pat in $FailPatterns) {
            if ($combined -match $pat) {
                $bad = $true
                $reasons += "输出中出现「$pat」"
            }
        }

        if ($bad -or $Full -or $ShowOutput) {
            $body = $combined.Trim()
            if ($body) {
                # 失败时把进度条噪音滤掉，只留真正有用的行
                if ($bad -and -not $Full) {
                    $body = ($body -split "`n" | Where-Object { $_ -notmatch '^\[\s*\d+%\s*\]' }) -join "`n"
                }
                Write-Host $body.Trim()
            }
        }

        if ($bad) {
            $script:Failures += $Name
            $reasons | ForEach-Object { Write-Host "  → $_" -ForegroundColor Red }
            Write-Host "✗ $Name" -ForegroundColor Red
        } else {
            Write-Host "✓ $Name" -ForegroundColor Green
        }
    }
    finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "PixelBattle 自检  —  $ProjectRoot" -ForegroundColor White

# ── 阶段 1：导入资源 + 加载全部脚本 ─────────────────────────────
# 新加的图片/音频会在这里生成 .import 元数据；脚本的解析错误也会在这里冒出来。
Invoke-Stage -Name '1/4 导入资源与解析脚本' `
             -Exe  $Godot `
             -Arguments @('--headless', '--path', $ProjectRoot, '--import') `
             -FailPatterns @('SCRIPT ERROR', 'Parse Error', 'Failed to load', 'Cannot open file')

# ── 阶段 2：静态检查 / 格式化 ───────────────────────────────────
if (-not $SkipLint) {
    # 先查 PATH；查不到就去 pip 的 Scripts 目录捞。
    # 必须兜底：刚 pip install 完的那个终端里 PATH 还是旧的，
    # 而 VSCode 任务继承的也可能是启动时的旧环境。
    function Resolve-Tool {
        param([string]$Name)
        $cmd = Get-Command $Name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $guesses = @(
            (Join-Path (Split-Path (& python -c "import sys;print(sys.executable)" 2>$null)) "Scripts\$Name.exe"),
            "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\Scripts\$Name.exe",
            "$env:APPDATA\Python\Scripts\$Name.exe"
        )
        foreach ($g in $guesses) {
            if ($g -and (Test-Path $g)) { return $g }
        }
        return $null
    }
    $gdlint   = Resolve-Tool 'gdlint'
    $gdformat = Resolve-Tool 'gdformat'
    if ($gdlint) {
        if ($Fix -and $gdformat) {
            Invoke-Stage -Name '2/4 gdformat 格式化' -Exe $gdformat -Arguments @('src', 'tests')
        }
        Push-Location $ProjectRoot
        Invoke-Stage -Name '2/4 gdlint 静态检查' -Exe $gdlint -Arguments @('src', 'tests')
        Pop-Location
    } else {
        Write-Stage '2/4 gdlint —— 跳过（未安装）'
        Write-Host 'pip install "gdtoolkit>=4.0" 可启用' -ForegroundColor Yellow
    }
}

# ── 阶段 3：运行时冒烟 ──────────────────────────────────────────
# 真的把主场景跑起来 120 帧再退出。能抓到「解析得过但一 _ready 就炸」的问题。
Invoke-Stage -Name '3/4 运行时冒烟（主场景跑 120 帧）' `
             -Exe  $Godot `
             -Arguments @('--headless', '--path', $ProjectRoot, '--quit-after', '120') `
             -FailPatterns @('SCRIPT ERROR', 'Invalid call', 'Nonexistent function', 'null instance')

# ── 阶段 4：单元测试 ────────────────────────────────────────────
if (-not $SkipTests) {
    if (Test-Path (Join-Path $ProjectRoot 'addons\gut\gut_cmdln.gd')) {
        Invoke-Stage -Name '4/4 GUT 单元测试' `
                     -Exe  $Godot `
                     -Arguments @('--headless', '--path', $ProjectRoot,
                                  '-s', 'res://addons/gut/gut_cmdln.gd',
                                  '-gdir=res://tests', '-ginclude_subdirs', '-gexit') `
                     -ShowOutput
    } else {
        Write-Stage '4/4 GUT —— 跳过（addons/gut 不存在）'
    }
}

# ── 汇总 ────────────────────────────────────────────────────────
Write-Host ''
Write-Host ("═" * 64) -ForegroundColor DarkGray
if ($script:Failures.Count -eq 0) {
    Write-Host '  全部通过 ✓' -ForegroundColor Green
    Write-Host ("═" * 64) -ForegroundColor DarkGray
    exit 0
} else {
    Write-Host "  失败 $($script:Failures.Count) 项：" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "    · $_" -ForegroundColor Red }
    Write-Host ("═" * 64) -ForegroundColor DarkGray
    exit 1
}
