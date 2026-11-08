`include "csr_defs.vh"

// WB：选择写回结果，产生寄存器堆写端口并提交 CSR/异常状态。
// 输入已经来自 MEM/WB 寄存器，因此这里不再增加流水寄存器。
// WB 固定每拍提交，无需 allow_in/ready_go；CSR 在本拍末的上升沿更新。
module wb_stage (
    input  wire         clk,
    input  wire         resetn,
    input  wire [7:0]   hw_int_in,
    output wire        has_int,

    // 来自 MEM/WB 的结果与写回控制
    input  wire         mem_wb_valid,
    input  wire [31:0]  mem_wb_pc,
    input  wire [31:0]  mem_wb_alu_result,
    input  wire [31:0]  mem_wb_mem_result,
    input  wire         mem_wb_res_from_mem,
    input  wire [1:0]   mem_wb_mem_size,
    input  wire         mem_wb_load_unsigned,
    input  wire [1:0]   mem_wb_addr_low,
    input  wire         mem_wb_gr_we,
    input  wire [4:0]   mem_wb_dest,
    input  wire [83:0]  mem_wb_csr_bus,
    input  wire [37:0]  mem_wb_ex_bus,

    // 在 WB 统一处理精确异常及返回，冲刷所有更年轻的指令。
    output wire         flush,
    output wire [31:0]  flush_pc,

    // 反馈给 ID 内部寄存器堆的写端口
    output wire         rf_we,
    output wire [4:0]   rf_waddr,
    output wire [31:0]  rf_wdata,

    // 供仿真比较与调试使用
    output wire [31:0]  debug_wb_pc,
    output wire [3:0]   debug_wb_rf_we,
    output wire [4:0]   debug_wb_rf_wnum,
    output wire [31:0]  debug_wb_rf_wdata
);
wire        csr_re;
wire        csr_we;
wire        ertn;
wire        syscall;
wire [13:0] csr_num;
wire [31:0] csr_wmask;
wire [31:0] csr_wdata;
wire [31:0] csr_rdata;
wire [31:0] ex_entry;
wire [31:0] ex_era;
wire [63:0] stable_counter;
wire        rdcntvh = mem_wb_csr_bus[83];
wire        rdcntvl = mem_wb_csr_bus[82];
wire [5:0]  wb_ecode = mem_wb_ex_bus[37] ? `ECODE_INT :
                       mem_wb_ex_bus[36] ? `ECODE_ADE :
                       mem_wb_ex_bus[35] ? `ECODE_ALE :
                       mem_wb_ex_bus[34] ? `ECODE_SYS :
                       mem_wb_ex_bus[33] ? `ECODE_BRK : `ECODE_INE;
wire [8:0]  wb_esubcode = 9'b0;
wire        wb_ex = resetn && mem_wb_valid && (|mem_wb_ex_bus[37:32]);
wire        ertn_flush = resetn && mem_wb_valid && ertn && !wb_ex;

assign {csr_re, csr_we, ertn, syscall, csr_num, csr_wmask, csr_wdata} = mem_wb_csr_bus[81:0];
assign flush = wb_ex || ertn_flush;
assign flush_pc = wb_ex ? ex_entry : ex_era;

// 读旧值、写新值和 GPR 写回发生在同一条指令的 WB 周期。
// 下一条 CSR 指令在下一拍读到更新后的状态，不需要 CSR 专用前递。
csr u_csr (
    .clk        (clk),
    .resetn     (resetn),
    .hw_int_in  (hw_int_in),
    .has_int    (has_int),
    .stable_counter(stable_counter),
    .csr_num    (csr_num),
    .csr_rdata  (csr_rdata),
    .csr_we     (resetn && mem_wb_valid && csr_we && !flush),
    .csr_wmask  (csr_wmask),
    .csr_wdata  (csr_wdata),
    .wb_ex      (wb_ex),
    .wb_pc      (mem_wb_pc),
    .wb_ecode   (wb_ecode),
    .wb_esubcode(wb_esubcode),
    .wb_badv    (mem_wb_ex_bus[31:0]),
    .ertn_flush (ertn_flush),
    .ex_entry   (ex_entry),
    .ex_era     (ex_era)
);

// 同步 RAM 返回一个对齐的 32 位字，按原始地址低位取出 load 的有效部分。
wire [7:0] load_byte = (mem_wb_addr_low == 2'b00) ? mem_wb_mem_result[7:0] :
                       (mem_wb_addr_low == 2'b01) ? mem_wb_mem_result[15:8] :
                       (mem_wb_addr_low == 2'b10) ? mem_wb_mem_result[23:16] :
                                                    mem_wb_mem_result[31:24];
wire [15:0] load_half = mem_wb_addr_low[1] ? mem_wb_mem_result[31:16] :
                                                   mem_wb_mem_result[15:0];
wire [31:0] load_result = (mem_wb_mem_size == 2'b00) ?
                          (mem_wb_load_unsigned ? {24'b0, load_byte} :
                                                   {{24{load_byte[7]}}, load_byte}) :
                          (mem_wb_mem_size == 2'b01) ?
                          (mem_wb_load_unsigned ? {16'b0, load_half} :
                                                   {{16{load_half[15]}}, load_half}) :
                          mem_wb_mem_result;

// 写使能必须同时满足“指令有效”和“需要写通用寄存器”
// WB 写回同时作为 ID 的相关检测依据；r0 和复位不产生写回。
assign rf_we    = resetn && !flush && mem_wb_gr_we && mem_wb_valid && (mem_wb_dest != 5'd0);
assign rf_waddr = mem_wb_dest;
// rdcntvl/h 读取的是独立的 64 位稳定计数器，不能走普通 ALU 结果通路。
assign rf_wdata = rdcntvh ? stable_counter[63:32] :
                  rdcntvl ? stable_counter[31:0] :
                  csr_re ? csr_rdata :
                 mem_wb_res_from_mem ? load_result : mem_wb_alu_result;

// 调试信号与实际寄存器堆写端口保持对应
assign debug_wb_pc       = mem_wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = rf_waddr;
assign debug_wb_rf_wdata = rf_wdata;

endmodule
