// EX：选择 ALU 操作数并执行运算，保存 EX/MEM 流水寄存器。
// 存储数据、目的寄存器号和后续阶段控制位随指令一起传递。
module ex_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         flush,

    // 来自 ID/EX 的操作数与控制信号
    input  wire         id_ex_valid,
    input  wire [31:0]  id_ex_pc,
    input  wire [31:0]  id_ex_rj_value,
    input  wire [31:0]  id_ex_rkd_value,
    input  wire [31:0]  id_ex_imm,
    input  wire [18:0]  id_ex_alu_op,
    input  wire         id_ex_src1_is_pc,
    input  wire         id_ex_src2_is_imm,
    input  wire         id_ex_res_from_mem,
    input  wire         id_ex_mem_we,
    input  wire [1:0]   id_ex_mem_size,
    input  wire         id_ex_load_unsigned,
    input  wire         id_ex_gr_we,
    input  wire [4:0]   id_ex_dest,
    input  wire [83:0]  id_ex_csr_bus,
    input  wire [38:0]  id_ex_ex_bus,

    // 除法未完成时阻止 ID/EX 接收下一条指令。
    output wire         allow_in,

    // 当前 EX 指令的相关信息反馈给 ID。
    // 算术/逻辑结果可直接前递；load 和 CSR 结果需等待 WB。
    output wire         ex_pending_we,
    output wire [4:0]   ex_pending_dest,
    output wire         ex_forward_we,
    output wire [4:0]   ex_forward_dest,
    output wire [31:0]  ex_forward_data,

    // EX/MEM 寄存器输出，供 MEM 阶段使用
    output reg          ex_mem_valid,
    output reg  [31:0]  ex_mem_pc,
    output reg  [31:0]  ex_mem_alu_result,
    output reg  [31:0]  ex_mem_store_data,
    output reg          ex_mem_res_from_mem,
    output reg          ex_mem_mem_we,
    output reg  [1:0]   ex_mem_mem_size,
    output reg          ex_mem_load_unsigned,
    output reg          ex_mem_gr_we,
    output reg  [4:0]   ex_mem_dest,
    output reg  [83:0]  ex_mem_csr_bus,
    output reg  [38:0]  ex_mem_ex_bus
);
// ALU 操作数选择：PC 或寄存器值，立即数或第二个寄存器值
wire [31:0]  alu_result;
wire         is_div = |id_ex_alu_op[18:15];
wire         div_complete;
reg          div_started;
wire [31:0]  div_quotient;
wire [31:0]  div_remainder;
wire [31:0]  ex_result = is_div
                       ? ((id_ex_alu_op[15] | id_ex_alu_op[17])
                          ? div_quotient : div_remainder)
                       : alu_result;

// complete 属于已启动的这条指令；不能让下一条除法消费旧完成标志。
assign allow_in = !id_ex_valid || !is_div || (div_started && div_complete);
assign ex_pending_we   = resetn && !flush && id_ex_valid && id_ex_gr_we &&
                         (id_ex_res_from_mem || (|id_ex_csr_bus[83:81]) ||
                          (is_div && !div_complete)) &&
                         (id_ex_dest != 5'd0);
assign ex_pending_dest = id_ex_dest;
wire [31:0]  alu_src1 = id_ex_src1_is_pc ? id_ex_pc : id_ex_rj_value;
wire [31:0]  alu_src2 = id_ex_src2_is_imm ? id_ex_imm : id_ex_rkd_value;
// 在发出数据 SRAM 请求之前检查地址对齐。字节访问始终对齐。
wire ale = (id_ex_res_from_mem || id_ex_mem_we) &&
           (((id_ex_mem_size == 2'b10) && (|alu_result[1:0])) ||
            ((id_ex_mem_size == 2'b01) && alu_result[0]));
wire ex_exception = id_ex_ex_bus[38] || ale;

alu u_alu (
    .alu_op     (id_ex_alu_op),
    .alu_src1   (alu_src1),
    .alu_src2   (alu_src2),
    .alu_result (alu_result)
);

divider u_divider (
    // 同步取消被异常冲刷的除法，避免旧 complete 污染处理程序中的除法。
    .clk       (clk),
    .resetn    (resetn && !flush),
    .start     (resetn && !flush && id_ex_valid && is_div && !div_started),
    .is_signed (id_ex_alu_op[15] | id_ex_alu_op[16]),
    .dividend  (id_ex_rj_value),
    .divisor   (id_ex_rkd_value),
    .complete  (div_complete),
    .quotient  (div_quotient),
    .remainder (div_remainder)
);

always @(posedge clk) begin
    if (!resetn || flush)
        div_started <= 1'b0;
    else if (id_ex_valid && is_div && !div_started)
        div_started <= 1'b1;
    else if (allow_in)
        div_started <= 1'b0;
end

assign ex_forward_we   = resetn && !flush && id_ex_valid && id_ex_gr_we &&
                         !id_ex_res_from_mem && !(|id_ex_csr_bus[83:81]) &&
                         !ex_exception && allow_in &&
                         (id_ex_dest != 5'd0);
assign ex_forward_dest = id_ex_dest;
assign ex_forward_data = ex_result;

// EX/MEM：ALU 结果用于算术写回或访存地址。
// store_data 直接传递第二个源寄存器值，不使用经过立即数选择的 alu_src2。
always @(posedge clk) begin
    if (~resetn || flush)
        ex_mem_valid <= 1'b0;
    else begin
        ex_mem_valid        <= id_ex_valid && allow_in;
        ex_mem_pc           <= id_ex_pc;
        ex_mem_alu_result   <= ex_result;
        ex_mem_store_data   <= id_ex_rkd_value;
        ex_mem_res_from_mem <= id_ex_res_from_mem && !ex_exception;
        ex_mem_mem_we       <= id_ex_mem_we && !ex_exception;
        ex_mem_mem_size     <= id_ex_mem_size;
        ex_mem_load_unsigned <= id_ex_load_unsigned;
        ex_mem_gr_we        <= id_ex_gr_we && !ex_exception;
        ex_mem_dest         <= id_ex_dest;
        ex_mem_csr_bus      <= id_ex_csr_bus;
        ex_mem_ex_bus       <= id_ex_ex_bus[38] ? id_ex_ex_bus :
                               {ale, 6'h09, alu_result};
    end
end

endmodule
