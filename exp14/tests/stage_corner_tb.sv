`timescale 1ns/1ps
// 定向制造 func 随机测试未必覆盖的边界：长访存阻塞跨过除法完成脉冲、
// 取指响应在 ID 堵塞时返回、多次重定向、冲刷当拍返回和 store 等待响应。
module stage_corner_tb;
reg clk = 0;
always #5 clk = !clk;
reg resetn = 0;
task tick;
    @(posedge clk); #1;
endtask
task drive;
    @(negedge clk);
endtask

reg id_allow = 1, redirect = 0, br_stall = 0;
reg [31:0] target = 0, inst_rdata = 0;
reg inst_addr_ok = 0, inst_data_ok = 0;
wire inst_req, if_valid;
wire [31:0] inst_addr, if_pc, if_inst;
if_stage u_if (
    .clk(clk), .resetn(resetn), .id_allow_in(id_allow), .br_stall(br_stall),
    .redirect_i(redirect), .redirect_pc_i(target), .inst_sram_req(inst_req),
    .inst_sram_addr(inst_addr), .inst_sram_addr_ok(inst_addr_ok),
    .inst_sram_data_ok(inst_data_ok), .inst_sram_rdata(inst_rdata),
    .if_id_valid(if_valid), .if_id_pc(if_pc), .if_id_inst(if_inst)
);

reg ex_valid = 0, mem_allow = 0, ex_flush = 0;
reg [31:0] dividend = 100, divisor = 3;
wire ex_allow, ex_out_valid;
wire [31:0] ex_result;
ex_stage u_ex (
    .clk(clk), .resetn(resetn), .flush(ex_flush), .mem_allow_in(mem_allow),
    .mem_req_block(1'b0), .id_ex_valid(ex_valid), .id_ex_pc(32'h1c001000),
    .id_ex_rj_value(dividend), .id_ex_rkd_value(divisor), .id_ex_imm(32'b0),
    .id_ex_alu_op(19'h08000), .id_ex_src1_is_pc(1'b0), .id_ex_src2_is_imm(1'b0),
    .id_ex_res_from_mem(1'b0), .id_ex_mem_we(1'b0), .id_ex_mem_size(2'b10),
    .id_ex_load_unsigned(1'b0), .id_ex_gr_we(1'b1), .id_ex_dest(5'd5),
    .id_ex_csr_bus(84'b0), .id_ex_ex_bus(38'b0), .data_sram_addr_ok(1'b0),
    .allow_in(ex_allow), .ex_mem_valid(ex_out_valid), .ex_mem_alu_result(ex_result)
);

reg mem_valid = 0, data_ok = 0;
wire mem_ready, wb_valid;
mem_stage u_mem (
    .clk(clk), .resetn(resetn), .flush(1'b0), .allow_in(mem_ready),
    .ex_mem_valid(mem_valid), .ex_mem_pc(32'h1c002000),
    .ex_mem_alu_result(32'h100), .ex_mem_store_data(32'h12345678),
    .ex_mem_res_from_mem(1'b0), .ex_mem_mem_we(1'b1), .ex_mem_mem_size(2'b10),
    .ex_mem_load_unsigned(1'b0), .ex_mem_gr_we(1'b0), .ex_mem_dest(5'b0),
    .ex_mem_csr_bus(84'b0), .ex_mem_ex_bus(38'b0),
    .data_sram_rdata(32'b0), .data_sram_data_ok(data_ok), .mem_wb_valid(wb_valid)
);

initial begin
    #100000; $fatal(1, "Corner test timeout");
end
initial begin
    repeat (3) tick();
    drive(); resetn = 1;
    // 地址不被接收时不可自增 PC。
    repeat (4) begin
        tick();
        if (!inst_req || inst_addr !== 32'h1c000000) $fatal(1, "IF address wait lost PC");
    end
    drive(); inst_addr_ok = 1;
    tick();
    drive(); inst_addr_ok = 0; id_allow = 0;
    inst_data_ok = 1; inst_rdata = 32'h12345678;
    tick();
    drive(); inst_data_ok = 0;
    repeat (4) begin
        tick();
        if (inst_req || if_valid) $fatal(1, "IF buffer overwritten or bypassed stalled ID");
    end
    drive(); id_allow = 1;
    tick();
    if (!if_valid || if_pc !== 32'h1c000000 || if_inst !== 32'h12345678)
        $fatal(1, "Buffered instruction lost");
    drive(); inst_addr_ok = 1;
    tick();
    drive(); inst_addr_ok = 0; redirect = 1; target = 32'h1c000100;
    tick();
    drive(); target = 32'h1c000200; // 连续第二次重定向必须覆盖第一次目标。
    tick();
    drive(); redirect = 0;
    repeat (3) begin
        tick();
        if (inst_req || if_valid) $fatal(1, "Cancelled fetch was not drained");
    end
    drive(); inst_data_ok = 1; inst_rdata = 32'hdeadbeef;
    tick();
    if (if_valid) $fatal(1, "Cancelled fetch reached ID");
    drive(); inst_data_ok = 0;
    if (!inst_req || inst_addr !== 32'h1c000200) $fatal(1, "Redirect target lost");
    inst_addr_ok = 1;
    tick();
    drive(); inst_addr_ok = 0; inst_data_ok = 1;
    redirect = 1; target = 32'h1c000300;
    tick(); // 响应与冲刷同拍，响应不能进入 ID，也不能再等待它一次。
    drive(); inst_data_ok = 0; redirect = 0;
    #1; // 驱动输入后留出组合逻辑传播时间，再检查 req。
    if (!inst_req || if_valid || inst_addr !== 32'h1c000300)
        $fatal(1, "Same-cycle redirect/response failed");
    br_stall = 1;
    #1;
    if (inst_req) $fatal(1, "Branch stall did not stop pre-IF");
    drive(); br_stall = 0; redirect = 1; target = 32'h1c000003;
    tick();
    drive(); redirect = 0;
    tick();
    if (inst_req || !if_valid || if_pc !== 32'h1c000003)
        $fatal(1, "Unaligned fetch must create ADEF without RAM request");
    drive(); br_stall = 1; id_allow = 0;

    // MEM 长时间阻塞，跨过除法器的一拍 complete，之后仍能正确交接商。
    ex_valid = 1;
    repeat (90) begin
        tick();
        if (ex_allow || ex_out_valid) $fatal(1, "EX advanced before MEM allowed");
    end
    drive(); mem_allow = 1;
    tick();
    if (!ex_out_valid || ex_result !== 32'd33) $fatal(1, "Division result lost during MEM stall");
    drive(); ex_valid = 0;
    tick();
    if (ex_out_valid) $fatal(1, "Division committed twice");

    // 取消半途执行的除法，新指令不能误用旧 complete 或旧结果。
    drive(); ex_valid = 1; dividend = 32'd1000; divisor = 32'd7;
    repeat (10) tick();
    drive(); ex_flush = 1;
    tick();
    drive(); ex_flush = 0; dividend = -32'd7; divisor = 32'd2;
    begin : wait_div
        integer cycles;
        cycles = 0;
        while (!ex_out_valid && cycles < 90) begin tick(); cycles++; end
        if (!ex_out_valid || ex_result !== 32'hfffffffd)
            $fatal(1, "Division flush/restart failed");
    end
    drive(); ex_valid = 0;
    tick();

    // store 也必须等待 data_ok，返回只应产生一次 WB 有效项。
    drive(); mem_valid = 1;
    repeat (5) begin
        tick();
        if (mem_ready || wb_valid) $fatal(1, "Store skipped its completion response");
    end
    drive(); data_ok = 1;
    tick();
    if (!wb_valid || !mem_ready) $fatal(1, "Store did not finish on data_ok");
    drive(); data_ok = 0; mem_valid = 0;
    tick();
    if (wb_valid) $fatal(1, "Store committed more than once");
    $display("EXP14_CORNER_PASS: IF buffer/redirect/ADEF, division stall/flush, store response");
    $finish;
end
endmodule
