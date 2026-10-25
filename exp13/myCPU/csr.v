// exp13 控制状态寄存器。CSR、异常及 ertn 在 WB 提交，计数器独立运行。
// 未实现的 CSR 读零、忽略写入；保留位读零且不可写。
module csr (
    input  wire        clk,
    input  wire        resetn,
    input  wire [7:0]  hw_int_in,
    output wire       has_int,
    output wire [1:0] current_plv,
    output reg  [63:0] stable_counter,
    input  wire [13:0] csr_num,
    output reg  [31:0] csr_rdata,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wdata,
    input  wire        wb_ex,
    input  wire [31:0] wb_pc,
    input  wire [5:0]  wb_ecode,
    input  wire [31:0] wb_badv,
    input  wire        ertn_flush,
    output wire [31:0] ex_entry,
    output wire [31:0] ex_era
);

localparam [13:0] CSR_CRMD   = 14'h0000,
                  CSR_PRMD   = 14'h0001,
                  CSR_ECFG   = 14'h0004,
                  CSR_ESTAT  = 14'h0005,
                  CSR_ERA    = 14'h0006,
                  CSR_BADV   = 14'h0007,
                  CSR_EENTRY = 14'h000c,
                  CSR_SAVE0  = 14'h0030,
                  CSR_SAVE1  = 14'h0031,
                  CSR_SAVE2  = 14'h0032,
                  CSR_SAVE3  = 14'h0033,
                  CSR_TID    = 14'h0040,
                  CSR_TCFG   = 14'h0041,
                  CSR_TVAL   = 14'h0042,
                  CSR_TICLR  = 14'h0044;

// CRMD[8:0] = {DATM, DATF, PG, DA, IE, PLV}，复位进入直接地址模式。
// 本实验不包含 MMU；访存仍沿用 exp11 的直接地址接口。
reg [8:0]  crmd;
reg [2:0]  prmd;          // {PIE, PPLV}
reg [1:0]  estat_is;      // 两路软件中断，由 CSR 写入/清除
reg [7:0]  estat_hw;
reg        estat_timer;
reg [12:0] ecfg_lie;
reg [31:0] badv;
reg [31:0] tid;
reg [31:0] tcfg;          // {InitVal[29:0], Periodic, En}
reg [31:0] timer_value;
reg        timer_running;
reg [5:0]  estat_ecode;
reg [8:0]  estat_esubcode;
reg [31:0] era;
reg [25:0] eentry_va;     // EENTRY[31:6]，低六位恒为零
reg [31:0] save0, save1, save2, save3;

// CSRWR 的掩码为全 1，CSRXCHG 的掩码来自 rj。
// 与旧值合并后，再按各寄存器允许写入的位更新。
wire [31:0] masked_value = (csr_wmask & csr_wdata) |
                           (~csr_wmask & csr_rdata);
