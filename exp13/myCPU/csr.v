`include "csr_defs.vh"

// 控制状态寄存器集中管理；指令访问和异常硬件更新均在 WB 提交。
// 保留位读零且不可写，未实现地址读零、忽略写入。
module csr (
    input  wire        clk,
    input  wire        resetn,
    input  wire [7:0]  hw_int_in,
    output wire        has_int,
    output reg  [63:0] stable_counter,
    input  wire [13:0] csr_num,
    output reg  [31:0] csr_rdata,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wdata,
    input  wire        wb_ex,
    input  wire [31:0] wb_pc,
    input  wire [5:0]  wb_ecode,
    input  wire [8:0]  wb_esubcode,
    input  wire [31:0] wb_badv,
    input  wire        ertn_flush,
    output wire [31:0] ex_entry,
    output wire [31:0] ex_era
);

// 本阶段尚无 MMU/Cache：DA=1，PG/DATF/DATM=0；仅 PLV、IE 可写。
reg [1:0] crmd_plv;
reg       crmd_ie;
reg [1:0] prmd_pplv;
reg       prmd_pie;
reg [1:0] estat_sw;
reg [5:0] estat_ecode;
reg [8:0] estat_esubcode;
reg [31:0] era;
reg [25:0] eentry_va;
reg [31:0] save0, save1, save2, save3;

wire [31:0] masked_value = (csr_wmask & csr_wdata) |
                           (~csr_wmask & csr_rdata);
assign ex_entry = {eentry_va, 6'b0};
assign ex_era = era;

reg [12:0] ecfg_lie;
reg [7:0]  estat_hw;
reg        estat_timer;
reg [31:0] badv;
reg [31:0] tid;
reg        tcfg_en;
reg        tcfg_periodic;
reg [29:0] tcfg_initval;
reg [31:0] timer_value;

wire [12:0] interrupt_status = {1'b0, estat_timer, 1'b0, estat_hw, estat_sw};
wire [31:0] tcfg_value = {tcfg_initval, tcfg_periodic, tcfg_en};
wire        write_tcfg = csr_we && csr_num == `CSR_TCFG;
assign has_int = crmd_ie && (|(ecfg_lie & interrupt_status));

