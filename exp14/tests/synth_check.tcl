# 在临时工作目录运行；只综合 CPU RTL，不生成 bit，不替代板级时序检查。
set CPU [file normalize [file join [file dirname [info script]] ../myCPU]]
set_property include_dirs [list $CPU] [current_fileset]
read_verilog [glob $CPU/*.v]
synth_design -top mycpu_top -part xc7a200tfbg676-1 -mode out_of_context
create_clock -name cpu_clk -period 20.000 [get_ports clk]
report_utilization -file cpu_utilization.rpt
report_timing_summary -file cpu_timing.rpt
set latches [get_cells -quiet -hier -filter {REF_NAME =~ LD*}]
if {[llength $latches] != 0} {
    error "Unexpected RTL latches: $latches"
}
puts "EXP14_SYNTH_PASS: CPU synthesis completed without latches"
