# 启动 Behavioral Simulation 后执行：
# source D:/Desktop/Vivado_prj/exp14/wave_exp14.tcl
# 采用 Vivado 2019.2 的 add_wave 写法，只展示流水推进和访存等待。
set CPU /tb_top/soc_lite/cpu
catch {delete_waveforms}

catch {add_wave_divider {PIPELINE}}
add_wave $CPU/clk
add_wave $CPU/resetn
foreach stage {if_id id_ex ex_mem mem_wb} {
    add_wave $CPU/${stage}_valid
    add_wave -radix hex $CPU/${stage}_pc
}

# ready_go 留在模块内部，但仍可以通过层次路径观察。
catch {add_wave_divider {HANDSHAKE}}
add_wave $CPU/id_allow_in
add_wave $CPU/ex_allow_in
add_wave $CPU/mem_allow_in
foreach stage {if id ex mem} {
    add_wave $CPU/u_${stage}/ready_go
}
add_wave $CPU/u_id/hazard_rj
add_wave $CPU/u_id/hazard_rkd

# req && addr_ok 是地址接受；data_ok 是之前请求的完成响应。
catch {add_wave_divider {MEMORY REQUEST AND RESPONSE}}
foreach port {inst data} {
    add_wave $CPU/${port}_sram_req
    add_wave $CPU/${port}_sram_addr_ok
    add_wave $CPU/${port}_sram_data_ok
    add_wave -radix hex $CPU/${port}_sram_addr
}
add_wave $CPU/data_sram_wr

catch {add_wave_divider {BUFFER AND REDIRECT}}
add_wave $CPU/u_if/fetch_pending
add_wave $CPU/u_if/inst_buf_valid
add_wave $CPU/u_if/discard_pending
add_wave $CPU/br_stall
add_wave $CPU/br_taken
add_wave $CPU/flush
