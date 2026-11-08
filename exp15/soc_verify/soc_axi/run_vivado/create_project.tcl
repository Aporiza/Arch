# Paths are relative to this script, so it can be sourced from any Tcl directory.
set RUN_DIR [file dirname [file normalize [info script]]]
set OLD_DIR [pwd]
cd $RUN_DIR
create_project -force loongson ./project -part xc7a200tfbg676-1

# Add conventional sources
add_files -scan_for_includes [glob -nocomplain ../rtl/*.v]
add_files -scan_for_includes [glob -nocomplain ../rtl/*/*.v]

# Add IPs
add_files -quiet [glob -nocomplain ../rtl/xilinx_ip/*/*.xci]

# Add simulation files
add_files -fileset sim_1 ../testbench

# Add myCPU
add_files -quiet -scan_for_includes ../../../myCPU
set_property include_dirs [list [file normalize ../../../myCPU]] [current_fileset]
set_property top soc_lite_top [current_fileset]

# Add constraints
add_files -fileset constrs_1 -quiet ./constraints

set_property -name "top" -value "tb_top" -objects  [get_filesets sim_1]
set_property -name "xsim.simulate.log_all_signals" -value "1" -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
cd $OLD_DIR
