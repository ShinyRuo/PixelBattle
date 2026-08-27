#Requires -Version 5.1
<#
.SYNOPSIS
    PixelBattle 一键自检：导入校验 → core 纯度 → 静态检查 → 运行时冒烟 → 单元测试。

.DESCRIPTION
    这是整套 AI 开发环境的心脏。Claude（或你自己）改完代码后跑这一条命令，
    就能知道有没有把项目改坏，不用切回 Godot 编辑器手动点。

    五个阶段任何一个失败，脚本以非零退出码结束 —— 这样 CI 和 AI 都能自动判断。

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
Invoke-Stage -Name '1/5 导入资源与解析脚本' `
             -Exe  $Godot `
             -Arguments @('--headless', '--path', $ProjectRoot, '--import') `
             -FailPatterns @('SCRIPT ERROR', 'Parse Error', 'Failed to load', 'Cannot open file')

# ── 阶段 2：core 纯度 ───────────────────────────────────────────
# 施工策划案 §14 的头号铁律：src/core/ 里不许出现任何引擎 API。
# 守住它白拿四样东西 —— 确定性、可单元测试、可 headless 批量模拟、可换渲染层。
# 破坏它的代价极高：sim 里一旦混进场景树访问，四样一起失效，拆回来等于重写。
#
# 靠人自觉守不住（尤其是 AI 改代码时），所以做成自动化防线。
function Invoke-CorePurityStage {
    $name = '2/5 core 纯度（零引擎依赖）'
    Write-Stage $name

    $coreDir = Join-Path $ProjectRoot 'src\core'
    if (-not (Test-Path $coreDir)) {
        Write-Host 'src/core 尚不存在，跳过' -ForegroundColor DarkGray
        Write-Host "✓ $name" -ForegroundColor Green
        return
    }

    # 键是正则，值是给人看的理由 —— 报错时要能直接告诉人「该用什么代替」。
    #
    # (?<![.\w]) 是这里最要紧的一段：rng.randf() 是合法的（我们自己持有的 RNG 实例），
    # 全局 randf() 才是禁止的。两者只差一个点，不看前缀就会把合法用法全拦下来。
    $banned = [ordered]@{
        '(?<![.\w])rand[if](_range)?\s*\('     = '全局随机数，状态不可存档。用 PBRngStreams 的流'
        '(?<![.\w])randomize\s*\('             = '全局随机数播种，会毁掉确定性'
        'extends\s+Node'                       = 'core 不继承 Node，用 RefCounted'
        '(?<![.\w])get_node\s*\('              = '访问场景树'
        '(?<![.\w])get_tree\s*\('              = '访问场景树'
        'Engine\s*\.'                          = '引擎单例。倍速靠步进 tick 数，不改 time_scale'
        '(?<![\w])delta(?![\w])'               = 'core 不读 delta，逻辑固定 20 tick/s'
        '(?<![.\w])(Input|OS|Time|DisplayServer|ProjectSettings|ResourceLoader)\s*\.' = '引擎单例'
        '\$[A-Za-z_"'']'                       = '$ 是 get_node 的语法糖'
        '(?<![.\w])await(?![\w])'              = 'core 必须同步，await 会把 SceneTree 拖进来'
    }

    $hits = @()
    foreach ($file in Get-ChildItem -Path $coreDir -Recurse -Filter '*.gd') {
        $rel = $file.FullName.Substring($ProjectRoot.Length + 1)
        $lineNo = 0
        foreach ($line in (Get-Content $file.FullName -Encoding UTF8)) {
            $lineNo++
            # 先掐掉注释再匹配：文档注释里大量出现 delta、randi() 这些词，
            # 它们是在解释「为什么禁用」，不该被自己的规则拦下来。
            # 这是启发式 —— 字符串字面量里的 # 会被误伤，core 里目前没有这种写法。
            $code = $line -replace '#.*$', ''
            if (-not $code.Trim()) { continue }
            foreach ($pattern in $banned.Keys) {
                # -cmatch 而不是 -match：PowerShell 的 -match 默认忽略大小写，
                # 那样一个叫 input 的局部变量会被当成 Input 单例误报。
                if ($code -cmatch $pattern) {
                    $hits += "  {0}:{1}  {2}" -f $rel, $lineNo, $banned[$pattern]
                    $hits += "      $($line.Trim())"
                }
            }
        }
    }

    if ($hits.Count -gt 0) {
        $hits | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        $script:Failures += $name
        Write-Host "✗ $name" -ForegroundColor Red
    } else {
        $count = (Get-ChildItem -Path $coreDir -Recurse -Filter '*.gd').Count
        if ($Full) { Write-Host "src/core 下 $count 个脚本，无引擎依赖" }
        Write-Host "✓ $name" -ForegroundColor Green
    }
}

Invoke-CorePurityStage

# ── 阶段 3：静态检查 / 格式化 ───────────────────────────────────
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
            Invoke-Stage -Name '3/5 gdformat 格式化' -Exe $gdformat -Arguments @('src', 'tests')
        }
        Push-Location $ProjectRoot
        Invoke-Stage -Name '3/5 gdlint 静态检查' -Exe $gdlint -Arguments @('src', 'tests')
        Pop-Location
    } else {
        Write-Stage '3/5 gdlint —— 跳过（未安装）'
        Write-Host 'pip install "gdtoolkit>=4.0" 可启用' -ForegroundColor Yellow
    }
}

# ── 阶段 4：运行时冒烟 ──────────────────────────────────────────
# 真的把主场景跑起来 120 帧再退出。能抓到「解析得过但一 _ready 就炸」的问题。
Invoke-Stage -Name '4/5 运行时冒烟（主场景跑 120 帧）' `
             -Exe  $Godot `
             -Arguments @('--headless', '--path', $ProjectRoot, '--quit-after', '120') `
             -FailPatterns @('SCRIPT ERROR', 'Invalid call', 'Nonexistent function', 'null instance')

# ── 阶段 5：单元测试 ────────────────────────────────────────────
if (-not $SkipTests) {
    if (Test-Path (Join-Path $ProjectRoot 'addons\gut\gut_cmdln.gd')) {
        Invoke-Stage -Name '5/5 GUT 单元测试' `
                     -Exe  $Godot `
                     -Arguments @('--headless', '--path', $ProjectRoot,
                                  '-s', 'res://addons/gut/gut_cmdln.gd',
                                  '-gdir=res://tests', '-ginclude_subdirs', '-gexit') `
                     -ShowOutput
    } else {
        Write-Stage '5/5 GUT —— 跳过（addons/gut 不存在）'
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