assign ex_entry = {eentry_va, 6'b0};
assign ex_era = era;
wire [12:0] interrupt_status = {1'b0, estat_timer, 1'b0, estat_hw, estat_is};
assign has_int = crmd[2] && (|(ecfg_lie & interrupt_status));
assign current_plv = crmd[1:0];

always @(*) begin
    case (csr_num)
        CSR_CRMD:   csr_rdata = {23'b0, crmd};
        CSR_PRMD:   csr_rdata = {29'b0, prmd};
        CSR_ECFG:   csr_rdata = {19'b0, ecfg_lie};
        CSR_ESTAT:  csr_rdata = {1'b0, estat_esubcode, estat_ecode,
                                3'b0, interrupt_status};
        CSR_ERA:    csr_rdata = era;
        CSR_BADV:   csr_rdata = badv;
        CSR_EENTRY: csr_rdata = ex_entry;
        CSR_SAVE0:  csr_rdata = save0;
        CSR_SAVE1:  csr_rdata = save1;
        CSR_SAVE2:  csr_rdata = save2;
        CSR_SAVE3:  csr_rdata = save3;
        CSR_TID:    csr_rdata = tid;
        CSR_TCFG:   csr_rdata = tcfg;
        CSR_TVAL:   csr_rdata = timer_value;
        CSR_TICLR:  csr_rdata = 32'b0;
        default:    csr_rdata = 32'b0;
    endcase
end

always @(posedge clk) begin
    if (!resetn) begin
        crmd          <= 9'h008;
        prmd          <= 3'b0;
        estat_is      <= 2'b0;
        ecfg_lie      <= 13'b0;
        badv          <= 32'b0;
        tid           <= 32'b0;
        estat_ecode   <= 6'b0;
        estat_esubcode <= 9'b0;
        era           <= 32'b0;
        eentry_va     <= 26'b0;
        save0         <= 32'b0;
        save1         <= 32'b0;
        save2         <= 32'b0;
        save3         <= 32'b0;
    end else if (wb_ex) begin
        // 异常/中断：保存被中断指令自身 PC 与旧 PLV/IE，再进入内核态。
        // ERA 不自动加 4，由异常处理程序决定返回地址。
        prmd          <= crmd[2:0];
        crmd[2:0]     <= 3'b0;
        era           <= wb_pc;
        estat_ecode   <= wb_ecode;
        estat_esubcode <= 9'b0;
        if (wb_ecode == 6'h08 || wb_ecode == 6'h09)
            badv <= wb_badv;
    end else if (ertn_flush) begin
        crmd[2:0] <= prmd;
    end else if (csr_we) begin
        case (csr_num)
            CSR_CRMD:   crmd      <= masked_value[8:0];
            CSR_PRMD:   prmd      <= masked_value[2:0];
            CSR_ECFG:   ecfg_lie  <= masked_value[12:0] & 13'h1bff;
            // Ecode/EsubCode、硬件及定时器中断状态不能由 ESTAT 写修改。
            CSR_ESTAT:  estat_is  <= masked_value[1:0];
            CSR_ERA:    era       <= masked_value;
            CSR_EENTRY: eentry_va <= masked_value[31:6];
            CSR_SAVE0:  save0     <= masked_value;
            CSR_SAVE1:  save1     <= masked_value;
            CSR_SAVE2:  save2     <= masked_value;
            CSR_SAVE3:  save3     <= masked_value;
            CSR_TID:    tid       <= masked_value;
            default: begin end
        endcase
    end
end

// 稳定计数器在流水线停顿、异常及定时器关闭时仍每拍递增。
always @(posedge clk) begin
    if (!resetn) begin
        stable_counter <= 64'b0;
        estat_hw <= 8'b0;
    end else begin
        stable_counter <= stable_counter + 64'd1;
        estat_hw <= hw_int_in;
    end
end

// 写 TCFG 且 En=1 时，用合并后的 InitVal<<2 重装计数值。
// 单次模式到零后变为全 1 并停止；周期模式到零后重新装载。
always @(posedge clk) begin
    if (!resetn) begin
        tcfg <= 32'b0;
        timer_value <= 32'hffff_ffff;
        timer_running <= 1'b0;
    end else if (csr_we && csr_num == CSR_TCFG) begin
        tcfg <= masked_value;
        timer_running <= masked_value[0];
        if (masked_value[0])
            timer_value <= {masked_value[31:2], 2'b0};
    end else if (timer_running) begin
        if (timer_value == 32'b0) begin
            timer_value <= tcfg[1] ? {tcfg[31:2], 2'b0} : 32'hffff_ffff;
            timer_running <= tcfg[1];
        end else
            timer_value <= timer_value - 32'd1;
    end
end

// 到期状态一直保持，直到软件通过 TICLR 的有效写位清除。
// 到期与清除同拍时到期优先；关闭 TCFG 不隐式清除中断状态。
always @(posedge clk) begin
    if (!resetn)
        estat_timer <= 1'b0;
    else if (timer_running && timer_value == 32'b0)
        estat_timer <= 1'b1;
    else if (csr_we && csr_num == CSR_TICLR && csr_wmask[0] && csr_wdata[0])
        estat_timer <= 1'b0;
end

endmodule
