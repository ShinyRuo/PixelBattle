#Requires -Version 5.1
<#
.SYNOPSIS
    在隔离目录中验证 check.ps1 的依赖检查、跳过语义与失败退出码。
.DESCRIPTION
    用小型命令行替身测试检查流程，不调用 Godot，也不改项目的插件或 PATH 设置。
    产物保留在被 Git 忽略的 build/check-contract 下，便于检查失败日志。
#>
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $projectRoot ('build\check-contract\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$stub = Join-Path $testRoot 'stage-stub.exe'
Add-Type -TypeDefinition @'
using System;
public static class CheckStageStub {
    public static int Main(string[] args) {
        if (Array.Exists(args, a => a.StartsWith("-gdir="))) {
            string mode = Environment.GetEnvironmentVariable("PB_CHECK_STUB_RESULT");
            if (mode == "empty") { Console.WriteLine("Tests 0"); return 0; }
            if (mode == "error") { Console.WriteLine("SCRIPT ERROR: simulated failure"); }
            Console.WriteLine("Tests 1");
            Console.WriteLine("Passing Tests 1");
        }
        return 0;
    }
}
'@ -OutputAssembly $stub -OutputType ConsoleApplication

$cases = @(
    @{Name='missing-lint'; Lint=$false; Gut=$true; Args=@(); Exit=127; Text='gdlint'},
    @{Name='missing-gut'; Lint=$true; Gut=$false; Args=@(); Exit=127; Text='GUT'},
    @{Name='missing-format'; Lint=$true; Gut=$true; Args=@('-Fix'); Exit=127; Text='gdformat'},
    @{Name='conflicting-fix'; Lint=$true; Gut=$true; Args=@('-Fix','-SkipLint'); Exit=2; Text='不能'},
    @{Name='conflicting-deep'; Lint=$true; Gut=$true; Args=@('-Deep','-SkipTests'); Exit=2; Text='不能'},
    @{Name='skip-both'; Lint=$false; Gut=$false; Args=@('-SkipLint','-SkipTests'); Exit=0; Text='部分检查'},
    @{Name='skip-tests'; Lint=$true; Gut=$false; Args=@('-SkipTests'); Exit=0; Text='部分检查'},
    @{Name='skip-lint'; Lint=$false; Gut=$true; Args=@('-SkipLint'); Exit=0; Text='部分检查'},
    @{Name='default-pass'; Lint=$true; Gut=$true; Args=@(); Exit=0; Text='默认自检全部通过'},
    @{Name='empty-suite'; Lint=$true; Gut=$true; Args=@(); Mode='empty'; Exit=1; Text='缺少有效测试汇总'},
    @{Name='script-error'; Lint=$true; Gut=$true; Args=@(); Mode='error'; Exit=1; Text='失败'},
    @{Name='launch-error'; Lint=$true; Gut=$true; Args=@(); BadExe=$true; Exit=1; Text='无法完成检查'}
)
$shellExe = Join-Path $PSHOME 'powershell.exe'
$utf8 = New-Object Text.UTF8Encoding($false)
$saved = @{}
foreach ($key in 'PATH','LOCALAPPDATA','APPDATA','GODOT','PB_CHECK_STUB_RESULT') {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    foreach ($case in $cases) {
        $fixture = Join-Path $testRoot $case.Name
        foreach ($dir in 'scripts','bin','src\core','addons\gut') {
            New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force | Out-Null
        }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'check.ps1') -Destination (Join-Path $fixture 'scripts\check.ps1')
        $env:GODOT = Join-Path $fixture 'bin\godot.exe'
        if ($case.BadExe) {
            [IO.File]::WriteAllText($env:GODOT, 'not an executable', $utf8)
        } else {
            Copy-Item -LiteralPath $stub -Destination $env:GODOT
        }
        if ($case.Lint) { Copy-Item -LiteralPath $stub -Destination (Join-Path $fixture 'bin\gdlint.exe') }
        if ($case.Gut) { [IO.File]::WriteAllText((Join-Path $fixture 'addons\gut\gut_cmdln.gd'), '# fixture', $utf8) }
        [IO.File]::WriteAllText((Join-Path $fixture 'src\core\probe.gd'), 'extends RefCounted', $utf8)
        $env:PATH = Join-Path $fixture 'bin'
        $env:LOCALAPPDATA = $fixture
        $env:APPDATA = $fixture
        $env:PB_CHECK_STUB_RESULT = $case.Mode
        $stdout = Join-Path $fixture 'stdout.log'
        $stderr = Join-Path $fixture 'stderr.log'
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + (Join-Path $fixture 'scripts\check.ps1') + '"')) + $case.Args
        $proc = Start-Process -FilePath $shellExe -ArgumentList $arguments -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = (Get-Content -LiteralPath $stdout -Raw -Encoding UTF8) + (Get-Content -LiteralPath $stderr -Raw -Encoding UTF8)
        if ($proc.ExitCode -ne $case.Exit -or $output -notmatch [regex]::Escape($case.Text)) {
            throw "$($case.Name): expected exit $($case.Exit) and '$($case.Text)', got $($proc.ExitCode). Logs: $fixture"
        }
        if (($case.Exit -ne 0 -or $case.Name -like 'skip-*') -and $output -match '全部通过') {
            throw "$($case.Name): misleading success summary. Logs: $fixture"
        }
        Write-Host "PASS $($case.Name)"
    }
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
Write-Host "check.ps1 contract: $($cases.Count) cases passed. Logs: $testRoot"
