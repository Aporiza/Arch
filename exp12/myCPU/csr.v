`include "csr_defs.vh"

// 控制状态寄存器集中管理；指令访问和异常硬件更新均在 WB 提交。
// 保留位读零且不可写，未实现地址读零、忽略写入。
module csr (
    input  wire        clk,
    input  wire        resetn,
    input  wire [13:0] csr_num,
    output reg  [31:0] csr_rdata,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wdata,
    input  wire        wb_ex,
    input  wire [31:0] wb_pc,
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

always @(*) begin
    case (csr_num)
        `CSR_CRMD:   csr_rdata = {28'b0, 1'b1, crmd_ie, crmd_plv};
        `CSR_PRMD:   csr_rdata = {29'b0, prmd_pie, prmd_pplv};
        `CSR_ESTAT:  csr_rdata = {1'b0, estat_esubcode, estat_ecode,
                                14'b0, estat_sw};
        `CSR_ERA:    csr_rdata = era;
        `CSR_EENTRY: csr_rdata = ex_entry;
        `CSR_SAVE0:  csr_rdata = save0;
        `CSR_SAVE1:  csr_rdata = save1;
        `CSR_SAVE2:  csr_rdata = save2;
        `CSR_SAVE3:  csr_rdata = save3;
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
        estat_ecode <= `ECODE_SYS;
        estat_esubcode <= 9'b0;
    end
end

endmodule
