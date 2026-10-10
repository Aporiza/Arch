`timescale 1ns / 1ps

module ex_divider_tb;
reg         clk = 1'b0;
reg         resetn = 1'b0;
reg         id_ex_valid = 1'b0;
reg  [31:0] id_ex_pc = 32'b0;
reg  [31:0] id_ex_rj_value = 32'b0;
reg  [31:0] id_ex_rkd_value = 32'b0;
reg  [18:0] id_ex_alu_op = 19'b0;
wire        allow_in;
wire        ex_mem_valid;
wire [31:0] ex_mem_pc;
wire [31:0] ex_mem_alu_result;

always #5 clk = ~clk;

ex_stage dut (
    .clk                 (clk),
    .resetn              (resetn),
    .id_ex_valid         (id_ex_valid),
    .id_ex_pc            (id_ex_pc),
    .id_ex_rj_value      (id_ex_rj_value),
    .id_ex_rkd_value     (id_ex_rkd_value),
    .id_ex_imm           (32'b0),
    .id_ex_alu_op        (id_ex_alu_op),
    .id_ex_src1_is_pc    (1'b0),
    .id_ex_src2_is_imm   (1'b0),
    .id_ex_res_from_mem  (1'b0),
    .id_ex_mem_we        (1'b0),
    .id_ex_gr_we         (1'b1),
    .id_ex_dest          (5'd1),
    .allow_in            (allow_in),
    .ex_pending_we       (),
    .ex_pending_dest     (),
    .ex_forward_we       (),
    .ex_forward_dest     (),
    .ex_forward_data     (),
    .ex_mem_valid        (ex_mem_valid),
    .ex_mem_pc           (ex_mem_pc),
    .ex_mem_alu_result   (ex_mem_alu_result),
    .ex_mem_store_data   (),
    .ex_mem_res_from_mem (),
    .ex_mem_mem_we       (),
    .ex_mem_gr_we        (),
    .ex_mem_dest         ()
);

reg [18:0] op [0:4];
reg [31:0] lhs [0:4];
reg [31:0] rhs [0:4];
reg [31:0] expected [0:4];
integer sent = 0;
integer received = 0;
integer cycles = 0;

initial begin
    op[0] = 19'b1 << 15; lhs[0] = -32'd13; rhs[0] = 32'd5;
    expected[0] = -32'd2;
    op[1] = 19'b1 << 17; lhs[1] = 32'hffff_ffff; rhs[1] = 32'd3;
    expected[1] = 32'h5555_5555;
    op[2] = 19'b1 << 16; lhs[2] = 32'd13; rhs[2] = -32'd5;
    expected[2] = 32'd3;
    op[3] = 19'b1 << 15; lhs[3] = 32'd9; rhs[3] = 32'b0;
    expected[3] = 32'hffff_ffff;
    op[4] = 19'b1; lhs[4] = 32'd3; rhs[4] = 32'd4;
    expected[4] = 32'd7;
    repeat (2) @(negedge clk);
    resetn = 1'b1;
end

always @(posedge clk) begin
    if (resetn && allow_in) begin
        id_ex_valid <= sent < 5;
        if (sent < 5) begin
            id_ex_pc        <= 32'h100 + sent * 4;
            id_ex_alu_op    <= op[sent];
            id_ex_rj_value  <= lhs[sent];
            id_ex_rkd_value <= rhs[sent];
            sent <= sent + 1;
        end
    end
    if (resetn) begin
        cycles <= cycles + 1;
        if (cycles > 180) begin
            $display("FAIL: EX divider timeout, received=%0d", received);
            $finish;
        end
    end
end

always @(negedge clk) begin
    if (resetn && ex_mem_valid) begin
        if (received >= 5 || ex_mem_pc !== (32'h100 + received * 4) ||
            ex_mem_alu_result !== expected[received]) begin
            $display("FAIL: output %0d pc=%h result=%h", received,
                     ex_mem_pc, ex_mem_alu_result);
            $finish;
        end
        received = received + 1;
        if (received == 5) begin
            $display("PASS: consecutive EX divide, mod, zero and add");
            $finish;
        end
    end
end

endmodule
