// MEM：接收 EX 已完成地址握手的事务，等待数据响应，保存 MEM/WB。
// load 和 store 都必须等 data_ok；否则下一条 load 会错认 store 的响应。
module mem_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         flush,
    output wire         allow_in,
    output wire         mem_req_block,

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

    // 数据响应没有 ready 反压；WB 固定可接收，在返回当拍锁存读数据。
    input  wire [31:0]  data_sram_rdata,
    input  wire         data_sram_data_ok,

    // MEM/WB 寄存器输出，供 WB 阶段使用
    output reg          mem_wb_valid,
    output reg  [31:0]  mem_wb_pc,
    output reg  [31:0]  mem_wb_alu_result,
    output reg  [31:0]  mem_wb_mem_result,
    output reg          mem_wb_res_from_mem,
    output reg  [1:0]   mem_wb_mem_size,
    output reg          mem_wb_load_unsigned,
    output reg  [1:0]   mem_wb_addr_low,
    output reg          mem_wb_gr_we,
    output reg  [4:0]   mem_wb_dest,
    output reg  [83:0]  mem_wb_csr_bus,
    output reg  [37:0]  mem_wb_ex_bus
);
wire is_memory_access = ex_mem_res_from_mem || ex_mem_mem_we;
// EX 已经完成地址握手；MEM 不能把“地址已接受”误当成“访存已结束”。
// 非访存（包括已屏蔽访存控制的异常项）无需等待外部响应。
wire ready_go = !is_memory_access || data_sram_data_ok;
wire mem_to_wb_valid = ex_mem_valid && ready_go;
assign allow_in = !ex_mem_valid || ready_go;  // WB 总能接收，不会阻塞 MEM。

// 精确异常保护：老异常/ertn 尚在 MEM 时，年轻 store 不得提前写内存。
// 对 load 采用同样的保守限制，保证数据事务不会被更老的异常取消。
// 旧访存仍占用 MEM 时也不接受新请求，数据端最多一笔未完成事务。
assign mem_req_block = ex_mem_valid &&
                       (is_memory_access || (|ex_mem_ex_bus[37:32]) ||
                        ex_mem_csr_bus[79]);
// load 和 CSR 结果都在 WB 可用；不能把它们的 ALU 结果误当前递数据。
assign mem_pending_we   = resetn && !flush && ex_mem_valid && ex_mem_gr_we &&
                          (ex_mem_res_from_mem || (|ex_mem_csr_bus[83:81])) &&
                          (ex_mem_dest != 5'd0);
assign mem_pending_dest = ex_mem_dest;

// 当前指令位于 MEM 阶段时，普通运算指令的 ALU 结果已经稳定，
// 可以绕过寄存器堆，直接送回 ID 阶段解决数据相关。
assign mem_forward_we   = resetn && !flush && ex_mem_valid && ex_mem_gr_we &&
                          ready_go &&
                          !ex_mem_res_from_mem && !(|ex_mem_csr_bus[83:81]) &&
                          (ex_mem_dest != 5'd0);
assign mem_forward_dest = ex_mem_dest;
assign mem_forward_data = ex_mem_alu_result;

// MEM/WB：传递 ALU 结果及对应的写回控制。
// 复位清除有效位，WB 通过该有效位禁止无效指令写寄存器。
always @(posedge clk) begin
    if (~resetn || flush)
        mem_wb_valid <= 1'b0;
    else begin
        // 每拍重新产生 WB 有效位；MEM 等待时 WB 是气泡，不能重复提交旧指令。
        mem_wb_valid        <= mem_to_wb_valid;
        mem_wb_mem_result   <= data_sram_rdata;
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
