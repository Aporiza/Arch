# In Vivado Behavioral Simulation:
# source E:/Xilinx/git_proj/Arch/exp15/wave_exp15.tcl
set CPU /tb_top/soc_lite/u_cpu
set CORE $CPU/u_core
catch {delete_waveforms}
catch {add_wave_divider {CLOCK AND PIPELINE}}
add_wave $CPU/aclk $CPU/aresetn
foreach stage {if_id id_ex ex_mem mem_wb} {
    add_wave $CORE/${stage}_valid
    add_wave -radix hex $CORE/${stage}_pc
}
catch {add_wave_divider {SRAM ACCEPT AND COMPLETE}}
foreach port {inst data} {
    add_wave $CPU/${port}_sram_req $CPU/${port}_sram_addr_ok $CPU/${port}_sram_data_ok
    add_wave -radix hex $CPU/${port}_sram_addr $CPU/${port}_sram_rdata
}
add_wave $CPU/data_sram_wr
catch {add_wave_divider {AXI READ}}
add_wave $CPU/arvalid $CPU/arready $CPU/rvalid $CPU/rready
add_wave -radix hex $CPU/arid $CPU/araddr $CPU/arsize $CPU/rid $CPU/rdata
catch {add_wave_divider {AXI WRITE}}
add_wave $CPU/awvalid $CPU/awready $CPU/wvalid $CPU/wready $CPU/bvalid $CPU/bready
add_wave -radix hex $CPU/awaddr $CPU/awsize $CPU/wdata $CPU/wstrb
catch {add_wave_divider {BRIDGE AND REDIRECT}}
add_wave $CPU/u_bridge/state $CPU/u_bridge/owner_data
add_wave $CPU/u_bridge/aw_pending $CPU/u_bridge/w_pending
add_wave $CORE/u_if/fetch_pending $CORE/u_if/discard_pending $CORE/u_if/inst_buf_valid
add_wave $CORE/br_taken $CORE/flush
