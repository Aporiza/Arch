// MEM：产生数据 SRAM 访问控制，保存 MEM/WB 流水寄存器。
// 同步 RAM 在 MEM/WB 更新的同一上升沿返回数据，返回线直接交给 WB。
// MEM 固定每拍接收 EX/MEM 内容，不需要额外的 allow_in/ready_go 握手端口。
module mem_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         flush,

    // 来自 EX/MEM 的地址、存储数据和控制信号
    input  wire         ex_mem_valid,
    input  wire [31:0]  ex_mem_pc,
    input  wire [31:0]  ex_mem_alu_result,
    input  wire [31:0]  ex_mem_store_data,
    input  wire         ex_mem_res_from_mem,
    input  wire         ex_mem_mem_we,
    input  wire [1:0]   ex_mem_mem_size,
    input  wire         ex_mem_load_unsigned,
    input  wire         ex_mem_gr_we,
    input  wire [4:0]   ex_mem_dest,
    input  wire [83:0]  ex_mem_csr_bus,
    input  wire [37:0]  ex_mem_ex_bus,

    // 当前 MEM 阶段 load/CSR 的写回意图，反馈给 ID 做相关检测。
    output wire         mem_pending_we,
    output wire [4:0]   mem_pending_dest,

    // EX/MEM 中的 ALU 结果直接前递到 ID。
    // load 的 ex_mem_alu_result 是地址，不是读出的数据，因此不走此通路。
    output wire         mem_forward_we,
    output wire [4:0]   mem_forward_dest,
    output wire [31:0]  mem_forward_data,

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
    output reg  [1:0]   mem_wb_mem_size,
    output reg          mem_wb_load_unsigned,
    output reg  [1:0]   mem_wb_addr_low,
    output reg          mem_wb_gr_we,
    output reg  [4:0]   mem_wb_dest,
    output reg  [83:0]  mem_wb_csr_bus,
    output reg  [37:0]  mem_wb_ex_bus
);
// load 和 CSR 结果都在 WB 可用；不能把它们的 ALU 结果误当前递数据。
assign mem_pending_we   = resetn && !flush && ex_mem_valid && ex_mem_gr_we &&
                          (ex_mem_res_from_mem || ex_mem_csr_bus[81] || ex_mem_csr_bus[80]) &&
                          (ex_mem_dest != 5'd0);
assign mem_pending_dest = ex_mem_dest;

// 当前指令位于 MEM 阶段时，普通运算指令的 ALU 结果已经稳定，
// 可以绕过寄存器堆，直接送回 ID 阶段解决数据相关。
assign mem_forward_we   = resetn && !flush && ex_mem_valid && ex_mem_gr_we &&
                          !ex_mem_res_from_mem && !ex_mem_csr_bus[81] && !ex_mem_csr_bus[80] &&
                          (ex_mem_dest != 5'd0);
assign mem_forward_dest = ex_mem_dest;
assign mem_forward_data = ex_mem_alu_result;

// WB 异常/ertn 冲刷时，MEM 指令比它年轻，必须在本拍就取消访存。
assign data_sram_en    = resetn && !flush && ex_mem_valid && (ex_mem_mem_we || ex_mem_res_from_mem);
// RAM 是 32 位、4 路字节写使能。字节/半字存储只打开对应 lane，
// 写数据在相应 lane 复制，兼容 BRAM 和外设桥的 byte-enable 语义。
assign data_sram_we = !resetn || flush || !ex_mem_valid || !ex_mem_mem_we ? 4'b0000 :
                      (ex_mem_mem_size == 2'b00) ? (4'b0001 << ex_mem_alu_result[1:0]) :
                      (ex_mem_mem_size == 2'b01) ? (ex_mem_alu_result[1] ? 4'b1100 : 4'b0011) :
                                                   4'b1111;
assign data_sram_addr  = ex_mem_alu_result;
assign data_sram_wdata = (ex_mem_mem_size == 2'b00) ? {4{ex_mem_store_data[7:0]}} :
                         (ex_mem_mem_size == 2'b01) ? {2{ex_mem_store_data[15:0]}} :
                                                       ex_mem_store_data;

// 不在这里再次采样 rdata：非阻塞赋值会采到上一笔请求的数据。
// RAM/bridge 内部的返回寄存器已经提供这一拍，与 mem_wb_* 对齐。
assign mem_wb_mem_result = data_sram_rdata;

// MEM/WB：传递 ALU 结果及对应的写回控制。
// 复位清除有效位，WB 通过该有效位禁止无效指令写寄存器。
always @(posedge clk) begin
    if (~resetn || flush)
        mem_wb_valid <= 1'b0;
    else begin
        mem_wb_valid        <= ex_mem_valid;
        mem_wb_pc           <= ex_mem_pc;
        mem_wb_alu_result   <= ex_mem_alu_result;
        mem_wb_res_from_mem <= ex_mem_res_from_mem;
        mem_wb_mem_size     <= ex_mem_mem_size;
        mem_wb_load_unsigned <= ex_mem_load_unsigned;
        mem_wb_addr_low     <= ex_mem_alu_result[1:0];
        mem_wb_gr_we        <= ex_mem_gr_we;
        mem_wb_dest         <= ex_mem_dest;
        mem_wb_csr_bus      <= ex_mem_csr_bus;
        mem_wb_ex_bus       <= ex_mem_ex_bus;
    end
end

endmodule
