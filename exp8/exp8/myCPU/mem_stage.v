// MEM：产生数据 SRAM 访问控制，保存 MEM/WB 流水寄存器。
// 同步 RAM 在 MEM/WB 更新的同一上升沿返回数据，返回线直接交给 WB。
module mem_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         allow_in,

    // 来自 EX/MEM 的地址、存储数据和控制信号
    input  wire         ex_mem_valid,
    input  wire [31:0]  ex_mem_pc,
    input  wire [31:0]  ex_mem_alu_result,
    input  wire [31:0]  ex_mem_store_data,
    input  wire         ex_mem_res_from_mem,
    input  wire         ex_mem_mem_we,
    input  wire         ex_mem_gr_we,
    input  wire [4:0]   ex_mem_dest,

    // 当前 MEM 指令的写回意图，反馈给 ID 做相关检测。
    output wire         mem_pending_we,
    output wire [4:0]   mem_pending_dest,
    output wire         ready_go,

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
    output wire [31:0]  mem_wb_mem_result,
    output reg          mem_wb_res_from_mem,
    output reg          mem_wb_gr_we,
    output reg  [4:0]   mem_wb_dest
);
assign ready_go = 1'b1;

assign mem_pending_we   = resetn && ex_mem_valid && ex_mem_gr_we && (ex_mem_dest != 5'd0);
assign mem_pending_dest = ex_mem_dest;

// 仅有效访存指令访问 SRAM；气泡和复位均不得产生存储副作用。
assign data_sram_en    = resetn && ex_mem_valid && (ex_mem_mem_we || ex_mem_res_from_mem);
assign data_sram_we    = {4{resetn && ex_mem_mem_we && ex_mem_valid}};
assign data_sram_addr  = ex_mem_alu_result;
assign data_sram_wdata = ex_mem_store_data;

// 不在这里再次采样 rdata：非阻塞赋值会采到上一笔请求的数据。
// RAM/bridge 内部的返回寄存器已经提供这一拍，与 mem_wb_* 对齐。
assign mem_wb_mem_result = data_sram_rdata;

// MEM/WB：传递 ALU 结果及对应的写回控制。
// 复位清除有效位，WB 通过该有效位禁止无效指令写寄存器。
always @(posedge clk) begin
    if (~resetn)
        mem_wb_valid <= 1'b0;
    else begin
        mem_wb_valid        <= ex_mem_valid;
        mem_wb_pc           <= ex_mem_pc;
        mem_wb_alu_result   <= ex_mem_alu_result;
        mem_wb_res_from_mem <= ex_mem_res_from_mem;
        mem_wb_gr_we        <= ex_mem_gr_we;
        mem_wb_dest         <= ex_mem_dest;
    end
end

endmodule
