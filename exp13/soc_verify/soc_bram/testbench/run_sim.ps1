# Run the supplied exp13 func/trace with Vivado XSim and behavioral SRAMs.
# Generated sources, snapshots and logs stay in the temporary build directory.
param(
    [string]$VivadoBin = 'E:/Xilinx/Vivado/2019.2/bin',
    [string]$BuildDir = (Join-Path $env:TEMP 'arch-exp13-func'),
    [switch]$HardwareInterrupts
)
$ErrorActionPreference = 'Stop'
$expRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
$BuildDir = (Resolve-Path -LiteralPath $BuildDir).Path
$rootForVerilog = $expRoot.Replace('\', '/')
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Change only file locations and waveform/progress verbosity in the temporary
# testbench. Keep the supplied golden-trace and test-score comparisons intact.
$tb = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'mycpu_tb.v'))
$tb = $tb.Replace('../../../../../../../../gettrace/golden_trace.txt', "$rootForVerilog/gettrace/golden_trace.txt")
$tb = $tb.Replace('    $dumpfile("dump.vcd");', '').Replace('    $dumpvars;', '')
$tb = $tb.Replace('#10000;', '#1000000;')
$tb = $tb.Replace('    trace_ref = $fopen(`TRACE_REF_FILE, "r");',
    '    trace_ref = $fopen(`TRACE_REF_FILE, "r"); if (!trace_ref) $fatal(1, "Cannot open golden trace");')
$tb = $tb.Replace('module tb_top( );', 'module tb_top( ); initial begin #200000000; $fatal(1, "Simulation timeout"); end')
[IO.File]::WriteAllText((Join-Path $BuildDir 'mycpu_tb.v'), $tb, $utf8)
$ram = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'sync_ram.v'))
$ram = $ram.Replace('../../../../../../../../func/obj/', "$rootForVerilog/func/obj/")
[IO.File]::WriteAllText((Join-Path $BuildDir 'sync_ram.v'), $ram, $utf8)
[IO.File]::WriteAllText((Join-Path $BuildDir 'run.tcl'), "run all`nquit`n", $utf8)
$sources = @(Get-ChildItem (Join-Path $expRoot 'myCPU/*.v') | ForEach-Object FullName)
$sources += (Join-Path $PSScriptRoot '../rtl/soc_lite_top.v')
$sources += (Join-Path $PSScriptRoot '../rtl/BRIDGE/bridge_1x2.v')
$sources += (Join-Path $PSScriptRoot '../rtl/CONFREG/confreg.v')
$sources += (Join-Path $BuildDir 'sync_ram.v'), (Join-Path $BuildDir 'mycpu_tb.v')
$snapshot = 'exp13_func'
$top = 'work.tb_top'
$logName = 'func.log'
if ($HardwareInterrupts) {
    $sources = @(Get-ChildItem (Join-Path $expRoot 'myCPU/*.v') | ForEach-Object FullName)
    $sources += (Join-Path $PSScriptRoot 'exp13_irq_tb.v')
    $snapshot = 'exp13_irq'
    $top = 'work.exp13_irq_tb'
    $logName = 'irq.log'
}
Push-Location -LiteralPath $BuildDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') @sources
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --mt off --debug typical --timescale 1ns/1ps --snapshot $snapshot $top
    if ($LASTEXITCODE -ne 0) { throw 'Design elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') $snapshot --tclbatch run.tcl --log $logName
    if ($LASTEXITCODE -ne 0) { throw 'XSim failed' }
    $log = [IO.File]::ReadAllText((Join-Path $BuildDir $logName))
    if ($HardwareInterrupts) {
        if ($log -notmatch 'EXP13_IRQ_PASS' -or $log -match 'Fatal:|Error:') {
            throw "Hardware interrupt test failed. See $BuildDir/$logName"
        }
        Write-Output "PASS: eight hardware IRQs, masking and precise store cancellation. Log: $BuildDir/$logName"
        return
    }
    $passes = [regex]::Matches($log, 'Functional Test Point PASS!!!').Count
    if ($log -notmatch '----PASS!!!' -or $log -match 'Error!!!|Fail!!!|Fatal:|Error\(' -or $passes -ne 58) {
        throw "Functional test failed ($passes/58 passed). See $BuildDir/func.log"
    }
    Write-Output "PASS: 58/58 functional test points. Log: $BuildDir/func.log"
} finally {
    Pop-Location
}
