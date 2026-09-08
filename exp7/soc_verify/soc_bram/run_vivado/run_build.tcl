open_project ./project/loongson.xpr
set_property top soc_lite_top [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "implementation/bitstream failed: [get_property STATUS [get_runs impl_1]]"
}
puts "TASK7_BUILD_PASS"
close_project
