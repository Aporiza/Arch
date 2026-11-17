// EX：运算、地址对齐检查和类 SRAM 地址请求，保存 EX/MEM 流水寄存器。
// 存储数据、目的寄存器号和后续阶段控制位随指令一起传递。
module ex_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         flush,
    input  wire         mem_allow_in,  // MEM 入口槽能否更新
    input  wire         mem_req_block, // 旧访存/异常/ertn 禁止年轻访存发请求

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
    input  wire [37:0]  id_ex_ex_bus,

    // 本级为空，或工作完成且 MEM 可接收时，才允许 ID 更新 ID/EX。
    output wire         allow_in,

    // 地址与写数据在 req && addr_ok 的上升沿一起被外部接收。
    output wire         data_sram_req,
    output wire         data_sram_wr,
    output wire [1:0]   data_sram_size,
    output wire [3:0]   data_sram_wstrb,
    output wire [31:0]  data_sram_addr,
    output wire [31:0]  data_sram_wdata,
    input  wire         data_sram_addr_ok,

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
    output reg  [37:0]  ex_mem_ex_bus
);
// ALU 操作数选择：PC 或寄存器值，立即数或第二个寄存器值
wire [31:0]  alu_result;
wire         is_div = |id_ex_alu_op[18:15];
wire         div_complete;
reg          div_started;
reg          div_done;
wire [31:0]  div_quotient;
wire [31:0]  div_remainder;
wire         ex_exception;
wire         addr_fire;
wire         is_memory_access = id_ex_res_from_mem || id_ex_mem_we;
wire [31:0]  ex_result = is_div
                       ? ((id_ex_alu_op[15] | id_ex_alu_op[17])
                          ? div_quotient : div_remainder)
                       : alu_result;

// complete 只有一拍；MEM 可能仍在等待响应，故必须锁存本条除法已完成。
// 普通运算当拍就绪，除法等待结果，合法访存等待地址握手。
// 异常访存不向 RAM 请求，直接把异常信息交给后级，避免永远等不到 addr_ok。
wire div_ready = div_started && (div_done || div_complete);
wire ready_go = (!is_div || div_ready) &&
                (!is_memory_access || ex_exception || addr_fire);
wire ex_to_mem_valid = id_ex_valid && ready_go;
wire ex_fire = ex_to_mem_valid && mem_allow_in;
// valid 表示当前 EX 槽中确有指令；ready_go 表示本条工作已经完成。
// 只有两者和 mem_allow_in 同时为 1 才真正向 MEM 交接。
// EX 为空则可以接收新指令，无需等待无效槽里的控制信号变为“就绪”。
assign allow_in = !id_ex_valid || (ready_go && mem_allow_in);
assign ex_pending_we   = resetn && !flush && id_ex_valid && id_ex_gr_we &&
                         (id_ex_res_from_mem || (|id_ex_csr_bus[83:81]) ||
                          (is_div && !div_ready)) &&
                         (id_ex_dest != 5'd0);
assign ex_pending_dest = id_ex_dest;
wire [31:0]  alu_src1 = id_ex_src1_is_pc ? id_ex_pc : id_ex_rj_value;
wire [31:0]  alu_src2 = id_ex_src2_is_imm ? id_ex_imm : id_ex_rkd_value;
// 在发出数据 SRAM 请求之前检查地址对齐。字节访问始终对齐。
wire ale = (id_ex_res_from_mem || id_ex_mem_we) &&
           (((id_ex_mem_size == 2'b10) && (|alu_result[1:0])) ||
            ((id_ex_mem_size == 2'b01) && alu_result[0]));
assign ex_exception = (|id_ex_ex_bus[37:32]) || ale;

// 最多一笔数据事务：仅在 MEM 能接收且没有旧事务/旧异常/ertn 时发请求。
// 地址一旦握手就必定同时进入 MEM，因此不需要在 EX 另设已发送标志，
// 也不会在下游堵塞时重复写 RAM。flush 当拍禁止一切新请求。
assign data_sram_req = resetn && !flush && id_ex_valid &&
                       is_memory_access && !ex_exception &&
                       mem_allow_in && !mem_req_block;
assign addr_fire = data_sram_req && data_sram_addr_ok;
assign data_sram_wr = id_ex_mem_we;
assign data_sram_size = id_ex_mem_size;
assign data_sram_addr = alu_result;
// size 和原始地址低位共同决定写入 lane，不能把字节/半字地址强行对齐。
assign data_sram_wstrb = (id_ex_mem_size == 2'b00) ? (4'b0001 << alu_result[1:0]) :
                         (id_ex_mem_size == 2'b01) ? (alu_result[1] ? 4'b1100 : 4'b0011) :
                                                                  4'b1111;
assign data_sram_wdata = (id_ex_mem_size == 2'b00) ? {4{id_ex_rkd_value[7:0]}} :
                         (id_ex_mem_size == 2'b01) ? {2{id_ex_rkd_value[15:0]}} :
                                                                   id_ex_rkd_value;

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
    if (!resetn || flush) begin
        div_started <= 1'b0;
        div_done <= 1'b0;
    end else if (ex_fire || !id_ex_valid) begin
        div_started <= 1'b0;
        div_done <= 1'b0;
    end else begin
        if (id_ex_valid && is_div && !div_started)
            div_started <= 1'b1;
        if (div_started && div_complete)
            div_done <= 1'b1;
    end
end

assign ex_forward_we   = resetn && !flush && id_ex_valid && id_ex_gr_we &&
                         !id_ex_res_from_mem && !(|id_ex_csr_bus[83:81]) &&
                         !ex_exception && ready_go &&
                         (id_ex_dest != 5'd0);
assign ex_forward_dest = id_ex_dest;
assign ex_forward_data = ex_result;

// EX/MEM：ALU 结果用于算术写回或访存地址。
// store_data 直接传递第二个源寄存器值，不使用经过立即数选择的 alu_src2。
always @(posedge clk) begin
    if (~resetn || flush)
        ex_mem_valid <= 1'b0;
    else if (mem_allow_in) begin
        // MEM 堵塞时保持整组 EX/MEM；EX 未完成时向空出的 MEM 注入气泡。
        ex_mem_valid        <= ex_to_mem_valid;
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
        ex_mem_ex_bus       <= (|id_ex_ex_bus[37:32]) ? id_ex_ex_bus :
                               {ale ? 6'b001000 : 6'b0,
                                ale ? alu_result : id_ex_ex_bus[31:0]};
    end
end

endmodule
