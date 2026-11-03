# 使用官方 func、golden_trace 和随机延迟包装器；只在临时目录替换文件路径及种子。
param(
    [string]$VivadoBin = 'D:/Xilinx/Vivado/2019.2/bin',
    [string]$BuildDir = (Join-Path $env:TEMP 'arch-exp14-func'),
    [ValidatePattern('^[0-7][0-9a-fA-F]{5}$')]
    [string]$Seed = '5501ff',
    [switch]$CornerCases
)
$ErrorActionPreference = 'Stop'
$expRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtl = Join-Path $expRoot 'soc_verify/soc_hs_bram/rtl'
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
$BuildDir = (Resolve-Path -LiteralPath $BuildDir).Path
$rootForVerilog = $expRoot.Replace('\', '/')
$utf8 = New-Object System.Text.UTF8Encoding($false)

$tb = [IO.File]::ReadAllText((Join-Path $expRoot 'soc_verify/soc_hs_bram/testbench/mycpu_tb.v'))
$tb = $tb.Replace('../../../../../../../../gettrace/golden_trace.txt', "$rootForVerilog/gettrace/golden_trace.txt")
$tb = $tb.Replace('    $dumpfile("dump.vcd");', '').Replace('    $dumpvars;', '')
$tb = $tb.Replace('#10000;', '#1000000;')
$tb = $tb.Replace('    trace_ref = $fopen(`TRACE_REF_FILE, "r");',
    '    trace_ref = $fopen(`TRACE_REF_FILE, "r"); if (!trace_ref) $fatal(1, "Cannot open golden trace");')
$tb = $tb.Replace('module tb_top( );', 'module tb_top( ); exp14_protocol_monitor monitor(); initial begin #200000000; $fatal(1, "Simulation timeout"); end')
[IO.File]::WriteAllText((Join-Path $BuildDir 'mycpu_tb.v'), $tb, $utf8)
$ram = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ram_model.v'))
$ram = $ram.Replace('../../../../../../../../func/obj/', "$rootForVerilog/func/obj/")
[IO.File]::WriteAllText((Join-Path $BuildDir 'ram_model.v'), $ram, $utf8)
$confreg = [IO.File]::ReadAllText((Join-Path $rtl 'CONFREG/confreg.v'))
$confreg = [regex]::Replace($confreg, '(?m)^`define RANDOM_SEED[^\r\n]*', ('`define RANDOM_SEED 23''h' + $Seed))
[IO.File]::WriteAllText((Join-Path $BuildDir 'confreg.v'), $confreg, $utf8)
[IO.File]::WriteAllText((Join-Path $BuildDir 'run.tcl'), "run all`nquit`n", $utf8)
$sources = @(Get-ChildItem (Join-Path $expRoot 'myCPU/*.v') | ForEach-Object FullName)
$sources += (Join-Path $rtl 'soc_lite_top.v'), (Join-Path $rtl 'BRIDGE/bridge_1x2.v')
$sources += (Join-Path $rtl 'ram_wrap/sram_wrap.v'), (Join-Path $BuildDir 'confreg.v')
$sources += (Join-Path $BuildDir 'ram_model.v'), (Join-Path $BuildDir 'mycpu_tb.v')
$snapshot = 'exp14_func'
$top = 'work.tb_top'
if ($CornerCases) {
    $sources = @(Get-ChildItem (Join-Path $expRoot 'myCPU/*.v') | ForEach-Object FullName)
    $snapshot = 'exp14_corner'
    $top = 'work.stage_corner_tb'
}
Push-Location -LiteralPath $BuildDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --relax -i (Join-Path $expRoot 'myCPU') @sources
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
    $testSource = if ($CornerCases) { 'stage_corner_tb.sv' } else { 'protocol_monitor.sv' }
    & (Join-Path $VivadoBin 'xvlog.bat') -sv (Join-Path $PSScriptRoot $testSource)
    if ($LASTEXITCODE -ne 0) { throw 'Protocol monitor compilation failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --mt off --debug typical --timescale 1ns/1ps --snapshot $snapshot $top
    if ($LASTEXITCODE -ne 0) { throw 'Design elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') $snapshot --tclbatch run.tcl --log func.log
    if ($LASTEXITCODE -ne 0) { throw 'XSim failed' }
    $log = [IO.File]::ReadAllText((Join-Path $BuildDir 'func.log'))
    if ($CornerCases) {
        if ($log -notmatch 'EXP14_CORNER_PASS' -or $log -match 'Fatal:|Error:') {
            throw "Corner tests failed. See $BuildDir/func.log"
        }
        Write-Output "PASS: directed stage corner cases. Log: $BuildDir/func.log"
        return
    }
    $passes = [regex]::Matches($log, 'Functional Test Point PASS!!!').Count
    if ($log -notmatch '----PASS!!!' -or $log -match 'Error!!!|Fail!!!|Fatal:|Error\(' -or $passes -ne 58) {
        throw "Functional test failed ($passes/58 passed). See $BuildDir/func.log"
    }
    Write-Output "PASS: 58/58 functional test points, seed=$Seed. Log: $BuildDir/func.log"
} finally {
    Pop-Location
}
