// EX：选择 ALU 操作数并执行运算，保存 EX/MEM 流水寄存器。
// 存储数据、目的寄存器号和后续阶段控制位随指令一起传递。
module ex_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         allow_in,

    // 来自 ID/EX 的操作数与控制信号
    input  wire         id_ex_valid,
    input  wire [31:0]  id_ex_pc,
    input  wire [31:0]  id_ex_rj_value,
    input  wire [31:0]  id_ex_rkd_value,
    input  wire [31:0]  id_ex_imm,
    input  wire [11:0]  id_ex_alu_op,
    input  wire         id_ex_src1_is_pc,
    input  wire         id_ex_src2_is_imm,
    input  wire         id_ex_res_from_mem,
    input  wire         id_ex_mem_we,
    input  wire         id_ex_gr_we,
    input  wire [4:0]   id_ex_dest,

    // 当前 EX 指令的写回意图，反馈给 ID；不前递运算结果。
    output wire         ex_pending_we,
    output wire [4:0]   ex_pending_dest,
    output wire         ready_go,

    // EX/MEM 寄存器输出，供 MEM 阶段使用
    output reg          ex_mem_valid,
    output reg  [31:0]  ex_mem_pc,
    output reg  [31:0]  ex_mem_alu_result,
    output reg  [31:0]  ex_mem_store_data,
    output reg          ex_mem_res_from_mem,
    output reg          ex_mem_mem_we,
    output reg          ex_mem_gr_we,
    output reg  [4:0]   ex_mem_dest
);
assign ready_go = 1'b1;

// ALU 操作数选择：PC 或寄存器值，立即数或第二个寄存器值
wire [31:0]  alu_result;
assign ex_pending_we   = resetn && id_ex_valid && id_ex_gr_we && (id_ex_dest != 5'd0);
assign ex_pending_dest = id_ex_dest;
wire [31:0]  alu_src1 = id_ex_src1_is_pc ? id_ex_pc : id_ex_rj_value;
wire [31:0]  alu_src2 = id_ex_src2_is_imm ? id_ex_imm : id_ex_rkd_value;

alu u_alu (
    .alu_op     (id_ex_alu_op),
    .alu_src1   (alu_src1),
    .alu_src2   (alu_src2),
    .alu_result (alu_result)
);

// EX/MEM：ALU 结果用于算术写回或访存地址。
// store_data 直接传递第二个源寄存器值，不使用经过立即数选择的 alu_src2。
always @(posedge clk) begin
    if (~resetn)
        ex_mem_valid <= 1'b0;
    else begin
        ex_mem_valid        <= id_ex_valid;
        ex_mem_pc           <= id_ex_pc;
        ex_mem_alu_result   <= alu_result;
        ex_mem_store_data   <= id_ex_rkd_value;
        ex_mem_res_from_mem <= id_ex_res_from_mem;
        ex_mem_mem_we       <= id_ex_mem_we;
        ex_mem_gr_we        <= id_ex_gr_we;
        ex_mem_dest         <= id_ex_dest;
    end
end

endmodule
