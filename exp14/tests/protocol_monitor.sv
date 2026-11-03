// 与官方 golden trace 并行的协议检查，不改变官方测试程序或随机延迟。
`define CPU tb_top.soc_lite.cpu
module exp14_protocol_monitor;
integer inst_owed = 0;
integer data_owed = 0;
integer inst_wait = 0, data_addr_wait = 0, data_wait = 0;
integer buffered = 0, discarded = 0, div_held = 0, counter_reads = 0;
reg ex_held = 0, mem_held = 0, id_held = 0;
reg [31:0] old_ex_pc, old_mem_pc, old_id_pc, old_id_inst;
reg [31:0] old_ex_src1, old_ex_src2, old_mem_result;
wire i_accept = `CPU.inst_sram_req && `CPU.inst_sram_addr_ok;
wire d_accept = `CPU.data_sram_req && `CPU.data_sram_addr_ok;
always @(posedge `CPU.clk) begin
    if (!`CPU.resetn) begin
        inst_owed = 0;
        data_owed = 0;
        ex_held = 0;
        mem_held = 0;
        id_held = 0;
    end else begin
        // 已接收的事务必须恰有一次返回；本实现每端口最多欠一笔响应。
        if (`CPU.inst_sram_data_ok) begin
            if (inst_owed != 1) $fatal(1, "Unmatched instruction response");
            inst_owed = inst_owed - 1;
        end
        if (`CPU.data_sram_data_ok) begin
            if (data_owed != 1) $fatal(1, "Unmatched data response");
            data_owed = data_owed - 1;
        end
        if (i_accept) inst_owed = inst_owed + 1;
        if (d_accept) data_owed = data_owed + 1;
        if (inst_owed > 1 || data_owed > 1) $fatal(1, "Too many outstanding requests");
        if (`CPU.flush && (`CPU.inst_sram_req || `CPU.data_sram_req))
            $fatal(1, "Request issued during exception flush");

        // 在上一个边沿未获准交接的流水项，本拍仍应保持原数据。
        if (ex_held && (`CPU.id_ex_pc !== old_ex_pc ||
            `CPU.id_ex_rj_value !== old_ex_src1 || `CPU.id_ex_rkd_value !== old_ex_src2))
            $fatal(1, "EX payload changed while stalled");
        if (mem_held && (`CPU.ex_mem_pc !== old_mem_pc || `CPU.ex_mem_alu_result !== old_mem_result))
            $fatal(1, "MEM payload changed while stalled");
        if (id_held && (`CPU.if_id_pc !== old_id_pc || `CPU.if_id_inst !== old_id_inst))
            $fatal(1, "ID payload changed while stalled");
        ex_held = !`CPU.flush && `CPU.id_ex_valid && !`CPU.ex_allow_in;
        mem_held = !`CPU.flush && `CPU.ex_mem_valid && !`CPU.mem_allow_in;
        id_held = !`CPU.flush && !`CPU.br_taken && `CPU.if_id_valid && !`CPU.id_allow_in;
        old_ex_pc = `CPU.id_ex_pc;
        old_ex_src1 = `CPU.id_ex_rj_value;
        old_ex_src2 = `CPU.id_ex_rkd_value;
        old_mem_pc = `CPU.ex_mem_pc;
        old_mem_result = `CPU.ex_mem_alu_result;
        old_id_pc = `CPU.if_id_pc;
        old_id_inst = `CPU.if_id_inst;

        if (`CPU.inst_sram_req && !`CPU.inst_sram_addr_ok) inst_wait++;
        if (`CPU.data_sram_req && !`CPU.data_sram_addr_ok) data_addr_wait++;
        if (data_owed && !`CPU.data_sram_data_ok) data_wait++;
        if (`CPU.u_if.return_valid && !`CPU.id_allow_in && !`CPU.u_if.redirect_i) buffered++;
        if (`CPU.u_if.response && (`CPU.u_if.discard_pending || `CPU.u_if.redirect_i)) discarded++;
        if (`CPU.u_ex.div_ready && !`CPU.mem_allow_in) div_held++;
        // 官方 trace 对随时间变化的计数值关闭比对，这里单独防止计数器漏写回。
        if (`CPU.rf_we && |`CPU.mem_wb_csr_bus[83:82]) begin
            counter_reads++;
            if (`CPU.mem_wb_csr_bus[82] && `CPU.rf_wdata !== `CPU.u_wb.stable_counter[31:0])
                $fatal(1, "rdcntvl writeback mismatch");
            if (`CPU.mem_wb_csr_bus[83] && `CPU.rf_wdata !== `CPU.u_wb.stable_counter[63:32])
                $fatal(1, "rdcntvh writeback mismatch");
        end
    end
end
final begin
    $display("PROTOCOL_COVER inst_addr_wait=%0d data_addr_wait=%0d data_wait=%0d buffer=%0d discard=%0d div_hold=%0d counter=%0d",
        inst_wait, data_addr_wait, data_wait, buffered, discarded, div_held, counter_reads);
end
endmodule
`undef CPU
