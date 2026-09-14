// IF：维护 PC，发出取指地址，并保存 IF/ID 流水寄存器。
// redirect_i 为 1 时使用 redirect_pc_i，并将顺序路径指令标记为无效。
module if_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,

    // 来自 ID 的取指重定向：是否跳转、目标地址
    input  wire         redirect_i,
    input  wire [31:0]  redirect_pc_i,
    // 上一级允许本阶段接收新指令；为 0 时保持 PC 和 IF/ID
    input  wire         allow_in,
    output wire         ready_go,

    // 指令 SRAM 接口
    input  wire [31:0]  inst_sram_rdata,
    output wire         inst_sram_en,
    output wire [3:0]   inst_sram_we,
    output wire [31:0]  inst_sram_addr,
    output wire [31:0]  inst_sram_wdata,

    // IF/ID 寄存器输出，供 ID 阶段使用
    output reg          if_id_valid,
    output reg  [31:0]  if_id_pc,
    output reg  [31:0]  if_id_inst
);
assign ready_go = 1'b1;

// PC 状态与取指启动有效位
reg  [31:0]  pc;
reg          valid;
wire         reset = ~resetn;

// 顺序取指加 4；重定向时改用分支目标
wire [31:0]  next_pc = redirect_i ? redirect_pc_i : pc + 32'd4;

// 同步指令 RAM 使用 next_pc 发起读取；IF/ID 在时钟沿保存当前返回值
// ID 阻塞时同时冻结 RAM 输出和 PC，否则解除阻塞后指令与 PC 会错位。
assign inst_sram_en    = resetn && allow_in;
assign inst_sram_we    = 4'b0;
assign inst_sram_addr  = next_pc;
assign inst_sram_wdata = 32'b0;

// PC 和 IF/ID 更新：复位后先建立取指有效位；跳转时向 ID 插入气泡。
// 数据寄存器无需随气泡清零，后续阶段通过 valid 屏蔽其副作用。
always @(posedge clk) begin
    if (reset) begin
        valid       <= 1'b0;
        pc          <= 32'h1bfffffc;
        if_id_valid <= 1'b0;
    end else if (allow_in) begin
        valid       <= 1'b1;
        pc          <= next_pc;
        if_id_valid <= valid && !redirect_i;
        if_id_pc    <= pc;
        if_id_inst  <= inst_sram_rdata;
    end
end

endmodule
