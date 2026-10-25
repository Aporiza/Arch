// exp12 控制状态寄存器。CSR 指令、syscall 和 ertn 都在 WB 提交。
// 未实现的 CSR 读零、忽略写入；保留位读零且不可写。
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

localparam [13:0] CSR_CRMD   = 14'h0000,
                  CSR_PRMD   = 14'h0001,
                  CSR_ESTAT  = 14'h0005,
                  CSR_ERA    = 14'h0006,
                  CSR_EENTRY = 14'h000c,
                  CSR_SAVE0  = 14'h0030,
                  CSR_SAVE1  = 14'h0031,
                  CSR_SAVE2  = 14'h0032,
                  CSR_SAVE3  = 14'h0033;

// CRMD[8:0] = {DATM, DATF, PG, DA, IE, PLV}，复位进入直接地址模式。
// 本实验不包含 MMU；访存仍沿用 exp11 的直接地址接口。
reg [8:0]  crmd;
reg [2:0]  prmd;          // {PIE, PPLV}
reg [1:0]  estat_is;      // 软件中断状态；exp12 尚不产生中断异常
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

always @(*) begin
    case (csr_num)
        CSR_CRMD:   csr_rdata = {23'b0, crmd};
        CSR_PRMD:   csr_rdata = {29'b0, prmd};
        CSR_ESTAT:  csr_rdata = {1'b0, estat_esubcode, estat_ecode,
                                14'b0, estat_is};
        CSR_ERA:    csr_rdata = era;
        CSR_EENTRY: csr_rdata = ex_entry;
        CSR_SAVE0:  csr_rdata = save0;
        CSR_SAVE1:  csr_rdata = save1;
        CSR_SAVE2:  csr_rdata = save2;
        CSR_SAVE3:  csr_rdata = save3;
        default:    csr_rdata = 32'b0;
    endcase
end

always @(posedge clk) begin
    if (!resetn) begin
        crmd          <= 9'h008;
        prmd          <= 3'b0;
        estat_is      <= 2'b0;
        estat_ecode   <= 6'b0;
        estat_esubcode <= 9'b0;
        era           <= 32'b0;
        eentry_va     <= 26'b0;
        save0         <= 32'b0;
        save1         <= 32'b0;
        save2         <= 32'b0;
        save3         <= 32'b0;
    end else if (wb_ex) begin
        // SYSCALL：保存异常指令自身 PC 与旧 PLV/IE，再进入内核态。
        // ERA 不自动加 4，由异常处理程序决定返回地址。
        prmd          <= crmd[2:0];
        crmd[2:0]     <= 3'b0;
        era           <= wb_pc;
        estat_ecode   <= 6'h0b;
        estat_esubcode <= 9'b0;
    end else if (ertn_flush) begin
        crmd[2:0] <= prmd;
    end else if (csr_we) begin
        case (csr_num)
            CSR_CRMD:   crmd      <= masked_value[8:0];
            CSR_PRMD:   prmd      <= masked_value[2:0];
            // Ecode/EsubCode 和未接入的硬件中断状态不能由 CSR 写修改。
            CSR_ESTAT:  estat_is  <= masked_value[1:0];
            CSR_ERA:    era       <= masked_value;
            CSR_EENTRY: eentry_va <= masked_value[31:6];
            CSR_SAVE0:  save0     <= masked_value;
            CSR_SAVE1:  save1     <= masked_value;
            CSR_SAVE2:  save2     <= masked_value;
            CSR_SAVE3:  save3     <= masked_value;
            default: begin end
        endcase
    end
end

endmodule
