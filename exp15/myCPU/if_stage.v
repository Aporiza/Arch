// IF：包含 pre-IF 地址请求控制、返回缓存和 IF/ID 流水寄存器。
// pre-IF 是生成取指地址的逻辑部分，不额外增加一个流水级模块。
// 每次最多一笔取指事务；ready_go 为模块内部信号，不作为级间端口。
module if_stage (
    input  wire        clk,
    input  wire        resetn,
    input  wire        id_allow_in,
    input  wire        br_stall,
    input  wire        redirect_i,
    input  wire [31:0] redirect_pc_i,

    // 地址阶段：只有 req && addr_ok 才表示这笔请求已被接收。
    // 数据阶段：已接收请求至少下一拍才返回 data_ok，返回端没有反压。
    output wire        inst_sram_req,
    output wire        inst_sram_wr,
    output wire [1:0]  inst_sram_size,
    output wire [3:0]  inst_sram_wstrb,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    input  wire [31:0] inst_sram_rdata,

    output reg         if_id_valid,
    output reg  [31:0] if_id_pc,
    output reg  [31:0] if_id_inst
);

reg [31:0] next_pc;          // 尚未发起请求的下一条指令地址
reg        fetch_pending;    // 地址已接收，仍欠一笔数据响应
reg [31:0] fetch_pc;         // 与未完成请求绑定，不能随 next_pc 改变
reg        discard_pending;  // 冲刷不能撤销外部请求，只能丢弃其返回
reg        inst_buf_valid;
reg [31:0] inst_buf;
reg [31:0] inst_buf_pc;

// 已预留一个返回缓存，因此 ID 堵塞也可以接收唯一未完成请求的响应。
// 缓存占用或仍有未完成事务时不再请求，避免重复取指和覆盖返回数据。
wire fetch_slot_free = !fetch_pending && !inst_buf_valid;
wire fetch_adef = |next_pc[1:0];
assign inst_sram_req   = resetn && !redirect_i && !br_stall &&
                         fetch_slot_free && !fetch_adef;
assign inst_sram_wr    = 1'b0;
assign inst_sram_size  = 2'b10;  // 每条指令固定为 4 字节
assign inst_sram_wstrb = 4'b0;
assign inst_sram_addr  = next_pc;
assign inst_sram_wdata = 32'b0;

wire addr_fire = inst_sram_req && inst_sram_addr_ok;
wire response = fetch_pending && inst_sram_data_ok;
// ADEF 不向 RAM 发请求；合成一个携带错误 PC 的流水项，由 ID 标记异常。
// 指令码置零，ADEF 优先于因此产生的 INE，最终 BADV/ERA 都能保存错误 PC。
wire local_adef = resetn && !redirect_i && !br_stall &&
                  fetch_slot_free && fetch_adef;
wire return_valid = (response && !discard_pending) || local_adef;
wire [31:0] return_pc = local_adef ? next_pc : fetch_pc;
wire [31:0] return_inst = local_adef ? 32'b0 : inst_sram_rdata;
// ready_go 仅说明“已有可交给 ID 的指令”；还需 id_allow_in 才能交接。
// IF/ID 是 ID 当前使用的入口槽，因此 ID 阻塞时不能改写它。
wire ready_go = inst_buf_valid || return_valid;
wire if_to_id_valid = ready_go && !redirect_i;

// 总线事务记账独立于流水线有效位。重定向目标直接锁存在 next_pc 中；
// 即使旧请求还没返回，也不会丢失一拍的分支/异常重定向。
always @(posedge clk) begin
    if (!resetn) begin
        next_pc <= 32'h1c00_0000;
        fetch_pending <= 1'b0;
        fetch_pc <= 32'b0;
        discard_pending <= 1'b0;
    end else begin
        if (response) begin
            fetch_pending <= 1'b0;
            discard_pending <= 1'b0;
        end
        if (addr_fire) begin
            fetch_pending <= 1'b1;
            fetch_pc <= next_pc;
            next_pc <= next_pc + 32'd4;
        end else if (local_adef)
            next_pc <= next_pc + 32'd4;

        // 重定向优先。若旧数据同拍返回，直接丢弃，不必继续等待。
        if (redirect_i) begin
            next_pc <= redirect_pc_i;
            if (fetch_pending && !response)
                discard_pending <= 1'b1;
        end
    end
end

// data_ok 没有反压：返回当拍若 ID 无法接收，必须保存指令和对应 PC。
// 先消费缓存，再允许下次请求，故不会发生缓存被第二个响应覆盖。
always @(posedge clk) begin
    if (!resetn || redirect_i) begin
        inst_buf_valid <= 1'b0;
        if_id_valid <= 1'b0;
    end else begin
        if (id_allow_in) begin
            if_id_valid <= if_to_id_valid;
            if (if_to_id_valid) begin
                if_id_pc <= inst_buf_valid ? inst_buf_pc : return_pc;
                if_id_inst <= inst_buf_valid ? inst_buf : return_inst;
            end
        end
        if (inst_buf_valid && id_allow_in)
            inst_buf_valid <= 1'b0;
        if (return_valid && !id_allow_in) begin
            inst_buf_valid <= 1'b1;
            inst_buf_pc <= return_pc;
            inst_buf <= return_inst;
        end
    end
end

endmodule
