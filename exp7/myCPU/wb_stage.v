// WB：组合选择写回结果，产生寄存器堆写端口和调试输出。
// 输入已经来自 MEM/WB 寄存器，因此这里不再增加流水寄存器。
module wb_stage (
    // 来自 MEM/WB 的结果与写回控制
    input  wire         mem_wb_valid,
    input  wire [31:0]  mem_wb_pc,
    input  wire [31:0]  mem_wb_alu_result,
    input  wire [31:0]  mem_wb_mem_result,
    input  wire         mem_wb_res_from_mem,
    input  wire         mem_wb_gr_we,
    input  wire [4:0]   mem_wb_dest,

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

// 写使能必须同时满足“指令有效”和“需要写通用寄存器”
assign rf_we    = mem_wb_gr_we && mem_wb_valid;
assign rf_waddr = mem_wb_dest;
assign rf_wdata = mem_wb_res_from_mem ? mem_wb_mem_result : mem_wb_alu_result;

// 调试信号与实际寄存器堆写端口保持对应
assign debug_wb_pc       = mem_wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = rf_waddr;
assign debug_wb_rf_wdata = rf_wdata;

endmodule
