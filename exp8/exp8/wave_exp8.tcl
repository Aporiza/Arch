# exp8 五级流水线波形脚本（写法参照 exp7/wave_cpu.tcl）
# Behavioral Simulation 启动后执行：
# source D:/Desktop/Vivado_prj/exp8/exp8/wave_exp8.tcl

set CPU /tb_top/soc_lite/cpu
catch {delete_waveforms}

# 1. 流水线是否前进：valid 和各级指令 PC
catch {add_wave_divider {PIPELINE VALID AND PC}}
add_wave /tb_top/soc_lite/cpu_clk
add_wave /tb_top/soc_lite/cpu_resetn
add_wave -radix hex $CPU/u_if/pc
add_wave $CPU/if_id_valid
add_wave -radix hex $CPU/if_id_pc
add_wave $CPU/id_ex_valid
add_wave -radix hex $CPU/id_ex_pc
add_wave $CPU/ex_mem_valid
add_wave -radix hex $CPU/ex_mem_pc
add_wave $CPU/mem_wb_valid
add_wave -radix hex $CPU/mem_wb_pc

# 2. 五级握手：观察阻塞从 ID 传回 IF，以及后级是否继续运行
catch {add_wave_divider {STAGE HANDSHAKE}}
add_wave $CPU/u_if/allow_in
add_wave $CPU/u_if/ready_go
add_wave $CPU/u_id/allow_in
add_wave $CPU/u_id/ready_go
add_wave $CPU/u_ex/allow_in
add_wave $CPU/u_ex/ready_go
add_wave $CPU/u_mem/allow_in
add_wave $CPU/u_mem/ready_go
add_wave $CPU/u_wb/allow_in
add_wave $CPU/u_wb/ready_go

# 3. 数据相关：当前指令源寄存器与各级待写目的寄存器
catch {add_wave_divider {DATA HAZARD}}
add_wave $CPU/u_id/use_rj
add_wave $CPU/u_id/use_rkd
add_wave $CPU/u_id/hazard_rj
add_wave $CPU/u_id/hazard_rkd
add_wave -radix unsigned $CPU/u_id/rj
add_wave -radix unsigned $CPU/u_id/rf_raddr2
add_wave $CPU/ex_pending_we
add_wave -radix unsigned $CPU/ex_pending_dest
add_wave $CPU/mem_pending_we
add_wave -radix unsigned $CPU/mem_pending_dest
add_wave $CPU/rf_we
add_wave -radix unsigned $CPU/rf_waddr