always @(*) begin
    case (csr_num)
        `CSR_CRMD:   csr_rdata = {28'b0, 1'b1, crmd_ie, crmd_plv};
        `CSR_PRMD:   csr_rdata = {29'b0, prmd_pie, prmd_pplv};
        `CSR_ESTAT:  csr_rdata = {1'b0, estat_esubcode, estat_ecode,
                                3'b0, interrupt_status};
        `CSR_ERA:    csr_rdata = era;
        `CSR_EENTRY: csr_rdata = ex_entry;
        `CSR_SAVE0:  csr_rdata = save0;
        `CSR_SAVE1:  csr_rdata = save1;
        `CSR_SAVE2:  csr_rdata = save2;
        `CSR_SAVE3:  csr_rdata = save3;
        `CSR_ECFG:   csr_rdata = {19'b0, ecfg_lie};
        `CSR_BADV:   csr_rdata = badv;
        `CSR_TID:    csr_rdata = tid;
        `CSR_TCFG:   csr_rdata = tcfg_value;
        `CSR_TVAL:   csr_rdata = timer_value;
        `CSR_TICLR:  csr_rdata = 32'b0;
        default:     csr_rdata = 32'b0;
    endcase
end

// CRMD：异常入口保存前状态并关闭中断，ertn 恢复 PLV/IE。
always @(posedge clk) begin
    if (!resetn) begin
        crmd_plv <= 2'b0;
        crmd_ie <= 1'b0;
    end else if (wb_ex) begin
        crmd_plv <= 2'b0;
        crmd_ie <= 1'b0;
    end else if (ertn_flush) begin
        crmd_plv <= prmd_pplv;
        crmd_ie <= prmd_pie;
    end else if (csr_we && csr_num == `CSR_CRMD) begin
        crmd_plv <= masked_value[1:0];
        crmd_ie <= masked_value[2];
    end
end

// 稳定计数器不受流水线停顿影响，每个时钟周期递增一次。
always @(posedge clk) begin
    if (!resetn)
        stable_counter <= 64'b0;
    else
        stable_counter <= stable_counter + 64'd1;
end

always @(posedge clk) begin
    if (!resetn) begin
        prmd_pplv <= 2'b0;
        prmd_pie <= 1'b0;
    end else if (wb_ex) begin
        prmd_pplv <= crmd_plv;
        prmd_pie <= crmd_ie;
    end else if (csr_we && csr_num == `CSR_PRMD) begin
        prmd_pplv <= masked_value[1:0];
        prmd_pie <= masked_value[2];
    end
end

// 软件中断位可写；异常编码由硬件更新，CSR 写不能修改。
always @(posedge clk) begin
    if (!resetn)
        estat_sw <= 2'b0;
    else if (csr_we && csr_num == `CSR_ESTAT)
        estat_sw <= masked_value[1:0];
end

always @(posedge clk) begin
    if (!resetn)
        era <= 32'b0;
    else if (wb_ex)
        // 保存异常指令自身 PC；是否跳过该指令由处理程序决定。
        era <= wb_pc;
    else if (csr_we && csr_num == `CSR_ERA)
        era <= masked_value;
end

always @(posedge clk) begin
    if (!resetn)
        eentry_va <= 26'b0;
    else if (csr_we && csr_num == `CSR_EENTRY)
        eentry_va <= masked_value[31:6];
end

always @(posedge clk) begin
    if (!resetn) begin
        save0 <= 32'b0;
        save1 <= 32'b0;
        save2 <= 32'b0;
        save3 <= 32'b0;
    end else if (csr_we) begin
        case (csr_num)
            `CSR_SAVE0: save0 <= masked_value;
            `CSR_SAVE1: save1 <= masked_value;
            `CSR_SAVE2: save2 <= masked_value;
            `CSR_SAVE3: save3 <= masked_value;
            default: begin end
        endcase
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        estat_ecode <= 6'b0;
        estat_esubcode <= 9'b0;
    end else if (wb_ex) begin
        estat_ecode <= wb_ecode;
        estat_esubcode <= wb_esubcode;
    end
end

// BADV 的硬件更新优先于软件写；非地址异常保持原值。
always @(posedge clk) begin
    if (!resetn)
        badv <= 32'b0;
    else if (wb_ex && ((wb_ecode == `ECODE_ADE && wb_esubcode == `ESUBCODE_ADEF) ||
                       wb_ecode == `ECODE_ALE))
        badv <= wb_badv;
    else if (csr_we && csr_num == `CSR_BADV)
        badv <= masked_value;
end

always @(posedge clk) begin
    if (!resetn) begin
        ecfg_lie <= 13'b0;
        tid <= 32'b0;
        estat_hw <= 8'b0;
    end else begin
        // 硬件中断在 CPU 时钟域采样；未实现的 IS[10]/IS[12] 恒零。
        estat_hw <= hw_int_in;
        if (csr_we && csr_num == `CSR_ECFG)
            ecfg_lie <= masked_value[12:0] & 13'h1bff;
        if (csr_we && csr_num == `CSR_TID)
            tid <= masked_value;
    end
end

// 配置字段与倒计数器分开维护。单次到期不清 En，TVAL 全 1 表示停止。
always @(posedge clk) begin
    if (!resetn) begin
        tcfg_en <= 1'b0;
        tcfg_periodic <= 1'b0;
        tcfg_initval <= 30'b0;
    end else if (write_tcfg) begin
        tcfg_en <= masked_value[0];
        tcfg_periodic <= masked_value[1];
        tcfg_initval <= masked_value[31:2];
    end
end

always @(posedge clk) begin
    if (!resetn)
        timer_value <= 32'hffff_ffff;
    else if (write_tcfg && masked_value[0])
        timer_value <= {masked_value[31:2], 2'b0};
    else if (tcfg_en && timer_value != 32'hffff_ffff) begin
        if (timer_value == 32'b0 && tcfg_periodic)
            timer_value <= {tcfg_initval, 2'b0};
        else
            timer_value <= timer_value - 32'd1;
    end
end

// 到期与 TICLR 写一清除同拍时到期优先；关闭定时器不清中断状态。
always @(posedge clk) begin
    if (!resetn)
        estat_timer <= 1'b0;
    else if (tcfg_en && timer_value == 32'b0)
        estat_timer <= 1'b1;
    else if (csr_we && csr_num == `CSR_TICLR && csr_wmask[0] && csr_wdata[0])
        estat_timer <= 1'b0;
end

endmodule
