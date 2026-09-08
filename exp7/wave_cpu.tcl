# Exp7 pipeline-register waveform setup for Vivado 2019.2.
# Run after opening Behavioral Simulation:
# source D:/Desktop/Vivado_prj/exp7/wave_cpu.tcl

catch {remove_wave [get_waves *]}
restart

# The stage PCs and valid bits make pipeline movement easy to see.
catch {add_wave_divider {PIPELINE OVERVIEW}}
add_wave /tb_top/soc_lite/cpu_clk
add_wave /tb_top/soc_lite/cpu_resetn
add_wave -radix hex /tb_top/soc_lite/cpu/pc
add_wave /tb_top/soc_lite/cpu/if_id_valid
add_wave -radix hex /tb_top/soc_lite/cpu/if_id_pc
add_wave /tb_top/soc_lite/cpu/id_ex_valid
add_wave -radix hex /tb_top/soc_lite/cpu/id_ex_pc
add_wave /tb_top/soc_lite/cpu/ex_mem_valid
add_wave -radix hex /tb_top/soc_lite/cpu/ex_mem_pc
add_wave /tb_top/soc_lite/cpu/mem_wb_valid
add_wave -radix hex /tb_top/soc_lite/cpu/mem_wb_pc

catch {add_wave_divider {IF ID REGISTER}}
add_wave -radix hex /tb_top/soc_lite/cpu/if_id_inst

catch {add_wave_divider {ID EX REGISTER}}
add_wave -radix hex /tb_top/soc_lite/cpu/id_ex_rj_value
add_wave -radix hex /tb_top/soc_lite/cpu/id_ex_rkd_value
add_wave -radix hex /tb_top/soc_lite/cpu/id_ex_imm
add_wave -radix hex /tb_top/soc_lite/cpu/id_ex_alu_op
add_wave -radix unsigned /tb_top/soc_lite/cpu/id_ex_dest

catch {add_wave_divider {EX MEM REGISTER}}
add_wave -radix hex /tb_top/soc_lite/cpu/ex_mem_alu_result
add_wave -radix hex /tb_top/soc_lite/cpu/ex_mem_store_data
add_wave -radix unsigned /tb_top/soc_lite/cpu/ex_mem_dest

catch {add_wave_divider {MEM WB REGISTER}}
add_wave -radix hex /tb_top/soc_lite/cpu/mem_wb_alu_result
add_wave -radix unsigned /tb_top/soc_lite/cpu/mem_wb_dest

run 5 us
