// MEM：产生数据 SRAM 访问控制，保存 MEM/WB 流水寄存器。
// 当前实现也在这里寄存 SRAM 返回数据；其有效时刻须与 RAM 读延迟对应。
module mem_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,

    // 来自 EX/MEM 的地址、存储数据和控制信号
    input  wire         ex_mem_valid,
    input  wire [31:0]  ex_mem_pc,
    input  wire [31:0]  ex_mem_alu_result,
    input  wire [31:0]  ex_mem_store_data,
    input  wire         ex_mem_res_from_mem,
    input  wire         ex_mem_mem_we,
    input  wire         ex_mem_gr_we,
    input  wire [4:0]   ex_mem_dest,

    // 数据 SRAM 接口
    input  wire [31:0]  data_sram_rdata,
    output wire         data_sram_en,
    output wire [3:0]   data_sram_we,
    output wire [31:0]  data_sram_addr,
    output wire [31:0]  data_sram_wdata,

    // MEM/WB 寄存器输出，供 WB 阶段使用
    output reg          mem_wb_valid,
    output reg  [31:0]  mem_wb_pc,
    output reg  [31:0]  mem_wb_alu_result,
    output reg  [31:0]  mem_wb_mem_result,
    output reg          mem_wb_res_from_mem,
    output reg          mem_wb_gr_we,
    output reg  [4:0]   mem_wb_dest
);

// SRAM 始终使能；仅有效的存储指令开启四个字节的写使能
assign data_sram_en    = 1'b1;
assign data_sram_we    = {4{ex_mem_mem_we && ex_mem_valid}};
assign data_sram_addr  = ex_mem_alu_result;
assign data_sram_wdata = ex_mem_store_data;

// MEM/WB：传递 ALU 结果、当前采样的 SRAM 数据及对应的写回控制。
// 复位清除有效位，WB 通过该有效位禁止无效指令写寄存器。
always @(posedge clk) begin
    if (~resetn)
        mem_wb_valid <= 1'b0;
    else begin
        mem_wb_valid        <= ex_mem_valid;
        mem_wb_pc           <= ex_mem_pc;
        mem_wb_alu_result   <= ex_mem_alu_result;
        mem_wb_mem_result   <= data_sram_rdata;
        mem_wb_res_from_mem <= ex_mem_res_from_mem;
        mem_wb_gr_we        <= ex_mem_gr_we;
        mem_wb_dest         <= ex_mem_dest;
    end
end

endmodule
